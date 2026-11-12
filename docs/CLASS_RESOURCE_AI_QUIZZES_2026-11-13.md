# Class resources and supplementary AI quizzes — local testing handoff

Implementation on `vince-branch`, November 12 UTC / November 13 Manila. Owner manual acceptance is **pending**. No production database/Storage access, reset, deployment or Git push was performed.

## A. Resource upload

The reported PDF failure was reproduced with a synthetic valid PDF: the dashboard returned HTTP 400 with the generic file error. The isolated Kong gateway recorded HTTP 503 and failed DNS resolution for the absent QA Storage container. The previous minimal quiz preview deliberately excluded `storage-api`. The private `learning-resources` bucket already existed with a 52,428,800-byte limit and the supported MIME allowlist.

A second defect appeared in the size regression: Next 15 middleware cloned and truncated request bodies at 10 MB. API routes already authenticate themselves and now bypass that no-op middleware path. Page authentication remains unchanged. The upload route authorizes the active instructor and owned active class before reading a bounded multipart stream; it checks MIME, signature, nonempty size and the same 50 MiB limit as UI and bucket. Chunked requests cannot bypass the body bound. The resource Storage client has a 30-second request timeout.

The launcher enables Storage only for `BQQuizQA20261112` (API `127.0.0.1:58921`, PostgreSQL `58922`). Restarting the earlier partial stack preserved its data volumes, accounts, attempts and grades. The original `ByteQuest` stack was left untouched. The bucket remains private; existing read RLS and the authorized metadata RPC remain in use. Server-only upload credentials never enter the browser or PDF worker.

Uploads show inline validation, real transfer progress followed by a saving state, actionable errors, retained failed inputs, success feedback and list refresh. A hash of scoped content and normalized metadata identifies identical retries. Existing objects are never overwritten. Different title/description intentionally creates a separate resource; an archived identical resource is not silently restored.

Storage and PostgreSQL cannot share a transaction. Definitive metadata rejection removes the new object. Ambiguous transport outcomes are retained in a server-only `resource_upload_jobs` compensation journal, so retry can reconcile them instead of risking a committed file. The journal stores identifiers/path/state only. `reconcile-uploads` is dry-run by default; `--apply` requires the Next preview to be stopped and only cleans expired unreferenced QA objects. It never deletes resource or learner rows.

## B. AI generation

- **Approved COC Content** retains active source approval/activation, published module/activity, approved rubric, mission alignment and criterion source-trace checks. The current isolated seed has **no approved module/activity catalog**. Its empty-state is legitimate; class uploads do not manufacture approval. Positive and negative approved-source behavior is covered with unit fixtures.
- **My Class Resource** lists only the instructor's active classes and their active resources. It authorizes the selected class/resource again on the server, checks the canonical private path, signs the download as the instructor through Storage RLS, restricts the download origin and size, and rechecks access before saving provider output. No COC association is required for supplementary resource quizzes.
- Text PDFs use pinned Mozilla PDF.js `6.5.438` in an isolated Node worker. Bounds: **10 MiB, 50 pages, 48,000 extracted characters, at least 80 non-whitespace characters, 15 seconds, 192 MB worker old-generation heap, two workers per server process**. The download is bounded and timed. Password-protected, corrupted, empty/scanned and over-limit PDFs produce specific errors. OCR, image/video transcription and arbitrary URL fetching are unsupported. Class uploads still support 50 MiB and the existing image/video formats.
- The worker receives no environment credentials. Parser output is discarded; extracted text remains in request memory and is not stored in generation context or logs. Provider context contains only the selected resource, quiz settings and optional instructor notes. Document text is untrusted reference data in the user message, with system instructions forbidding instruction overrides, tools, official claims or publishing actions. Output schema/answer validation and mandatory instructor review enforce the application boundary.
- The UI discloses that source text, focus and optional notes leave ByteQuest for OpenRouter/model-provider processing. Class-resource requests require explicit consent server-side. Source changes clear consent. Settings persist across workspace/source tabs; resource refresh and a Class Resources link are provided. Alternatives remain separate drafts and retain the original.
- A scoped request ID, unique database index and instructor advisory lock prevent duplicate provider calls and duplicate persisted drafts during concurrent retries. Completed retries return their original generation. Provider failures save no partial questions. No automatic approval or publication was added.

