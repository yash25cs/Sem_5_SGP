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

## Day 7 — Mobile release readiness

**Commit:** `chore(release): prepare Android MVP build`

- Run analysis, tests, and a physical-device regression pass.
- Set an app icon, release name/version, privacy notes, and signed-build steps.
- Create a tagged release and attach the Android APK only if needed.

## Rule for future work

Do not mix unrelated features in one push. A commit should build or clearly
state what dependency remains unavailable (for example the Gemini key).
