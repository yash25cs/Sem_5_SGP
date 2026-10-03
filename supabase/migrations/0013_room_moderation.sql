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
