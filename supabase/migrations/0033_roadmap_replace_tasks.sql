-- ============================================================
-- 0033  Regenerating the roadmap clears its unfinished tasks from Today.
--
--  generate-roadmap replaces a goal's milestones; the cascade takes their
--  milestone_tasks, and daily_tasks.milestone_task_id is `on delete set
--  null` (0001). So every task the student had pulled into Today's plan from
--  the old roadmap stayed behind, cut loose: still listed, still counted as
--  overdue by get_roadmap_pace, still written to the phone calendar.
--
--  Now deleting a roadmap task deletes its unfinished Today copy with it.
--  Finished ones stay — they are what badges count (first_step, task
--  totals) and the record of work done; the app no longer lists them on
--  Today once their roadmap task is gone. Unfinished ones already cut loose
--  by an earlier regeneration are removed here: every daily task comes from
--  the roadmap (Plan today, plan_catch_up), so an unfinished one without a
--  link can only be such a leftover.
--
-- Idempotent, like every migration here.
-- ============================================================

create or replace function app_private.milestone_task_drop_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from daily_tasks
   where milestone_task_id = old.id
     and not done;
  return old;
end $$;

revoke execute on function app_private.milestone_task_drop_pending() from public;

drop trigger if exists milestone_tasks_drop_pending on milestone_tasks;
create trigger milestone_tasks_drop_pending
  before delete on milestone_tasks
  for each row execute function app_private.milestone_task_drop_pending();

delete from daily_tasks
 where milestone_task_id is null
   and not done;

notify pgrst, 'reload schema';
