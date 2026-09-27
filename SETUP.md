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
24 tables including `profiles`, `goals`, `material_chunks`, `flashcards`, and
`xp_rules` (the XP amounts — if that one is missing, the security migration
didn't run and the app's reward RPCs will 404).

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
2. Signup lands on the upload screen. **Authentication → Users** in the
   dashboard shows the account, and `profiles` + `streaks` each have a row.
3. Upload a PDF. The tile goes **Processing** and reaches **Embedded** within
   about a minute; `material_chunks` fills up. A file over the size limit is
   refused with a readable message, not a crash.
4. **Skip for now** also works — onboarding must not require a file.
5. Set a target: goal name, exam date, pace, at least one subject. The footer
   button stays disabled until the required fields are filled.
6. It lands on Home with the goal in the hero card.

**The five tabs**

7. **Home** — **Plan day** pulls the next unfinished milestone into today's list.
   Tick one: the checkbox sticks, XP and the streak chip move, and the Roadmap
   tab shows that checkbox ticked too. Untick it and both go back.
8. **Roadmap** — the timeline shows weeks with their state dots. Ticking a task
   here moves Home's copy as well. `tune` regenerates, warning first that it
   replaces the current plan; the milestone count doesn't double.
9. **Cards** — generate a deck from an embedded file. Review it: reveal, grade,
   and the due count drops when the session ends.
10. **Quiz** — generate a quiz and **play it to the end**. The score screen
    appears and XP is awarded. This is the one to do properly; it's the only path
    that exercises `finish_quiz_attempt`.
11. **Chat** — ask something answerable from the uploaded file. The answer cites
    the material. Ask with no material uploaded: it says so rather than inventing
    an answer.
12. **Profile** — XP, level, badges, and the streak all match what the tabs did.

**The things that only fail on a real phone**

13. **Airplane mode on, cold start.** The app shows the offline screen with
    **Try again**, not an endless spinner. Turn the network back on and retry:
    it recovers without a restart.
14. **Airplane mode mid-action.** Tick a task, generate a deck, send a chat
    message. Each fails with a readable message and stays retryable; no tick is
    left claiming a write that never happened.
15. **Rotate** on Home, Roadmap, and mid-quiz. Nothing is lost.
16. **Backgrounding.** Force-quit and reopen: still signed in, on the same tab.
17. **Keyboard.** Every text field scrolls into view when focused — the chat
    composer, the goal name, the add-task sheet.
18. **Font scale.** Set the system font to its largest and check Home and Quiz
    for clipped text.
19. **Dark mode**, if the device has it on: no unreadable text.
20. **The launcher icon** is the StudyTrail mark, not the Flutter default, and it
    is not clipped on a launcher that uses circular icons.


- **Onboarding order changed.** Auth now comes first (welcome → signup →
  upload → set target), because uploads and goals both need a `user_id`.
  A returning account that already has a goal skips straight to the home shell.
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

  Then deploy the five functions that read it (`--use-api` bundles server-side, so
  no Docker or Deno is needed locally):

  ```bash
  npx --yes supabase@latest functions deploy embed-material chat generate-roadmap generate-quiz generate-flashcards --use-api --project-ref tmakrbqggezkxtygythc
  ```

  Until both are done, uploads land on **Failed** with a readable reason and Chat
  keeps the question without answering. `supabase/README.md` lists the optional
  model/base-URL overrides.
