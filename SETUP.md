# StudyTrail — setup

What you need to do once, to get the app talking to a real backend.

## 1. Create a Supabase project (free)

1. Sign in at [supabase.com](https://supabase.com) → **New project**.
2. Region: pick the closest one (e.g. **South Asia (Mumbai)**) — this is the
   single biggest factor in how snappy the app feels on your phone.
3. Set a database password and save it somewhere.

Wait ~2 minutes for provisioning.

## 2. Apply the database schema

Open **SQL Editor** → **New query** → paste the entire contents of
`supabase/all_migrations.sql` → **Run**.

You should see `Success. No rows returned`. Verify under **Table Editor**:
44 tables including `profiles`, `goals`, `material_chunks`, `flashcards`,
`study_rooms`, `reward_catalog`, `exam_papers`, `room_quizzes`, `doubts`,
`material_playlists`, and `xp_rules` (the XP amounts — if that one is
missing, the security migration didn't run and the app's reward RPCs will 404).
If `reward_catalog` is missing, migrations 0010–0012 didn't run: study rooms and
the Rewards screen will fail. If `room_quizzes` is missing, 0013–0019 didn't:
past papers, answer practice, weak spots, catch-up and group quizzes will. If
`doubts` is missing, 0020–0023 didn't: private room channels, the doubt board,
speed rounds, the weekly report and the mistakes deck will. If
`material_playlists` is missing, 0024 didn't: adding a YouTube playlist will
fail.

If the `vector` extension errors, enable it first under
**Database → Extensions** (search "vector"), then re-run. The script is
idempotent, so re-running is safe.

If the storage section errors with *"must be owner of table objects"*, create
the bucket manually: **Storage → New bucket** → name `materials`, **not**
public → then add the four policies from `supabase/migrations/0005_storage.sql`
under **Storage → Policies**.

## 3. Turn off email confirmation (for development)

**Authentication → Sign In / Providers → Email** → turn **Confirm email**
OFF. Otherwise every test signup waits on an inbox round-trip.

Turn it back **on** before anyone other than you signs up: with it off, anyone
can create accounts under email addresses they don't own.

## 4. Copy your keys

**Project Settings → API Keys**:

- **Project URL** — `https://xxxxxxxx.supabase.co`
- **anon / publishable key** — starts with `eyJ` or `sb_publishable_`

The anon key is safe to put in the app; RLS is what protects the data. The
**service_role** key must never go in the app.

## 5. Run the app

```bash
flutter run -d 3C15A60003Y00000 --dart-define=SUPABASE_URL=https://YOUR.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_KEY
```

Running without these shows a "Backend not configured" screen instead of
crashing.

To avoid retyping, put them in `studytrail_flutter/dart_define.json`:

```json
{
  "SUPABASE_URL": "https://YOUR.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_KEY"
}
```

```bash
flutter run -d 3C15A60003Y00000 --dart-define-from-file=dart_define.json
```

That file is gitignored — keep it off version control.

## 6. Verify it worked

1. Tap through Welcome → **Create account** with a real-looking email.
2. In the dashboard, **Authentication → Users** shows the new user.
3. **Table Editor → profiles** shows a matching row — created automatically by
   the `handle_new_user` trigger, along with a row in `streaks`.
4. Force-quit the app and reopen it: you should still be signed in.

## 7. Build a release APK

A debug build is fine for development but is slow, ships the Dart VM, and is
signed with a throwaway key. For anything you hand to someone else:

```bash
flutter build apk --release --dart-define-from-file=dart_define.json
```

The APK lands in `studytrail_flutter/build/app/outputs/flutter-apk/app-release.apk`.
`--dart-define-from-file` is not optional here — without it the release build
opens on "Backend not configured", because the URL and anon key are compiled in,
not read at runtime.

That APK is ~54 MB because it carries native code for all three ABIs
(`arm64-v8a`, `armeabi-v7a`, `x86_64`) and a phone uses exactly one of them. For
something you actually send to someone:

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=dart_define.json
```

That writes one APK per ABI — `app-arm64-v8a-release.apk` is ~20 MB and is the
one any phone made in the last decade wants. R8 and Android resource shrinking are
already on; they come from the Flutter Gradle plugin and are deliberately left
alone (`DECISIONS.md` D-023).

`versionName` and `versionCode` both come from `version: 1.0.0+1` in
`pubspec.yaml` (`1.0.0` before the `+`, `1` after). Bump the number after the `+`
on every build you distribute; Android refuses to install an APK whose
`versionCode` isn't higher than the one already on the device.

### Signing it with your own key

Without a key of your own the release build is signed with the **debug** key —
it installs and runs, but it can't be published, and it can't be upgraded by a
later properly-signed build. To create a real one:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep `upload-keystore.jks` **outside** the repository — losing it means you can
never update the app again, and committing it means anyone can sign as you.
Then create `studytrail_flutter/android/key.properties`:

```properties
storePassword=whatever_you_typed
keyPassword=whatever_you_typed
keyAlias=upload
storeFile=C:/Users/you/keys/upload-keystore.jks
```

`storeFile` is resolved relative to `android/app/`, so use a full path unless you
enjoy counting `../`. Both `key.properties` and `*.jks`/`*.keystore` are
gitignored. `android/app/build.gradle.kts` reads the file if it exists and falls
back to the debug key if it doesn't, so a fresh clone still builds.

Because that fallback is silent, check which key you actually got:

```bash
"$ANDROID_HOME/build-tools/36.1.0/apksigner" verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

`CN=Android Debug` means the fallback fired and `key.properties` wasn't found.
Fine for testing on your own device, useless for publishing.

### One-time gotcha: the package name changed

The application id is `in.charusat.studytrail` (it used to be
`in.charusat.studytrail.studytrail_flutter`). Android treats a different id as a
different app, so the first build after this change **installs alongside** any
older one instead of upgrading it. Uninstall the old one; nothing is lost that
isn't in Supabase.

## 8. Manual mobile test pass

Nothing here can be automated — `flutter test` runs against fakes, and the parts
most likely to break on a phone (a real keyboard, a real network, a real
`file_picker` sheet) are exactly the parts a widget test can't see. Run the whole
list on a physical device before calling a build good.

**Onboarding, on a fresh install and a brand-new email**

1. Welcome → **Next** → **Create account**. The name, email, and password fields
   each show their own validation message when wrong.
2. Signup lands on the academic profile form (college, program/branch,
   semester, enrollment ID); saving it moves on to the upload screen.
   **Authentication → Users** in the dashboard shows the account, and
   `profiles` + `streaks` each have a row.
3. Upload a PDF. The tile goes **Processing** and reaches **Embedded** within
   about a minute; `material_chunks` fills up. A file over the size limit is
   refused with a readable message, not a crash.
4. **Skip for now** also works — onboarding must not require a file.
5. Set a target: goal name, exam date, pace, at least one subject. The footer
   button stays disabled until the required fields are filled.
6. It lands on Home with the goal in the hero card.

**The five tabs** — Home, Roadmap, Chat, Quiz, Profile. Flashcards, focus
timer, study rooms, achievements, leaderboard, rewards and analytics open from
the **+** button.

7. **Home** — **Plan day** pulls the next unfinished milestone into today's list.
   Tick one: the checkbox sticks, XP and the streak chip move, and the Roadmap
   tab shows that checkbox ticked too. Untick it and both go back.
8. **Roadmap** — the timeline shows weeks with their state dots. Ticking a task
   here moves Home's copy as well. The sparkle button at the top regenerates,
   warning first that it replaces the current plan; the milestone count doesn't
   double.
9. **Flashcards** (from **+**) — generate a deck from an embedded file. Review
   it: reveal, grade, and the due count drops when the session ends.
10. **Quiz** — generate a quiz and **play it to the end**. The score screen
    appears and XP is awarded. This is the one to do properly; it's the only path
    that exercises `finish_quiz_attempt`.
11. **Chat** — ask something answerable from the uploaded file. The answer cites
    the material. Ask with no material uploaded: it says so rather than inventing
    an answer.
12. **Profile** — XP, level, badges, and the streak all match what the tabs did.

**Study rooms — needs two phones and two accounts**

13. Phone A opens a room from **+ → Study rooms** → **+**: the sheet asks only
    for a name and how many people (2–6), nothing about the timer. Pick 2.
    Phone B sees it in the lobby with `1/2` members and joins with the **Join**
    button; a third account typing the code into the full room is told it's
    full.
14. Both phones list both names under the room, with a status dot: green while
    the timer runs, amber on a break, grey when stopped.
15. A taps **Change** under the timer and picks 45 min focus / 10 min break:
    both phones show `45 min focus` and 45:00 (B has no **Change**). A starts the
    timer. B's timer starts at the same time and counts down with it (never
    jumps to 00:00). A pauses: B pauses at the same second.
