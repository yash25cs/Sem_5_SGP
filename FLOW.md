# StudyTrail execution flow

This is the living trace of how the application runs. Update it whenever a
meaningful file, service boundary, or user flow changes.

## Runtime path

```text
Flutter app starts
  -> SupabaseConfig reads compile-time dart defines
  -> Supabase.initialize
  -> StudyTrailApp provides ThemeController and AuthStore
  -> NotificationService initialises (device-local reminders)
  -> RootFlow checks the current auth session
      -> signed out: Welcome -> Sign up / Log in
      -> signed in, academic profile incomplete: Academic profile
      -> signed in with no goal: Upload material -> Set target
      -> signed in with a goal: HomeShell
  -> HomeShell keeps five tabs alive with IndexedStack
      -> Home | Roadmap | Chat | Quiz | Profile
      -> the + button opens Flashcards, Focus timer, Study rooms,
         Achievements, Leaderboard, Rewards, Analytics
```

## Data flow

```text
Screen widget
  -> Provider store (state/)
  -> Repository (data/repositories/)
  -> Supabase Flutter client
  -> Supabase Auth / PostgREST / Storage / RPC
  -> PostgreSQL with row-level security
```

Each signed-in user gets a fresh provider scope keyed by their user id. This
prevents cached study data from one account appearing for another account after
sign-out and sign-in.

Study rooms add a second path beside it: `RoomStore` also holds one Supabase
Realtime channel per room (`room:<id>`) for the host's timer broadcasts,
presence, and inserts on `room_messages`.

## Important user journeys

### Account and onboarding

1. `WelcomeScreen` takes the student to `SignupScreen` or `LoginScreen`.
2. Supabase Auth creates/authenticates the user.
3. `handle_new_user()` creates matching `profiles` and `streaks` rows.
4. `AcademicProfileScreen` saves college, program/branch with semester, and
   enrollment ID to `profiles`. A returning student missing any of those is sent
   here first on sign-in.
5. `UploadMaterialScreen` uploads a file to the private `materials` bucket or
   records a video link.
6. `SetTargetScreen` creates the active goal and its subjects.
7. `RootFlow` detects an existing goal on later launches and opens the app.

### Daily planning

1. Home loads profile, every goal (the newest active one wins), streak, today’s
   tasks, and the active goal’s subjects.
2. **Plan day** pulls the next unfinished milestone off the roadmap onto today’s
   list — up to `HomeStore.plannedTasksPerDay` rows at a time, each carrying its
   `milestone_task_id`. Anything already scheduled on any date is skipped, so a
   second tap moves on to the next week instead of duplicating a topic. This is
   the only thing that turns a generated roadmap into today’s work.
3. Completing a task calls `complete_task`, which writes `daily_tasks.done`,
   logs the study activity, awards XP once, rolls the streak, and — when the row
   came from the roadmap — flips `milestone_tasks.done` in the same transaction.
4. A tick from either tab refreshes the other: the same work shows on Home and on
   the Roadmap timeline, and the shell keeps both tabs alive.
5. Because `complete_task` doesn’t own the derived columns, a linked tick is
   followed by re-deriving the parent milestone’s `state` and calling
   `recompute_goal_progress`, which moves the hero card’s percentage.

### Learning tools

1. Flashcards (opened from the **+** button) read decks and cards from
   Supabase.
2. Grading a card calls the server-side `apply_sr_grade` RPC, which applies
   SM-2 scheduling.
3. Quiz choices are submitted to `finish_quiz_attempt`; correctness and XP are
   calculated on the server.
4. Chat sends the question to the `chat` Edge Function, which writes both the
   student's turn and the cited AI answer server-side; the app then reloads the
   thread.

### Generating practice

1. Flashcards and Quiz each have a **New** action that opens the shared
   `GenerateSheet`. It lists only materials whose `status` is `embedded` — an
   unread file has no chunks to generate from — and says how many are hidden.
2. The student picks one file and a size (10/20/30 cards, 5/10/15 questions).
   `generate-flashcards` / `generate-quiz` read that material's chunks in order,
   write the deck or quiz server-side, and the store reloads the list.
3. Generated cards are due immediately, so the Cards header's due count moves as
   soon as the deck appears. Each generation appends: quizzes keep their own
   `quiz_attempts` history, so replacing them would erase it.
