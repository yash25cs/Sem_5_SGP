# StudyTrail — Supabase backend

Postgres schema, RLS, RPCs, Storage, and the Gemini Edge Functions for the
StudyTrail Flutter app. Nothing here touches `studytrail_ui.html` or the
existing Flutter UI.

```
supabase/
  config.toml          # local/dev project config
  migrations/          # ordered SQL — apply 0001 → 0012
  all_migrations.sql   # GENERATED: all twelve concatenated, for the SQL editor
  functions/           # Edge Functions: embed-material, chat, generate-*, summarize-material, delete-account, _shared/
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

Seven are written, all under `functions/`:

| Function | Body | Does |
|---|---|---|
| `embed-material` | `{materialId, force?}` | Downloads the file from the private `materials` bucket, splits it into sections (PDF via Gemini's document vision, `.txt`/`.md` locally), embeds each at 768 dimensions, replaces that material's `material_chunks` rows, then flips `status` to `embedded`. |
| `chat` | `{threadId, question, subjectId?}` | Embeds the question, retrieves through `match_material_chunks`, answers from those excerpts only, and writes **both** turns to `chat_messages` plus `chat_citations`. |
| `generate-roadmap` | `{goalId}` | Reads the goal, its subjects and the distinct `unit_label`s across the student's materials, writes a weekly plan (2–12 weeks from `exam_date`/`pace`), **replaces** the goal's `milestones` + `milestone_tasks`, and sets `goals.roadmap_days` / `current_day`. |
| `generate-quiz` | `{materialId, length?}` | Reads one material's chunks in order, writes a 5/10/15-question MCQ set into `quizzes` + `quiz_questions`. Appends — `quiz_attempts` history hangs off the quiz row. |
| `generate-flashcards` | `{materialId, count?}` | Same source, writes a new `flashcard_decks` row plus 10/20/30 `flashcards`, each pointing back at the chunk it came from. Every card lands due immediately. |
| `summarize-material` | `{materialId}` | Same even sample of one material's chunks, returned as 5–10 bullet points. Writes nothing. |
| `delete-account` | — | Removes the caller's `materials/<uid>/` objects, their rows, then the auth user (every user table cascades from it). Service-role, identity from the JWT only. |

All seven verify the JWT (`verify_jwt = true` in `config.toml`) and take the
caller's identity from it. A `user_id` in the request body is never read.

### The `service_role` boundary

`embed-material`, `chat`, `generate-flashcards` and `summarize-material` use **no** elevated key. Each
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

`delete-account` is the third holder of the key, for the one thing no user
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
npx --yes supabase@latest functions deploy embed-material chat generate-roadmap generate-quiz generate-flashcards summarize-material delete-account --use-api --project-ref tmakrbqggezkxtygythc
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
