import { interact, parseJsonObject } from '../_shared/gemini.ts';
import {
  loadMaterialSource,
  numberedSource,
  sampleChunks,
} from '../_shared/material.ts';
import {
  adminClient,
  HttpError,
  json,
  readJson,
  requireUser,
  serve,
} from '../_shared/supa.ts';

/// Writes a multiple-choice quiz from one material the student picked.
///
/// Body: `{ materialId: string, length?: 5 | 10 | 15 }`. The caller is taken
/// from the JWT, never from the body — see `requireUser`.
///
/// Two clients, deliberately. Reads and the ownership check go through the
/// caller's own token so RLS decides what is theirs; only the two inserts use
/// `adminClient()`, because `0008_rewards.sql` revokes `insert on quizzes,
/// quiz_questions` from `authenticated` (a self-authored quiz with known answers
/// is 10 XP a question). `user_id` on both rows still comes from the JWT.

const LENGTHS = [5, 10, 15];
const DEFAULT_LENGTH = 10;

/// Below this the quiz isn't worth saving — see `keepValid`, which drops
/// individual malformed questions rather than failing the whole batch.
const MIN_QUESTIONS = 3;

/// Output budget. A question with four options and an explanation runs about
/// 200 tokens; the rest is JSON scaffolding and headroom.
const TOKENS_PER_QUESTION = 320;
const TOKENS_BASE = 900;

const QUIZ_SCHEMA = {
  type: 'object',
  properties: {
    title: { type: 'string' },
    questions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          correct_index: { type: 'integer' },
          explanation: { type: 'string' },
        },
        required: ['question', 'options', 'correct_index'],
      },
    },
  },
  required: ['questions'],
};

const QUIZ_INSTRUCTION = `You write exam-style multiple-choice questions from a \
student's own study material.

Rules:
- Every question must be answerable from the excerpts alone. Do not test \
anything the excerpts don't state.
- Exactly four options per question. One is correct; the other three are wrong \
but plausible — a misremembered definition, a swapped term, a near-miss number. \
Never "all of the above" or "none of the above".
- correct_index is the 0-based position of the correct option. Vary it; do not \
put the answer first every time.
- explanation is one or two sentences saying why the answer is right, in the \
material's own terms.
- Spread the questions across the excerpts you were given, not just the first \
few. Prefer definitions, distinctions, causes and worked steps over trivia like \
a page number or a figure caption.
- Questions must stand alone. No "according to the text" or "in excerpt [2]".
- title is a short name for the quiz, like "Unit 3 — Normalisation".`;

interface Question {
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string | null;
}

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  if (materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }
  const wanted = pickLength(body.length);

  const source = await loadMaterialSource(supa, materialId);
  const chunks = sampleChunks(source.chunks);

  const raw = await interact({
    systemInstruction: QUIZ_INSTRUCTION,
    // Some invention is the point here — the three wrong options have to be
    // written, not copied. Low enough that the right one stays faithful.
    temperature: 0.4,
    schema: QUIZ_SCHEMA,
    input: `Material: ${source.title}\n\n`
      + `Write exactly ${wanted} questions from these excerpts.\n\n`
      + `${numberedSource(chunks)}`,
    maxOutputTokens: TOKENS_BASE + wanted * TOKENS_PER_QUESTION,
    // Longer than chat's 30 s because the whole quiz is written in one call, and
    // still well inside the client's 180 s function budget (D-018).
    budgetMs: 60_000,
  });

  const parsed = parseQuiz(raw);
  const questions = keepValid(parsed.questions).slice(0, wanted);

  if (questions.length < MIN_QUESTIONS) {
    console.error(
      `Only ${questions.length} of ${parsed.questions.length} questions were `
        + `usable for material ${materialId}`,
    );
    throw new HttpError(
      502,
      "The AI couldn't make a quiz from that file. Try a different one.",
    );
  }

  const admin = adminClient();

  // `subject_id` stays null: nothing associates a material with a subject yet
  // (`embed-material` writes null on every chunk for the same reason), and
  // guessing one would mis-attribute the subject progress that hangs off it.
  const { data: quiz, error: quizError } = await admin
    .from('quizzes')
    .insert({
      user_id: userId,
      title: quizTitle(parsed.title, source.title),
      length: questions.length,
    })
    .select('id')
    .single();
  if (quizError || !quiz) {
    console.error('Could not save the quiz', quizError);
    throw new HttpError(500, "Couldn't save that quiz. Try again.");
  }

  const { error: questionError } = await admin.from('quiz_questions').insert(
    questions.map((q, index) => ({
      user_id: userId,
      quiz_id: quiz.id,
      question: q.question,
      options: q.options,
      correct_index: q.correctIndex,
      explanation: q.explanation,
      order_index: index,
      // `xp_reward` keeps its default 10 — the client reads it, so a generator
      // setting it would be the same self-certification the revokes prevent.
    })),
  );
  if (questionError) {
    console.error('Could not save the questions', questionError);
    // A quiz row with no questions would list in the picker and then open
    // empty, so it goes with them.
    await admin.from('quizzes').delete().eq('id', quiz.id);
    throw new HttpError(500, "Couldn't save that quiz. Try again.");
  }

  return json({
    quizId: quiz.id,
    questions: questions.length,
    title: quizTitle(parsed.title, source.title),
  });
});

