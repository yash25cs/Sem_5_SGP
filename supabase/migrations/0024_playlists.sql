-- StudyTrail — 0024: a YouTube playlist is one library item
--
-- A playlist used to become one `materials` row per video, so a 92-lecture
-- course spent all 20 library slots on its first 20 videos and stopped. Now
-- the playlist is one `material_playlists` row and counts as one item; its
-- videos are still ordinary `video_link` materials (transcript file, chunks,
-- retry, summaries — all unchanged) that point back at it (D-038).
--
-- The video list is stored when the playlist is added. The phone reads the
-- captions (D-037), so an import is only as long-lived as the app; with the
-- list on the server, one the phone couldn't finish — app closed, signal lost
-- — carries on at the next launch, on any device.
--
-- Idempotent, like every migration here.

create table if not exists material_playlists (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null default auth.uid()
                          references auth.users(id) on delete cascade,
  youtube_id  text        not null check (youtube_id ~ '^[A-Za-z0-9_-]{12,64}$'),
  title       text        not null check (char_length(title) between 1 and 300),
  -- The playlist's videos in playlist order, as listed when it was added.
  -- YouTube lists 100 per page; that is the ceiling the app reads.
  video_ids   text[]      not null
                          check (cardinality(video_ids) between 1 and 100),
  -- Videos that won't be read: no captions, private or deleted, or removed
  -- from the playlist by the student. Never retried.
  skipped_ids text[]      not null default '{}'
                          check (cardinality(skipped_ids) <= 100),
  created_at  timestamptz not null default now(),
  unique (user_id, youtube_id)
);
create index if not exists material_playlists_user_idx
  on material_playlists(user_id);

alter table material_playlists enable row level security;
drop policy if exists owner_all on material_playlists;
create policy owner_all on material_playlists
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on material_playlists from anon, authenticated;
grant select, insert, delete on material_playlists to authenticated;
-- After creation only the skip list moves. The video list is what the import
-- was asked for and stays as listed.
grant update (skipped_ids) on material_playlists to authenticated;

alter table materials
  add column if not exists playlist_id uuid
    references material_playlists(id) on delete cascade;
create index if not exists materials_playlist_idx
  on materials(playlist_id) where playlist_id is not null;

-- RLS on `materials` checks the row's own `user_id`, not whose playlist it
-- names. Without this a student could hang a video off a classmate's playlist
-- id — unreadable to them, but deleted along with it. `playlist_id` is set at
-- insert only: 0009's update grant (goal_id, title, status) doesn't include it.
create or replace function app_private.material_playlist_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.playlist_id is not null and not exists (
    select 1 from material_playlists
    where id = new.playlist_id and user_id = new.user_id
  ) then
    raise exception 'playlist % is not yours', new.playlist_id
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists materials_playlist_owner on materials;
create trigger materials_playlist_owner
  before insert or update of playlist_id on materials
  for each row execute function app_private.material_playlist_owner();

notify pgrst, 'reload schema';
