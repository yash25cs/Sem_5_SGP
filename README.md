# StudyTrail

StudyTrail is an Android exam-preparation app for students, built with Flutter
and Supabase as an SGP project. A student adds their subjects, exam dates and
notes; StudyTrail turns them into a week-by-week roadmap and daily tasks, writes
quizzes, flashcards and exam questions from those notes, marks written answers
like an examiner, and answers questions with citations from the student's own
material.

## Features

**Plan**
- **Goals and subjects** — each subject with its own exam date, and an optional
  syllabus (PDF or typed) whose units the plan follows.
- **Roadmap** — a weekly plan to the last exam, sized to the student's pace:
  Relaxed, Steady, Intense, or a custom time a day. A catch-up plan when they
  fall behind.
- **Daily tasks** on Home, ticked off to earn XP and keep the streak.
- **Reminders** at a time the student picks, a "streak at risk" nudge, and a
  Sunday weekly report.
- **Calendar sync** — exams, roadmap weeks and tasks written straight into the
  phone's calendar and kept up to date.
- **Home-screen widgets** — Today, Exam countdown and Streak.

**Learn from your own notes**
- **Library** — PDFs, photos of handwritten pages, and YouTube videos or whole
  playlists (read from their captions), up to 20 items.
- **AI tutor (chat)** — answers from the student's notes with citations, and
  suggested follow-ups.
- **Summaries** of any material.
- Explanations in **English, Hindi or Gujarati**.

**Practise**
- **Quizzes** written from the notes, with a "My mistakes" deck of every wrong
  answer, and a history of past attempts.
- **Flashcards** with spaced repetition, usable offline.
- Quizzes, attempts, decks and single cards can each be deleted, or all at
  once.
- **Answer practice** — Theory (5/10-mark) or Practical (NEP-style case
  questions in lettered parts), from all notes, one subject or one file;
  answers typed or photographed on paper, marked against the notes with
  feedback and a full-marks outline.
- **Past papers** — upload one to see which topics come up most, and take a mock
  exam weighted the same way.

**Together**
- **Study rooms** — a shared focus timer, live chat, group quizzes and speed
  rounds; members share notes that anyone in the room can save to their own
  library; a room history with each room's materials and quiz results.
- **Doubt board** — ask any student; an AI first answer from your notes;
  upvotes and "solved".
- **Leaderboard** across every StudyTrail student.

**Progress**
- **Analytics** — study time, quiz accuracy, written-answer marks (theory vs
  NEP), a week summary and a consistency heatmap.
- **XP, levels, badges with progress, streaks** and a **rewards store** (streak
  freeze, focus boost, golden border and more).
- **Focus timer** (Pomodoro) with custom presets.

## Tech stack

| Part | Built with |
|---|---|
| App | Flutter 3.47 (Dart 3.11), Provider for state, Material 3 |
| Backend | Supabase: PostgreSQL with Row Level Security, Auth, Storage, Realtime |
| Server logic | 31 SQL migrations (tables, RLS policies, RPCs) and 11 Edge Functions (Deno/TypeScript) |
| AI | Google Gemini (`gemini-3.5-flash-lite` for text, `gemini-embedding-2` for search), called only from Edge Functions |
| Android | Kotlin for the home-screen widgets and calendar sync; local notifications |
| CI | GitHub Actions: `flutter analyze`, `flutter test`, and a migrations check |

## How it fits together

```text
Flutter app (Android)
  screens ─► stores (Provider) ─► repositories ─► Supabase client
                                                   │
         ┌─────────────────────────────────────────┼──────────────────────┐
         ▼                                         ▼                      ▼
  PostgreSQL + RLS                         Edge Functions            Storage (private)
  tables, RPCs that award XP,              embed-material, chat,     uploaded notes,
  badges, streaks, leaderboard             generate-quiz/-roadmap/   papers, answer photos
                                           -flashcards, grade-answer,
                                           analyze-paper, doubt-ai, …
                                                   │
                                                   ▼
                                             Google Gemini
```

