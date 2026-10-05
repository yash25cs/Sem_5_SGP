-- StudyTrail — core schema
-- Extensions, enums, and all tables (identity, planning, materials+RAG,
-- flashcards, quizzes, gamification/analytics, chat).

create extension if not exists vector;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type pace_enum          as enum ('relaxed','steady','intense');
  create type milestone_state    as enum ('done','active','upcoming');
  create type task_tag_enum      as enum ('now','quiz','done');
  create type sr_grade_enum       as enum ('again','hard','good','easy');
  create type material_type_enum as enum ('syllabus_pdf','notes','video_link');
  create type ingest_status_enum as enum ('uploaded','processing','embedded','failed');
  create type chat_role_enum      as enum ('user','ai');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Identity & class
-- ---------------------------------------------------------------------------
create table if not exists classes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  college text,
  branch text,
  batch text,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  enrollment_id text,
  branch text,
  college text,
  email text,
  avatar_initial text,
  level int not null default 1,
  xp int not null default 0,
  xp_to_next int not null default 500,
  class_id uuid references classes(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Planning core
-- ---------------------------------------------------------------------------
create table if not exists goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  exam_date date,
  pace pace_enum not null default 'steady',
  roadmap_days int,
  current_day int not null default 1,
  overall_percent numeric(5,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists goals_user_idx on goals(user_id);

create table if not exists subjects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  name text not null,
  icon_key text,
  color_key text,
  is_focus boolean not null default true,
  progress numeric(5,2) not null default 0,
  accuracy numeric(5,2) not null default 0
);
create index if not exists subjects_user_idx on subjects(user_id);

create table if not exists milestones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  week_label text,
  title text not null,
  state milestone_state not null default 'upcoming',
  order_index int not null default 0,
  color_key text
);
create index if not exists milestones_goal_idx on milestones(goal_id);

create table if not exists milestone_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  milestone_id uuid not null references milestones(id) on delete cascade,
  name text not null,
  done boolean not null default false,
  order_index int not null default 0
);
create index if not exists milestone_tasks_milestone_idx on milestone_tasks(milestone_id);

create table if not exists daily_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  milestone_task_id uuid references milestone_tasks(id) on delete set null,
  title text not null,
  duration_min int,
  tag task_tag_enum not null default 'now',
  scheduled_date date not null default current_date,
  done boolean not null default false
);
create index if not exists daily_tasks_user_date_idx on daily_tasks(user_id, scheduled_date);
-- StudyTrail — materials + RAG (pgvector), flashcards, quizzes,
-- gamification/analytics, and AI chat.

-- ---------------------------------------------------------------------------
-- Materials + RAG
-- ---------------------------------------------------------------------------
create table if not exists materials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  source_type material_type_enum not null,
  title text,
  storage_path text,
  external_url text,
  status ingest_status_enum not null default 'uploaded',
  created_at timestamptz not null default now()
);
create index if not exists materials_user_idx on materials(user_id);

-- text-embedding-004 = 768 dims. Only table needing pgvector.
create table if not exists material_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  material_id uuid not null references materials(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  unit_label text,
  chunk_index int not null default 0,
  content text not null,
  embedding vector(768)
);
create index if not exists material_chunks_user_idx on material_chunks(user_id);
create index if not exists material_chunks_embedding_idx
  on material_chunks using hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- Flashcards (SM-2 spaced repetition)
-- ---------------------------------------------------------------------------
create table if not exists flashcard_decks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  name text not null,
  created_at timestamptz not null default now()
);
create index if not exists flashcard_decks_user_idx on flashcard_decks(user_id);

create table if not exists flashcards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  deck_id uuid not null references flashcard_decks(id) on delete cascade,
  unit_label text,
  front text not null,
  back text not null,
  source_chunk_id uuid references material_chunks(id) on delete set null,
  ease numeric(4,2) not null default 2.5,
  interval_days int not null default 0,
  repetitions int not null default 0,
  due_at timestamptz not null default now(),
  last_grade sr_grade_enum
);
create index if not exists flashcards_deck_idx on flashcards(deck_id);
create index if not exists flashcards_due_idx on flashcards(user_id, due_at);

-- total / due counts per deck.
-- security_invoker: without it the view runs as its owner (postgres) and would
-- bypass RLS on flashcards, exposing every user's counts. Requires PG15+.
create or replace view deck_stats
with (security_invoker = true) as
select
  d.id as deck_id,
  d.user_id,
  count(c.id) as total,
  count(c.id) filter (where c.due_at <= now()) as due
from flashcard_decks d
left join flashcards c on c.deck_id = d.id
group by d.id, d.user_id;

-- ---------------------------------------------------------------------------
-- Quizzes
-- ---------------------------------------------------------------------------
create table if not exists quizzes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  title text,
  length int,
  timer_sec int not null default 30,
  created_at timestamptz not null default now()
);
create index if not exists quizzes_user_idx on quizzes(user_id);

create table if not exists quiz_questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  quiz_id uuid not null references quizzes(id) on delete cascade,
  question text not null,
  options text[] not null check (array_length(options,1) = 4),
  correct_index int not null check (correct_index between 0 and 3),
  explanation text,
  xp_reward int not null default 10,
  order_index int not null default 0
);
create index if not exists quiz_questions_quiz_idx on quiz_questions(quiz_id);

create table if not exists quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  quiz_id uuid not null references quizzes(id) on delete cascade,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  score int,
  total int,
  xp_earned int
);
create index if not exists quiz_attempts_user_idx on quiz_attempts(user_id);

create table if not exists quiz_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  attempt_id uuid not null references quiz_attempts(id) on delete cascade,
  question_id uuid not null references quiz_questions(id) on delete cascade,
  picked_index int,
  is_correct boolean
);

-- ---------------------------------------------------------------------------
-- Gamification & analytics
-- ---------------------------------------------------------------------------
create table if not exists streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak int not null default 0,
  best_streak int not null default 0,
  last_active_date date
);

create table if not exists activity_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  minutes_studied int not null default 0,
  tasks_completed int not null default 0,
  xp_earned int not null default 0,
  unique (user_id, activity_date)
);

create table if not exists badges (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  name text not null,
  icon_key text,
  color_key text,
  description text
);

create table if not exists user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references badges(id) on delete cascade,
  unlocked boolean not null default false,
  unlocked_at timestamptz,
  primary key (user_id, badge_id)
);

create table if not exists study_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  length_min int,
  sessions_count int,
  focused_min int,
  started_at timestamptz,
  ended_at timestamptz,
  session_date date not null default current_date
);
create index if not exists study_sessions_user_idx on study_sessions(user_id, session_date);

-- ---------------------------------------------------------------------------
-- AI chat
-- ---------------------------------------------------------------------------
create table if not exists chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  title text,
  created_at timestamptz not null default now()
);

create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null references chat_threads(id) on delete cascade,
  role chat_role_enum not null,
  text text not null,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_thread_idx on chat_messages(thread_id, created_at);

create table if not exists chat_citations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references chat_messages(id) on delete cascade,
  chunk_id uuid references material_chunks(id) on delete set null,
  unit_label text
);
-- StudyTrail — Row Level Security.
-- Owner-only access on every user-owned table; read-all on catalogs.

-- Owner-only policy applied uniformly to all tables with a user_id column.
do $$
declare
  t text;
  owner_tables text[] := array[
    'goals','subjects','milestones','milestone_tasks','daily_tasks',
    'materials','material_chunks','flashcard_decks','flashcards',
    'quizzes','quiz_questions','quiz_attempts','quiz_answers',
    'streaks','activity_log','user_badges','study_sessions',
    'chat_threads','chat_messages','chat_citations'
  ];
begin
  foreach t in array owner_tables loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists owner_all on %I;', t);
    execute format($f$
      create policy owner_all on %I
        for all to authenticated
        using (auth.uid() = user_id)
        with check (auth.uid() = user_id);
    $f$, t);
  end loop;
end $$;

-- profiles: owner reads/updates own row (class-scoped reads go through an RPC).
alter table profiles enable row level security;
drop policy if exists profiles_select_own on profiles;
create policy profiles_select_own on profiles
  for select to authenticated using (auth.uid() = id);
drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists profiles_insert_own on profiles;
create policy profiles_insert_own on profiles
  for insert to authenticated with check (auth.uid() = id);

-- Catalog tables: read-only for any authenticated user.
alter table badges enable row level security;
drop policy if exists badges_read on badges;
create policy badges_read on badges for select to authenticated using (true);

alter table classes enable row level security;
drop policy if exists classes_read on classes;
create policy classes_read on classes for select to authenticated using (true);
-- StudyTrail — functions, triggers, and RPCs.

-- ---------------------------------------------------------------------------
-- New-user bootstrap: seed profiles + streaks when an auth.users row appears.
-- SECURITY DEFINER so it can write past RLS during the auth transaction.
-- ---------------------------------------------------------------------------
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, avatar_initial)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    upper(left(coalesce(new.raw_user_meta_data->>'full_name', new.email, '?'), 1))
  )
  on conflict (id) do nothing;

  insert into public.streaks (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- RAG retrieval: cosine similarity over the caller's own chunks.
-- SECURITY INVOKER (default) → RLS on material_chunks scopes rows to auth.uid();
-- the explicit user_id filter is defensive belt-and-suspenders.
-- ---------------------------------------------------------------------------
create or replace function match_material_chunks(
  query_embedding vector(768),
  match_count int default 6,
  filter_subject uuid default null
)
returns table (
  id uuid,
  material_id uuid,
  subject_id uuid,
  unit_label text,
  content text,
  similarity float
)
language sql
stable
as $$
  select
    c.id,
    c.material_id,
    c.subject_id,
    c.unit_label,
    c.content,
    1 - (c.embedding <=> query_embedding) as similarity
  from material_chunks c
  where c.user_id = auth.uid()
    and c.embedding is not null
    and (filter_subject is null or c.subject_id = filter_subject)
  order by c.embedding <=> query_embedding
  limit match_count;
$$;

-- ---------------------------------------------------------------------------
-- Class leaderboard: exposes only safe columns for peers in the caller's class.
-- SECURITY DEFINER so it can read past the owner-only profiles policy, but it
-- hard-scopes to the caller's own class_id — no cross-class leakage.
-- ---------------------------------------------------------------------------
-- 0012 widens the return type; `create or replace` can't change one, so a
-- re-run of this file drops first. 0012 then re-creates its own version.
drop function if exists get_class_leaderboard(int);
create or replace function get_class_leaderboard(limit_count int default 20)
returns table (
  user_id uuid,
  full_name text,
  avatar_initial text,
  level int,
  xp int,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_class uuid;
begin
  select class_id into my_class from profiles where id = auth.uid();
  if my_class is null then
    return;
  end if;

  return query
    select p.id, p.full_name, p.avatar_initial, p.level, p.xp,
           (p.id = auth.uid()) as is_me
    from profiles p
    where p.class_id = my_class
    order by p.xp desc, p.level desc
    limit limit_count;
end $$;

-- ---------------------------------------------------------------------------
-- Spaced repetition (SM-2). Maps the 4-button grade to SM-2 quality, updates
-- ease / interval / repetitions / due_at, and returns the updated row.
-- SECURITY INVOKER → RLS ensures a user can only grade their own cards.
-- ---------------------------------------------------------------------------
create or replace function apply_sr_grade(card_id uuid, grade sr_grade_enum)
returns flashcards
language plpgsql
as $$
declare
  card       flashcards;
  quality    int;
  new_ease   numeric(4,2);
  new_reps   int;
  new_int    int;
begin
  select * into card from flashcards where id = card_id;
  if not found then
    raise exception 'flashcard % not found', card_id;
  end if;

  quality := case grade
    when 'again' then 1
    when 'hard'  then 3
    when 'good'  then 4
    when 'easy'  then 5
  end;

  -- Ease update, floored at 1.3.
  new_ease := greatest(1.3,
    card.ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)));

  if quality < 3 then
    new_reps := 0;
    new_int  := 1;
  else
    new_reps := card.repetitions + 1;
    new_int  := case
      when new_reps = 1 then 1
      when new_reps = 2 then 6
      else greatest(1, round(card.interval_days * new_ease))
    end;
  end if;

  update flashcards
    set ease          = new_ease,
        repetitions   = new_reps,
        interval_days = new_int,
        due_at        = now() + (new_int || ' days')::interval,
        last_grade    = grade
    where id = card_id
    returning * into card;

  return card;
end $$;
-- StudyTrail — private Storage bucket for uploaded materials.
-- Objects live under /{uid}/... so ownership is derivable from the path.
--
-- Note: storage.objects is owned by supabase_storage_admin. If this file fails
-- with "must be owner of table objects", create the bucket + these four
-- policies through Storage → Policies in the dashboard instead; the using/
-- with-check expressions below are what to paste in.

insert into storage.buckets (id, name, public)
values ('materials', 'materials', false)
on conflict (id) do nothing;

-- Owner-only access, scoped to the caller's uid folder prefix.
drop policy if exists materials_read on storage.objects;
create policy materials_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists materials_insert on storage.objects;
create policy materials_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists materials_update on storage.objects;
create policy materials_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists materials_delete on storage.objects;
create policy materials_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
-- StudyTrail — seed catalog data (badges + a default class).
-- Idempotent: safe to re-run.

-- Default class for the CSPIT / Charusat cohort so the leaderboard has a home.
insert into classes (name, college, branch, batch)
select 'CE-A 2025', 'CSPIT, Charusat University', 'Computer Engineering', '2025'
where not exists (select 1 from classes where name = 'CE-A 2025');

-- Achievement catalog. icon_key / color_key mirror the UI's token names.
insert into badges (key, name, icon_key, color_key, description) values
  ('first_step',    'First Step',      'flag',          'sky',    'Complete your first study task.'),
  ('week_warrior',  'Week Warrior',    'local_fire_department', 'amber', 'Maintain a 7-day streak.'),
  ('quiz_ace',      'Quiz Ace',        'quiz',          'violet', 'Score 100% on any quiz.'),
  ('card_master',   'Card Master',     'style',         'emerald','Review 100 flashcards.'),
  ('night_owl',     'Night Owl',       'nightlight',    'indigo', 'Study after 10 PM.'),
  ('early_bird',    'Early Bird',      'wb_sunny',      'orange', 'Study before 7 AM.'),
  ('focused_mind',  'Focused Mind',    'self_improvement','teal', 'Finish 10 Pomodoro sessions.'),
  ('roadmap_ready', 'Roadmap Ready',   'map',           'rose',   'Generate your first AI roadmap.'),
  ('curious_learner','Curious Learner','chat',          'cyan',   'Ask the AI tutor 25 questions.'),
  ('goal_crusher',  'Goal Crusher',    'emoji_events',  'gold',   'Reach 100% on a goal.')
on conflict (key) do nothing;
-- StudyTrail — activity, streaks, XP, and quiz scoring RPCs.
-- Split out from 0004 so the core schema stays stable while these evolve.
--
-- Locals are prefixed `v_` throughout: plpgsql resolves an unqualified name
-- that matches both a variable and a column as an error, so `set score = score`
-- would fail at runtime.

-- ---------------------------------------------------------------------------
-- Records study activity for today and rolls the streak forward in one
-- statement. Read-then-write from the client would race between the Pomodoro
-- timer, task toggles, and quiz completion all logging at once.
-- SECURITY INVOKER → RLS confines every write to the caller's own rows.
-- ---------------------------------------------------------------------------
create or replace function log_activity(
  minutes int default 0,
  tasks int default 0,
  xp int default 0
)
returns activity_log
language plpgsql
as $$
declare
  v_today date := current_date;
  v_row   activity_log;
  v_last  date;
  v_cur   int;
begin
  insert into activity_log (user_id, activity_date, minutes_studied,
                            tasks_completed, xp_earned)
  values (auth.uid(), v_today, greatest(0, minutes), greatest(0, tasks),
          greatest(0, xp))
  on conflict (user_id, activity_date) do update
    set minutes_studied = activity_log.minutes_studied + greatest(0, minutes),
        tasks_completed = activity_log.tasks_completed + greatest(0, tasks),
        xp_earned       = activity_log.xp_earned + greatest(0, xp)
  returning * into v_row;

  -- Roll the streak: same day = no-op, yesterday = +1, older/never = reset to 1.
  select last_active_date, current_streak
    into v_last, v_cur
    from streaks where user_id = auth.uid();

  if found and v_last is distinct from v_today then
    v_cur := case
      when v_last = v_today - 1 then coalesce(v_cur, 0) + 1
      else 1
    end;
    update streaks
      set current_streak   = v_cur,
          best_streak      = greatest(best_streak, v_cur),
          last_active_date = v_today
      where user_id = auth.uid();
  end if;

  return v_row;
end $$;

-- ---------------------------------------------------------------------------
-- Awards XP and levels up. Same race argument as log_activity: quiz results,
-- task completion, and Pomodoro all grant XP independently.
-- Each level costs 20% more than the last.
-- ---------------------------------------------------------------------------
create or replace function award_xp(amount int)
returns profiles
language plpgsql
as $$
declare
  v_xp    int;
  v_level int;
  v_next  int;
  v_row   profiles;
begin
  select xp, level, xp_to_next into v_xp, v_level, v_next
    from profiles where id = auth.uid();
  if not found then
    raise exception 'no profile for %', auth.uid();
  end if;

  -- Guard the loop: a zero/negative threshold would never be reached.
  if v_next is null or v_next <= 0 then
    v_next := 100;
  end if;

  v_xp := v_xp + greatest(0, amount);
  while v_xp >= v_next loop
    v_xp    := v_xp - v_next;
    v_level := v_level + 1;
    v_next  := round(v_next * 1.2);
  end loop;

  update profiles
    set xp = v_xp, level = v_level, xp_to_next = v_next, updated_at = now()
    where id = auth.uid()
    returning * into v_row;

  return v_row;
end $$;

