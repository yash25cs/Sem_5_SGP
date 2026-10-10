-- ============================================================
-- 0030  Materials shared in a study room, and each student's room history.
--
--  1. room_history: one row per student per room they've been in — created
--     or joined — kept after they leave and after the room closes. Written
--     only by triggers on room_members; the student can read and delete
--     their own rows ("Remove from history").
--
--  2. room_materials: a member shares one of their own ready materials into
--     the room. Everyone who is or was in that room (and wasn't removed by
--     the host) can see it, read its file, and save a copy to their own
--     library. Unsharing is for whoever shared it, or the host. Deleting the
--     original from the sharer's library takes it out of the room
--     (cascade); copies already saved are independent and stay.
--
--     Saving copies the file in the app (the new storage policy lets the
--     saver read it) and the embedded chunks here, so nothing is sent to
--     Gemini again. materials.source_material_id marks the copy, which is
--     how a second save of the same material is refused.
--
--  3. get_room_history() / get_room_history_detail(): rooms with name,
--     role, dates and counts; and one room's shared materials and group
--     quizzes with the caller's own score and rank.
--
-- Idempotent, like every migration here.
-- ============================================================

-- ── 1. Room history ─────────────────────────────────────────────────────────
create table if not exists room_history (
  user_id         uuid        not null references auth.users(id) on delete cascade,
  room_id         uuid        not null references study_rooms(id) on delete cascade,
  role            text        not null default 'member'
                              check (role in ('host', 'member')),
  first_joined_at timestamptz not null default now(),
  last_joined_at  timestamptz not null default now(),
  left_at         timestamptz,
  primary key (user_id, room_id)
);
create index if not exists room_history_user_idx
  on room_history(user_id, last_joined_at desc);

alter table room_history enable row level security;
revoke all on room_history from anon, authenticated;
grant select, delete on room_history to authenticated;

drop policy if exists room_history_own_select on room_history;
create policy room_history_own_select on room_history
  for select to authenticated using (user_id = auth.uid());
drop policy if exists room_history_own_delete on room_history;
create policy room_history_own_delete on room_history
  for delete to authenticated using (user_id = auth.uid());

create or replace function app_private.room_history_on_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into room_history (user_id, room_id, role, first_joined_at, last_joined_at)
  values (new.user_id, new.room_id, new.role, new.joined_at, new.joined_at)
  on conflict (user_id, room_id) do update
    set last_joined_at = excluded.last_joined_at,
        left_at = null,
        -- Once a host, always shown as the room's creator.
        role = case when room_history.role = 'host' then 'host' else excluded.role end;
  return new;
end $$;

create or replace function app_private.room_history_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update room_history
     set left_at = now()
   where user_id = old.user_id and room_id = old.room_id;
  return old;
end $$;

drop trigger if exists room_members_history_join on room_members;
create trigger room_members_history_join
  after insert on room_members
  for each row execute function app_private.room_history_on_join();

drop trigger if exists room_members_history_leave on room_members;
create trigger room_members_history_leave
  after delete on room_members
  for each row execute function app_private.room_history_on_leave();

-- Whoever is in a room now starts with a history row.
insert into room_history (user_id, room_id, role, first_joined_at, last_joined_at)
select user_id, room_id, role, joined_at, joined_at from room_members
on conflict (user_id, room_id) do nothing;

