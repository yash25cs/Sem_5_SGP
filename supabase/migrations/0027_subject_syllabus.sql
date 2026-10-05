-- StudyTrail — 0027: a syllabus for each subject
--
-- Home lets a student add a syllabus to each subject — a PDF, or text typed
-- or pasted in. It is an ordinary material (read by embed-material, listed in
-- the library, counted against the 20-item limit) that names its subject, so
-- the chunks it becomes carry that subject too: until now `material_chunks.
-- subject_id` was always null, because nothing tied a material to a subject.
-- generate-roadmap then plans each subject from its own syllabus units
-- (D-045).
--
-- Idempotent, like every migration here.

alter table materials
  add column if not exists subject_id uuid
    references subjects(id) on delete set null;

create index if not exists materials_subject_idx
  on materials(subject_id) where subject_id is not null;

-- Same rule as 0024's playlists: a foreign key is checked past RLS, so without
-- this a student who learnt another student's subject id could hang a file off
-- it.
create or replace function app_private.material_subject_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.subject_id is not null and not exists (
    select 1 from subjects
    where id = new.subject_id and user_id = new.user_id
  ) then
    raise exception 'subject % is not yours', new.subject_id
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists materials_subject_owner on materials;
create trigger materials_subject_owner
  before insert or update of subject_id on materials
  for each row execute function app_private.material_subject_owner();

notify pgrst, 'reload schema';