-- ---------------------------------------------------------------------------
-- Scores a finished quiz attempt server-side. The client sends what it picked;
-- correctness is decided here against quiz_questions so a tampered client
-- can't inflate its own score or XP.
-- picks: jsonb object of {question_id: picked_index}.
-- ---------------------------------------------------------------------------
create or replace function finish_quiz_attempt(attempt uuid, picks jsonb)
returns quiz_attempts
language plpgsql
as $$
declare
  v_row      quiz_attempts;
  v_score    int := 0;
  v_total    int := 0;
  v_earned   int := 0;
  v_question record;
  v_picked   int;
begin
  select * into v_row from quiz_attempts where id = attempt;
  if not found then
    raise exception 'attempt % not found', attempt;
  end if;
  if v_row.completed_at is not null then
    return v_row;  -- already scored; don't double-award
  end if;

  for v_question in
    select id, correct_index, xp_reward
      from quiz_questions where quiz_id = v_row.quiz_id
  loop
    v_total  := v_total + 1;
    v_picked := nullif(picks ->> v_question.id::text, '')::int;

    insert into quiz_answers (user_id, attempt_id, question_id, picked_index,
                              is_correct)
    values (auth.uid(), attempt, v_question.id, v_picked,
            v_picked is not distinct from v_question.correct_index);

    if v_picked is not distinct from v_question.correct_index then
      v_score  := v_score + 1;
      v_earned := v_earned + v_question.xp_reward;
    end if;
  end loop;

  update quiz_attempts
    set score = v_score, total = v_total, xp_earned = v_earned,
        completed_at = now()
    where id = attempt
    returning * into v_row;

  perform award_xp(v_earned);
  perform log_activity(0, 0, v_earned);

  return v_row;
end $$;

-- ---------------------------------------------------------------------------
-- Unlocks a badge by its stable key. Idempotent — re-unlocking is a no-op, so
-- the client can call this whenever a milestone is hit without checking first.
-- Returns true only the first time, which is the cue to show the "unlocked!"
-- toast.
-- ---------------------------------------------------------------------------
create or replace function unlock_badge(badge_key text)
returns boolean
language plpgsql
as $$
declare
  v_badge   uuid;
  v_changed int;
begin
  select id into v_badge from badges where key = badge_key;
  if v_badge is null then
    return false;
  end if;

  insert into user_badges (user_id, badge_id, unlocked, unlocked_at)
  values (auth.uid(), v_badge, true, now())
  on conflict (user_id, badge_id) do update
    set unlocked    = true,
        unlocked_at = coalesce(user_badges.unlocked_at, now())
    where user_badges.unlocked = false;

  get diagnostics v_changed = row_count;
  return v_changed > 0;
end $$;
-- StudyTrail — server-controlled rewards.
--
-- Closes the P0 finding in REVIEW.md. Before this migration XP, activity, and
-- badges were all reachable with client-supplied values: `award_xp(999999)`,
-- `log_activity(999999,…)`, `unlock_badge('goal_crusher')`. RLS stopped a
-- student touching *someone else's* rows but never stopped them lying about
-- their own.
--
-- The fix has three parts:
--
--   1. The privileged helpers move into `app_private`, a schema PostgREST is
--      not configured to expose and which `anon`/`authenticated` have no USAGE
--      on. They are unreachable over the API, by any URL.
--   2. Every reward is now derived from rows the server can see — a task that
--      is really unfinished, a focus block within believable bounds, a card
--      that was really due, an answer really matching `correct_index`. The
--      client says *what it did*, never *what it earned*.
--   3. Table privileges are narrowed so the reward tables can't be written
--      around the RPCs. This is the part RLS alone could never do: column and
--      table privileges are checked before policies, so `PATCH /profiles
--      {xp: 999999}` now fails on privilege, not on policy.
--
-- Locals are prefixed `v_` and parameters `p_` throughout: plpgsql raises at
-- runtime on a name that matches both a variable and a column, and most of
-- these functions write to tables whose columns share the obvious names.

-- ---------------------------------------------------------------------------
-- 1. app_private — helpers the API cannot see.
-- ---------------------------------------------------------------------------
create schema if not exists app_private;

-- Postgres grants EXECUTE on new functions to PUBLIC by default, so the schema
-- itself is the boundary: without USAGE the grant is unusable.
revoke all on schema app_private from public;
revoke all on schema app_private from anon, authenticated;
grant usage on schema app_private to postgres, service_role;

comment on schema app_private is
  'Privileged reward helpers. Not exposed by PostgREST and not granted to '
  'anon/authenticated — only SECURITY DEFINER functions in public may call in.';

-- ---------------------------------------------------------------------------
-- 2. xp_rules — the one place XP amounts are defined.
--
-- REVIEW.md P2 asked for a single documented home for the XP rules; this is it.
-- Clients may read it (so the UI can show "+15 XP" without hardcoding) but
-- cannot write it, and the RPCs below never accept an amount as an argument.
-- ---------------------------------------------------------------------------
create table if not exists xp_rules (
  action      text primary key,
  xp          int  not null check (xp >= 0 and xp <= 1000),
  unit        text not null default 'each',
  description text not null
);

comment on table xp_rules is
  'Single source of truth for XP payouts, read-only to clients.';

insert into xp_rules (action, xp, unit, description) values
  ('task_completed',  15, 'task',   'Ticking off a daily task. Paid once per task, ever.'),
  ('focus_minute',     1, 'minute', 'Per minute of a Pomodoro focus block that ran to completion.'),
  ('flashcard_review', 2, 'card',   'Grading a card that was genuinely due.'),
  ('quiz_correct',    10, 'answer', 'Ceiling for one correct quiz answer.')
on conflict (action) do update
  set xp          = excluded.xp,
      unit        = excluded.unit,
      description = excluded.description;

alter table xp_rules enable row level security;
drop policy if exists xp_rules_read on xp_rules;
create policy xp_rules_read on xp_rules for select to authenticated using (true);
revoke insert, update, delete on xp_rules from anon, authenticated;

create or replace function app_private.xp_for(p_action text)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce((select xp from public.xp_rules where action = p_action), 0);
$$;

-- ---------------------------------------------------------------------------
-- 3. One-shot task rewards.
--
-- Without this a student could tick a task off and on all afternoon and be paid
-- every time. `rewarded_at` records the first completion and is never cleared,
-- so re-completing is worth nothing.
-- ---------------------------------------------------------------------------
alter table daily_tasks add column if not exists rewarded_at timestamptz;

comment on column daily_tasks.rewarded_at is
  'When this task first paid out XP. Non-null blocks re-payment.';

-- Tasks already ticked off before this migration are treated as paid, so
-- deploying it doesn't hand out a retroactive windfall on the next toggle.
update daily_tasks set rewarded_at = now() where done and rewarded_at is null;

-- ---------------------------------------------------------------------------
-- 4. Internal helpers.
--
-- Each takes the user explicitly rather than reading auth.uid(): they run
-- inside SECURITY DEFINER callers that have already established who the caller
-- is, and an explicit argument makes that dependency visible at every call.
-- ---------------------------------------------------------------------------

-- Records activity for today and rolls the streak forward in one statement.
-- Read-then-write from the client would race between the Pomodoro timer, task
-- toggles, and quiz completion all logging at once.
create or replace function app_private.log_activity(
  p_user    uuid,
  p_minutes int default 0,
  p_tasks   int default 0,
  p_xp      int default 0
)
returns activity_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := current_date;
  v_row   activity_log;
  v_last  date;
  v_cur   int;
begin
  insert into activity_log (user_id, activity_date, minutes_studied,
                            tasks_completed, xp_earned)
  values (p_user, v_today, greatest(0, p_minutes), greatest(0, p_tasks),
          greatest(0, p_xp))
  on conflict (user_id, activity_date) do update
    set minutes_studied = activity_log.minutes_studied + greatest(0, p_minutes),
        tasks_completed = activity_log.tasks_completed + greatest(0, p_tasks),
        xp_earned       = activity_log.xp_earned + greatest(0, p_xp)
  returning * into v_row;

  -- Roll the streak: same day = no-op, yesterday = +1, older/never = reset to 1.
  select last_active_date, current_streak
    into v_last, v_cur
    from streaks where user_id = p_user;

  if found and v_last is distinct from v_today then
    v_cur := case
      when v_last = v_today - 1 then coalesce(v_cur, 0) + 1
      else 1
    end;
    update streaks
      set current_streak   = v_cur,
          best_streak      = greatest(best_streak, v_cur),
          last_active_date = v_today
      where user_id = p_user;
  end if;

  return v_row;
end $$;

-- Adds XP and levels up. Each level costs 20% more than the last.
create or replace function app_private.award_xp(p_user uuid, p_amount int)
returns profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_xp    int;
  v_level int;
  v_next  int;
  v_row   profiles;
begin
  select xp, level, xp_to_next into v_xp, v_level, v_next
    from profiles where id = p_user;
  if not found then
    raise exception 'no profile for %', p_user;
  end if;

  -- Guard the loop: a zero/negative threshold would never be reached.
  if v_next is null or v_next <= 0 then
    v_next := 100;
  end if;

  v_xp := v_xp + greatest(0, p_amount);
  while v_xp >= v_next loop
    v_xp    := v_xp - v_next;
    v_level := v_level + 1;
    v_next  := round(v_next * 1.2);
  end loop;

  update profiles
    set xp = v_xp, level = v_level, xp_to_next = v_next, updated_at = now()
    where id = p_user
    returning * into v_row;

  return v_row;
end $$;

