# ByteQuest implementation status audit

Date: 2026-09-15 (Asia/Manila)<br>
Branch: `new` (`origin/main` unchanged)<br>
Scope: Flutter learner app, Next.js Instructor/Admin dashboard, Supabase Auth/PostgreSQL/Storage/Realtime, migrations, scripts, and current connected project.

This is the required pre-code-change status report. "Working" is supported by source inspection and existing automated or live evidence. It does not mean every screen has been manually exercised in this session. No production migration is authorized by this report.

## Architecture and current evidence

- Flutter/Dart uses Provider, a typed reusable 2D simulation runtime, learner-owned practice evidence, assigned authoritative attempts, local pause/resume snapshots, and Supabase-backed learner services.
- Next.js 15/TypeScript has distinct Instructor and Admin route families, server-side role guards, Supabase SSR sessions, route handlers, and an OpenRouter Instructor-only quiz draft assistant.
- Supabase PostgreSQL is the assessment authority. Versioned sources, activities, rubrics, actions, criterion results, append-only score revisions, releases, class membership, resources, quiz lifecycle, audit, and RLS are already modeled. Flutter does not author competency or release results.
- Read-only connected-project inventory confirmed 4 COC modules, 20 missions, 20 activity versions, 20 rubric versions, 98 rubric criteria, 9 classes, 9 memberships, 21 assignments, 41 attempts, 64 score revisions, 22 releases, 2 learning resources, and no current COC bypass or quiz records. These counts demonstrate installed data, not a completed UI journey.
- Official source files and traceability are present under `docs/reference/tesda_sources/`, `docs/MISSION_TESDA_ALIGNMENT_AUDIT.md`, and `docs/TESDA_SOURCE_VALIDATION_STATUS.md`. The official amended CSS NC II Training Regulations and current SAG identify the four core competencies, but do not provide a numeric ByteQuest passing cutoff or XP formula. ByteQuest operational `all_required` evidence is separate from formal TESDA certification.

## Requirement-by-requirement classification

| Requirement | Classification | Current implementation and remaining proof/defect |
|---|---|---|
| Existing architecture and dashboard audit | Already implemented and working | Separate Flutter learner and Next.js Instructor/Admin apps; Supabase shared authority, source-level role guards and 44 ordered migrations. Current authenticated screen-by-screen manual QA remains unrecorded. |
| Official CSS NC II competency/COC alignment | Already implemented and working | Four official unit codes, 20 versioned mission identities and 98 criteria are traced to local official references; project scenario rules are labelled operational. |
| TESDA grading, scores, points, and evidence methods | Partially implemented | All-required criterion evaluation, raw/max/percentage/released state, written quiz and practical/scenario workflows exist. No numeric TESDA threshold is asserted; instructor numeric/criterion correction lacks a reliable UI and the RPC does not enforce aggregate consistency. Physical workmanship and assessor judgment are outside the simulator. |
| Instructor/Admin role separation | Already implemented and working | Distinct route/navigation guards, RLS/RPC boundaries, Instructor-owned classes, Admin account/system scope and negative tests. |
| External training vs internal platform concerns | Partially implemented | Teaching/review/resource and Admin security/settings/audit areas are separated. No dedicated concern intake, assignment, status, or resolution workflow was identified. |
| COC1–4 Instructor bypass | Already implemented and working | `grant_coc_bypass` is owned-class, learner-scoped, reasoned, audit-backed and access-only. There are no current live bypass rows, so this session has not exercised a new bypass. |
| Practical demonstration zoom/layout | Already implemented and working | Shared scene has `InteractiveViewer`, fit/zoom and object picker, accessible alternatives and assessment answer withholding. Physical Android/visual hierarchy walkthrough remains unverified. |
| Scenario interaction and optional video | Partially implemented | Multi-phase inspect/connect/configure/decision/test/observe/troubleshoot interactions are present and no mission is drag-only. Text content works; signed video resource access exists, but embedded scenario-video execution is not demonstrated. |
| Instructor score editing and review | Implemented but incorrect | `finalize_attempt` appends adjusted/final revisions with actor and reason. The current form only exposes outcome change and forwards unchanged provisional totals/criterion values. The RPC checks nonnegative total and percentage bounds but not `total <= max`, `percentage = total/max`, criterion sum, required-criterion outcome consistency, or immutable rubric maximum. |
| AI quiz generation | Partially implemented | Existing server-only OpenRouter provider validates grounded JSON drafts, role/rate controls and Instructor review/publish gating. Individual draft edit/remove is implemented; targeted single-question regeneration and current-project end-to-end UI proof remain unverified. Current project has no quiz records. Do not add a second provider. |
| LMS classes, enrollment, assignment, resources and monitoring | Already implemented and working | Owned-class RPCs, historical memberships, class assignments, private Storage uploads, signed learner resource access, learner path, real analytics/reporting. Manual cross-client walkthrough remains. |
| Student deactivation/account governance | Already implemented and working | Instructor can deactivate a learner only within owned class scope; Admin role/status and safeguarded empty-account removal have server/database checks and audits. Existing academic history is preserved. |
| Database/API integrity and Realtime | Already implemented and working | Existing FKs, RLS, idempotent attempt/action/release contracts and scoped invalidation are present. New score-correction checks must preserve the existing RPC signature and release contract. |
| Regression/runtime QA | Partially implemented | Existing Flutter, Web, authenticated lifecycle and rollback suites exist. Android SDK/device/TalkBack, human browser breakpoints, local Docker PostgreSQL rollback, signed release and a fresh current-project authenticated full journey are pending. |
| Backup/restore and operational issue handling | Not implemented | No verified isolated backup+restore or dedicated external/internal concern ticket workflow was found. These require an operational design and validation environment before claiming completion. |

