-- ============================================================
-- 0035  Deleting a goal keeps the student's notes and chats.
--
--  materials.goal_id and chat_threads.goal_id were `on delete cascade`
--  (0002), so deleting a goal in Settings silently deleted every file
--  uploaded while it was active, with their chunks, and the chats asked
--  under it — though the dialog promises only "its subjects, roadmap and
--  tasks". Worse, the files themselves stayed in Storage with no row
--  pointing at them, unreachable. Found by the live end-to-end test.
--
--  Both now become `on delete set null`: the notes stay in the library and
--  the chats in the history, just no longer tied to that goal. The library
--  and the history were never filtered by goal, so nothing else changes.
--
-- Idempotent, like every migration here.
-- ============================================================

do $$
declare
  r record;
begin
  for r in
    select c.conname, c.conrelid::regclass as tbl
      from pg_constraint c
      join pg_attribute a
        on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
     where c.contype = 'f'
       and c.confrelid = 'public.goals'::regclass
       and a.attname = 'goal_id'
       and c.conrelid in ('public.materials'::regclass,
                          'public.chat_threads'::regclass)
       and c.confdeltype <> 'n'   -- not already "set null"
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format(
      'alter table %s add constraint %I foreign key (goal_id) '
      'references public.goals(id) on delete set null', r.tbl, r.conname);
  end loop;
end $$;

notify pgrst, 'reload schema';
