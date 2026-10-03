-- ============================================================
-- 0019  Study rooms: six-person cap, focus length set inside the
--       room, and group quizzes.
-- ============================================================
--
-- A room is now created with just a name and a size (2–6). The host picks the
-- focus and break lengths from inside the room, and can propose a group quiz:
-- everyone in the room gets the same questions from the same material, the
-- quiz only starts once every one of them agrees, scores are shown to the
-- whole room at the end, and the top three earn XP.
--
-- Answers never reach a client before the quiz is over: the quiz tables have
-- no client grants at all, and the only read path (`get_room_quiz`) leaves out
-- the correct answers until the quiz is finished. Scoring is server-side.
-- ============================================================

-- ── 1. Six people at most ───────────────────────────────────────────────────
create or replace function public.create_study_room(
  p_name        text,
  p_class_id    uuid default null,
  p_timer_min   int  default 25,
  p_break_min   int  default 5,
  p_max_members int  default 4
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_room study_rooms;
begin
  if v_uid is null then
    raise exception 'Sign in to open a study room.';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Give the room a name of 1 to 60 characters.';
  end if;
  if p_max_members not between 2 and 6 then
    raise exception 'A study room holds 2 to 6 people.';
  end if;
  if p_timer_min not between 5 and 120 or p_break_min not between 1 and 60 then
    raise exception 'Those timer settings are out of range.';
  end if;
  if p_class_id is not null
     and p_class_id is distinct from (select class_id from profiles where id = v_uid) then
    raise exception 'You can only open a room for your own class.';
  end if;

  update study_rooms set status = 'closed'
    where created_by = v_uid and status = 'active';

  insert into study_rooms
    (name, created_by, class_id, timer_duration_min, break_duration_min, max_members)
  values
    (v_name, v_uid, p_class_id, p_timer_min, p_break_min, p_max_members)
  returning * into v_room;

  insert into room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  return row_to_json(v_room);
end $$;

-- ── 2. Focus length, chosen inside the room ─────────────────────────────────
-- Stored on the room so someone who joins later gets the same lengths.
create or replace function public.set_room_timer(
  p_room      uuid,
  p_focus_min int,
  p_break_min int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_focus_min not between 5 and 120 or p_break_min not between 1 and 60 then
    raise exception 'Those timer settings are out of range.';
  end if;
  update study_rooms
     set timer_duration_min = p_focus_min,
         break_duration_min = p_break_min
   where id = p_room and created_by = auth.uid() and status = 'active';
  if not found then
    raise exception 'Only the host can change the timer.';
  end if;
end $$;

-- ── 3. Group quizzes ────────────────────────────────────────────────────────
create table if not exists room_quizzes (
  id             uuid        primary key default gen_random_uuid(),
  room_id        uuid        not null references study_rooms(id) on delete cascade,
  created_by     uuid        not null references auth.users(id) on delete cascade,
  title          text        not null,
  question_count int         not null check (question_count between 1 and 20),
  status         text        not null default 'voting'
                             check (status in ('voting', 'running', 'finished', 'cancelled')),
  created_at     timestamptz not null default now(),
  started_at     timestamptz,
  finished_at    timestamptz
);
-- One quiz on the go per room.
create unique index if not exists room_quizzes_one_open
  on room_quizzes(room_id) where status in ('voting', 'running');

create table if not exists room_quiz_questions (
  id            uuid   primary key default gen_random_uuid(),
  room_quiz_id  uuid   not null references room_quizzes(id) on delete cascade,
  order_index   int    not null,
  question      text   not null,
  options       text[] not null check (array_length(options, 1) = 4),
  correct_index int    not null check (correct_index between 0 and 3),
  explanation   text
);
create index if not exists room_quiz_questions_quiz_idx
  on room_quiz_questions(room_quiz_id, order_index);

-- Everyone in the room when the quiz was proposed. vote null = not yet.
create table if not exists room_quiz_players (
  room_quiz_id uuid        not null references room_quizzes(id) on delete cascade,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  vote         boolean,
  picks        jsonb,
  score        int,
  submitted_at timestamptz,
  rank         int,
  xp_awarded   int         not null default 0,
  primary key (room_quiz_id, user_id)
);

alter table room_quizzes        enable row level security;
alter table room_quiz_questions enable row level security;
alter table room_quiz_players   enable row level security;
-- No policies and no grants: every read and write goes through the functions
-- below, which is what keeps correct answers away from clients mid-quiz.
revoke all on room_quizzes, room_quiz_questions, room_quiz_players
  from anon, authenticated;

-- XP for the podium. Read through app_private.xp_for like every other award.
insert into xp_rules (action, xp, unit, description) values
  ('room_quiz_first',  30, 'quiz', 'First place in a group quiz (two or more players).'),
  ('room_quiz_second', 20, 'quiz', 'Second place in a group quiz.'),
  ('room_quiz_third',  10, 'quiz', 'Third place in a group quiz.')
on conflict (action) do update
  set xp = excluded.xp, unit = excluded.unit, description = excluded.description;

-- Everything a room screen shows about one quiz, in one call. Correct answers
-- and explanations only once it's finished; picks only your own until then.
create or replace function public.get_room_quiz(p_quiz uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_quiz room_quizzes;
  v_done boolean;
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
  v_done := v_quiz.status = 'finished';

  return json_build_object(
    'id', v_quiz.id,
    'room_id', v_quiz.room_id,
    'created_by', v_quiz.created_by,
    'title', v_quiz.title,
    'question_count', v_quiz.question_count,
    'status', v_quiz.status,
    'players', (
      select coalesce(json_agg(json_build_object(
               'user_id', pl.user_id,
               'full_name', pr.full_name,
               'avatar_initial', pr.avatar_initial,
               'vote', pl.vote,
               'submitted', pl.submitted_at is not null,
               'score', case when v_done or pl.user_id = v_uid then pl.score end,
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
               'correct_index', case when v_done then q.correct_index end,
               'explanation', case when v_done then q.explanation end
             ) order by q.order_index), '[]'::json)
        from room_quiz_questions q
       where q.room_quiz_id = p_quiz) end,
    'my_picks', (select picks from room_quiz_players
                  where room_quiz_id = p_quiz and user_id = v_uid)
  );
end $$;

-- The quiz on the go in a room (voting or running), or the latest finished
-- one from the last hour so a returning student still sees the results.
create or replace function public.get_active_room_quiz(p_room uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from room_members
                  where room_id = p_room and user_id = auth.uid()) then
    raise exception 'You are not in this room.';
  end if;
  select id into v_id from room_quizzes
   where room_id = p_room
     and (status in ('voting', 'running')
          or (status = 'finished' and finished_at > now() - interval '1 hour'))
   order by created_at desc
   limit 1;
  if v_id is null then
    return null;
  end if;
  return public.get_room_quiz(v_id);
end $$;

-- Ranks the submitted players and pays the podium. Ties go to whoever
-- submitted first. XP needs two or more players, a score above zero, and at
-- most three paid group quizzes per student per day, so a pair can't farm it.
create or replace function app_private.finish_room_quiz(p_quiz uuid)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_players int;
  v_row     record;
  v_xp      int;
  v_today   int;
begin
  update room_quizzes
     set status = 'finished', finished_at = now()
   where id = p_quiz and status = 'running';
  if not found then
    return;
  end if;

  with ranked as (
    select user_id,
           row_number() over (order by score desc, submitted_at asc) as r
      from room_quiz_players
     where room_quiz_id = p_quiz and submitted_at is not null
  )
  update room_quiz_players p
     set rank = ranked.r
    from ranked
   where p.room_quiz_id = p_quiz and p.user_id = ranked.user_id;

  select count(*) into v_players from room_quiz_players
   where room_quiz_id = p_quiz and submitted_at is not null;
  if v_players < 2 then
    return;
  end if;

  for v_row in
    select user_id, rank, score from room_quiz_players
     where room_quiz_id = p_quiz and rank between 1 and 3 and score > 0
  loop
    select count(*) into v_today
      from room_quiz_players pl
      join room_quizzes q on q.id = pl.room_quiz_id
     where pl.user_id = v_row.user_id
       and pl.xp_awarded > 0
       and q.finished_at::date = current_date;
    continue when v_today >= 3;

    v_xp := app_private.xp_for(case v_row.rank
      when 1 then 'room_quiz_first'
      when 2 then 'room_quiz_second'
      else 'room_quiz_third' end);
    update room_quiz_players set xp_awarded = v_xp
     where room_quiz_id = p_quiz and user_id = v_row.user_id;
    perform app_private.log_activity(v_row.user_id, 0, 0, v_xp);
    perform app_private.award_xp(v_row.user_id, v_xp);
  end loop;
end $$;

create or replace function public.vote_room_quiz(p_quiz uuid, p_agree boolean)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Lock the quiz so the last two votes can't both miss "everyone agreed".
  perform 1 from room_quizzes where id = p_quiz and status = 'voting' for update;
  if not found then
    raise exception 'That quiz isn''t waiting for votes any more.';
  end if;

  update room_quiz_players set vote = p_agree
   where room_quiz_id = p_quiz and user_id = v_uid;
  if not found then
    raise exception 'You weren''t in the room when this quiz was proposed.';
  end if;

  if not p_agree then
    update room_quizzes set status = 'cancelled', finished_at = now()
     where id = p_quiz;
  elsif not exists (select 1 from room_quiz_players
                     where room_quiz_id = p_quiz and vote is distinct from true) then
    update room_quizzes set status = 'running', started_at = now()
     where id = p_quiz;
  end if;

  return public.get_room_quiz(p_quiz);
end $$;

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

-- Host only: cancel while voting, or end a running quiz for those who've
-- handed in (someone left, or is taking too long).
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
  elsif v_quiz.status = 'running' then
    perform app_private.finish_room_quiz(p_quiz);
  end if;
  return public.get_room_quiz(p_quiz);
end $$;

revoke execute on function public.set_room_timer(uuid, int, int),
                           public.get_room_quiz(uuid),
                           public.get_active_room_quiz(uuid),
                           public.vote_room_quiz(uuid, boolean),
                           public.submit_room_quiz(uuid, jsonb),
                           public.end_room_quiz(uuid)
  from public, anon;
grant execute on function public.set_room_timer(uuid, int, int),
                          public.get_room_quiz(uuid),
                          public.get_active_room_quiz(uuid),
                          public.vote_room_quiz(uuid, boolean),
                          public.submit_room_quiz(uuid, jsonb),
                          public.end_room_quiz(uuid)
  to authenticated;
revoke execute on function app_private.finish_room_quiz(uuid) from public;
