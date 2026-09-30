# StudyTrail review — 15 August 2026

This review is read-only: no production code was changed. Items are ordered by
impact and should be resolved before adding new user-facing features.

**Status lines added 17 August 2026** record what has since been fixed. The
last two open findings — chat promising answers no function generated (P1) and
missing tests (P2) — were closed on 22 August and 4 September. A second review,
of the features added in late September, is at the end of this file.

## P0 — Prevent direct reward and badge manipulation

`award_xp(amount)`, `log_activity(minutes, tasks, xp)`, and
`unlock_badge(badge_key)` are callable RPCs with values supplied by the
authenticated client. Row Level Security ensures students can only change
their own data, but it does not stop a modified client from calling:

```text
award_xp(999999)
log_activity(999999, 999999, 999999)
unlock_badge('goal_crusher')
```

**Required change:** move privileged reward helpers behind a server-controlled
workflow. Revoke direct client execution where possible; calculate XP and
badges inside security-definer RPCs or Edge Functions that validate the action
and derive all rewards server-side. Do not accept raw XP or badge keys from a
client as proof of achievement.

**Relevant files:** `supabase/migrations/0007_activity.sql` lines 14, 63, 161.

**Status — fixed, `supabase/migrations/0008_rewards.sql`.** All three functions
are dropped from `public` and re-created in `app_private`, a schema PostgREST
does not expose and `anon`/`authenticated` have no `USAGE` on. XP is now derived
from rows the server can verify, and the finding turned out to be wider than
described: the same forgery was reachable straight through PostgREST
(`PATCH /profiles {xp:999999}`, `POST /activity_log`, `POST /user_badges`)
because no migration granted or revoked anything. Table and column privileges
are now narrowed — checked *before* RLS, so they can do what a policy cannot.
`ProfileRepository.addXp` and the old `unlockBadge` were deleted with them.

## P1 — Make multi-step writes atomic or recoverable

Several user actions span independent calls:

- Creating a goal first deactivates the old goal, then inserts the new goal,
  then inserts subjects.
- Completing a daily task updates the task, optionally updates a milestone,
  then logs activity.
- Uploading material writes Storage first, then the `materials` row.

A failure midway can leave a student with no active goal, a task completed in
the database but visually reverted, mismatched roadmap state, or an orphaned
Storage object.

**Required change:** use purpose-built RPCs/Edge Functions for transactional
database workflows. For Storage, implement compensating cleanup when the
database insert fails and retain a retryable `failed` status for ingestion.

**Relevant files:**

- `studytrail_flutter/lib/data/repositories/goal_repository.dart` line 35
- `studytrail_flutter/lib/state/home_store.dart` line 69
- `studytrail_flutter/lib/data/repositories/material_repository.dart`

**Status — fixed.** Goal creation is one `create_goal` RPC
(`0009_atomicity.sql`); task completion plus its milestone mirror and reward is
one `complete_task` RPC (`0008_rewards.sql`). Storage can't join a Postgres
transaction, so `uploadFile` now removes the object it just wrote if the
`materials` insert fails, and `deleteMaterial` drops the row *before* the object
— an orphaned object costs storage, an orphaned row breaks the screen.
`materials.status` is client-settable except for `embedded`, which a trigger
rejects unless embedded chunks exist, so a failed ingest is retryable.

## P1 — Do not promise AI answers before the AI service exists

The chat UI says Trail AI “Knows your syllabus” and claims it answers from
uploaded material. The current store persists only the student message; no
answer is generated until the Phase C Edge Function exists.

**Required change:** either finish the authenticated `chat` Edge Function
before exposing this tab, or label it “AI study assistant — coming soon” and
disable sending. When implemented, return an answer with citations and show a
clear retry state.

**Relevant files:** `studytrail_flutter/lib/screens/chat_screen.dart`,
`studytrail_flutter/lib/state/chat_store.dart`.

**Status — fixed 22 August 2026.** The `chat` Edge Function answers from the
student's own chunks with citations and writes both turns server-side; verified
on the live project (answers in 5.4–7.5 s).

## P1 — Preserve failed flashcard reviews

The flashcard store advances to the next card before the server-side grade is
saved. If the request fails, the card remains due in the database but disappears
from the current session.

**Required change:** keep a pending-review queue, restore the card on failure,
and offer retry. Alternatively wait for a successful grade before advancing.

**Relevant file:** `studytrail_flutter/lib/state/flashcard_store.dart` line 59.

**Status — fixed.** The advance stays optimistic, but a failed grade puts the
card back on the end of the queue and decrements the session counter, so it
comes round again instead of disappearing. Re-queued at the end rather than at
its old index: by the time the failure returns the student may have graded
further cards, and yanking the view backwards would be worse than the wait.

## P2 — Add parent-ownership integrity checks

Most policies validate only `auth.uid() = user_id`. A modified client can still
reference another user’s known parent UUID (for example a goal, deck, or quiz)
while supplying its own `user_id`. This does not normally expose rows, but it
allows invalid cross-user relationships and complicates future joins.

**Required change:** enforce matching ownership with insert/update policies or
prefer RPCs that derive parent ids from rows already owned by the caller.

**Relevant files:** `supabase/migrations/0001_init_schema.sql`,
`supabase/migrations/0002_features.sql`, `supabase/migrations/0003_rls.sql`.