16. With A's timer running, B leaves and rejoins. B's timer picks up at A's
    time instead of restarting.
17. Chat both ways. Each message appears once on both phones, with the local
    time. Messages are still there after leaving and rejoining.
18. B presses the phone's back button: it asks before leaving. A closes the
    room: B is told the host closed it, and the room disappears from the lobby.

**Rewards, reminders, account**

19. **Leaderboard** (from **+**) — without a class it offers to pick one; after
    joining, it lists only real classmates, ranked by total XP.
20. **Rewards** (from **+**) — the balance matches XP earned. With under 100 XP,
    **Redeem** is disabled and says how much more is needed.
21. **Settings → Daily study reminder** — turning it on asks for notification
    permission and confirms 6:00 PM. Turn it off and back on: no duplicate
    reminders.
22. **Settings → Delete account** with a throwaway account: the app returns to
    sign-in, and the account can no longer log in.

**The things that only fail on a real phone**

23. **Airplane mode on, cold start.** The app shows the offline screen with
    **Try again**, not an endless spinner. Turn the network back on and retry:
    it recovers without a restart.
24. **Airplane mode mid-action.** Tick a task, generate a deck, send a chat
    message. Each fails with a readable message and stays retryable; no tick is
    left claiming a write that never happened.
25. **Rotate** on Home, Roadmap, and mid-quiz. Nothing is lost.
26. **Backgrounding.** Force-quit and reopen: still signed in, on the same tab.
27. **Keyboard.** Every text field scrolls into view when focused — the chat
    composer, the goal name, the add-task sheet.