**Real OpenRouter status: BLOCKED by missing local API key.** The owner approved one free-model request using only the synthetic PDF. No live request has been sent. Mock provider/schema tests and the explicitly labelled loopback simulator are separate evidence. No owner-uploaded document was transmitted externally. Do not report real provider success until the authorized test actually passes.

Put the key privately in ignored `.tmp/quiz-ai.env` as `OPENROUTER_API_KEY=...`; do not put it in chat, a public variable or a committed file. Optional `OPENROUTER_MODEL` must be `openrouter/free` or end in `:free` for this local launcher. Stop the default preview, run `node scripts/quiz-preview.mjs ai-start`, then in another terminal run `node scripts/quiz-preview.mjs ai-test`. That test sends exactly one request with a newly uploaded synthetic networking PDF and saves one unapproved draft. No automatic retry, approval or publication is performed. Owner-initiated manual generation also requires the UI content-sharing confirmation.

## C. Learner parity and business rules

Both origins use the existing `quiz_items`, review RPCs, published versions, class assignments, learner RPCs, Flutter quiz screens and PostgreSQL grading. There is no learner AI interface or origin badge. Learner list/start/result contracts exclude generation IDs, provider/model and source-processing context; instructor/admin provenance and audit history are retained. A Flutter regression renders the same controls for manual/AI provenance.

The earlier migration `20261112111620_quiz_publishing_and_single_attempt.sql` remains unchanged. A canonical `(learner_id, quiz_id)` claim spans versions, assignments, classes and devices. Resume uses the original attempt/questions/answers. Completed submissions consume the attempt; row locks and the unique result identity make repeat grading idempotent. Republication/reassignment does not grant another attempt. Existing historical attempts and grades are retained. Instructor preview does not start an attempt. Publication reason remains optional/NULL; question review, archive reasons and publication/assignment authorization remain enforced.

Learner labels are: “Not started — 1 attempt available”, “In progress — Continue attempt”, “Submitted — Attempt used”, and “Unavailable — Quiz not accessible”. No mission functionality was changed.

## D. Automated verification

All checks below actually ran and passed after corrections. Final evidence is recorded in `CODEX_STATE.md`. The full resource/AI suite passed 11 groups; a separate missing-configuration API probe also passed without creating a generation or contacting a provider. Coverage includes:

| Check | Scope |
| --- | --- |
| TypeScript, ESLint, Next production build | Dashboard and server routes |
| 20 client/general tests | Existing authoring, alternatives, auth, reporting and multipart stream bounds |
| 22 server tests | Existing provider/practice regressions, approved COC validation, resource provider contract/injection isolation, PDF extraction/error/limit cases |
| 10 existing authenticated quiz API groups | Review/edit/reorder, reason-free atomic publication, RLS, 16 concurrent starts, 12 submissions, cross-device/relogin resume, republication, revoked enrollment, audit |
| Resource/AI integration groups | Real QA uploads, exact 50 MiB, invalid/oversize rejection, retries, forced metadata cleanup, Storage outage/restart, learner/private access, consent/source scope, unreadable PDFs, invalid/rate-limited responses, one provider call under concurrency, draft review/publication, 12 starts/8 submissions/one grade, republication |
| Browser regressions | Existing editor workflow; upload refresh; source controls; settings retention; disclosure; four draft types; alternatives; keyboard tabs; 320/375/768/1440 layouts |
| 5 rollback-only PostgreSQL groups | New request guard/journal RLS plus existing single-attempt, learner, foundation and historical preservation gates |
| Local database lint | `public` and `private` schemas |
| Flutter | Dependency resolution, analyzer, 451 full tests, debug APK with explicit local QA defines |

