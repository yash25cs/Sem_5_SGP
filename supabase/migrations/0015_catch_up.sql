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
