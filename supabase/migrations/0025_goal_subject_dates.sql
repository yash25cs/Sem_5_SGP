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
