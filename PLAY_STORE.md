# Play Store internal testing

What is ready in the repository, and the steps only the account owner can do.
Internal testing reaches up to 100 testers by email, with no review wait after
the first one.

## Ready in the repository

- **The bundle builds.** From `studytrail_flutter/`:

  ```bash
  flutter build appbundle --release --dart-define-from-file=dart_define.json
  ```

  It lands in `build/app/outputs/bundle/release/app-release.aab`. Without
  `android/key.properties` it is signed with the debug key, which Play
  rejects — create the upload key first (below).
- **Target and minimum SDK** come from Flutter 3.47: target 36, minimum 24.
  Play's current floor for new apps is 35.
- **Version** is `version:` in `pubspec.yaml` — `1.0.0+1` is versionName `1.0.0`,
  versionCode `1`. Every upload needs a higher number after the `+`.
- **Permissions:** `INTERNET`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
  `VIBRATE`. No location, contacts, microphone or storage permission; the
  camera opens through the system app.
- **Account deletion** is in the app (Settings → Delete account), as Play
  requires.
- **Privacy policy and deletion pages:** `docs/privacy-policy.md` and
  `docs/delete-account.md`, written for GitHub Pages.

## Steps for the account owner

1. **Upload key.** Follow `SETUP.md` §7, "Signing it with your own key". Keep
   the `.jks` file and its password somewhere safe outside the repository.
2. **Publish the two pages.** On GitHub: the repository → Settings → Pages →
   deploy from branch `main`, folder `/docs`. They will be at
   `https://yash25cs.github.io/Sem_5_SGP/privacy-policy` and
   `.../delete-account`. Read them first: they say what the app stores and
   who can see it.
3. **Play Console account** at play.google.com/console — a one-time US$25 fee
   and identity verification. New personal accounts have had to run a closed
   test (12 testers for 14 days, last time this was checked) before they can
   publish to production — the Console shows the current rule. Internal
   testing isn't held to it.
4. **Create the app:** name StudyTrail, default language English (India), App,
   Free.
5. **Internal testing → Create new release.** Accept Play App Signing, upload
   the `.aab`, add release notes, and add testers by email (or a Google Group).
   Share the opt-in link with them.
6. **App content** (Play Console → Policy → App content):
   - *Privacy policy:* the privacy-policy URL from step 2.
   - *App access:* "All or some functionality is restricted" — give reviewers
     a test account (email and password) that already has a goal and a
     material, so they don't stop at sign-up.
   - *Ads:* no ads.
   - *Content rating:* the questionnaire. Users can talk to each other (study
     room chat, the doubt board); say so — blocking and reporting are in the app.
   - *Target audience:* university students. Choose **18 and over** unless you
     mean to support younger students; never select under 13.
   - *Data safety:* see below.
   - *Account deletion:* the in-app path, and the delete-account URL.
7. **Store listing** (needed even for internal testing): icon 512×512,
   feature graphic 1024×500, at least two phone screenshots, and the text below.

## Data safety answers

From README "What the app collects" — check them against the build you upload.

| Data type | Collected | Why | Optional |
|---|---|---|---|
| Name, email address | Yes | Account | No |
| User IDs (enrollment ID) | Yes | Academic profile | No |
| Photos | Yes — notes, papers, answers (answer photos deleted after marking) | App functionality | Yes |
| Files and docs | Yes — uploaded study material | App functionality | Yes |
| In-app messages | Yes — study-room chat, doubt board | App functionality | Yes |
| Other user-generated content | Yes — chat questions, written answers | App functionality | Yes |
| App interactions | Yes — tasks, quizzes, focus time, XP | App functionality | No |

- **Shared with third parties:** No. Supabase and Google Gemini process data on
  the app's behalf, which Play counts as service providers, not sharing.
- **Encrypted in transit:** Yes (HTTPS only).
- **Users can request deletion:** Yes — in the app, and by the URL above.
- No location, contacts, financial, health, device or advertising identifiers.

## Listing text

**Short description (80 characters max)**

> Plan your exams, practise from your own notes, and study with your class.

**Full description**

> StudyTrail turns your syllabus and notes into an exam plan you can follow.
>
> • Upload your notes, syllabus or a photo of a page. Ask the AI tutor
>   anything and get answers from your own material, with citations.
> • A week-by-week roadmap to your exam date, and a catch-up plan when you
>   fall behind.
> • Quizzes and flashcards written from your notes. Questions you get wrong
>   become cards in "My mistakes".
> • Past papers: upload one and see which topics come up most, then take a
>   mock exam weighted the same way.
> • Answer practice: write a 5- or 10-mark answer — or photograph your
>   handwritten one — and get marked like an examiner would.
> • Explanations in English, Hindi or Gujarati.
> • Study rooms with a shared focus timer, chat and group quizzes, including a
>   speed round.
> • A class doubt board, a class leaderboard, streaks, badges and a weekly
>   report.
>
> No ads. Your notes stay in your account, and you can delete everything from
> Settings at any time.
