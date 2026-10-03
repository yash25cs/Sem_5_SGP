import { interact, parseJsonObject } from '../_shared/gemini.ts';
import {
  type Chunk,
  loadMaterialSource,
  loadWeakSource,
  numberedSource,
  sampleChunks,
} from '../_shared/material.ts';
import { HttpError, json, readJson, requireUser, serve } from '../_shared/supa.ts';

/// Writes flashcards from one material the student picked, or from one chat
/// answer.
///
/// Body: `{ materialId: string, count?: 10 | 20 | 30 }` for a new deck from a
/// file, or `{ messageId: string }` to save a few cards from a Trail AI answer
/// into the student's "Saved from chat" deck, or `{ weak: true, count? }` for a
/// deck drawn from the units they keep getting wrong. The caller is taken from
/// the JWT, never from the body — see `requireUser`.
///
/// No `adminClient()` here, unlike the other two generators: `0008_rewards.sql`
/// grants `insert (user_id, deck_id, unit_label, front, back, source_chunk_id)
/// on flashcards` and leaves `flashcard_decks` open, because a card is content
/// the student could equally have typed — the SM-2 columns that *are*
/// XP-bearing stay behind `apply_sr_grade`. So this function acts as the caller
/// and RLS enforces ownership, exactly like `chat`.

const COUNTS = [10, 20, 30];
const DEFAULT_COUNT = 20;

/// Below this the deck isn't worth a review session.
const MIN_CARDS = 4;

/// Output budget. A card is a question and a short answer — call it 90 tokens
/// with its JSON wrapper.
const TOKENS_PER_CARD = 110;
const TOKENS_BASE = 700;

/// Ceilings on what goes in a card. No database constraint forces these; a card
/// is read on a phone-sized face, and a model that starts writing paragraphs
/// should have them cut rather than have the card dropped.
const MAX_FRONT_CHARS = 240;
const MAX_BACK_CHARS = 700;

/// Chat mode: a handful of cards from one answer, all into one deck, so saving
/// from chat a dozen times doesn't leave a dozen tiny decks.
const CHAT_CARDS = 5;
const CHAT_MIN_CARDS = 2;
const CHAT_DECK_NAME = 'Saved from chat';

const CARD_SCHEMA = {
  type: 'object',
  properties: {
    deck_name: { type: 'string' },
    cards: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          front: { type: 'string' },
          back: { type: 'string' },
          unit_label: { type: 'string' },
          source: { type: 'integer' },
        },
        required: ['front', 'back'],
      },
    },
  },
  required: ['cards'],
};

const CARD_INSTRUCTION = `You write revision flashcards from a student's own \
study material.

Rules:
- front is one question, term or prompt. back is the answer, in one or two \
sentences at most. Both come from the excerpts; invent nothing.
- One idea per card. Split a definition with three parts into three cards \
rather than listing them on one back.
- Ask the thing worth remembering: definitions, distinctions between similar \
terms, formulas and what their symbols mean, the steps of a process, why a \
result holds. Skip page furniture, figure captions and anything only true of \
this document's layout.
- Cards must stand alone. No "according to the text", no "see above", no \
reference to excerpt numbers.
- Do not repeat a card. If two excerpts cover the same term, write one card.
- unit_label is the heading the card came from, copied from the excerpt it was \
drawn from. source is that excerpt's number.
- deck_name is a short name for the deck, like "Unit 3 — Normalisation".`;

