# StudyTrail daily GitHub delivery plan

This plan keeps every push small, reviewable, and safe to run. Each completed
day gets its own pull request (or direct commit while working solo), followed
by an update to `FLOW.md` and `DECISIONS.md` where needed.

## Commit conventions

```text
type(scope): short outcome
```

Use `feat`, `fix`, `security`, `test`, `docs`, `chore`, or `refactor` for
`type`. Examples:

```text
security(rewards): restrict client-controlled XP and badges
fix(tasks): make task completion retryable
feat(ai): add cited syllabus chat function
```

## Baseline — repository setup

**Commit:** `chore(repo): establish StudyTrail baseline`

**Status:** Completed on 15 August 2026.

- Add existing Flutter application, Supabase migrations, proposal/context, and
  project documentation.
- Keep the previous `studytrail_ui.html` intact.
- Exclude credentials, build output, local tooling, and reference exports.
- Link the local repository to `https://github.com/yash25cs/Sem_6_SGP.git`.

## Day 1 — Secure rewards and data ownership

**Commit:** `security(rewards): prevent forged XP and badge unlocks`

- Restrict direct client access to reward-granting RPCs.
- Move XP and badge decisions to validated server-side workflows.
- Add ownership checks between child rows and parent resources.
- Add SQL/RLS verification tests or repeatable verification scripts.

## Day 2 — Reliable core writes

**Commit:** `fix(core): make goal and task updates recoverable`

- Replace multi-call goal creation with one transactional RPC.
- Make task completion and roadmap progress one server-side operation.
- Add storage cleanup/retry handling for material upload failures.

## Day 3 — Test the core student journey

**Commit:** `test(core): cover onboarding and learning flows`

**Status:** written 2026-09-04, alongside Day 7 — the four journeys named below
had been shipped and hand-verified but never pinned down by a test.
`test/stores_test.dart` holds them; `flutter test` 19/19, `flutter analyze`
clean. There is no mocking package: the repositories reach Supabase through a
global `db` getter, so the seam is the repository itself and each fake subclasses
the real one, overriding only what the test exercises. The store's own logic —
the optimistic write, the revert, the re-queue, the derived state — therefore
runs for real while nothing touches the network.

- Add store/repository tests with mocked Supabase dependencies.
- Cover signup bootstrap, goal creation, task retry, and flashcard-grade retry.
- Add a short manual mobile test checklist to `SETUP.md`.

## Day 4 — Material ingestion and RAG foundations

**Commit:** `feat(materials): process uploads into searchable chunks`

**Status:** written 2026-08-20 — `supabase/functions/embed-material/`. Deployed
and verified end to end on 2026-08-22: a real PDF becomes unit-labelled chunks
with `status = embedded` in 7.4 s.

- Create the authenticated `embed-material` Edge Function.
- Extract text, chunk it, generate embeddings, and update material status.
- Keep the Gemini key in Supabase Function secrets only.

## Day 5 — Real AI study chat

**Commit:** `feat(chat): answer syllabus questions with citations`

**Status:** written 2026-08-20 — `supabase/functions/chat/`. Deployed with
`embed-material` and verified on 2026-08-22: answers cite the student's own
chunks in 5.4–7.5 s.

- Create the `chat` Edge Function.
- Retrieve only the caller’s chunks through RLS-scoped search.
- Save answer messages and citation rows; show clear retry/error states.

## Day 6 — AI-generated practice

**Commit:** `feat(practice): generate roadmaps, quizzes and flashcards`

**Status:** written 2026-09-01. Three functions, not two — the day's title named
quizzes and flashcards, but the roadmap was blocked by the same `0008` revoke and
had a dead button waiting for it, so `generate-roadmap` shipped in the same pass.
`flutter analyze` clean, `flutter test` 7/7, `flutter build apk --debug` exit 0.
Deployed and verified end to end on the hosted project: 7 milestones / 28 tasks
from a goal, a 5-question quiz scored 5/5 for +50 XP through
`finish_quiz_attempt`, 10 cards due immediately and rescheduled by
`apply_sr_grade`, and `404` for a second account on all three.