4. The Roadmap tab's top-right action calls `generate-roadmap`, which reads the
   goal, its subjects, and the distinct unit labels across the student's
   materials, then **replaces** that goal's `milestones` and `milestone_tasks`
   and updates `goals.roadmap_days` / `current_day`. Because it replaces, the
   screen asks for confirmation when a roadmap already exists.
5. Malformed model output is dropped per item rather than failing the batch
   (`DECISIONS.md` D-021), so the app reports what actually landed — a request
   for 15 questions can produce 12.

### Study rooms

1. The lobby (`BuddyRoomScreen`) lists open rooms from the student's class plus
   unscoped ones, newest first, hiding any older than 12 hours.
2. Creating calls `create_study_room`, which validates the settings, closes any
   other room the host left open, and enrols the host. Joining — by typed code or
   the lobby's **Join** button — calls `join_room_by_code`, which checks the room
   is open and not full under a row lock.
3. Entering loads names through `get_room_members` (profiles are owner-only) and
   the last 50 messages, then subscribes to the room's Realtime channel.
4. Only the host drives the timer. Each start/pause/reset/phase change is a
   `timer` broadcast carrying the seconds left; members mirror it. When a new
   member's presence arrives, the host re-sends the current state as `sync`.
5. Chat inserts a `room_messages` row under an id the client picks, shows it
   immediately, and de-duplicates the Realtime echo on that id.
6. Leaving deletes the student's own membership row. A trigger closes the room
   when the host or the last member leaves; a host closing on purpose also
   broadcasts `room: closed` so members are told.

### Rewards and leaderboard

1. The Rewards screen reads `get_reward_wallet`: XP ever earned
   (`activity_log`) minus XP spent, plus the catalog and what the student holds.
2. **Redeem** calls `redeem_reward`, which locks the profile row, checks the
   balance and the holding cap, and records the purchase. Spending never
   changes level or rank.
3. A held Streak Freeze is spent inside `log_activity` the next time the student
   studies after missing one or two days, and the streak continues.
4. `get_class_leaderboard` ranks the student's class by total XP earned and says
   who owns the Golden Border. A student with no class is offered the class
   picker instead of a ranking.

### Reminders and account

1. `HomeShell` re-applies the reminder setting on open; Settings → **Daily study
   reminder** turns it on or off. It is a local notification scheduled on the
   phone at 18:00 device time, inexact, with no server involved.
2. Settings → **Delete account** calls the `delete-account` Edge Function, which
   removes the student's Storage objects and then the auth user; every user
   table cascades from it. The app then signs out.

### Material ingestion

1. The upload screen stores the file in the private `materials` bucket and
   inserts a `materials` row.
2. It then invokes `embed-material`, which downloads the file, splits it into
   sections, embeds each one, and writes `material_chunks`.
3. Chunks are inserted before `materials.status` becomes `embedded` — the
   `0009` status trigger rejects that status while a material has no chunks.
4. Video links are recorded but not read: `embed-material` refuses them and the
   screen says so.

## Backend boundaries

- Flutter may use only the Supabase URL and anon/publishable key.
- RLS limits every user-owned row to `auth.uid() = user_id`.
- The `materials` Storage bucket is private and scoped to `/{user-id}/...`.
- Gemini is called only from Supabase Edge Functions. Its API key is a function
  secret and never enters Flutter, requests, documentation, or version control.
- `embed-material`, `chat`, `generate-flashcards` and `summarize-material` act
  as the calling student: they forward the request's JWT to `supabase-js` and
  rely on RLS, so no service-role key is used in any of the four.
- `generate-roadmap` and `generate-quiz` are the only functions that hold the
  service-role key, because `0008_rewards.sql` revokes `insert` on `milestones`,
  `milestone_tasks`, `quizzes` and `quiz_questions` from `authenticated`. Even
  there, every read and every ownership check still goes through the caller's
  client, and every written `user_id` comes from the verified JWT — never from
  the request body (`DECISIONS.md` D-019).
- `delete-account` also holds the service-role key, for `auth.admin.deleteUser`
  only; the user it deletes is the one in the verified JWT.
- Study-room membership and room lifecycle change only through RPCs
  (`create_study_room`, `join_room_by_code`, `close_study_room`); the client can
  insert its own chat messages and delete its own membership, nothing else
  (`DECISIONS.md` D-024).
