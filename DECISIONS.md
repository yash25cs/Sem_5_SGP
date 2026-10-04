# StudyTrail decisions

This is the record of meaningful engineering decisions: what was chosen, why,
and the accepted trade-off. Update it whenever implementation changes involve a
non-trivial choice.

## Decision log

### D-001 — Keep the existing HTML prototype unchanged

- **Decision:** Preserve `studytrail_ui.html`; build the production frontend in
  `studytrail_flutter/` and backend assets in `supabase/`.
- **Why:** The HTML gallery is a useful visual reference and is a separate
  deliverable. Replacing it would risk losing approved UI work.
- **Trade-off:** Two UI representations must stay visually aligned.

### D-002 — Supabase for the mobile backend

- **Decision:** Use hosted Supabase for Auth, PostgreSQL, Storage, Realtime,
  Row Level Security, and Edge Functions.
- **Why:** It gives the Flutter app a direct, low-latency data layer without a
  separately hosted application server or mobile cold starts.
- **Trade-off:** Database schema and RLS policies must be designed carefully;
  PostgREST query limitations shape some repository queries.

### D-003 — Provider stores and repositories

- **Decision:** Screen widgets talk to `ChangeNotifier` stores; stores talk to
  repositories; repositories own Supabase calls.
- **Why:** It keeps rendering, async state, and persistence responsibilities
  separate and testable.
- **Trade-off:** More files than direct screen-to-database calls, but clearer
  error handling and less duplicated logic.

### D-004 — Scope data stores to the authenticated user

- **Decision:** Put the signed-in store scope above the Navigator and key it by
  user id.
- **Why:** Pushed pages need access to the same stores, while a user switch
  must discard the previous user’s cached data.
- **Trade-off:** Stores reload after sign-in/sign-out, intentionally favouring
  privacy and correctness over cache reuse.

### D-005 — Server-side scoring and spaced repetition

- **Decision:** Keep quiz scoring, XP awards, streak updates, and SM-2 card
  scheduling in Supabase RPCs.
- **Why:** A client can be altered; the backend is the authority for progress
  and rewards.
- **Trade-off:** The app needs network access to finalise those actions.

### D-006 — Gemini only in Edge Functions

- **Decision:** Use Gemini free-tier models from Supabase Edge Functions, not
  directly from Flutter.
- **Why:** The Gemini API key must remain secret and requests must derive the
  authenticated user from the Supabase JWT.
- **Trade-off:** AI features require Edge Function deployment and a Gemini key
  before they can be enabled.

### D-007 — Fetch flashcard statistics separately

- **Decision:** Query `flashcard_decks` and the aggregate `deck_stats` view
  separately, then merge the results in `FlashcardRepository`.
- **Why:** PostgREST cannot embed a `GROUP BY` view because it cannot infer a
  foreign-key relationship, producing `PGRST200`.
- **Trade-off:** One extra lightweight query avoids a schema workaround and
  keeps the statistics view secure with `security_invoker`.

### D-008 — Keep generated credentials out of source control

- **Decision:** Use gitignored `studytrail_flutter/dart_define.json` with
  `--dart-define-from-file` for the project URL and publishable key.
- **Why:** Developers can run the app without hardcoding environment-specific
  values in Dart files.
- **Trade-off:** Each development machine needs a local configuration file.

### D-009 — Use a clean baseline, then daily feature commits

- **Decision:** Create one honest baseline commit for the current working
  Flutter/Supabase implementation, then deliver one focused feature or fix per
  daily commit.
- **Why:** The workspace was developed before Git was initialised. Artificially
  splitting the existing snapshot into a fake history would make debugging and
  review less trustworthy.
- **Trade-off:** The first commit is larger, but every later change is small,
  reviewable, and traceable in `DAILY_PLAN.md`.

### D-010 — Do not publish test-account credentials

- **Decision:** The backend verification helper requires a test email and
  password at runtime instead of embedding a default test account.
- **Why:** Test credentials are still credentials; publishing them makes the
  live project unnecessarily vulnerable and creates cleanup work.
- **Trade-off:** Running the helper requires two explicit command arguments.

### D-011 — Ingestion and chat functions act as the caller, not as `service_role`

