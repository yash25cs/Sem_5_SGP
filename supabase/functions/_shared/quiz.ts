import { interact, parseJsonObject } from './gemini.ts';
import { type Chunk, numberedSource, sampleChunks } from './material.ts';

/// Writing multiple-choice questions from a student's material — shared by
/// `generate-quiz` (a student's own quiz) and `room-quiz` (one quiz a whole
/// study room takes together).

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
          source: { type: 'integer' },
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
- source is the number of the excerpt the question tests.
- title is a short name for the quiz, like "Unit 3 — Normalisation".`;

export interface Question {
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string | null;
  unitLabel: string | null;
  sourceChunkId: string | null;
}

export interface WrittenQuiz {
  /// The model's own title, when it gave one.
  modelTitle: string | null;
  /// Validated questions, at most `wanted`.
  questions: Question[];
  /// How many the model returned before validation, for the logs.
  offered: number;
}

/// One model call: [wanted] questions from [chunks], validated per question.
export async function writeQuiz(opts: {
  sourceTitle: string;
  chunks: Chunk[];
  wanted: number;
  /// Extra guidance placed before the excerpts (a mock exam's past questions).
  styleGuide?: string;
}): Promise<WrittenQuiz> {
  // Trim the material further for quiz generation — shorter prompts respond
  // faster and stay well inside the model's comfort zone.
  const trimmedChunks = sampleChunks(sampleChunks(opts.chunks), 40_000);

  const raw = await interact({
    systemInstruction: QUIZ_INSTRUCTION,
    // Some invention is the point here — the three wrong options have to be
    // written, not copied. Low enough that the right one stays faithful.
    temperature: 0.4,
    schema: QUIZ_SCHEMA,
    input: `Material: ${opts.sourceTitle}\n\n`
      + (opts.styleGuide ?? '')
      + `Write exactly ${opts.wanted} questions from these excerpts.\n\n`
      + `${numberedSource(trimmedChunks)}`,
    maxOutputTokens: TOKENS_BASE + opts.wanted * TOKENS_PER_QUESTION,
    // 120 s total budget, 55 s per attempt — gives the retry loop room for
    // a second try on a transient 503 or timeout, well inside the client's
    // 180 s function budget (D-018).
    budgetMs: 120_000,
    attemptMs: 55_000,
  });

  const parsed = parseQuiz(raw);
  return {
    modelTitle: parsed.title,
    questions: keepValid(parsed.questions, trimmedChunks).slice(0, opts.wanted),
    offered: parsed.questions.length,
  };
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
function keepValid(items: any[], chunks: Chunk[]): Question[] {
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
    // 1-based in the prompt. A number that points nowhere just leaves the
    // question without a unit — it still counts for XP, not for weak spots.
    const index = Number(item?.source) - 1;
    const chunk = Number.isInteger(index) && index >= 0 && index < chunks.length
      ? chunks[index]
      : null;
    kept.push({
      question,
      options,
      correctIndex,
      explanation: explanation.length > 0 ? explanation : null,
      unitLabel: chunk?.unitLabel ?? null,
      sourceChunkId: chunk?.id ?? null,
    });
  }

  return kept;
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}