The app holds only the Supabase URL and anon key. Everything a student owns is
protected by Row Level Security; anything that awards XP or a grade happens on
the server, so it can't be edited from the phone. More detail:
[docs/FLOW.md](docs/FLOW.md) and [docs/OWNERSHIP.md](docs/OWNERSHIP.md).

## Repository layout

```text
studytrail_flutter/      Flutter application (Android)
  lib/                   screens, widgets, stores, repositories, models, services
  test/                  unit and widget tests
  android/               Android project, incl. home-screen widgets and calendar sync
supabase/                backend
  migrations/            PostgreSQL schema, RLS, RPCs — applied in order
  all_migrations.sql     every migration in one file (CI checks it matches)
  functions/             Edge Functions (all Gemini calls happen here)
docs/                    project documentation
  SETUP.md               setting up Supabase, building, and the device checklist
  FLOW.md                runtime and data flow, plus the change log
  DECISIONS.md           architecture decisions and trade-offs
  OWNERSHIP.md           module ownership and security boundaries
  REVIEW.md              review findings and how they were fixed
  DAILY_PLAN.md          the day-by-day delivery plan
  PLAY_STORE.md          Play Store listing and data-safety answers
  privacy-policy.md      privacy policy
  delete-account.md      how to delete an account
studytrail_ui.html       original browser UI prototype — the design reference (kept unchanged)
.github/workflows/       CI: analyze, test, and the migrations check
```

## Getting started

### 1. Backend (Supabase)

1. Create a Supabase project.
2. Run `supabase/all_migrations.sql` in the SQL editor (or apply
   `supabase/migrations/` in order).
3. Set the Gemini key as an Edge Function secret and deploy the functions:

   ```bash
   npx --yes supabase@latest secrets set GEMINI_API_KEY=your_key_here --project-ref YOUR_REF
   npx --yes supabase@latest functions deploy embed-material chat generate-roadmap generate-quiz generate-flashcards summarize-material analyze-paper grade-answer room-quiz doubt-ai delete-account --use-api --project-ref YOUR_REF
   ```

Full instructions, including Storage and Auth settings, are in
[docs/SETUP.md](docs/SETUP.md) and [supabase/README.md](supabase/README.md).

### 2. App

1. Create `studytrail_flutter/dart_define.json` (ignored by Git):

   ```json
   {
     "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
     "SUPABASE_ANON_KEY": "YOUR_PUBLISHABLE_KEY"
   }
   ```

2. Run on a connected Android phone:

   ```bash
   cd studytrail_flutter
   flutter pub get
   flutter run --dart-define-from-file=dart_define.json
   ```

Sections 7 and 8 of `docs/SETUP.md` cover release builds, signing, and the
manual device checklist.

### 3. Tests

```bash
cd studytrail_flutter
flutter analyze
flutter test
```

225 unit and widget tests cover the stores, repositories, onboarding, practice,
rooms, rewards and screen layouts down to a 320 dp phone. A few live tests
against a real Supabase project are skipped unless configured. CI runs the same
checks on every push.

## What the app collects

Written down plainly because an exam planner sees a student's coursework, and
because anyone installing this deserves to know before they upload a file. There
is no analytics SDK, no advertising library, no crash reporter, and no device
identifier of any kind. The app declares six Android permissions:
`INTERNET` to reach Supabase; `POST_NOTIFICATIONS` for the optional study
reminders (Android 13+ asks first); `RECEIVE_BOOT_COMPLETED` so they survive a
restart; `VIBRATE`, which the notification plugin adds; and `READ_CALENDAR` /
`WRITE_CALENDAR`, asked for only when the student turns on *Add to my
calendar*, which writes StudyTrail's own events and removes them when it's
turned off. Reminders are scheduled on the phone itself, at a time the student
picks — there is no push server. Files come through the system document picker
and photos through the system camera app, neither of which needs a permission
of its own.

Everything below lives in the Supabase project **you** create, under Row Level
Security scoped to the signed-in user (`docs/OWNERSHIP.md`):

