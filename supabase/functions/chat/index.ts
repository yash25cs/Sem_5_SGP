import {
  embedTexts,
  interact,
  queryText,
} from '../_shared/gemini.ts';
import { languageOf, languageRule } from '../_shared/language.ts';
import {
  adminClient,
  HttpError,
  json,
  readJson,
  requireUser,
  serve,
} from '../_shared/supa.ts';

/// Answers a student's question from their own uploaded materials.
///
/// Body: `{ threadId: string, question: string, subjectId?: string }`.
///
/// Both turns are written here rather than on the client: one round trip, and
/// the question and the answer can't end up interleaved with another send.
///
/// They are written with the service-role key, because `0020_hardening.sql`
/// revokes insert and update on `chat_messages` and `chat_citations` — a client
/// that could write its own turns could forge "AI" answers and farm the
/// curious_learner badge. Everything is still read as the caller, the thread is
/// checked to be theirs first, and every `user_id` comes from the JWT.

/// Excerpts fed to the model. Six is `match_material_chunks`' own default and
/// fits comfortably in one prompt alongside the recent transcript.
const MATCH_COUNT = 6;

/// Turns of history sent for continuity — enough for "explain that again"
/// to mean something, short enough not to crowd out the excerpts.
const HISTORY_TURNS = 8;

/// How much of each excerpt goes into the prompt.
const EXCERPT_CHARS = 1500;

const MAX_QUESTION_CHARS = 2000;

const TUTOR_INSTRUCTION = `You are StudyTrail's study tutor. You are helping one \
student revise from the material they uploaded themselves.

How to answer:
- Answer from the numbered excerpts below. They are that student's own notes and \
syllabus, so prefer their wording and their notation.
- Cite the excerpt you used inline, like [1] or [2][3]. Cite only excerpts you \
actually relied on.
- When the excerpts don't cover the question, say so in one plain sentence, then \
answer from general knowledge and mark that part "(not from your materials)".
- When there are no excerpts at all, say that nothing they've uploaded covers it \
and suggest uploading the relevant notes. Do not invent a citation.
- Be direct and concrete. Explain, don't pad. Short paragraphs, and a list only \
when the content is genuinely a list.
- No headings, no bold, no preamble like "Great question". Just the answer, as a \
tutor would say it out loud.
- After the answer, add one final line starting with "FOLLOW-UPS:" and three \
short questions the student could ask next about this material, separated by \
" | ". Nothing after that line.`;

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const threadId = typeof body.threadId === 'string' ? body.threadId.trim() : '';
  const question = typeof body.question === 'string' ? body.question.trim() : '';
  const subjectId = typeof body.subjectId === 'string' && body.subjectId.length > 0
    ? body.subjectId
    : null;

  if (threadId.length === 0 || question.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }
  if (question.length > MAX_QUESTION_CHARS) {
    throw new HttpError(400, 'That question is too long. Try asking it shorter.');
  }

  // RLS turns "not yours" into "not found", which is the honest answer anyway.
  const { data: thread, error: threadError } = await supa
    .from('chat_threads')
    .select('id')
    .eq('id', threadId)
    .maybeSingle();
  if (threadError) {
    console.error('Could not read thread', threadError);
    throw new HttpError(500, "Couldn't open that conversation. Try again.");
  }
  if (!thread) {
    throw new HttpError(404, "That conversation isn't yours.");
  }

  // History before the insert, so the student's new question isn't in it twice.
  const [{ data: history }, lang] = await Promise.all([
    supa
      .from('chat_messages')
      .select('role, text')
      .eq('thread_id', threadId)
      .order('created_at', { ascending: false })
      .limit(HISTORY_TURNS),
    languageOf(supa, userId),
  ]);

  const admin = adminClient();
  const { error: askError } = await admin.from('chat_messages').insert({
    user_id: userId,
    thread_id: threadId,
    role: 'user',
    text: question,
  });
  if (askError) {
    console.error('Could not save the question', askError);
    throw new HttpError(500, "Couldn't send that message. Try again.");
  }

  const [queryVector] = await embedTexts([queryText(question)]);

  const { data: chunks, error: matchError } = await supa.rpc(
    'match_material_chunks',
    {
      query_embedding: queryVector,
      match_count: MATCH_COUNT,
      filter_subject: subjectId,
    },
  );
  if (matchError) {
    console.error('Retrieval failed', matchError);
    throw new HttpError(500, "Couldn't search your materials. Try again.");
  }

  // deno-lint-ignore no-explicit-any
  const excerpts: any[] = Array.isArray(chunks) ? chunks : [];

  const raw = await interact({
    systemInstruction: TUTOR_INSTRUCTION + languageRule(lang),
    temperature: 0.3,
    input: buildPrompt(question, excerpts, history ?? []),
    // A tutor's reply, not an essay. Generous enough for a worked example.
    // Hindi and Gujarati script take roughly twice the tokens for the same text.
    maxOutputTokens: lang === 'en' ? 2048 : 4096,
    // The student is watching a typing indicator while this runs, so it fails
    // fast rather than sitting there until the worker is killed.
    budgetMs: 30_000,
  });
  // The follow-ups ride on the same call rather than costing a second one;
  // only the answer itself is stored.
  const { answer, suggestions } = splitFollowUps(raw);

  const { data: reply, error: replyError } = await admin
    .from('chat_messages')
    .insert({
      user_id: userId,
      thread_id: threadId,
      role: 'ai',
      text: answer,
    })
    .select('id')
    .single();
  if (replyError || !reply) {
    console.error('Could not save the answer', replyError);
    // The answer exists but has nowhere to live, and the client reloads from the
    // table — so admitting the failure beats returning text that vanishes.
    throw new HttpError(500, "Couldn't save that answer. Ask again.");
  }

  const cited = citedExcerpts(answer, excerpts);
  if (cited.length > 0) {
    const { error: citeError } = await admin.from('chat_citations').insert(
      cited.map((chunk) => ({
        user_id: userId,
        message_id: reply.id,
        chunk_id: chunk.id,
        unit_label: chunk.unit_label ?? null,
      })),
    );
    // A missing chip is a cosmetic loss next to a lost answer, so this doesn't
    // fail the request.
    if (citeError) console.error('Could not save citations', citeError);
  }

  return json({
    answer,
    messageId: reply.id,
    suggestions,
    citations: cited.map((chunk) => ({
      chunkId: chunk.id,
      materialId: chunk.material_id ?? null,
      unitLabel: chunk.unit_label ?? null,
    })),
  });
});

