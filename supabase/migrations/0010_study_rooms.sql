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