-- Idempotent unlock. Returns true only the first time, which is the cue for the
-- "unlocked!" toast.
create or replace function app_private.unlock_badge(p_user uuid, p_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_badge   uuid;
  v_changed int;
begin
  select id into v_badge from badges where key = p_key;
  if v_badge is null then
    return false;
  end if;

  insert into user_badges (user_id, badge_id, unlocked, unlocked_at)
  values (p_user, v_badge, true, now())
  on conflict (user_id, badge_id) do update
    set unlocked    = true,
        unlocked_at = coalesce(user_badges.unlocked_at, now())
    where user_badges.unlocked = false;

  get diagnostics v_changed = row_count;
  return v_changed > 0;
end $$;

-- ---------------------------------------------------------------------------
-- Badge evaluation.
--
-- This replaces `unlock_badge(key)` as the client-facing entry point. Every
-- condition below is checked against real rows, so asking for a badge you
-- haven't earned returns nothing rather than granting it. Conditions mirror the
-- catalog descriptions in 0006_seed.sql.
--
-- Returns the keys unlocked *by this call* — an empty set on every call after
-- the first.
-- ---------------------------------------------------------------------------
create or replace function app_private.evaluate_badges(p_user uuid)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Hour-of-day badges are judged in the cohort's local time; started_at is
  -- timestamptz, so without this "study after 10 PM" would mean 10 PM UTC.
  v_tz  constant text := 'Asia/Kolkata';
  v_key text;
begin
  for v_key in
    select k from (values
      -- 'Complete your first study task.'
      ('first_step',
       exists (select 1 from daily_tasks
                where user_id = p_user and done)),
      -- 'Maintain a 7-day streak.' — best_streak, so it survives a lapse.
      ('week_warrior',
       exists (select 1 from streaks
                where user_id = p_user and best_streak >= 7)),
      -- 'Score 100% on any quiz.'
      ('quiz_ace',
       exists (select 1 from quiz_attempts
                where user_id = p_user and completed_at is not null
                  and total > 0 and score = total)),
      -- 'Review 100 flashcards.' — repetitions only ever move via the SR RPC.
      ('card_master',
       coalesce((select sum(repetitions) from flashcards
                  where user_id = p_user), 0) >= 100),
      -- 'Study after 10 PM.'
      ('night_owl',
       exists (select 1 from study_sessions
                where user_id = p_user and started_at is not null
                  and extract(hour from started_at at time zone v_tz) >= 22)),
      -- 'Study before 7 AM.'
      ('early_bird',
       exists (select 1 from study_sessions
                where user_id = p_user and started_at is not null
                  and extract(hour from started_at at time zone v_tz) < 7)),
      -- 'Finish 10 Pomodoro sessions.'
      ('focused_mind',
       coalesce((select sum(sessions_count) from study_sessions
                  where user_id = p_user), 0) >= 10),
      -- 'Generate your first AI roadmap.'
      ('roadmap_ready',
       exists (select 1 from milestones where user_id = p_user)),
      -- 'Ask the AI tutor 25 questions.'
      ('curious_learner',
       (select count(*) from chat_messages
         where user_id = p_user and role = 'user') >= 25),
      -- 'Reach 100% on a goal.'
      ('goal_crusher',
       exists (select 1 from goals
                where user_id = p_user and overall_percent >= 100))
    ) as t(k, earned)
    where earned
  loop
    if app_private.unlock_badge(p_user, v_key) then
      return next v_key;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Retire the client-callable reward RPCs.
--
-- Dropped rather than revoked so a stale build fails loudly with "function not
-- found" instead of silently doing nothing. plpgsql resolves function names at
-- runtime, so recreating the callers below is enough to keep them working.
-- ---------------------------------------------------------------------------
drop function if exists public.award_xp(int);
drop function if exists public.log_activity(int, int, int);
drop function if exists public.unlock_badge(text);

-- ---------------------------------------------------------------------------
-- 6. Public RPCs — the only way to earn anything.
--
-- All SECURITY DEFINER, which means RLS does *not* apply inside them. Every one
-- therefore re-checks ownership explicitly against auth.uid(); the `and
-- user_id = v_user` clauses below are load-bearing, not decoration.
-- ---------------------------------------------------------------------------

-- Ticks a daily task off (or back on) and pays out at most once.
create or replace function public.complete_task(p_task uuid, p_done boolean)
returns daily_tasks
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  -- Tasks are student-authored, so "complete a task" is XP the student can mint
  -- by typing. The cap is what keeps that honest: 20 paid completions a day is
  -- more than any real checklist, and the 21st still counts toward the streak.
  c_daily_paid_tasks constant int := 20;

  v_user       uuid := auth.uid();
  v_before     daily_tasks;
  v_row        daily_tasks;
  v_first      boolean;
  v_paid_today int;
  v_minutes    int;
  v_xp         int;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_before
    from daily_tasks where id = p_task and user_id = v_user;
  if not found then
    raise exception 'task % not found', p_task using errcode = 'no_data_found';
  end if;

  if v_before.done = p_done then
    return v_before;  -- idempotent; never a second payout
  end if;

  -- Whether this is the first completion has to be read before the update.
  v_first := p_done and v_before.rewarded_at is null;

  update daily_tasks
    set done        = p_done,
        tag         = case when p_done then 'done'::task_tag_enum
                           else 'now'::task_tag_enum end,
        rewarded_at = case when v_first then now() else rewarded_at end
    where id = p_task
    returning * into v_row;

  -- Keep the roadmap checkbox in step. Same transaction, so the two screens
  -- can't disagree the way two separate client calls could.
  if v_row.milestone_task_id is not null then
    update milestone_tasks
      set done = p_done
      where id = v_row.milestone_task_id and user_id = v_user;
  end if;

  if v_first then
    -- duration_min is student-entered, so it's clamped before it reaches the
    -- study log: a task claiming 99999 minutes is worth at most four hours.
    v_minutes := least(greatest(coalesce(v_row.duration_min, 0), 0), 240);

    select count(*) into v_paid_today
      from daily_tasks
      where user_id = v_user
        and rewarded_at is not null
        and rewarded_at >= date_trunc('day', now());

    -- Over the cap the work still lands in the log — it happened — but it is
    -- worth no XP. rewarded_at is set either way, so the same task can't come
    -- back tomorrow for a second try at the payout.
    v_xp := case when v_paid_today > c_daily_paid_tasks
                 then 0
                 else app_private.xp_for('task_completed') end;

    perform app_private.log_activity(v_user, v_minutes, 1, v_xp);
    if v_xp > 0 then
      perform app_private.award_xp(v_user, v_xp);
    end if;
    perform app_private.evaluate_badges(v_user);
  end if;

  return v_row;
end $$;

-- Persists one finished Pomodoro focus block and pays for the minutes in it.
create or replace function public.record_focus_session(
  p_subject     uuid default null,
  p_length_min  int  default 25,
  p_focused_min int  default null
)
returns study_sessions
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_focused int;
  v_today   int;
  v_xp      int;
  v_row     study_sessions;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- A focus block longer than three hours isn't a Pomodoro, it's a forged one.
  if p_length_min is null or p_length_min < 1 or p_length_min > 180 then
    raise exception 'length_min must be between 1 and 180, got %', p_length_min
      using errcode = 'check_violation';
  end if;

  v_focused := coalesce(p_focused_min, p_length_min);
  if v_focused < 0 or v_focused > p_length_min then
    raise exception 'focused_min must be between 0 and length_min'
      using errcode = 'check_violation';
  end if;

  -- Parent-ownership check (REVIEW.md P2): a known subject id belonging to
  -- someone else must not become the parent of the caller's session.
  if p_subject is not null
     and not exists (select 1 from subjects
                      where id = p_subject and user_id = v_user) then
    raise exception 'subject % not found', p_subject using errcode = 'no_data_found';
  end if;

  -- Sixteen hours of logged focus in one day is the outer edge of plausible;
  -- past that, stop counting rather than trust the clock the client sent.
  select coalesce(sum(focused_min), 0) into v_today
    from study_sessions
    where user_id = v_user and session_date = current_date;

  if v_today + v_focused > 960 then
    raise exception 'daily focus limit reached' using errcode = 'check_violation';
  end if;

  insert into study_sessions (user_id, subject_id, length_min, sessions_count,
                              focused_min, started_at, ended_at)
  values (v_user, p_subject, p_length_min, 1, v_focused,
          now() - make_interval(mins => v_focused), now())
  returning * into v_row;

  v_xp := v_focused * app_private.xp_for('focus_minute');
  perform app_private.log_activity(v_user, v_focused, 0, v_xp);
  perform app_private.award_xp(v_user, v_xp);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- Spaced repetition (SM-2), now also the only writer of a card's SR state.
--
-- Maps the 4-button grade to SM-2 quality, updates ease / interval /
-- repetitions / due_at, and pays for the review. Parameter names are unchanged
-- from 0004 because `create or replace` cannot rename them — and because the
-- client already calls it this way.
create or replace function public.apply_sr_grade(card_id uuid, grade sr_grade_enum)
returns flashcards
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_card    flashcards;
  v_was_due boolean;
  v_quality int;
  v_ease    numeric(4,2);
  v_reps    int;
  v_int     int;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_card
    from flashcards where id = card_id and user_id = v_user;
  if not found then
    raise exception 'flashcard % not found', card_id using errcode = 'no_data_found';
  end if;

  -- Only a card that had actually come up for review pays out. Grading pushes
  -- due_at at least a day forward, so this caps earnings at one payment per
  -- card per day without needing a counter to track it.
  v_was_due := v_card.due_at <= now();

  v_quality := case grade
    when 'again' then 1
    when 'hard'  then 3
    when 'good'  then 4
    when 'easy'  then 5
  end;

  -- Ease update, floored at 1.3.
  v_ease := greatest(1.3,
    v_card.ease + (0.1 - (5 - v_quality) * (0.08 + (5 - v_quality) * 0.02)));

  if v_quality < 3 then
    v_reps := 0;
    v_int  := 1;
  else
    v_reps := v_card.repetitions + 1;
    v_int  := case
      when v_reps = 1 then 1
      when v_reps = 2 then 6
      else greatest(1, round(v_card.interval_days * v_ease))
    end;
  end if;

  update flashcards
    set ease          = v_ease,
        repetitions   = v_reps,
        interval_days = v_int,
        due_at        = now() + make_interval(days => v_int),
        last_grade    = grade
    where id = card_id
    returning * into v_card;

  if v_was_due then
    perform app_private.log_activity(
      v_user, 0, 0, app_private.xp_for('flashcard_review'));
    perform app_private.award_xp(
      v_user, app_private.xp_for('flashcard_review'));
    perform app_private.evaluate_badges(v_user);
  end if;

  return v_card;
end $$;

-- Scores a finished quiz attempt. The client sends what it picked; correctness
-- is decided here against quiz_questions.
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
      v_earned := v_earned + least(greatest(coalesce(v_question.xp_reward, 0), 0), v_cap);
    end if;
  end loop;

  update quiz_attempts
    set score = v_score, total = v_total, xp_earned = v_earned,
        completed_at = now()
    where id = attempt
    returning * into v_row;

  perform app_private.award_xp(v_user, v_earned);
  perform app_private.log_activity(v_user, 0, 0, v_earned);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- Re-derives a goal's completion from its roadmap tasks.
--
-- Was computed client-side and written straight to goals.overall_percent, which
-- is the input to the goal_crusher badge — so the badge was effectively
-- self-certified. Now the percentage is counted server-side and the column is
-- no longer client-writable.
create or replace function public.recompute_goal_progress(p_goal uuid)
returns numeric
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_total   int;
  v_done    int;
  v_percent numeric(5,2);
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if not exists (select 1 from goals where id = p_goal and user_id = v_user) then
    raise exception 'goal % not found', p_goal using errcode = 'no_data_found';
  end if;

  select count(*), count(*) filter (where mt.done)
    into v_total, v_done
    from milestone_tasks mt
    join milestones m on m.id = mt.milestone_id
    where m.goal_id = p_goal and mt.user_id = v_user;

  v_percent := case when v_total = 0 then 0
                    else round((v_done::numeric / v_total) * 100, 2) end;

  update goals set overall_percent = v_percent where id = p_goal;
  perform app_private.evaluate_badges(v_user);

  return v_percent;
end $$;

-- Client-facing badge check, for the Achievements screen to call on open.
-- Returns only the keys this call newly unlocked.
create or replace function public.evaluate_badges()
returns setof text
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  return query select app_private.evaluate_badges(v_user);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Narrow the table privileges.
--
-- The RPCs above are pointless if the same rows are writable directly. These
-- revokes are what actually closes the hole; the DEFINER functions are
-- unaffected because they execute as the owner.
-- ---------------------------------------------------------------------------

-- Reward state: readable by its owner, written only by the RPCs.
revoke insert, update, delete on activity_log   from anon, authenticated;
revoke insert, update, delete on streaks        from anon, authenticated;
revoke insert, update, delete on user_badges    from anon, authenticated;
revoke insert, update, delete on study_sessions from anon, authenticated;
revoke insert, update, delete on quiz_answers   from anon, authenticated;

-- Attempts are opened by the client and scored by finish_quiz_attempt, so
-- insert stays and update goes.
revoke update on quiz_attempts from anon, authenticated;

-- profiles: level/xp/xp_to_next become server-only. Column-level grants are the
-- only way to say this — an RLS policy can restrict *which rows* you may update
-- but not which columns.
revoke update on profiles from anon, authenticated;
grant update (full_name, enrollment_id, branch, college, avatar_initial,
              class_id, updated_at)
  on profiles to authenticated;

-- flashcards: content is the student's, SM-2 state is the server's. Leaving
-- `repetitions` writable would have made the card_master badge self-certified.
revoke update on flashcards from anon, authenticated;
grant update (deck_id, unit_label, front, back) on flashcards to authenticated;

-- goals: overall_percent (and the roadmap counters) move behind
-- recompute_goal_progress and the Phase C roadmap generator.
revoke update on goals from anon, authenticated;
grant update (name, exam_date, pace, is_active) on goals to authenticated;

-- subjects: progress/accuracy are derived from quiz and task history, so they
-- are not the client's to assert.
revoke update on subjects from anon, authenticated;
grant update (goal_id, name, icon_key, color_key, is_focus)
  on subjects to authenticated;

-- Revoking UPDATE alone would have left the same forgery reachable one step
-- earlier, at INSERT: `POST /quiz_attempts {score:10,total:10,completed_at:…}`
-- self-certifies quiz_ace without a quiz existing. Postgres has column-level
-- INSERT grants too, so each table below is narrowed to exactly the columns the
-- Flutter repositories actually send.
revoke insert on quiz_attempts from anon, authenticated;
grant insert (user_id, quiz_id) on quiz_attempts to authenticated;

revoke insert on flashcards from anon, authenticated;
grant insert (user_id, deck_id, unit_label, front, back, source_chunk_id)
  on flashcards to authenticated;

revoke insert on goals from anon, authenticated;
grant insert (user_id, name, exam_date, pace, roadmap_days)
  on goals to authenticated;

revoke insert on subjects from anon, authenticated;
grant insert (user_id, goal_id, name, icon_key, color_key, is_focus)
  on subjects to authenticated;

-- daily_tasks: `done` and `rewarded_at` belong to complete_task. A task created
-- pre-ticked would otherwise hand out first_step for free.
revoke insert on daily_tasks from anon, authenticated;
grant insert (user_id, goal_id, subject_id, milestone_task_id, title,
              duration_min, tag, scheduled_date)
  on daily_tasks to authenticated;

-- profiles rows come from the handle_new_user trigger (SECURITY DEFINER, so it
-- writes past this), never from the app.
revoke insert on profiles from anon, authenticated;

-- Roadmaps and quizzes are generated artefacts: nothing in the app creates one
-- by hand, and both are XP-bearing if forged — a self-authored quiz with known
-- answers would be a free 10 XP a question. The client keeps only the two
-- checkbox writes it genuinely makes, plus DELETE for regenerating a roadmap.
--
-- Phase C consequence: generate-roadmap and generate-quiz must write with the
-- service_role key after verifying the JWT, not by forwarding the user's token.
revoke insert on milestones, milestone_tasks, quizzes, quiz_questions
  from anon, authenticated;

revoke update on milestones from anon, authenticated;
grant update (state) on milestones to authenticated;

revoke update on milestone_tasks from anon, authenticated;
grant update (done) on milestone_tasks to authenticated;

revoke update on quizzes, quiz_questions from anon, authenticated;

-- DELETE is the same forgery from the other side: drop the roadmap tasks you
-- haven't done and recompute_goal_progress reports 100%; drop the questions you
-- got wrong before finishing and the attempt scores full marks. Deleting the
-- parent still works — the FK cascade doesn't consult these privileges — so the
-- app keeps regenerating a roadmap and deleting a quiz.
revoke delete on milestone_tasks, quiz_questions from anon, authenticated;

-- Left deliberately open, and worth naming so the next reader doesn't assume
-- they were missed:
--   * daily_tasks / flashcards INSERT — creating a task or a card is a real
--     feature, so both are still routes to XP through actual typing. The daily
--     caps in complete_task and the due-date gate in apply_sr_grade bound them.
--   * chat_messages INSERT (role='user') — curious_learner counts these, and the
--     app inserts its own outgoing messages today. Phase C moves that write into
--     the chat function; the grant can be narrowed then.

-- Policies for the read-only reward tables, narrowed from `for all` to match
-- the privileges above. Defence in depth, and it documents the intent in the
-- place a reader looks first.
do $$
declare
  v_table text;
  v_read_only text[] := array[
    'activity_log','streaks','user_badges','study_sessions','quiz_answers'
  ];
begin
  foreach v_table in array v_read_only loop
    execute format('drop policy if exists owner_all on %I;', v_table);
    execute format('drop policy if exists owner_read on %I;', v_table);
    execute format($f$
      create policy owner_read on %I
        for select to authenticated
        using (auth.uid() = user_id);
    $f$, v_table);
  end loop;
end $$;

-- New functions are executable by PUBLIC by default; name the grants anyway so
-- the intended surface is explicit and reviewable.
grant execute on function public.complete_task(uuid, boolean)          to authenticated;
grant execute on function public.record_focus_session(uuid, int, int)  to authenticated;
grant execute on function public.apply_sr_grade(uuid, sr_grade_enum)   to authenticated;
grant execute on function public.finish_quiz_attempt(uuid, jsonb)      to authenticated;
grant execute on function public.recompute_goal_progress(uuid)         to authenticated;
grant execute on function public.evaluate_badges()                     to authenticated;

revoke all on function public.complete_task(uuid, boolean)         from anon;
revoke all on function public.record_focus_session(uuid, int, int) from anon;
revoke all on function public.apply_sr_grade(uuid, sr_grade_enum)  from anon;
revoke all on function public.finish_quiz_attempt(uuid, jsonb)     from anon;
revoke all on function public.recompute_goal_progress(uuid)        from anon;
revoke all on function public.evaluate_badges()                    from anon;

-- PostgREST caches the schema; without this the new RPCs 404 until it restarts.
notify pgrst, 'reload schema';
-- StudyTrail — atomic multi-step writes.
--
-- Closes the first P1 finding in REVIEW.md. Creating a goal was three separate
-- round-trips from the client: deactivate the old goal, insert the new one,
-- insert its subjects. Every gap between them is a state a student can actually
-- end up in — network drops, app killed, token expires:
--
--   * after step 1 → no active goal at all. Home renders empty, and
--     `hasAnyGoal()` still says true, so onboarding won't offer to fix it.
--   * after step 2 → a goal with no subjects. The Pomodoro subject chip and the
--     Progress breakdown are both empty, and nothing tells the student why.
--
-- One RPC makes it one transaction: all three, or none. `complete_task` in
-- 0008 already did the same for the task/milestone pair.
--
-- Locals are `v_`, parameters `p_`, constants `c_` — same convention as 0008.

-- ---------------------------------------------------------------------------
-- create_goal — deactivate + insert + seed subjects, atomically.
-- ---------------------------------------------------------------------------
create or replace function public.create_goal(
  p_name       text,
  p_exam_date  date default null,
  p_pace       text default 'steady',
  p_subjects   text[] default '{}'
)
returns goals
language plpgsql
security definer
set search_path = public
as $$
declare
  -- A real exam has a handful of subjects. The bound is here so a malformed or
  -- hostile call can't seed thousands of rows in one statement.
  c_max_subjects constant int := 40;
  c_max_name     constant int := 120;

  v_user  uuid := auth.uid();
  v_pace  pace_enum;
  v_name  text := btrim(coalesce(p_name, ''));
  v_goal  goals;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if v_name = '' then
    raise exception 'a goal needs a name' using errcode = '22023';
  end if;
  if length(v_name) > c_max_name then
    raise exception 'goal name is longer than % characters', c_max_name
      using errcode = '22001';
  end if;

  -- Cast explicitly rather than typing the parameter as pace_enum: PostgREST
  -- sends JSON strings, and a clear error here beats a cast failure in the
  -- argument list that names no column.
  begin
    v_pace := coalesce(nullif(btrim(coalesce(p_pace, '')), ''), 'steady')::pace_enum;
  exception when invalid_text_representation then
    raise exception 'unknown pace %; expected relaxed, steady or intense', p_pace
      using errcode = '22023';
  end;

  -- An exam that has already happened is almost always a date-picker slip, but
  -- it's the student's call — the roadmap generator clamps, it doesn't refuse.

  update goals
    set is_active = false
    where user_id = v_user and is_active;

  insert into goals (user_id, name, exam_date, pace)
    values (v_user, v_name, p_exam_date, v_pace)
    returning * into v_goal;

  -- distinct on lower() so "DBMS" and "dbms" don't both become subjects; there
  -- is no unique constraint on (goal_id, name) to lean on.
  insert into subjects (user_id, goal_id, name)
  select v_user, v_goal.id, subject_name
  from (
    select distinct on (lower(btrim(s))) btrim(s) as subject_name
    from unnest(coalesce(p_subjects, '{}'::text[])) as s
    where btrim(s) <> ''
    order by lower(btrim(s))
  ) as cleaned
  limit c_max_subjects;

  return v_goal;
end $$;

comment on function public.create_goal(text, date, text, text[]) is
  'Creates a goal, retires the previous active one, and seeds its subjects in a '
  'single transaction. Replaces three client round-trips (REVIEW.md P1).';

grant execute on function public.create_goal(text, date, text, text[])
  to authenticated;
revoke all on function public.create_goal(text, date, text, text[]) from anon;

-- ---------------------------------------------------------------------------
-- materials.status — let a failed ingest be retried.
-- ---------------------------------------------------------------------------
--
-- `ingest_status_enum` already has `failed`; what was missing is anything that
-- sets it. The Phase C `embed-material` function marks its own failures, but a
-- function that never starts — invoke rejected, cold start timeout — leaves the
-- row on `uploaded` forever, indistinguishable from one still queued.
--
-- The client may move a row between these states because "my upload broke, try
-- again" is honest client knowledge, and nothing here is XP-bearing. It may not
-- claim `embedded`: that asserts chunks exist, which only the function can know.
revoke update on materials from anon, authenticated;
grant update (goal_id, title, status) on materials to authenticated;

-- Enforces that last sentence. The trigger fires for service_role too, so
-- `embed-material` must insert its chunks *before* flipping the status —
-- which is the order it wants anyway, so the row is never briefly lying.
create or replace function app_private.material_status_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'embedded'::ingest_status_enum
     and old.status is distinct from new.status
     and not exists (
       select 1 from material_chunks
       where material_id = new.id and embedding is not null
     )
  then
    raise exception 'material % has no embedded chunks', new.id
      using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists materials_status_guard on materials;
create trigger materials_status_guard
  before update of status on materials
  for each row execute function app_private.material_status_guard();

notify pgrst, 'reload schema';
-- ============================================================
-- 0010  Study Buddy Rooms
-- ============================================================
-- Adds the tables, RLS policies, and RPCs needed for real-time
-- study rooms: room creation, membership, chat, and invite codes.
-- ============================================================

-- ── Helper: generate a random 6-char invite code ─────────────
create or replace function generate_invite_code()
returns text
language sql volatile
as $$
  select upper(substr(md5(gen_random_uuid()::text), 1, 6));
$$;

-- ── Table: study_rooms ───────────────────────────────────────
create table if not exists study_rooms (
  id               uuid        primary key default gen_random_uuid(),
  name             text        not null,
  invite_code      text        unique not null default generate_invite_code(),
  created_by       uuid        not null references profiles(id) on delete cascade,
  class_id         uuid        references classes(id) on delete set null,
  max_members      int         not null default 10,
  timer_duration_min int       not null default 25,
  break_duration_min int       not null default 5,
  status           text        not null default 'active'
                               check (status in ('active', 'closed')),
  created_at       timestamptz not null default now()
);

create index if not exists idx_study_rooms_status    on study_rooms(status);
create index if not exists idx_study_rooms_class     on study_rooms(class_id);
create index if not exists idx_study_rooms_code      on study_rooms(invite_code);
create index if not exists idx_study_rooms_created_by on study_rooms(created_by);

-- ── Table: room_members ──────────────────────────────────────
create table if not exists room_members (
  id        uuid        primary key default gen_random_uuid(),
  room_id   uuid        not null references study_rooms(id) on delete cascade,
  user_id   uuid        not null references profiles(id) on delete cascade,
  role      text        not null default 'member'
                        check (role in ('host', 'member')),
  joined_at timestamptz not null default now(),
  unique(room_id, user_id)
);

create index if not exists idx_room_members_room on room_members(room_id);
create index if not exists idx_room_members_user on room_members(user_id);

-- ── Table: room_messages ─────────────────────────────────────
create table if not exists room_messages (
  id         uuid        primary key default gen_random_uuid(),
  room_id    uuid        not null references study_rooms(id) on delete cascade,
  user_id    uuid        not null references profiles(id) on delete cascade,
  body       text        not null check (char_length(body) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_room_messages_room on room_messages(room_id);

-- ── Enable Realtime for room_messages ────────────────────────
-- Guarded so the file stays safe to re-run (README: every migration is).
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime'
                    and schemaname = 'public' and tablename = 'room_messages') then
    alter publication supabase_realtime add table room_messages;
  end if;
end $$;

-- ============================================================
-- RLS Policies
-- ============================================================

alter table study_rooms   enable row level security;
alter table room_members  enable row level security;
alter table room_messages enable row level security;

-- study_rooms: anyone authed can see active rooms (for lobby)
drop policy if exists "rooms_select" on study_rooms;
create policy "rooms_select" on study_rooms for select to authenticated
  using (true);

-- study_rooms: creator can insert
drop policy if exists "rooms_insert" on study_rooms;
create policy "rooms_insert" on study_rooms for insert to authenticated
  with check (created_by = auth.uid());

-- study_rooms: only host can update (e.g. close room)
drop policy if exists "rooms_update" on study_rooms;
create policy "rooms_update" on study_rooms for update to authenticated
  using (created_by = auth.uid());

-- study_rooms: only host can delete
drop policy if exists "rooms_delete" on study_rooms;
create policy "rooms_delete" on study_rooms for delete to authenticated
  using (created_by = auth.uid());

-- room_members: can see members of rooms you're in
drop policy if exists "members_select" on room_members;
create policy "members_select" on room_members for select to authenticated
  using (
    room_id in (select room_id from room_members where user_id = auth.uid())
  );

-- room_members: can join a room (insert yourself)
drop policy if exists "members_insert" on room_members;
create policy "members_insert" on room_members for insert to authenticated
  with check (user_id = auth.uid());

-- room_members: can leave a room (delete yourself)
drop policy if exists "members_delete" on room_members;
create policy "members_delete" on room_members for delete to authenticated
  using (user_id = auth.uid());

-- room_messages: can see messages in rooms you're in
drop policy if exists "messages_select" on room_messages;
create policy "messages_select" on room_messages for select to authenticated
  using (
    room_id in (select room_id from room_members where user_id = auth.uid())
  );

-- room_messages: can send messages in rooms you're in
drop policy if exists "messages_insert" on room_messages;
create policy "messages_insert" on room_messages for insert to authenticated
  with check (
    user_id = auth.uid()
    and room_id in (select room_id from room_members where user_id = auth.uid())
  );

-- ============================================================
-- RPCs
-- ============================================================

--- Create a study room and auto-join the creator as host.
create or replace function create_study_room(
  p_name             text,
  p_class_id         uuid    default null,
  p_timer_min        int     default 25,
  p_break_min        int     default 5,
  p_max_members      int     default 10
)
returns json
language plpgsql security definer
as $$
declare
  v_room study_rooms;
begin
  insert into study_rooms (name, created_by, class_id, timer_duration_min, break_duration_min, max_members)
  values (p_name, auth.uid(), p_class_id, p_timer_min, p_break_min, p_max_members)
  returning * into v_room;

  insert into room_members (room_id, user_id, role)
  values (v_room.id, auth.uid(), 'host');

  return row_to_json(v_room);
end;
$$;

--- Join a room by its 6-char invite code.
create or replace function join_room_by_code(p_code text)
returns json
language plpgsql security definer
as $$
declare
  v_room  study_rooms;
  v_count int;
begin
  select * into v_room from study_rooms
  where upper(invite_code) = upper(trim(p_code))
    and status = 'active';

  if not found then
    raise exception 'Room not found or already closed.' using errcode = 'P0001';
  end if;

  -- Check capacity
  select count(*) into v_count from room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'This room is full.' using errcode = 'P0002';
  end if;

  -- Check if already a member
  if exists (select 1 from room_members where room_id = v_room.id and user_id = auth.uid()) then
    return row_to_json(v_room);
  end if;

  insert into room_members (room_id, user_id, role)
  values (v_room.id, auth.uid(), 'member');

  return row_to_json(v_room);
end;
$$;

--- Close a room (host only).
create or replace function close_study_room(p_room_id uuid)
returns void
language plpgsql security definer
as $$
begin
  update study_rooms
  set status = 'closed'
  where id = p_room_id
    and created_by = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'Room not found or you are not the host.' using errcode = 'P0003';
  end if;
end;
$$;
-- ============================================================
-- 0011  Study rooms: fix the recursive policy, route every
--       membership change through an RPC, and let members see
--       each other's names.
-- ============================================================
--
-- What 0010 shipped with, verified against the hosted project on 2026-09-30:
--
-- 1. `members_select` on room_members read room_members inside its own USING
--    clause. Postgres answers that with 42P17 "infinite recursion detected in
--    policy", so *every* query touching the table failed — including the
--    lobby's `room_members(id)` embed and the subquery in both room_messages
--    policies. The repository swallowed the error, so the lobby was always
--    empty, the member list was always empty, and no chat message was ever
--    saved.
--
-- 2. `members_insert` let any signed-in student insert themselves straight into
--    any room, skipping the capacity check, the closed-room check, and the
--    invite code — and pick role = 'host' while doing it.
--
-- 3. Other members' names came from a `profiles(...)` embed, but profiles are
--    owner-only (0003), so every other member rendered as a blank.
--
-- 4. The three SECURITY DEFINER functions had no `set search_path`, and
--    create_study_room accepted any name, timer length, or capacity.
--
-- After this migration the client can read rooms, members and messages, write
-- its own messages, and delete its own membership (leaving). Everything else —
-- creating, joining, closing — is an RPC that checks what it has to.
-- ============================================================

-- ── 1. Non-recursive membership policy ──────────────────────────────────────
-- Your own rows, plus the rows of any open room. The lobby needs member counts
-- for rooms you haven't joined, and rooms are public by design (the lobby
-- lists them), so who is sitting in an open room is not a secret. It reads
-- study_rooms, whose policy doesn't read room_members, so nothing recurses.
drop policy if exists members_select on room_members;
create policy members_select on room_members for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from study_rooms r
      where r.id = room_members.room_id and r.status = 'active'
    )
  );

