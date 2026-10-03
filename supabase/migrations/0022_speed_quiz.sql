-- StudyTrail — 0022: speed rounds
--
-- A second kind of group quiz. Everyone sees the same question at the same
-- moment, has `seconds_per_question` to answer, and a right answer is worth
-- 500 points plus up to 500 more for speed. After each question there's a
-- short reveal: the right option and the live scores. The clock, not the
-- players, runs the round:
--
--   5 s "get ready" lead, then for question i:
--     [lead + i·slot, lead + i·slot + T)   answering   (T = seconds_per_question)
--     [lead + i·slot + T, lead + (i+1)·slot) reveal    (slot = T + 4 s)
--
-- Answers live in room_quiz_answers, which — like every room_quiz table — no
-- client can read. A question's right option, and the points scored on it,
-- are only returned once its answering window has closed (D-031).
--
-- Idempotent, like every migration here.

alter table room_quizzes
  add column if not exists mode text not null default 'standard',
  add column if not exists seconds_per_question int;
do $$ begin
  alter table room_quizzes add constraint room_quizzes_mode_check
    check (mode in ('standard', 'speed'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table room_quizzes add constraint room_quizzes_speed_seconds_check
    check ((mode = 'speed') = (seconds_per_question is not null)
           and (seconds_per_question is null
                or seconds_per_question between 10 and 60));
exception when duplicate_object then null; end $$;

create table if not exists room_quiz_answers (
  room_quiz_id uuid        not null references room_quizzes(id) on delete cascade,
  question_id  uuid        not null references room_quiz_questions(id) on delete cascade,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  pick         int         not null check (pick between 0 and 3),
  answered_at  timestamptz not null default now(),
  points       int         not null default 0,
  primary key (room_quiz_id, question_id, user_id)
);
alter table room_quiz_answers enable row level security;
revoke all on room_quiz_answers from anon, authenticated;

-- Where the round is now: `cur` is the question index (-1 during the lead),
-- `in_slot` the seconds into that question's slot.
create or replace function app_private.speed_clock(
  p_started timestamptz, p_secs int,
  out cur int, out in_slot numeric
)
language sql
stable
as $$
  select floor(e / (p_secs + 4))::int,
         e - floor(e / (p_secs + 4)) * (p_secs + 4)
    from (select extract(epoch from (now() - p_started)) - 5 as e) t;
$$;

-- Closes a speed round: every player who answered anything gets their points
-- as their score and their answers as their picks (so My mistakes fills the
-- same way), then the usual ranking and podium XP.
create or replace function app_private.finish_speed_quiz(p_quiz uuid)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  update room_quiz_players pl
     set score = a.points,
         picks = a.picks,
         submitted_at = a.last_at
    from (select user_id,
                 sum(points)::int as points,
                 jsonb_object_agg(question_id::text, pick) as picks,
                 max(answered_at) as last_at
            from room_quiz_answers
           where room_quiz_id = p_quiz
           group by user_id) a
   where pl.room_quiz_id = p_quiz
     and pl.user_id = a.user_id
     and pl.submitted_at is null;
  perform app_private.finish_room_quiz(p_quiz);
end $$;

-- Everything a room screen shows about one quiz, in one call. For a standard
-- quiz, unchanged from 0019. For a speed round: only the questions opened so
-- far, each one's answer once its window has closed, and everyone's points on
-- closed questions (live), plus the clock to draw the countdown from.
create or replace function public.get_room_quiz(p_quiz uuid)
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid   uuid := auth.uid();
  v_quiz  room_quizzes;
  v_done  boolean;
  v_speed boolean;
  v_secs  int;
  v_cur   int := -1;
  v_in    numeric := 0;
begin
  select * into v_quiz from room_quizzes where id = p_quiz;
  if not found or not exists (
       select 1 from room_members
        where room_id = v_quiz.room_id and user_id = v_uid)
     and not exists (
       select 1 from room_quiz_players
        where room_quiz_id = p_quiz and user_id = v_uid) then
    raise exception 'That quiz isn''t in your room.';
  end if;
  v_done  := v_quiz.status = 'finished';
  v_speed := v_quiz.mode = 'speed';
  v_secs  := v_quiz.seconds_per_question;
  if v_speed and v_quiz.status = 'running' then
    select c.cur, c.in_slot into v_cur, v_in
      from app_private.speed_clock(v_quiz.started_at, v_secs) c;
  end if;

  return json_build_object(
    'id', v_quiz.id,
    'room_id', v_quiz.room_id,
    'created_by', v_quiz.created_by,
    'title', v_quiz.title,
    'question_count', v_quiz.question_count,
    'status', v_quiz.status,
    'mode', v_quiz.mode,
    'seconds_per_question', v_secs,
    'started_at', v_quiz.started_at,
    'server_now', now(),
    'players', (
      select coalesce(json_agg(json_build_object(
               'user_id', pl.user_id,
               'full_name', pr.full_name,
               'avatar_initial', pr.avatar_initial,
               'vote', pl.vote,
               'submitted', pl.submitted_at is not null,
               'score', case
                 when v_done then pl.score
                 when v_speed then (
                   select coalesce(sum(a.points), 0)::int
                     from room_quiz_answers a
                     join room_quiz_questions q on q.id = a.question_id
                    where a.room_quiz_id = p_quiz and a.user_id = pl.user_id
                      and (q.order_index < v_cur
                           or (q.order_index = v_cur and v_in >= v_secs)))
                 when pl.user_id = v_uid then pl.score
               end,
               'answered_current', v_speed and exists (
                 select 1 from room_quiz_answers a
                   join room_quiz_questions q on q.id = a.question_id
                  where a.room_quiz_id = p_quiz and a.user_id = pl.user_id
                    and q.order_index = v_cur),
               'rank', pl.rank,
               'xp_awarded', pl.xp_awarded
             ) order by pl.rank nulls last, pr.full_name), '[]'::json)
        from room_quiz_players pl
        join profiles pr on pr.id = pl.user_id
       where pl.room_quiz_id = p_quiz),
    'questions', case when v_quiz.status in ('running', 'finished') then (
      select coalesce(json_agg(json_build_object(
               'id', q.id,
               'question', q.question,
               'options', q.options,
               'correct_index', case
                 when v_done or (v_speed and (q.order_index < v_cur
                      or (q.order_index = v_cur and v_in >= v_secs)))
                 then q.correct_index end,
               'explanation', case when v_done then q.explanation end
             ) order by q.order_index), '[]'::json)
        from room_quiz_questions q
       where q.room_quiz_id = p_quiz
         and (not v_speed or v_done or q.order_index <= v_cur)) end,
    'my_picks', case
      when v_speed and not v_done then (
        select jsonb_object_agg(question_id::text, pick)
          from room_quiz_answers
         where room_quiz_id = p_quiz and user_id = v_uid)
      else (select picks from room_quiz_players
             where room_quiz_id = p_quiz and user_id = v_uid) end
  );
end $$;

-- One answer in a speed round, inside that question's window (with 1.5 s of
-- grace for the trip from the phone). Points: 0 when wrong; when right, 500
-- plus up to 500 for speed.
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
  insert into room_quiz_answers (room_quiz_id, question_id, user_id, pick, points)
  values (p_quiz, p_question, v_uid, p_pick, v_points)
  on conflict do nothing;
  if not found then
    raise exception 'You''ve already answered that one.';
  end if;

  -- Everyone has answered the last question: no need to wait out the clock.
  if v_q.order_index = v_quiz.question_count - 1
     and (select count(*) from room_quiz_answers
           where room_quiz_id = p_quiz and question_id = p_question)
       >= (select count(*) from room_quiz_players where room_quiz_id = p_quiz) then
    perform app_private.finish_speed_quiz(p_quiz);
  end if;

  return public.get_room_quiz(p_quiz);
end $$;

-- Any player's phone calls this when its clock says the round is over; the
-- first one in closes it. Too early, it changes nothing.
create or replace function public.tick_room_quiz(p_quiz uuid)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_quiz room_quizzes;
  v_cur  int;
  v_in   numeric;
begin
  select * into v_quiz from room_quizzes where id = p_quiz for update;
  if found and v_quiz.mode = 'speed' and v_quiz.status = 'running' then
    select c.cur, c.in_slot into v_cur, v_in
      from app_private.speed_clock(v_quiz.started_at, v_quiz.seconds_per_question) c;
    if v_cur > v_quiz.question_count - 1
       or (v_cur = v_quiz.question_count - 1
           and v_in >= v_quiz.seconds_per_question + 1.5) then
      perform app_private.finish_speed_quiz(p_quiz);
    end if;
  end if;
  return public.get_room_quiz(p_quiz);  -- also checks the caller is in the room
end $$;

-- Hand-ins are for standard quizzes. Otherwise unchanged from 0019.
create or replace function public.submit_room_quiz(p_quiz uuid, p_picks jsonb)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid   uuid := auth.uid();
  v_score int;
begin
  perform 1 from room_quizzes where id = p_quiz and status = 'running' for update;
  if not found then
    raise exception 'That quiz has already ended.';
  end if;
  if exists (select 1 from room_quizzes where id = p_quiz and mode = 'speed') then
    raise exception 'A speed round is answered one question at a time.';
  end if;
  if not exists (select 1 from room_quiz_players
                  where room_quiz_id = p_quiz and user_id = v_uid
                    and submitted_at is null) then
    raise exception 'You''ve already handed this quiz in.';
  end if;

  select count(*) into v_score
    from room_quiz_questions q
   where q.room_quiz_id = p_quiz
     and nullif(p_picks ->> q.id::text, '')::int = q.correct_index;

  update room_quiz_players
     set picks = coalesce(p_picks, '{}'::jsonb), score = v_score, submitted_at = now()
   where room_quiz_id = p_quiz and user_id = v_uid;

  if not exists (select 1 from room_quiz_players
                  where room_quiz_id = p_quiz and submitted_at is null) then
    perform app_private.finish_room_quiz(p_quiz);
  end if;

  return public.get_room_quiz(p_quiz);
end $$;

-- The host ending a speed round scores it as it stands. Otherwise unchanged
-- from 0019.
create or replace function public.end_room_quiz(p_quiz uuid)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_quiz room_quizzes;
begin
  select * into v_quiz from room_quizzes where id = p_quiz for update;
  if not found or v_quiz.created_by <> auth.uid() then
    raise exception 'Only the person who started the quiz can end it.';
  end if;
  if v_quiz.status = 'voting' then
    update room_quizzes set status = 'cancelled', finished_at = now()
     where id = p_quiz;
  elsif v_quiz.status = 'running' and v_quiz.mode = 'speed' then
    perform app_private.finish_speed_quiz(p_quiz);
  elsif v_quiz.status = 'running' then
    perform app_private.finish_room_quiz(p_quiz);
  end if;
  return public.get_room_quiz(p_quiz);
end $$;

-- A leaver drops off a speed round's board. Otherwise unchanged from 0020.
create or replace function app_private.room_quiz_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_quiz    room_quizzes;
  v_closing boolean;
  v_left    int;
begin
  select (r.created_by = old.user_id or r.status <> 'active')
    into v_closing
    from study_rooms r where r.id = old.room_id;

  for v_quiz in
    select * from room_quizzes
     where room_id = old.room_id and status in ('voting', 'running')
     for update
  loop
    if v_quiz.status = 'voting' then
      delete from room_quiz_players
       where room_quiz_id = v_quiz.id and user_id = old.user_id;
      select count(*) into v_left from room_quiz_players
       where room_quiz_id = v_quiz.id;
      if coalesce(v_closing, true) or v_left < 2 then
        update room_quizzes set status = 'cancelled', finished_at = now()
         where id = v_quiz.id;
      elsif not exists (select 1 from room_quiz_players
                         where room_quiz_id = v_quiz.id
                           and vote is distinct from true) then
        update room_quizzes set status = 'running', started_at = now()
         where id = v_quiz.id;
      end if;
    elsif v_quiz.mode = 'speed' then
      -- The clock runs the round, so nobody waits on a leaver; they just
      -- drop off the board. An empty room has no round left to play.
      delete from room_quiz_answers
       where room_quiz_id = v_quiz.id and user_id = old.user_id;
      delete from room_quiz_players
       where room_quiz_id = v_quiz.id and user_id = old.user_id;
      if coalesce(v_closing, true) or not exists (
           select 1 from room_quiz_players where room_quiz_id = v_quiz.id) then
        perform app_private.finish_speed_quiz(v_quiz.id);
      end if;
    else
      delete from room_quiz_players
       where room_quiz_id = v_quiz.id and user_id = old.user_id
         and submitted_at is null;
      if not exists (select 1 from room_quiz_players
                      where room_quiz_id = v_quiz.id
                        and submitted_at is null) then
        perform app_private.finish_room_quiz(v_quiz.id);
      end if;
    end if;
  end loop;
  return old;
end $$;

revoke execute on function app_private.speed_clock(timestamptz, int) from public;
revoke execute on function app_private.finish_speed_quiz(uuid) from public;
revoke execute on function public.answer_room_quiz_question(uuid, uuid, int),
                           public.tick_room_quiz(uuid)
  from public, anon;
grant execute on function public.answer_room_quiz_question(uuid, uuid, int),
                          public.tick_room_quiz(uuid)
  to authenticated;

notify pgrst, 'reload schema';
