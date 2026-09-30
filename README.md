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
identifier of any kind. The app declares three Android permissions:
`INTERNET` to reach Supabase, `POST_NOTIFICATIONS` for the optional 6 PM study
reminder (Android 13+ asks first), and `RECEIVE_BOOT_COMPLETED` so that reminder
survives a restart. The reminder is scheduled on the phone itself — there is no
push server. File uploads go through the system document picker, which needs no
permission.

Everything below lives in the Supabase project **you** create, under Row Level
Security scoped to the signed-in user (`OWNERSHIP.md`):

- **Account** — email, password (hashed by Supabase Auth, never seen by the app),
  the full name typed at signup, and the academic profile asked for right after
  it: college, program/branch with semester, and enrollment ID.
- **Study material** — the PDFs and notes uploaded, in a private Storage bucket,
  plus the text extracted from them and its embeddings (`material_chunks`).
- **Study activity** — goals, subjects, roadmap, daily tasks, quiz attempts and
  answers, flashcard schedules, study-log entries, XP, streaks, badges, and
  rewards bought with XP.
- **Chat** — questions asked, answers received, and which chunks were cited.

Most of that is visible only to its owner. Three things are shared on purpose:

- **Class leaderboard** — once a student joins a class, classmates see their
  name, level, total XP, and whether they bought the golden border. Leaving the
  class removes them from it.
- **Study rooms** — members of the same room see each other's name, whether
  they're focusing or on a break, and the room's chat messages.
- **Open rooms** — every signed-in student can see an open room's name, invite
  code, and member count, which is how the lobby works.

A few preferences stay on the phone and are never uploaded: timer presets,
whether the reminder is on, and whether the welcome tour has been seen.

Two third parties are involved, both server-side:

- **Supabase** hosts the database, storage, and Edge Functions.
- **Google Gemini** receives material text (during ingestion and generation) and
  chat questions, from the Edge Functions only. The Gemini key never reaches the
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