**Status — largely fixed, by removing the write rather than policing it.** The
paths that cross a parent boundary now go through RPCs that check it:
`record_focus_session` rejects a subject that isn't the caller's,
`finish_quiz_attempt` matches every question to the caller, `complete_task`
derives the milestone task from the row it just read, `create_goal` derives
`goal_id` from the goal it just inserted. Everything else was narrowed instead:
roadmap, quiz, and quiz-question rows are no longer client-insertable at all
(they're generated artefacts), so there is nothing left to point at a stranger's
parent. Chat threads/messages are the remaining gap and close in Phase C, when
the `chat` function becomes the only writer.

## P2 — Make XP semantics consistent

Quiz completion invokes `award_xp`, but Pomodoro and flashcard actions only
write `activity_log.xp_earned`. The progress view can therefore show earned XP
that is absent from the student profile and leaderboard.

**Required change:** choose one server-side reward path for every activity and
define the XP rules in one documented location.

**Relevant files:** `supabase/migrations/0007_activity.sql`,
`studytrail_flutter/lib/state/pomodoro_store.dart`,
`studytrail_flutter/lib/state/flashcard_store.dart`.

**Status — fixed, `0008_rewards.sql`.** Every reward path now calls both
`log_activity` and `award_xp`, so `activity_log.xp_earned` and `profiles.xp` can
no longer disagree. The amounts live in one readable table, `xp_rules`, which is
also the ceiling applied to the client-writable `quiz_questions.xp_reward`. The
four `logActivity(xp: …)` calls the stores used to make are gone.

## P2 — Establish meaningful automated tests and source control

There is one smoke widget test. No repository, store, migration/RLS, or
critical-flow tests protect the project. The workspace also has no Git
repository, so changes cannot be reviewed, restored, or attributed safely.

**Required change:** initialise Git, add a remote, and introduce tests for
signup bootstrap, RLS isolation, XP restrictions, goal creation rollback,
flashcard grading failure, and the onboarding-to-home path.

**Relevant file:** `studytrail_flutter/test/widget_test.dart` line 8.

**Status — half done, and the open half.** Git is initialised with a GitHub
remote (three commits as of the baseline push). The tests are not written; the
smoke test is still the only one. This is the next piece of work, and the
reward RPCs added in 0008 are the first thing that needs covering — they are
the code most likely to be attacked and the code no test currently touches.

**Status — fixed 4 September 2026, extended 30 September.** 27 tests across
`test/stores_test.dart` (signup bootstrap, goal creation, task retry, flashcard
retry, roadmap seeding), `test/widget_test.dart`, and
`test/rooms_rewards_test.dart` (room timer sync, wallet and leaderboard parsing).
The reward RPCs themselves are covered by live probes against the hosted project
rather than unit tests — there is no local Postgres in this setup.

## Suggested delivery order

1. Fix P0 reward/badge RPC access and unify XP.
2. Add transactional workflows for goals and task completion.
3. Add tests plus Git before Phase C changes.
4. Implement Edge Functions for material ingestion and AI chat.
5. Build the real-time buddy room only after the core flows are stable.

# Review — 30 September 2026

A read of everything added between 28 and 30 September (Days 8–16), checked
against the hosted project rather than only the source. Those days had been
verified with `flutter analyze` alone, and analyze can't see a policy that
fails at runtime, a function that was never deployed, or a screen that shows
invented data.

## Fixed on 30 September (`c0842b7`, details in `DAILY_PLAN.md` Day 17)

| Severity | Finding | Fix |
|---|---|---|
| P0 | `room_members` RLS policy read its own table → `42P17` on every read. Lobby, member list and room chat silently dead. | `0011` non-recursive policy |
| P0 | Any student could insert themselves into any room as `host`, past capacity and closed-room checks. | `0011`: membership changes are RPC-only |
| P1 | Lobby **Join** entered without joining, so chat was unreadable. | Joins through `join_room_by_code` |
| P1 | Timer broadcasts read at the wrong payload level — every member's timer went to 00:00. | Unwrapped; late joiners get `sync` |
| P1 | `delete-account` and `summarize-material` never deployed. | Deployed; storage cleanup pages past 100 files |
| P1 | Rewards spent XP in SharedPreferences (per phone, shared across accounts); coupons had no effect. | `0012` server wallet; freeze and border enforced server-side |
| P1 | Leaderboard padded with nine invented students, a copied banner, and fake promotion zones. | Real classmates only |
| P2 | Leaderboard ranked by XP-within-level. | Ranked by total XP |
| P2 | Reminder fired at 18:00 UTC (23:30 IST); Settings switches did nothing. | Local time, inexact, switch wired |
| P2 | Other members' names blank (profiles are owner-only). | `get_room_members()` |
| P2 | Room chat times shown in UTC; duplicate bubbles possible. | Local time; client-chosen ids |
| P3 | Onboarding hung offline after saving the academic profile. | Routed through the entry check's retry screen |

## Still open

- **Two-phone Realtime pass.** The database side of rooms is verified live;
  timer broadcast, presence and the chat echo can only be proven on two devices
  (`SETUP.md` §8 items 13–18).
- **Streak days roll over at 05:30 IST.** `log_activity` uses `current_date` on
  a UTC server. Needs the student's timezone passed in or stored.
- **Semester is stored inside `profiles.branch`** as `"<branch> · Semester N"`
  and parsed back out. Give it its own column.
- **Achievements screen hides load failures.** `GamificationStore.load()`
  catches every error per section, so offline shows empty sections with no retry.
- **Dark mode isn't persisted** — `ThemeController` resets to light on launch.
- **Room broadcast and presence use a public Realtime channel** named after the
  room id. Private channels need Realtime Authorization policies.
- **Email confirmation is off** on the hosted project, which is right for
  development and wrong for real users.
- **Android toolchain sits exactly on Flutter's minimum** for Gradle, AGP and
  Kotlin; the next Flutter release that raises a floor will fail the build.
