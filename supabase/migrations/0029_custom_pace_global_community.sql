-- ============================================================
-- 0029  A pace of the student's own, and one community for everyone.
--
--  1. goals.daily_minutes: the study time a day the student chose for
--     themselves ("Custom" pace). Null means the preset pace stands; pace
--     is still set to the nearest preset, so everything that reads pace
--     keeps working. generate-roadmap sizes each week to it.
--
--  2. Classes are gone from the app. The leaderboard ranks every student,
--     and the doubt board is one board shared by all of them. Rooms were
--     already open to everyone when created without a class; the app now
--     always creates them that way.
--
--     The doubt board's functions all scope through app_private.my_class(),
--     so the board turns global by having that return one fixed community
--     row instead of the caller's class. profiles.class_id and the classes
--     table stay (old builds still read them) but nothing ranks by them.
--
-- Idempotent, like every migration here.
-- ============================================================

-- ── 1. Custom pace ──────────────────────────────────────────────────────────
alter table goals
  add column if not exists daily_minutes int
  check (daily_minutes is null or daily_minutes between 15 and 720);

-- ── 2. One community ────────────────────────────────────────────────────────
insert into classes (id, name)
values ('00000000-0000-0000-0000-0000000e0e0e', 'Everyone')
on conflict (id) do nothing;

create or replace function app_private.my_class()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  return '00000000-0000-0000-0000-0000000e0e0e'::uuid;
end $$;

revoke execute on function app_private.my_class() from public;

-- Doubts asked on a class board before this join the shared one.
update doubts
   set class_id = '00000000-0000-0000-0000-0000000e0e0e'
 where class_id is distinct from '00000000-0000-0000-0000-0000000e0e0e';

-- Every student, ranked by XP ever earned. The top [limit_count], plus the
-- caller's own row when they're further down, each with its real rank.
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
  is_me          boolean,
  rank           int
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := greatest(1, least(coalesce(limit_count, 20), 100));
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  return query
    with totals as (
      select p.id, p.full_name, p.avatar_initial, p.level, p.xp,
             coalesce((select sum(a.xp_earned) from activity_log a
                        where a.user_id = p.id), 0)::int as total_xp
        from profiles p
    ),
    ranked as (
      select t.*,
             (row_number() over (order by t.total_xp desc, t.level desc,
                                          t.xp desc, t.full_name asc,
                                          t.id))::int as pos
        from totals t
    )
    select r.id, r.full_name, r.avatar_initial, r.level, r.xp, r.total_xp,
           exists (select 1 from reward_redemptions rr
                    where rr.user_id = r.id and rr.reward_key = 'golden_border'),
           (r.id = auth.uid()),
           r.pos
      from ranked r
     where r.pos <= v_limit or r.id = auth.uid()
     order by r.pos;
end $$;

revoke execute on function public.get_class_leaderboard(int) from public, anon;
grant execute on function public.get_class_leaderboard(int) to authenticated;

notify pgrst, 'reload schema';
