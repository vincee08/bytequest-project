# Quiz workflow revision — implementation and owner acceptance

Status: **ready for owner-led manual testing** on `vince-branch`. Automated validation passed; owner acceptance is pending. No push, hosted migration or deployment is authorized.

## Plan

1. Trace existing authoring RPCs, AI grounding, assignment, learner RPCs and Flutter models.
2. Add regression coverage for reason-free atomic publication and quiz-wide single attempts.
3. Prepare one targeted additive migration; rehearse only in isolated QA. Preserve historical attempts, answers, results and versions.
4. Replace the stacked editor with Questions, Settings, Publishing, optional AI, History and Results sections. Use typed question dialogs, a non-consuming preview and unsaved-change guards.
5. Run dashboard checks/build, database lifecycle and concurrency tests, relevant Flutter compatibility checks; prepare a local-only preview.
6. Record exact results, rollout/recovery requirements and owner test steps here. No hosted changes, push or deployment without owner approval.

## Existing contract

- Instructor-only RPCs create quiz/version drafts, upsert questions, review, soft-remove, publish, archive and assign. RLS restricts instructor reads to owned quizzes/classes. AI uses `/api/instructor/quizzes/ai-draft`, approved COC/activity/source context and OpenRouter; generated items remain drafts.
- Four question types: multiple choice and scenario use 2–6 choices with exact choice grading; identification and true/false use trimmed, case-insensitive equality. Multiple accepted identification answers are not supported by the existing contract and will not be invented.
- Flutter calls the learner list/start/save/submit/result RPCs directly. A completed attempt has exactly one immutable `quiz_results` row; submission locks the attempt and repeated submission returns that result.
- Existing limits are assignment-scoped and may be unlimited. A new private claim keyed by learner + stable quiz ID will enforce the rule across classes, assignments and versions. Historical duplicates remain untouched; any prior submitted attempt exhausts the quiz.
- Supplementary quiz results remain distinct from accredited competency assessments and instructor release.

## Design references

UI/UX Pro Max: progressive disclosure, visible labels, inline errors, keyboard dialogs, responsive tabs and retained form state. Existing navy/blue tokens and Radix controls are reused. Python is unavailable, so the skill's local quick references are used without installing software. Superpowers was not found in the installed skill locations; the plan and regression-first workflow above supply the implementation process.

Database references: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html). Existing definer RPCs retain role/ownership checks; new orchestration/trigger functions use invoker security.

## A. Implementation

- `src/app/quizzes/page.tsx`, `QuizLibrary.tsx`, `CreateQuizForm.tsx`: searchable/filterable compact library, one Create action, private draft creation with title/topic and optional COC, advanced optional description/instructions, inline validation and retained values after failures.
- `src/app/quizzes/[id]/page.tsx`, `QuizAuthoringWorkspace.tsx`: Questions, Settings, Publishing, AI assistant, History and Results tabs. Header shows title, status, COC, question count, save state and primary actions. Inactive tabs retain form state. Historical version links load the corresponding immutable questions. Instructor Results includes scores from earlier versions and classes under existing RLS.
- `QuestionEditor.tsx`, `QuizPreview.tsx`, `src/lib/quizzes/authoring.ts`: question dialogs with separate choice fields/correct-option radios, true/false radios, identification answer rules, scenario choice grading, optional explanations, inline errors, failed-save recovery, explicit discard confirmation, page-unload/link protection and an independent preview that never invokes learner start/grading.
- `AiQuizPanel.tsx`: moves the existing OpenRouter authoring/generation/alternative controls into an optional tab. Approved context and draft-only review rules remain. No AI endpoint/provider contract was replaced.
- `src/app/quizzes/error.tsx`: recoverable quiz-data loading failures instead of an empty library or false missing-quiz result.
- `src/types/database.generated.ts`: optional legacy publication reason and typed orchestration/reorder RPCs. No public table shape changed.
- Flutter changes are restricted to assigned-quiz status text, restricted-access state and a disabled submitted briefing action, plus the corresponding regression. No mission screen, evaluation, progression quiz, simulator or official instructor-release behavior changed.
- Tests/tooling: `tests/quiz-authoring.test.ts`, `supabase/tests/quiz_single_attempt_rollback.sql`, `scripts/quiz-workflow-{db,api,browser}-tests.mjs`, `scripts/fixtures/quiz_legacy_attempts.sql`, `scripts/quiz-preview.mjs`, `scripts/quiz-release-preflight.sql`.

## B. Business rules and compatibility

Migration: `supabase/migrations/20261112111620_quiz_publishing_and_single_attempt.sql`.

Reviewed source SHA-256: `08FEEBBC1E095BFC3C9C49F8B4AFE404D8F8EF87F468CAD77C45977D69F94701`.

