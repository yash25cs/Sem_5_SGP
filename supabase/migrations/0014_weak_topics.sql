-- ============================================================
-- 0014  Weak topics: find the units a student keeps getting
--       wrong, so practice can target them.
-- ============================================================
--
-- The evidence was mostly there already: every flashcard carries its source
-- chunk and its last grade, and every quiz answer is marked right or wrong.
-- What was missing is which unit a quiz question tested — generate-quiz now
-- records it, from the excerpt the question was written from. Questions
-- generated before this migration have no unit and simply don't count.
-- ============================================================

alter table quizzes
  add column if not exists material_id uuid references materials(id) on delete set null;

alter table quiz_questions
  add column if not exists unit_label text,
  add column if not exists source_chunk_id uuid references material_chunks(id) on delete set null;

-- Units ranked by how often the student gets them wrong.
--
-- A topic is (material, unit label); a file with no unit headings at all is
-- one topic, with a null label. Evidence is one row per answered quiz
-- question and one per reviewed flashcard; a miss is a wrong answer or a card
-- whose last grade was "again" or "hard". The chunk's own unit label is
-- preferred over the one the model copied, so a quiz and a deck from the same
-- section land on the same topic.
--
-- Security invoker: every table read here is owner-scoped by RLS, and each
-- branch also filters on auth.uid() explicitly.
create or replace function public.get_weak_topics(p_limit int default 5)
returns table (
  material_id      uuid,
  material_title   text,
  unit_label       text,
  answered         int,
  correct          int,
  cards_reviewed   int,
  cards_struggling int,
  miss_rate        numeric
)
language sql
stable
set search_path = public
as $$
  with evidence as (
    select coalesce(c.material_id, q.material_id)  as material_id,
           coalesce(c.unit_label, qq.unit_label)   as unit_label,
           1                                       as answered,
           case when qa.is_correct then 1 else 0 end as correct,
           0                                       as reviewed,
           0                                       as struggling
      from quiz_answers qa
      join quiz_questions qq on qq.id = qa.question_id
      join quizzes q         on q.id = qq.quiz_id
      left join material_chunks c on c.id = qq.source_chunk_id
     where qa.user_id = auth.uid()
    union all
    select c.material_id,
           coalesce(c.unit_label, f.unit_label),
           0, 0, 1,
           case when f.last_grade in ('again', 'hard') then 1 else 0 end
      from flashcards f
      join material_chunks c on c.id = f.source_chunk_id
     where f.user_id = auth.uid()
       and f.last_grade is not null
  ),
  topics as (
    select e.material_id,
           e.unit_label,
           sum(e.answered)::int   as answered,
           sum(e.correct)::int    as correct,
           sum(e.reviewed)::int   as cards_reviewed,
           sum(e.struggling)::int as cards_struggling
      from evidence e
     where e.material_id is not null
     group by e.material_id, e.unit_label
  )
  select t.material_id,
         m.title,
         t.unit_label,
         t.answered,
         t.correct,
         t.cards_reviewed,
         t.cards_struggling,
         round(((t.answered - t.correct) + t.cards_struggling)::numeric
               / (t.answered + t.cards_reviewed), 2) as miss_rate
    from topics t
    join materials m on m.id = t.material_id
   -- Two pieces of evidence at least, and wrong a third of the time or more:
   -- one unlucky answer isn't a weak topic.
   where t.answered + t.cards_reviewed >= 2
     and ((t.answered - t.correct) + t.cards_struggling)::numeric
         / (t.answered + t.cards_reviewed) >= 0.34
   order by miss_rate desc, t.answered + t.cards_reviewed desc
   limit greatest(1, least(p_limit, 20));
$$;

revoke execute on function public.get_weak_topics(int) from public, anon;
grant execute on function public.get_weak_topics(int) to authenticated;
