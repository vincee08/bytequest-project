# Learner name/email enrollment — local testing handoff

Implemented on `vince-branch`. The owner has approved the previous Manual Quiz and AI Quiz features. **Enrollment acceptance is pending.** These revisions remain local for the owner's later combined push/deployment; no production synchronization is authorized.

## 1. Enrollment interface

Classes → class → Learners now has a labelled name/email combobox instead of an email-only form. It waits 300 ms after typing, requires two characters, and loads 15 profiles per page. Results show the actual registered full name, email, initials and status in this class. Duplicate display names remain separate options identified by stable learner UUIDs. Selecting a result displays a confirmation; editing/clearing it removes that selection. Text alone cannot enroll an account.

Loading, empty results, connection errors, retry, explicit success, pending/duplicate-click protection, bounded request waits and cancellation of stale searches are implemented. Arrow keys/Enter select; Escape closes; Tab preserves normal focus navigation. Controls use the existing ByteQuest tokens and at least 44 px touch targets. Narrow layouts wrap names/emails instead of overflowing. Successful enrollment refreshes membership history and the active count.

## 2. Directory and API

The actual full Learners Page is the admin `/learners` route, backed by `getAdminGovernanceData()` → `public.profiles`, filtered to the learner role. The instructor's Learners link instead opens `/progress`, which is enrollment-scoped monitoring, not an unassigned registration directory. Restricting search to that population would prevent first-time enrollment.

The owner explicitly selected **all active registered learner profiles** after this distinction was explained. `GET /api/classes/[classId]/learners?q=...&page=...` therefore queries that same authoritative profiles population with `role=learner` and `status=active`. It does not query Supabase Auth users, create profiles, expose other roles or change either existing Learners page.

Before any directory read, the endpoint verifies the authenticated session, active instructor profile and ownership of the active target class. The profile query uses the existing **server-only administrative client**, because ordinary instructor profile RLS intentionally excludes unassigned learners. This is the narrowly authorized name/email discovery endpoint; general profile RLS remains unchanged and its denial was tested directly. The response contains only `id`, `fullName`, `email`, the selected class's enrollment state, and a next-page flag. Other-class names, memberships, activity, account metadata and credentials are not returned. Responses are `private, no-store`.

Search is a case-insensitive literal substring match against name or email, with quoted PostgREST values and escaped LIKE `%`/`_` characters. Commas, quotes, parentheses, apostrophes and backslashes were tested. Search operators/asterisks/control characters are rejected. Queries are bounded to 100 characters and page 0–100; larger result sets should use a narrower name/email. Ordering by name then UUID keeps duplicate names deterministic. Pagination fetches one extra row to detect another page rather than loading the entire directory into the browser.

## 3. Registration and mobile relationship

The existing flow works without a profile-contract change:

`SignupScreen → AuthService.signUp(fullName,email,password) → Supabase Auth → handle_new_user trigger → profiles.user_id → registered Learners directory → class enrollment`.

The trigger assigns learner/active itself and persists Auth ID, email and signup full-name metadata. The profile's unique user identity prevents duplicate profiles. Flutter verifies provisioning when signup returns a session; confirmation-pending signup follows its existing confirmation flow. `ProfileService` edits only its existing allowlisted fields, including full name, and never creates an identity or assigns a role. Email is persisted at signup and is not an editable field in the current profile workflow. No broken provisioning or name synchronization was found. QA tests exercised ordinary signup, one profile per identity, profile-name edits and immediate directory search.

**Environment distinction:** normal Flutter `.env` targets hosted Supabase. The running local learner preview was positively verified to use `.tmp/quiz-local-web-defines.json` with `BQ_SUPABASE_URL=http://127.0.0.1:58921`; the dashboard build/runtime uses the same isolated QA API. This does not retarget an existing hosted Android APK. Use the QA learner web preview for this acceptance test. Hosted accounts will not appear in the isolated directory. No hosted account or configuration was modified.

## 4. Authorization, enrollment and data

`POST /api/classes/[classId]/learners` accepts only `{learnerId: UUID}`. It authenticates and checks the class again, then calls the existing `enroll_learner` RPC **as the instructor**, not the administrative client. The RPC validates active class ownership and active learner role/status again. Its insert and audit event are transactional. The existing partial unique index on `(class_id,learner_id)` for active memberships enforces concurrent duplicate protection. Ten parallel requests produced one membership; others returned the specific duplicate response.

- Not enrolled: selectable/enrollable, including someone in another class.
- Already active: clearly labelled; enrollment button disabled. A duplicate backend request returns 409.
- Previously removed: labelled with retained history. Re-enrollment creates a new membership UUID, preserving the old row and its reason/timestamps exactly.
- Inactive/non-learner account: excluded from search; a stale/forged selection is rejected server-side.
- Wrong instructor, learner caller or archived class: denied before directory disclosure/enrollment.

**No migration, policy, trigger, function or constraint change is required for this revision.** No learner record was deleted or reset. Historical quiz versions/results and the existing single-attempt rule are untouched. The previous pending release migrations retain their separate approval requirements.

## 5. Automated evidence

Executed results:

