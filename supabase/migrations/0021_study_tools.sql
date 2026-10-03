-- StudyTrail — 0021: study tools
--
--   1. Explanations in Hindi or Gujarati: `profiles.answer_language`, read by
--      the chat, summarize-material and grade-answer functions.
--   2. A "My mistakes" deck that fills itself: every question a student gets
--      wrong in a quiz — their own or a room's — becomes a flashcard, due now.
--   3. A weekly report: this week against last, in the student's own days.
--
-- Idempotent, like every migration here.

-- ── 1. Answer language ──────────────────────────────────────────────────────
alter table profiles
  add column if not exists answer_language text not null default 'en';
do $$ begin
  alter table profiles add constraint profiles_answer_language_check
    check (answer_language in ('en', 'hi', 'gu'));
exception when duplicate_object then null; end $$;

grant update (answer_language) on profiles to authenticated;

-- ── 2. My mistakes ──────────────────────────────────────────────────────────
alter table flashcard_decks
  add column if not exists is_mistakes boolean not null default false;
create unique index if not exists flashcard_decks_one_mistakes
  on flashcard_decks(user_id) where is_mistakes;

-- 'quiz:<question id>' or 'room:<question id>'. Getting the same question
-- wrong again makes its card due now instead of adding a second one.
alter table flashcards add column if not exists mistake_key text;
create unique index if not exists flashcards_mistake_key
  on flashcards(user_id, mistake_key) where mistake_key is not null;

create or replace function app_private.mistakes_deck(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deck uuid;
begin
  select id into v_deck from flashcard_decks
   where user_id = p_user and is_mistakes;
  if v_deck is null then
    insert into flashcard_decks (user_id, name, is_mistakes)
    values (p_user, 'My mistakes', true)
    on conflict (user_id) where is_mistakes do nothing
    returning id into v_deck;
    if v_deck is null then
      select id into v_deck from flashcard_decks
       where user_id = p_user and is_mistakes;
    end if;
  end if;
  return v_deck;
end $$;

create or replace function app_private.add_mistake(
  p_user        uuid,
  p_key         text,
  p_question    text,
  p_options     text[],
  p_correct     int,
  p_explanation text,
  p_unit        text,
  p_chunk       uuid
)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  if p_correct is null or p_correct not between 0 and 3 then
    return;
  end if;
  insert into flashcards (user_id, deck_id, unit_label, front, back,
                          source_chunk_id, mistake_key, due_at)
  values (p_user, app_private.mistakes_deck(p_user), p_unit, p_question,
          'Answer: ' || p_options[p_correct + 1]
            || coalesce(E'\n\n' || nullif(btrim(p_explanation), ''), ''),
          p_chunk, p_key, now())
  on conflict (user_id, mistake_key) where mistake_key is not null
  do update set due_at = least(flashcards.due_at, now());
end $$;

-- Solo quizzes: quiz_answers is written only by finish_quiz_attempt.
create or replace function app_private.quiz_answer_mistake()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_q quiz_questions;
begin
  if new.is_correct is distinct from false then
    return new;
  end if;
  select * into v_q from quiz_questions where id = new.question_id;
  if found then
    perform app_private.add_mistake(new.user_id, 'quiz:' || v_q.id, v_q.question,
      v_q.options, v_q.correct_index, v_q.explanation, v_q.unit_label,
      v_q.source_chunk_id);
  end if;
  return new;
end $$;

drop trigger if exists quiz_answers_mistakes on quiz_answers;
create trigger quiz_answers_mistakes
  after insert on quiz_answers
  for each row execute function app_private.quiz_answer_mistake();

-- Group quizzes: once the quiz is over — not at hand-in, which would put the
-- answers in a deck while others are still answering (D-031) — each question
-- every player who handed in missed or left.
create or replace function app_private.room_quiz_mistakes()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_row record;
begin
  for v_row in
    select pl.user_id, q.*
      from room_quiz_players pl
      join room_quiz_questions q on q.room_quiz_id = pl.room_quiz_id
     where pl.room_quiz_id = new.id
       and pl.submitted_at is not null
       and nullif(pl.picks ->> q.id::text, '')::int is distinct from q.correct_index
  loop
    perform app_private.add_mistake(v_row.user_id, 'room:' || v_row.id,
      v_row.question, v_row.options, v_row.correct_index, v_row.explanation,
      null, null);
  end loop;
  return new;
end $$;

drop trigger if exists room_quiz_players_mistakes on room_quiz_players;
drop trigger if exists room_quizzes_mistakes on room_quizzes;
create trigger room_quizzes_mistakes
  after update of status on room_quizzes
  for each row
  when (new.status = 'finished' and old.status is distinct from 'finished')
  execute function app_private.room_quiz_mistakes();

revoke execute on function app_private.mistakes_deck(uuid) from public;
revoke execute on function app_private.add_mistake(uuid, text, text, text[], int, text, text, uuid) from public;

-- ── 3. Weekly report ────────────────────────────────────────────────────────
-- Totals for [p_from, p_to] in the student's own days ([p_off] minutes east
-- of UTC).
create or replace function app_private.week_totals(
  p_user uuid, p_from date, p_to date, p_off int
)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'minutes', coalesce((select sum(minutes_studied) from activity_log
                          where user_id = p_user
                            and activity_date between p_from and p_to), 0),
    'xp', coalesce((select sum(xp_earned) from activity_log
                     where user_id = p_user
                       and activity_date between p_from and p_to), 0),
    'tasks', coalesce((select sum(tasks_completed) from activity_log
                        where user_id = p_user
                          and activity_date between p_from and p_to), 0),
    'active_days', (select count(*) from activity_log
                     where user_id = p_user
                       and activity_date between p_from and p_to
                       and (minutes_studied > 0 or tasks_completed > 0
                            or xp_earned > 0)),
    'quizzes', (select count(*) from quiz_attempts
                 where user_id = p_user and completed_at is not null
                   and (completed_at + make_interval(mins => p_off))::date
                       between p_from and p_to),
    'quiz_correct', coalesce((select sum(score) from quiz_attempts
                               where user_id = p_user and completed_at is not null
                                 and (completed_at + make_interval(mins => p_off))::date
                                     between p_from and p_to), 0),
    'quiz_total', coalesce((select sum(total) from quiz_attempts
                             where user_id = p_user and completed_at is not null
                               and (completed_at + make_interval(mins => p_off))::date
                                   between p_from and p_to), 0),
    'group_quizzes', (select count(*) from room_quiz_players
                       where user_id = p_user and submitted_at is not null
                         and (submitted_at + make_interval(mins => p_off))::date
                             between p_from and p_to),
    'podiums', (select count(*) from room_quiz_players pl
                 where pl.user_id = p_user and pl.rank between 1 and 3
                   and (pl.submitted_at + make_interval(mins => p_off))::date
                       between p_from and p_to
                   -- A podium of one isn't one.
                   and (select count(*) from room_quiz_players o
                         where o.room_quiz_id = pl.room_quiz_id
                           and o.submitted_at is not null) >= 2),
    'answers', (select count(*) from answer_attempts
                 where user_id = p_user
                   and (created_at + make_interval(mins => p_off))::date
                       between p_from and p_to),
    'answer_percent', (select round(avg(score / max_marks) * 100)
                         from answer_attempts
                        where user_id = p_user
                          and (created_at + make_interval(mins => p_off))::date
                              between p_from and p_to)
  );
