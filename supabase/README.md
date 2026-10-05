# StudyTrail — Supabase backend

Postgres schema, RLS, RPCs, Storage, and the Gemini Edge Functions for the
StudyTrail Flutter app. Nothing here touches `studytrail_ui.html` or the
existing Flutter UI.

```
supabase/
  config.toml          # local/dev project config
  migrations/          # ordered SQL — apply 0001 → 0027
  all_migrations.sql   # GENERATED: all twenty-four concatenated, for the SQL editor
  functions/           # Edge Functions: embed-material, chat, generate-*, summarize-material, analyze-paper, grade-answer, room-quiz, doubt-ai, delete-account, _shared/
```

## What's in the migrations

| File | Contents |
|---|---|
| `0001_init_schema.sql` | `vector` + `pgcrypto` extensions, 7 enums, `classes`, `profiles`, `goals`, `subjects`, `milestones`, `milestone_tasks`, `daily_tasks` |
| `0002_features.sql` | `materials` + `material_chunks` (pgvector 768, HNSW cosine), flashcards w/ SM-2, `deck_stats` view, quizzes, streaks/activity/badges/sessions, chat tables |
| `0003_rls.sql` | Owner-only RLS (`auth.uid() = user_id`) on all 20 user tables; owner-scoped `profiles`; read-all `badges`/`classes` |
| `0004_functions.sql` | `handle_new_user()` trigger, `match_material_chunks()` (RAG), `get_class_leaderboard()`, `apply_sr_grade()` (SM-2) |
| `0005_storage.sql` | Private `materials` bucket + `/{uid}/…` prefix policies |
| `0006_seed.sql` | 10 badges + one default class (`CE-A 2025`) |
| `0007_activity.sql` | `activity_log` roll-up, streak advance, `finish_quiz_attempt()` |
| `0008_rewards.sql` | **Security.** `app_private` schema, `xp_rules`, server-derived XP + badge evaluation, column-level privileges. Closes REVIEW.md P0 |
| `0009_atomicity.sql` | `create_goal()` (three writes → one transaction), retryable material ingest. Closes REVIEW.md P1 |
| `0010_study_rooms.sql` | `study_rooms`, `room_members`, `room_messages` (Realtime-published), `create_study_room` / `join_room_by_code` / `close_study_room` |
| `0011_study_rooms_fix.sql` | **Fixes 0010.** Non-recursive `room_members` policy (0010's was 42P17 on every read), joins/creates/closes RPC-only, `get_room_members()` for names, `search_path` + input checks on the room RPCs, rooms auto-close when the host or last member leaves |
| `0013_room_moderation.sql` | `user_blocks`, `room_reports` (with a message snapshot), `room_bans`; `report_room_user()`, `remove_room_member()`; `join_room_by_code()` refuses a removed student |
| `0014_weak_topics.sql` | `quiz_questions.unit_label` / `source_chunk_id`, `quizzes.material_id`; `get_weak_topics()` ranks units by quiz misses and hard/again cards |
| `0015_catch_up.sql` | **Security:** `daily_tasks` UPDATE narrowed (resetting `rewarded_at` farmed XP). `goals.roadmap_started_on`; `get_roadmap_pace()` and `plan_catch_up()`, both taking the phone's date |
| `0016_exam_papers.sql` | `exam_papers`, `paper_questions`; `get_exam_topics()` — units ranked by how often past papers ask them |
| `0017_answer_practice.sql` | `answer_attempts` — graded long answers, insert-revoked from students (a client-written score would be self-chosen) |
| `0018_subject_exams.sql` | `subjects.exam_date`, and a trigger keeping the goal's date at the last subject exam |
| `0019_room_quiz.sql` | Rooms hold 2–6 (`create_study_room`); `set_room_timer()` (host sets focus/break inside the room); `room_quizzes`, `room_quiz_questions`, `room_quiz_players` with **no client grants**; `get_room_quiz()` / `get_active_room_quiz()` (answers only once finished, scores only your own until then), `vote_room_quiz()` (unanimous start, one "no" cancels), `submit_room_quiz()` (server-marked), `end_room_quiz()` (host); podium XP 30/20/10 from `xp_rules`, needing two hand-ins and a score above zero, three paid quizzes a day |
| `0020_hardening.sql` | **Security.** Room channels private (`realtime.messages` policies via `is_room_channel_member()`); a leaver no longer holds up a group quiz (trigger on `room_members`); `profiles.utc_offset_min` + `set_utc_offset()` so `log_activity`, the focus cap and the group-quiz cap use the student's day; `chat_messages` / `chat_citations` insert and update revoked (the `chat` function writes them) |
| `0021_study_tools.sql` | `profiles.answer_language` (en/hi/gu); the "My mistakes" deck (`flashcard_decks.is_mistakes`, `flashcards.mistake_key`) filled by triggers on `quiz_answers` and on a group quiz finishing; `get_weekly_report()` |
| `0022_speed_quiz.sql` | Speed rounds: `room_quizzes.mode` / `seconds_per_question`, `room_quiz_answers` (no client grants), `answer_room_quiz_question()` (500 + up to 500 for speed), `tick_room_quiz()`; `get_room_quiz()` shows a speed round's questions, answers and live points only as each window closes |
| `0023_doubts.sql` | The class doubt board: `doubts`, `doubt_answers`, `doubt_votes`, `doubt_reports`, all RPC-only (`get_class_doubts`, `get_doubt`, `post_doubt`, `answer_doubt`, `vote_doubt_answer`, `mark_doubt_solved`, `delete_*`, `report_doubt_content`); blocks hide a classmate's posts |
| `0024_playlists.sql` | A YouTube playlist is one library item: `material_playlists` (title, its video list, a skip list — only the skip list is updatable) and `materials.playlist_id` (cascade). A trigger refuses a video hung off someone else's playlist |
| `0025_goal_subject_dates.sql` | `create_goal` takes each subject's exam date (`p_subject_dates`, parallel to `p_subjects`), still one transaction; the old four-argument version is dropped |
| `0026_achievements_rewards.sql` | `app_private.badge_progress()` (progress, goal and unit for every badge) drives both `evaluate_badges` and the new `get_badge_progress()`; eight more badges; three more rewards — Focus Boost (doubles focus XP for a day, in `record_focus_session`), 50:50 lifeline (`use_quiz_lifeline()`), Aurora profile card |
| `0027_subject_syllabus.sql` | `materials.subject_id` (a syllabus belongs to a subject; its chunks carry the subject too) with an ownership trigger like 0024's |
| `0012_rewards_store.sql` | `reward_catalog` + `reward_redemptions`, `get_reward_wallet()` / `redeem_reward()` (balance = XP earned − XP spent), streak freezes consumed inside `log_activity`, `get_class_leaderboard()` ranked by total XP with `golden_border` |

All files are idempotent — safe to re-run.

> **0008 is not optional.** It *drops* `award_xp`, `log_activity`, and
> `unlock_badge`, and the app no longer calls them. A project still on 0007 will
> 404 on `complete_task` / `record_focus_session` / `evaluate_badges`; a project
> on 0008 running an older build of the app will fail on the dropped RPCs. Apply
> it and ship the matching build together.


## Setup

### 1. Create the hosted project

Sign in at [supabase.com](https://supabase.com) → **New project** (free tier).
Pick a region close to you (e.g. `ap-south-1` Mumbai) for lowest mobile latency.
Save the database password.

### 2. Apply the schema

**Option A — Dashboard (no CLI needed, fastest):**
Open **SQL Editor** → paste the contents of `all_migrations.sql` → **Run**.

**Option B — CLI:**

```bash
npx --yes supabase@latest login
```

```bash
npx --yes supabase@latest link --project-ref YOUR_PROJECT_REF
```

```bash
npx --yes supabase@latest db push
```

### 3. Enable pgvector

`0001` runs `create extension if not exists vector`. If it errors on the free
tier, enable **vector** under **Database → Extensions** first, then re-run.

### 4. Auth settings

**Authentication → Providers → Email**: enabled. For development turn
**Confirm email** OFF so signups can log in immediately.

**Authentication → URL Configuration**: add redirect URL
`in.charusat.studytrail://login-callback` (needed for Google OAuth later).

### 5. Grab the keys

**Project Settings → API** → copy the **Project URL** and **anon public** key.
These go into the Flutter app via `--dart-define` (never committed):

```bash
flutter run -d 3C15A60003Y00000 --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
```

The `anon` key is safe to ship — RLS is what protects the data. The
**service_role** key must never appear in the app.

## Verifying RLS

After signing up on the device, in the SQL editor:

```sql
select id, email, full_name from profiles;
select * from streaks;
```

Both should show exactly one row, auto-created by the `handle_new_user`
trigger. Because the SQL editor runs as `postgres` it bypasses RLS; to verify
the policies themselves, query PostgREST with a real user JWT.

## Edge Functions

Eleven are written, all under `functions/`:

| Function | Body | Does |
|---|---|---|
| `embed-material` | `{materialId, force?}` | Downloads the file from the private `materials` bucket, splits it into sections (PDF via Gemini's document vision, `.txt`/`.md` locally), embeds each at 768 dimensions, replaces that material's `material_chunks` rows, then flips `status` to `embedded`. |
| `chat` | `{threadId, question, subjectId?}` | Embeds the question, retrieves through `match_material_chunks` (the student's own chunks), answers in the student's chosen language, from those excerpts only, and writes **both** turns to `chat_messages` plus `chat_citations`. Returns three follow-up `suggestions` from the same model call. |
| `generate-roadmap` | `{goalId}` | Reads the goal, its subjects and the distinct `unit_label`s across the student's materials, writes a weekly plan (2–12 weeks from `exam_date`/`pace`), **replaces** the goal's `milestones` + `milestone_tasks`, and sets `goals.roadmap_days` / `current_day`. |
| `generate-quiz` | `{materialId, length?}` · `{weak: true}` · `{mock: true}` | Reads one material's chunks in order, writes a 5/10/15-question MCQ set into `quizzes` + `quiz_questions`. Appends — `quiz_attempts` history hangs off the quiz row. |
| `generate-flashcards` | `{materialId, count?}` · `{weak: true}` · `{messageId}` | Same source, writes a new `flashcard_decks` row plus 10/20/30 `flashcards`, each pointing back at the chunk it came from. Every card lands due immediately. |
| `summarize-material` | `{materialId}` | Same even sample of one material's chunks, returned as 5–10 bullet points. Writes nothing. |
| `analyze-paper` | `{paperId}` | Reads a past exam paper (PDF or photo) into `paper_questions`, each with its marks and one of the student's own unit labels. Replaces on re-read. |
| `grade-answer` | `{action:'question', unitLabel?}` / `{action:'grade', answer, questionId \| question+marks}` | Writes a 5/10-mark question from the student's notes (weakest unit by default), or grades a written answer against them and stores it in `answer_attempts` with the service-role key. No XP. |
| `room-quiz` | `{roomId, materialId, count: 5\|10\|15, mode?: 'speed', seconds?: 10\|20\|30}` | Host only. Writes one quiz from one of the host's own materials (the same writer as `generate-quiz`, `_shared/quiz.ts`) and enrols everyone in the room as a player, the host already agreeing. Inserts with the service-role key; voting, marking and XP are the `0019` RPCs. |
| `doubt-ai` | `{doubtId}` | The asker only, once per doubt: one first answer on the class doubt board, written from the asker's own notes (retrieval as the caller). Inserted with the service-role key; the doubt tables have no client grants. |
| `delete-account` | — | Removes the caller's `materials/<uid>/` objects, their rows, then the auth user (every user table cascades from it). Service-role, identity from the JWT only. |

All eleven verify the JWT (`verify_jwt = true` in `config.toml`) and take the
caller's identity from it. A `user_id` in the request body is never read.

### The `service_role` boundary

`embed-material`, `generate-flashcards` and `summarize-material` use **no** elevated key. Each
builds a `supabase-js` client that forwards the caller's `Authorization` header,
so RLS decides what they can see and `match_material_chunks` — security-invoker,
`where c.user_id = auth.uid()` — resolves to the right student. Every table they
write is owner-insertable, `flashcards` and `flashcard_decks` included
(`0008_rewards.sql` grants `insert (user_id, deck_id, unit_label, front, back,
source_chunk_id) on flashcards`), so an elevated key would buy nothing.

`generate-roadmap` and `generate-quiz` are the two exceptions, because
`0008_rewards.sql` revokes `insert` on `milestones`, `milestone_tasks`, `quizzes`
and `quiz_questions` from `anon, authenticated` — all four are XP-bearing if
forged. They call `adminClient()` in `_shared/supa.ts`, which reads the
auto-injected `SUPABASE_SERVICE_ROLE_KEY`; nothing to set, no migration. The rule
that keeps ownership intact once that key is in the room:

- every read and every ownership check still goes through the caller's client, so
  a goal or material that isn't theirs comes back empty and the function answers
  `404` before any write;
- every `user_id` written comes from the verified JWT;
- if the child insert fails, the parent rows just written are deleted, so a
  task-less milestone or an empty quiz never survives.

`chat` holds it only to write the two turns and their citations: `0020`
revoked those inserts so a client can't forge "AI" turns; the thread is checked
to be the caller's first, and retrieval runs as the caller. `doubt-ai` holds it
only to insert its one answer into `doubt_answers`.

`grade-answer` holds it only to insert into `answer_attempts`, which students
can't write (a client-inserted grade would be a self-chosen score); every read
it makes is the caller's. `room-quiz` holds it only to insert into the three
`room_quiz*` tables, which have no client grants at all — that is what keeps
the answers out of every client until the quiz is over; the room, the host
check, the member list and the material are all read as the caller. `delete-account` holds it for the one thing no user
token can do: `auth.admin.deleteUser`. It takes the user id from the verified
JWT and nothing else, so the only account it can delete is the caller's.

Deleting is not one of the exceptions: `delete on milestones` is still granted,
and the FK cascade removes `milestone_tasks` past their revoked `delete`. That is
what makes regenerating a roadmap replace rather than duplicate it.

Chunks are inserted **before** `status` becomes `embedded`, not after:
`app_private.material_status_guard()` (`0009_atomicity.sql`) raises `23514` on an
`embedded` material with no chunks, and it fires for every role including
`service_role`.

### Secrets

The Gemini key is a function secret, never a `--dart-define` — it must not ship
in the APK. Get one from [aistudio.google.com](https://aistudio.google.com) →
**Get API key**.

```bash
npx --yes supabase@latest secrets set GEMINI_API_KEY=your_key_here --project-ref tmakrbqggezkxtygythc
```

| Name | Default | Why you'd set it |
|---|---|---|
| `GEMINI_API_KEY` | — | Required. Without it both functions answer *"The AI features are not set up for this project yet."* |
| `GEMINI_TEXT_MODEL` | `gemini-3.5-flash-lite` | A newer text model — but re-time it first. Thinking models spend the answer's token budget on thinking and return empty text (see below). |
| `GEMINI_EMBED_MODEL` | `gemini-embedding-2` | Falling back to `gemini-embedding-001` — pair it with `GEMINI_EMBED_TASK_TYPE`, which `gemini-embedding-2` rejects. |
| `GEMINI_EMBED_DIM` | `768` | Only if `material_chunks.embedding` changes, which means re-embedding everything. |
| `GEMINI_API_BASE` | `https://generativelanguage.googleapis.com/v1beta` | Only `/v1beta` works — `/v1beta2` is a 404 despite what the migration guide says. |

#### The text model is load-bearing

Measured against this project's key on 2026-08-22, `:generateContent`, a
three-word prompt:

| Model | Latency | Result |
|---|---|---|
| `gemini-3.5-flash-lite` | 765 ms | Answers. No thinking tokens. **The default.** |
| `gemini-3.5-flash` | 923 ms | Answers, but 39 of 40 tokens were thinking. |
| `gemini-3.6-flash` | 12.5 s | `finishReason: MAX_TOKENS`, **empty text**. |
| `gemini-3.7-flash` | never inside 22 s | Unusable. Was the old default. |
| `gemini-2.5-flash`, `-lite` | — | `404`, retired for new keys. |

Swapping in a thinking model does not produce slow answers — it produces no
answers, and before the deadlines in `_shared/gemini.ts` it produced
`HTTP 546 WORKER_RESOURCE_LIMIT` with nothing in the logs. `outputText()` now
logs `finishReason` and the usage breakdown on both failure modes, so check the
function logs after any change here.

Custom names may not start with `SUPABASE_` — that prefix is reserved for the
`SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` the runtime
injects, and the first two are what `requireUser` reads.

### Deploying

`--use-api` bundles server-side, which is what makes this work with no Docker and
no Deno installed. The folder isn't linked (`supabase/.temp/` has no
`project-ref`), so every command names the project:

```bash
npx --yes supabase@latest login
```

```bash
npx --yes supabase@latest functions deploy embed-material chat generate-roadmap generate-quiz generate-flashcards summarize-material analyze-paper grade-answer delete-account --use-api --project-ref tmakrbqggezkxtygythc
```

The deploy is also the first real syntax check — nothing here can be type-checked
locally. Logs are in the dashboard under **Edge Functions → chat /
embed-material → Logs**; every handled failure logs the upstream reason there and
returns `{"error": "…"}`, which the app shows verbatim in a snackbar.

The generators are the ones worth watching in the logs: a model that returns
malformed items has them dropped per item (D-021), and the count that was dropped
is logged rather than surfaced, so "I asked for 15 and got 12" is answered there.

## Regenerating `all_migrations.sql`

It is a plain concatenation of `migrations/*.sql` in filename order:

```bash
cat supabase/migrations/*.sql > supabase/all_migrations.sql
```

Verify it by byte count — the output must equal the sum of the parts, which is
what proves nothing was reordered or dropped:

```bash
python -c "import glob,os;p=sorted(glob.glob('supabase/migrations/0*.sql'));print(sum(os.path.getsize(f) for f in p), os.path.getsize('supabase/all_migrations.sql'))"
```
