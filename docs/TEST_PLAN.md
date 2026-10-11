# StudyTrail test plan

Two halves: what the automated tests already prove (you don't need to redo
those by hand), and what only a real phone can show.

Last full run: **12 October 2026** — 253 unit and widget tests and 74 live
end-to-end tests, all passing. Three bugs were found and fixed on the way (see
the end).

---

## 1. Automated — already verified

### Unit and widget tests (no network)

```bash
cd studytrail_flutter
flutter test
```

253 tests: every store's logic against fake repositories, and the screens laid
out at 320 dp with long names — tasks and Undo, quizzes and their history,
flashcards (offline too), chat and its starters, answer practice, past papers,
rooms (timer sync, pause requests, group and speed quizzes, shared materials,
history), rewards, badges, onboarding forms, home-screen widget data, loading
and arrival animations.

### Live end-to-end tests (the real backend)

```bash
cd studytrail_flutter
STUDYTRAIL_LIVE=1 flutter test test/live --concurrency=1
```

These run the app's **real repositories** against the hosted Supabase project
as throwaway students, who delete themselves at the end. About 7 minutes. Run
them one file at a time (`--concurrency=1`): run together they make ~15 AI
requests a minute and hit Gemini's free-tier limit.

| File | What it proves |
|---|---|
| `e2e_study_test.dart` (23) | One student's whole journey: profile, goal with dated subjects (blank names dropped, dates kept in step), text and **PDF** notes read into chunks, a broken PDF failing cleanly and retrying, a client unable to fake "ready", typed syllabus, summary, roadmap, Today planned from it, **a tick paying 15 XP once** (untick/retick pays nothing), roadmap and Today staying in step, streak, **regenerating clearing the old plan from Today**, catch-up, quiz (**first attempt pays, retakes don't**, a finished attempt can't be paid twice), forged scores refused, attempt history deleted with XP kept, weak spots, flashcards (a due card pays 2 XP once, card and deck deletion), cited chat answers, save-as-cards, forged chat rows refused, answer practice (**≤ 6 marks**, too-short answers refused, scores within the marks, forged grades refused), past paper PDF → questions → topics → mock exam, focus XP, badges, leaderboard, weekly report, analytics, XP and badges not client-writable, rewards (balance, refusal, lifeline used once), goal deletion, account deletion (sign-in gone, data gone) |
| `e2e_social_security_test.dart` (31) | **Isolation**: a second student can't read 13 kinds of the first one's rows, can't update, delete or insert in their name, can't tick their task, finish their quiz, read/list/write their files, or use their files in any of six AI functions; a client with no account sees nothing. **Rooms**: capacity, case-insensitive codes, outsiders can't read or post, 500-character limit, host-only timer and quiz, shared material saved by a member and hidden from outsiders, a full group quiz with answers hidden until it ends and podium XP, report, block, host removal with no way back, history kept after leaving, closing. **Doubt board**: asking, answering, asker-only "solved", vote toggling, AI answer once and asker-only, reports, blocking hides posts, author-only delete. **Leaderboard** rank |
| `e2e_edge_test.dart` (13) | Gujarati name with an emoji, Hindi subjects, duplicates, 120-character goal names (121 refused), no subjects, blank names refused, exams tomorrow and already past, oversized quiz/deck sizes clamped, a double tap making two good quizzes, chat in Hindi, empty and off-topic questions, room names with emoji/Gujarati (blank, over-long, oversized refused), doubt length limits, deleting a file a quiz or a room share came from, **deleting a goal keeping its notes and chats** |
| `rooms_live_test.dart` (2) | Two clients on a private room channel: timer, presence, chat echo and quiz ping delivered, an outsider and a same-named public channel hearing nothing; a shared material's ping reaching the other member |
| `answer_marks_live_test.dart`, `chat_starters_live_test.dart`, `youtube_live_test.dart` | Generated questions ≤ 6 marks; starters built from a real file's units; YouTube captions read in |

Database rules that need a clock (speed rounds, streak freezes, missed days)
were checked in rolled-back transactions when their migrations were written.

---

## 2. On a phone — only you can check these

