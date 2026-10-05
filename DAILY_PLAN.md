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

## Day 16 – Academic Profile Onboarding & Profile Direct Navigation

### Academic Profile Setup Screen (`lib/screens/academic_profile_screen.dart`)
- **First-Run / Post-Signup Onboarding:**
  - Automatically prompts new students immediately after creating their account / ID to fill out their academic information before proceeding to material upload and goal planning.
  - Form gathers:
    - **Full Name** (prefilled or editable)
    - **College / University Name** (e.g. CSPIT, Charusat University)
    - **Program & Branch / Major** (e.g. B.Tech Computer Engineering, IT)
    - **Student ID / Roll No / Enrollment ID** (e.g. 22CS045, D25CS118)
    - **Current Semester** (dropdown: Semester 1 through 8)
  - Saves atomically to Supabase `profiles` table via `ProfileRepository.updateProfile` and refreshes global `ProfileStore` and `HomeStore`.

### Settings & Profile Editing Integration
- **`SettingsScreen` (`lib/screens/settings_screen.dart`):**
  - Added dedicated **Academic Profile** section displaying College, Program & Branch, and Student ID.
  - Tapping any row or "Edit" navigates to `AcademicProfileScreen` in edit mode to modify any academic field anytime.
- **`ProfileScreen` (`lib/screens/profile_screen.dart`):**
  - Added interactive tap trigger on `_IdentityCard` to quickly open the academic profile editor.
  - Added an "Academic profile" row in the Profile settings list with school icon and chevron.

### Home Screen Top-Right User Icon Navigation
- **`HomeScreen` (`lib/screens/home_screen.dart`):**
  - Wrapped top-right `GradAvatar` with interactive tap detection and a tooltip.
  - Configured with `onOpenProfile` callback that smoothly switches to Tab 4 (Profile) in `HomeShell`.
  - Added fallback navigation pushing `ProfileScreen` if opened outside `HomeShell`.

### Returning / Old User Login Support
- **`RootFlow` (`lib/main.dart`):**
  - Connected `onSignIn` on `LoginScreen` to execute `_resolveEntryStage()`.
  - In `_resolveEntryStage()`, checks whether `college`, `branch`, and `enrollmentId` are populated. If any are missing, returning users are immediately guided to `AcademicProfileScreen` to input their academic credentials.
  - Upon saving, returning users with existing goals automatically proceed straight into the main app shell without having to re-upload materials or recreate goals.
- **Validation:**
  - Validated with `flutter analyze`: **0 issues found** (100% clean compilation).

## Day 17 – Audit: live bugs fixed, fake data replaced

**Status:** Completed on 30 September 2026. `flutter analyze` clean,
`flutter test` 27/27 (8 new in `test/rooms_rewards_test.dart`), 34/34 live
checks against the hosted project with throwaway accounts, and the streak-freeze
rules exercised in a rolled-back transaction.

### Broken on the live project, now fixed
- **Study rooms never worked end to end.** 0010's `room_members` policy was
  recursive (Postgres 42P17 on every read), so the lobby was always empty, the
  member list was empty and chat was never saved — the repository hid the error.
  `0011_study_rooms_fix.sql` replaces the policy and moves create/join/close
  behind RPCs (D-024).
- **Lobby Join skipped membership**, so a student who joined from the list could
  not read or send chat. It now joins through `join_room_by_code`.
- **Members' timers were zeroed by every host command.** realtime_client
  delivers broadcasts as `{type, event, payload}` and the store read the top
  level. Late joiners now get a `sync` from the host; a host closing the room
  tells members; the system back gesture confirms before leaving; chat bubbles
  de-duplicate on a client-chosen id and show local time instead of UTC.
- **`delete-account` and `summarize-material` were never deployed**, so both
  buttons failed. Deployed; storage cleanup in `delete-account` now pages past
  100 files.
- **The 6 PM reminder fired at 11:30 PM IST** — `tz.local` was never set, so it
  was 18:00 UTC. Now scheduled from local wall time, inexact (no exact-alarm
  permission, which Play restricts), and the Settings switch actually turns it
  on and off. The dead "Sound effects" switch is gone.