- **Decision:** `embed-material` and `chat` build their Supabase client from the
  request's own `Authorization` header, so RLS decides what they can read and
  write and `match_material_chunks` resolves `auth.uid()` to the real caller. No
  service-role key is used or stored for either function.
- **Why:** Every table they touch — `material_chunks`, `chat_messages`,
  `chat_citations` — is still owner-insertable, so the elevated key would buy
  nothing and would make a `user_id` in the request body meaningful, which is
  exactly what `OWNERSHIP.md` forbids.
- **Trade-off:** `generate-quiz` and `generate-roadmap` cannot follow this
  pattern: `0008_rewards.sql` revokes `insert` on their tables from
  `authenticated`, so they will need the service-role key and must verify the
  JWT themselves before writing.
- **Extended by D-019** on 2026-09-01, which is that trade-off arriving.
  `generate-flashcards` turned out to belong on this side of the line.

### D-012 — Read PDFs with Gemini's document vision, not a Deno PDF parser

- **Decision:** `embed-material` sends the PDF to Gemini as a `document` input
  and asks for ordered, unit-labelled sections. `.txt` and `.md` are split
  locally with no model call.
- **Why:** Neither Deno nor Docker is installed on the development machine, so a
  bundled parser could not be run even once before deploying, and pdf.js under
  the Edge Runtime is a common source of crashes. Gemini also keeps headings and
  table text readable, which a raw text extractor usually loses.
- **Trade-off:** Ingestion costs one generation call per document and is capped
  at roughly 14 MB per PDF, since the file has to be inlined as base64. Large
  files will need the Gemini Files API later.

### D-013 — Request shape for Gemini's Interactions API degrades instead of failing

- **Decision:** `_shared/gemini.ts` reads the API base URL and model ids from
  function secrets, and on a `400` that names `response_format`,
  `system_instruction` or `generation_config` it retries with a simpler request
  — down to asking for JSON in words and parsing it defensively.
- **Why:** Google's own documentation disagrees with itself about the
  Interactions endpoint (`/v1beta` vs `/v1beta2`) and about whether
  `response_format` is an object or an array. None of it can be verified locally
  without Deno, so the first real test is a deploy against live infrastructure.
- **Trade-off:** More code than a single request shape, and a wrong guess costs
  an extra round trip before it corrects itself.
- **Superseded by D-014** on 2026-08-22, once the live deploy made guessing
  unnecessary.

### D-014 — One measured request shape, not a degradation ladder

- **Decision:** Supersedes D-013. `interact()` sends exactly one shape —
  `POST /v1beta/models/{model}:generateContent` with camelCase
  `systemInstruction` and `generationConfig` — and reads the answer from
  `candidates[0].content.parts[].text`. The retry ladder, the `prependText`
  fallback and the `generateContentFallback` path are deleted.
- **Why:** Deploying settled every question the docs left open. The shape above
  works with `systemInstruction`, with `responseMimeType` +`responseSchema`, and
  with an inlined PDF. `/v1beta/interactions` does answer, but it appears in no
  model's `supportedGenerationMethods` and it re-enables thinking;
  `/v1beta2/interactions` is a 404.
- **Trade-off:** A future API change now fails outright instead of limping. That
  is the better failure: the ladder turned a wrong guess into a slow, silent
  degradation, and a hard 400 with the response body logged is diagnosable in
  one deploy.

### D-015 — Every Gemini call runs under a deadline

- **Decision:** `post()` takes a `budgetMs` for the whole call and an
  `attemptMs` per try, and each `fetch` carries `AbortSignal.timeout`. Chat asks
  for 30 s, PDF sectioning 90 s, embeddings 40 s with 20 s attempts. A timeout
  surfaces as `503 "The AI took too long to answer. Try again."`.
- **Why:** An unbounded call hits the Edge Runtime's own ceiling instead —
  `HTTP 546 {"code":"WORKER_RESOURCE_LIMIT"}` — and the worker is killed before
  it can write an error, so the student sees a blank failure with nothing in the
  logs. This is the reported symptom "it takes so much time and tells me to try
  again."
- **Trade-off:** A genuinely slow-but-successful answer is now thrown away. With
  the model in D-016 answering in under a second, that trade is close to free.

### D-016 — `gemini-3.5-flash-lite` for text, because thinking models never answer