Do the base list in [SETUP.md § 8](SETUP.md#8-manual-mobile-test-pass) first,
then the items below. Two phones (two accounts) where it says so.

### Recent features

- [ ] **Task Undo** — tap a task on Home: it ticks and "Done: …" with **Undo**
  appears *at once*, and disappears by itself after about 5 s. Undo puts it
  back. Tapping a done task only shows "Long-press it to mark it as not done";
  long-press → *Mark as not done?* → confirm reopens it. Same on the Roadmap.
- [ ] **Regenerate the roadmap** with some tasks on Today: Today then shows only
  the new plan's tasks.
- [ ] **Chat starters** — a new chat's cards and chips name your own files and
  units ("Explain Normalisation", "Summarize DBMS notes"). *New chat* gives a
  different mix. After an answer, the AI's follow-ups replace them.
- [ ] **Quiz retake** — retake a finished quiz: a *Practice* chip instead of
  "+10 XP", results say "No XP on a retake", and XP doesn't move.
- [ ] **Answer practice** — questions are 3, 4 or 6 marks (case questions up to
  6); the word guide under the box matches the marks.
- [ ] **Custom pace** — Settings → Pace → Custom → save. (This failed before
  0034.)
- [ ] **Delete a goal** — its notes are still in the library and its chats in the
  history afterwards.
- [ ] **Delete options** — a quiz's *History* → delete one attempt / *Clear
  history*; a deck's *Cards* → delete one card; delete a card mid-review;
  *Delete all* quizzes / decks (the bin icon by *New*).
- [ ] **Loading and animations** — creating a room, joining, sharing, posting a
  doubt and saving a goal show a spinner on the button; grading, writing the
  roadmap and the group quiz show the animated "working" panel; a new quiz,
  deck, task, file or doubt fades into its list.

### Two phones in one room

- [ ] **Shared material arrives live** — A shares a file: it appears on B within
  a couple of seconds *without* refreshing. B taps **Save** → *In library*, and
  it's usable for a quiz straight away. With 20 items in B's library, Save is
  refused with a message.
- [ ] **Timer stays in step** — A starts the timer. B puts the app in the
  background for 30 s, then returns: B's timer matches A's within ~5 s. A
  pauses and resumes several times quickly: B ends in the same state. B turns
  airplane mode on for 10 s and off: back in step within ~5 s.
- [ ] **Ask to pause** — B taps *Ask host to pause*: A sees "B asks to pause"
  with *Pause* / *Not now*. *Not now*: B is told the host kept it running.
  *Pause*: both pause and B is told. B's button reads "Asked…" for 30 s.
- [ ] **Speed round** — tap one option, then another before time runs out: the
  second one counts.
- [ ] **Refresh** — the ↻ button in the room reloads members, chat, shared
  materials and the quiz; the lobby's ↻ reloads rooms and history.
- [ ] **Room history** — leave a room: it's under *Your room history*. Open it:
  shared materials still saveable, your group-quiz score and rank, *Rejoin*
  while it's open, *Remove from history*.

### Edge cases only a phone shows

- [ ] **Kill the app mid-upload** (swipe it away while a file says Processing),
  reopen: the file ends Ready or shows *Retry* — never Processing forever.
- [ ] **Kill it mid-generation** (quiz, deck, roadmap): reopen — nothing half
  made, and generating again works.
- [ ] **Permissions denied** — refuse notifications (reminder switch explains),
  calendar (switch stays off with a message), camera (photo notes and
  handwritten answers explain instead of crashing).
- [ ] **Slow network** (weak signal, or a hotspot far away) — spinners show,
  and tapping *Generate* / *Create* twice doesn't make two.
- [ ] **Sign out, sign in as someone else** on the same phone: none of the
  first account's tasks, flashcards (offline copy), chats or widget data show.
- [ ] **Same account on two phones** — tick a task on one, pull to refresh on
  the other: it's ticked there too.
- [ ] **Back button** — inside a sheet, a dialog, a quiz half-way and a room:
  each closes or asks first; nothing loses work silently.
- [ ] **Smallest phone you have, largest system font, landscape** — Home, Quiz,
  Rooms and Answer practice: no clipped or overlapping text.
- [ ] **Several students at once** (a class demo): five phones generating at the
  same moment — some may see "The AI is busy right now. Try again in a
  minute." That's the free AI limit (about 15 requests a minute for everyone);
  the retry should work a minute later.

---

## 3. What this pass found and fixed

| Found by | Problem | Fix |
|---|---|---|
| live study test | Saving a **custom pace** failed with "permission denied" — on goal creation and on any pace change in Settings. `goals.daily_minutes` (0029) was never made writable. | `0034_goal_daily_minutes_grant.sql` |
| live edge test | **Deleting a goal deleted its notes and chats** (the dialog promises only subjects, roadmap and tasks) and left the notes' files stranded in storage. | `0035_goal_delete_keeps_notes.sql` — both are kept, unlinked |
| live edge test | A goal name over 120 characters was refused by the database with a raw error. | The goal-name fields stop at 120 characters |

Known limits, not bugs: the free Gemini quota (about 15 AI requests a minute,
shared by every student); once in a while, right after sign-up, a request can
be refused with "JWT issued at future" when Supabase's servers briefly
disagree about the time. Seen once in the live runs, on a test account's very
first request; it didn't recur.
