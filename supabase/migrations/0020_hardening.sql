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
