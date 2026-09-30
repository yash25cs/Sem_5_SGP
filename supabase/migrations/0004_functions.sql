-- StudyTrail — functions, triggers, and RPCs.

-- ---------------------------------------------------------------------------
-- New-user bootstrap: seed profiles + streaks when an auth.users row appears.
-- SECURITY DEFINER so it can write past RLS during the auth transaction.
-- ---------------------------------------------------------------------------
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, avatar_initial)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    upper(left(coalesce(new.raw_user_meta_data->>'full_name', new.email, '?'), 1))
  )
  on conflict (id) do nothing;

  insert into public.streaks (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- RAG retrieval: cosine similarity over the caller's own chunks.
-- SECURITY INVOKER (default) → RLS on material_chunks scopes rows to auth.uid();
-- the explicit user_id filter is defensive belt-and-suspenders.
-- ---------------------------------------------------------------------------
create or replace function match_material_chunks(
  query_embedding vector(768),
  match_count int default 6,
  filter_subject uuid default null
)
returns table (
  id uuid,
  material_id uuid,
  subject_id uuid,
  unit_label text,
  content text,
  similarity float
)
language sql
stable
as $$
  select
    c.id,
    c.material_id,
    c.subject_id,
    c.unit_label,
    c.content,
    1 - (c.embedding <=> query_embedding) as similarity
  from material_chunks c
  where c.user_id = auth.uid()
    and c.embedding is not null
    and (filter_subject is null or c.subject_id = filter_subject)
  order by c.embedding <=> query_embedding
  limit match_count;
$$;

-- ---------------------------------------------------------------------------
-- Class leaderboard: exposes only safe columns for peers in the caller's class.
-- SECURITY DEFINER so it can read past the owner-only profiles policy, but it
-- hard-scopes to the caller's own class_id — no cross-class leakage.
-- ---------------------------------------------------------------------------
-- 0012 widens the return type; `create or replace` can't change one, so a
-- re-run of this file drops first. 0012 then re-creates its own version.
drop function if exists get_class_leaderboard(int);
create or replace function get_class_leaderboard(limit_count int default 20)
returns table (
  user_id uuid,
  full_name text,
  avatar_initial text,
  level int,
  xp int,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_class uuid;
begin
  select class_id into my_class from profiles where id = auth.uid();
  if my_class is null then
    return;
  end if;

  return query
    select p.id, p.full_name, p.avatar_initial, p.level, p.xp,
           (p.id = auth.uid()) as is_me
    from profiles p
    where p.class_id = my_class
    order by p.xp desc, p.level desc
    limit limit_count;
end $$;

-- ---------------------------------------------------------------------------
-- Spaced repetition (SM-2). Maps the 4-button grade to SM-2 quality, updates
-- ease / interval / repetitions / due_at, and returns the updated row.
-- SECURITY INVOKER → RLS ensures a user can only grade their own cards.
-- ---------------------------------------------------------------------------
create or replace function apply_sr_grade(card_id uuid, grade sr_grade_enum)
returns flashcards
language plpgsql
as $$
declare
  card       flashcards;
  quality    int;
  new_ease   numeric(4,2);
  new_reps   int;
  new_int    int;
begin
  select * into card from flashcards where id = card_id;
  if not found then
    raise exception 'flashcard % not found', card_id;
  end if;

  quality := case grade
    when 'again' then 1
    when 'hard'  then 3
    when 'good'  then 4
    when 'easy'  then 5
  end;

  -- Ease update, floored at 1.3.
  new_ease := greatest(1.3,
    card.ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)));

  if quality < 3 then
    new_reps := 0;
    new_int  := 1;
  else
    new_reps := card.repetitions + 1;
    new_int  := case
      when new_reps = 1 then 1
      when new_reps = 2 then 6
      else greatest(1, round(card.interval_days * new_ease))
    end;
  end if;

  update flashcards
    set ease          = new_ease,
        repetitions   = new_reps,
        interval_days = new_int,
        due_at        = now() + (new_int || ' days')::interval,
        last_grade    = grade
    where id = card_id
    returning * into card;

  return card;
end $$;