Initial regression failures were corrected and affected checks rerun: the 10 MB middleware truncation was an implementation defect; browser label/tab selectors and Storage readiness waits were test issues. The outage test also exposed unbounded Storage waits, now bounded in the upload client. A Playwright timeout printed a local QA session header once; error output is now sanitized and affected QA instructor refresh sessions were signed out. Those access tokens expire normally; no production credential was involved.

Image/video upload tests use synthetic signature fixtures; actual media playback and physical-device/owner acceptance are not claimed. Live provider quality, OCR and hosted/Linux runtime acceptance are not covered by the local simulator.

## E. Owner manual testing

Instructor preview: **http://localhost:3008**. Learner Flutter web preview: **http://127.0.0.1:3009**. Both returned HTTP 200 after the final build/restart. The simulator is stopped and real AI is disabled pending the key. Use separate private browser contexts for instructor and learner. Login details remain only in ignored `.tmp/quiz-preview-accounts.json`, using `accounts.instructor`, `accounts.learner` and `accounts.resumeLearner`. No passwords are included here. Sign in again after the QA session cleanup. This minimal QA stack does not run Realtime: refresh the learner list between roles.

Prepared class: **Owner PDF Quiz Testing**. Direct Resources URL: `http://localhost:3008/classes/6ef7b6bf-b9fa-420c-bcc8-b0039e314bda?tab=resources`. Both QA learners are enrolled. Setup metadata is in `.tmp/quiz-resource-owner-setup.json`. Sample file: `.tmp/bytequest-sample-networking.pdf`. Setup does not consume learner attempts.

1. Sign in as the QA instructor; open the prepared class's Resources tab. Upload the sample PDF with a title. Confirm progress, success, list refresh and Open/download.
2. Open Quizzes; create a supplementary quiz with title/topic (COC optional). Open AI assistant and select My Class Resource, the prepared class and the PDF. Refresh resources if it was uploaded in another tab. Set focus, difficulty, count and types.
3. After the local key is configured and live testing enabled, read and confirm the external-processing disclosure, then generate. Without a key, the button explains the configuration blocker; the simulator is not a substitute for real provider acceptance.
4. Review the generated editable drafts. Edit answers/explanations, reject inappropriate items and approve acceptable items. Use Preview without starting a learner attempt.
5. Select the prepared class in Publishing, confirm and publish. No publication reason should be requested. Check assignment and version history.
6. Sign in to the learner preview with the QA learner, open assigned quizzes, and confirm the ordinary title, controls and absence of AI-origin labels. Start, answer, leave and resume the same attempt; refresh/sign in again if desired. Submit and verify that another attempt is blocked.
7. Use `resumeLearner` separately to test an unfinished attempt. Return to the instructor Results tab and check the submitted result. Compare with a freshly manually authored, approved quiz assigned to the same class.
8. Check desktop/tablet/mobile browser widths and keyboard controls. Report issues to Codex. Only the owner can accept the UI and end-to-end behavior; nothing here marks UAT complete.

From the repository root, restart using `node scripts/quiz-preview.mjs setup`, `node scripts/quiz-preview.mjs start`, and separately `node scripts/quiz-preview.mjs learner`. `setup` does not reset existing QA data. On an existing pre-feature QA stack, `node scripts/quiz-preview.mjs migrate-resources` applies only the new targeted migration after row-hash checks. Do **not** run `seed` during UAT: it creates another fixture set and changes the account file. `test-start` and `quiz-ai-local-provider.mjs` are for automated simulation only and must not be mistaken for live AI.

## F. Changes and future release