## First controlled remediation

1. Preserve the existing Supabase `finalize_attempt` signature and score revision/release table identities.
2. Expose only rubric-supported Instructor criterion correction before finalization, with reason, original versus revised values, and honest outcome/percentage preview. No arbitrary TESDA score or client-authoritative final evaluation.
3. Add backend validation of criterion values and aggregate totals before a revision can be appended, while preserving the existing reasoned Instructor outcome override. Test negative cases in the rollback-only local lifecycle suite; do not apply to the connected project without passing isolated migration/rollback validation.
4. Run affected Web tests and the full Flutter/Web gates, then update `CODEX_STATE.md` and this report with actual results.

## Preservation boundary

Do not replace working mission routes, authentication/RLS, class tables, Storage contract, OpenRouter provider, approved TESDA source identities, operational rubric rules, learner evidence transport, Instructor-only release, or current visual design. The untracked dashboard `package-lock.json` belongs to the existing worktree and remains untouched.

## Prioritized issues and controlled change record

| Issue ID | Component | Description | Severity | Root cause | Proposed fix / current status |
|---|---|---|---|---|---|
| BUG-001 | Instructor dashboard | Criterion score cannot be corrected before finalization | High | Review form forwards unchanged provisional criterion values and numeric aggregates | Criterion-level binary-rubric editor, derived preview, original/revised history, mandatory reason. Implemented; unit/type/lint verified, authenticated UI path still unverified. |
| BUG-002 | Supabase evaluation | Direct `finalize_attempt` request can send mismatched criterion totals or percentage | High | RPC checks only nonnegative/range values, not rubric and aggregate equivalence | Add SECURITY INVOKER insert trigger for Instructor revisions and rollback negative tests. Migration written but not applied or DB-verified. |
| BUG-003 | Assessment lifecycle | A mistake found after Instructor finalization/release cannot be corrected through the current workflow | High | `finalize_attempt` accepts only `evaluated` attempts; no controlled correction/re-release operation updates the current learner projection | Design an audited, reasoned replacement revision and release transition with Instructor scope and rollback/idempotency tests. Unresolved; no new elevated RPC added without isolated review. |
| GAP-003 | AI authoring | No targeted per-question regeneration workflow in the pre-change audit | Medium | Existing generation API drafts a batch; UI edits/removes individual drafts but had no single-item action | Added a per-item grounded one-question alternative action that keeps the original until review. Implemented; focused test/type/lint verified, authenticated AI flow still unverified. |
| GAP-004 | Instructor/Admin concerns | No dedicated intake/assignment/resolution record for external vs internal issues | Medium | Current route separation covers teaching vs system administration, not a case-management workflow | Define minimal role-scoped record/API with audit and retention in an isolated DB environment. Unresolved. |
| QA-005 | Android validation | APK/Android device launch unavailable | High validation blocker | Android SDK/device absent on this machine | Install/configure Android SDK and run device matrix. Blocked by environment, not a diagnosed code bug. |
| QA-006 | Database validation | Rollback lifecycle and migration application unavailable | High validation blocker | Local PostgreSQL `127.0.0.1:57322` refused connection; Docker/local stack unavailable | Start disposable Supabase stack and run rollback suite before any connected-project migration. Blocked by environment. |