- Add `generate-roadmap`, `generate-quiz` and `generate-flashcards` Edge
  Functions. Only the first two need the service-role key, and only for the
  inserts the schema forbids a student to make (`DECISIONS.md` D-019).
- Validate generated data before saving it: drop the malformed item, keep the
  rest, and refuse to save a stub (D-021).
- Connect the Roadmap, Cards and Quiz screens to generated content through one
  shared `GenerateSheet` that offers embedded materials only.
- **Follow-up, 2026-09-04:** a generated roadmap didn't reach Home, so the day's
  most visible feature was invisible on the first screen. `HomeStore.planDayFromRoadmap`
  now seeds `daily_tasks` from the next unfinished milestone and both screens tick
  the same work through `complete_task` (`DECISIONS.md` D-022). `flutter test`
  9/9; 13/13 live checks against the hosted project.

## Day 7 — Mobile release readiness

**Commit:** `chore(release): prepare Android MVP build`

**Status:** written 2026-09-04. `flutter analyze` clean, `flutter test` 19/19,
`flutter build apk --release` exit 0 (54.1 MB fat APK, 202 s, R8 and resource
shrinking on). Verified in the artefact rather than assumed: package
`in.charusat.studytrail`, label `StudyTrail`, `versionCode 1` / `versionName
1.0.0`, `INTERNET` as the only declared permission, the adaptive icon surviving
resource shrinking with all 11 launcher resources intact, and
`apksigner --print-certs` reporting `CN=Android Debug` — the signing fallback
working exactly as designed, because no `key.properties` exists here.

Two things this day found rather than planned. The first release build **failed**:
`isMinifyEnabled = false` in `app/build.gradle.kts` turned off half of a pair the
Flutter Gradle plugin sets together, and AGP refused to configure
(`DECISIONS.md` D-023). The second is that Day 3 had never been done, so its four
tests were written here — see that day.

The **device regression pass is not done**; it can't be, from a machine with no
phone attached. `SETUP.md` §8 is the checklist to run, and the release APK above
is the build to run it against.

- Run analysis, tests, and a physical-device regression pass.
- Set an app icon, release name/version, privacy notes, and signed-build steps.
- Create a tagged release and attach the Android APK only if needed.

Delivered against those three: real launcher icons at all five densities plus an
adaptive icon (gradient background, white trail foreground, `<monochrome>` for
Android 13 themed icons) and a 512 px Play icon, rendered from
`app_colors.dart`'s palette; the label, `applicationId` and `namespace` shortened
to `in.charusat.studytrail` so it matches the OAuth scheme; `key.properties`
signing with a debug fallback and the `keytool` command in `SETUP.md` §7 rather
than run here, because a keystore password typed into a transcript is a published
password; privacy notes as a *What the app collects* section in `README.md`,
including the honest gap that there is no in-app account deletion yet; and
`SETUP.md` §8's 20-item manual checklist. No tag is cut — nothing is committed
yet, and the device pass has to come first.

## Rule for future work

## Day 8 - AI Reliability & Core Bug Fixes

**Commit:** `fix(core): resolve quiz generation, flashcard animations, and account deletion`

**Status:** Completed on 28 September 2026.

- Fixed a critical timeout issue in `generate-quiz` Edge Function by increasing execution budget to 120s and implementing proper chunk trimming for Gemini 3.5 Flash-Lite.
- Resolved an unmodifiable list crash (`const <QuizQuestion>[]`) in `Quiz.fromMap` that prevented quizzes from loading on the client.
- Fixed a visual glitch in `FlashcardsScreen` by isolating the flip animation into a separate `_FlipCard` widget, ensuring smooth transitions without revealing answers prematurely.
- Implemented the `delete-account` Edge Function using a strict leaf-first foreign key deletion order and integrated it with the Settings UI.
- Constrained the chat citation UI (`SoftChip`) to safely wrap and truncate long PDF filenames instead of overflowing the screen.
- Implemented the `summarize-material` Edge Function and a visual Study Streak Heatmap on the Profile screen to close out major SGP Quick Wins.

