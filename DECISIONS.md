# StudyTrail decisions

This is the record of meaningful engineering decisions: what was chosen, why,
and the accepted trade-off. Update it whenever implementation changes involve a
non-trivial choice.

## Decision log

### D-001 — Keep the existing HTML prototype unchanged

- **Decision:** Preserve `studytrail_ui.html`; build the production frontend in
  `studytrail_flutter/` and backend assets in `supabase/`.
- **Why:** The HTML gallery is a useful visual reference and is a separate
  deliverable. Replacing it would risk losing approved UI work.
- **Trade-off:** Two UI representations must stay visually aligned.

### D-002 — Supabase for the mobile backend

- **Decision:** Use hosted Supabase for Auth, PostgreSQL, Storage, Realtime,
  Row Level Security, and Edge Functions.
- **Why:** It gives the Flutter app a direct, low-latency data layer without a
  separately hosted application server or mobile cold starts.
- **Trade-off:** Database schema and RLS policies must be designed carefully;
  PostgREST query limitations shape some repository queries.

### D-003 — Provider stores and repositories

- **Decision:** Screen widgets talk to `ChangeNotifier` stores; stores talk to
  repositories; repositories own Supabase calls.
- **Why:** It keeps rendering, async state, and persistence responsibilities
  separate and testable.
- **Trade-off:** More files than direct screen-to-database calls, but clearer
  error handling and less duplicated logic.

### D-004 — Scope data stores to the authenticated user

- **Decision:** Put the signed-in store scope above the Navigator and key it by
  user id.
- **Why:** Pushed pages need access to the same stores, while a user switch
  must discard the previous user’s cached data.
- **Trade-off:** Stores reload after sign-in/sign-out, intentionally favouring
  privacy and correctness over cache reuse.

### D-005 — Server-side scoring and spaced repetition

- **Decision:** Keep quiz scoring, XP awards, streak updates, and SM-2 card
  scheduling in Supabase RPCs.
- **Why:** A client can be altered; the backend is the authority for progress
  and rewards.
- **Trade-off:** The app needs network access to finalise those actions.

### D-006 — Gemini only in Edge Functions

- **Decision:** Use Gemini free-tier models from Supabase Edge Functions, not
  directly from Flutter.
- **Why:** The Gemini API key must remain secret and requests must derive the
  authenticated user from the Supabase JWT.
- **Trade-off:** AI features require Edge Function deployment and a Gemini key
  before they can be enabled.

### D-007 — Fetch flashcard statistics separately

- **Decision:** Query `flashcard_decks` and the aggregate `deck_stats` view
  separately, then merge the results in `FlashcardRepository`.
- **Why:** PostgREST cannot embed a `GROUP BY` view because it cannot infer a
  foreign-key relationship, producing `PGRST200`.
- **Trade-off:** One extra lightweight query avoids a schema workaround and
  keeps the statistics view secure with `security_invoker`.

### D-008 — Keep generated credentials out of source control

- **Decision:** Use gitignored `studytrail_flutter/dart_define.json` with
  `--dart-define-from-file` for the project URL and publishable key.
- **Why:** Developers can run the app without hardcoding environment-specific
  values in Dart files.
- **Trade-off:** Each development machine needs a local configuration file.

### D-009 — Use a clean baseline, then daily feature commits

- **Decision:** Create one honest baseline commit for the current working
  Flutter/Supabase implementation, then deliver one focused feature or fix per
  daily commit.
- **Why:** The workspace was developed before Git was initialised. Artificially
  splitting the existing snapshot into a fake history would make debugging and
  review less trustworthy.
- **Trade-off:** The first commit is larger, but every later change is small,
  reviewable, and traceable in `DAILY_PLAN.md`.

### D-010 — Do not publish test-account credentials

- **Decision:** The backend verification helper requires a test email and
  password at runtime instead of embedding a default test account.
- **Why:** Test credentials are still credentials; publishing them makes the
  live project unnecessarily vulnerable and creates cleanup work.
- **Trade-off:** Running the helper requires two explicit command arguments.

### D-011 — Ingestion and chat functions act as the caller, not as `service_role`

