-- StudyTrail — 0023: the doubt board
--
-- A class's own Q&A. A student posts a doubt; classmates answer; answers can
-- be upvoted, and the asker marks the one that solved it. The `doubt-ai`
-- function can add one first answer, written from the asker's own notes.
--
-- Everything goes through the RPCs below — the tables have no client grants,
-- the way study rooms work (D-024): each write has a check the client can't
-- be trusted with (same class, own post, a daily limit), and names come from
-- profiles, which are owner-only. Blocks from 0013 apply: a blocked student's
-- doubts and answers are hidden from whoever blocked them.
--
-- Idempotent, like every migration here.

create table if not exists doubts (
  id         uuid        primary key default gen_random_uuid(),
  class_id   uuid        not null references classes(id) on delete cascade,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  subject    text        check (subject is null or char_length(subject) <= 80),
  title      text        not null check (char_length(title) between 5 and 200),
  body       text        check (body is null or char_length(body) <= 4000),
  solved_answer_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists doubts_class_idx on doubts(class_id, created_at desc);

create table if not exists doubt_answers (
  id         uuid        primary key default gen_random_uuid(),
  doubt_id   uuid        not null references doubts(id) on delete cascade,
  -- For an AI answer, the asker whose notes it was written from.
  user_id    uuid        not null references auth.users(id) on delete cascade,
  is_ai      boolean     not null default false,
  body       text        not null check (char_length(body) between 1 and 6000),
  created_at timestamptz not null default now()
);
create index if not exists doubt_answers_doubt_idx on doubt_answers(doubt_id, created_at);
create unique index if not exists doubt_answers_one_ai on doubt_answers(doubt_id) where is_ai;

do $$ begin
  alter table doubts add constraint doubts_solved_fk
    foreign key (solved_answer_id) references doubt_answers(id) on delete set null;
exception when duplicate_object then null; end $$;

create table if not exists doubt_votes (
  answer_id  uuid not null references doubt_answers(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  primary key (answer_id, user_id)
);

create table if not exists doubt_reports (
  id           uuid        primary key default gen_random_uuid(),
  reporter_id  uuid        not null references auth.users(id) on delete cascade,
  reported_id  uuid        not null references auth.users(id) on delete cascade,
  doubt_id     uuid        references doubts(id) on delete set null,
  answer_id    uuid        references doubt_answers(id) on delete set null,
  body         text,
  reason       text        not null
                           check (reason in ('spam', 'harassment', 'inappropriate', 'other')),
  status       text        not null default 'open'
                           check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);

alter table doubts        enable row level security;
alter table doubt_answers enable row level security;
alter table doubt_votes   enable row level security;
alter table doubt_reports enable row level security;
revoke all on doubts, doubt_answers, doubt_votes, doubt_reports
  from anon, authenticated;

-- The caller's class, or an error that says what to do about it.
create or replace function app_private.my_class()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_class uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select class_id into v_class from profiles where id = auth.uid();
  if v_class is null then
    raise exception 'Join your class first — the doubt board is shared with your classmates.';
  end if;
  return v_class;
end $$;

-- A doubt in the caller's class, or an error.
create or replace function app_private.class_doubt(p_doubt uuid)
returns doubts
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_row doubts;
begin
  select * into v_row from doubts
   where id = p_doubt and class_id = app_private.my_class();
  if not found then
    raise exception 'That doubt isn''t on your class''s board.';
  end if;
  return v_row;
end $$;

-- ── Reads ───────────────────────────────────────────────────────────────────
-- The class's board, newest first. p_filter: 'all' | 'open' (not solved) |
-- 'mine'.
create or replace function public.get_class_doubts(
  p_filter text default 'all',
  p_limit  int  default 40
)
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid   uuid := auth.uid();
  v_class uuid := app_private.my_class();
begin
  return coalesce((
    select json_agg(row_to_json(t) order by t.created_at desc)
      from (
        select d.id, d.title, d.subject, d.created_at,
               d.solved_answer_id is not null as solved,
               d.user_id = v_uid as is_mine,
               coalesce(nullif(btrim(pr.full_name), ''), 'Student') as author,
               pr.avatar_initial,
               (select count(*) from doubt_answers a
                 where a.doubt_id = d.id
                   and not exists (select 1 from user_blocks b
                                    where b.blocker_id = v_uid
                                      and b.blocked_id = a.user_id
                                      and not a.is_ai))::int as answers,
               exists (select 1 from doubt_answers a
                        where a.doubt_id = d.id and a.is_ai) as has_ai
          from doubts d
          join profiles pr on pr.id = d.user_id
         where d.class_id = v_class
           and not exists (select 1 from user_blocks b
                            where b.blocker_id = v_uid and b.blocked_id = d.user_id)
           and (p_filter = 'all'
                or (p_filter = 'open' and d.solved_answer_id is null)
                or (p_filter = 'mine' and d.user_id = v_uid))
         order by d.created_at desc
         limit least(greatest(coalesce(p_limit, 40), 1), 100)
      ) t), '[]'::json);
end $$;

-- One doubt with its answers: the solving answer first, then by votes.
create or replace function public.get_doubt(p_doubt uuid)
returns json
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid uuid := auth.uid();
  v_d   doubts := app_private.class_doubt(p_doubt);
begin
  return json_build_object(
    'id', v_d.id,
    'title', v_d.title,
    'body', v_d.body,
    'subject', v_d.subject,
    'created_at', v_d.created_at,
    'user_id', v_d.user_id,
    'is_mine', v_d.user_id = v_uid,
    'solved_answer_id', v_d.solved_answer_id,
    'author', (select coalesce(nullif(btrim(full_name), ''), 'Student')
                 from profiles where id = v_d.user_id),
    'avatar_initial', (select avatar_initial from profiles where id = v_d.user_id),
    'answers', (
      select coalesce(json_agg(row_to_json(t)
               order by (t.id = v_d.solved_answer_id) desc, t.votes desc,
                        t.created_at), '[]'::json)
        from (
          select a.id, a.body, a.is_ai, a.created_at, a.user_id,
                 a.user_id = v_uid and not a.is_ai as is_mine,
                 coalesce(nullif(btrim(pr.full_name), ''), 'Student') as author,
                 pr.avatar_initial,
                 (select count(*) from doubt_votes v where v.answer_id = a.id)::int as votes,
                 exists (select 1 from doubt_votes v
                          where v.answer_id = a.id and v.user_id = v_uid) as voted
            from doubt_answers a
            join profiles pr on pr.id = a.user_id
           where a.doubt_id = v_d.id
             and (a.is_ai or not exists (
                   select 1 from user_blocks b
                    where b.blocker_id = v_uid and b.blocked_id = a.user_id))
        ) t)
  );
end $$;

-- ── Writes ──────────────────────────────────────────────────────────────────
create or replace function public.post_doubt(
  p_title   text,
  p_body    text default null,
  p_subject text default null
)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid   uuid := auth.uid();
  v_class uuid := app_private.my_class();
  v_title text := btrim(coalesce(p_title, ''));
  v_id    uuid;
begin
  if char_length(v_title) < 5 then
    raise exception 'Say a bit more in the title — at least 5 characters.';
  end if;
  if char_length(v_title) > 200 or char_length(coalesce(p_body, '')) > 4000 then
    raise exception 'That doubt is too long.';
  end if;
  if (select count(*) from doubts
       where user_id = v_uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'That''s ten doubts today — try again tomorrow.';
  end if;
  insert into doubts (class_id, user_id, title, body, subject)
  values (v_class, v_uid, v_title, nullif(btrim(coalesce(p_body, '')), ''),
          nullif(btrim(coalesce(p_subject, '')), ''))
  returning id into v_id;
  return public.get_doubt(v_id);
end $$;

create or replace function public.answer_doubt(p_doubt uuid, p_body text)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid  uuid := auth.uid();
  v_d    doubts := app_private.class_doubt(p_doubt);
  v_body text := btrim(coalesce(p_body, ''));
begin
  if char_length(v_body) < 2 then
    raise exception 'Write an answer first.';
  end if;
  if char_length(v_body) > 6000 then
    raise exception 'That answer is too long.';
  end if;
  if (select count(*) from doubt_answers
       where user_id = v_uid and not is_ai
         and created_at > now() - interval '1 day') >= 50 then
    raise exception 'That''s a lot of answers for one day — try again tomorrow.';
  end if;
  insert into doubt_answers (doubt_id, user_id, body)
  values (v_d.id, v_uid, v_body);
  return public.get_doubt(v_d.id);
end $$;

-- Toggles the caller's upvote. Not on your own answer.
create or replace function public.vote_doubt_answer(p_answer uuid)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid uuid := auth.uid();
  v_a   doubt_answers;
begin
  select * into v_a from doubt_answers where id = p_answer;
  if not found then
    raise exception 'That answer has gone.';
  end if;
  perform app_private.class_doubt(v_a.doubt_id);
  if v_a.user_id = v_uid and not v_a.is_ai then
    raise exception 'You can''t upvote your own answer.';
  end if;
  delete from doubt_votes where answer_id = p_answer and user_id = v_uid;
  if not found then
    insert into doubt_votes (answer_id, user_id) values (p_answer, v_uid);
  end if;
  return public.get_doubt(v_a.doubt_id);
end $$;

-- The asker marks the answer that solved it; null un-marks.
create or replace function public.mark_doubt_solved(p_doubt uuid, p_answer uuid)
returns json
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_d doubts := app_private.class_doubt(p_doubt);
begin
  if v_d.user_id <> auth.uid() then
    raise exception 'Only whoever asked can mark it solved.';
  end if;
  if p_answer is not null and not exists (
       select 1 from doubt_answers where id = p_answer and doubt_id = v_d.id) then
    raise exception 'That answer isn''t on this doubt.';
  end if;
  update doubts set solved_answer_id = p_answer where id = v_d.id;
  return public.get_doubt(v_d.id);
end $$;

create or replace function public.delete_doubt(p_doubt uuid)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  delete from doubts where id = p_doubt and user_id = auth.uid();
  if not found then
    raise exception 'You can only delete your own doubt.';
  end if;
end $$;

create or replace function public.delete_doubt_answer(p_answer uuid)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  delete from doubt_answers
   where id = p_answer and user_id = auth.uid() and not is_ai;
  if not found then
    raise exception 'You can only delete your own answer.';
  end if;
end $$;

-- Reports a doubt or an answer, with a snapshot of what was said.
create or replace function public.report_doubt_content(
  p_reason text,
  p_doubt  uuid default null,
  p_answer uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_uid    uuid := auth.uid();
  v_author uuid;
  v_body   text;
  v_doubt  uuid := p_doubt;
begin
  if p_reason not in ('spam', 'harassment', 'inappropriate', 'other') then
    raise exception 'Pick a reason for the report.';
  end if;
  if p_answer is not null then
    select user_id, body, doubt_id into v_author, v_body, v_doubt
      from doubt_answers where id = p_answer and not is_ai;
  elsif p_doubt is not null then
    select user_id, title || coalesce(E'\n\n' || body, '') into v_author, v_body
      from doubts where id = p_doubt;
  end if;
  if v_author is null then
    raise exception 'There''s nothing there to report.';
  end if;
  perform app_private.class_doubt(v_doubt);
  if v_author = v_uid then
    raise exception 'You can''t report yourself.';
  end if;
  if exists (select 1 from doubt_reports
              where reporter_id = v_uid and status = 'open'
                and doubt_id is not distinct from v_doubt
                and answer_id is not distinct from p_answer) then
    return;
  end if;
  insert into doubt_reports (reporter_id, reported_id, doubt_id, answer_id, body, reason)
  values (v_uid, v_author, v_doubt, p_answer, left(v_body, 6000), p_reason);
end $$;

revoke execute on function app_private.my_class(),
                           app_private.class_doubt(uuid)
  from public;
revoke execute on function public.get_class_doubts(text, int),
                           public.get_doubt(uuid),
                           public.post_doubt(text, text, text),
                           public.answer_doubt(uuid, text),
                           public.vote_doubt_answer(uuid),
                           public.mark_doubt_solved(uuid, uuid),
                           public.delete_doubt(uuid),
                           public.delete_doubt_answer(uuid),
                           public.report_doubt_content(text, uuid, uuid)
  from public, anon;
grant execute on function public.get_class_doubts(text, int),
                          public.get_doubt(uuid),
                          public.post_doubt(text, text, text),
                          public.answer_doubt(uuid, text),
                          public.vote_doubt_answer(uuid),
                          public.mark_doubt_solved(uuid, uuid),
                          public.delete_doubt(uuid),
                          public.delete_doubt_answer(uuid),
                          public.report_doubt_content(text, uuid, uuid)
  to authenticated;

notify pgrst, 'reload schema';