/// Separates the answer from the trailing `FOLLOW-UPS:` line the tutor is asked
/// to add. A reply without one is all answer and no suggestions — the chips
/// are a convenience, never a reason to fail.
function splitFollowUps(raw: string): { answer: string; suggestions: string[] } {
  const match = raw.match(/(?:^|\n)[ \t*_]*FOLLOW-?UPS?[*_]*:\s*([\s\S]*)$/i);
  if (!match || match.index === undefined) {
    return { answer: raw.trim(), suggestions: [] };
  }
  const answer = raw.slice(0, match.index).trim();
  const suggestions = match[1]
    .split(/\||\n/)
    .map((s) => s.trim().replace(/^[-*•\d.)\s]+/, '').trim())
    .filter((s) => s.length >= 4 && s.length <= 140)
    .slice(0, 3);
  return { answer: answer.length > 0 ? answer : raw.trim(), suggestions };
}

/// Assembles the single text input: recent turns, then numbered excerpts, then
/// the question.
function buildPrompt(
  question: string,
  // deno-lint-ignore no-explicit-any
  excerpts: any[],
  // deno-lint-ignore no-explicit-any
  history: any[],
): string {
  const parts: string[] = [];

  if (history.length > 0) {
    // `history` came back newest-first for the limit; the model reads it in the
    // order it was said.
    const lines = [...history]
      .reverse()
      .map((m) =>
        `${m.role === 'ai' ? 'Tutor' : 'Student'}: ${
          String(m.text ?? '').slice(0, 600)
        }`
      );
    parts.push(`Earlier in this conversation:\n${lines.join('\n')}`);
  }

  if (excerpts.length === 0) {
    parts.push(
      "Excerpts from the student's materials: none — they have not uploaded "
        + 'anything that covers this yet.',
    );
  } else {
    const blocks = excerpts.map((chunk, index) => {
      const label = typeof chunk?.unit_label === 'string' && chunk.unit_label.trim()
        ? chunk.unit_label.trim()
        : 'Untitled section';
      const content = String(chunk?.content ?? '').slice(0, EXCERPT_CHARS);
      return `[${index + 1}] ${label}\n${content}`;
    });
    parts.push(
      `Excerpts from the student's materials, most relevant first:\n\n${
        blocks.join('\n\n')
      }`,
    );
  }

  parts.push(`The student asks: ${question}`);
  return parts.join('\n\n---\n\n');
}

/// The excerpts the answer actually referenced.
///
/// Falls back to the top three retrieved when the answer cited nothing: the
/// chips are there to show *where this came from*, and a grounded answer that
/// forgot its brackets still came from somewhere. Returns nothing when nothing
/// was retrieved — no excerpts means no source to name.
// deno-lint-ignore no-explicit-any
function citedExcerpts(answer: string, excerpts: any[]): any[] {
  if (excerpts.length === 0) return [];

  const seen = new Set<number>();
  for (const match of answer.matchAll(/\[(\d{1,2})\]/g)) {
    const index = Number(match[1]) - 1;
    if (index >= 0 && index < excerpts.length) seen.add(index);
  }

  const picked = seen.size > 0
    ? [...seen].sort((a, b) => a - b).map((i) => excerpts[i])
    : excerpts.slice(0, 3);

  // Two chunks of the same unit would render as two identical chips.
  const byId = new Map<string, unknown>();
  for (const chunk of picked) {
    if (chunk?.id) byId.set(String(chunk.id), chunk);
  }
  return [...byId.values()];
}
