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