## Day 9 - Notifications & Gamification Polish

**Commit:** `feat(ui): add notifications, haptics, confetti, and shimmer loaders`

**Status:** Completed on 28 September 2026.

- Implemented in-app notification system (`NotificationBell`) providing dynamic alerts for streaks at risk, task completion, and upcoming exams.
- Integrated `flutter_local_notifications` and configured Android permissions and core desugaring (`desugar_jdk_libs:2.1.4`) to schedule daily background study reminders (6:00 PM).
- Added an urgent countdown visual state to the Home screen `_HeroCard` when an exam is less than 7 days away.
- Replaced basic loading spinners with modern shimmering skeleton loaders (`LoadingBlock`) using the `shimmer` package.
- Added `HapticFeedback` interactions for daily tasks and a celebratory `ConfettiWidget` explosion upon completing all daily tasks.

## Day 10 - Competitive Leagues & Reward Unlocks

**Commit:** `feat(gamification): add streak celebration sheet, league leaderboard, and rewards store`

**Status:** Completed on 28 September 2026.

- Implemented interactive `StreakModalSheet` with a 7-day Monday-Sunday circular flame calendar, progress indicator, native social sharing via `share_plus`, and streak rules info modal.
- Built full-featured `LeaderboardScreen` inspired by competitive student leagues: podium stage with level badges, light beam effect, promotion vs safety zone slider with user pinpoint rank, and animated cohort ranking.
- Added `LevelUpInfoSheet` dialog detailing XP mechanics, batch leagues, and bi-weekly promotion/demotion reshuffling.
- Built `RewardsScreen` featuring an XP Unlockables Store with coupon redemption (Streak Freeze Shields, 2x XP Boosters, Pro AI Quiz Passes), a "How it Works" guide, and an expandable FAQ accordion.
- Integrated quick actions and navigation access across HomeShell, HomeScreen, and AchievementsScreen.


## Day 11 - Navigation Tuning, Dark Mode Adaptation & Logout Flow

**Commit:** `fix(ui): swap cards and quiz navigation, resolve dark mode issues, fix overflows, and fix logout redirect`

**Status:** Completed on 28 September 2026.

- Swapped **Cards** (Flashcards) on the main bottom navigation bar with **Quiz**, placing Quiz directly in the primary navigation flow and moving Flashcards into the Center Quick Actions menu.
- Added full **Dark Mode** theming support across `RewardsScreen`, `LeaderboardScreen`, and `StreakModalSheet`, converting hardcoded light/white backgrounds and text colors to semantic `context.p` palette tokens (`p.bg`, `p.card`, `p.ink`, `p.line`).
- Resolved UI overflow issues reported on physical devices:
  - Fixed 19px right overflow in `AchievementsScreen` top bar by wrapping the title in `Expanded` and optimizing action icon spacing.
  - Fixed 3.8px right overflow in `RewardsScreen` coupon unlock tags by wrapping the coupon code label in `Flexible` with text truncation.
- Fixed **Logout Navigation & Confirmation**:
  - Maintained the clean confirmation dialog ("Log out? Your progress stays saved.") with Cancel and Log out choices.
  - Bound `rootNavigatorKey` to `MaterialApp` and added `popUntil((route) => route.isFirst)` on logout to dismiss all pushed modal routes and immediately transition the view to `LoginScreen`.


## Day 12 - Stability Fixes, Loading Polish & Rewards Persistence

**Commit:** `fix(core): resolve flashcards material crash, prevent streak popup spam, add plan day loader, and implement rewards persistence`

**Status:** Completed on 29 September 2026.