interface Card {
  front: string;
  back: string;
  unitLabel: string | null;
  sourceChunkId: string | null;
}

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const messageId = typeof body.messageId === 'string'
    ? body.messageId.trim()
    : '';
  if (messageId.length > 0) {
    return await cardsFromChat(supa, userId, messageId);
  }

  const weak = body.weak === true;
  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  if (!weak && materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }
  // Weak-spot decks default to the smallest size: a few units, reviewed soon.
  const wanted = weak && body.count === undefined ? 10 : pickCount(body.count);

  const source = weak
    ? await loadWeakSource(supa)
    : await loadMaterialSource(supa, materialId);
  const chunks = sampleChunks(source.chunks);

  const raw = await interact({
    systemInstruction: CARD_INSTRUCTION,
    // Lower than the quiz's 0.4: there are no distractors to invent here, and a
    // card that drifts from the material is a card that teaches the wrong thing.
    temperature: 0.2,
    schema: CARD_SCHEMA,
    input: `Material: ${source.title}\n\n`
      + `Write exactly ${wanted} flashcards from these excerpts, spread across `
      + `all of them.\n\n${numberedSource(chunks)}`,
    maxOutputTokens: TOKENS_BASE + wanted * TOKENS_PER_CARD,
    budgetMs: 60_000,
  });

  const parsed = parseJsonObject(raw);
  // deno-lint-ignore no-explicit-any
  const items: any[] = Array.isArray(parsed?.cards) ? parsed.cards : [];
  const cards = keepValid(items, chunks).slice(0, wanted);

  if (cards.length < MIN_CARDS) {
    console.error(
      `Only ${cards.length} of ${items.length} cards were usable for `
        + (weak ? 'weak spots' : `material ${materialId}`),
    );
    throw new HttpError(
      502,
      "The AI couldn't make cards from that file. Try a different one.",
    );
  }

  // `subject_id` stays null for the same reason as in `generate-quiz`: nothing
  // associates a material with a subject yet.
  const name = weak
    ? source.title
    : deckName(parsed?.deck_name, source.title);
  const { data: deck, error: deckError } = await supa
    .from('flashcard_decks')
    .insert({
      user_id: userId,
      name,
    })
    .select('id')
    .single();
  if (deckError || !deck) {
    console.error('Could not create the deck', deckError);
    throw new HttpError(500, "Couldn't save those cards. Try again.");
  }

  // Exactly the columns `0008_rewards.sql` grants — the SM-2 state (`ease`,
  // `interval_days`, `repetitions`, `due_at`) takes its defaults, which is what
  // makes every generated card due immediately.
  const { error: cardError } = await supa.from('flashcards').insert(
    cards.map((card) => ({
      user_id: userId,
      deck_id: deck.id,
      unit_label: card.unitLabel,
      front: card.front,
      back: card.back,
      source_chunk_id: card.sourceChunkId,
    })),
  );
  if (cardError) {
    console.error('Could not save the cards', cardError);
    // An empty deck would sit in the list showing "0 due" forever.
    await supa.from('flashcard_decks').delete().eq('id', deck.id);
    throw new HttpError(500, "Couldn't save those cards. Try again.");
  }

  return json({
    deckId: deck.id,
    cards: cards.length,
    deckName: name,
  });
});