- **Decision:** `GEMINI_TEXT_MODEL` defaults to `gemini-3.5-flash-lite`.
- **Why:** Measured against this project's key on 2026-08-22, the previous
  default `gemini-3.7-flash` never answered inside 22 s — on
  `:generateContent` or `/v1beta/interactions`, thinking off or on. Worse,
  `gemini-3.6-flash` returned in 12.5 s with `finishReason: MAX_TOKENS` and
  **empty text**, because thinking spends the same token budget as the answer.
  `gemini-3.5-flash` answered in 923 ms but spent 39 of 40 tokens thinking.
  `-lite` does no thinking: 765 ms, and it still honours `systemInstruction`,
  JSON schemas, and inline PDFs. Ingesting a real PDF went from 124.7 s (which
  died on the worker limit) to 7.4 s; chat answers land in 5.4–7.5 s.
- **Trade-off:** A lite model reasons less well on a hard question. For a tutor
  quoting the student's own notes back at them the retrieved excerpts carry the
  reasoning, and an answer that arrives beats a better one that never does.
  Anything set in `GEMINI_TEXT_MODEL` needs re-timing before it is trusted —
  `outputText()` now names both silent failures (`MAX_TOKENS`, empty text) in
  the logs so a bad swap is obvious.

### D-017 — 20 materials per student, enforced in the store

- **Decision:** `OnboardingStore.maxMaterials = 20`, checked in
  `pickAndUpload` (an oversized multi-file pick is trimmed to the free slots
  rather than refused wholesale) and surfaced in both places a file can be
  added: the onboarding drop zone and the chat screen's materials sheet.
- **Why:** Cost and answer quality point the same way. Every file is read by
  Gemini once on upload and its chunks are searched on every question, and
  `match_material_chunks` returns the 6 best regardless of how many exist — so
  past a point more files stop improving answers and start diluting retrieval,
  with a stray page from a half-related PDF outranking the right unit.
- **Trade-off:** A student with more than a semester's material has to remove
  something. Enforced client-side, so it is a guardrail rather than a security
  boundary; the real limits are the bucket quota and RLS.

### D-018 — Every request carries a deadline, and a failed startup gets a page

- **Decision:** Two layers. `TimeoutHttpClient` is passed to
  `Supabase.initialize`, so auth, REST, storage, and the functions all inherit a
  cap — 20 s for a plain round trip, 180 s where the work is legitimately long
  (`/functions/v1/`, `/storage/v1/`). On top of that, `RootFlow`'s entry check
  gets its own 10 s deadline and, if it fails, renders `ErrorScreen` with a
  **Try again** button instead of falling through to onboarding.
- **Why:** Opening the app with no internet left it on the splash spinner
  forever. Nothing in the Supabase Dart packages sets a timeout and neither does
  Dart's own client, so two things hang indefinitely: a network that accepts the
  connection and never answers (a captive portal, or full bars with no data),
  and an expired persisted session — `SupabaseClient` refreshes the token before
  every query and gotrue retries that refresh on a backoff ladder. Separately,
  `_resolveEntryStage`'s `catch` swallowed the failure and landed on the upload
  screen, so a returning student on a train was told to upload their syllabus
  again and every write they tried then failed.
- **Trade-off:** A genuinely slow-but-working connection can now be cut off at
  the deadline, which is why uploads and AI calls get 180 s rather than 20 s —
  `embed-material` alone budgets 90 s to read a PDF. The startup probe's 10 s is
  the tightest of the three because it sits between a student and their first
  frame; it covers a token refresh plus one `select … limit 1` and nothing more.
  Deliberately no `connectivity_plus`: it reports "Wi-Fi is connected", not
  "the internet works", so it would add manifest surface for a worse signal
  than a request that actually failed. The offline screen offers no **Sign out**:
  it would work (gotrue clears the local session before it tries to revoke it
  server-side) but it leads nowhere, because signing back in needs the network
  that just failed. It is offered on the non-network screen, where retrying
  can't help and a different account might.

### D-019 — `service_role` only where the schema forbids the student to write

- **Decision:** `_shared/supa.ts` gains `adminClient()`, and exactly two
  functions use it: `generate-roadmap` and `generate-quiz`, and only for the
  artefact inserts. Every read, every ownership check, and the `user_id` on every
  inserted row still come from `requireUser()`'s caller-scoped client — a
  `user_id` in the request body is never read. `generate-flashcards` gets no
  admin client at all, because `insert (user_id, deck_id, unit_label, front,
  back, source_chunk_id) on flashcards` is granted to `authenticated`; it lives
  server-side for the Gemini key, not for the write.