28. **Font scale.** Set the system font to its largest and check Home and Quiz
    for clipped text.
29. **Dark mode** (Settings): no unreadable text, and the choice survives
    closing and reopening the app.
30. **The launcher icon** is the StudyTrail mark, not the Flutter default, and it
    is not clipped on a launcher that uses circular icons.

**Day 18 features**

31. **Photo notes** — Chat → materials → *Snap your notes*: a photo of a
    handwritten page reaches Ready, and chat can answer from it.
32. **Chat** — after an answer, three follow-up chips replace the starters.
    *Save as flashcards* under an answer adds cards to "Saved from chat" once
    (a second tap does nothing).
33. **Weak spots** — play a quiz and get one unit wrong on purpose. Home's Weak
    spots card names that unit; *Practice quiz* makes a quiz only on it.
34. **Catch up** — with a roadmap, leave a planned task undone past midnight.
    Home shows the catch-up banner; *Catch up* moves it to today and plans the
    week. Try it between midnight and 5:30 AM too.
35. **Past papers** (+ menu) — upload a past paper; each question gets a unit;
    *Mock exam* builds 15 questions; *Practise answering* opens answer practice.
36. **Answer practice** (+ menu) — write a weak answer, then a good one; the
    marks and "what would earn more" should differ sensibly.
