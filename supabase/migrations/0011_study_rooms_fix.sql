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