- **Decision:** `embed-material` and `chat` build their Supabase client from the
  request's own `Authorization` header, so RLS decides what they can read and
  write and `match_material_chunks` resolves `auth.uid()` to the real caller. No
  service-role key is used or stored for either function.
- **Why:** Every table they touch — `material_chunks`, `chat_messages`,
  `chat_citations` — is still owner-insertable, so the elevated key would buy
  nothing and would make a `user_id` in the request body meaningful, which is
  exactly what `OWNERSHIP.md` forbids.
- **Trade-off:** `generate-quiz` and `generate-roadmap` cannot follow this
  pattern: `0008_rewards.sql` revokes `insert` on their tables from
  `authenticated`, so they will need the service-role key and must verify the
  JWT themselves before writing.
- **Extended by D-019** on 2026-09-01, which is that trade-off arriving.
  `generate-flashcards` turned out to belong on this side of the line.

### D-012 — Read PDFs with Gemini's document vision, not a Deno PDF parser

- **Decision:** `embed-material` sends the PDF to Gemini as a `document` input
  and asks for ordered, unit-labelled sections. `.txt` and `.md` are split
  locally with no model call.
- **Why:** Neither Deno nor Docker is installed on the development machine, so a
  bundled parser could not be run even once before deploying, and pdf.js under
  the Edge Runtime is a common source of crashes. Gemini also keeps headings and
  table text readable, which a raw text extractor usually loses.
- **Trade-off:** Ingestion costs one generation call per document and is capped
  at roughly 14 MB per PDF, since the file has to be inlined as base64. Large
  files will need the Gemini Files API later.

### D-013 — Request shape for Gemini's Interactions API degrades instead of failing

- **Decision:** `_shared/gemini.ts` reads the API base URL and model ids from
  function secrets, and on a `400` that names `response_format`,
  `system_instruction` or `generation_config` it retries with a simpler request
  — down to asking for JSON in words and parsing it defensively.
- **Why:** Google's own documentation disagrees with itself about the
  Interactions endpoint (`/v1beta` vs `/v1beta2`) and about whether
  `response_format` is an object or an array. None of it can be verified locally
  without Deno, so the first real test is a deploy against live infrastructure.
- **Trade-off:** More code than a single request shape, and a wrong guess costs
  an extra round trip before it corrects itself.
- **Superseded by D-014** on 2026-08-22, once the live deploy made guessing
  unnecessary.

### D-014 — One measured request shape, not a degradation ladder

- **Decision:** Supersedes D-013. `interact()` sends exactly one shape —
  `POST /v1beta/models/{model}:generateContent` with camelCase
  `systemInstruction` and `generationConfig` — and reads the answer from
  `candidates[0].content.parts[].text`. The retry ladder, the `prependText`
  fallback and the `generateContentFallback` path are deleted.
- **Why:** Deploying settled every question the docs left open. The shape above
  works with `systemInstruction`, with `responseMimeType` +`responseSchema`, and
  with an inlined PDF. `/v1beta/interactions` does answer, but it appears in no
  model's `supportedGenerationMethods` and it re-enables thinking;
  `/v1beta2/interactions` is a 404.
- **Trade-off:** A future API change now fails outright instead of limping. That
  is the better failure: the ladder turned a wrong guess into a slow, silent
  degradation, and a hard 400 with the response body logged is diagnosable in
  one deploy.

### D-015 — Every Gemini call runs under a deadline

- **Decision:** `post()` takes a `budgetMs` for the whole call and an
  `attemptMs` per try, and each `fetch` carries `AbortSignal.timeout`. Chat asks
  for 30 s, PDF sectioning 90 s, embeddings 40 s with 20 s attempts. A timeout
  surfaces as `503 "The AI took too long to answer. Try again."`.
- **Why:** An unbounded call hits the Edge Runtime's own ceiling instead —
  `HTTP 546 {"code":"WORKER_RESOURCE_LIMIT"}` — and the worker is killed before
  it can write an error, so the student sees a blank failure with nothing in the
  logs. This is the reported symptom "it takes so much time and tells me to try
  again."
- **Trade-off:** A genuinely slow-but-successful answer is now thrown away. With
  the model in D-016 answering in under a second, that trade is close to free.