New targeted migration: `supabase/migrations/20261112151434_resource_quiz_sources_and_request_safety.sql`, SHA-256 **CC24CCAEED3CBEE8BDDD66417B64CEFB00ECEADEA41467757575FDE56A28A671**. Applied only to isolated QA after rollback rehearsal. It adds the private-to-clients upload journal, an AI request-identity index and stricter concurrency/idempotency inside the existing `begin_ai_quiz_generation` RPC. No new SECURITY DEFINER function, learner table mutation or relaxed RLS policy was introduced. The QA application verified unchanged hashes for attempts, answers, results, quizzes, versions, items, resources and profiles.

Changed source groups:

- Dashboard: `src/app/api/classes/[classId]/resources/route.ts`, `src/app/api/instructor/quizzes/ai-draft/route.ts`, `src/components/classes/LearningResourceManager.tsx`, `src/components/quizzes/AiQuizPanel.tsx`, `QuizAuthoringWorkspace.tsx`, `src/middleware.ts`, `src/types/database.generated.ts`.
- Server libraries: `src/lib/resources/{policy.ts,upload-form.ts,pdf.ts,pdf-worker.mjs}`, `src/lib/ai/{config.ts,quiz-draft.ts,resource-source.ts,alternative-quiz-draft.ts,providers/openrouter.ts}`, `src/lib/supabase/admin.ts`.
- Runtime/build: dashboard `package.json`, `pnpm-lock.yaml`, `next.config.ts`; Node **22.13+** is required. PDF.js and its worker/polyfill dependencies are server-only and included in output tracing.
- Regression coverage: dashboard `tests/{resource-content,resource-upload-form,resource-quiz-provider,quiz-grounding}.test.ts`, `supabase/tests/resource_ai_workflow_rollback.sql`, and the extended SQL runner.
- Local tooling: `scripts/quiz-preview.mjs`, `resource-ai-workflow-tests.mjs`, `resource-upload-reconcile.mjs`, `quiz-ai-local-provider.mjs`, `quiz-ai-live-synthetic-test.mjs`, `quiz-resource-owner-setup.mjs`, `quiz-qa-end-sessions.mjs`, `fixtures/resource-pdf.mjs`.
- Flutter: only the requested unavailable-status string in `lib/data/mission_content_data.dart` and the parity regression in `test/learner_quiz_flow_test.dart`.
- Handoff: this document and `CODEX_STATE.md`. Preexisting untracked owner files and credentials remain uncommitted.

API compatibility: existing approved-activity requests remain accepted; class-resource requests add `sourceMode`, `classId`, `resourceId`, `externalConsent` and optional idempotency `requestId`. Instructor generation responses retain provider/count/status. Existing learner payloads, scoring and answer rules do not change. Additional concurrent generation requests can receive 409; completed identical retries return 200 with `reused: true`.

Before any production release, obtain owner UAT and separate explicit approval for hosted reads/backup, the exact migration batch and deployment. Verify hosted schema/function history, export a recoverable encrypted database backup and private Storage object bytes/metadata, and rehearse against a restored isolated copy. Apply the earlier single-attempt migration only if preflight confirms it is required, then this resource migration, then the compatible Node 22+ dashboard. Never replay unrelated history. Ensure OpenRouter credentials stay server-only and audit/provider privacy requirements are reviewed.

**Production blocker:** a 50 MiB multipart upload through a Vercel Function is not made viable by the local Next fix. Vercel documents a 4.5 MB request-body limit. Before release, route large uploads through a separately reviewed authenticated signed/resumable private-Storage flow, or another approved streaming server architecture; verify Linux PDF worker/native dependency packaging. No production-ready 50 MiB hosted upload claim or deployment is made. See [Vercel function limits](https://vercel.com/docs/functions/limitations) and [Next body buffering](https://nextjs.org/docs/app/api-reference/config/next-config-js/middlewareClientMaxBodySize).

Recovery: roll back application code only to a schema-compatible revision; keep journal/generation/audit rows, historical grades and the one-attempt rule. Do not restore old permissive attempt RPCs or drop claim data. Reconcile unreferenced upload jobs offline, using a dry run first. Prefer a targeted forward fix if live generations/uploads exist. No recovery procedure here authorizes a hosted write.