- **Why:** This is D-011's predicted trade-off arriving. `0008_rewards.sql`
  revokes `insert` on `milestones`, `milestone_tasks`, `quizzes` and
  `quiz_questions` from `anon, authenticated` — all four are XP-bearing if
  forged, and a self-authored quiz with known answers would be 10 XP a question
  — so there is no client path to a roadmap or a quiz at all. Its own comment
  prescribes the fix: write with the service-role key *after* verifying the JWT.
  `SUPABASE_SERVICE_ROLE_KEY` is injected into the Edge Runtime automatically, so
  this needs no secret to set and no migration.
- **Trade-off:** Two functions now hold a key that bypasses RLS, so their
  ownership checks are load-bearing in a way `chat`'s aren't: a missing
  `.eq('id', …)` on the caller's client would become a cross-account write rather
  than an empty result. Both keep `verify_jwt = true`, both scope the write to
  `Caller.userId`, and both delete what they just inserted if the child rows
  fail, so a partial artefact never survives. Rejected: a `SECURITY DEFINER` RPC
  in a new migration — it keeps the key out of the function environment entirely
  but needs another SQL-editor step on the hosted project and duplicates the
  validation into PL/pgSQL.

### D-020 — Generated practice reads one named material, not a vector search

- **Decision:** The student picks a file; `generate-quiz` and
  `generate-flashcards` read `material_chunks where material_id = ? order by
  chunk_index` and pass the text to Gemini. No `embedTexts` call and no
  `match_material_chunks`. `generate-roadmap` is the exception — being
  goal-shaped, it reads the goal, its subjects, and the distinct `unit_label`s
  across the student's materials (headings only, no chunk bodies).
- **Why:** With the file already chosen there is nothing to search *for*.
  Retrieval would return the 6 best fragments, and a 15-question quiz drawn from
  6 fragments is a quiz about whichever passage embedded best. Reading the
  document in order also sidesteps a live gap: `embed-material` writes
  `subject_id: null` on every chunk, so any subject-scoped retrieval matches
  nothing.
- **Trade-off:** A long book has to be trimmed to fit the prompt, so
  `_shared/material.ts` caps the source at ~60k characters by **sampling evenly
  across the chunks** rather than truncating at the front — deliberately, because
  head truncation would make every quiz a quiz about chapter 1. Generation is
  therefore per-file: "quiz me on everything" isn't offered, and generated
  quizzes and decks carry no `subject_id` until materials are associated with
  subjects.

### D-021 — Validate and drop per item, then insist on a minimum

- **Decision:** Every generated item is checked in Deno before the insert and bad
  ones are dropped: a question needs exactly four distinct non-empty options and
  an integer `correct_index` in 0–3; a card needs a front and a back, deduped by
  front; a milestone needs a title and at least one task. If fewer than 3
  questions (4 cards, 2 milestones) survive, the function fails with a readable
  message instead of saving a stub.
- **Why:** `quiz_questions` carries `check (array_length(options,1) = 4)` and
  `check (correct_index between 0 and 3)`, and Postgres applies them to the whole
  batch — one malformed question would reject all fifteen, turning a mostly-good
  generation into a total failure. Dropping the bad item saves the rest.
- **Trade-off:** A student can ask for 15 questions and get 12, so the client
  reports what actually landed (`FlashcardStore.generatedCards`, the quiz's own
  `length`) rather than what was requested. Roadmap weeks are renumbered after
  the drop, so a plan never reads Week 1, 2, 4.

### D-022 — One work item, one XP path: `complete_task`

- **Decision:** A generated roadmap reaches Home through `daily_tasks` rows that
  carry `milestone_task_id` (`HomeStore.planDayFromRoadmap`, one milestone at a
  time), and from then on **both** screens tick that work through the
  `complete_task` RPC. `RoadmapRepository.toggleTask` looks up the linked
  `daily_tasks` row first and only writes `milestone_tasks.done` directly when
  there isn't one. Whichever screen the student taps, the other is reloaded by
  the screen that owns the tap — the same cross-store refresh `_createGoal` does
  for `ProfileStore`.