| Check | Result |
| --- | --- |
| TypeScript / ESLint | Passed; final production build repeats both checks |
| Next production build | Passed again after the final trailing-whitespace correction |
| Node unit/server tests | 47/47 passed, including five new search/selection/state/error regressions |
| Component/prerender tests | 6/6 passed, including the new labelled-selector/explicit-selection test |
| Authenticated integration | Full 11-group run passed: signup, name/email/case/duplicate names, literal filter safety, deterministic pages, role/class/RLS denials, persistence, retained history, concurrent duplicates, account eligibility, archived classes, browser behavior and learner visibility |
| Final browser regression | Seven focused groups passed against the final build, including trailing whitespace, dropdown pagination/focus, loading and aborted stale searches |
| Owner fixture/mobile query | Separate welcome-PDF upload and enrolled-only Flutter resource query passed |
| PostgreSQL | New `learner_enrollment_rollback.sql` passed with actual authenticated-role RLS/lifecycle checks, privileged audit verification and rollback |
| Relevant Flutter regressions | 5/5 passed across auth provisioning, signup feedback and profile setup; no Flutter source/contract change |

Initial harness failures were corrected: the audit assertion originally ran as an instructor despite intentionally admin-only audit read policy; the metric assertion expected whitespace in aggregated DOM text; standalone TSX rendering required an explicit React import. The corresponding checks passed after correction. No authorization policy was loosened to make tests pass. The final edge correction ensures adding trailing whitespace cannot erase otherwise valid matches.

The new tests intentionally create disposable QA registrations/classes/memberships and retain them. They do not create users because of search text. No live AI/provider request is part of this suite. Exact counts/hashes of all **14 quiz attempts, 9 quiz results and 38 quiz answers** match the pre-test snapshot; both prior targeted migration file hashes also match their frozen handoffs. A private scan of 115 final browser assets found no OpenRouter key or hosted project reference, and confirmed the dedicated QA API URL. Both previews returned HTTP 200. Earlier SQL/mobile/quiz tests are not represented here as newly executed checks. Android builds/device testing and owner acceptance are not claimed.

## 6. Owner manual testing

Dashboard: **http://localhost:3008**. Learner preview: **http://127.0.0.1:3009**. Use separate browser contexts for the two roles.

Prepared class: **http://localhost:3008/classes/5ec3eb0f-848b-4a38-b0fd-786352d96f6b?tab=learners**. Search name: **Enrollment QA 10e9f791 Dela Cruz**.

The ignored `.tmp/quiz-preview-accounts.json` retains the existing `accounts.instructor` credentials. The ignored `.tmp/learner-enrollment-qa.json` contains the prepared class URL, a searchable synthetic full name and two registered QA learner credentials. Do not paste either file into chat or commit it. Both learners share a display name intentionally; email distinguishes them. `learners[0]` is already active in the prepared class, while `learners[1]` is available to enroll.

The existing Flutter Classes tab is populated by assigned activities/shared resources, so a bare empty membership does not create a visible class card. A tiny synthetic **Enrollment QA welcome** PDF has been uploaded to this QA class using the existing authorized upload route. Its metadata/classes join is visible to the enrolled QA learner and hidden from the unenrolled peer, using the same query as `LearningResourceService`. This prepares the existing learner interface without modifying missions or consuming quiz attempts.

1. Sign in at the dashboard as the QA instructor. Open the `classUrl` in `.tmp/learner-enrollment-qa.json` and the Learners tab.
2. Search the fixture's `fullName`; confirm two distinct learner emails. Try partial and differently capitalized name text.
3. Clear the field and search the second learner's email (`learners[1].email`). Select the actual result and check the selected name/email confirmation.
4. Click Enroll learner. Confirm the pending state, success, membership row and active learner count changing from one to two.
5. Search/select that learner again. Confirm Already enrolled and a disabled enrollment action. The member count should remain two.
6. Optionally remove only this synthetic membership using the existing required reason, then search again. Confirm Previously enrolled, re-enroll and verify both old and new history rows with one active membership.
7. In the learner preview, sign in with `learners[1]` from the private fixture, open Missions → Classes, refresh and check the enrolled class/welcome resource. The minimal QA stack has no Realtime service, so refresh when switching roles.
8. Check keyboard selection and desktop/tablet/mobile widths. Report issues before accepting enrollment. The overall dashboard remains open for the remaining revisions.

Safe restart from the repository root: `node scripts/quiz-preview.mjs ai-start`; the `ai-start` variant preserves the privately configured, already approved quiz AI setup. In another terminal use `node scripts/quiz-preview.mjs learner` only if the learner preview is stopped. Do not run `seed`, reset databases, replay migrations or start against hosted defaults during UAT.

## 7. Files and release boundary

- `ByteQuest-Web-Dashboard/src/components/classes/EnrollLearnerForm.tsx`: new selector and enrollment UX.
- `ByteQuest-Web-Dashboard/src/components/classes/ClassManagementForms.tsx`: re-exports the replacement; other management forms retained.
- `ByteQuest-Web-Dashboard/src/app/classes/[id]/page.tsx`: enrollment heading/help copy only.
- `ByteQuest-Web-Dashboard/src/app/api/classes/[classId]/learners/route.ts`: guarded directory search and authenticated enrollment.
- `ByteQuest-Web-Dashboard/src/lib/learners/enrollment.ts`: validated search/UUID contract, fixed filter grammar, states and safe errors.
- `ByteQuest-Web-Dashboard/tests/learner-enrollment.test.ts` and `learner-enrollment-form.test.tsx`: focused unit/component coverage.
- `scripts/learner-enrollment-tests.mjs` and `scripts/quiz-preview.mjs`: isolated API/browser runner and launcher command.
- `supabase/tests/learner_enrollment_rollback.sql`: rollback-only lifecycle/RLS verification.
- This handoff and `CODEX_STATE.md`.

No dependency, Flutter source or database migration changed. Search uses existing server-side Supabase configuration. Local commits are permitted; **no Git push, Vercel deployment, hosted migration or combined production release** is authorized. Keep previous approved revisions intact and wait for the owner's remaining revisions and explicit release approval.