- Fixed the red screen crash in **Flashcards** (`No Material widget found`) by wrapping the screen in `Scaffold` and `SafeArea`, ensuring safe independent route navigation.
- Fixed the repeated streak celebration glitch in `HomeScreen._toggle` with a session guard flag (`_hasShownStreakModal`), ensuring the celebration sheet triggers exactly once upon daily task completion.
- Enhanced visual feedback for **Plan Day**:
  - Upgraded the "Plan day" `SoftChip` button with a dynamic progress spinner and "Planning..." status.
  - Displayed a shimmering `LoadingBlock` in the task list while the roadmap planner is fetching tasks.
  - Ensured `LoadingBlock` always displays when the Achievements store is actively loading.
- Implemented complete **Rewards Redemption & Persistence**:
  - Saved unlocked coupons and spent XP to device storage via `LocalPrefs` (`SharedPreferences`).
  - Added real-time XP deduction reflected in the user's available XP counter.
  - Added confirmation dialogs before redeeming rewards with XP.
  - Added visible coupon expiration dates (e.g., `Expires 31 Dec 2026`).
  - Added a dedicated 1-tap **Copy button** (`Symbols.content_copy`) with clipboard support and toast feedback.

## Day 13 - Achievements Section Recovery, Catalog Badges Fallback & Resilient Gamification Layer

**Commit:** `fix(achievements): resolve empty achievements screen, fix PostgREST query syntax, and add badge catalog fallback`

**Status:** Completed on 29 September 2026.

- **Root Cause Identified & Fixed:**
  - The query in `GamificationRepository.getBadges` used invalid PostgREST syntax `.select('*, user_badges!left(*)')`. Because PostgREST embeds are left outer joins by default and do not have a `!left` keyword, Supabase returned an HTTP error (`PGRST200`), causing `Future.wait` in `GamificationStore.load()` to crash and blank the entire screen with empty badges.
  - Fixed the query syntax to `.select('*, user_badges(*)')` and added fallback queries for user badges.
- **Built-in 10-Badge Catalog Fallback:**
  - Added `GamificationRepository.defaultBadges` covering all 10 core achievements (First Step, Week Warrior, Quiz Ace, Card Master, Night Owl, Early Bird, Focused Mind, Roadmap Ready, Curious Learner, Goal Crusher).
  - Merged local/server unlock status so the badge section is never blank or empty, even if the database catalog hasn't been seeded or the network fails.
- **Resilient Store Loading:**
  - Decoupled `GamificationStore.load()` into isolated `try/catch` blocks for profile, streak, badges, recent activity, and leaderboard, ensuring that a single failing service cannot take down the entire screen.
- **Achievements Screen Polish & Interactions:**
  - Enabled tap interaction on badges in `AchievementsScreen` to open a modal bottom sheet (`_showBadgeDetail`) displaying badge descriptions, locked/unlocked status, and how to earn them.
  - Integrated `LeaderboardScreen.resolveEntries` so the Class Leaderboard section on `AchievementsScreen` displays active cohort rankings rather than an empty placeholder.
  - Fixed RenderFlex unbounded width crash: eliminated the outer `Row` wrapping `CardHeader('Class leaderboard')` which triggered an unhandled assertion crash that rendered the `ListView` completely blank on physical devices.
  - Enhanced badge detail modal sheet (`_showBadgeDetail`) with a clear "How to earn" explanation box and unmistakable "Earned!" vs "Not earned yet" status chips.
  - Verified widget tree rendering via automated test and validated codebase health with `flutter analyze` (0 issues).

## Day 14 – App Logo & Roadmap UI Overhaul

### App Logo Update
- **New StudyTrail Logo:** Generated a professional app icon featuring an open book with a winding trail and milestone dots — captures the "study + journey" brand identity.
- **Launcher Icons:** Added `flutter_launcher_icons` package and regenerated all Android `mipmap-*` launcher icon sizes (mdpi through xxxhdpi) plus adaptive icon assets.
- **In-App Branding:** Updated `BrandMark` widget on the login/signup screens to display the new logo image (`assets/images/studytrail_logo.jpg`) instead of the old gradient + route icon placeholder.
- **Asset Pipeline:** Added Flutter asset declaration in `pubspec.yaml` for the logo image.