1. `publish_quiz_version(uuid,text)` retains its identity; its second argument defaults to NULL. Blank/omitted reasons are accepted and stay NULL in the audit. Older clients may still supply a real reason. Archive, removal and rejection reasons remain required.
2. `publish_and_assign_quiz` is a new SECURITY INVOKER transaction around existing scoped publication/assignment RPCs. A bad class rolls back the entire request. Duplicate target IDs and retry/concurrent assignment requests return existing active assignments without duplicate audit events. Assigned versions remain separate records from publication.
3. The new private `quiz_attempt_claims` primary key is `(learner_id, quiz_id)`, where `quiz_id` is the stable quiz identity shared by all versions. Its unique attempt reference, INSERT trigger and start transaction/advisory lock prevent duplicate starts across assignments, classes, devices and versions. Authenticated clients cannot read/write this private table or directly insert attempts. Existing public write grants/RLS are preserved.
4. Backfill preserves every historical row. If a learner has completed attempts, the earliest completed attempt is canonical; otherwise the earliest submitted attempt; otherwise the oldest unfinished attempt. Historical duplicates/grades are neither deleted nor renumbered. Other old unfinished records remain retained but cannot be submitted as extra attempts.
5. Start/resume returns the canonical unfinished attempt and saved answers. Republishing preserves access to its original immutable question version while its original assignment, class and enrollment remain available. The learner list shows one row per quiz and retains the canonical historical result. Revoked enrollment, closed/expired assignments or archived quizzes restrict further work.
6. Save/submit require the canonical attempt and current class access. Completed submission retries still return the original result, including after access changes. The existing attempt row lock, unique result-per-attempt constraint and append-only results protect concurrent grading. Answer comparisons remain unchanged.
7. Reordering uses the existing audited upsert API inside one invoker transaction. Reserved/removed slots and question codes survive; changed order returns draft questions to review. Published history remains immutable, with review/removal serialized against publication.

The new dashboard requires this migration before its new RPCs can work. Existing Flutter RPC names and response fields remain compatible. Instructor-assigned supplementary quizzes are the scope of this single-attempt rule; separate COC progression quizzes and accredited competency assessments are unchanged.

## C. Automated verification

Executed successfully so far:

- TypeScript and Next lint; production build against isolated public configuration.
- Authoring/validation and existing browser-independent dashboard regressions; OpenRouter mock provider tests (8), supplementary progression quiz tests (5). The first combined invocation of the progression tests omitted `--conditions=react-server`; rerunning with that required condition passed. This was a harness invocation failure, not a product change.
- Isolated rollback migration/lifecycle checks: new quiz rule suite, existing learner quiz suite, existing foundation instructor finalization/release suite, and historical duplicate/result/assignment hash preservation.
- Authenticated isolated API: 10 groups covering all four item types, editing/review/reorder, atomic publication without a reason, class/RLS isolation, 16 concurrent starts across classes returning one ID, relogin/second-device saved-answer resume, 12 concurrent submissions producing one grade, republication, retired-version resume, revoked enrollment and exactly-once publication audit.
- Browser automation: actual login/authoring/publishing, previous-version learner result display, four editors, failed-save retention/retry, discard guard, reorder/removal, mandatory rejection notes, approvals, preview without a start request, settings retention, history/results, native keyboard tabs and 320/375/768/1440 layouts. Visual review found a squeezed phone header despite no horizontal overflow; the layout was corrected and a minimum title-width assertion added.
- Fresh isolated stack applied all repository migrations, including this migration. Database lint reported no schema errors; no public/private application table lacked RLS; new public helpers are invoker functions.
- Final Flutter gates: dependency resolution exit 0; analyzer exit 0 with **0 errors, 0 warnings and 217 existing infos**; **450/450 tests**, including the submitted-briefing regression; debug APK exit 0. The focused quiz suite also passed 8/8. No APK was installed and no device or owner testing is claimed.

Final results: **30/30 dashboard unit regressions**, **10 authenticated API groups**, **8 browser workflow groups**, **4 SQL migration/lifecycle/preservation groups**, clean database lint, TypeScript/lint/production build, and all Flutter gates passed. The final browser rerun includes the phone header-width assertion and successful repeat runs with unique fixture titles. Initial test-fixture/selector failures were corrected and rerun; there are no unresolved failures in these executed gates. Both preview URLs returned HTTP 200 after restarting the final source/build. Automated screenshots under ignored `.tmp/quiz-screenshots/` were visually inspected, including the corrected phone header and 320px editor.

The original populated local Supabase and hosted project were not changed. A dedicated `BQQuizQA20261112` stack and a separate cloned synthetic QA database were used. Final function refinements were rehearsed transactionally and refreshed only in the dedicated preview stack.

## D. Owner-led manual testing

Dashboard: **http://127.0.0.1:3008/quizzes**

Learner Flutter web preview: **http://127.0.0.1:3009**

These are local URLs on this Windows machine. They are not public staging deployments. Open the two previews in a private browser window for an independent testing session. The original hosted app/accounts and the original local stack are independent.