### D-016 — `gemini-3.5-flash-lite` for text, because thinking models never answer

- **Decision:** `GEMINI_TEXT_MODEL` defaults to `gemini-3.5-flash-lite`.
- **Why:** Measured against this project's key on 2026-08-22, the previous
  default `gemini-3.7-flash` never answered inside 22 s — on
  `:generateContent` or `/v1beta/interactions`, thinking off or on. Worse,
  `gemini-3.6-flash` returned in 12.5 s with `finishReason: MAX_TOKENS` and
  **empty text**, because thinking spends the same token budget as the answer.
  `gemini-3.5-flash` answered in 923 ms but spent 39 of 40 tokens thinking.
  `-lite` does no thinking: 765 ms, and it still honours `systemInstruction`,
  JSON schemas, and inline PDFs. Ingesting a real PDF went from 124.7 s (which
  died on the worker limit) to 7.4 s; chat answers land in 5.4–7.5 s.
- **Trade-off:** A lite model reasons less well on a hard question. For a tutor
  quoting the student's own notes back at them the retrieved excerpts carry the
  reasoning, and an answer that arrives beats a better one that never does.
  Anything set in `GEMINI_TEXT_MODEL` needs re-timing before it is trusted —
  `outputText()` now names both silent failures (`MAX_TOKENS`, empty text) in
  the logs so a bad swap is obvious.

### D-017 — 20 materials per student, enforced in the store

- **Decision:** `OnboardingStore.maxMaterials = 20`, checked in
  `pickAndUpload` (an oversized multi-file pick is trimmed to the free slots
  rather than refused wholesale) and surfaced in both places a file can be
  added: the onboarding drop zone and the chat screen's materials sheet.
- **Why:** Cost and answer quality point the same way. Every file is read by
  Gemini once on upload and its chunks are searched on every question, and
  `match_material_chunks` returns the 6 best regardless of how many exist — so
  past a point more files stop improving answers and start diluting retrieval,
  with a stray page from a half-related PDF outranking the right unit.
- **Trade-off:** A student with more than a semester's material has to remove
  something. Enforced client-side, so it is a guardrail rather than a security
  boundary; the real limits are the bucket quota and RLS.

### D-018 — Every request carries a deadline, and a failed startup gets a page

- **Decision:** Two layers. `TimeoutHttpClient` is passed to
  `Supabase.initialize`, so auth, REST, storage, and the functions all inherit a
  cap — 20 s for a plain round trip, 180 s where the work is legitimately long
  (`/functions/v1/`, `/storage/v1/`). On top of that, `RootFlow`'s entry check
  gets its own 10 s deadline and, if it fails, renders `ErrorScreen` with a
  **Try again** button instead of falling through to onboarding.
- **Why:** Opening the app with no internet left it on the splash spinner
  forever. Nothing in the Supabase Dart packages sets a timeout and neither does
  Dart's own client, so two things hang indefinitely: a network that accepts the
  connection and never answers (a captive portal, or full bars with no data),
  and an expired persisted session — `SupabaseClient` refreshes the token before
  every query and gotrue retries that refresh on a backoff ladder. Separately,
  `_resolveEntryStage`'s `catch` swallowed the failure and landed on the upload
  screen, so a returning student on a train was told to upload their syllabus
  again and every write they tried then failed.
- **Trade-off:** A genuinely slow-but-working connection can now be cut off at
  the deadline, which is why uploads and AI calls get 180 s rather than 20 s —
  `embed-material` alone budgets 90 s to read a PDF. The startup probe's 10 s is
  the tightest of the three because it sits between a student and their first
  frame; it covers a token refresh plus one `select … limit 1` and nothing more.
  Deliberately no `connectivity_plus`: it reports "Wi-Fi is connected", not
  "the internet works", so it would add manifest surface for a worse signal
  than a request that actually failed. The offline screen offers no **Sign out**:
  it would work (gotrue clears the local session before it tries to revoke it
  server-side) but it leads nowhere, because signing back in needs the network
  that just failed. It is offered on the non-network screen, where retrying
  can't help and a different account might.

### D-019 — `service_role` only where the schema forbids the student to write