- XP spending is server-side: `reward_redemptions` has no client write grant, and
  `redeem_reward` is the only way in (`DECISIONS.md` D-025).

## Current implementation status — 30 September 2026

- Flutter UI and live-data wiring are implemented.
- Supabase schema, RLS, storage policies, seed data, and RPCs are applied,
  including `0008` and `0009` (verified on the hosted project: all seven reward
  RPCs resolve, and all 20 owner-scoped tables return nothing to an anon caller).
- The verified flashcard deck-count flow fetches the aggregated `deck_stats`
  view separately, then merges counts into deck rows in Flutter. PostgREST
  cannot embed an aggregated view because it has no foreign-key relationship.
- Material ingestion and cited AI chat are implemented as the `embed-material`
  and `chat` Edge Functions. Both are deployed and ACTIVE with `verify_jwt`, and
  the Gemini path is now exercised end to end: a real PDF uploaded by a signed-in
  student becomes unit-labelled chunks with `status = embedded` in 7.4 s, and
  chat answers from those chunks with citations in 5.4–7.5 s. The text model is
  `gemini-3.5-flash-lite` and that choice is load-bearing — see `DECISIONS.md`
  D-016 and the timing table in `supabase/README.md`.
- Every Gemini call runs under a deadline (`DECISIONS.md` D-015). Without one the
  Edge Runtime kills the worker with `546 WORKER_RESOURCE_LIMIT` before it can
  report anything, which reads to a student as a long wait and then "try again".
- A student may keep 20 materials (`DECISIONS.md` D-017). They can see and manage
  them from the chat screen's top-right button as well as from onboarding.
- Every Supabase request runs under an HTTP deadline and a failed cold start
  shows a retryable page rather than a spinner (`DECISIONS.md` D-018). Opening
  the app offline now says so on the first frame after the probe times out.
- Roadmap, quiz, and flashcard generation are implemented as three more Edge
  Functions (`generate-roadmap`, `generate-quiz`, `generate-flashcards`). All
  five are deployed and ACTIVE with `verify_jwt`, and the three new ones are
  verified against the live project: a generated quiz scores through
  `finish_quiz_attempt` and awards XP, generated cards land due immediately and
  reschedule through `apply_sr_grade`, regenerating a roadmap replaces it rather
  than duplicating it, and a second account gets `404` from all three. The dead
  `tune` button on the Roadmap header is now the generate action.
- A generated roadmap now reaches Home: **Plan day** seeds `daily_tasks` from the
  next unfinished milestone, and a tick from either tab moves the other and pays
  XP exactly once, through `complete_task` (`DECISIONS.md` D-022). Verified live,
  13/13 checks — the mirror fires, the second tick pays nothing, and the goal
  percentage moves. Before this, Home's only task-creation path (`addTask`) had no
  UI caller, so the checklist could not be filled at all.
- The four core writes are pinned down by tests at last: `test/stores_test.dart`
  covers signup bootstrap, goal creation, task-tick retry, and flashcard-grade
  retry against subclassed repositories, so store logic runs for real with nothing
  on the network. `test/rooms_rewards_test.dart` adds the room timer sync and the
  wallet/leaderboard parsing. `flutter test` is 27/27 and `flutter analyze` is
  clean.
- An Android release build is verified in the artefact, not just by an exit code:
  package `in.charusat.studytrail`, label `StudyTrail`, `versionCode 1` /
  `versionName 1.0.0`, `INTERNET` as the only declared permission at the time
  (the reminder later added `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED`), the adaptive
  icon surviving resource shrinking, and `apksigner` reporting `CN=Android Debug`
  — the `key.properties`-or-debug-key fallback working as designed. R8 and
  resource shrinking are left to the Flutter Gradle plugin, which sets both
  together (`DECISIONS.md` D-023). `SETUP.md` §7 has the build and signing steps.
- The physical-device regression pass is **not** done — it can't be from a machine
  with no phone attached. `SETUP.md` §8 is the 30-item checklist to run against
  the release APK, and it covers what a widget test structurally cannot: a real
  keyboard, a real network dropping mid-write, rotation, the launcher icon, and
  two phones in one study room.