-- In the room now, or was and still has it in their history — and wasn't
-- removed by the host.
create or replace function app_private.can_see_room(p_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and not exists (select 1 from room_bans
                      where room_id = p_room and user_id = auth.uid())
     and (exists (select 1 from room_members
                   where room_id = p_room and user_id = auth.uid())
          or exists (select 1 from room_history
                      where room_id = p_room and user_id = auth.uid()));
$$;
revoke execute on function app_private.can_see_room(uuid) from public;

-- ── 2. Shared materials ─────────────────────────────────────────────────────
alter table materials
  add column if not exists source_material_id uuid;
create index if not exists materials_source_idx
  on materials(user_id, source_material_id) where source_material_id is not null;

create table if not exists room_materials (
  id          uuid        primary key default gen_random_uuid(),
  room_id     uuid        not null references study_rooms(id) on delete cascade,
  material_id uuid        not null references materials(id) on delete cascade,
  shared_by   uuid        not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (room_id, material_id)
);
create index if not exists room_materials_room_idx
  on room_materials(room_id, created_at desc);

alter table room_materials enable row level security;
-- No policies and no grants: read and written only by the functions below,
-- because the materials row behind each share is the sharer's own.
revoke all on room_materials from anon, authenticated;

-- A room's shared materials, newest first, with who shared each and whether
-- the caller already has a copy.
create or replace function public.get_room_materials(p_room uuid)
returns table (
  id           uuid,
  room_id      uuid,
  material_id  uuid,
  title        text,
  source_type  text,
  storage_path text,
  external_url text,
  shared_by    uuid,
  shared_by_name text,
  created_at   timestamptz,
  saved        boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not app_private.can_see_room(p_room) then
    raise exception 'You''re not in this room.' using errcode = '42501';
  end if;
  return query
  select rm.id, rm.room_id, rm.material_id,
         coalesce(nullif(btrim(m.title), ''), 'Untitled'),
         m.source_type::text, m.storage_path, m.external_url,
         rm.shared_by,
         coalesce(nullif(btrim(p.full_name), ''), 'Student'),
         rm.created_at,
         (m.user_id = auth.uid()
          or exists (select 1 from materials c
                      where c.user_id = auth.uid()
                        and c.source_material_id = m.id))
    from room_materials rm
    join materials m on m.id = rm.material_id
    left join profiles p on p.id = rm.shared_by
   where rm.room_id = p_room
   order by rm.created_at desc;
end $$;

revoke execute on function public.get_room_materials(uuid) from public, anon;
grant execute on function public.get_room_materials(uuid) to authenticated;

-- Shares one of the caller's own ready materials into a room they're in now.
create or replace function public.share_room_material(p_room uuid, p_material uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from room_members rm
                   join study_rooms r on r.id = rm.room_id
                  where rm.room_id = p_room and rm.user_id = v_uid
                    and r.status = 'active') then
    raise exception 'Join the room to share a material.' using errcode = '42501';
  end if;
  if not exists (select 1 from materials
                  where id = p_material and user_id = v_uid) then
    raise exception 'That material isn''t yours.' using errcode = '42501';
  end if;
  if not exists (select 1 from materials
                  where id = p_material and status = 'embedded') then
    raise exception 'That material is still being read. Share it once it''s ready.'
      using errcode = '22023';
  end if;
  if (select count(*) from room_materials where room_id = p_room) >= 30 then
    raise exception 'A room can hold up to 30 shared materials.' using errcode = '22023';
  end if;

  insert into room_materials (room_id, material_id, shared_by)
  values (p_room, p_material, v_uid)
  on conflict (room_id, material_id) do nothing
  returning id into v_id;

  if v_id is null then
    raise exception 'You''ve already shared that here.' using errcode = '23505';
  end if;
  return v_id;
end $$;

revoke execute on function public.share_room_material(uuid, uuid) from public, anon;
grant execute on function public.share_room_material(uuid, uuid) to authenticated;

-- Takes a share out of the room: whoever shared it, or the room's host.
create or replace function public.unshare_room_material(p_share uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from room_materials rm
   using study_rooms r
   where rm.id = p_share
     and r.id = rm.room_id
     and (rm.shared_by = v_uid or r.created_by = v_uid);
  if not found then
    raise exception 'Only whoever shared it, or the host, can remove it.'
      using errcode = '42501';
  end if;
end $$;

revoke execute on function public.unshare_room_material(uuid) from public, anon;
grant execute on function public.unshare_room_material(uuid) to authenticated;

-- Copies a shared material into the caller's library. The app has already
-- copied the file to [p_path] in the caller's own folder; this records it and
-- copies the chunks, so it's ready straight away.
create or replace function public.save_room_material(p_share uuid, p_path text)
returns materials
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_src  materials;
  v_room uuid;
  v_new  materials;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select rm.room_id into v_room from room_materials rm where rm.id = p_share;
  if v_room is null or not app_private.can_see_room(v_room) then
    raise exception 'That material is no longer shared here.' using errcode = '42501';
  end if;

  select m.* into v_src
    from room_materials rm join materials m on m.id = rm.material_id
   where rm.id = p_share;

  if v_src.user_id = v_uid then
    raise exception 'This is already in your library.' using errcode = '23505';
  end if;
  if exists (select 1 from materials
              where user_id = v_uid and source_material_id = v_src.id) then
    raise exception 'You''ve already saved this to your library.' using errcode = '23505';
  end if;
  if p_path is null or p_path not like v_uid::text || '/%'
     or not exists (select 1 from storage.objects
                     where bucket_id = 'materials' and name = p_path) then
    raise exception 'The copied file didn''t arrive. Try again.' using errcode = '22023';
  end if;

  insert into materials (user_id, source_type, title, storage_path,
                         external_url, status, source_material_id)
  values (v_uid, v_src.source_type, v_src.title, p_path,
          v_src.external_url, 'uploaded', v_src.id)
  returning * into v_new;

  insert into material_chunks (user_id, material_id, unit_label, chunk_index,
                               content, embedding)
  select v_uid, v_new.id, c.unit_label, c.chunk_index, c.content, c.embedding
    from material_chunks c
   where c.material_id = v_src.id;

  -- The status guard (0009) wants chunks before 'embedded'; a source with
  -- none is left 'uploaded' so the app reads it in like a fresh upload.
  if found then
    update materials set status = 'embedded' where id = v_new.id
    returning * into v_new;
  end if;
  return v_new;
end $$;

revoke execute on function public.save_room_material(uuid, text) from public, anon;
grant execute on function public.save_room_material(uuid, text) to authenticated;

-- Read access to a shared material's file, for saving a copy.
create or replace function public.can_read_shared_material(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from room_materials rm
      join materials m on m.id = rm.material_id
     where m.storage_path = p_path
       and app_private.can_see_room(rm.room_id));
$$;

revoke execute on function public.can_read_shared_material(text) from public, anon;
grant execute on function public.can_read_shared_material(text) to authenticated;

drop policy if exists materials_read_shared on storage.objects;
create policy materials_read_shared on storage.objects
  for select to authenticated
  using (
    bucket_id = 'materials'
    and public.can_read_shared_material(name)
  );

-- ── 3. History reads ────────────────────────────────────────────────────────
create or replace function public.get_room_history(p_limit int default 50)
returns table (
  room_id         uuid,
  name            text,
  invite_code     text,
  status          text,
  role            text,
  created_at      timestamptz,
  first_joined_at timestamptz,
  last_joined_at  timestamptz,
  left_at         timestamptz,
  is_member       boolean,
  member_count    int,
  material_count  int,
  quiz_count      int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  return query
  select h.room_id, r.name, r.invite_code, r.status, h.role, r.created_at,
         h.first_joined_at, h.last_joined_at, h.left_at,
         exists (select 1 from room_members m
                  where m.room_id = h.room_id and m.user_id = auth.uid()),
         (select count(*)::int from room_members m where m.room_id = h.room_id),
         (select count(*)::int from room_materials rm where rm.room_id = h.room_id),
         (select count(*)::int from room_quiz_players qp
            join room_quizzes q on q.id = qp.room_quiz_id
           where q.room_id = h.room_id and qp.user_id = auth.uid()
             and q.status = 'finished')
    from room_history h
    join study_rooms r on r.id = h.room_id
   where h.user_id = auth.uid()
     and not exists (select 1 from room_bans b
                      where b.room_id = h.room_id and b.user_id = auth.uid())
   order by h.last_joined_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 200));
end $$;

revoke execute on function public.get_room_history(int) from public, anon;
grant execute on function public.get_room_history(int) to authenticated;

-- The finished group quizzes the caller played in one room, newest first.
create or replace function public.get_room_quiz_history(p_room uuid)
returns table (
  id             uuid,
  title          text,
  mode           text,
  question_count int,
  finished_at    timestamptz,
  score          int,
  rank           int,
  players        int,
  xp_awarded     int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not app_private.can_see_room(p_room) then
    raise exception 'You''re not in this room.' using errcode = '42501';
  end if;
  return query
  select q.id, q.title, q.mode, q.question_count,
         coalesce(q.finished_at, q.created_at),
         qp.score, qp.rank,
         (select count(*)::int from room_quiz_players o
           where o.room_quiz_id = q.id and o.submitted_at is not null),
         qp.xp_awarded
    from room_quizzes q
    join room_quiz_players qp on qp.room_quiz_id = q.id and qp.user_id = auth.uid()
   where q.room_id = p_room and q.status = 'finished'
   order by coalesce(q.finished_at, q.created_at) desc;
end $$;

revoke execute on function public.get_room_quiz_history(uuid) from public, anon;
grant execute on function public.get_room_quiz_history(uuid) to authenticated;

notify pgrst, 'reload schema';
