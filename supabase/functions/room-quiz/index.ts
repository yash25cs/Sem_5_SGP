import { loadMaterialSource } from '../_shared/material.ts';
import { writeQuiz } from '../_shared/quiz.ts';
import {
  adminClient,
  HttpError,
  json,
  readJson,
  requireUser,
  serve,
} from '../_shared/supa.ts';

/// Proposes a group quiz in a study room.
///
/// Body: `{ roomId, materialId, count: 5 | 10 | 15, mode?: 'standard' | 'speed',
/// seconds?: 10 | 20 | 30 }`. A speed round shows everyone the same question at
/// the same moment for `seconds` (`0022_speed_quiz.sql`). Only the room's host
/// may propose, from one of their own ready materials. The questions are
/// written now, so the quiz can start the moment everyone agrees; voting,
/// answering, scoring and XP are all database functions (`0019_room_quiz.sql`).
///
/// Reads and ownership checks go through the caller's client. The inserts use
/// the service-role key because the quiz tables have no client grants at all —
/// that is what keeps the correct answers out of every client until the quiz
/// is over.

const COUNTS = [5, 10, 15];
const SPEED_SECONDS = [10, 20, 30];
const MIN_QUESTIONS = 3;

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const roomId = typeof body.roomId === 'string' ? body.roomId.trim() : '';
  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  if (roomId.length === 0 || materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }
  const wanted = COUNTS.includes(Number(body.count)) ? Number(body.count) : 10;
  const speed = body.mode === 'speed';
  const seconds = SPEED_SECONDS.includes(Number(body.seconds))
    ? Number(body.seconds)
    : 20;

  const { data: room } = await supa
    .from('study_rooms')
    .select('id, created_by, status')
    .eq('id', roomId)
    .maybeSingle();
  if (!room || room.status !== 'active') {
    throw new HttpError(404, 'That room has closed.');
  }
  if (room.created_by !== userId) {
    throw new HttpError(403, 'Only the host can start a group quiz.');
  }

  // Everyone in the room right now takes part — and has to agree first.
  const { data: members, error: membersError } = await supa.rpc(
    'get_room_members',
    { p_room_id: roomId },
  );
  if (membersError) {
    console.error('Could not read members', membersError);
    throw new HttpError(500, "Couldn't read who's in the room. Try again.");
  }
  // deno-lint-ignore no-explicit-any
  const players: string[] = (members ?? []).map((m: any) => String(m.user_id));
  if (players.length < 2) {
    throw new HttpError(
      400,
      'A group quiz needs at least two people in the room.',
    );
  }

  const admin = adminClient();
  const { data: open } = await admin
    .from('room_quizzes')
    .select('id')
    .eq('room_id', roomId)
    .in('status', ['voting', 'running'])
    .limit(1);
  if ((open ?? []).length > 0) {
    throw new HttpError(409, 'There is already a quiz going in this room.');
  }

  // The caller's client: a material that isn't the host's is "not found".
  const source = await loadMaterialSource(supa, materialId);
  const written = await writeQuiz({
    sourceTitle: source.title,
    chunks: source.chunks,
    wanted,
  });
  if (written.questions.length < MIN_QUESTIONS) {
    console.error(
      `Only ${written.questions.length} of ${written.offered} usable for room ${roomId}`,
    );
    throw new HttpError(
      502,
      "The AI couldn't make a quiz from that file. Try a different one.",
    );
  }

  const title = (written.modelTitle?.trim() || `${source.title} quiz`).slice(0, 120);
  const { data: quiz, error: quizError } = await admin
    .from('room_quizzes')
    .insert({
      room_id: roomId,
      created_by: userId,
      title,
      question_count: written.questions.length,
      mode: speed ? 'speed' : 'standard',
      seconds_per_question: speed ? seconds : null,
    })
    .select('id')
    .single();
  if (quizError || !quiz) {
    // The partial unique index is the race guard: two proposals at once.
    if (quizError?.code === '23505') {
      throw new HttpError(409, 'There is already a quiz going in this room.');
    }
    console.error('Could not save the room quiz', quizError);
    throw new HttpError(500, "Couldn't start the quiz. Try again.");
  }

  const { error: questionError } = await admin.from('room_quiz_questions').insert(
    written.questions.map((q, i) => ({
      room_quiz_id: quiz.id,
      order_index: i,
      question: q.question,
      options: q.options,
      correct_index: q.correctIndex,
      explanation: q.explanation,
    })),
  );
  const { error: playerError } = questionError ? { error: null } : await admin
    .from('room_quiz_players')
    .insert(players.map((id) => ({
      room_quiz_id: quiz.id,
      user_id: id,
      // Proposing is agreeing.
      vote: id === userId ? true : null,
    })));
  if (questionError || playerError) {
    console.error('Could not save the quiz', questionError ?? playerError);
    await admin.from('room_quizzes').delete().eq('id', quiz.id);
    throw new HttpError(500, "Couldn't start the quiz. Try again.");
  }

  return json({ quizId: quiz.id, questions: written.questions.length, title });
});
