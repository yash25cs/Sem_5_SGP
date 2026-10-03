import {
  loadMaterialSource,
  loadMockSource,
  loadWeakSource,
} from '../_shared/material.ts';
import { writeQuiz } from '../_shared/quiz.ts';
import {
  adminClient,
  HttpError,
  json,
  readJson,
  requireUser,
  serve,
} from '../_shared/supa.ts';

/// Writes a multiple-choice quiz from one material the student picked, or from
/// the units they keep getting wrong.
///
/// Body: `{ materialId: string, length?: 5 | 10 | 15 }`, or
/// `{ weak: true, length? }` to draw from `get_weak_topics` instead, or
/// `{ mock: true, length? }` for a mock exam weighted toward the units past
/// papers ask about most. The caller is taken from the JWT, never from the
/// body — see `requireUser`.
///
/// Every question records the excerpt it was written from and that excerpt's
/// unit, which is what lets `get_weak_topics` rank units by quiz misses.
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

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const weak = body.weak === true;
  const mock = body.mock === true;
  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  if (!weak && !mock && materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }
  // A mock exam defaults to the long form; practice quizzes to the middle.
  const wanted = mock && body.length === undefined ? 15 : pickLength(body.length);

  const weakSource = weak ? await loadWeakSource(supa) : null;
  const mockSource = mock ? await loadMockSource(supa) : null;
  const source = weakSource ?? mockSource ??
    await loadMaterialSource(supa, materialId);
  const quizMaterialId = weakSource
    ? weakSource.materialId
    : mockSource
    ? null
    : materialId;
  // Real past questions steer the new ones toward what this exam actually asks.
  const styleGuide = mockSource && mockSource.examples.length > 0
    ? 'Past exam questions on these topics, for style and emphasis only — '
      + 'write new multiple-choice questions, do not copy these:\n'
      + mockSource.examples.map((e) => `- ${e}`).join('\n') + '\n\n'
    : '';
  const written = await writeQuiz({
    sourceTitle: source.title,
    chunks: source.chunks,
    wanted,
    styleGuide,
  });
  const questions = written.questions;
  // Weak-spots and mock quizzes are named for what they are, not by the model.
  const title = weakSource || mockSource
    ? source.title
    : quizTitle(written.modelTitle, source.title);

  if (questions.length < MIN_QUESTIONS) {
    console.error(
      `Only ${questions.length} of ${written.offered} questions were `
        + `usable for ${
          weak ? 'weak spots' : mock ? 'a mock exam' : `material ${materialId}`
        }`,
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
      title,
      length: questions.length,
      material_id: quizMaterialId,
      // Exam conditions: a little longer per question than practice.
      ...(mock ? { timer_sec: 45 } : {}),
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
      unit_label: q.unitLabel,
      source_chunk_id: q.sourceChunkId,
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
    title,
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

/// The model's title when it wrote one, the file's name otherwise.
function quizTitle(modelTitle: string | null, materialTitle: string): string {
  const title = (modelTitle ?? '').trim();
  return (title.length > 0 ? title : `${materialTitle} quiz`).slice(0, 120);
}
