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