- **Onboarding could hang** after saving the academic profile with no network;
  it now goes through the entry check's retry screen.

### Fake or misleading, now real
- **Leaderboard** padded a small class with nine invented students, showed a
  copied "missing XP points will be added soon" banner, a hard-coded Level 1 and
  a 30-rank promotion zone with a 14-day reshuffle nothing implements. It now
  shows real classmates only, the student's real level, and their gap to the
  next place. It also ranked by XP-within-level; it now ranks by total XP.
- **Rewards** spent XP in SharedPreferences (per phone, shared between accounts)
  and sold four coupons with no effect. `0012_rewards_store.sql` puts the wallet
  on the server and sells what the server can enforce: a streak freeze that is
  used automatically on a missed day, and a golden border shown on the
  leaderboard (D-025).

### Housekeeping
- 0004 and 0010 made safe to re-run; `all_migrations.sql` regenerated with all
  twelve migrations and re-run end to end on the hosted project inside a
  rolled-back transaction.

## Day 18 – Fifteen features: adaptive practice, exam papers, faculty view

**Status:** Completed on 1 October 2026 (not committed). Every feature was
verified against the hosted project with throwaway accounts that deleted
themselves afterwards; migrations 0013–0019 were dry-run in rolled-back
transactions before being applied, and the full 19-file chain was re-run the
same way at the end.

### Quick wins
- **Room focus earns XP.** A completed focus block in a study room is logged
  through `record_focus_session`, crediting only the minutes this device watched.
- **Smarter reminders.** One-off reminders for the week instead of a repeating
  one: the 6 PM nudge is dropped on days the student already studied, and a
  9 PM "streak at risk" nudge fires only when there's a streak to lose.
- **Dark mode is remembered.**
- **CI.** `.github/workflows/checks.yml` runs `flutter analyze`, `flutter test`
  and an `all_migrations.sql` freshness check on every push.
- **Chat extras.** Three follow-up questions after every answer (same model
  call), and "Save as flashcards" turns one answer into real cards in a
  "Saved from chat" deck. Live: 16/16.
- **Photo notes.** Camera or gallery; `embed-material` reads JPG/PNG/WebP/HEIC
  with the same vision call as PDFs. Live: 9/9, including chat answering from a
  photo.
