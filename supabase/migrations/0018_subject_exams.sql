-- ============================================================
-- 0018  An exam date per subject.
-- ============================================================
--
-- A semester is several exams on different days, not one. The goal stays the
-- whole exam season; each subject can carry the date of its own paper, and
-- the goal's date follows the last of them so pace (0015) and the roadmap
-- cover every exam.
-- ============================================================

alter table subjects add column if not exists exam_date date;

-- The student's own column to set, next to the ones 0008 already grants.
grant update (exam_date) on subjects to authenticated;
grant insert (exam_date) on subjects to authenticated;

-- Keep goals.exam_date at the latest subject exam. Only ever moves it later:
-- clearing a subject's date shouldn't shorten a goal the student dated
-- themselves.
create or replace function app_private.extend_goal_to_last_exam()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.exam_date is not null and new.goal_id is not null then
    update goals
       set exam_date = new.exam_date
     where id = new.goal_id
       and (exam_date is null or exam_date < new.exam_date);
  end if;
  return null;
end $$;

drop trigger if exists subjects_extend_goal on subjects;
create trigger subjects_extend_goal
  after insert or update of exam_date on subjects
  for each row execute function app_private.extend_goal_to_last_exam();
