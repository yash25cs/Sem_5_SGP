-- ============================================================
-- 0028  Answer practice: a kind of question.
--       'theory' = the 5/10-mark descriptive answer it has always been;
--       'nep'    = a case-based, application question in the style of an
--                  NEP 2020 outcome-based paper: a scenario, then lettered
--                  parts that ask the student to choose, estimate, analyse
--                  or justify.
-- ============================================================

alter table answer_attempts
  add column if not exists kind text not null default 'theory'
  check (kind in ('theory', 'nep'));

notify pgrst, 'reload schema';