### Roadmap Screen UI Improvements
- **Stats Dashboard:** Replaced the simple progress bar with a rich dashboard featuring a circular progress ring (custom `_ProgressRingPainter`) plus 4 mini-stat cards showing topics done, weeks done, current week, and days remaining.
- **Motivational Hints:** Dynamic motivational text that changes based on overall progress level (✨ → 🚀 → 🔥 → 💪).
- **Collapsible Milestones:** Completed and upcoming milestone cards are now expandable/collapsible with tap-to-toggle and animated rotation on the expand arrow.
- **Status Badges:** Each milestone header now shows a colored pill badge — "DONE" (green) or "IN PROGRESS" (primary) — for instant visual scanning.
- **Week Numbers:** Timeline dots for upcoming milestones now display the week number instead of a lock icon, making the timeline more informative.
- **Task Count & Time Estimates:** Each milestone card shows a compact summary line with the task count and estimated study time (~25 min per topic).
- **Better Task Items:** Individual task rows now have subtle background containers and animated icon switching when checked/unchecked.
- **Gradient Timeline Connectors:** Completed milestone connectors now use a gradient fade instead of a flat line for visual depth.
- **Confetti Celebration:** Completing all tasks in a milestone triggers a confetti burst at the top of the screen.

## Day 15 – Real-Time Study Buddy Room & Group Focus System

### Database & Backend Architecture (`supabase/migrations/0010_study_rooms.sql`)
- **Tables Created:**
  - `study_rooms`: Stores room configuration (name, invite_code, host, timer/break durations, max members, status).
  - `room_members`: Tracks active students in each room with roles (`host`, `member`).
  - `room_messages`: Peer-to-peer room chat messages with automatic Supabase Realtime publication.
- **Security & RLS:**
  - Comprehensive Row Level Security policies ensuring privacy: students can only read and write messages/members for rooms they have joined.
  - Hosts have exclusive authority to update or close rooms.
- **Security Definer RPCs:**
  - `create_study_room`: Atomically creates a room and assigns host role to creator.
  - `join_room_by_code`: Validates 6-character alphanumeric code, checks capacity limits, and enrolls student.
  - `close_study_room`: Authoritative host closure mechanism.

### Realtime State & Synchronized Timer (`lib/state/room_store.dart`)
- **Presence Tracking:** Tracks connected students via `channel.onPresenceSync` and broadcasts live focus status (`focusing`, `on_break`, `idle`).
- **Synchronized Pomodoro Timer:**
  - Host controls start, pause, resume, reset, and phase switching.
  - Timer commands are broadcast over the `timer` event so every room member's timer ticks in lockstep with the host.
- **Peer-to-Peer Realtime Chat:**
  - Optimistic message delivery with dual broadcast and PostgreSQL change listener for resilient instant chat.

### Frontend Screens & Navigation
- **`BuddyRoomScreen` Lobby (`lib/screens/buddy_room_screen.dart`):**
  - Transformed the stub leaderboard into a comprehensive Study Room Lobby.
  - Active rooms list with live count badges, focus length indicators, and direct join buttons.
  - 6-character invite code input for instant room entry.
  - "Create Room" bottom sheet with configurable focus (25/45/50m) and break (5/10/15m) times.
  - Seamlessly integrates the Class Cohort Leaderboard and leave class option below the room actions.
- **`StudyRoomScreen` Session (`lib/screens/study_room_screen.dart`):**
  - Full in-room experience featuring large synchronized countdown dial and progress track.
  - Host controls vs member sync indicators.
  - Live study buddy avatars with active presence indicators.
  - Tap-to-copy room invite code badge with toast feedback.
  - Integrated real-time room chat with custom message bubbles.
  - Host confirmation dialog when leaving/closing the room.
- **Validation:**
  - Passed `flutter analyze` with 0 issues.