- **Why:** `complete_task` mirrors `milestone_tasks.done` inside its own
  transaction, so linking the two tables makes one checkbox out of two rows. But
  it is also idempotent by design (`if v_before.done = p_done then return
  v_before`), so it pays exactly once — and that cuts both ways. A bare `update
  milestone_tasks set done = true` from the Roadmap tab would leave Home still
  asking for finished work, and the reconciling tick from Home afterwards would
  find `done` already matching and pay nothing. Routing through the RPC is what
  keeps the student's XP attached to the work rather than to which tab they
  happened to be on.
- **Trade-off:** A roadmap tick now costs an extra round trip (the lookup) even
  when the task was never scheduled, and `milestones.state` plus
  `goals.overall_percent` are still derived afterwards by the client
  (`resyncMilestoneForTask`, `recompute_goal_progress`) because the RPC doesn't
  touch either — three writes where a trigger would do one. Both resyncs run
  outside the mutation and are swallowed on failure, so the worst case is a
  progress bar one tick stale until the next load, never a lost tick. Verified
  live against the hosted project: the seeded insert is accepted with its link,
  the mirror fires, the second tick pays nothing, and the goal percentage moves.
- Seeding is capped at `HomeStore.plannedTasksPerDay` (4) so an 11-week plan
  doesn't land on today as 44 tasks, and the duplicate check is date-agnostic: a
  topic pulled in yesterday and left unticked is still the student's list, not a
  fresh one to hand them again.

### D-023 — A release build that works without the signing key, and Flutter's shrinker as-is

- **Decision:** `android/app/build.gradle.kts` reads signing values from
  `android/key.properties` when that file exists and **falls back to the debug
  signing config when it doesn't**, so `flutter build apk --release` succeeds on a
  fresh clone. `key.properties` and `*.jks`/`*.keystore` are gitignored, and the
  `keytool` command that creates the store lives in `SETUP.md` rather than being
  run here — a keystore password typed into a transcript is a published password.
  R8 and resource shrinking are left entirely to the Flutter Gradle plugin. The
  `applicationId` and `namespace` were shortened from
  `in.charusat.studytrail.studytrail_flutter` to `in.charusat.studytrail`, and
  `MainActivity.kt` moved to match.
- **Why:** Three separate things that all had to be decided before the first real
  build. The signing fallback is what keeps the repository buildable by someone
  who doesn't have the key — the alternative, failing configuration when
  `key.properties` is missing, punishes every contributor for a file only the
  publisher can have. The shrinker: `FlutterPlugin.kt` sets **both**
  `isMinifyEnabled = true` and `isShrinkResources = true` for release, so the
  `isMinifyEnabled = false` this file carried at first turned off half of a pair
  and AGP refused to configure at all — *"Removing unused resources requires
  unused code shrinking to be turned on"*. Each plugin's keep rules arrive inside
  its AAR, so there was never anything to hand-write; the earlier worry about
  per-plugin rules was simply wrong. And the `applicationId` is frozen at first
  publish: nothing has been published, so the only cheap moment to drop the
  duplicated Flutter project name from it was now, while it cost two Gradle lines
  and one Kotlin file. It already had to match the OAuth scheme in
  `AndroidManifest.xml` (`in.charusat.studytrail://login-callback`), which the
  long form did not.
- **Trade-off:** A release APK built without `key.properties` is signed with the
  debug key — it installs and runs, which is exactly what makes it useful for
  device testing, but it cannot be published and cannot be upgraded in place by a
  later properly-signed build. That is a footgun, so `SETUP.md` says it in the
  same breath as the command. R8 means a release crash can land in obfuscated
  plugin code rather than readable stack frames; the mapping file under
  `build/app/outputs/mapping/release/` is what makes that recoverable, and the
  manual pass in `SETUP.md` exercises a release build on a device rather than
  trusting that the debug build's behaviour carries over. The `applicationId`
  change means the first build after it **installs alongside** any older copy
  instead of upgrading it — a one-time uninstall, and nothing is lost that isn't
  in Supabase.

### D-024 — Study rooms: every membership change is an RPC

