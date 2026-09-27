# StudyTrail

StudyTrail is a Flutter mobile exam-preparation planner for the SGP project.
It helps a student turn a syllabus into a roadmap, daily tasks, review cards,
quizzes, progress insights, and cited AI help.

## Repository layout

```text
studytrail_flutter/  Flutter application
supabase/            PostgreSQL migrations, RLS, Storage policies, RPCs
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
identifier of any kind. The only Android permission the app declares is
`INTERNET`; file uploads go through the system document picker, which needs none.

Everything below lives in the Supabase project **you** create, under Row Level
Security scoped to the signed-in user (`OWNERSHIP.md`):

- **Account** — email, password (hashed by Supabase Auth, never seen by the app),
  and the full name typed at signup.
- **Study material** — the PDFs and notes uploaded, in a private Storage bucket,
  plus the text extracted from them and its embeddings (`material_chunks`).
- **Study activity** — goals, subjects, roadmap, daily tasks, quiz attempts and
  answers, flashcard schedules, study-log entries, XP, streaks, and badges.
- **Chat** — questions asked, answers received, and which chunks were cited.

Two third parties are involved, both server-side:

- **Supabase** hosts the database, storage, and Edge Functions.
- **Google Gemini** receives material text (during ingestion and generation) and
  chat questions, from the Edge Functions only. The Gemini key never reaches the
  app (`DECISIONS.md` D-006), and nothing is sent to Gemini except in service of a
  request the student made.

**Known gap:** there is no in-app "delete my account" yet. Removing an account
today means deleting the user in the Supabase dashboard, which cascades the rest.
Say so rather than implying a control that doesn't exist.

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
