-- ============================================================
-- 0017  Long-answer practice: a written answer to a 5- or 10-mark
--       question, graded against the student's own notes.
-- ============================================================
--
-- Deliberately pays no XP. An AI grade can be argued with, retried, or gamed
-- by pasting the notes back in; XP stays tied to things the server can
-- verify (0008). What a student gets here is feedback, kept so they can see
-- themselves improve on a topic.
-- ============================================================

create table if not exists answer_attempts (
  id          uuid         primary key default gen_random_uuid(),
  user_id     uuid         not null references auth.users(id) on delete cascade,
  question_id uuid         references paper_questions(id) on delete set null,
  question    text         not null check (char_length(question) <= 4000),
  unit_label  text,
  max_marks   numeric(5,1) not null check (max_marks between 1 and 100),
  answer      text         not null check (char_length(answer) between 1 and 12000),
  score       numeric(5,1) not null check (score >= 0),
  feedback    jsonb        not null default '{}'::jsonb,
  created_at  timestamptz  not null default now(),
  check (score <= max_marks)
);
create index if not exists answer_attempts_user_idx
  on answer_attempts(user_id, created_at desc);

alter table answer_attempts enable row level security;
drop policy if exists answer_attempts_own on answer_attempts;
create policy answer_attempts_own on answer_attempts for select to authenticated
  using (user_id = auth.uid());
drop policy if exists answer_attempts_delete_own on answer_attempts;
create policy answer_attempts_delete_own on answer_attempts for delete to authenticated
  using (user_id = auth.uid());

-- Written only by grade-answer, which holds the grade: a score the client
-- could insert would be a score the client chose.
revoke all on answer_attempts from anon;
revoke insert, update on answer_attempts from authenticated;