- **Decision:** `0011_study_rooms_fix.sql` revokes the client's INSERT on
  `room_members` and INSERT/UPDATE/DELETE on `study_rooms`. Creating, joining and
  closing go through `create_study_room`, `join_room_by_code` and
  `close_study_room`; the lobby's Join button calls `join_room_by_code` with the
  room's own code. Leaving stays a plain delete of your own row, and a trigger
  closes the room when the host or the last member leaves. Member names come from
  `get_room_members()`, which checks membership before reading past the
  owner-only `profiles` policy.
- **Why:** 0010's `members_select` read `room_members` inside its own policy, so
  every query touching the table failed with 42P17 and the repository hid it
  behind empty lists — lobby, member list and saved chat were all silently dead.
  Fixing only the recursion would have left `members_insert` letting anyone insert
  themselves into any room as `host`, past the capacity and closed-room checks.
  Each of those checks needs a lock or a read the client can't be trusted with, so
  the write moved behind the check instead of the check being copied into
  policies.
- **Trade-off:** Open rooms and who sits in them are visible to every signed-in
  student, as the lobby already implied. Broadcast and presence ride a public
  Realtime channel named after the room id; making them private needs Realtime
  Authorization policies, which this project hasn't enabled. A host whose app is
  killed leaves an "active" room behind until they open another (one open room
  per host) — the lobby hides rooms older than 12 hours in the meantime.

### D-025 — Rewards are bought with a balance, not with level XP

- **Decision:** `0012_rewards_store.sql` moves the store to the server. Balance =
  `sum(activity_log.xp_earned)` − `sum(reward_redemptions.cost_xp)`;
  `redeem_reward()` locks the student's profile row, checks balance and the
  holding cap, and inserts. Only rewards with a server-enforced effect are sold:
  the streak freeze (consumed inside `log_activity` when it covers every missed
  day of a 1–2 day gap) and the golden border (returned by
  `get_class_leaderboard`). The leaderboard ranks by total XP earned.
- **Why:** The previous screen kept "spent XP" in SharedPreferences, so purchases
  belonged to the phone rather than the student, and none of its four coupons did
  anything. It also measured against `profiles.xp`, which `award_xp` resets on
  every level-up, so levelling up lowered the balance — and the same column made
  the leaderboard rank a level-3 student below a level-1 one. `activity_log` is
  kept equal to every award since 0008, so it is the one number that means "XP
  ever earned".
- **Trade-off:** Spending never touches level or rank, so the store can't be used
  to lose places, but it also means rewards are "free" in leaderboard terms. The
  freeze is capped at two held, so a three-day absence always resets. Streak days
  are still `current_date` on a UTC server, so a day boundary falls at 05:30 IST —
  unchanged from 0008, and the freeze doesn't paper over it.

### D-026 — Offline flashcards queue grades; the server still grades

- **Decision:** Decks and every card due in the next seven days are cached on
  the phone per student. Offline, reviews come from that cache and each grade
  is queued; the next online load replays the queue through `apply_sr_grade`
  in order, dropping any the server refuses (a deleted card).
- **Why:** SM-2 scheduling and XP stay server-side (D-011, 0008). Computing a
  schedule on the phone would mean two implementations that drift, and XP a
  modified client could award itself.
- **Trade-off:** A card graded offline isn't rescheduled until sync, so it can't
  come round again in the same offline session.

### D-027 — Teachers see aggregates only, and nothing below three students

- **Decision:** `get_class_overview` returns totals, averages and a 14-day
  series for the class, plus units three or more students miss. Below three
  students it returns only the count. Teacher codes live in a table with no
  API access at all.
- **Why:** A "class average" of one student is that student's data. The
  project's privacy stance (README) says who sees what; a teacher view that
  showed individuals would break it.
- **Trade-off:** A teacher can't help one struggling student from the
  dashboard — that stays a conversation, not a query.
- **Superseded by D-030:** the teacher view was removed on 2 October 2026.

### D-028 — Long answers are graded, but pay no XP

- **Decision:** `grade-answer` stores its grade with the service-role key
  (insert is revoked from students) and awards nothing.
- **Why:** An AI grade can be retried until lucky or gamed by pasting the notes
  back in. XP stays tied to what the server can verify.

### D-029 — Planner dates come from the phone

- **Decision:** `get_roadmap_pace` and `plan_catch_up` take the student's own
  date, refused if more than a day from the server's.
- **Why:** The database clock is UTC; between midnight and 05:30 in India its
  "today" is yesterday, and Home lists tasks by the phone's date — tasks
  scheduled by the server in that window never appeared.