$$;

-- The last seven days (today included) against the seven before, a day-by-day
-- series, and per-unit quiz accuracy with last week's for comparison.
create or replace function public.get_weekly_report()
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_user  uuid := auth.uid();
  v_off   int;
  v_today date;
  v_from  date;
  v_prev  date;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select coalesce(utc_offset_min, 330) into v_off from profiles where id = v_user;
  v_off   := coalesce(v_off, 330);
  v_today := (now() + make_interval(mins => v_off))::date;
  v_from  := v_today - 6;
  v_prev  := v_from - 7;

  return json_build_object(
    'from', v_from,
    'to', v_today,
    'this_week', app_private.week_totals(v_user, v_from, v_today, v_off),
    'last_week', app_private.week_totals(v_user, v_prev, v_from - 1, v_off),
    'days', (
      select json_agg(json_build_object(
               'date', d::date,
               'minutes', coalesce(a.minutes_studied, 0),
               'xp', coalesce(a.xp_earned, 0)) order by d)
        from generate_series(v_from::timestamp, v_today::timestamp,
                             interval '1 day') d
        left join activity_log a
          on a.user_id = v_user and a.activity_date = d::date),
    'units', (
      select coalesce(json_agg(u order by u.correct::float / u.answered,
                                         u.unit_label), '[]'::json)
        from (
          select q.unit_label,
                 count(*) filter (where t.day >= v_from) as answered,
                 count(*) filter (where t.day >= v_from and a.is_correct) as correct,
                 count(*) filter (where t.day < v_from) as answered_before,
                 count(*) filter (where t.day < v_from and a.is_correct) as correct_before
            from quiz_answers a
            join (select id, (completed_at + make_interval(mins => v_off))::date as day
                    from quiz_attempts
                   where user_id = v_user and completed_at is not null) t
              on t.id = a.attempt_id
            join quiz_questions q on q.id = a.question_id
           where a.user_id = v_user
             and q.unit_label is not null
             and t.day between v_prev and v_today
           group by q.unit_label
          having count(*) filter (where t.day >= v_from) > 0
        ) u),
    'streak', (select json_build_object('current', current_streak,
                                        'best', best_streak)
                 from streaks where user_id = v_user),
    'mistakes_due', (select count(*) from flashcards c
                       join flashcard_decks d on d.id = c.deck_id
                      where c.user_id = v_user and d.is_mistakes
                        and c.due_at <= now())
  );
end $$;

revoke execute on function app_private.week_totals(uuid, date, date, int) from public;
revoke execute on function public.get_weekly_report() from public, anon;
grant execute on function public.get_weekly_report() to authenticated;

notify pgrst, 'reload schema';
