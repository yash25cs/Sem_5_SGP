-- ============================================================
-- 0031  Speed rounds: an answer can be changed while its timer runs.
--
--  answer_room_quiz_question used to refuse a second answer ("You've
--  already answered that one."), so a mis-tap was final with seconds still
--  on the clock. Now a new pick inside the window replaces the old one;
--  points are worked out from the answer that stands, at the moment it was
--  given. Because answers can change until time is up, the round no longer
--  finishes the moment everyone has answered the last question — it ends
--  on the clock, through tick_room_quiz, like every other question.
--
-- Idempotent, like every migration here.
-- ============================================================

-- One answer in a speed round, inside that question's window (with 1.5 s of
-- grace for the trip from the phone), changeable until the window closes.
-- Points: 0 when wrong; when right, 500 plus up to 500 for speed.
create or replace function public.answer_room_quiz_question(
  p_quiz uuid, p_question uuid, p_pick int
)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid    uuid := auth.uid();
  v_quiz   room_quizzes;
  v_q      room_quiz_questions;
  v_cur    int;
  v_in     numeric;
  v_points int;
begin
  select * into v_quiz from room_quizzes where id = p_quiz for update;
  if not found or v_quiz.mode <> 'speed' then
    raise exception 'That isn''t a speed round.';
  end if;
  if v_quiz.status <> 'running' then
    raise exception 'That quiz has already ended.';
  end if;
  if not exists (select 1 from room_quiz_players
                  where room_quiz_id = p_quiz and user_id = v_uid) then
    raise exception 'You weren''t in the room when this quiz was proposed.';
  end if;
  if p_pick is null or p_pick not between 0 and 3 then
    raise exception 'Pick one of the four options.';
  end if;
  select * into v_q from room_quiz_questions
   where id = p_question and room_quiz_id = p_quiz;
  if not found then
    raise exception 'That question isn''t in this quiz.';
  end if;

  select c.cur, c.in_slot into v_cur, v_in
    from app_private.speed_clock(v_quiz.started_at, v_quiz.seconds_per_question) c;
  if v_q.order_index <> v_cur or v_in > v_quiz.seconds_per_question + 1.5 then
    raise exception 'Time''s up for that question.';
  end if;

  v_points := case when p_pick = v_q.correct_index
    then 500 + floor(500 * greatest(0, 1 - least(v_in, v_quiz.seconds_per_question)
                                         / v_quiz.seconds_per_question))::int
    else 0 end;
  -- A second tap inside the window replaces the first. Points follow the
  -- answer that stands, timed from when it was given, so a change costs speed
  -- points but never more than answering late would.
  insert into room_quiz_answers (room_quiz_id, question_id, user_id, pick, points)
  values (p_quiz, p_question, v_uid, p_pick, v_points)
  on conflict (room_quiz_id, question_id, user_id) do update
    set pick = excluded.pick,
        points = excluded.points,
        answered_at = now();

  -- The round no longer ends early when everyone has answered the last
  -- question: someone may still change their answer. tick_room_quiz closes it
  -- once the clock runs out.

  return public.get_room_quiz(p_quiz);
end $$;

notify pgrst, 'reload schema';
