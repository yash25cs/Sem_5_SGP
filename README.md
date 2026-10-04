# StudyTrail

StudyTrail is a Flutter mobile exam-preparation planner for the SGP project.
It helps a student turn a syllabus into a roadmap, daily tasks, review cards,
quizzes, progress insights, and cited AI help.

## Repository layout

```text
studytrail_flutter/  Flutter application
supabase/            PostgreSQL migrations, RLS, Storage policies, RPCs, Edge Functions
SGP/                 Project proposal and academic context
studytrail_ui.html   Earlier browser UI prototype (kept unchanged)
FLOW.md              Runtime and data-flow documentation
DECISIONS.md         Architecture decisions and trade-offs
OWNERSHIP.md         Module ownership and security boundaries
REVIEW.md            Known review findings and recommended fixes
DAILY_PLAN.md        Small, pushable daily delivery plan
```

## Run the Flutter app

1. Create `studytrail_flutter/dart_define.json` locally. It is ignored by Git.

   ```json
   {
     "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
     "SUPABASE_ANON_KEY": "YOUR_PUBLISHABLE_KEY"
   }
   ```

2. Run on a connected Android device:

   ```powershell
   cd studytrail_flutter
   flutter pub get
   flutter run --dart-define-from-file=dart_define.json
   ```

For the complete Supabase setup, see [SETUP.md](SETUP.md) and
[supabase/README.md](supabase/README.md). Sections 7 and 8 of `SETUP.md` cover
release builds, signing, and the manual device checklist.

## What the app collects

Written down plainly because an exam planner sees a student's coursework, and
because anyone installing this deserves to know before they upload a file. There
is no analytics SDK, no advertising library, no crash reporter, and no device
identifier of any kind. The app declares four Android permissions:
`INTERNET` to reach Supabase; `POST_NOTIFICATIONS` for the optional study
reminders (Android 13+ asks first); `RECEIVE_BOOT_COMPLETED` so they survive a
restart; and `VIBRATE`, which the notification plugin adds. Reminders are
scheduled on the phone itself — there is no push server. Files come through the
system document picker and photos through the system camera app, neither of
which needs a permission of its own.

Everything below lives in the Supabase project **you** create, under Row Level
Security scoped to the signed-in user (`OWNERSHIP.md`):

- **Account** — email, password (hashed by Supabase Auth, never seen by the app),
  the full name typed at signup, and the academic profile asked for right after
  it: program (with semester, or class for school students), an optional
  branch, and the school or college.
- **Study material** — the PDFs and notes uploaded, in a private Storage bucket,
  plus the text extracted from them and its embeddings (`material_chunks`).
- **Study activity** — goals, subjects, roadmap, daily tasks, quiz attempts and
  answers, flashcard schedules (including the "My mistakes" deck the server
  fills from wrong quiz answers), study-log entries, XP, streaks, badges, and
  rewards bought with XP — plus the phone's offset from UTC, so streaks follow
  the student's own day.
- **Chat** — questions asked, answers received, and which chunks were cited.
- **Exam practice** — past papers uploaded and the questions read from them,
  and written answers with the AI's marks and feedback. A photo of a
  handwritten answer is read, marked and deleted; what was read from it is kept
  with the grade.
- **Doubt board** — doubts posted and answers written, upvotes, and any reports.
- **Preferences** — the language explanations come back in (English, Hindi or
  Gujarati).
- **Study rooms** — messages sent, group-quiz answers and scores, plus any
  blocks and reports the student makes (reports are kept for whoever runs the
  project to review).

Most of that is visible only to its owner. Four things are shared on purpose:

- **Class leaderboard** — once a student joins a class, classmates see their
  name, level, total XP, and whether they bought the golden border. Leaving the
  class removes them from it.
- **Study rooms** — members of the same room see each other's name, whether
  they're focusing or on a break, and the room's chat messages. Once a group
  quiz ends, everyone who was in it sees every player's score and rank.
- **Open rooms** — every signed-in student can see an open room's name, invite
  code, and member count, which is how the lobby works.
- **Doubt board** — classmates see the doubts and answers posted in their class,
  with the author's name. An AI answer is labelled as written from the asker's
  notes. Blocking someone hides what they post.

A few things stay on the phone and are never uploaded: timer presets, dark
mode, whether reminders are on, whether the welcome tour has been seen, a copy
of the student's flashcards for offline review, and what the home-screen widget
shows (next exam, today's tasks, streak — cleared on sign-out).

Two third parties are involved, both server-side:

- **Supabase** hosts the database, storage, and Edge Functions.
- **Google Gemini** receives material text (during ingestion and generation),
  chat questions, doubts, and answers to be marked — including answer photos —
  from the Edge Functions only. The Gemini key never reaches the
  app (`DECISIONS.md` D-006), and nothing is sent to Gemini except in service of a
  request the student made.

**Deleting an account:** Settings → **Delete account**. The `delete-account`
Edge Function removes the student's uploaded files, then the sign-in itself;
every table cascades from that, so nothing of theirs is left behind. It acts
only on the account whose token made the request.

## Security rules

- Never commit `dart_define.json`, a Gemini key, or a Supabase `service_role`
  key.
- The Flutter app uses only the Supabase URL and anon/publishable key.
- All user data is protected with Supabase Row Level Security.
- Gemini calls belong only in authenticated Supabase Edge Functions.

## Development cadence

Follow [DAILY_PLAN.md](DAILY_PLAN.md): one focused change per day, one
descriptive commit, then update the flow and decision documentation when a
meaningful path or trade-off changes.