/// Chat mode. Reads the answer, the question it answered, and the excerpts it
/// cited — all through the caller's client, so another student's message id
/// comes back as not found — and saves cards into "Saved from chat".
async function cardsFromChat(
  // deno-lint-ignore no-explicit-any
  supa: any,
  userId: string,
  messageId: string,
): Promise<Response> {
  const { data: message, error: messageError } = await supa
    .from('chat_messages')
    .select('id, thread_id, role, text, created_at')
    .eq('id', messageId)
    .maybeSingle();
  if (messageError) {
    console.error('Could not read chat message', messageError);
    throw new HttpError(500, "Couldn't open that answer. Try again.");
  }
  if (!message || message.role !== 'ai') {
    throw new HttpError(404, "That answer isn't yours.");
  }

  const { data: asked } = await supa
    .from('chat_messages')
    .select('text')
    .eq('thread_id', message.thread_id)
    .eq('role', 'user')
    .lte('created_at', message.created_at)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const { data: citations } = await supa
    .from('chat_citations')
    .select('chunk_id')
    .eq('message_id', messageId);
  const chunkIds = (citations ?? [])
    // deno-lint-ignore no-explicit-any
    .map((c: any) => c.chunk_id)
    .filter((id: unknown): id is string => typeof id === 'string');

  // deno-lint-ignore no-explicit-any
  let cited: any[] = [];
  if (chunkIds.length > 0) {
    const { data } = await supa
      .from('material_chunks')
      .select('id, unit_label, content')
      .in('id', chunkIds);
    cited = data ?? [];
  }

  // The answer is excerpt [1]; a card drawn from it has no chunk to point at,
  // which [keepValid] turns into a null `source_chunk_id`.
  const chunks: Chunk[] = [
    {
      id: '',
      unitLabel: 'Tutor answer',
      content: `Question: ${text(asked?.text)}\n\nAnswer: ${text(message.text)}`,
    },
    ...cited
      .map((row) => ({
        id: String(row.id),
        unitLabel: text(row.unit_label) || null,
        content: text(row.content),
      }))
      .filter((chunk) => chunk.content.length > 0),
  ];

  const raw = await interact({
    systemInstruction: CARD_INSTRUCTION,
    temperature: 0.2,
    schema: CARD_SCHEMA,
    input: `Write exactly ${CHAT_CARDS} flashcards that capture what the tutor `
      + 'answer in excerpt [1] teaches. Use the other excerpts only to get '
      + `details right.\n\n${numberedSource(chunks)}`,
    maxOutputTokens: TOKENS_BASE + CHAT_CARDS * TOKENS_PER_CARD,
    budgetMs: 45_000,
  });

  const parsed = parseJsonObject(raw);
  // deno-lint-ignore no-explicit-any
  const items: any[] = Array.isArray(parsed?.cards) ? parsed.cards : [];
  const cards = keepValid(items, chunks).slice(0, CHAT_CARDS);
  if (cards.length < CHAT_MIN_CARDS) {
    console.error(`Only ${cards.length} cards usable from message ${messageId}`);
    throw new HttpError(
      502,
      "The AI couldn't make cards from that answer. Try a longer one.",
    );
  }

  // RLS scopes this to the caller's own decks.
  const { data: existing } = await supa
    .from('flashcard_decks')
    .select('id')
    .eq('name', CHAT_DECK_NAME)
    .limit(1)
    .maybeSingle();
  let deckId: string | null = existing?.id ?? null;
  const createdDeck = deckId === null;
  if (createdDeck) {
    const { data: deck, error: deckError } = await supa
      .from('flashcard_decks')
      .insert({ user_id: userId, name: CHAT_DECK_NAME })
      .select('id')
      .single();
    if (deckError || !deck) {
      console.error('Could not create the chat deck', deckError);
      throw new HttpError(500, "Couldn't save those cards. Try again.");
    }
    deckId = deck.id;
  }

  const { error: cardError } = await supa.from('flashcards').insert(
    cards.map((card) => ({
      user_id: userId,
      deck_id: deckId,
      unit_label: card.unitLabel,
      front: card.front,
      back: card.back,
      source_chunk_id: card.sourceChunkId,
    })),
  );
  if (cardError) {
    console.error('Could not save chat cards', cardError);
    if (createdDeck) await supa.from('flashcard_decks').delete().eq('id', deckId);
    throw new HttpError(500, "Couldn't save those cards. Try again.");
  }

  return json({ deckId, cards: cards.length, deckName: CHAT_DECK_NAME });
}

/// Clamps the requested count to one of [COUNTS] — see `generate-quiz`'s
/// `pickLength` for why this rounds instead of refusing.
function pickCount(value: unknown): number {
  const asked = typeof value === 'number' && Number.isFinite(value)
    ? Math.round(value)
    : DEFAULT_COUNT;
  return COUNTS.reduce(
    (best, option) =>
      Math.abs(option - asked) < Math.abs(best - asked) ? option : best,
    DEFAULT_COUNT,
  );
}

/// Keeps the cards worth storing, and resolves each one's excerpt number to a
/// real `material_chunks.id`.
///
/// `source_chunk_id` is a foreign key, so a hallucinated number has to become
/// null rather than a failed insert. Duplicate fronts are dropped: the model is
/// told not to repeat itself, and when it does anyway the student would review
/// the same card twice in one session.
// deno-lint-ignore no-explicit-any
function keepValid(items: any[], chunks: Chunk[]): Card[] {
  const kept: Card[] = [];
  const seen = new Set<string>();

  for (const item of items) {
    const front = text(item?.front).slice(0, MAX_FRONT_CHARS);
    const back = text(item?.back).slice(0, MAX_BACK_CHARS);
    if (front.length === 0 || back.length === 0) continue;

    const key = front.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    // 1-based in the prompt, so the model's "3" is `chunks[2]`.
    const index = Number(item?.source) - 1;
    const chunk = Number.isInteger(index) && index >= 0 && index < chunks.length
      ? chunks[index]
      : null;

    const label = text(item?.unit_label);
    kept.push({
      front,
      back,
      unitLabel: label.length > 0 ? label.slice(0, 80) : chunk?.unitLabel ?? null,
      // `||` rather than `??`: chat mode's answer excerpt has an empty id.
      sourceChunkId: chunk?.id || null,
    });
  }

  return kept;
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function deckName(modelName: unknown, materialTitle: string): string {
  const name = text(modelName);
  return (name.length > 0 ? name : `${materialTitle} cards`).slice(0, 120);
}