- **Room moderation** (`0013`). Block (hide a person's messages everywhere),
  report (stored with a snapshot of the message for dashboard review), and host
  removal (can't rejoin). Live: 22/22.

### The three big ones
- **Weak topics** (`0014`). Quiz questions now record their unit;
  `get_weak_topics` ranks units by quiz misses and "hard/again" cards. Home's
  Weak spots card generates a quiz or deck from only those units. The text
  splitter now recognises "Unit 3: …" headings, and a file without headings
  counts as one topic. Live: 17/17.
- **Catch-up planner** (`0015`). `get_roadmap_pace` measures the student against
  a straight line to the exam; `plan_catch_up` moves missed tasks to today and
  fills the next 7 days at the pace needed. Live: 17/17.
- **Past papers + mock exam** (`0016`, `analyze-paper`). Papers are read into
  questions tagged with the student's own units; "Most-asked topics" ranks them;
  a 15-question mock exam is weighted toward them. Live: 17/17 — every sample
  question mapped to the right unit.

### Bigger ones
- **Long-answer practice** (`0017`, `grade-answer`). Examiner-style marks and
  feedback against the student's notes; no XP. Live: correct answer 5/5, wrong
  answer 0/5, prompt-injection answer 0/5.
- **Exam date per subject** (`0018`). The goal's date follows the last exam;
  the roadmap finishes each subject by its own exam week. Live: 8/8.
- **Offline flashcards.** Decks and a week of due cards cached per student;
  grades queued offline replay through `apply_sr_grade` in order.
- **Faculty view** (`0019`). Teacher code per class; aggregate-only overview,
  withheld below three students; teachers can share notes that their class's
  chat, quizzes and cards then use. Live: 20/20 in a throwaway class.
  *Removed on Day 20 — the app is for students only.*

### Found and fixed on the way
- **XP farming** through a direct `daily_tasks` update (15 → 30 XP per loop),
  closed in `0015`.
- **Midnight–5:30 AM IST bug** in the new planner: server "today" is UTC, so
  pace and catch-up now take the phone's date.
- Quiz generation errors reached students as `Error: FunctionException(...)`.

`flutter analyze` clean; `flutter test` 58/58 (up from 27).

## Day 19 – Layout fixes and a regrouped quick-actions sheet

**Status:** 2 October 2026, from device screenshots (not committed).

- **"RIGHT OVERFLOWED" on buttons.** `PillButton`'s label couldn't shrink, so two
  buttons sharing a row (Past papers, Weak spots, Answer practice, photo upload)
  overflowed on a narrow phone or a large system font. The label now scales down
  to fit whatever width it gets, and is unchanged when it fits.
- **Other overflows found by a new layout test** rendering screens at 320 dp
  with long names: section headers (`CardHeader` now wraps its action to the next
  line), the catch-up banner and mock-exam card (button moved under the text),
  the hero card's streak chip, Chat's status line, the Rewards balance pill, the
  Leaderboard rank line and rows, and the faculty stat grid and weak units.
- **Quick actions** regrouped from a ten-row list into a featured *Start a focus
  session* card plus *Practise*, *Together* and *Progress* groups in a
  three-column grid; the teacher-only dashboard moved to a quiet link at the
  bottom.
- `test/layout_overflow_test.dart` keeps it that way: 9 screens, and the test
  binding fails on any overflow and names the widget.

## Day 20 – Students only; study rooms sized at creation, with a group quiz

**Status:** 2 October 2026 (not committed).

- **Teacher feature removed** (D-030). The faculty screen, store, repository,
  model, test and `0019_faculty.sql` are gone; on the live database its
  policies, functions, column and two tables were dropped and
  `match_material_chunks` restored to own-chunks-only. The academic-profile
  step no longer offers *I'm a teacher*, and the quick-actions sheet has no
  teacher link.
- **Room size at creation.** Creating a room asks for a name and how many
  people (2, 3, 4, 5 or 6, host included) — no focus or break length.
  `create_study_room` refuses anything outside 2–6.
- **Focus session inside the room.** The timer card shows the room's focus and
  break lengths; the host taps **Change** (clock stopped) to pick 15/25/45/50
  and 5/10/15 minutes. Saved on the room (`set_room_timer`) and carried on
  every timer broadcast, so members and late joiners follow.
- **Group quiz** (`0019_room_quiz.sql`, `room-quiz`, D-031). The host picks one
  of their own notes and 5/10/15 questions. Everyone in the room is asked; it
  starts only when all of them agree. Everyone answers the same questions on a
  new answer screen; marking is on the server. When the last person hands in
  (or the host ends it) the room sees every score, ranked, and the top three
  earn 30/20/10 XP. *Answers* shows each question with the right option.
  `generate-quiz` and `room-quiz` now share one question writer
  (`_shared/quiz.ts`).
- Live probe 26/26 (see `FLOW.md` change log). `flutter analyze` clean;
  `flutter test` 84/84, with `test/room_quiz_test.dart` covering the store's
  quiz flow, the focus-length rules, and every quiz state at 320 dp.

## Day 21 – Fourteen more: hardening, study tools, together, ship prep

**Status:** 2 October 2026 (not committed). Migrations 0020–0023 were each
dry-run in a rolled-back transaction before being applied; every feature was
probed live with throwaway accounts that deleted themselves.

### Fixes (`0020_hardening.sql`)
- **Private room channels** — only a room's members can join, hear or send
  (D-032). The live two-account test shows an outsider refused and a public
  channel of the same name hearing nothing.
- **Leaving mid-quiz** — a leaver drops out of the vote or the running quiz;
  under two players cancels; everyone left handed in finishes it.
- **Streaks on the student's day** — the phone's UTC offset is stored; every
  reward path logs to the local date (D-033). Live: activity lands on the
  UTC+14 and UTC−12 dates for students in those zones.
- **Server-only chat writes** — the client can't insert or edit chat turns
  (D-034). Live 21/21 for the four fixes.

### Study tools (`0021_study_tools.sql`)
- **Handwritten answers** — photograph up to three pages; transcribed, marked,
  photos deleted. Live: a rendered handwriting page was read word for word.
- **Hindi and Gujarati** explanations in chat, summaries, answer feedback and
  doubt-board AI answers. Live: Gujarati chat and summary, Hindi feedback.
- **My mistakes deck** — wrong quiz answers become due cards, no duplicates;
  group-quiz misses only once the quiz is over.
- **Weekly report** — this week against last; Sunday 7 PM notification.
  Live 26/27 (the one miss was the probe's own arithmetic).

### Together
- **Speed rounds** (`0022`) — same question on every phone at once, timed on
  the server, 500 + speed bonus, live reveal (D-035). Live 21/21 with real
  timing.
- **Doubt board** (`0023`, `doubt-ai`) — class Q&A with an AI first answer from
  the asker's notes, upvotes, solved, report and block (D-036). Live 27/27.

### Everyday
- **Calendar export** — an `.ics` of exams (with reminders), roadmap weeks and
  upcoming tasks, through the share sheet.
- **Home-screen widget** (Android) — days to the next exam, today's tasks,
  streak; it counts the days itself, so it stays right without the app.

### Engineering
- **Live two-account room test** — `STUDYTRAIL_LIVE=1 flutter test test/live`;
  skipped otherwise, so CI never touches the hosted project.
- **Play Store** — `PLAY_STORE.md`: the release bundle builds; listing text,
  data-safety answers, and privacy and deletion pages (`docs/`) are ready. The
  Play account, upload key and upload are the owner's.

## Day 22 – YouTube videos and playlists the AI can read

**Status:** 3 October 2026 (not committed). `embed-material` redeployed; no
migration.

- **Crash fixed.** Adding any link on the upload step turned the screen red
  (`'_dependents.isEmpty': is not true`). The link sheet's text controller was
  disposed the moment the sheet *started* closing, while its field was still
  on screen. The sheet now owns its controller (`widgets/video_link_sheet.dart`).
  Settings' *rename goal* sheet had the same bug and is fixed the same way.
- **YouTube videos and playlists are read** (D-037). Paste a video, a playlist,
  or a video opened inside a playlist (the app asks *whole playlist* or *just
  this video*). The phone fetches each video's captions — English first, then
  Hindi, then Gujarati, a human-written track before an automatic one — and
  stores them as a timestamped `.txt` on a `video_link` row. `embed-material`
  chunks on the timestamps, so a citation reads `12:40 · Lecture 3`. Chat,
  summaries, quizzes and flashcards work on videos like on notes.
- **Playlists** add one row per video, one at a time, each turning Ready as it
  goes. Videos already in the library are skipped; it stops at the 20-file
  limit and says how many didn't fit; videos with no captions or that won't
  play are skipped and counted.
- **After onboarding** the chat screen's materials sheet has a **YouTube**
  button — before this there was no way to add a video once onboarding was
  over. Other links are still saved as bookmarks, and now say so.
- Live: a 45-minute MIT lecture became 23 chunks in 9 s; chat answered from it
  citing `9:40 · 1. Algorithms and Computation`. Probe account deleted itself.
  `flutter analyze` clean; `flutter test` 128 passed, 4 live tests skipped.
  `STUDYTRAIL_LIVE=1 flutter test test/live/youtube_live_test.dart` checks the
  service against real YouTube (3/3 from a home connection).

## Day 23 – Long playlists as one item, and a launch screen

**Status:** 3 October 2026 (not committed). `0024_playlists.sql` dry-run in a
rolled-back transaction, then applied; `generate-roadmap` redeployed.

- **A playlist is one library item** (D-038). A 92-video playlist used to take
  all 20 slots on its first 20 videos and stop. Now it's one row —
  "Reading · 34 of 92 ready" with a progress bar — that opens to list its
  videos (each with retry, summarize, remove). Up to 100 videos per playlist.
- **Three at a time, in the background.** Adding a playlist returns at once
  ("Reading 92 videos — about 6 minutes"); the student carries on using the
  app. Measured per video: ~1 s on the phone for captions, ~9 s to read.
- **It survives the app closing.** The video list is stored with the playlist,
  so whatever wasn't read carries on at the next launch, when the app comes
  back to the front, or from **Resume**. A dropped connection pauses it; it
  never marks a video unreadable for that. Videos with no captions, private
  ones, and ones the student removes are skipped for good.
- **A busy AI no longer fails videos.** The first real run (a 92-video
  playlist) left 39 videos `failed`: the free tier embeds ~100 chunks a minute
  (confirmed live — four 23-chunk videos at once went through, the fifth got a
  429). Now a 429 makes every worker wait a minute and retry; if the limit
  doesn't clear, the reader pauses with the videos still queued. **Retry** on
  the playlist row re-reads any that failed before this.
- **The roadmap sees each lecture once.** It read headings from chunks, which
  for a video are one per timestamp — and its 600-row scan reached only the
  first couple of dozen lectures. It now reads video titles directly.
- **Launch screen.** The bare spinner is replaced by the logo settling in with
  a trail circling it (the logo's own teal and indigo) and the wordmark rising
  underneath; it fades into the app. Still with "remove animations" on.
- Live probe 16/16 (playlist row, videos under it, embed, skip list writable
  and video list not, roadmap from video titles, delete cascading to videos,
  chunks and files). `flutter analyze` clean; `flutter test` 138 passed, 4 live
  skipped — new tests prove three-at-a-time, pause and resume, no doubling on a
  second paste, waiting out a busy AI, Retry, and the playlist row and splash
  at 320 dp.

## Day 24 – Chat history, and a new chat on every launch

**Status:** 4 October 2026. No migration and no function change.

- **A new chat on every launch,** as other AI chat apps do. The chat used to
  reopen the latest thread forever. Switching tabs or backgrounding the app
  keeps the conversation; only a fresh launch starts over.
- **No empty chats.** The thread row is written with the first question, not
  when the screen opens — New chat used to leave an empty thread every tap.
- **History panel.** The AI's avatar at the top left (now with a small history
  badge) slides the student's chats in from the left: New chat at the top,
  then Today / Yesterday / Previous 7 days / Earlier, each chat named by its
  first question, the open one highlighted. Tap to open and carry on; delete
  asks first. One query reads the list with each chat's first question and
  leaves out empty threads — checked live with a throwaway account.
- The 39 videos that failed in the first 92-video run were from before
  Day 23's busy-AI fix; on the new build the playlist row's **Retry 39**
  re-reads them.
- `flutter analyze` clean; `flutter test` 146 passed, 4 live skipped
  (`test/chat_history_test.dart`: launch opens empty and writes nothing, the
  first question makes the chat, New chat keeps the old one in the list,
  opening and continuing a past chat, deleting the open one, day grouping,
  and the panel at 320 dp). Panel checked by eye in light and dark.

## Day 25 – A faster launch and quicker screens

**Status:** 4 October 2026 (not committed). No migration, no function change.
Measured first: the database is in Sydney (`ap-southeast-2`), and from India
one query costs ~300 ms on a reused connection — so every wait that follows
another wait shows.

- **Only Home loads at launch.** The bottom bar built all five tabs at once,
  firing ~27 requests for screens nobody had opened. Tabs now build — and load
  — the first time they're opened (`LazyIndexedStack`), then stay as before.
- **Home is fetched during the splash.** Once the launch check knows you're
  going to Home, Home's data loads while the logo is still up (capped at 2 s),
  so Home opens filled in. The launch check's two reads, and Home's subjects
  and pace, now run together — two waits of ~300 ms each gone.
- **AI calls pinned next to the database.** Edge Functions ran in Mumbai and
  crossed to Sydney for every query; pinned to `ap-southeast-2`, a call
  measured 0.77 s instead of 1.22 s. Done in the app's HTTP client, so every
  `functions.invoke` gets it.
- **Rewards, Leaderboard, Achievements:** six reads one after another (1.8 s
  measured) are now two rounds; the badge list still waits for the badge
  check.
- **Before the first frame:** the 10-year timezone data instead of all of
  history (8x faster to load), notification setup alongside Supabase's, and
  Plus Jakarta Sans bundled (the five weights the app uses, hash-checked
  against google_fonts) so the first launch never shows the system font
  first. The font's OFL licence is on the licences page.
- **Study room:** the countdown ticks on its own notifier, so the room —
  members, chat, controls — no longer rebuilds every second.
- **Leaderboard in dark mode:** the "how it works" steps no longer show light
  pastel discs; they tint from the icon's own colour.
- `flutter analyze` clean; `flutter test` 156 passed, 4 live skipped
  (`test/smoothness_test.dart`: lazy tabs, the prefetch hand-off, subjects and
  pace together, Rewards in two rounds with a failed read falling back, the
  region header on function calls only, the quiet room clock, and the bundled
  font found with downloading switched off — which fails if a weight is
  removed).

## Day 26 – Simpler onboarding forms

**Status:** 5 October 2026 (not committed). Migration `0025` applied; no
function change.

- **No starter subjects.** The goal form used to open with DBMS, OS and
  Networks filled in. It now starts empty, and the old "+ Add" chip is a
  full-width **Add your first subject** button.
- **An exam date with every subject.** The add sheet asks for the name and
  the paper's date together and won't add one without the other; a repeated
  name is refused there with the reason. Subjects list in exam order with
  "in N days", tap one to change its date. The single exam-date field is gone
  — the goal runs to the last paper. `create_goal` takes the dates in the
  same transaction (0025); an app build from before still works against it.
- **Academic details:** no enrollment ID. The program is a dropdown grouped
  into School, Science & Technology, Commerce & Management and Arts &
  Humanities, plus Other (type the name). School asks for the class (1–12)
  and the school name, with no branch; CA, CS and CMA ask for the level; the
  rest ask for the semester, with an optional branch. Settings and the
  profile card no longer show the enrollment ID.
- **Plain placeholders** on sign-in, sign-up and academic details: "Enter
  your email", "Enter your full name" and so on, instead of a real name,
  email and college.
- `flutter analyze` clean; `flutter test` 163 passed, 4 live skipped
  (`test/onboarding_forms_test.dart`: empty start and the no-subject error,
  the sheet's name/date/duplicate checks, exam order and the dates reaching
  the store, no enrollment field, School → class, a typed program opening as
  Other, and the saved text round-tripping). 0025 dry-run in a rolled-back
  transaction, then applied, then called live through PostgREST with a
  self-deleting account.

## Day 27 – Home-screen widgets

**Status:** 5 October 2026 (not committed). No migration, no function change.

- **Today widget, redesigned** (4×2): brand gradient with the launcher's
  own corner radius, a streak chip, days to the next paper, a ring for
  today's tasks ("2/5"), the next three tasks taking turns — each slides up
  and out as the next slides in — and **Focus**, **Cards** and **Ask AI**
  buttons. Shorter than 4×2 it drops the buttons, then the task line.
- **Two small widgets.** **Exam countdown** (2×2, violet): days to the next
  paper, its date, how many are left; after each exam day it moves on to the
  next subject by itself. **Streak** (2×1, coral to amber): the flame and the
  count; taller, "Done today · best N". Until a task is done today a light
  circles the flame, and a tap starts a focus session; afterwards a tap
  opens Achievements. A streak missed for a whole day shows 0, even if the
  app hasn't been opened since.
- **Taps:** every button ripples; on Android 12+ the widget grows into the
  app. Each part opens its own screen — Home, Roadmap, Chat, Pomodoro,
  Flashcards, Achievements — closing whatever was open on top first.
- **Settings → Home-screen widgets:** live previews with the student's own
  numbers (the task line and the streak light animate as on the phone) and
  an **Add** button that asks the launcher to place each one; on launchers
  that can't, it says how to add one by hand.
- **Right at midnight:** the widgets redraw just after each of the next
  seven midnights, so the countdowns roll over without the app being opened.
  Sign-out clears them and cancels that.
- Icons are Material Symbols Rounded, the app's own icon set, as vector
  drawables.
- `flutter analyze` clean; `flutter test` 170 passed, 4 live skipped
  (`test/home_widgets_test.dart`: every widget link and the ones that
  aren't, the exam lines the countdown reads, the seven midnights across a
  month end, and the Settings sheet at 320 dp with its task line moving
  on). The debug APK builds — aapt checks every layout and drawable, and the
  Kotlin compiles. Not yet seen on a phone: no device or emulator here.