37. **Subject exam dates** — tap *Set exam date* under a subject on Home; the
    *Next exam* strip appears; regenerating the roadmap finishes that subject by
    its exam week.
38. **Offline cards** — open Flashcards once online, then airplane mode: the
    decks still load, a session runs, the banner counts queued grades, and they
    sync the next time Flashcards opens online.
39. **Rooms** — study XP arrives after a completed focus block; long-press a
    message to report/block; as host, tap a buddy to remove them.
40. **Group quiz** (two phones in one room) — the host taps *Start a group
    quiz*, picks a ready file and 5 questions. B sees *I'm in* / *Not now*; no
    question shows until B agrees, then both get the same questions. Hand in on
    both: the card shows both scores ranked, *Answers* shows the right options,
    and the winner's XP goes up by 30 (second by 20 if they got any right). A
    second quiz where B taps *Not now* is cancelled for both.
41. **Reminders** — study before 6 PM: no 6 PM reminder that day.
42. **Handwritten answer** — Answer practice → *Photo of my paper*, photograph
    a written answer: it's marked, and *What I read from your page* shows the
    transcription.
43. **Language** — Settings → *Explanations in* → ગુજરાતી: the next chat answer,
    summary and answer feedback come back in Gujarati.
44. **My mistakes** — finish a quiz with a wrong answer: the results say so,
    and Flashcards lists *My mistakes* first with that question due.
45. **Weekly report** (+ → Progress) — this week against last, with the
    focus-per-day chart; a Sunday 7 PM notification opens it.
46. **Speed round** (two phones) — the host picks *Speed round*, 10 s: both
    phones show a 5-second countdown, the same question at once, then the right
    answer and the scores; the faster right answer scores more.
47. **Doubt board** (+ → Together, both accounts in one class) — A asks with
    *Get a first answer from AI* on; B sees the doubt and the AI answer,
    answers, and A marks it solved.
48. **Calendar** — Settings → *Add to my calendar*: the share sheet offers
    `studytrail.ics`; importing it shows the exams with reminders.
49. **Home-screen widget** — long-press the launcher → Widgets → StudyTrail:
    days to the next exam and today's tasks; ticking a task in the app updates
    it.


- **Onboarding order.** Auth comes first (welcome → signup → academic
  profile → upload → set target), because uploads and goals both need a
  `user_id`. A returning account that already has a goal skips straight to the
  home shell — unless its college, branch or enrollment ID is missing, in which
  case it is asked for those first.
- **Google sign-in** additionally needs the provider enabled in the dashboard
  and `in.charusat.studytrail://login-callback` added under
  **Authentication → URL Configuration**. The Android intent-filter is already
  in place.
- **Gemini API key** is what turns on material ingestion and AI chat. Get one
  from [aistudio.google.com](https://aistudio.google.com) → **Get API key**, then
  set it as a Supabase *function* secret — never a `--dart-define`, so it can't
  ship in the APK:

  ```bash
  npx --yes supabase@latest secrets set GEMINI_API_KEY=your_key_here --project-ref tmakrbqggezkxtygythc
  ```

  Then deploy all eleven functions (`--use-api` bundles server-side, so no Docker
  or Deno is needed locally). Ten read the Gemini key; `delete-account` needs
  none, but without it Settings → Delete account fails:

  ```bash
  npx --yes supabase@latest functions deploy embed-material chat generate-roadmap generate-quiz generate-flashcards summarize-material analyze-paper grade-answer room-quiz doubt-ai delete-account --use-api --project-ref tmakrbqggezkxtygythc
  ```

  Until both are done, uploads land on **Failed** with a readable reason and Chat
  keeps the question without answering. `supabase/README.md` lists the optional
  model/base-URL overrides.
