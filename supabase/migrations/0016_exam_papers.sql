-- ============================================================
-- 0016  Previous-year exam papers: which topics get asked, how
--       often, and for how many marks.
-- ============================================================
--
-- A paper is uploaded like a material but kept apart from them on purpose:
-- it is questions, not notes, and embedding it would make Trail AI cite an
-- exam paper as if it were an explanation. `analyze-paper` reads it with
-- Gemini, extracts each question with its marks, and tags it with one of the
-- student's own syllabus units.
--
-- Nothing here pays XP, so the owner may read and write these rows directly,
-- the same as flashcard decks.
-- ============================================================

create table if not exists exam_papers (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        not null references auth.users(id) on delete cascade,
  goal_id        uuid        references goals(id) on delete set null,
  title          text        not null,
  year           int         check (year is null or year between 1990 and 2100),
  storage_path   text        not null,
  status         text        not null default 'pending'
                             check (status in ('pending', 'analyzing', 'analyzed', 'failed')),
  question_count int         not null default 0,
  error          text,
  created_at     timestamptz not null default now()
);
create index if not exists exam_papers_user_idx on exam_papers(user_id);

create table if not exists paper_questions (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  paper_id    uuid        not null references exam_papers(id) on delete cascade,
  question_no text,
  text        text        not null check (char_length(text) <= 4000),
  marks       numeric(5,1) check (marks is null or marks between 0 and 100),
  unit_label  text,
  created_at  timestamptz not null default now()
);
create index if not exists paper_questions_paper_idx on paper_questions(paper_id);
create index if not exists paper_questions_user_unit_idx on paper_questions(user_id, unit_label);

alter table exam_papers     enable row level security;
alter table paper_questions enable row level security;

drop policy if exists exam_papers_own on exam_papers;
create policy exam_papers_own on exam_papers for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A question may only hang off one of the caller's own papers.
drop policy if exists paper_questions_own on paper_questions;
create policy paper_questions_own on paper_questions for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from exam_papers p
                 where p.id = paper_id and p.user_id = auth.uid())
  );

revoke all on exam_papers, paper_questions from anon;

-- Topics ranked by how often past papers ask about them.
create or replace function public.get_exam_topics(p_limit int default 20)
returns table (
  unit_label  text,
  times_asked int,
  total_marks numeric,
  years       int[],
  papers      int,
  example     text
)
language sql
stable
set search_path = public
as $$
  select coalesce(q.unit_label, 'Other')                          as unit_label,
         count(*)::int                                            as times_asked,
         coalesce(sum(q.marks), 0)                                as total_marks,
         array_remove(array_agg(distinct p.year order by p.year), null) as years,
         count(distinct q.paper_id)::int                          as papers,
         (array_agg(q.text order by q.marks desc nulls last))[1]  as example
    from paper_questions q
    join exam_papers p on p.id = q.paper_id
   where q.user_id = auth.uid()
     and p.status = 'analyzed'
   group by coalesce(q.unit_label, 'Other')
   order by times_asked desc, total_marks desc
   limit greatest(1, least(p_limit, 50));
$$;

revoke execute on function public.get_exam_topics(int) from public, anon;
grant execute on function public.get_exam_topics(int) to authenticated;
