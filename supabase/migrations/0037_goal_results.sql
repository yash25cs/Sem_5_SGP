-- StudyTrail — 0037: how an exam went
--
-- Once a goal's exams are over, Home asks "How did it go?": the marks, how it
-- felt, and which units were hard. That turns the finished goal into a record
-- the student can set against how much they prepared, and `generate-roadmap`
-- gives the hard units more time in the next goal's plan.
--
-- One row per goal, the student's own. Idempotent, like every migration here.

create table if not exists goal_results (
  goal_id     uuid        primary key references goals(id) on delete cascade,
  user_id     uuid        not null default auth.uid()
                          references auth.users(id) on delete cascade,
  marks       numeric     check (marks >= 0),
  out_of      numeric     check (out_of > 0 and out_of <= 10000),
  -- 1 tough · 2 okay · 3 good · 4 great
  feeling     smallint    check (feeling between 1 and 4),
  hard_units  text[]      not null default '{}'
                          check (cardinality(hard_units) <= 20),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (marks is null or out_of is null or marks <= out_of)
);
create index if not exists goal_results_user_idx on goal_results(user_id);

alter table goal_results enable row level security;
drop policy if exists owner_all on goal_results;
-- The row's own user_id, and the goal it names must be theirs too: otherwise
-- a guessed goal id would let a student write a result onto someone else's.
create policy owner_all on goal_results
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from goals g
                 where g.id = goal_id and g.user_id = auth.uid())
  );

revoke all on goal_results from anon, authenticated;
grant select, insert, delete on goal_results to authenticated;
grant update (marks, out_of, feeling, hard_units, updated_at)
  on goal_results to authenticated;