| Issue ID | Fix implemented | Files changed | Verification | Status |
|---|---|---|---|---|
| BUG-001 | Approved binary criterion correction and reasoned review preview; preserve original evaluation in history | `AttemptReviewActions.tsx`, attempt detail page, `criterion-adjustment.ts`, focused test | TypeScript 0 errors, ESLint 0 warnings/errors, focused test 3/3, Next.js build and dev startup pass | Implemented; authenticated score-edit/release NOT TESTED |
| BUG-002 | Additive Instructor score-revision consistency trigger and rollback negative cases; lifecycle fixture updated to use valid aggregate | New SQL migration, rollback test, COC2 UAT script | UAT script syntax pass; `supabase test db` fails before execution at local DB connection | Unresolved until isolated DB PASS and migration applied |
| GAP-003 | Separate single-question alternative via the existing grounded OpenRouter route, original draft retained | `QuizAuthoringWorkspace.tsx`, `alternative-quiz-draft.ts`, focused test | Focused test 2/2, TypeScript, ESLint, and production build pass | Implemented; authenticated AI generation NOT TESTED |

The connected project's existing assessment rows were inventoried read-only. No schema/data migration was applied to that project. The existing `finalize_attempt` signature, RLS, immutable `criterion_results`, append-only revision history, Instructor finalization, and Instructor-only result release remain unchanged.

## Validation and exact local run configuration

| Check | Result | Evidence |
|---|---|---|
| Web TypeScript / lint / production build | PASS | 0 TypeScript errors, 0 ESLint warnings/errors, Next.js 15.5.24 build generated all 23 static pages. |
| Web configured unit contracts | PASS | Analytics 4/4, CSV 2/2, middleware 1/1, metric strip 3/3, OpenRouter provider 6/6, new focused corrections/alternative tests 5/5. |
| Web runtime / unauthenticated boundary | PASS | `http://127.0.0.1:3000/login` 200; `/` 307 to login; protected report API 403 without HTML redirect. |
| Flutter dependencies / analyzer / tests | PASS | `flutter pub get` resolved; analyzer 0 errors with 202 info-level modernization notices; 242/242 tests passed. |
| Flutter Chrome preview | PASS | `flutter run -d chrome --web-port 8082` launched, Dart main ran, Supabase client initialized, and app entry GET returned 200. This is not Android-device validation. |
| Android debug APK/device | BLOCKED | `flutter build apk --debug` failed: `No Android SDK found`; no Android target in `flutter devices`. |
| Connected-project read-only table inventory | PASS | Existing COC/content/class/attempt/revision/release rows were read without mutation. This does not prove an authenticated workflow. |
| New migration rollback / connected-project application | BLOCKED | `supabase test db` failed before tests at `ECONNREFUSED 127.0.0.1:57322`; the migration was not applied. |
| Instructor score edit/release, AI alternative, class/file, bypass, and cross-client authenticated workflows | NOT TESTED | No disposable isolated DB or verified test credentials/session were used for new end-to-end writes. |

Local run: from `ByteQuest-Web-Dashboard`, use `npx --yes pnpm@9.15.9 install --frozen-lockfile` and `npx --yes pnpm@9.15.9 dev --hostname 127.0.0.1 --port 3000`. From `ByteQuest-Mobile-App`, use `C:\Users\HP\Tools\flutter\bin\flutter.bat pub get`, inspect `flutter devices`, and run `C:\Users\HP\Tools\flutter\bin\flutter.bat run -d chrome --web-port 8082` for the available preview. For Android, configure the SDK first and use an actual listed device ID. The clients need their existing ignored `.env.local` / `.env` Supabase configuration; never commit those files. To validate the SQL change, start a disposable local Supabase/PostgreSQL stack with Docker and run `npx --yes supabase@2.117.0 test db` before proposing any connected-project migration application.
