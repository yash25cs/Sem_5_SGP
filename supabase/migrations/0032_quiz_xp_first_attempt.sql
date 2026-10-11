-- ============================================================
-- 0032  Quiz XP on the first attempt only; smaller speed-round points.
--
--  1. finish_quiz_attempt paid 10 XP per correct answer on every attempt,
--     so retaking one quiz again and again was unlimited XP. Now only the
--     first finished attempt pays. quizzes.xp_paid_at records it and is
--     never cleared: deleting attempts doesn't reset it, and students can't
--     update quizzes (0008). Retakes are still scored and kept — practice.
--     Quizzes already finished before this count as paid.
--
--  2. Speed rounds scored 500 plus up to 500 for speed per right answer —
--     points that only rank players (podium XP is still 30/20/10), but far
--     out of scale with the rest of the app. Now 10 plus up to 10, in line
--     with a solo quiz's 10 XP an answer.
--
-- Idempotent, like every migration here.
-- ============================================================

-- ── 1. First attempt only ───────────────────────────────────────────────────
alter table quizzes add column if not exists xp_paid_at timestamptz;

update quizzes q
   set xp_paid_at = a.first_done
  from (select quiz_id, min(completed_at) as first_done
          from quiz_attempts
         where completed_at is not null
         group by quiz_id) a
 where q.id = a.quiz_id and q.xp_paid_at is null;

create or replace function public.finish_quiz_attempt(attempt uuid, picks jsonb)
returns quiz_attempts
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user     uuid := auth.uid();
  v_row      quiz_attempts;
  v_score    int := 0;
  v_total    int := 0;
  v_earned   int := 0;
  v_cap      int;
  v_question record;
  v_picked   int;
  v_paid     boolean;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_row
    from quiz_attempts where id = attempt and user_id = v_user;
  if not found then
    raise exception 'attempt % not found', attempt using errcode = 'no_data_found';
  end if;
  if v_row.completed_at is not null then
    return v_row;  -- already scored; don't double-award
  end if;

  -- XP is for the first time through a quiz only. quizzes.xp_paid_at is
  -- set by the first finished attempt and never cleared — deleting attempts
  -- doesn't reset it, and students can't update quizzes (0008) — so a retake
  -- is practice: scored and recorded, worth nothing.
  select xp_paid_at is not null into v_paid
    from quizzes where id = v_row.quiz_id and user_id = v_user
    for update;

  -- xp_reward is a client-writable column, so the rules table caps it. Without
  -- this, inserting a question worth 999999 XP would be a payout of 999999.
  v_cap := app_private.xp_for('quiz_correct');

  for v_question in
    select id, correct_index, xp_reward
      from quiz_questions
      -- Ownership of the parent question set, not just of the attempt.
      where quiz_id = v_row.quiz_id and user_id = v_user
      order by order_index
  loop
    v_total  := v_total + 1;
    v_picked := nullif(picks ->> v_question.id::text, '')::int;

    insert into quiz_answers (user_id, attempt_id, question_id, picked_index,
                              is_correct)
    values (v_user, attempt, v_question.id, v_picked,
            v_picked is not distinct from v_question.correct_index);

    if v_picked is not distinct from v_question.correct_index then
      v_score  := v_score + 1;
      if not coalesce(v_paid, false) then
        v_earned := v_earned + least(greatest(coalesce(v_question.xp_reward, 0), 0), v_cap);
      end if;
    end if;
  end loop;

  update quiz_attempts
    set score = v_score, total = v_total, xp_earned = v_earned,
        completed_at = now()
    where id = attempt
    returning * into v_row;

  update quizzes set xp_paid_at = now()
   where id = v_row.quiz_id and xp_paid_at is null;

  perform app_private.award_xp(v_user, v_earned);
  perform app_private.log_activity(v_user, 0, 0, v_earned);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- ── 2. Speed-round points ───────────────────────────────────────────────────
-- One answer in a speed round, inside that question's window (with 1.5 s of
-- grace for the trip from the phone), changeable until the window closes
-- (0031). Points: 0 when wrong; when right, 10 plus up to 10 for speed.
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
    then 10 + floor(10 * greatest(0, 1 - least(v_in, v_quiz.seconds_per_question)
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