- Real-time study rooms (Phase D) are implemented: `0010_study_rooms.sql` plus
  `0011_study_rooms_fix.sql`, which replaced 0010's recursive policy — before it,
  every room read failed on the live project. The database side is verified live
  (34/34 checks); the Realtime side (timer, presence, chat echo) still needs the
  two-phone pass.
- Rewards, the class leaderboard, notifications, the academic profile, the
  summary sheet and account deletion landed between 28 and 30 September. The
  rewards store and leaderboard were rebuilt on the server in `0012` (D-025),
  and all seven Edge Functions are deployed and ACTIVE with `verify_jwt`.

## Update rule

After every meaningful change, append a dated entry to the **Change log** below
and update the affected path above. Also record any design or technical choice
in `DECISIONS.md`.

## Change log

| Date | Change | Files / area | Verification |
|---|---|---|---|
| 2026-08-13 | Created the living project-flow document. | Root documentation | Initial flow reconciled with Flutter and Supabase implementation. |
| 2026-08-13 | Fixed flashcard deck statistics query. | `studytrail_flutter/lib/data/repositories/flashcard_repository.dart` | `flutter analyze` and web build succeeded; live deck statistics query returned correct counts. |
| 2026-08-15 | Completed a read-only architecture and security review. | `REVIEW.md` | Confirmed reward-RPC, multi-step write, chat-delivery, and test-coverage risks from source inspection. |
| 2026-08-15 | Added a daily GitHub delivery plan and root repository ignore rules. | `DAILY_PLAN.md`, `.gitignore` | Ready for a clean source-control baseline; local credentials and generated files are excluded. |
| 2026-08-15 | Removed test-account defaults from the backend verification helper before source-control setup. | `supabase/verify_backend.py` | Script now requires supplied test credentials and reads local Supabase defines from an ignored file. |
| 2026-08-15 | Initialised Git and pushed the StudyTrail baseline to GitHub `main`. | Repository root | Commit `aaf625a` is now the shared baseline; future work follows `DAILY_PLAN.md`. |
| 2026-08-20 | Added the `embed-material` and `chat` Edge Functions and wired both client paths. | `supabase/functions/`, `supabase/config.toml`, `studytrail_flutter/lib/data/repositories/{material,chat}_repository.dart`, `lib/state/{onboarding,chat}_store.dart`, `lib/screens/upload_material_screen.dart`, `lib/models/study_material.dart` | `flutter analyze` clean and `flutter build apk --debug` succeeded. End-to-end ingestion and cited chat still need `GEMINI_API_KEY` and a `functions deploy`. |
| 2026-08-21 | Deployed both Edge Functions and applied migrations `0008`/`0009` on the hosted project. | Hosted Supabase project (no source change) | `functions list` shows both ACTIVE with `verify_jwt`; an anon-key POST to each returned the functions' own 401 JSON, proving the Deno modules load and `requireUser` runs. All seven reward RPCs plus `create_goal` resolve; 20/20 owner tables return no rows to an anon caller. The Gemini request path is still unexercised. |
| 2026-08-22 | Exercised the Gemini path and fixed what it exposed: one measured request shape in place of the degradation ladder, per-call deadlines, and `gemini-3.5-flash-lite` as the text model. | `supabase/functions/_shared/gemini.ts`, `supabase/functions/{chat,embed-material}/index.ts` | Timed against the live key: the old default `gemini-3.7-flash` never answered inside 22 s and `gemini-3.6-flash` returned empty text on `MAX_TOKENS`. After the swap a real PDF ingested in 7.4 s (was 124.7 s, dying on `546 WORKER_RESOURCE_LIMIT`) producing 2 correctly unit-labelled chunks and `status = embedded`; chat answered "summarize this pdf" from them with citations in 5.4–7.5 s, and quoted an invented term planted in the PDF — proving the answer came from retrieval, not model knowledge. |
| 2026-08-22 | Fixed upside-down chat transcripts, and the same latent bug in ten other sorts. | `studytrail_flutter/lib/data/repositories/*.dart` | postgrest-dart's `order()` defaults to **descending**, the opposite of PostgREST's own default, so `getMessages` returned newest-first and every answer rendered above its question. All 11 `.order()` calls are now explicit; `flutter analyze` clean. |
| 2026-08-22 | Added a materials sheet to the chat screen, a 20-file cap, and an animated typing indicator. | `studytrail_flutter/lib/screens/{chat,upload_material}_screen.dart`, `lib/widgets/material_tile.dart`, `lib/state/onboarding_store.dart`, `lib/data/supabase_client.dart` | `flutter analyze` clean. The header button badges the file count and turns amber when nothing is searchable; the sheet lists every material with retry/remove and an add button that disables at the cap. `MaterialTile` was extracted so onboarding and chat show the same row. |
| 2026-08-23 | Gave every request a deadline and replaced the endless offline splash with a retryable error page. | `studytrail_flutter/lib/data/timeout_http_client.dart` (new), `lib/main.dart`, `lib/widgets/data_states.dart`, `pubspec.yaml`, `test/widget_test.dart` | Launching with no internet used to spin forever, because no Supabase package sets an HTTP timeout and gotrue retries the pre-query token refresh on a backoff ladder. `TimeoutHttpClient` now caps every sub-client (20 s queries, 180 s uploads and AI calls) and `RootFlow`'s 10 s entry probe renders `ErrorScreen` on failure instead of silently landing on onboarding. `flutter analyze` clean, `flutter test` 6/6 — including one that proves a host which accepts the connection and never answers throws `TimeoutException` — and `flutter build apk --debug` exit 0. |
| 2026-09-01 | Added the three generation Edge Functions and the UI that reaches them, closing the last Phase C gap. | `supabase/functions/{generate-roadmap,generate-quiz,generate-flashcards}/index.ts` (new), `functions/_shared/{supa,material}.ts`, `supabase/config.toml`, `studytrail_flutter/lib/data/repositories/{roadmap,quiz,flashcard}_repository.dart`, `lib/state/{roadmap,quiz,flashcard}_store.dart`, `lib/widgets/generate_sheet.dart` (new), `lib/screens/{roadmap,quiz,flashcards}_screen.dart`, `test/widget_test.dart` | Three of the four AI features were structurally dead, not merely unwired: `0008_rewards.sql` revokes `insert` on `milestones`, `milestone_tasks`, `quizzes` and `quiz_questions`, so no client path could create a roadmap or a quiz at all, and the Roadmap header's `tune` button had no `onTap`. The two blocked functions now write with the auto-injected service-role key after `requireUser`, while every read, ownership check, and `user_id` still comes from the caller's JWT (D-019); `generate-flashcards` needs no elevated key. `flutter analyze` clean, `flutter test` 7/7 — the new one proves `GenerateSheet` offers embedded materials only and won't fire until one is picked — and `flutter build apk --debug` exit 0. All five functions are ACTIVE with `verify_jwt`, and the three new ones were exercised end to end against the live project with a throwaway account: a `.txt` material became 3 chunks, `generate-roadmap` wrote 7 milestones / 28 tasks with contiguous weeks and `roadmap_days = 44`, regenerating left the count at 7 (replaces, not appends), ticking a generated task moved the goal to 3.57%, `generate-quiz` wrote 5 questions that all held `array_length(options,1) = 4` and scored 5/5 for +50 XP through `finish_quiz_attempt`, and `generate-flashcards` wrote 10 cards — all due immediately, all with a `source_chunk_id`, drawn from all three units of the source — which `apply_sr_grade` then rescheduled. From a second account all three functions answered `404` ("That file isn't yours." / "That goal isn't yours."), so the service-role writes stay inside the caller's own data. |
| 2026-09-04 | Linked the generated roadmap to Home, so one tick moves both screens and pays once. | `studytrail_flutter/lib/data/repositories/{task,roadmap}_repository.dart`, `lib/state/{home,roadmap}_store.dart`, `lib/screens/{home,roadmap}_screen.dart`, `test/widget_test.dart` | `generate-roadmap` wrote `milestone_tasks`, but Home's `daily_tasks` only ever came from `addTask` — which had no UI caller at all — so a student could generate an 11-week plan and Home still said "nothing scheduled". Home's new **Plan day** action seeds the next unfinished milestone (4 tasks at a time, skipping anything already scheduled on any date), each row carrying its `milestone_task_id`. `RoadmapRepository.toggleTask` now looks the linked row up and ticks through `complete_task` when it exists, so the roadmap can't silently cost the student the XP that a bare `milestone_tasks` write would (D-022); each screen reloads the other's store after a linked tick, and Home re-derives the milestone state and the goal percentage that the RPC doesn't own. No migration needed — `milestone_task_id` is already inside 0008's `grant insert (…) on daily_tasks`. `flutter analyze` clean and `flutter test` 9/9, the two new ones proving the seeding skips a done task, moves to Week 2 on a second tap, and then reports nothing left. Verified live on the hosted project with a throwaway account, 13/13 checks: `generate-roadmap` wrote 11 milestones / 44 tasks, the seeded insert was accepted with its link (201) and not pre-ticked, `milestone_task_id=not.is.null` returned only linked rows, `complete_task` flipped the roadmap checkbox and paid 0 → 15 XP, a second identical tick paid nothing (still 15), the derived state wrote as `active` at 1/4, `recompute_goal_progress` moved the goal 0.0% → 2.27%, and untick + delete restored both rows. |
| 2026-09-04 | Closed the never-done Day 1–3 test debt and made the Android release build work, then verified the artefact rather than the exit code. | `studytrail_flutter/test/stores_test.dart` (new), `test/widget_test.dart`, `android/app/build.gradle.kts`, `SETUP.md`, `README.md`, `DECISIONS.md`, `DAILY_PLAN.md` | Day 3's four journeys had shipped and been hand-verified but were never pinned by a test. There is no mocking package here — the repositories reach Supabase through a global `db` getter, so the seam is the repository itself and each fake subclasses the real one, overriding only what the test exercises; the optimistic write, the revert, the re-queue and the derived state therefore all run for real. 12 store tests plus 7 widget/transport tests, `flutter test` 19/19, `flutter analyze` clean. The `HomeStore.planDayFromRoadmap` group moved out of `widget_test.dart` so the split is one file per level. The first `flutter build apk --release` **failed**: `isMinifyEnabled = false` in the app module turned off half of a pair the Flutter Gradle plugin sets together (`FlutterPlugin.kt` sets `isShrinkResources = true` alongside it), and AGP refused to configure — the earlier worry about needing per-plugin keep rules was simply wrong, since they arrive inside each plugin's AAR (D-023). With the override removed the build is exit 0 (54.1 MB fat APK, 202 s), and `aapt2` + `apksigner` confirm package `in.charusat.studytrail`, label `StudyTrail`, `versionCode 1` / `versionName 1.0.0`, `INTERNET` as the only permission, all 11 launcher resources intact through resource shrinking, and `CN=Android Debug` from the signing fallback. Measured per-ABI payloads (arm64 18.8 MB / armeabi-v7a 16.3 MB / x86_64 20.3 MB) are what `SETUP.md` §7's `--split-per-abi` guidance rests on. `README.md` now states plainly what the app collects, including the honest gap that there is no in-app account deletion. The physical-device pass in `SETUP.md` §8 stays outstanding. |
| 2026-09-28 – 09-30 | Days 8–16 of `DAILY_PLAN.md`: summary and account-deletion functions, notifications and haptics, streak modal, leaderboard, rewards store, study rooms (`0010`), new logo and roadmap dashboard, academic-profile onboarding. | `studytrail_flutter/lib/**`, `supabase/functions/{summarize-material,delete-account}`, `supabase/migrations/0010_study_rooms.sql` | `flutter analyze` only. The 09-30 audit below found most of the new server paths broken or undeployed. |
| 2026-09-30 | Audit and repair of the above against the live project. Study rooms fixed (`0011`: recursive policy, RPC-only membership, member names, host-close, late-join timer sync, deduped chat); rewards and leaderboard moved to the server (`0012`: wallet, streak freeze, total-XP ranking, no invented classmates); `delete-account` and `summarize-material` deployed; reminder fixed from 18:00 UTC to local time and wired to Settings; onboarding no longer hangs offline. | `supabase/migrations/{0004,0010,0011,0012}`, `supabase/all_migrations.sql`, `supabase/functions/delete-account`, `studytrail_flutter/lib/{data,models,state,screens,services}`, `android/app/src/main/AndroidManifest.xml`, `test/rooms_rewards_test.dart` | `flutter analyze` clean, `flutter test` 27/27, `flutter build apk --debug` exit 0. 34/34 live checks with throwaway accounts (room RLS and RPC rules, capacity, names, close trigger, wallet refusals, leaderboard order, account deletion); streak-freeze rules run in a rolled-back transaction; the full twelve-migration chain re-run on the live database inside a rolled-back transaction. Commit `c0842b7`. |