/// Clamps the requested length to one of [LENGTHS].
///
/// The picker only offers those three, so anything else is a hand-built request:
/// it is rounded to the nearest offered length rather than refused, because the
/// cost of a wrong number here is a quiz of a slightly different size.
function pickLength(value: unknown): number {
  const asked = typeof value === 'number' && Number.isFinite(value)
    ? Math.round(value)
    : DEFAULT_LENGTH;
  return LENGTHS.reduce(
    (best, option) =>
      Math.abs(option - asked) < Math.abs(best - asked) ? option : best,
    DEFAULT_LENGTH,
  );
}

interface ParsedQuiz {
  title: string | null;
  // deno-lint-ignore no-explicit-any
  questions: any[];
}

function parseQuiz(raw: string): ParsedQuiz {
  // `interact` was given a schema, so this should be plain JSON —
  // `parseJsonObject` covers the case where it arrives fenced anyway, and turns
  // an unreadable answer into a 502 the student can act on.
  const parsed = parseJsonObject(raw);
  return {
    title: typeof parsed.title === 'string' ? parsed.title : null,
    questions: Array.isArray(parsed.questions) ? parsed.questions : [],
  };
}

/// Keeps the questions Postgres will actually accept.
///
/// `quiz_questions` has `check (array_length(options,1) = 4)` and `check
/// (correct_index between 0 and 3)`, and a batch insert is one statement — so a
/// single malformed question would take the other fourteen with it. Dropping it
/// here costs one question; not dropping it costs the quiz.
// deno-lint-ignore no-explicit-any
function keepValid(items: any[]): Question[] {
  const kept: Question[] = [];

  for (const item of items) {
    const question = text(item?.question);
    const options = Array.isArray(item?.options)
      ? item.options.map(text).filter((o: string) => o.length > 0)
      : [];
    const correctIndex = Number(item?.correct_index);

    if (question.length === 0 || options.length !== 4) continue;
    if (!Number.isInteger(correctIndex)) continue;
    if (correctIndex < 0 || correctIndex > 3) continue;
    // Two identical options mean one of them is silently also correct.
    if (new Set(options).size !== 4) continue;

    const explanation = text(item?.explanation);
    kept.push({
      question,
      options,
      correctIndex,
      explanation: explanation.length > 0 ? explanation : null,
    });
  }

  return kept;
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/// The model's title when it wrote one, the file's name otherwise.
function quizTitle(modelTitle: string | null, materialTitle: string): string {
  const title = (modelTitle ?? '').trim();
  return (title.length > 0 ? title : `${materialTitle} quiz`).slice(0, 120);
}