- **Decision:** `_shared/supa.ts` gains `adminClient()`, and exactly two
  functions use it: `generate-roadmap` and `generate-quiz`, and only for the
  artefact inserts. Every read, every ownership check, and the `user_id` on every
  inserted row still come from `requireUser()`'s caller-scoped client — a
  `user_id` in the request body is never read. `generate-flashcards` gets no
  admin client at all, because `insert (user_id, deck_id, unit_label, front,
  back, source_chunk_id) on flashcards` is granted to `authenticated`; it lives
  server-side for the Gemini key, not for the write.
- **Why:** This is D-011's predicted trade-off arriving. `0008_rewards.sql`
  revokes `insert` on `milestones`, `milestone_tasks`, `quizzes` and
  `quiz_questions` from `anon, authenticated` — all four are XP-bearing if
  forged, and a self-authored quiz with known answers would be 10 XP a question
  — so there is no client path to a roadmap or a quiz at all. Its own comment
  prescribes the fix: write with the service-role key *after* verifying the JWT.
  `SUPABASE_SERVICE_ROLE_KEY` is injected into the Edge Runtime automatically, so
  this needs no secret to set and no migration.
- **Trade-off:** Two functions now hold a key that bypasses RLS, so their
  ownership checks are load-bearing in a way `chat`'s aren't: a missing
  `.eq('id', …)` on the caller's client would become a cross-account write rather
  than an empty result. Both keep `verify_jwt = true`, both scope the write to
  `Caller.userId`, and both delete what they just inserted if the child rows
  fail, so a partial artefact never survives. Rejected: a `SECURITY DEFINER` RPC
  in a new migration — it keeps the key out of the function environment entirely
  but needs another SQL-editor step on the hosted project and duplicates the
  validation into PL/pgSQL.

### D-020 — Generated practice reads one named material, not a vector search

- **Decision:** The student picks a file; `generate-quiz` and
  `generate-flashcards` read `material_chunks where material_id = ? order by
  chunk_index` and pass the text to Gemini. No `embedTexts` call and no
  `match_material_chunks`. `generate-roadmap` is the exception — being
  goal-shaped, it reads the goal, its subjects, and the distinct `unit_label`s
  across the student's materials (headings only, no chunk bodies).
- **Why:** With the file already chosen there is nothing to search *for*.
  Retrieval would return the 6 best fragments, and a 15-question quiz drawn from
  6 fragments is a quiz about whichever passage embedded best. Reading the
  document in order also sidesteps a live gap: `embed-material` writes
  `subject_id: null` on every chunk, so any subject-scoped retrieval matches
  nothing.
- **Trade-off:** A long book has to be trimmed to fit the prompt, so
  `_shared/material.ts` caps the source at ~60k characters by **sampling evenly
  across the chunks** rather than truncating at the front — deliberately, because
  head truncation would make every quiz a quiz about chapter 1. Generation is
  therefore per-file: "quiz me on everything" isn't offered, and generated
  quizzes and decks carry no `subject_id` until materials are associated with
  subjects.

### D-021 — Validate and drop per item, then insist on a minimum

- **Decision:** Every generated item is checked in Deno before the insert and bad
  ones are dropped: a question needs exactly four distinct non-empty options and
  an integer `correct_index` in 0–3; a card needs a front and a back, deduped by
  front; a milestone needs a title and at least one task. If fewer than 3
  questions (4 cards, 2 milestones) survive, the function fails with a readable
  message instead of saving a stub.
- **Why:** `quiz_questions` carries `check (array_length(options,1) = 4)` and
  `check (correct_index between 0 and 3)`, and Postgres applies them to the whole
  batch — one malformed question would reject all fifteen, turning a mostly-good
  generation into a total failure. Dropping the bad item saves the rest.
- **Trade-off:** A student can ask for 15 questions and get 12, so the client
  reports what actually landed (`FlashcardStore.generatedCards`, the quiz's own
  `length`) rather than what was requested. Roadmap weeks are renumbered after
  the drop, so a plan never reads Week 1, 2, 4.

## Update rule

For each meaningful decision, add the next `D-###` item with the decision,
reason, and trade-off. If a decision is superseded, keep it and add a new entry
that links back to it.