- **Trade-off:** Streaks (`log_activity`, 0008) still use the server's date;
  moving them is a larger change to every reward path.

### D-030 — StudyTrail is for students only

- **Decision:** The faculty view (D-027: teacher codes, `class_teachers`,
  `get_class_overview`, shared materials) is removed from the app, the
  migrations and the live database. `match_material_chunks` is back to the
  student's own chunks only, and `0019` is now the room quiz.
- **Why:** The app's audience is students. A second kind of account meant a
  second onboarding path, a dashboard most users never see, and class-shared
  notes leaking into every student's chat and quizzes.
- **Trade-off:** Notes a teacher had shared stop reaching the class, and a
  class's progress is no longer visible to anyone outside it.

### D-031 — A group quiz keeps its answers on the server until it's over

- **Decision:** The quiz, its questions and its players live in three tables
  with no client grants at all. Clients read through `get_room_quiz`, which
  leaves out the questions while voting, and the correct answers and other
  players' scores until the quiz is finished. Hand-ins are marked by
  `submit_room_quiz`. It starts only when every player has agreed, and one
  "no" cancels it. XP goes to the top three (30/20/10) only with at least two
  hand-ins and a score above zero, and for at most three paid quizzes a day.
- **Why:** Everyone gets the same questions, so any answer readable early —
  through the API or a broadcast — is the whole room's answer key. Requiring
  agreement means nobody is dragged into a quiz mid-focus-block. The XP rules
  stop two accounts trading wins, or a host farming solo podiums.
- **Trade-off:** Results reach other phones by a ping and a re-read rather
  than in the broadcast itself, so they can lag by up to the 15-second poll
  when a ping is missed. Someone who joins after a quiz is proposed sits that
  one out.

### D-032 — Room channels are private

- **Decision:** `room:<id>` is a private Realtime channel. Policies on
  `realtime.messages` admit a member of that room only, through
  `is_room_channel_member()`, which refuses any topic that isn't a room id.
- **Why:** On a public channel anyone who learned a room id could hear the chat
  pings, presence and quiz traffic, or send fake timer commands.
- **Checked:** a live two-account test shows an outsider refused, and a public
  channel of the same name hearing nothing, so the dashboard's "allow public
  access" setting can stay as it is.
- **Trade-off:** a member can still send a timer broadcast, and other members
  will follow it. Realtime checks authorization when you join, not per
  message, and a broadcast carries no verified sender, so "host only" can't be
  enforced for an event. Outsiders are what this closes.

### D-033 — The student's day, not UTC's

- **Decision:** the phone sends its UTC offset at sign-in (`set_utc_offset`);
  `log_activity`, the daily focus cap and the group-quiz cap use
  `app_private.local_today()`. India (330) is assumed until the phone says.
- **Why:** between midnight and 05:30 in India the server's date was
  yesterday, so studying then counted for the wrong day and could break a
  streak. One function fixes every reward path instead of a date parameter on
  each RPC (D-029 did that for the planner only).
- **Trade-off:** the task-XP daily cap in `complete_task` still resets on UTC.

### D-034 — Chat turns are written by the server

- **Decision:** `0020` revokes insert and update on `chat_messages` and
  `chat_citations`; the `chat` function writes both turns with the service
  key after checking the thread is the caller's.
- **Why:** `curious_learner` counts the student's questions, and a client could
  write — or rewrite — any turn, including "AI" ones.
- **Trade-off:** no offline or no-function fallback for sending; the app shows
  the error instead.

### D-035 — Speed rounds run on the server's clock

- **Decision:** a speed round's schedule is derived from `started_at` — a 5 s
  lead, then each question's window and a 4 s reveal. The server refuses late
  answers, scores speed from its own clock, and only returns a question's
  answer and its points once that window has closed. Phones draw the countdown
  from `server_now`.
- **Why:** players' phones disagree about the time by seconds; a fair speed
  bonus needs one clock, and the answer key must not leak while anyone can
  still answer (D-031).
- **Trade-off:** no pause, and a slow network eats into thinking time — the
  1.5 s grace covers the trip, not a bad connection.

### D-036 — The doubt board is class-scoped and RPC-only