-- The message policies read room_members through the policy above, which now
-- resolves. Recreated anyway so that a message can only be *written* to a room
-- that is still open.
drop policy if exists messages_select on room_messages;
create policy messages_select on room_messages for select to authenticated
  using (
    room_id in (select m.room_id from room_members m where m.user_id = auth.uid())
  );

drop policy if exists messages_insert on room_messages;
create policy messages_insert on room_messages for insert to authenticated
  with check (
    user_id = auth.uid()
    and room_id in (select m.room_id from room_members m where m.user_id = auth.uid())
    and exists (
      select 1 from study_rooms r
      where r.id = room_messages.room_id and r.status = 'active'
    )
  );

-- ── 2. Privileges ───────────────────────────────────────────────────────────
-- Supabase's default privileges grant ALL on new public tables to anon and
-- authenticated; RLS alone decides rows, not verbs. Narrow the verbs.
revoke all on study_rooms, room_members, room_messages from anon;

-- Rooms are created and closed by RPC only.
revoke insert, update, delete on study_rooms from authenticated;
drop policy if exists rooms_insert on study_rooms;
drop policy if exists rooms_update on study_rooms;
drop policy if exists rooms_delete on study_rooms;

-- Joining is by RPC only (capacity, open-room check). Leaving stays a plain
-- delete of your own row — members_delete already scopes it to user_id.
revoke insert, update on room_members from authenticated;
drop policy if exists members_insert on room_members;

-- Messages are immutable once sent. `id` is insertable so the client can
-- pick it up front: the optimistic bubble and the realtime echo then share
-- one id and de-duplicate. `created_at` is not — the server's clock orders
-- the transcript, not the sender's.
revoke insert, update, delete on room_messages from authenticated;
grant insert (id, room_id, user_id, body) on room_messages to authenticated;