Disposable local login details are in the ignored `.tmp/quiz-preview-accounts.json` file. Use its `instructor` account on the dashboard and `learner`/`resumeLearner` on Flutter; `outsider` is deliberately unenrolled. Passwords and API keys are not included in this report. All fixtures use `@bytequest.invalid` addresses. Do not paste hosted credentials into these test sessions.

From the repository root, restart the prepared environment if needed:

```powershell
node scripts/quiz-preview.mjs setup
node scripts/quiz-preview.mjs start
# In another terminal:
node scripts/quiz-preview.mjs learner
```

For a fresh disposable fixture set, `node scripts/quiz-preview.mjs seed` creates local-only QA accounts/classes and executes API regression groups. It updates the ignored account file; existing fixtures/history are retained. Do not rerun seed during an owner session without recording that the login details change. Stop the owned dashboard server before `node scripts/quiz-preview.mjs build`, then restart it. The launcher discovers the installed Supabase CLI or accepts `BQ_SUPABASE_CLI`; dependencies must already be installed. It never runs a hosted/linked operation or prints keys.

Owner checklist (all pending owner confirmation):

1. Create a **new** quiz with a short title/topic. Verify optional COC/description/instructions and the immediate Questions screen. Existing API-test quizzes already contain consumed attempts; use the new quiz for the first-attempt journey.
2. Add multiple choice, true/false, identification and scenario questions. Select correct answers, edit, cancel a changed edit, save and reorder. Check separate fields, inline errors and keyboard navigation.
3. Try publishing with unreviewed questions. Review content/answers, reject one with a note, edit/review it and approve every active question. Remove a draft with an explicit removal reason.
4. Preview questions. Verify no learner attempt appears in Results. Select QA Class A and/or B, confirm publication **without any reason field**, and verify assignment badges/history.
5. In Flutter web, complete onboarding if shown, sign in as the disposable `learner`, open assigned Quizzes and find the new quiz: **Not started — 1 attempt available**.
6. Start and save an answer. Leave, refresh, sign out/in or use another browser session with the same learner. Continue the same attempt and verify saved answers. The prepared `resumeLearner` also has an unfinished API-test quiz available for a separate resume check.
7. Finish and submit once. Verify **Submitted — Attempt used**, result visibility and no additional attempt. Opening the quiz through another class or republishing another version must not grant a new attempt.
8. Return to the instructor Results tab and verify the learner's result. Inspect prior-version questions, class assignments and historical results. Test the archive confirmation/reason on a disposable quiz only.
9. Check desktop/tablet/phone widths and personal usability. Report the exact screen, role, action and observed result. Only the owner can confirm final acceptance.

Known test-environment limits: the minimal local stack excludes Realtime and Storage, so refresh/reopen lists when switching roles; no production realtime regression is claimed. Live OpenRouter calls are deliberately disabled in this local preview; manual authoring remains fully usable and provider behavior is covered with mocks. Live grounded AI acceptance requires approved source content plus a separately configured server credential. Flutter web does not replace physical Android/TalkBack acceptance. The ordinary debug APK is a build-validation artifact, not an authorized hosted-testing release for this migration.

## E. Production preparation and approval

No production write/deployment/push has occurred. Owner manual acceptance and explicit release approval remain required.

1. Run `scripts/quiz-release-preflight.sql` read-only against the intended target. Compare the eight existing function bodies/ACLs, required quiz schema, migration history and aggregate historical duplicates. Hosted history diverges from repository history; **do not replay unrelated migrations or run an unreviewed `db push --include-all`**.
2. Take a **fresh encrypted full logical backup plus roles and affected-data hashes**, verify restore in isolated QA and protect it outside Git. Preserve quizzes, versions/items/reviews, assignments, attempts, answers, immutable results, audit events, Auth/profile identities and migration history. The earlier Nov 11 backup is historical evidence, not a substitute for a current release backup.
3. Obtain owner approval for the exact targeted migration/hash and reviewed existing-function replacements. Apply only this transaction; its five-second lock timeout fails without partial schema/data changes. Verify claim backfill, RLS/ACLs, grants and PostgREST schema reload.
4. Deploy the dashboard only after the database contract is verified. Older clients remain compatible; then distribute the Flutter status update if accepted. Production public URLs/keys must be the correct hosted project, with all server secrets kept server-only.
5. Run scoped authenticated hosted smoke with separately approved test identities/data. Check reason-free audit, assignment access, resume, concurrent start/submission protection and instructor results before declaring release accepted.
6. Prefer forward recovery. A pre-commit migration failure rolls back automatically. After successful use, keep the claim table/unique key/triggers and history; reverting the dashboard is possible, but removing one-attempt enforcement would permit retakes. Any database restore or behavior rollback needs separate owner approval and reconciliation of post-backup learner writes. No reset/delete of learner records is part of this release.