- **Decision:** doubts belong to a class; every read and write is an RPC that
  checks the caller's class; blocks hide a person's posts. The AI's answer is
  one per doubt, requested by the asker only, written from the asker's notes,
  and labelled as such.
- **Why:** names live in owner-only profiles, and each write has a rule the
  client can't be trusted with (same class, own post, daily limits). Writing
  the AI answer from anyone else's notes would show classmates material that
  isn't theirs to see.
- **Trade-off:** reports are reviewed in the dashboard; there is no moderator
  role in the app (students only, D-030).

### D-037 — The phone reads YouTube captions; the server only embeds them

- **Decision:** the app fetches a video's captions (and a playlist's video
  list) from YouTube itself, uploads the transcript as a `.txt`, and
  `embed-material` chunks it on its timestamps. No Gemini video call.
- **Why:** measured on 2026-10-02. From Supabase's servers YouTube's player API
  answered every client with "Sign in to confirm you're not a bot"; from a home
  connection the same call returned caption tracks needing no extra token.
  Gemini can watch a YouTube URL, but a cold 60-second clip took 80 s and a
  10-minute video didn't finish in 115 s — a lecture would outlive the
  function. Captions cost no AI tokens and a 45-minute lecture embeds in 9 s.
- **Trade-off:** a video without captions can't be added. The calls are the
  ones YouTube's own apps make, not a published API, so a YouTube change can
  break them; the playlist list falls back to the RSS feed (first 15 videos),
  every failure is a plain sentence, and `test/live/youtube_live_test.dart`
  shows quickly whether YouTube still answers the same way.

### D-038 — A playlist is one library item, read three videos at a time

- **Decision:** a YouTube playlist is one `material_playlists` row that counts
  once against the 20-item limit; its videos are ordinary `video_link`
  materials pointing at it. The phone reads them three at a time in the
  background, and the playlist's stored video list lets an unfinished import
  carry on at the next launch.
- **Why:** one row per video spent a whole library on one course. The 20 cap
  exists for Gemini reading cost and retrieval noise; a video costs only an
  embedding call, and a course's own lectures are on-topic for its questions.
  Three at a time took a measured ~11.5 s per video down to ~4 s (92 videos:
  ~18 → ~6 minutes) at one embedding call each.
- **Trade-off:** the phone has to be on for the reading, since captions can
  only be fetched from it (D-037); a paused import shows **Resume** and picks
  up on its own at launch. One playlist page is read — 100 videos.
- **Rate limit (found in the first real run):** the free tier embeds about
  100 chunks a minute, and a 92-video playlist read three at a time ran past
  it in its second minute — 39 videos ended `failed`. A busy answer (429) now
  makes every worker wait a minute and the video go again; three cooldowns in
  a row with nothing read means the day's limit, so the reader pauses with
  the videos still queued. The playlist row has **Retry** for any left failed.

### D-039 — Every launch opens a new chat; the thread is written on the first question

- **Decision:** the chat screen opens empty each launch; past chats are in a
  history panel that slides in from the left. A `chat_threads` row is created
  by the first question, not by opening the screen or tapping New chat.
- **Why:** it is how every AI chat app the students use behaves, and a
  months-long single thread made old answers drown new ones. Writing the row
  late means the history only lists chats someone actually asked something
  in; the list reads each chat's first question in the same query, so no
  title column or title-writing call was needed.
- **Trade-off:** chats are named by their first question rather than an AI
  summary, and listed by when they started, not when they were last used.

### D-040 — Load only what's on screen, and pin functions next to the database

- **Decision:** tabs build when first opened; Home is fetched during the
  launch splash; independent reads run together; Edge Functions run in the
  database's region (`ap-southeast-2`); the font is bundled.
- **Why:** measured from India, a query to the Sydney database costs ~300 ms
  and a function call 1.22 s (0.77 s pinned). The app paid that up to six
  times in a row on some screens, and fired ~27 requests at launch for tabs
  nobody had opened.
- **Trade-off:** a tab's first visit now loads then rather than at launch. The
  region is a constant (overridable with `SUPABASE_FUNCTIONS_REGION`) and
  must follow the database if the project ever moves. Moving the database to
  Mumbai would roughly halve every query again, but needs a new project.

## Update rule

For each meaningful decision, add the next `D-###` item with the decision,
reason, and trade-off. If a decision is superseded, keep it and add a new entry
that links back to it.