-- ── 3. RPCs ─────────────────────────────────────────────────────────────────
create or replace function public.create_study_room(
  p_name        text,
  p_class_id    uuid default null,
  p_timer_min   int  default 25,
  p_break_min   int  default 5,
  p_max_members int  default 10
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
  if p_timer_min not between 5 and 120
     or p_break_min not between 1 and 60
     or p_max_members not between 2 and 20 then
    raise exception 'Those room settings are out of range.';
  end if;
  -- A class-scoped room must be the host's own class, so nobody can plant
  -- rooms in another cohort's lobby.
  if p_class_id is not null
     and p_class_id is distinct from (select class_id from profiles where id = v_uid) then
    raise exception 'You can only open a room for your own class.';
  end if;

  -- One open room per host. A host whose app died never ran "close", and
  -- this is where their ghost room finally goes away.
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

create or replace function public.join_room_by_code(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  study_rooms;
  v_count int;
begin
  if v_uid is null then
    raise exception 'Sign in to join a study room.';
  end if;

  -- FOR UPDATE serialises concurrent joins on the same room, so two students
  -- racing for the last seat can't both pass the capacity check.
  select * into v_room from study_rooms
   where invite_code = upper(btrim(coalesce(p_code, '')))
     and status = 'active'
   for update;

  if not found then
    raise exception 'No open room has that code.';
  end if;

  if exists (select 1 from room_members
              where room_id = v_room.id and user_id = v_uid) then
    return row_to_json(v_room);
  end if;

  select count(*) into v_count from room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'This room is full.';
  end if;

  insert into room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'member');

  return row_to_json(v_room);
end $$;

create or replace function public.close_study_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update study_rooms
     set status = 'closed'
   where id = p_room_id
     and created_by = auth.uid()
     and status = 'active';

  if not found then
    raise exception 'Only the host can close this room.';
  end if;
end $$;

-- Members with display names. profiles are owner-only, so this reads past RLS
-- — and therefore checks membership itself and returns only the two columns a
-- room shows.
create or replace function public.get_room_members(p_room_id uuid)
returns table (
  user_id        uuid,
  role           text,
  joined_at      timestamptz,
  full_name      text,
  avatar_initial text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from room_members m
                  where m.room_id = p_room_id and m.user_id = auth.uid()) then
    raise exception 'You are not in this room.';
  end if;

  return query
    select m.user_id, m.role, m.joined_at, p.full_name, p.avatar_initial
      from room_members m
      join profiles p on p.id = m.user_id
     where m.room_id = p_room_id
     order by m.joined_at asc;
end $$;

revoke execute on function public.create_study_room(text, uuid, int, int, int),
                           public.join_room_by_code(text),
                           public.close_study_room(uuid),
                           public.get_room_members(uuid)
  from public, anon;
grant execute on function public.create_study_room(text, uuid, int, int, int),
                          public.join_room_by_code(text),
                          public.close_study_room(uuid),
                          public.get_room_members(uuid)
  to authenticated;

-- ── 4. Rooms close themselves ───────────────────────────────────────────────
-- When the host leaves, or the last member does, the room is over. Without
-- this every abandoned room stayed "active" in the lobby forever.
create or replace function app_private.close_abandoned_room()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update study_rooms r
     set status = 'closed'
   where r.id = old.room_id
     and r.status = 'active'
     and (r.created_by = old.user_id
          or not exists (select 1 from room_members m where m.room_id = old.room_id));
  return null;
end $$;

drop trigger if exists room_members_close_abandoned on room_members;
create trigger room_members_close_abandoned
  after delete on room_members
  for each row execute function app_private.close_abandoned_room();

-- Existing ghosts from before this migration.
update study_rooms r
   set status = 'closed'
 where r.status = 'active'
   and not exists (select 1 from room_members m where m.room_id = r.id);
-- ============================================================
-- 0012  Rewards store on the server, a streak freeze that
--       actually freezes, and a leaderboard ranked by total XP.
-- ============================================================
--
-- The Rewards screen used to keep "spent XP" and unlocked coupons in
-- SharedPreferences: per install rather than per student (a second account on
-- the same phone inherited the first one's purchases), reset by reinstalling,
-- and none of the four coupons changed anything in the app. It also measured
-- the balance against `profiles.xp`, which is XP *within the current level* —
-- award_xp subtracts the threshold on every level-up — so levelling up made the
-- balance drop.
--
-- Balance here = XP ever earned (sum of activity_log.xp_earned, which 0008
-- keeps in lock-step with every award) minus XP ever spent. Spending never
-- touches profiles.xp or level, so buying something can't cost a student
-- leaderboard rank.
-- ============================================================

-- ── 1. Catalog ──────────────────────────────────────────────────────────────
create table if not exists reward_catalog (
  key         text primary key,
  title       text not null,
  description text not null,
  cost_xp     int  not null check (cost_xp > 0),
  -- Most a student may hold unused at once; null = no cap.
  max_held    int  check (max_held is null or max_held > 0),
  sort_order  int  not null default 0
);

insert into reward_catalog (key, title, description, cost_xp, max_held, sort_order) values
  ('streak_freeze', 'Streak Freeze',
   'Covers one missed day so your streak survives. Used automatically the next time you study. Hold up to 2.',
   100, 2, 1),
  ('golden_border', 'Golden Scholar Border',
   'A gold ring around your name on the class leaderboard. Yours for good.',
   300, 1, 2)
on conflict (key) do update
  set title = excluded.title,
      description = excluded.description,
      cost_xp = excluded.cost_xp,
      max_held = excluded.max_held,
      sort_order = excluded.sort_order;

alter table reward_catalog enable row level security;
drop policy if exists reward_catalog_read on reward_catalog;
create policy reward_catalog_read on reward_catalog for select to authenticated
  using (true);
revoke all on reward_catalog from anon;
revoke insert, update, delete on reward_catalog from authenticated;

-- ── 2. Redemptions ──────────────────────────────────────────────────────────
create table if not exists reward_redemptions (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,
  reward_key   text        not null references reward_catalog(key),
  cost_xp      int         not null check (cost_xp > 0),
  redeemed_at  timestamptz not null default now(),
  -- Streak freezes only: when one was spent, and which missed day it covered.
  consumed_at  timestamptz,
  consumed_for date
);

create index if not exists reward_redemptions_user_idx
  on reward_redemptions (user_id, reward_key)
  where consumed_at is null;

alter table reward_redemptions enable row level security;
drop policy if exists reward_redemptions_own on reward_redemptions;
create policy reward_redemptions_own on reward_redemptions for select to authenticated
  using (user_id = auth.uid());
-- Written only by redeem_reward and log_activity.
revoke all on reward_redemptions from anon;
revoke insert, update, delete on reward_redemptions from authenticated;

-- ── 3. Wallet ───────────────────────────────────────────────────────────────
create or replace function app_private.reward_balance(p_user uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select (coalesce((select sum(xp_earned) from activity_log where user_id = p_user), 0)
        - coalesce((select sum(cost_xp)   from reward_redemptions where user_id = p_user), 0))::int
$$;

-- Everything the Rewards screen shows, in one round trip.
create or replace function public.get_reward_wallet()
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sign in to see your rewards.';
  end if;

  return json_build_object(
    'earned',  coalesce((select sum(xp_earned) from activity_log where user_id = v_uid), 0),
    'spent',   coalesce((select sum(cost_xp) from reward_redemptions where user_id = v_uid), 0),
    'balance', app_private.reward_balance(v_uid),
    'rewards', coalesce((
      select json_agg(json_build_object(
               'key', c.key,
               'title', c.title,
               'description', c.description,
               'cost_xp', c.cost_xp,
               'max_held', c.max_held,
               'held', (select count(*) from reward_redemptions r
                         where r.user_id = v_uid and r.reward_key = c.key
                           and r.consumed_at is null),
               'used', (select count(*) from reward_redemptions r
                         where r.user_id = v_uid and r.reward_key = c.key
                           and r.consumed_at is not null)
             ) order by c.sort_order)
        from reward_catalog c), '[]'::json)
  );
end $$;

create or replace function public.redeem_reward(p_key text)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid     uuid := auth.uid();
  v_reward  reward_catalog;
  v_held    int;
  v_balance int;
begin
  if v_uid is null then
    raise exception 'Sign in to redeem rewards.';
  end if;

  -- Serialise this student's redemptions: two taps racing each other must not
  -- both pass the balance check.
  perform 1 from profiles where id = v_uid for update;

  select * into v_reward from reward_catalog where key = p_key;
  if not found then
    raise exception 'That reward is no longer available.';
  end if;

  select count(*) into v_held from reward_redemptions
   where user_id = v_uid and reward_key = p_key and consumed_at is null;
  if v_reward.max_held is not null and v_held >= v_reward.max_held then
    raise exception 'You already have the most of these you can hold.';
  end if;

  v_balance := app_private.reward_balance(v_uid);
  if v_balance < v_reward.cost_xp then
    raise exception 'You need % more XP for this.', v_reward.cost_xp - v_balance;
  end if;

  insert into reward_redemptions (user_id, reward_key, cost_xp)
  values (v_uid, p_key, v_reward.cost_xp);

  return public.get_reward_wallet();
end $$;

revoke execute on function public.get_reward_wallet(), public.redeem_reward(text)
  from public, anon;
grant execute on function public.get_reward_wallet(), public.redeem_reward(text)
  to authenticated;
revoke execute on function app_private.reward_balance(uuid) from public;

-- ── 4. Streak freeze ────────────────────────────────────────────────────────
-- log_activity from 0008, unchanged except for the gap case: when the student
-- missed one or two days and holds enough freezes to cover every missed day,
-- the freezes are spent and the streak continues instead of resetting to 1.
-- Holding is capped at 2, so a gap of 3+ days always resets.
create or replace function app_private.log_activity(
  p_user    uuid,
  p_minutes int default 0,
  p_tasks   int default 0,
  p_xp      int default 0
)
returns activity_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := current_date;
  v_row     activity_log;
  v_last    date;
  v_cur     int;
  v_missed  int;
  v_freezes int;
begin
  insert into activity_log (user_id, activity_date, minutes_studied,
                            tasks_completed, xp_earned)
  values (p_user, v_today, greatest(0, p_minutes), greatest(0, p_tasks),
          greatest(0, p_xp))
  on conflict (user_id, activity_date) do update
    set minutes_studied = activity_log.minutes_studied + greatest(0, p_minutes),
        tasks_completed = activity_log.tasks_completed + greatest(0, p_tasks),
        xp_earned       = activity_log.xp_earned + greatest(0, p_xp)
  returning * into v_row;

  -- Roll the streak: same day = no-op, yesterday = +1, a gap covered by
  -- freezes = +1 (freezes spent), anything else = reset to 1.
  select last_active_date, current_streak
    into v_last, v_cur
    from streaks where user_id = p_user;

  if found and v_last is distinct from v_today then
    if v_last = v_today - 1 then
      v_cur := coalesce(v_cur, 0) + 1;
    else
      v_missed := v_today - v_last - 1;   -- null when never active
      select count(*) into v_freezes from reward_redemptions
       where user_id = p_user and reward_key = 'streak_freeze'
         and consumed_at is null;

      if v_missed between 1 and v_freezes and coalesce(v_cur, 0) > 0 then
        for i in 1..v_missed loop
          update reward_redemptions
             set consumed_at = now(), consumed_for = v_last + i
           where id = (select id from reward_redemptions
                        where user_id = p_user and reward_key = 'streak_freeze'
                          and consumed_at is null
                        order by redeemed_at
                        limit 1);
        end loop;
        v_cur := v_cur + 1;
      else
        v_cur := 1;
      end if;
    end if;

    update streaks
      set current_streak   = v_cur,
          best_streak      = greatest(best_streak, v_cur),
          last_active_date = v_today
      where user_id = p_user;
  end if;

  return v_row;
end $$;

-- ── 5. Leaderboard ──────────────────────────────────────────────────────────
-- 0004 ordered by `p.xp desc, p.level desc`. profiles.xp resets on every
-- level-up, so a level-3 student with 10 XP into the level ranked below a
-- level-1 student with 400. Rank by total XP earned instead, and say who has
-- the golden border. Return type changes, so drop first.
drop function if exists public.get_class_leaderboard(int);
create function public.get_class_leaderboard(limit_count int default 20)
returns table (
  user_id        uuid,
  full_name      text,
  avatar_initial text,
  level          int,
  xp             int,
  total_xp       int,
  golden_border  boolean,
  is_me          boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_class uuid;
begin
  select class_id into my_class from profiles where id = auth.uid();
  if my_class is null then
    return;
  end if;

  return query
    select p.id, p.full_name, p.avatar_initial, p.level, p.xp,
           coalesce((select sum(a.xp_earned) from activity_log a
                      where a.user_id = p.id), 0)::int as total_xp,
           exists (select 1 from reward_redemptions r
                    where r.user_id = p.id and r.reward_key = 'golden_border')
             as golden_border,
           (p.id = auth.uid()) as is_me
      from profiles p
     where p.class_id = my_class
     order by total_xp desc, p.level desc, p.xp desc, p.full_name asc
     limit greatest(1, least(limit_count, 100));
end $$;

revoke execute on function public.get_class_leaderboard(int) from public, anon;
grant execute on function public.get_class_leaderboard(int) to authenticated;
-- ============================================================
-- 0013  Study-room moderation: block, report, host removal.
-- ============================================================
--
-- Anyone who joins a room can post in its chat, so once rooms are used by
-- real students three things are needed:
--
-- * Block — a personal filter. The blocker stops seeing the blocked student's
--   messages in every room. Nothing changes for anyone else.
-- * Report — a record for whoever runs the project to review in the
--   dashboard. It snapshots the message text, because a room can be closed or
--   a message deleted before anyone looks.
-- * Remove — the host takes someone out of their room, and that student can't
--   rejoin it with the code.
-- ============================================================

-- ── Blocks ──────────────────────────────────────────────────────────────────
create table if not exists user_blocks (
  blocker_id uuid        not null references auth.users(id) on delete cascade,
  blocked_id uuid        not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table user_blocks enable row level security;
drop policy if exists user_blocks_own on user_blocks;
create policy user_blocks_own on user_blocks for all to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

revoke all on user_blocks from anon;
revoke insert, update, delete on user_blocks from authenticated;
grant insert (blocker_id, blocked_id), delete on user_blocks to authenticated;

-- ── Reports ─────────────────────────────────────────────────────────────────
create table if not exists room_reports (
  id           uuid        primary key default gen_random_uuid(),
  reporter_id  uuid        not null references auth.users(id) on delete cascade,
  reported_id  uuid        not null references auth.users(id) on delete cascade,
  room_id      uuid        references study_rooms(id) on delete set null,
  message_id   uuid        references room_messages(id) on delete set null,
  message_body text,
  reason       text        not null
                           check (reason in ('spam', 'harassment', 'inappropriate', 'other')),
  details      text        check (details is null or char_length(details) <= 500),
  status       text        not null default 'open'
                           check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);

create index if not exists room_reports_open_idx
  on room_reports (created_at desc) where status = 'open';

alter table room_reports enable row level security;
-- A reporter can see what they filed; nobody else can see reports at all
-- through the API. Review happens in the dashboard.
drop policy if exists room_reports_own on room_reports;
create policy room_reports_own on room_reports for select to authenticated
  using (reporter_id = auth.uid());
revoke all on room_reports from anon;
revoke insert, update, delete on room_reports from authenticated;

create or replace function public.report_room_user(
  p_room_id     uuid,
  p_reported_id uuid,
  p_reason      text,
  p_message_id  uuid default null,
  p_details     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_body text;
begin
  if v_uid is null then
    raise exception 'Sign in to report.';
  end if;
  if p_reported_id = v_uid then
    raise exception 'You can''t report yourself.';
  end if;
  if p_reason not in ('spam', 'harassment', 'inappropriate', 'other') then
    raise exception 'Pick a reason for the report.';
  end if;
  -- Only someone in the room saw what happened there.
  if not exists (select 1 from room_members
                  where room_id = p_room_id and user_id = v_uid) then
    raise exception 'You can only report someone in a room you''re in.';
  end if;

  if p_message_id is not null then
    select body into v_body from room_messages
     where id = p_message_id and room_id = p_room_id and user_id = p_reported_id;
    if not found then
      raise exception 'That message isn''t in this room.';
    end if;
  end if;

  -- One open report per reporter, person and message is enough.
  if exists (select 1 from room_reports
              where reporter_id = v_uid and reported_id = p_reported_id
                and message_id is not distinct from p_message_id
                and status = 'open') then
    return;
  end if;

  insert into room_reports
    (reporter_id, reported_id, room_id, message_id, message_body, reason, details)
  values
    (v_uid, p_reported_id, p_room_id, p_message_id, v_body, p_reason,
     nullif(left(btrim(coalesce(p_details, '')), 500), ''));
end $$;

-- ── Host removal ────────────────────────────────────────────────────────────
create table if not exists room_bans (
  room_id   uuid        not null references study_rooms(id) on delete cascade,
  user_id   uuid        not null references auth.users(id) on delete cascade,
  banned_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table room_bans enable row level security;
-- No policies: read and written only by the RPCs below.
revoke all on room_bans from anon, authenticated;

create or replace function public.remove_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (select 1 from study_rooms
                  where id = p_room_id and created_by = v_uid and status = 'active') then
    raise exception 'Only the host can remove someone.';
  end if;
  if p_user_id = v_uid then
    raise exception 'Close the room instead of removing yourself.';
  end if;

  delete from room_members where room_id = p_room_id and user_id = p_user_id;
  if not found then
    raise exception 'They''re not in this room.';
  end if;

  insert into room_bans (room_id, user_id) values (p_room_id, p_user_id)
  on conflict do nothing;
end $$;

-- join_room_by_code from 0011, plus the ban check.
create or replace function public.join_room_by_code(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  study_rooms;
  v_count int;
begin
  if v_uid is null then
    raise exception 'Sign in to join a study room.';
  end if;

  select * into v_room from study_rooms
   where invite_code = upper(btrim(coalesce(p_code, '')))
     and status = 'active'
   for update;

  if not found then
    raise exception 'No open room has that code.';
  end if;

  if exists (select 1 from room_bans
              where room_id = v_room.id and user_id = v_uid) then
    raise exception 'The host removed you from this room.';
  end if;

  if exists (select 1 from room_members
              where room_id = v_room.id and user_id = v_uid) then
    return row_to_json(v_room);
  end if;

  select count(*) into v_count from room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'This room is full.';
  end if;

  insert into room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'member');

  return row_to_json(v_room);
end $$;

revoke execute on function public.report_room_user(uuid, uuid, text, uuid, text),
                           public.remove_room_member(uuid, uuid),
                           public.join_room_by_code(text)
  from public, anon;
grant execute on function public.report_room_user(uuid, uuid, text, uuid, text),
                          public.remove_room_member(uuid, uuid),
                          public.join_room_by_code(text)
  to authenticated;
-- ============================================================
-- 0014  Weak topics: find the units a student keeps getting
--       wrong, so practice can target them.
-- ============================================================
--
-- The evidence was mostly there already: every flashcard carries its source
-- chunk and its last grade, and every quiz answer is marked right or wrong.
-- What was missing is which unit a quiz question tested — generate-quiz now
-- records it, from the excerpt the question was written from. Questions
-- generated before this migration have no unit and simply don't count.
-- ============================================================

alter table quizzes
  add column if not exists material_id uuid references materials(id) on delete set null;

alter table quiz_questions
  add column if not exists unit_label text,
  add column if not exists source_chunk_id uuid references material_chunks(id) on delete set null;

-- Units ranked by how often the student gets them wrong.
--
-- A topic is (material, unit label); a file with no unit headings at all is
-- one topic, with a null label. Evidence is one row per answered quiz
-- question and one per reviewed flashcard; a miss is a wrong answer or a card
-- whose last grade was "again" or "hard". The chunk's own unit label is
-- preferred over the one the model copied, so a quiz and a deck from the same
-- section land on the same topic.
--
-- Security invoker: every table read here is owner-scoped by RLS, and each
-- branch also filters on auth.uid() explicitly.
create or replace function public.get_weak_topics(p_limit int default 5)
returns table (
  material_id      uuid,
  material_title   text,
  unit_label       text,
  answered         int,
  correct          int,
  cards_reviewed   int,
  cards_struggling int,
  miss_rate        numeric
)
language sql
stable
set search_path = public
as $$
  with evidence as (
    select coalesce(c.material_id, q.material_id)  as material_id,
           coalesce(c.unit_label, qq.unit_label)   as unit_label,
           1                                       as answered,
           case when qa.is_correct then 1 else 0 end as correct,
           0                                       as reviewed,
           0                                       as struggling
      from quiz_answers qa
      join quiz_questions qq on qq.id = qa.question_id
      join quizzes q         on q.id = qq.quiz_id
      left join material_chunks c on c.id = qq.source_chunk_id
     where qa.user_id = auth.uid()
    union all
    select c.material_id,
           coalesce(c.unit_label, f.unit_label),
           0, 0, 1,
           case when f.last_grade in ('again', 'hard') then 1 else 0 end
      from flashcards f
      join material_chunks c on c.id = f.source_chunk_id
     where f.user_id = auth.uid()
       and f.last_grade is not null
  ),
  topics as (
    select e.material_id,
           e.unit_label,
           sum(e.answered)::int   as answered,
           sum(e.correct)::int    as correct,
           sum(e.reviewed)::int   as cards_reviewed,
           sum(e.struggling)::int as cards_struggling
      from evidence e
     where e.material_id is not null
     group by e.material_id, e.unit_label
  )
  select t.material_id,
         m.title,
         t.unit_label,
         t.answered,
         t.correct,
         t.cards_reviewed,
         t.cards_struggling,
         round(((t.answered - t.correct) + t.cards_struggling)::numeric
               / (t.answered + t.cards_reviewed), 2) as miss_rate
    from topics t
    join materials m on m.id = t.material_id
   -- Two pieces of evidence at least, and wrong a third of the time or more:
   -- one unlucky answer isn't a weak topic.
   where t.answered + t.cards_reviewed >= 2
     and ((t.answered - t.correct) + t.cards_struggling)::numeric
         / (t.answered + t.cards_reviewed) >= 0.34
   order by miss_rate desc, t.answered + t.cards_reviewed desc
   limit greatest(1, least(p_limit, 20));
$$;

revoke execute on function public.get_weak_topics(int) from public, anon;
grant execute on function public.get_weak_topics(int) to authenticated;
-- ============================================================
-- 0015  Catch-up planner, and closing an XP-farming hole in
--       daily_tasks.
-- ============================================================

-- ── 1. Security: daily_tasks UPDATE ─────────────────────────────────────────
-- 0008 narrowed INSERT on daily_tasks and said `done` and `rewarded_at`
-- belong to complete_task, but never revoked UPDATE. Verified on the hosted
-- project on 2026-10-01: a client could PATCH a ticked task back to
-- `done = false, rewarded_at = null` and tick it again through complete_task,
-- earning 15 XP every loop (15 → 30 in the probe). The app itself never
-- updates this table directly, so the grant goes down to the harmless columns.
revoke update on daily_tasks from anon, authenticated;
grant update (title, duration_min, scheduled_date) on daily_tasks to authenticated;

-- Shared catalogues: their row policies are read-only, so writes were already
-- refused, but nothing should rely on a missing policy alone.
revoke insert, update, delete on badges, classes, xp_rules from anon, authenticated;

-- ── 2. When the roadmap started ─────────────────────────────────────────────
-- Pace needs a start date and nothing recorded one. generate-roadmap sets it
-- from now on; existing roadmaps fall back to when the goal was created.
alter table goals add column if not exists roadmap_started_on date;

-- ── 3. Pace ─────────────────────────────────────────────────────────────────
-- Both functions take the student's own date. The database clock is UTC, so
-- between midnight and 05:30 in India `current_date` is still yesterday — and
-- Home lists tasks by the phone's date, so anything scheduled by the server's
-- "today" in that window would never appear. A date more than a day from the
-- server's is refused rather than trusted.
drop function if exists public.get_roadmap_pace(uuid);
drop function if exists public.plan_catch_up(uuid, int);

-- Where the student stands against a straight-line schedule from the roadmap's
-- start to the exam: how many topics should be done by today, how many are,
-- and how many a day finishes the rest in time. Security invoker: it reads
-- only the caller's own rows, and a goal that isn't theirs is simply missing.
create or replace function public.get_roadmap_pace(
  p_goal  uuid,
  p_today date default current_date
)
returns json
language plpgsql
stable
set search_path = public
as $$
declare
  v_goal      goals;
  v_start     date;
  v_end       date;
  v_weeks     int;
  v_total     int;
  v_done      int;
  v_span      int;
  v_elapsed   int;
  v_expected  int;
  v_days_left int;
  v_overdue   int;
  v_today     date := coalesce(p_today, current_date);
begin
  if v_today not between current_date - 1 and current_date + 1 then
    raise exception 'Your phone''s date looks wrong. Check it and try again.';
  end if;

  select * into v_goal from goals where id = p_goal;
  if not found then
    raise exception 'That goal isn''t yours.';
  end if;

  select count(*) into v_weeks from milestones where goal_id = p_goal;
  select count(*), count(*) filter (where t.done)
    into v_total, v_done
    from milestone_tasks t
    join milestones m on m.id = t.milestone_id
   where m.goal_id = p_goal;

  select count(*) into v_overdue
    from daily_tasks
   where goal_id = p_goal and not done and scheduled_date < v_today;

  if v_total = 0 then
    return json_build_object('has_roadmap', false, 'overdue', v_overdue);
  end if;

  v_start := coalesce(v_goal.roadmap_started_on, v_goal.created_at::date);
  -- The plan ends at the exam, or after its last week when there's no date.
  v_end := coalesce(v_goal.exam_date, v_start + v_weeks * 7);
  v_span := greatest(1, v_end - v_start);
  v_elapsed := least(v_span, greatest(0, v_today - v_start + 1));
  v_expected := least(v_total, round(v_total::numeric * v_elapsed / v_span)::int);
  v_days_left := greatest(1, v_end - v_today);

  return json_build_object(
    'has_roadmap', true,
    'total', v_total,
    'done', v_done,
    'expected', v_expected,
    'behind', greatest(0, v_expected - v_done),
    'days_left', v_days_left,
    'per_day', least(10, greatest(1, ceil((v_total - v_done)::numeric / v_days_left)::int)),
    'overdue', v_overdue,
    'current_week', least(v_weeks, greatest(1, (v_today - v_start) / 7 + 1)),
    'weeks', v_weeks
  );
end $$;

-- ── 4. Catch up ─────────────────────────────────────────────────────────────
-- Rebuilds the next few days of the student's checklist at the pace the exam
-- now needs:
--   * unfinished tasks from past days move to today — until now they dropped
--     off Home (which shows today only) and "Plan day" never offered them
--     again, because it skips anything already scheduled on any date;
--   * the rest of the roadmap, in order, fills each of the next p_days days up
--     to the per-day pace from get_roadmap_pace.
-- Security invoker: every write is one the student may make themselves
-- (insert into daily_tasks, update scheduled_date), under RLS.
create or replace function public.plan_catch_up(
  p_goal  uuid,
  p_days  int  default 7,
  p_today date default current_date
)
returns json
language plpgsql
set search_path = public
as $$
declare
  v_pace      json;
  v_per_day   int;
  v_moved     int;
  v_scheduled int := 0;
  v_day       date;
  v_room      int;
  v_task      record;
  v_today     date := coalesce(p_today, current_date);
begin
  v_pace := public.get_roadmap_pace(p_goal, v_today);
  if not (v_pace ->> 'has_roadmap')::boolean then
    raise exception 'Generate a roadmap for this goal first.';
  end if;
  v_per_day := (v_pace ->> 'per_day')::int;

  update daily_tasks
     set scheduled_date = v_today
   where goal_id = p_goal and not done and scheduled_date < v_today;
  get diagnostics v_moved = row_count;

  for d in 0 .. greatest(1, least(p_days, 14)) - 1 loop
    v_day := v_today + d;
    select v_per_day - count(*) into v_room
      from daily_tasks
     where goal_id = p_goal and scheduled_date = v_day and not done;
    continue when v_room <= 0;

    for v_task in
      select t.id, t.name
        from milestone_tasks t
        join milestones m on m.id = t.milestone_id
       where m.goal_id = p_goal
         and not t.done
         and not exists (select 1 from daily_tasks dt
                          where dt.milestone_task_id = t.id and not dt.done)
       order by m.order_index, t.order_index
       limit v_room
    loop
      insert into daily_tasks (user_id, goal_id, milestone_task_id, title, scheduled_date)
      values (auth.uid(), p_goal, v_task.id, v_task.name, v_day);
      v_scheduled := v_scheduled + 1;
    end loop;
  end loop;

  return json_build_object(
    'per_day', v_per_day,
    'moved', v_moved,
    'scheduled', v_scheduled,
    'days_left', (v_pace ->> 'days_left')::int
  );
end $$;

revoke execute on function public.get_roadmap_pace(uuid, date),
                           public.plan_catch_up(uuid, int, date)
  from public, anon;
grant execute on function public.get_roadmap_pace(uuid, date),
                          public.plan_catch_up(uuid, int, date)
  to authenticated;
-- ============================================================
-- 0016  Previous-year exam papers: which topics get asked, how
--       often, and for how many marks.
-- ============================================================
--
-- A paper is uploaded like a material but kept apart from them on purpose:
-- it is questions, not notes, and embedding it would make Trail AI cite an
-- exam paper as if it were an explanation. `analyze-paper` reads it with
-- Gemini, extracts each question with its marks, and tags it with one of the
-- student's own syllabus units.
--
-- Nothing here pays XP, so the owner may read and write these rows directly,
-- the same as flashcard decks.
-- ============================================================

create table if not exists exam_papers (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        not null references auth.users(id) on delete cascade,
  goal_id        uuid        references goals(id) on delete set null,
  title          text        not null,
  year           int         check (year is null or year between 1990 and 2100),
  storage_path   text        not null,
  status         text        not null default 'pending'
                             check (status in ('pending', 'analyzing', 'analyzed', 'failed')),
  question_count int         not null default 0,
  error          text,
  created_at     timestamptz not null default now()
);
create index if not exists exam_papers_user_idx on exam_papers(user_id);

create table if not exists paper_questions (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  paper_id    uuid        not null references exam_papers(id) on delete cascade,
  question_no text,
  text        text        not null check (char_length(text) <= 4000),
  marks       numeric(5,1) check (marks is null or marks between 0 and 100),
  unit_label  text,
  created_at  timestamptz not null default now()
);
create index if not exists paper_questions_paper_idx on paper_questions(paper_id);
create index if not exists paper_questions_user_unit_idx on paper_questions(user_id, unit_label);

alter table exam_papers     enable row level security;
alter table paper_questions enable row level security;

drop policy if exists exam_papers_own on exam_papers;
create policy exam_papers_own on exam_papers for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A question may only hang off one of the caller's own papers.
drop policy if exists paper_questions_own on paper_questions;
create policy paper_questions_own on paper_questions for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from exam_papers p
                 where p.id = paper_id and p.user_id = auth.uid())
  );

revoke all on exam_papers, paper_questions from anon;

-- Topics ranked by how often past papers ask about them.
create or replace function public.get_exam_topics(p_limit int default 20)
returns table (
  unit_label  text,
  times_asked int,
  total_marks numeric,
  years       int[],
  papers      int,
  example     text
)
language sql
stable
set search_path = public
as $$
  select coalesce(q.unit_label, 'Other')                          as unit_label,
         count(*)::int                                            as times_asked,
         coalesce(sum(q.marks), 0)                                as total_marks,
         array_remove(array_agg(distinct p.year order by p.year), null) as years,
         count(distinct q.paper_id)::int                          as papers,
         (array_agg(q.text order by q.marks desc nulls last))[1]  as example
    from paper_questions q
    join exam_papers p on p.id = q.paper_id
   where q.user_id = auth.uid()
     and p.status = 'analyzed'
   group by coalesce(q.unit_label, 'Other')
   order by times_asked desc, total_marks desc
   limit greatest(1, least(p_limit, 50));
$$;

revoke execute on function public.get_exam_topics(int) from public, anon;
grant execute on function public.get_exam_topics(int) to authenticated;
-- ============================================================
-- 0017  Long-answer practice: a written answer to a 5- or 10-mark
--       question, graded against the student's own notes.
-- ============================================================
--
-- Deliberately pays no XP. An AI grade can be argued with, retried, or gamed
-- by pasting the notes back in; XP stays tied to things the server can
-- verify (0008). What a student gets here is feedback, kept so they can see
-- themselves improve on a topic.
-- ============================================================

create table if not exists answer_attempts (
  id          uuid         primary key default gen_random_uuid(),
  user_id     uuid         not null references auth.users(id) on delete cascade,
  question_id uuid         references paper_questions(id) on delete set null,
  question    text         not null check (char_length(question) <= 4000),
  unit_label  text,
  max_marks   numeric(5,1) not null check (max_marks between 1 and 100),
  answer      text         not null check (char_length(answer) between 1 and 12000),
  score       numeric(5,1) not null check (score >= 0),
  feedback    jsonb        not null default '{}'::jsonb,
  created_at  timestamptz  not null default now(),
  check (score <= max_marks)
);
create index if not exists answer_attempts_user_idx
  on answer_attempts(user_id, created_at desc);

alter table answer_attempts enable row level security;
drop policy if exists answer_attempts_own on answer_attempts;
create policy answer_attempts_own on answer_attempts for select to authenticated
  using (user_id = auth.uid());
drop policy if exists answer_attempts_delete_own on answer_attempts;
create policy answer_attempts_delete_own on answer_attempts for delete to authenticated
  using (user_id = auth.uid());

-- Written only by grade-answer, which holds the grade: a score the client
-- could insert would be a score the client chose.
revoke all on answer_attempts from anon;
revoke insert, update on answer_attempts from authenticated;
-- ============================================================
-- 0018  An exam date per subject.
-- ============================================================
--
-- A semester is several exams on different days, not one. The goal stays the
-- whole exam season; each subject can carry the date of its own paper, and
-- the goal's date follows the last of them so pace (0015) and the roadmap
-- cover every exam.
-- ============================================================

alter table subjects add column if not exists exam_date date;

-- The student's own column to set, next to the ones 0008 already grants.
grant update (exam_date) on subjects to authenticated;
grant insert (exam_date) on subjects to authenticated;

-- Keep goals.exam_date at the latest subject exam. Only ever moves it later:
-- clearing a subject's date shouldn't shorten a goal the student dated
-- themselves.
create or replace function app_private.extend_goal_to_last_exam()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.exam_date is not null and new.goal_id is not null then
    update goals
       set exam_date = new.exam_date
     where id = new.goal_id
       and (exam_date is null or exam_date < new.exam_date);
  end if;
  return null;
end $$;

drop trigger if exists subjects_extend_goal on subjects;
create trigger subjects_extend_goal
  after insert or update of exam_date on subjects
  for each row execute function app_private.extend_goal_to_last_exam();
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
-- StudyTrail — 0020: hardening
--
-- Four fixes from REVIEW.md, none of which adds a feature:
--   1. Study-room channels are private: only a room's members can join, hear
--      or send on `room:<id>` (Realtime Authorization on realtime.messages).
--   2. Someone who leaves a room mid-quiz stops holding the quiz up.
--   3. Streaks and daily caps follow the student's own day, not UTC's — in
--      India the server's "today" used to change at 05:30.
--   4. Chat turns are written by the `chat` function only. A client could
--      insert or edit its own "AI" turns and count towards curious_learner.
--
-- Idempotent, like every migration here.

-- ── 1. Private room channels ────────────────────────────────────────────────
-- realtime.topic() is the channel name the client joined. The app's only
-- channel is `room:<room id>`; anything else is refused. CASE (not AND) so the
-- uuid cast never runs on a topic that isn't one.
create or replace function public.is_room_channel_member(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_topic ~ '^room:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then exists (select 1 from room_members
                    where room_id = substr(p_topic, 6)::uuid
                      and user_id = auth.uid())
    else false
  end;
$$;

revoke execute on function public.is_room_channel_member(text) from public, anon;
grant execute on function public.is_room_channel_member(text) to authenticated;

-- Receiving broadcast and presence on a private channel needs SELECT; sending
-- and tracking presence needs INSERT. Postgres changes on room_messages are
-- still filtered by that table's own RLS.
drop policy if exists room_channel_receive on realtime.messages;
create policy room_channel_receive on realtime.messages
  for select to authenticated
  using (public.is_room_channel_member(realtime.topic()));

drop policy if exists room_channel_send on realtime.messages;
create policy room_channel_send on realtime.messages
  for insert to authenticated
  with check (public.is_room_channel_member(realtime.topic()));

-- ── 2. Leaving a room mid-quiz ──────────────────────────────────────────────
-- While voting, a leaver is no longer asked: if everyone left has agreed the
-- quiz starts, and under two players it is cancelled. While running, a leaver
-- who hadn't handed in is dropped, and if everyone left has handed in the quiz
-- finishes. A host leaving closes the room, so a vote is cancelled outright.
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

drop trigger if exists room_members_quiz_leave on room_members;
create trigger room_members_quiz_leave
  after delete on room_members
  for each row execute function app_private.room_quiz_on_leave();

-- ── 3. The student's own day ────────────────────────────────────────────────
-- Minutes east of UTC, sent by the app at sign-in. 330 (India) until it is.
alter table profiles
  add column if not exists utc_offset_min smallint not null default 330;
do $$ begin
  alter table profiles add constraint profiles_utc_offset_range
    check (utc_offset_min between -720 and 840);
exception when duplicate_object then null; end $$;

create or replace function app_private.local_date(p_user uuid, p_at timestamptz)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select (p_at + make_interval(mins => coalesce(
            (select utc_offset_min from profiles where id = p_user), 330)))::date;
$$;

create or replace function app_private.local_today(p_user uuid)
returns date
language sql
stable
security definer
set search_path = public, app_private
as $$
  select app_private.local_date(p_user, now());
$$;

-- The phone's offset from UTC. Not a client-writable column: the range check
-- lives here and in the constraint, and nothing else about a profile changes.
create or replace function public.set_utc_offset(p_minutes int)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_minutes is null or p_minutes not between -720 and 840 then
    raise exception 'That is not a time zone.';
  end if;
  update profiles set utc_offset_min = p_minutes where id = auth.uid();
end $$;

revoke execute on function public.set_utc_offset(int) from public, anon;
grant execute on function public.set_utc_offset(int) to authenticated;
revoke execute on function app_private.local_date(uuid, timestamptz) from public;
revoke execute on function app_private.local_today(uuid) from public;

-- Every reward path logs through this, so the streak, the activity heatmap
-- and the weekly totals all move to the student's day here. Otherwise
-- unchanged from 0012.
create or replace function app_private.log_activity(
  p_user    uuid,
  p_minutes int default 0,
  p_tasks   int default 0,
  p_xp      int default 0
)
returns activity_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := app_private.local_today(p_user);
  v_row     activity_log;
  v_last    date;
  v_cur     int;
  v_missed  int;
  v_freezes int;
begin
  insert into activity_log (user_id, activity_date, minutes_studied,
                            tasks_completed, xp_earned)
  values (p_user, v_today, greatest(0, p_minutes), greatest(0, p_tasks),
          greatest(0, p_xp))
  on conflict (user_id, activity_date) do update
    set minutes_studied = activity_log.minutes_studied + greatest(0, p_minutes),
        tasks_completed = activity_log.tasks_completed + greatest(0, p_tasks),
        xp_earned       = activity_log.xp_earned + greatest(0, p_xp)
  returning * into v_row;

  -- Roll the streak: same day = no-op, yesterday = +1, a gap covered by
  -- freezes = +1 (freezes spent), anything else = reset to 1.
  select last_active_date, current_streak
    into v_last, v_cur
    from streaks where user_id = p_user;

  if found and v_last is distinct from v_today then
    if v_last = v_today - 1 then
      v_cur := coalesce(v_cur, 0) + 1;
    else
      v_missed := v_today - v_last - 1;   -- null when never active
      select count(*) into v_freezes from reward_redemptions
       where user_id = p_user and reward_key = 'streak_freeze'
         and consumed_at is null;

      if v_missed between 1 and v_freezes and coalesce(v_cur, 0) > 0 then
        for i in 1..v_missed loop
          update reward_redemptions
             set consumed_at = now(), consumed_for = v_last + i
           where id = (select id from reward_redemptions
                        where user_id = p_user and reward_key = 'streak_freeze'
                          and consumed_at is null
                        order by redeemed_at
                        limit 1);
        end loop;
        v_cur := v_cur + 1;
      else
        v_cur := 1;
      end if;
    end if;

    update streaks
      set current_streak   = v_cur,
          best_streak      = greatest(best_streak, v_cur),
          last_active_date = v_today
      where user_id = p_user;
  end if;

  return v_row;
end $$;

-- The 16-hour daily focus cap counts the student's day. Otherwise unchanged
-- from 0008.
create or replace function public.record_focus_session(
  p_subject     uuid default null,
  p_length_min  int  default 25,
  p_focused_min int  default null
)
returns study_sessions
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_focused int;
  v_today   int;
  v_xp      int;
  v_row     study_sessions;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- A focus block longer than three hours isn't a Pomodoro, it's a forged one.
  if p_length_min is null or p_length_min < 1 or p_length_min > 180 then
    raise exception 'length_min must be between 1 and 180, got %', p_length_min
      using errcode = 'check_violation';
  end if;

  v_focused := coalesce(p_focused_min, p_length_min);
  if v_focused < 0 or v_focused > p_length_min then
    raise exception 'focused_min must be between 0 and length_min'
      using errcode = 'check_violation';
  end if;

  -- Parent-ownership check (REVIEW.md P2): a known subject id belonging to
  -- someone else must not become the parent of the caller's session.
  if p_subject is not null
     and not exists (select 1 from subjects
                      where id = p_subject and user_id = v_user) then
    raise exception 'subject % not found', p_subject using errcode = 'no_data_found';
  end if;

  -- Sixteen hours of logged focus in one day is the outer edge of plausible;
  -- past that, stop counting rather than trust the clock the client sent.
  select coalesce(sum(focused_min), 0) into v_today
    from study_sessions
    where user_id = v_user
      and session_date = app_private.local_today(v_user);

  if v_today + v_focused > 960 then
    raise exception 'daily focus limit reached' using errcode = 'check_violation';
  end if;

  insert into study_sessions (user_id, subject_id, session_date, length_min,
                              sessions_count, focused_min, started_at, ended_at)
  values (v_user, p_subject, app_private.local_today(v_user), p_length_min, 1,
          v_focused, now() - make_interval(mins => v_focused), now())
  returning * into v_row;

  v_xp := v_focused * app_private.xp_for('focus_minute');
  perform app_private.log_activity(v_user, v_focused, 0, v_xp);
  perform app_private.award_xp(v_user, v_xp);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- Three paid group quizzes per student's day. Otherwise unchanged from 0019.
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
       and app_private.local_date(v_row.user_id, q.finished_at)
           = app_private.local_today(v_row.user_id);
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

-- ── 4. Chat turns are server-written ────────────────────────────────────────
-- 0008 left these writable "until Phase C moves the write into the chat
-- function". It has: the function verifies the thread is the caller's and
-- writes both turns with the service-role key. Students keep read and delete.
revoke insert, update on chat_messages, chat_citations from anon, authenticated;

notify pgrst, 'reload schema';
-- StudyTrail — 0021: study tools
--
--   1. Explanations in Hindi or Gujarati: `profiles.answer_language`, read by
--      the chat, summarize-material and grade-answer functions.
--   2. A "My mistakes" deck that fills itself: every question a student gets
--      wrong in a quiz — their own or a room's — becomes a flashcard, due now.
--   3. A weekly report: this week against last, in the student's own days.
--
-- Idempotent, like every migration here.

-- ── 1. Answer language ──────────────────────────────────────────────────────
alter table profiles
  add column if not exists answer_language text not null default 'en';
do $$ begin
  alter table profiles add constraint profiles_answer_language_check
    check (answer_language in ('en', 'hi', 'gu'));
exception when duplicate_object then null; end $$;

grant update (answer_language) on profiles to authenticated;

-- ── 2. My mistakes ──────────────────────────────────────────────────────────
alter table flashcard_decks
  add column if not exists is_mistakes boolean not null default false;
create unique index if not exists flashcard_decks_one_mistakes
  on flashcard_decks(user_id) where is_mistakes;

-- 'quiz:<question id>' or 'room:<question id>'. Getting the same question
-- wrong again makes its card due now instead of adding a second one.
alter table flashcards add column if not exists mistake_key text;
create unique index if not exists flashcards_mistake_key
  on flashcards(user_id, mistake_key) where mistake_key is not null;

create or replace function app_private.mistakes_deck(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deck uuid;
begin
  select id into v_deck from flashcard_decks
   where user_id = p_user and is_mistakes;
  if v_deck is null then
    insert into flashcard_decks (user_id, name, is_mistakes)
    values (p_user, 'My mistakes', true)
    on conflict (user_id) where is_mistakes do nothing
    returning id into v_deck;
    if v_deck is null then
      select id into v_deck from flashcard_decks
       where user_id = p_user and is_mistakes;
    end if;
  end if;
  return v_deck;
end $$;

create or replace function app_private.add_mistake(
  p_user        uuid,
  p_key         text,
  p_question    text,
  p_options     text[],
  p_correct     int,
  p_explanation text,
  p_unit        text,
  p_chunk       uuid
)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  if p_correct is null or p_correct not between 0 and 3 then
    return;
  end if;
  insert into flashcards (user_id, deck_id, unit_label, front, back,
                          source_chunk_id, mistake_key, due_at)
  values (p_user, app_private.mistakes_deck(p_user), p_unit, p_question,
          'Answer: ' || p_options[p_correct + 1]
            || coalesce(E'\n\n' || nullif(btrim(p_explanation), ''), ''),
          p_chunk, p_key, now())
  on conflict (user_id, mistake_key) where mistake_key is not null
  do update set due_at = least(flashcards.due_at, now());
end $$;

-- Solo quizzes: quiz_answers is written only by finish_quiz_attempt.
create or replace function app_private.quiz_answer_mistake()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_q quiz_questions;
begin
  if new.is_correct is distinct from false then
    return new;
  end if;
  select * into v_q from quiz_questions where id = new.question_id;
  if found then
    perform app_private.add_mistake(new.user_id, 'quiz:' || v_q.id, v_q.question,
      v_q.options, v_q.correct_index, v_q.explanation, v_q.unit_label,
      v_q.source_chunk_id);
  end if;
  return new;
end $$;

drop trigger if exists quiz_answers_mistakes on quiz_answers;
create trigger quiz_answers_mistakes
  after insert on quiz_answers
  for each row execute function app_private.quiz_answer_mistake();

-- Group quizzes: once the quiz is over — not at hand-in, which would put the
-- answers in a deck while others are still answering (D-031) — each question
-- every player who handed in missed or left.
create or replace function app_private.room_quiz_mistakes()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_row record;
begin
  for v_row in
    select pl.user_id, q.*
      from room_quiz_players pl
      join room_quiz_questions q on q.room_quiz_id = pl.room_quiz_id
     where pl.room_quiz_id = new.id
       and pl.submitted_at is not null
       and nullif(pl.picks ->> q.id::text, '')::int is distinct from q.correct_index
  loop
    perform app_private.add_mistake(v_row.user_id, 'room:' || v_row.id,
      v_row.question, v_row.options, v_row.correct_index, v_row.explanation,
      null, null);
  end loop;
  return new;
end $$;

drop trigger if exists room_quiz_players_mistakes on room_quiz_players;
drop trigger if exists room_quizzes_mistakes on room_quizzes;
create trigger room_quizzes_mistakes
  after update of status on room_quizzes
  for each row
  when (new.status = 'finished' and old.status is distinct from 'finished')
  execute function app_private.room_quiz_mistakes();

revoke execute on function app_private.mistakes_deck(uuid) from public;
revoke execute on function app_private.add_mistake(uuid, text, text, text[], int, text, text, uuid) from public;

-- ── 3. Weekly report ────────────────────────────────────────────────────────
-- Totals for [p_from, p_to] in the student's own days ([p_off] minutes east
-- of UTC).
create or replace function app_private.week_totals(
  p_user uuid, p_from date, p_to date, p_off int
)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'minutes', coalesce((select sum(minutes_studied) from activity_log
                          where user_id = p_user
                            and activity_date between p_from and p_to), 0),
    'xp', coalesce((select sum(xp_earned) from activity_log
                     where user_id = p_user
                       and activity_date between p_from and p_to), 0),
    'tasks', coalesce((select sum(tasks_completed) from activity_log
                        where user_id = p_user
                          and activity_date between p_from and p_to), 0),
    'active_days', (select count(*) from activity_log
                     where user_id = p_user
                       and activity_date between p_from and p_to
                       and (minutes_studied > 0 or tasks_completed > 0
                            or xp_earned > 0)),
    'quizzes', (select count(*) from quiz_attempts
                 where user_id = p_user and completed_at is not null
                   and (completed_at + make_interval(mins => p_off))::date
                       between p_from and p_to),
    'quiz_correct', coalesce((select sum(score) from quiz_attempts
                               where user_id = p_user and completed_at is not null
                                 and (completed_at + make_interval(mins => p_off))::date
                                     between p_from and p_to), 0),
    'quiz_total', coalesce((select sum(total) from quiz_attempts
                             where user_id = p_user and completed_at is not null
                               and (completed_at + make_interval(mins => p_off))::date
                                   between p_from and p_to), 0),
    'group_quizzes', (select count(*) from room_quiz_players
                       where user_id = p_user and submitted_at is not null
                         and (submitted_at + make_interval(mins => p_off))::date
                             between p_from and p_to),
    'podiums', (select count(*) from room_quiz_players pl
                 where pl.user_id = p_user and pl.rank between 1 and 3
                   and (pl.submitted_at + make_interval(mins => p_off))::date
                       between p_from and p_to
                   -- A podium of one isn't one.
                   and (select count(*) from room_quiz_players o
                         where o.room_quiz_id = pl.room_quiz_id
                           and o.submitted_at is not null) >= 2),
    'answers', (select count(*) from answer_attempts
                 where user_id = p_user
                   and (created_at + make_interval(mins => p_off))::date
                       between p_from and p_to),
    'answer_percent', (select round(avg(score / max_marks) * 100)
                         from answer_attempts
                        where user_id = p_user
                          and (created_at + make_interval(mins => p_off))::date
                              between p_from and p_to)
  );
$$;

-- The last seven days (today included) against the seven before, a day-by-day
-- series, and per-unit quiz accuracy with last week's for comparison.
create or replace function public.get_weekly_report()
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_user  uuid := auth.uid();
  v_off   int;
  v_today date;
  v_from  date;
  v_prev  date;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select coalesce(utc_offset_min, 330) into v_off from profiles where id = v_user;
  v_off   := coalesce(v_off, 330);
  v_today := (now() + make_interval(mins => v_off))::date;
  v_from  := v_today - 6;
  v_prev  := v_from - 7;

  return json_build_object(
    'from', v_from,
    'to', v_today,
    'this_week', app_private.week_totals(v_user, v_from, v_today, v_off),
    'last_week', app_private.week_totals(v_user, v_prev, v_from - 1, v_off),
    'days', (
      select json_agg(json_build_object(
               'date', d::date,
               'minutes', coalesce(a.minutes_studied, 0),
               'xp', coalesce(a.xp_earned, 0)) order by d)
        from generate_series(v_from::timestamp, v_today::timestamp,
                             interval '1 day') d
        left join activity_log a
          on a.user_id = v_user and a.activity_date = d::date),
    'units', (
      select coalesce(json_agg(u order by u.correct::float / u.answered,
                                         u.unit_label), '[]'::json)
        from (
          select q.unit_label,
                 count(*) filter (where t.day >= v_from) as answered,
                 count(*) filter (where t.day >= v_from and a.is_correct) as correct,
                 count(*) filter (where t.day < v_from) as answered_before,
                 count(*) filter (where t.day < v_from and a.is_correct) as correct_before
            from quiz_answers a
            join (select id, (completed_at + make_interval(mins => v_off))::date as day
                    from quiz_attempts
                   where user_id = v_user and completed_at is not null) t
              on t.id = a.attempt_id
            join quiz_questions q on q.id = a.question_id
           where a.user_id = v_user
             and q.unit_label is not null
             and t.day between v_prev and v_today
           group by q.unit_label
          having count(*) filter (where t.day >= v_from) > 0
        ) u),
    'streak', (select json_build_object('current', current_streak,
                                        'best', best_streak)
                 from streaks where user_id = v_user),
    'mistakes_due', (select count(*) from flashcards c
                       join flashcard_decks d on d.id = c.deck_id
                      where c.user_id = v_user and d.is_mistakes
                        and c.due_at <= now())
  );
end $$;

revoke execute on function app_private.week_totals(uuid, date, date, int) from public;
revoke execute on function public.get_weekly_report() from public, anon;
grant execute on function public.get_weekly_report() to authenticated;

notify pgrst, 'reload schema';
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
-- StudyTrail — 0023: the doubt board
--
-- A class's own Q&A. A student posts a doubt; classmates answer; answers can
-- be upvoted, and the asker marks the one that solved it. The `doubt-ai`
-- function can add one first answer, written from the asker's own notes.
--
-- Everything goes through the RPCs below — the tables have no client grants,
-- the way study rooms work (D-024): each write has a check the client can't
-- be trusted with (same class, own post, a daily limit), and names come from
-- profiles, which are owner-only. Blocks from 0013 apply: a blocked student's
-- doubts and answers are hidden from whoever blocked them.
--
-- Idempotent, like every migration here.

create table if not exists doubts (
  id         uuid        primary key default gen_random_uuid(),
  class_id   uuid        not null references classes(id) on delete cascade,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  subject    text        check (subject is null or char_length(subject) <= 80),
  title      text        not null check (char_length(title) between 5 and 200),
  body       text        check (body is null or char_length(body) <= 4000),
  solved_answer_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists doubts_class_idx on doubts(class_id, created_at desc);

create table if not exists doubt_answers (
  id         uuid        primary key default gen_random_uuid(),
  doubt_id   uuid        not null references doubts(id) on delete cascade,
  -- For an AI answer, the asker whose notes it was written from.
  user_id    uuid        not null references auth.users(id) on delete cascade,
  is_ai      boolean     not null default false,
  body       text        not null check (char_length(body) between 1 and 6000),
  created_at timestamptz not null default now()
);
create index if not exists doubt_answers_doubt_idx on doubt_answers(doubt_id, created_at);
create unique index if not exists doubt_answers_one_ai on doubt_answers(doubt_id) where is_ai;

do $$ begin
  alter table doubts add constraint doubts_solved_fk
    foreign key (solved_answer_id) references doubt_answers(id) on delete set null;
exception when duplicate_object then null; end $$;

create table if not exists doubt_votes (
  answer_id  uuid not null references doubt_answers(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  primary key (answer_id, user_id)
);

create table if not exists doubt_reports (
  id           uuid        primary key default gen_random_uuid(),
  reporter_id  uuid        not null references auth.users(id) on delete cascade,
  reported_id  uuid        not null references auth.users(id) on delete cascade,
  doubt_id     uuid        references doubts(id) on delete set null,
  answer_id    uuid        references doubt_answers(id) on delete set null,
  body         text,
  reason       text        not null
                           check (reason in ('spam', 'harassment', 'inappropriate', 'other')),
  status       text        not null default 'open'
                           check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);

alter table doubts        enable row level security;
alter table doubt_answers enable row level security;
alter table doubt_votes   enable row level security;
alter table doubt_reports enable row level security;
revoke all on doubts, doubt_answers, doubt_votes, doubt_reports
  from anon, authenticated;

-- The caller's class, or an error that says what to do about it.
create or replace function app_private.my_class()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_class uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select class_id into v_class from profiles where id = auth.uid();
  if v_class is null then
    raise exception 'Join your class first — the doubt board is shared with your classmates.';
  end if;
  return v_class;
end $$;

-- A doubt in the caller's class, or an error.
create or replace function app_private.class_doubt(p_doubt uuid)
returns doubts
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_row doubts;
begin
  select * into v_row from doubts
   where id = p_doubt and class_id = app_private.my_class();
  if not found then
    raise exception 'That doubt isn''t on your class''s board.';
  end if;
  return v_row;
end $$;

-- ── Reads ───────────────────────────────────────────────────────────────────
-- The class's board, newest first. p_filter: 'all' | 'open' (not solved) |
-- 'mine'.
create or replace function public.get_class_doubts(
  p_filter text default 'all',
  p_limit  int  default 40
)
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid   uuid := auth.uid();
  v_class uuid := app_private.my_class();
begin
  return coalesce((
    select json_agg(row_to_json(t) order by t.created_at desc)
      from (
        select d.id, d.title, d.subject, d.created_at,
               d.solved_answer_id is not null as solved,
               d.user_id = v_uid as is_mine,
               coalesce(nullif(btrim(pr.full_name), ''), 'Student') as author,
               pr.avatar_initial,
               (select count(*) from doubt_answers a
                 where a.doubt_id = d.id
                   and not exists (select 1 from user_blocks b
                                    where b.blocker_id = v_uid
                                      and b.blocked_id = a.user_id
                                      and not a.is_ai))::int as answers,
               exists (select 1 from doubt_answers a
                        where a.doubt_id = d.id and a.is_ai) as has_ai
          from doubts d
          join profiles pr on pr.id = d.user_id
         where d.class_id = v_class
           and not exists (select 1 from user_blocks b
                            where b.blocker_id = v_uid and b.blocked_id = d.user_id)
           and (p_filter = 'all'
                or (p_filter = 'open' and d.solved_answer_id is null)
                or (p_filter = 'mine' and d.user_id = v_uid))
         order by d.created_at desc
         limit least(greatest(coalesce(p_limit, 40), 1), 100)
      ) t), '[]'::json);
end $$;

-- One doubt with its answers: the solving answer first, then by votes.
create or replace function public.get_doubt(p_doubt uuid)
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid uuid := auth.uid();
  v_d   doubts := app_private.class_doubt(p_doubt);
begin
  return json_build_object(
    'id', v_d.id,
    'title', v_d.title,
    'body', v_d.body,
    'subject', v_d.subject,
    'created_at', v_d.created_at,
    'user_id', v_d.user_id,
    'is_mine', v_d.user_id = v_uid,
    'solved_answer_id', v_d.solved_answer_id,
    'author', (select coalesce(nullif(btrim(full_name), ''), 'Student')
                 from profiles where id = v_d.user_id),
    'avatar_initial', (select avatar_initial from profiles where id = v_d.user_id),
    'answers', (
      select coalesce(json_agg(row_to_json(t)
               order by (t.id = v_d.solved_answer_id) desc, t.votes desc,
                        t.created_at), '[]'::json)
        from (
          select a.id, a.body, a.is_ai, a.created_at, a.user_id,
                 a.user_id = v_uid and not a.is_ai as is_mine,
                 coalesce(nullif(btrim(pr.full_name), ''), 'Student') as author,
                 pr.avatar_initial,
                 (select count(*) from doubt_votes v where v.answer_id = a.id)::int as votes,
                 exists (select 1 from doubt_votes v
                          where v.answer_id = a.id and v.user_id = v_uid) as voted
            from doubt_answers a
            join profiles pr on pr.id = a.user_id
           where a.doubt_id = v_d.id
             and (a.is_ai or not exists (
                   select 1 from user_blocks b
                    where b.blocker_id = v_uid and b.blocked_id = a.user_id))
        ) t)
  );
end $$;

-- ── Writes ──────────────────────────────────────────────────────────────────
create or replace function public.post_doubt(
  p_title   text,
  p_body    text default null,
  p_subject text default null
)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid   uuid := auth.uid();
  v_class uuid := app_private.my_class();
  v_title text := btrim(coalesce(p_title, ''));
  v_id    uuid;
begin
  if char_length(v_title) < 5 then
    raise exception 'Say a bit more in the title — at least 5 characters.';
  end if;
  if char_length(v_title) > 200 or char_length(coalesce(p_body, '')) > 4000 then
    raise exception 'That doubt is too long.';
  end if;
  if (select count(*) from doubts
       where user_id = v_uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'That''s ten doubts today — try again tomorrow.';
  end if;
  insert into doubts (class_id, user_id, title, body, subject)
  values (v_class, v_uid, v_title, nullif(btrim(coalesce(p_body, '')), ''),
          nullif(btrim(coalesce(p_subject, '')), ''))
  returning id into v_id;
  return public.get_doubt(v_id);
end $$;

create or replace function public.answer_doubt(p_doubt uuid, p_body text)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid  uuid := auth.uid();
  v_d    doubts := app_private.class_doubt(p_doubt);
  v_body text := btrim(coalesce(p_body, ''));
begin
  if char_length(v_body) < 2 then
    raise exception 'Write an answer first.';
  end if;
  if char_length(v_body) > 6000 then
    raise exception 'That answer is too long.';
  end if;
  if (select count(*) from doubt_answers
       where user_id = v_uid and not is_ai
         and created_at > now() - interval '1 day') >= 50 then
    raise exception 'That''s a lot of answers for one day — try again tomorrow.';
  end if;
  insert into doubt_answers (doubt_id, user_id, body)
  values (v_d.id, v_uid, v_body);
  return public.get_doubt(v_d.id);
end $$;

-- Toggles the caller's upvote. Not on your own answer.
create or replace function public.vote_doubt_answer(p_answer uuid)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid uuid := auth.uid();
  v_a   doubt_answers;
begin
  select * into v_a from doubt_answers where id = p_answer;
  if not found then
    raise exception 'That answer has gone.';
  end if;
  perform app_private.class_doubt(v_a.doubt_id);
  if v_a.user_id = v_uid and not v_a.is_ai then
    raise exception 'You can''t upvote your own answer.';
  end if;
  delete from doubt_votes where answer_id = p_answer and user_id = v_uid;
  if not found then
    insert into doubt_votes (answer_id, user_id) values (p_answer, v_uid);
  end if;
  return public.get_doubt(v_a.doubt_id);
end $$;

-- The asker marks the answer that solved it; null un-marks.
create or replace function public.mark_doubt_solved(p_doubt uuid, p_answer uuid)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_d doubts := app_private.class_doubt(p_doubt);
begin
  if v_d.user_id <> auth.uid() then
    raise exception 'Only whoever asked can mark it solved.';
  end if;
  if p_answer is not null and not exists (
       select 1 from doubt_answers where id = p_answer and doubt_id = v_d.id) then
    raise exception 'That answer isn''t on this doubt.';
  end if;
  update doubts set solved_answer_id = p_answer where id = v_d.id;
  return public.get_doubt(v_d.id);
end $$;

create or replace function public.delete_doubt(p_doubt uuid)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  delete from doubts where id = p_doubt and user_id = auth.uid();
  if not found then
    raise exception 'You can only delete your own doubt.';
  end if;
end $$;

create or replace function public.delete_doubt_answer(p_answer uuid)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  delete from doubt_answers
   where id = p_answer and user_id = auth.uid() and not is_ai;
  if not found then
    raise exception 'You can only delete your own answer.';
  end if;
end $$;

-- Reports a doubt or an answer, with a snapshot of what was said.
create or replace function public.report_doubt_content(
  p_reason text,
  p_doubt  uuid default null,
  p_answer uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid    uuid := auth.uid();
  v_author uuid;
  v_body   text;
  v_doubt  uuid := p_doubt;
begin
  if p_reason not in ('spam', 'harassment', 'inappropriate', 'other') then
    raise exception 'Pick a reason for the report.';
  end if;
  if p_answer is not null then
    select user_id, body, doubt_id into v_author, v_body, v_doubt
      from doubt_answers where id = p_answer and not is_ai;
  elsif p_doubt is not null then
    select user_id, title || coalesce(E'\n\n' || body, '') into v_author, v_body
      from doubts where id = p_doubt;
  end if;
  if v_author is null then
    raise exception 'There''s nothing there to report.';
  end if;
  perform app_private.class_doubt(v_doubt);
  if v_author = v_uid then
    raise exception 'You can''t report yourself.';
  end if;
  if exists (select 1 from doubt_reports
              where reporter_id = v_uid and status = 'open'
                and doubt_id is not distinct from v_doubt
                and answer_id is not distinct from p_answer) then
    return;
  end if;
  insert into doubt_reports (reporter_id, reported_id, doubt_id, answer_id, body, reason)
  values (v_uid, v_author, v_doubt, p_answer, left(v_body, 6000), p_reason);
end $$;

revoke execute on function app_private.my_class(),
                           app_private.class_doubt(uuid)
  from public;
revoke execute on function public.get_class_doubts(text, int),
                           public.get_doubt(uuid),
                           public.post_doubt(text, text, text),
                           public.answer_doubt(uuid, text),
                           public.vote_doubt_answer(uuid),
                           public.mark_doubt_solved(uuid, uuid),
                           public.delete_doubt(uuid),
                           public.delete_doubt_answer(uuid),
                           public.report_doubt_content(text, uuid, uuid)
  from public, anon;
grant execute on function public.get_class_doubts(text, int),
                          public.get_doubt(uuid),
                          public.post_doubt(text, text, text),
                          public.answer_doubt(uuid, text),
                          public.vote_doubt_answer(uuid),
                          public.mark_doubt_solved(uuid, uuid),
                          public.delete_doubt(uuid),
                          public.delete_doubt_answer(uuid),
                          public.report_doubt_content(text, uuid, uuid)
  to authenticated;

notify pgrst, 'reload schema';
-- StudyTrail — 0024: a YouTube playlist is one library item
--
-- A playlist used to become one `materials` row per video, so a 92-lecture
-- course spent all 20 library slots on its first 20 videos and stopped. Now
-- the playlist is one `material_playlists` row and counts as one item; its
-- videos are still ordinary `video_link` materials (transcript file, chunks,
-- retry, summaries — all unchanged) that point back at it (D-038).
--
-- The video list is stored when the playlist is added. The phone reads the
-- captions (D-037), so an import is only as long-lived as the app; with the
-- list on the server, one the phone couldn't finish — app closed, signal lost
-- — carries on at the next launch, on any device.
--
-- Idempotent, like every migration here.

create table if not exists material_playlists (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null default auth.uid()
                          references auth.users(id) on delete cascade,
  youtube_id  text        not null check (youtube_id ~ '^[A-Za-z0-9_-]{12,64}$'),
  title       text        not null check (char_length(title) between 1 and 300),
  -- The playlist's videos in playlist order, as listed when it was added.
  -- YouTube lists 100 per page; that is the ceiling the app reads.
  video_ids   text[]      not null
                          check (cardinality(video_ids) between 1 and 100),
  -- Videos that won't be read: no captions, private or deleted, or removed
  -- from the playlist by the student. Never retried.
  skipped_ids text[]      not null default '{}'
                          check (cardinality(skipped_ids) <= 100),
  created_at  timestamptz not null default now(),
  unique (user_id, youtube_id)
);
create index if not exists material_playlists_user_idx
  on material_playlists(user_id);

alter table material_playlists enable row level security;
drop policy if exists owner_all on material_playlists;
create policy owner_all on material_playlists
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on material_playlists from anon, authenticated;
grant select, insert, delete on material_playlists to authenticated;
-- After creation only the skip list moves. The video list is what the import
-- was asked for and stays as listed.
grant update (skipped_ids) on material_playlists to authenticated;

alter table materials
  add column if not exists playlist_id uuid
    references material_playlists(id) on delete cascade;
create index if not exists materials_playlist_idx
  on materials(playlist_id) where playlist_id is not null;

-- RLS on `materials` checks the row's own `user_id`, not whose playlist it
-- names. Without this a student could hang a video off a classmate's playlist
-- id — unreadable to them, but deleted along with it. `playlist_id` is set at
-- insert only: 0009's update grant (goal_id, title, status) doesn't include it.
create or replace function app_private.material_playlist_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.playlist_id is not null and not exists (
    select 1 from material_playlists
    where id = new.playlist_id and user_id = new.user_id
  ) then
    raise exception 'playlist % is not yours', new.playlist_id
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists materials_playlist_owner on materials;
create trigger materials_playlist_owner
  before insert or update of playlist_id on materials
  for each row execute function app_private.material_playlist_owner();

notify pgrst, 'reload schema';
-- StudyTrail — 0025: each subject's exam date, set when the goal is made
--
-- The goal form starts with no subjects and asks for every subject's exam
-- date as it is added (D-041). `create_goal` takes those dates as a second
-- array, parallel to the subject names, so the goal and its dated subjects
-- are still written in one transaction (0009). 0018's trigger then moves the
-- goal's own date out to the last paper.
--
-- The old four-argument version is dropped rather than left as an overload:
-- with defaults on both, a call naming only the first four arguments would
-- match either one, and PostgREST refuses an ambiguous call.
--
-- Idempotent, like every migration here.

drop function if exists public.create_goal(text, date, text, text[]);

create or replace function public.create_goal(
  p_name          text,
  p_exam_date     date default null,
  p_pace          text default 'steady',
  p_subjects      text[] default '{}',
  p_subject_dates date[] default '{}'
)
returns goals
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Same bounds as 0009.
  c_max_subjects constant int := 40;
  c_max_name     constant int := 120;

  v_user  uuid := auth.uid();
  v_pace  pace_enum;
  v_name  text := btrim(coalesce(p_name, ''));
  v_goal  goals;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if v_name = '' then
    raise exception 'a goal needs a name' using errcode = '22023';
  end if;
  if length(v_name) > c_max_name then
    raise exception 'goal name is longer than % characters', c_max_name
      using errcode = '22001';
  end if;

  begin
    v_pace := coalesce(nullif(btrim(coalesce(p_pace, '')), ''), 'steady')::pace_enum;
  exception when invalid_text_representation then
    raise exception 'unknown pace %; expected relaxed, steady or intense', p_pace
      using errcode = '22023';
  end;

  update goals
    set is_active = false
    where user_id = v_user and is_active;

  insert into goals (user_id, name, exam_date, pace)
    values (v_user, v_name, p_exam_date, v_pace)
    returning * into v_goal;

  -- unnest() of two arrays pads the shorter with nulls, so a subject without
  -- a date is still created, undated. distinct on lower() keeps the first
  -- "DBMS" the student entered and drops a later "dbms".
  insert into subjects (user_id, goal_id, name, exam_date)
  select v_user, v_goal.id, subject_name, subject_date
  from (
    select distinct on (lower(btrim(s.name)))
           btrim(s.name) as subject_name,
           s.exam_date   as subject_date
    from unnest(coalesce(p_subjects, '{}'::text[]),
                coalesce(p_subject_dates, '{}'::date[]))
         with ordinality as s(name, exam_date, ord)
    where btrim(coalesce(s.name, '')) <> ''
    order by lower(btrim(s.name)), s.ord
  ) as cleaned
  limit c_max_subjects;

  -- 0018's trigger may have moved the goal's date while the subjects went in.
  select * into v_goal from goals where id = v_goal.id;
  return v_goal;
end $$;

comment on function public.create_goal(text, date, text, text[], date[]) is
  'Creates a goal, retires the previous active one, and seeds its subjects '
  'with their exam dates in a single transaction (0009, 0025).';

revoke all on function public.create_goal(text, date, text, text[], date[])
  from public, anon;
grant execute on function public.create_goal(text, date, text, text[], date[])
  to authenticated;

notify pgrst, 'reload schema';
-- StudyTrail — 0026: badge progress, eight more badges, three more rewards
--
-- Badges said only "locked" or "earned"; a student couldn't see they were
-- 5 of 7 days into Week Warrior. badge_progress() now works out every
-- badge's progress from the same rows the old conditions read, and
-- evaluate_badges() unlocks exactly the badges whose progress has reached
-- its goal — so the bar on screen and the unlock can never disagree (D-044).
--
-- The new rewards each change something real, like the two from 0012:
--   * Focus Boost doubles focus-session XP for a day (record_focus_session);
--   * a 50:50 lifeline removes two wrong answers in a quiz
--     (use_quiz_lifeline, spent from the quiz screen);
--   * the Aurora card restyles the student's profile card.
--
-- Idempotent, like every migration here.

-- ── 1. Eight more badges ───────────────────────────────────────────────────
insert into badges (key, name, icon_key, color_key, description) values
  ('warming_up',      'Warming Up',      'bolt',               'orange', 'Keep a 3-day streak.'),
  ('unstoppable',     'Unstoppable',     'whatshot',           'red',    'Keep a 30-day streak.'),
  ('task_tackler',    'Task Tackler',    'task_alt',           'green',  'Complete 50 study tasks.'),
  ('quiz_regular',    'Quiz Regular',    'psychology',         'violet', 'Finish 10 quizzes.'),
  ('deep_diver',      'Deep Diver',      'timer',              'teal',   'Log 10 hours of focus sessions.'),
  ('xp_collector',    'XP Collector',    'diamond',            'sky',    'Earn 1,000 XP.'),
  ('library_builder', 'Library Builder', 'library_books',      'indigo', 'Add 5 files, videos or playlists to your library.'),
  ('helping_hand',    'Helping Hand',    'volunteer_activism', 'rose',   'Answer 5 of your classmates'' doubts.')
on conflict (key) do update
  set name = excluded.name,
      icon_key = excluded.icon_key,
      color_key = excluded.color_key,
      description = excluded.description;

-- ── 2. Progress, for every badge ───────────────────────────────────────────
-- One row per badge: how far the student is, the goal, and what's being
-- counted (null for a yes/no badge). The first ten rows are the conditions
-- 0008 checked, restated as counts with the same thresholds.
create or replace function app_private.badge_progress(p_user uuid)
returns table (key text, progress int, goal int, unit text)
language sql
stable
security definer
set search_path = public
as $$
  with
    s as (select coalesce(max(best_streak), 0) as best
            from streaks where user_id = p_user),
    t as (select count(*) filter (where done) as done
            from daily_tasks where user_id = p_user),
    -- Hour-of-day badges in the cohort's time, as in 0008.
    f as (select coalesce(sum(sessions_count), 0) as sessions,
                 coalesce(sum(focused_min), 0)    as minutes,
                 bool_or(extract(hour from started_at at time zone 'Asia/Kolkata') >= 22) as late,
                 bool_or(extract(hour from started_at at time zone 'Asia/Kolkata') < 7)   as early
            from study_sessions where user_id = p_user and started_at is not null)
  select * from (values
    ('first_step',      (select least(done, 1) from t)::int, 1, null::text),
    ('week_warrior',    (select best from s)::int, 7, 'days'),
    -- Best quiz score as a percentage; 100 only when score = total.
    ('quiz_ace',        coalesce((select max(floor(100.0 * score / total))
                                    from quiz_attempts
                                   where user_id = p_user and completed_at is not null
                                     and total > 0), 0)::int, 100, '%'),
    -- Repetitions only ever move via the SR RPC.
    ('card_master',     coalesce((select sum(repetitions) from flashcards
                                   where user_id = p_user), 0)::int, 100, 'reviews'),
    ('night_owl',       (select case when coalesce(late, false) then 1 else 0 end from f), 1, null),
    ('early_bird',      (select case when coalesce(early, false) then 1 else 0 end from f), 1, null),
    ('focused_mind',    (select sessions from f)::int, 10, 'sessions'),
    ('roadmap_ready',   (case when exists (select 1 from milestones where user_id = p_user)
                              then 1 else 0 end), 1, null),
    ('curious_learner', (select count(*) from chat_messages
                          where user_id = p_user and role = 'user')::int, 25, 'questions'),
    ('goal_crusher',    coalesce((select max(floor(overall_percent)) from goals
                                   where user_id = p_user), 0)::int, 100, '%'),
    ('warming_up',      (select best from s)::int, 3, 'days'),
    ('unstoppable',     (select best from s)::int, 30, 'days'),
    ('task_tackler',    (select done from t)::int, 50, 'tasks'),
    ('quiz_regular',    (select count(*) from quiz_attempts
                          where user_id = p_user and completed_at is not null)::int, 10, 'quizzes'),
    ('deep_diver',      (select minutes / 60 from f)::int, 10, 'hours'),
    -- The same total the Rewards wallet counts as earned.
    ('xp_collector',    coalesce((select sum(xp_earned) from activity_log
                                   where user_id = p_user), 0)::int, 1000, 'XP'),
    -- A playlist is one library item (0024), not one per video.
    ('library_builder', ((select count(*) from materials
                           where user_id = p_user and playlist_id is null)
                       + (select count(*) from material_playlists
                           where user_id = p_user))::int, 5, 'items'),
    -- Written by the student, on someone else's doubt; AI answers don't count.
    ('helping_hand',    (select count(*) from doubt_answers a
                           join doubts d on d.id = a.doubt_id
                          where a.user_id = p_user and not a.is_ai
                            and d.user_id <> p_user)::int, 5, 'answers')
  ) as b(key, progress, goal, unit)
$$;

revoke all on function app_private.badge_progress(uuid) from public;

-- ── 3. Unlock by progress ──────────────────────────────────────────────────
-- Same contract as 0008: returns the keys unlocked by this call.
create or replace function app_private.evaluate_badges(p_user uuid)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
begin
  for v_key in
    select b.key from app_private.badge_progress(p_user) b
     where b.progress >= b.goal
  loop
    if app_private.unlock_badge(p_user, v_key) then
      return next v_key;
    end if;
  end loop;
end $$;

-- What the Achievements screen draws under each badge. Progress is capped at
-- the goal, so a 45-day streak reads 30/30, not 45/30.
create or replace function public.get_badge_progress()
returns table (key text, progress int, goal int, unit text)
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  return query
    select b.key, least(b.progress, b.goal), b.goal, b.unit
      from app_private.badge_progress(v_user) b;
end $$;

revoke all on function public.get_badge_progress() from public, anon;
grant execute on function public.get_badge_progress() to authenticated;

-- ── 4. Three more rewards ──────────────────────────────────────────────────
insert into reward_catalog (key, title, description, cost_xp, max_held, sort_order) values
  ('focus_boost', 'Focus Boost',
   'Double XP from every focus session for a whole day. It starts with your next session. Hold up to 2.',
   120, 2, 3),
  ('fifty_fifty', '50:50 Lifeline',
   'Removes two wrong answers from one quiz question. Tap 50:50 on the question to use it. Hold up to 5.',
   30, 5, 4),
  ('aurora_profile', 'Aurora Profile Card',
   'A northern-lights look for your profile card. Yours for good.',
   400, 1, 5)
on conflict (key) do update
  set title = excluded.title,
      description = excluded.description,
      cost_xp = excluded.cost_xp,
      max_held = excluded.max_held,
      sort_order = excluded.sort_order;

-- ── 5. Focus Boost: 0020's record_focus_session, plus the boost ───────────
create or replace function public.record_focus_session(
  p_subject     uuid default null,
  p_length_min  int  default 25,
  p_focused_min int  default null
)
returns study_sessions
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_day     date;
  v_focused int;
  v_today   int;
  v_xp      int;
  v_boost   boolean;
  v_row     study_sessions;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- A focus block longer than three hours isn't a Pomodoro, it's a forged one.
  if p_length_min is null or p_length_min < 1 or p_length_min > 180 then
    raise exception 'length_min must be between 1 and 180, got %', p_length_min
      using errcode = 'check_violation';
  end if;

  v_focused := coalesce(p_focused_min, p_length_min);
  if v_focused < 0 or v_focused > p_length_min then
    raise exception 'focused_min must be between 0 and length_min'
      using errcode = 'check_violation';
  end if;

  -- Parent-ownership check (REVIEW.md P2): a known subject id belonging to
  -- someone else must not become the parent of the caller's session.
  if p_subject is not null
     and not exists (select 1 from subjects
                      where id = p_subject and user_id = v_user) then
    raise exception 'subject % not found', p_subject using errcode = 'no_data_found';
  end if;

  -- Serialise this student's sessions, so two finishing at once can't both
  -- start a boost.
  perform 1 from profiles where id = v_user for update;
  v_day := app_private.local_today(v_user);

  -- Sixteen hours of logged focus in one day is the outer edge of plausible;
  -- past that, stop counting rather than trust the clock the client sent.
  select coalesce(sum(focused_min), 0) into v_today
    from study_sessions
    where user_id = v_user
      and session_date = v_day;

  if v_today + v_focused > 960 then
    raise exception 'daily focus limit reached' using errcode = 'check_violation';
  end if;

  insert into study_sessions (user_id, subject_id, session_date, length_min,
                              sessions_count, focused_min, started_at, ended_at)
  values (v_user, p_subject, v_day, p_length_min, 1,
          v_focused, now() - make_interval(mins => v_focused), now())
  returning * into v_row;

  v_xp := v_focused * app_private.xp_for('focus_minute');

  -- A boost already running today, or else the next one held, which then
  -- covers the rest of today. A session with no focused minutes earns
  -- nothing to double, so it doesn't start one.
  if v_xp > 0 then
    v_boost := exists (select 1 from reward_redemptions
                        where user_id = v_user and reward_key = 'focus_boost'
                          and consumed_for = v_day);
    if not v_boost then
      update reward_redemptions
         set consumed_at = now(), consumed_for = v_day
       where id = (select id from reward_redemptions
                    where user_id = v_user and reward_key = 'focus_boost'
                      and consumed_at is null
                    order by redeemed_at
                    limit 1)
      returning true into v_boost;
    end if;
    if coalesce(v_boost, false) then
      v_xp := v_xp * 2;
    end if;
  end if;

  perform app_private.log_activity(v_user, v_focused, 0, v_xp);
  perform app_private.award_xp(v_user, v_xp);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- ── 6. 50:50 lifeline ──────────────────────────────────────────────────────
-- Spends one held lifeline and returns how many are left. The quiz screen
-- removes two wrong options only after this succeeds. (The options and the
-- answer are already on the phone — 0008 lets the app reveal answers after
-- each pick — so the server's part is the spending, not the hiding.)
create or replace function public.use_quiz_lifeline()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
  v_left int;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform 1 from profiles where id = v_user for update;

  select id into v_id from reward_redemptions
   where user_id = v_user and reward_key = 'fifty_fifty' and consumed_at is null
   order by redeemed_at
   limit 1;
  if v_id is null then
    raise exception 'You have no 50:50 lifelines left. Get more in Rewards.';
  end if;

  update reward_redemptions set consumed_at = now() where id = v_id;

  select count(*) into v_left from reward_redemptions
   where user_id = v_user and reward_key = 'fifty_fifty' and consumed_at is null;
  return v_left;
end $$;

revoke all on function public.use_quiz_lifeline() from public, anon;
grant execute on function public.use_quiz_lifeline() to authenticated;

notify pgrst, 'reload schema';