- **Account** — email, password (hashed by Supabase Auth, never seen by the app),
  the full name typed at signup, and the academic profile asked for right after
  it: program (with semester, or class for school students), an optional
  branch, and the school or college.
- **Study material** — the PDFs, photos and notes uploaded, in a private Storage
  bucket, and the YouTube links added, plus the text read from them and its
  embeddings (`material_chunks`).
- **Study activity** — goals, subjects and exam dates, pace, roadmap, daily
  tasks, quiz attempts and answers, flashcard schedules (including the "My
  mistakes" deck the server fills from wrong quiz answers), study-log entries,
  XP, streaks, badges, and rewards bought with XP — plus the phone's offset from
  UTC, so streaks follow the student's own day.
- **Chat** — questions asked, answers received, and which chunks were cited.
- **Exam practice** — past papers uploaded and the questions read from them,
  and written answers (theory or NEP) with the AI's marks and feedback. A photo
  of a handwritten answer is read, marked and deleted; what was read from it is
  kept with the grade.
- **Doubt board** — doubts posted and answers written, upvotes, and any reports.
- **Preferences** — the language explanations come back in (English, Hindi or
  Gujarati).
- **Study rooms** — messages sent, group-quiz answers and scores, materials
  shared into a room, the rooms the student created or joined and when, plus
  any blocks and reports the student makes (reports are kept for whoever runs
  the project to review).

Most of that is visible only to its owner. Four things are shared on purpose:

- **Leaderboard** — every student sees every other student's name, level,
  total XP, and whether they bought the golden border. There are no classes:
  one leaderboard for everyone.
- **Study rooms** — members of the same room see each other's name, whether
  they're focusing or on a break, and the room's chat messages. Once a group
  quiz ends, everyone who was in it sees every player's score and rank. A
  material shared into a room can be seen and copied by anyone who is or was
  in that room, until the sharer takes it out or deletes it.
- **Open rooms** — every signed-in student can see an open room's name, invite
  code, and member count, which is how the lobby works.
- **Doubt board** — one board shared by every student: the doubts and answers
  posted there, with the author's name. An AI answer is labelled as written
  from the asker's notes. Blocking someone hides what they post.

A few things stay on the phone and are never uploaded: timer presets, dark
mode, whether reminders are on and when, whether calendar sync is on and which
calendar events it wrote, whether the welcome tour has been seen, a copy of the
student's flashcards for offline review, and what the home-screen widgets show
(exam dates, today's tasks, streak — cleared on sign-out).

Two third parties are involved, both server-side:

- **Supabase** hosts the database, storage, and Edge Functions.
- **Google Gemini** receives material text (during ingestion and generation),
  chat questions, doubts, and answers to be marked — including answer photos —
  from the Edge Functions only. The Gemini key never reaches the app
  (`docs/DECISIONS.md` D-006), and nothing is sent to Gemini except in service
  of a request the student made.

**Deleting an account:** Settings → **Delete account**. The `delete-account`
Edge Function removes the student's uploaded files, then the sign-in itself;
every table cascades from that, so nothing of theirs is left behind. It acts
only on the account whose token made the request. The in-app version of all
this is Settings → **Privacy & security**; the full policy is
[docs/privacy-policy.md](docs/privacy-policy.md).

## Security rules

- Never commit `dart_define.json`, a Gemini key, or a Supabase `service_role`
  key.
- The Flutter app uses only the Supabase URL and anon/publishable key.
- All user data is protected with Supabase Row Level Security.
- Gemini calls belong only in authenticated Supabase Edge Functions, which take
  the user's id from their login token, never from the request.
- Anything that awards XP, badges or a grade is decided on the server.

## Development cadence

Follow [docs/DAILY_PLAN.md](docs/DAILY_PLAN.md): one focused change per day, one
descriptive commit, then update [docs/FLOW.md](docs/FLOW.md) and
[docs/DECISIONS.md](docs/DECISIONS.md) when a meaningful path or trade-off
changes.
