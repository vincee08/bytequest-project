# ByteQuest — Codex Handoff State

> Read this file with `AGENTS.md`, `README.md`, and `bytequest.md` before changing the repository.

## Current continuation - 2026-11-12 spacious technical workspaces

- Implemented the owner's authorized Flutter workspace UI improvements on `vince-branch` for all 20 production practice routes. Added a shared constraint-based workspace/task layout, compact guidance and action rows, safe full-guide sheets, expandable task controls, and a landscape sidebar whose mission chrome scrolls with its tools. Retained form and canvas subtrees through panel resizing/rotation. Moved revision navigation after actual task controls. The installed UI/UX Pro Max reference and its Flutter guidance informed the implementation.
- Enlarged scene targets and changed placement/connection presentation from four cramped columns to one wide source/destination pair per row. The existing resolved rectangles continue to drive painting, connections, hit-testing, transformed drops, and auto-scrolling. Tool buttons wrap with 8 dp gaps; feedback sits outside the canvas and expires after five seconds, with its reason retained in the task panel. Simulation identities, answers, phase/evidence contracts, reducers, completion/scoring, persistence, COC timer rules, and instructor release are unchanged. No Supabase, migration, dashboard product, or environment file was changed.
- Font-matched timed-screen measurements with 24 dp system insets: COC1 M2 canvas at 360x800 increased from 358x92.5 to 358x311.8 dp; at 320x568 the previous zero-height/overflow canvas is now 318x125 dp; at 640x360 it increased from 381.4x14 to 357x202 dp. Placement sources at 360 dp grew from approximately 71.6x72 to 150.4x112 dp. Full component list, measurement table, 20-row coverage matrix, limitations, and exact owner test screens: `ByteQuest-Mobile-App/docs/technical_workspace_ui_2026-11-12.md`.
- Final validation PASS: dependency resolution; analyzer **0 errors / 0 warnings / 217 existing infos**; **449/449 Flutter tests**, including all 20 touch work orders and all 115 phases at compact portrait/landscape with doubled text; **12/12** focused layout tests with real-font captures; debug APK. New tests cover five phone sizes (including 568x320), timed practice, safe areas/cutouts, doubled text, scrolling/closing the guide, keyboard, draft/camera retention during rotation, a real drop after resizing, and non-obstructing feedback expiry. Existing zoom/pan, offscreen drag, cable, orientation, identification, evidence, resume, and review regressions passed. Dashboard TypeScript/lint/build also passed through Corepack/pnpm; no dashboard source was revised.
- Visually inspected rendered initial screens for all 20 missions at 360x800, four representative later work phases/guide sheets, and representative small-phone/doubled-text screenshots. These are synthetic widget renders, not physical Android or all-phase visual acceptance. Ignored PNG galleries and raw measurements are under `ByteQuest-Mobile-App/build/workspace-qa/`. The 568x320 large-text sidebar guide is reached by scrolling its owning panel; its test explicitly verifies the visible hit target before opening the sheet.
- Updated hosted APK: `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/ByteQuest-workspace-hosted-20261112-debug.apk`, **211997300 bytes**, SHA-256 **F005C4668B92CE51F38B2600FA43E52D53100435CD3B5318F0B0CCF825B40492**. Verified compiled hosted project/key/API binding and new workspace code; no local Supabase override. Package `com.example.bytequest`, version 1.0(1), valid Android Debug signer SHA-256 `a4d01056c847034cf2fdc199d4a5dbfa203af5e716d715f560f6db9755bd1d37`, matching the previous owner APK. Attestation JSON is ignored under the QA artifact directory. Existing Kotlin/SDK notices remain non-blocking.
- `adb devices -l` was empty. No emulator start, app install/uninstall, data clear, account creation, hosted write, migration replay, API deployment, or Git push occurred. Owner can update the existing app in place and use its current hosted learner/progress. Physical touch performance, TalkBack, Android font/rotation acceptance, and live hosted interaction/persistence after this UI update remain pending owner testing. Preserve the existing hosted migration/backup records and all unrelated untracked files.

## Current continuation - 2026-11-12 hosted mobile backend fixed; APK handed to owner

- Status: **READY FOR HOSTED MOBILE TESTING**; physical testing has NOT passed. Owner will download/install the APK and declined USB; do not ask for USB again. Approved Flutter UI and dashboard product source remain unchanged on vince-branch. Current report/matrix: docs/HOSTED_MOBILE_TESTING_2026-11-11.md (Nov 11 UTC / Nov 12 Manila).
- Official CLI logins completed. Supabase account now has Owner on the correct healthy ByteQuest project rslmteqipxqfifwftugk; former 403 resolved without changing account permissions. Vercel team vincee08s-projects/project bytequest verified. Active production dpl_CM8Kh72voepkXTVm8zWSKJZ2rZhS, Git dff80603087522c7c0a0a070464696b9237580f7; no API source update/deployment required.
- Managed backups list empty, PITR false. Owner did not know DB password; no reset. Owner explicitly approved POST /v1/projects/rslmteqipxqfifwftugk/cli/login-role with read_only:true. Issued role cli_login_supabase_read_only_user, TTL 300 seconds (expired); allowed SET ROLE supabase_read_only_user supplies read access. No manual grants or auth bypass. TLS verify-full uses official Supabase production CA bundle.
- Encrypted full logical backup/roles/digests in %LOCALAPPDATA%/ByteQuest/Recovery/rslmteqipxqfifwftugk-20261111, Windows-user/SYSTEM ACL only, AES-256-GCM and DPAPI CurrentUser key. Database archive SHA256 13fb80319663c62d83dab89f45a0ef26a7550b31f76ad12ddfdc9be4cee4ee3c. Restore proof: 116 relations / 5,453 rows, all content hashes/counts exact, on fresh pinned Supabase Postgres 17.6 container network none/no ports/tmpfs/read-only root/non-root. Container stopped; old stacks preserved. Storage objects/Vault secrets zero; preserve config/metadata and export actual object bytes separately if any appear later. Recovery is tied to this Windows DPAPI profile/key; no hosted restore authorized.
- Restored-hosted-copy foundation gate exposed a concrete second shared-backend incompatibility: CLIENT_ACTION_ID_IDEMPOTENCY_FAILED; hosted assessment append RPC/index lacked existing 20260908120000 hardening. Duplicate-key preflight zero. No other mission definition mismatch was invented. Reused that existing SQL plus unchanged COC1 M1 v3 migration, with the two quiz functions/required grants. Exact targeted batch and original v2 discard/restart, historical quiz and instructor lifecycle rollback tests passed (restore-verification-attempt8.json).
- Owner explicitly approved exact scripts/hosted-mobile-compatibility-20261111.sql SHA256 412420f9ef8d742bb02ced545e3b71d4b5eadb64ac8bd09486e053fc85b86ab4. Applied once through authorized Management API at 16:06 UTC after rechecking backup matched all 116 source relations. Atomic guards preserve all protected data. 49 hosted history entries preserved; now 50, with honest batch record 20261111160000 / hosted_mobile_v3_and_action_idempotency containing the two executed SQL bodies. Do not replay 52 migrations, repair history, edit/reapply the frozen batch, or assume local timestamp history now equals hosted.
- Post-write read-only full data hashes match on all 114 unaffected relations; only practice_mission_contracts and schema_migrations changed. Counts before QA signup unchanged: 37 profiles/Auth users, 595 practice actions (297 M1 across four learners), 1 practice completion, 0 practice quiz/COC progress, 45 assessment attempts, 64 score revisions, 22 releases. TeacherDesk preserved. All 20 hosted definitions now EXACTLY match approved Flutter export. Seven shared practice/assessment RPC bodies and grants match approved source. Unfinished v2 evidence retained; only learner-confirmed discard/restart, never automatic conversion/deletion.
- Owner explicitly approved dedicated hosted test plan. Created bytequest.mobile.qa.20261112@bytequest.invalid via legitimate hosted signup; owner chose password in secure local prompt. QA user 3ce14700-2e68-4cf1-aa2c-14c607e23428, learner/active. Real password sign-in/user confirmation and learning-path read passed. Production API GET for a random nonexistent quiz returned expected authenticated 404, proving it accepted the new correct-project learner/profile and read the hosted table. Vercel request sin1::iad1::fw7jg-1794413794353-6dc6c216a363 at 16:16 UTC. No synthetic evidence, mission completion or quiz written by automation. Login/session credentials are DPAPI-encrypted outside Git; never print them. Owner manual phone actions/evidence/20 missions/four quizzes are approved for this identity; class/enrollment/extra test identities/cleanup/deployments are NOT approved.
- Hosted download APK: ByteQuest-Mobile-App/build/app/outputs/flutter-apk/ByteQuest-hosted-testing-20261112-debug.apk; 211997300 bytes, SHA256 63c336d3938487c85b26e4acce02ce6430306e919b1f09e937e29a6df777bfc0; debug/com.example.bytequest, 1.0(1), API24/36, all three ABIs, Android Debug signer a4d01056c847034cf2fdc199d4a5dbfa203af5e716d715f560f6db9755bd1d37. Checkout 73257c1b4b71af15c3d8e71e81f799a4b9635fd4, app source 5ae4dd6ba520685b40217847daf0b4d333634aa2; explicit hosted BQ_* define file ignored, public key only. 600 nonempty decompressed entries scanned; no configured server secret/local backend override; signature valid. No app installed/replaced/cleared. Actual phone runtime/backend/event delivery and all manual interaction/persistence results remain pending. If updating existing app, owner signs out and preserves its data; fresh QA identity prevents replay of an old local learner's pending work.
- Instructor practice visibility remains unresolved: deployed progress/dashboard source reads official attempts and score revisions, not practice completion/COC progress. Do not claim it displays practice progress; no dashboard redesign/revision started. A minimal related integration would need scoped work and separate deployment approval after phone testing. Phone registration UI also unverified; automated real hosted registration is not physical UI proof.
- Fresh required local gates passed: Flutter dependency resolution, analyzer (0 errors / 0 warnings / 217 infos), **436/436 tests**, explicit hosted debug APK build, dashboard TypeScript/lint/build, and Git whitespace checks. No application source changed. No Git push or production API/environment change. Next: owner installs downloaded APK, uses locally chosen QA password, tests M1 then all 20 missions/four quizzes and reports observed phone results; correlate real requests/rows/logs without exposing credentials. Keep test evidence; do not claim physical success before owner approval.

## Current continuation - 2026-11-11 hosted mobile testing gate

- Status: **BLOCKED — ACTION REQUIRED**. Focused report and the 20-row compatibility matrix: `docs/HOSTED_MOBILE_TESTING_2026-11-11.md`. Application source is `5ae4dd6ba520685b40217847daf0b4d333634aa2` on `vince-branch`. The approved Flutter UI and all dashboard product files are unchanged.
- Fresh read-only checks at 14:24–14:32 UTC identify hosted **ByteQuest · production**, reference `rslmteqipxqfifwftugk`. Mobile publishable-key Auth health/settings return 200. `https://bytequest-alpha.vercel.app/api/learner/practice` returns the expected unsigned 401; that route returns before constructing its database client, so this does not verify the deployed SHA or backend binding.
- Fresh server-side GETs of contract metadata, compared canonically to definitions exported from current Flutter, confirm exactly **19 matches / 1 mismatch**. Hosted COC1 M1 is still `css-sag-20261011-v2` with four first-phase placement requirements; current Flutter is v3 identification. Shared practice tables/RPC names are exposed. Hosted verifier bodies, RLS, grants, constraints and authenticated execution remain unverified. No migration is indicated for the other 19 missions.
- Hosted read-only SQL and backup listing again return **403**. Vercel has no CLI login; its login prompt was canceled. Migration history/catalog, tested recoverable backup, current deployment revision and effective environment are still unavailable. The owner replied “i cant” to retrieving evidence. Supabase/Vercel plugins were suggested as an alternative; neither is confirmed connected. An authorized project/team account holder must connect access or provide the documented non-secret evidence. Do not keep retrying the same denied requests or bypass authorization.
- Added `scripts/hosted-mobile-readonly-evidence.sql`: catalog/history hashes, practice function bodies, RLS/ACL metadata, hosted-only object inventory and aggregate preservation counts, inside a read-only transaction ending in rollback. It passed against the **existing local database only** (`transaction_read_only=on`, 52 migrations, 20 contracts). Its private output remains ignored. No hosted SQL succeeded and no database write was performed.
- No Android device/emulator is attached. The inspected pre-validation APK has hosted bundled defaults and SHA-256 `75A8E67CB1A167E7A4DB2DAD1D1A181E842485D8BE4E437EE2CED335086B478E`, variant `debug`, package `com.example.bytequest`; this is not runtime proof or a hosted-testing release. The last recorded emulator installation used local endpoints. No installation, replacement, data clear, learner login or test write occurred.
- Specific acceptance dependency: current instructor monitoring/progress pages query official attempts and score revisions; no practice-completion/progress query was found in those UI paths. Live dashboard revision remains unknown. Record instructor visibility of practice progress as unresolved; do not claim that practice verification appears in the assessment UI or start unrelated dashboard revisions.
- The sole existing targeted v3 migration is now tracked, unchanged at SHA-256 `95D60BDC4ECC09A728814C3A31156E170B8BE7EBC1873E30CA580ABAF81E9A3F`. Its earlier isolated rollback rehearsal remains valid within its documented scope. Obtain history/catalog, backup/restore and deployment evidence before presenting a concrete migration for separate owner approval. Preserve unfinished v2 actions and use only learner-confirmed discard/restart; no automatic evidence conversion or deletion.
- The report specifies future dedicated hosted QA account operations, all-20 owner test records, runtime host/log correlation, package/signing provenance and installation safeguards. **Separate explicit approval is still required before any hosted migration, deployment, environment modification or test-data write.** Use a fresh hosted QA identity so pending local evidence from an old identity is not replayed to hosted. No push or production operation is authorized.
- Local commit gates passed: dependency resolution, analyzer (0 errors / 0 warnings / 217 infos), **436/436 Flutter tests**, debug APK build, dashboard TypeScript/lint/build and `git diff --check`. Flutter 3.47.7 reproduced the same APK SHA-256 above; Android Debug signature verifies. All 601 decompressed entries were checked against configured server-only credentials with no match; only the expected public client environment is bundled, and no specific local backend override URL was found in the Dart payload. The APK remains a **validation artifact, not an approved hosted-testing build**. Desktop symlink checks were avoided with process-local `FLUTTER_WINDOWS/FLUTTER_LINUX/FLUTTER_MACOS=false`; no global setting changed. Existing Kotlin/SDK migration notices remain. Commit only the report, read-only evidence SQL and this handoff; preserve all unrelated untracked files.

## Current continuation - 2026-11-11 Docker inspection and approved local commit

- Read-only Docker inspection found two independent groups: `ByteQuest` has the primary local Supabase stack (`supabase_db_ByteQuest`, API 57321, PostgreSQL 57322); `supabase-bytequest_backend_qa_20261110_01-coc1m1v-5765542790ab` has an isolated QA PostgreSQL container on loopback port 58801 and its volume helper. Their PostgreSQL volumes and Docker networks are distinct. The QA group currently has no API container.
- Primary local migration history records all 52 repository versions, including `20261109120000`; QA has the ByteQuest schema but no `supabase_migrations.schema_migrations` table. Both live databases have 20 practice contracts and COC1 M1 v3. Their other 19 contract definitions and quiz functions match. The verifier function matches after line-ending normalization. COC1 M1 differs only in the already documented P2 safety option label (`???` in primary local versus the source em dash in QA); action requirements and verification constraints match. No database write or migration was run.
- The ignored mobile and dashboard environment files point by default to hosted project `rslmteqipxqfifwftugk`; build-time/process overrides mean a particular running app or API binding needs separate attestation. Hosted SQL catalog/history and backups remain unverified under the previously documented access blockers. A fresh publishable-key REST contract read returned HTTP 401; it did not refresh the earlier same-day hosted v2 observation.
- Reviewed the application, migration, tests, scripts, and reports against the prior 20-mission QA record. Excluded the unrelated untracked `.agents/`, dashboard `package-lock.json`, copied PDF, `skills.md`, and `skills-lock.json` from the local commit scope. No credential-shaped value was found in proposed files. No push, deployment, environment change, Docker lifecycle action, or hosted write was performed.
- Validation passed: `flutter pub get`; Flutter analyzer with 0 errors, 0 warnings, 217 informational notices; all 436 Flutter tests; debug APK build; dashboard TypeScript, lint, and production build; Node syntax checks for both practice scripts; and `git diff --check`. Kotlin/SDK future-compatibility build warnings remain.

## Current continuation - 2026-11-11 hosted COC1 M1 v3 preflight

- Completed a read-only hosted preflight and isolated rollback-only v2-to-v3 rehearsal on `vince-branch`. Full report: `docs/HOSTED_COC1_M1_V3_PREFLIGHT_2026-11-11.md`. Decision: **BLOCKED — REQUIREMENTS NOT MET**.
- Hosted `db query --read-only` and `backups list` each returned 403; migration listing still lacks an authorized IPv4 pooler connection. Hosted migration history/catalog, recoverable backup, and deployed Vercel API binding remain unverified. The candidate remains the untracked `20261109120000_coc1_m1_identification_contract.sql`; no migration was applied to hosted or the populated local database.
- `.tmp/rehearse-coc1-m1-v3.mjs` used the isolated QA database only. It restored v2 COC1 M1 inside one transaction, seeded synthetic unfinished evidence, applied the unchanged v3 SQL, verified preservation/rejection and explicit-discard recovery, ran identification/quiz/instructor lifecycle checks, and rolled back. The separate 20-mission replay and nine practice progression assertions passed. QA returned to 4 profiles, 658 actions, 40 completions, v3 COC1 M1, and zero preflight actions. No commit, push, deployment, reset, hosted write, or secret change occurred.

## Current continuation - 2026-11-11 local versus hosted Supabase read-only audit

- Completed the read-only comparison on `vince-branch`; full results and the 52-migration/20-mission matrices are in `docs/LOCAL_HOSTED_SUPABASE_SYNC_AUDIT_2026-11-11.md`. Decision: **LOCAL-ONLY CHANGES DETECTED**. Hosted COC1 M1 remains `css-sag-20261011-v2`, while populated local and isolated QA use `css-sag-20261109-v3`; the other 19 practice definitions and all 20 official activity packages/98 rubric criteria match in live read-only comparisons.
- Local history records all 52 repository migrations; QA replay log passes all 52 but its user migration-history table is absent. Hosted migration history, function bodies, RLS, grants, triggers, indexes and constraints could not be inspected: hosted read-only SQL returned 403 and direct migration listing lacked an IPv4 pooler connection. The live hosted API exposes 22 additional `td_*` relation definitions absent from this repository; their relation kinds remain unverified and they must be preserved. The current Vercel deployment source version is unverified because its CLI has no stored login.
- No hosted or local database was written, no migration/deployment/relink/reset was run, no environment or learner data was changed, and no commit or push was made. The report proposes a targeted v3 migration only after read-only catalog reconciliation, backup/restore rehearsal, in-progress evidence review and explicit owner approval.

## Current continuation - 2026-11-11 owner acceptance of physical-device revisions

- The project owner stated, "I accept the physical-device revisions." Record this as owner acceptance of the proposed revisions. It does not supply measured physical-device or TalkBack test results and does not authorize hosted deployment, migration, or production release.
- `adb devices -l` showed no connected Android device at the time of this acceptance. Physical-device interaction, large-text, TalkBack, performance, and authenticated end-to-end checks remain unverified until they are run and recorded. The 20-mission automated local QA results in `docs/practice_all_missions_qa_2026-11-11.md` retain their stated scope.

## Current continuation - 2026-11-11 original local learner sign-in recovery

- At the owner's request, reset the active learner account's password in the original **local** Supabase Auth using the server-side admin API. Verified the replacement with a local password sign-in and signed out the verification session. The temporary password is disclosed only in the conversation; it is not stored in this repository. Hosted Supabase and isolated QA Auth were not changed. The learner's existing local practice completion remains present.
- Started the original `ByteQuest_QA_API35` emulator (`emulator-5554`). Its network could not reach `10.0.2.2`, so rebuilt the original app with compile-time loopback URLs for the original local Supabase (port 57321) and practice API (port 3000). Mapped both ports with `adb reverse` and confirmed device TCP connectivity. Installed the APK in place and launched ByteQuest. The original app first-install time and `FlutterSharedPreferences.xml` hash were identical before and after installation. The separate isolated QA emulator (`emulator-5556`) remains available. No mission action, completion, hosted credential, repository commit, or push was made.

## Current continuation - 2026-11-11 all 20 practice mission regression

- Verified the prior COC1 M1 root cause: the Android build had local Supabase evidence but a hosted practice API endpoint, and the local v2 contract required placement evidence from a phase now completed by identification taps. The previous session aligned the local API and published the COC1 M1 v3 contract. This session did not reapply any migration or change historical learner evidence.
- Compared current Flutter practice definitions to the local published contracts using UTF-8 JSONB. COC1 M2-M5, all COC2/COC3 missions, and all COC4 missions match exactly. COC1 M1 has one option-label encoding difference with no verifier effect. No shared contract mismatch was reproduced in the remaining missions.
- Corrected `scripts/test-practice-progression.mjs`: it now checks the COC1 M1 identification role instead of obsolete placement, uses transaction-local synthetic learners, and requires an isolated QA database container. Added `scripts/test-practice-api-all-missions.mjs` and the 20-row verification matrix in `docs/practice_all_missions_qa_2026-11-11.md`.
- Recreated the isolated `ByteQuest_Backend_QA_20261110_01` database and applied its 52 existing migrations there only. Rollback-only all-20 PostgreSQL replay passed, as did the 9-check practice progression test, COC1 M1 identification rollback test, and instructor finalization/release foundation lifecycle test. Local production-built Next.js API integration passed 138 checks across 20 missions with synthetic users: incomplete and invalid-action rejection, evidence write, verification, idempotency, all four quizzes, Learn Page projection, and cross-learner isolation.
- Full Flutter analyzer/test/debug build passed; the test suite exercised all 20 mission phases through touch controls. Dashboard TypeScript, lint, and production build passed. Built an explicit local-QA Android APK for `ByteQuest_Isolated_QA_API35` (`emulator-5556`) using Android loopback URLs. That AVD retains airplane mode; `adb reverse` maps its loopback ports 29453 and 3001 to isolated Supabase and the local Next.js production API. Both device TCP probes passed with airplane mode still enabled. The original `ByteQuest_QA_API35` (`emulator-5554`) was restarted from its saved AVD and retains its original app first-install time; it was not reinstalled or cleared. No commit, push, hosted change, or populated-database write was made.

## Current continuation - 2026-11-11 COC1 M1 local verification repair

- The emulator had local Supabase evidence but a hosted practice API endpoint. With the owner's approval to keep this run local and update the local database, applied `20261109120000_coc1_m1_identification_contract.sql` to `supabase_db_ByteQuest` and recorded its migration version. The active COC1 M1 contract is now `css-sag-20261109-v3`; no hosted database or environment file changed.
- A rollback-only migration dry run, `coc1_m1_identification_rollback.sql`, and a rollback-only verification of the learner's saved evidence passed. Existing COC1 M1 action and completion counts remained 143 and 1 before the live confirmation.
- Built the Android debug APK with runtime defines for local Supabase and `http://10.0.2.2:3000/api/learner/practice`, installed it in place on `emulator-5554`, and preserved the app's original first-install time and saved Phase 5 state. The local Next.js practice API is running from the dashboard with local Docker credentials supplied in process only.
- The first live confirmation reached the API and recorded a v3 completion, but Flutter showed a retry message during the API's initial compilation. Retrying succeeded with HTTP 200; the mission screen showed "Saved successfully" and the Learn screen showed **COC1 M1 verified, 1 of 5 missions**. The learner's other saved evidence remains intact. The local practice API must be running while this local Android build is in use.
- Validation after the local contract change: `flutter pub get`, `flutter analyze --no-fatal-infos` (zero errors), all **436 Flutter tests**, debug APK build, dashboard TypeScript, lint, and production build passed. The local Next.js practice API was restarted after the production build. The provisional COC timer expired during validation; its in-app restart control restored 60 minutes without clearing the verified mission or evidence. No source commit or push was made because the worktree already contained unrelated uncommitted changes and the previous owner instruction reserved commits.

## Current development branch - 2026-11-08

The project owner confirmed `vince-branch`, tracking
`bytequest-project/vince-branch`, as the official development branch. Earlier
branch references below are historical to their dated sessions.

## Current continuation - 2026-11-11 signup connectivity repair

- Reproduced the project owner's signup failure from `emulator-5554` logs: `/auth/v1/signup` never reached the hosted Supabase project because Android reported `SocketException: Failed host lookup`. The Windows host resolved and reached the same hostname. On the original emulator, Wi-Fi was disabled and there was no active default network; `adb shell svc wifi enable` restored a validated Wi-Fi network. The emulator then resolved the project host and reached TCP 443.
- Updated the original Flutter signup feedback to classify failed host lookups and related socket errors as an account-server connection problem. Moved the edited feedback strings into `mission_content_data.dart`, removed incorrect advice to disable email confirmation, and retained distinct messages for duplicate email, invalid email, weak password, provisioning, disabled signup, and email delivery errors. Supabase URL, keys, authentication flow, and account records were unchanged.
- Focused `signup_feedback_test.dart`, `auth_provisioning_test.dart`, and `mobile_ux_test.dart` passed **19/19**. `flutter analyze --no-pub --no-fatal-infos` passed with 0 errors, 0 warnings, and 215 informational notices; `flutter build apk --debug --no-pub` passed. The updated APK was installed in place on `emulator-5554` and launched as `com.example.bytequest/.MainActivity`. The original first-install timestamp and `FlutterSharedPreferences.xml` remain intact; Android's active network is validated and TCP 443 to the project succeeds. No test account was created on hosted Supabase, and no database migration, commit, push, reset, or clean was performed.

## Current continuation - 2026-11-10 interactive mission guidance

- Extended the original Flutter guidance on `vince-branch` for all 20 missions and 115 authoritative production phases, covering all 13 interaction families and the review phase. The new "What to do next" list names actual controls and catalog objects, follows recorded runtime actions, highlights the current task, shows completed/remaining counts, and defers Continue readiness to the existing phase policy. Pending server evidence remains pending in the guide.
- Added a compact, collapsible current-action bar and replayable "Show me how" outlines on the actual Objects, Place equipment, Connect ports, task controls, equipment operations, and Continue/Confirm controls. The guide scrolls relevant lower controls into view without covering the workspace. Identification and COC4 replacement directions use taps; placement directions include drag and tap paths where supported. Graded decision and troubleshooting directions do not disclose the required correction choice.
- Changed only guidance content, presentation, and focused tests in the original mobile app. Existing evidence recording, duplicate prevention, progress synchronization, COC timer, grading, and instructor result release were preserved. The original `CODEX_STATE.md` and all preexisting modified/untracked files were preserved; no commit, push, reset, clean, migration, hosted-backend change, or learner mission submission was performed.
- Validation: full `flutter test --no-pub --reporter compact` passed **427/427** before the final graded-decision wording edit; focused final `mission_phase_guidance_test.dart` passed **14/14**, including a check that graded decisions do not name the required correction button. Focused workspace/scene/guidance tests passed **65/65**, mission screen tests **60/60**, and completion policy/session tests **29/29**. Final `flutter analyze --no-pub --no-fatal-infos` passed with no errors or warnings and 215 informational notices. Final `flutter build apk --debug --no-pub` and `git diff --check` passed.
- Rebuilt and installed the original `com.example.bytequest` in place on `emulator-5554` with the matching debug signing certificate; no uninstall or data clear. It launched and remains foregrounded as `com.example.bytequest/.MainActivity`. Android first-install time stayed `2026-09-28 03:00:28`, and `FlutterSharedPreferences.xml` remains present. Backend endpoints were not changed.
- Completion blocker: the active local published COC1 M1 contract `css-sag-20261011-v2` still requires four P1 placement records, while the current identification flow records inspection taps. The prepared v3 SQL migration remains unapplied under the user's database restriction, so server verification for that mission can reject completion. Hosted contract state was not independently verified.

## Current continuation - 2026-11-10 original development environment

- Verified the current Learn rows, guidance, identification-only controls, drag refinements, and COC practice timer in the original `vince-branch` source. Preserved every existing tracked and untracked project file; copied no QA source into the repository.
- Removed eight positively identified QA Docker containers, three dedicated QA networks, and three QA database volumes. The QA databases had zero Auth users; the active v3 QA database also had zero profiles. The original `supabase_db_ByteQuest` stack and its volume remain running, with 48 profiles. Local COC1 M1 is still `css-sag-20261011-v2`; the v3 migration remains unapplied.
- Verified that the original Flutter and dashboard environment files, the previously installed Android APK, and the repository's remote link metadata all reference the same hosted project. The installed `com.example.bytequest` APK and a new original-source debug build have matching signing certificates. The app was updated in place on `emulator-5554` and left in the foreground; first-install time and shared preferences were preserved.
- Validation: `flutter pub get` passed, `flutter analyze --no-pub --no-fatal-infos` passed with 215 informational notices and no errors or warnings, `flutter test --no-pub --reporter expanded` passed 419/419, and `flutter build apk --debug --no-pub` passed. No mission action, learner-record mutation, migration, commit, push, reset, or database recreation was performed.
- Automatic approval review blocked deletion of the three disposable sibling QA folders and `ByteQuest_Isolated_QA_API35` AVD, so they were preserved. It also blocked removal of the temporary pulled installed APK at `C:\Users\HP\AppData\Local\Temp\bytequest_original_installed_base.apk`. The original emulator is `ByteQuest_QA_API35`, running as `emulator-5554`.

## Current continuation - 2026-11-10 guided Flutter learning UX

- On `vince-branch`, the original Flutter app now shows compact Learn mission rows with expandable descriptions and puts COC quiz/progress detail after the five missions. The four COC cards retain server-derived verified counts, selection, and lock state.
- Added a shared phase-guidance resolver and pinned expandable instruction UI for all 20 production missions: 115 phases across 13 rendered interaction families (COC1 26, COC2 30, COC3 29, COC4 30). Guidance uses each catalog phase objective, actual typed controls and equipment overlays, and runtime progress. COC1 M1 and COC4 M1 identification directions require taps; COC4 M4 replacement directions use tap placement; practical drag phases retain drag instructions. Continue status now includes outstanding work-order checks.
- Compact inspection scenes reflow to wider, taller hardware targets while placement/connection scene sizing remains unchanged for drag reachability. Invalid placement messages use a readable `component to destination` separator. The mission timer presents the remaining countdown distinctly and shows a short expiry label; the underlying provisional 60-minute local COC practice policy is unchanged.
- Verification after final source changes: `flutter analyze --no-pub --no-fatal-infos` passed with 0 errors, 0 warnings and 215 informational notices; the complete safe `flutter test --no-pub --reporter expanded` suite passed **419/419**. Focused scene/workspace/drag tests passed **55/55**. A disposable synthetic-state visual harness passed **10/10** and refreshed screenshots in `C:\Users\HP\Documents\Projects\ByteQuest_Visual_QA_20261109_01\screenshots\guided_20261110`. No original secrets, hosted Supabase, existing database, or emulator data were accessed or changed.
- The COC1 M1 v3 SQL migration remains source-only and unapplied; server-side completion for the revised identification path remains unverified pending separately authorized QA backend migration and verification. No commit, push, branch change, database operation, or Android install was made.

## Current continuation - 2026-11-09 isolated Android visual QA

- Copied the current original Flutter source from `vince-branch` to sibling disposable workspace `C:\Users\HP\Documents\Projects\ByteQuest_Visual_QA_20261109_01`, excluding original credentials and generated files. Used only synthetic `.env` values (`bytequest.invalid` and a test key). The final debug APK is 172,043,350 bytes, SHA-256 `FF157030E0891CAE48CEEFBF587229B8108A1271E3CAEA1F56CC36280B52E3D5`.
- Verified `emulator-5556` is `ByteQuest_Isolated_QA_API35` and confirmed IPv4, IPv6, and DNS attempts fail with non-loopback output rejection before installation and launch. Replaced only the earlier synthetic QA package; its debug signature differed, so the QA package was uninstalled before installation. `emulator-5554`, its learner data, local databases, and hosted services were untouched.
- The first disposable build lacked Android plugin registration because Windows desktop symlink creation interrupted offline `pub get`; excluded the desktop target in the disposable copy, regenerated plugins offline, rebuilt, and confirmed real onboarding/login startup. Captured standard, compact, and landscape login states; compact and landscape login actions remain reachable by scrolling. Restored the QA display size and density after inspection. No current-process Flutter exception or overflow was found.
- Disposable widget harness with synthetic in-process HTTP responses and in-memory mission evidence captured the Learn page, all four COC cards and five-mission lists, COC1 M1 tap identification, valid/invalid placement feedback, active practice timer, and blocked timeout state. Screenshots and the QA-only harness are under the sibling disposable workspace. No production Flutter source fix was needed; six final visual widget tests passed.
- Original-source verification PASS: `flutter analyze --no-pub --no-fatal-infos` with 0 errors, 0 warnings, 215 infos; complete safe `flutter test --no-pub --reporter compact` suite **410/410**. `git diff --check` passed. COC1 M1 server completion remains unverified until the pending v3 SQL migration is separately authorized, applied, and tested. No SQL was run; no commit or push was made.

## Current continuation - 2026-11-09 COC1 M1 identification contract source

- Prepared source-only `supabase/migrations/20261109120000_coc1_m1_identification_contract.sql`. It publishes only COC1 M1 as `css-sag-20261109-v3`: P1 requires seven inspection taps and no placement; P2 uses tap-recorded, single-choice component-role classifications through the existing `selection_confirmed` action. The final readiness test remains the server authority for correct roles and the safe work plan. No historical migration or learner evidence row was changed.
- The migration replaces only the two server-only practice quiz gate functions so already verified COC1 M1 v1/v2 completions still count with the other four current mission completions. Unsupported versions still fail closed. The active contract remains v2 in every existing database until this migration is separately applied. Coordinate backend migration before distributing a Flutter build with the new COC1 M1 flow.
- Added rollback-only SQL coverage for correct and incorrect identification, spoofed client success, duplicate action IDs, legacy placement evidence, historical completion versions, and server-only evaluator access. SQL was **not executed** because this task forbids running migrations or touching existing Docker databases. No dashboard, official assessment, instructor finalization, release, timer, emulator, or environment file changed.
- Validation: `flutter analyze --no-pub --no-fatal-infos` passed with zero errors and warnings (215 informational notices); the complete safe isolated `flutter test --no-pub --reporter expanded` suite passed **410/410** after all Flutter changes. No APK was built or installed. No commit or push was made as explicitly requested.

## Current continuation - 2026-11-09 Learn, workspace, and COC practice time

- On `vince-branch`, improved the original Flutter Learn practice tab into four expandable COC paths with five mission descriptions, verified counts, selected-mission state, server-derived locks, and a visible COC countdown. The learning path now shows all five published mission titles and the COC details page shows the same practice timer. Assigned assessment routing, result release, quiz thresholds, and database projections remain unchanged.
- Added a provisional, configurable 60-minute local practice deadline per learner and COC. The learner explicitly starts it; all five catalog missions share the checkpoint in `ProgressResumeService`. The timer resumes from its UTC deadline, announces 10/5/1-minute bands, blocks new timed practice actions at expiry, and preserves evidence. A backward device-clock jump pauses interaction. Assigned assessment payloads do not use this practice timer. An expired local practice session can be explicitly restarted; it does not clear mission evidence or award completion.
- Shared equipment workspace now highlights compatible destinations after selection, marks incompatible hovered destinations, prevents duplicate completed placements/connections, and retains the existing orientation and evidence flow. Tap inspection displays a recorded-target count. Existing scene coordinate handling passed a zoom/pan drop regression.
- Reviewed the 20 runtime routes and equipment overlays. COC4 M1 inspection advances without placement; COC4 remains non-draggable. COC1 M1 is labeled identification but its published `css-sag-20261011-v2` practice contract requires four `coc1_m1_p1` placement records. A Flutter-only removal would make backend verification fail, so that contract remains intact pending a separately authorized versioned backend contract change. No Supabase or dashboard file changed. Server-enforced COC timeouts likewise require a separately approved backend contract; local checkpoints cannot prevent deliberate device-clock or storage tampering across process restarts.
- Validation: `flutter analyze --no-pub --no-fatal-infos` passed with 0 errors, 0 warnings, 214 info notices; full isolated `flutter test --no-pub --reporter compact` passed 404/404 before the final checkpoint-queue fix; final timer service tests passed 8/8 and final mission screen/workspace/completion tests passed 96/96. `git diff --check` passed. No emulator installation, learner-record mutation, production account, network test, or APK build was performed. This session did not commit or push, as the user explicitly requested.

## Current continuation - 2026-10-13 duplicate placement feedback removed

Continue on the user-selected `new` branch. In practice, an incompatible
component/destination now clears the previous workspace and task-panel feedback
and shows only the five-second incorrect-placement modal. Both canvas drag/tap
and lower controlled-placement actions use this path. Other placement failures
retain their distinct technical feedback; evidence handling and assessment
rules are unchanged.

The canvas regression test first reproduced three copies of the same reason
(workspace, task panel, modal). The updated tests pass for both placement paths
and confirm the old reason does not reappear after manual or timed dismissal.
Mandatory gates PASS: `flutter pub get`, analyzer (0 errors, 0 warnings, 206
existing infos), **395/395 Flutter tests**, debug APK build, dashboard
TypeScript/lint/production build. The APK was built with the existing hosted
practice API URL and installed on Android emulator `emulator-5554`; local and
installed SHA-256 match:
`E40BC314479EC5F9B83A00A14CC62DF4684324F2216AA592B20EAFCD52CEC867`.
App process launch had no Flutter exception or overflow. Replacement preserved
the existing COC1 M2 Phase 1 snapshot exactly: 1 placement, 0 connections,
4 accepted evidence IDs, 0 pending. No live incorrect placement was generated
against the learner's account; modal behavior is verified by widget tests.
Preserve the user's untracked PDF and dashboard `package-lock.json`.

## Current continuation - 2026-10-13 incorrect placement notification

Continue on the user-selected `new` branch. A practice attempt to install a
component in an incompatible slot now opens a compact modal with the tried
component, destination and technical reason. It closes after five seconds or
when the learner taps the labeled 48 dp Close button. This covers the shared
canvas drag/tap path and the retained controlled-placement controls. The
modal timer cancels when dismissed or the route is disposed; assessment
correctness remains private. Incorrect attempts still record evidence and do
not install a part. Other placement failures retain their distinct technical
feedback. Text is in `mission_content_data.dart`.

Focused widget tests pass for wrong canvas placement, five-second expiry,
manual dismissal without leaving the mission, and rejected evidence without
an installed part. Final mandatory gates PASS: Flutter dependency resolution,
analyzer **0 errors / 0 warnings / 206 existing infos**, **395/395 tests**,
debug APK build, and dashboard TypeScript/lint/production build. Existing
SDK/Kotlin plugin migration notices remain non-blocking.

The rebuilt APK was installed on the Android API 35 emulator with the existing
hosted public practice endpoint. APK SHA-256
`9E78E66E8E557C156DEC6873FC8A5C166E41D6CD9D28ABFA890B99E288995B88`
matches the installed package. App launch reports no current-process Flutter
exception or overflow. APK replacement preserved the learner's current COC1
M2 Phase 1 run exactly: **1 placement, 0 connections, 3 accepted evidence IDs,
0 pending evidence**. Mission reentry shows the Phase 1 placement workspace
with the existing chassis, and the saved runtime remains identical. No
practice action or completion was generated for QA.
This is emulator and widget validation; physical-device/TalkBack acceptance
remains separate. Preserve the user's untracked PDF and dashboard
`package-lock.json`.

## Current continuation - 2026-10-12 workspace overlap repair

This follow-up supersedes the previous APK and device snapshot. Continue on the
explicitly selected `new` branch, tracking `bytequest-project/new` in
`vincee08/bytequest-project`.

- Reproduced overlapping cable labels on Android and parts clamped onto the same lower scene coordinates. The catalog can supply more rows than the old normalized canvas accommodates; minimum tap-target expansion also caused collisions. Fixed the shared presentation engine, preserving mission definitions, object IDs and evidence contracts.
- Crowded scenes now reflow into distinct rows on a vertically scrollable canvas. Separated existing columns are retained where they fit; narrow layouts use a grid. Connection lines use the same resolved object coordinates. Fit returns to the first row; changing mode/phase resets the scene scroll. Every object retains at least a 48 dp target.
- Hotspot artwork, labels and optional action hints have separate measured space. Photos render once with a corner status indicator. An installed source keeps its selectable Installed status; its part photo appears at its destination. Placement status follows actual placements rather than earlier inspection alone. Reduced-motion and compact completion transitions remain.
- Canvas drags use the existing reusable edge-scrolling control, including an adaptive edge zone for very short viewports. Saving still freezes mission interactions. Tap placement, keyed orientation, connection evidence and backend evaluation are unchanged.
- Focused validation PASS: **68 tests**, including all twenty scene definitions at compact portrait/landscape widths, unique non-overlapping 48 dp objects, scroll/tap access, one installed-part image, offscreen canvas drag, placement/connection/orientation paths, accessibility and reduced motion. The legacy assessment large-text check now verifies the review action is reachable through its owning scroll view rather than assuming only one scroll view exists.
- Final mandatory gates PASS: dependency resolution; analyzer **0 errors / 0 warnings / 206 existing infos**; **394/394 Flutter tests**; Android debug APK; dashboard TypeScript, lint and production build. This includes all real mission phases with doubled text and all twenty touch-control work orders. Existing SDK/Kotlin plugin notices remain non-blocking.
- Current saved learner run before installation: phase `coc1_m2_p3`, **8 placements, 0 connections, 20 accepted evidence IDs and 0 pending evidence**. No mission action, reset, submission or completion is generated for presentation QA. The previous Phase 5 snapshot is historical, not this session's current state.
- APK rebuilt at `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk`, installed with replacement preserving data. SHA-256: **EC90F03BAF3913EE5659613EE48F764FE0CAB222875A57137E3B4A951A1D1277**. Scope and validation are recorded in the overlap follow-up of `docs/MOBILE_UX_AUDIT_2026-10-11.md`.
- Android API 35 smoke PASS: recognizable connection targets, separately rendered photos/names/status, vertical navigation to the last distinct inspection row and Fit returning to the start. APK replacement and M2 reentry preserve login, phase, placements, connections, accepted evidence IDs and configuration. After Fit/return to Connect ports, the saved runtime matches the pre-install snapshot exactly. No current-process Flutter exception or overflow was found. These are presentation/resume checks, not live mission completions.
- Preserve the user's untracked PDF and dashboard `package-lock.json`. Build artifacts, client environment, device snapshots and local logs remain ignored. Further physical-device, complete TalkBack and independent learner acceptance remain separate checks.

## Current continuation - 2026-10-12 mobile UI/UX audit and validation complete

This section supersedes earlier UI/build blockers. The explicit user-selected
branch remains `new`, tracking `bytequest-project/new` in
`vincee08/bytequest-project`. The scoped UX commit includes this handoff and
`docs/MOBILE_UX_AUDIT_2026-10-11.md`; inspect Git for its current revision.

- Audited all 45 screen sources, routes, shared controls and runtime. Implemented recognizable button/disabled/loading states, wrapping labels, visible Material ink, labeled Settings/Learning path/Quizzes and accessible Back controls. Removed nonfunctional avatar-camera/upload decorations; signup policy text now opens the real Terms/Privacy route.
- The four main destinations retain state through an IndexedStack. Home selects the existing Learn destination, and Android Back follows visited destinations. Secondary routes preserve the Learn/Practice context. Existing routes/features remain.
- All twenty runtime missions use a pinned Continue/Review/Confirm evidence action area. Learner-visible pending action counts explain disabled Continue without changing completion gates or leaking assessment targets. Phase titles, source/location captions, selected-source instructions, installed/connected indicators and numbered sequence controls clarify tasks. COC4 uses tap sequencing instructions. Large-text layouts scroll the scene/task panel together, preserving the primary action.
- Practice access has loading/recovery states rather than temporary lock notices. COC summaries show verified mission counts and the next step; quizzes have an explicit labeled action when the existing server-backed access permits it. Existing unlock/evaluation rules are unchanged.
- Reset/discard requires consequence confirmation. Edit Profile retains entries on failure, presents an inline recovery message and prevents duplicate saves. Mission errors show a guarded Retry; pending evidence is retried with its original action ID rather than repeating a phase transition. Disabled completed hotspots remain readable and screen-reader activation runs once.
- Fixed and reran the three earlier failures: keep offscreen power-supply drag reachable by placing help after inventory; distinguish numbered sequence steps from keyed task labels and remove duplicate COC4 numbering; use Material/Ink for nested static-card controls such as FAQ expansion.
- Final mandatory gates PASS: Flutter dependency resolution; ordinary Flutter analyzer **0 errors / 0 warnings / 206 infos**; **389/389 Flutter tests**; Android debug APK; dashboard TypeScript, lint and full production build. Previous SDK/process restrictions are no longer blocking. Existing analyzer infos and Kotlin/plugin migration notices remain tracked, non-blocking.
- Automated coverage includes all twenty touch-control work orders, every real phase at 320x568, 640x360 and 800x360 with 2x text, offscreen drag/tap/orientation alternatives, retained navigation/forms, destructive guards, save failure/retry and screen-reader hotspot semantics. These are widget results, not twenty live learner completions.
- Final Android API 35 smoke PASS: Home Continue/View all -> existing Learn, Progress -> system Back -> retained Practice, path/quizzes -> Back -> Learn, Settings/Profile Back, labeled Settings Back, Help FAQ expansion, M2 review/pinned confirmation and Save and Exit. Current-process Flutter logs contain no exception/overflow in these checks.
- Built/installed `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk` with the hosted public practice endpoint. SHA-256 **2F378211EE3720D40F5BCA9689AD89982831CE35DBB52FB036C87E246703DCE2** matches the installed package. Reinstallation, force-stop/relaunch and M2 reentry preserve login, phase `coc1_m2_p5`, **8 placements, 2 connections, 47 accepted evidence IDs and 0 pending evidence**. The catalog reports the learner's existing COC1 **1/5** verified practice missions. No practice action, reset, submission, quiz score or completion was generated for UI smoke testing. Emulator remains open on M2 Review evidence.
- Backend/API/auth/schema/RLS/assessment and instructor-release contracts remain unchanged; no hosted migration or Vercel API deployment is needed for this mobile UX change. Full TalkBack use, further physical-device coverage and independent first-time-user acceptance remain separate checks; do not infer these from source/widget/emulator results.
- Preserve the user's untracked PDF and dashboard `package-lock.json`. APKs/build files/env files and local QA logs/snapshots remain ignored. Earlier copied tooling under `.tmp/` remains local; original SDK/emulator data were not removed. Future work should extend this validated implementation rather than redoing it.

## Current continuation - 2026-10-11 COC1 drag repair

This section supersedes the APK and device-check status below. Continue on the
user-selected `new` branch, tracking `bytequest-project/new`.

- Reproduced the reported problem in both installation areas. During evidence synchronization, disabled draggables let the canvas pan instead of accepting a drop. Lower-panel keyed parts silently required an orientation selection farther down the controls, and offscreen destinations were unreachable during a drag.
- The shared workspace freezes camera gestures during saving and distinguishes equipment placement/connection gestures from inspection panning. A visible, accessible `Saving action…` status identifies the wait. Existing zoom/Fit controls remain available.
- Canvas and lower-panel installation now share the explicit alignment dialog; selecting an orientation records one drag action, and cancelling records none. A reusable edge-scrolling draggable makes lower-panel part and cable destinations reachable. Changing phases starts controls at the top. Technical rejection messages appear inside the workspace without covering Continue.
- Preserved existing action IDs/payloads, backend evaluation, evidence/resume services and COC4 behavior. This is a Flutter deployment; hosted contracts, Supabase migrations and Vercel API source are unchanged.
- Final gates PASS: dependency resolution; mobile analyzer **0 errors / 0 warnings / 212 existing infos**; **370/370 Flutter tests**; Android debug APK build; dashboard TypeScript/lint/production build. Regression coverage includes a previously failing save-time pan gesture, all six assembly drops, both internal cables, all four peripheral cables, alignment cancellation, offscreen lower-panel part/cable drops and phase-scroll reset across all twenty touch-driven work orders.
- Real Android API 35 gestures installed all six COC1 M2 components with explicit alignment. The lower-panel power-supply drag auto-scrolled to its destination. Both ATX power and SATA data connections saved to hosted `practice_mission_actions` with `input_method=drag`; six assembly records and two cable records are present exactly once. The saved runtime contains all eight placements (including two preparation items), both endpoint pairs, phase `coc1_m2_p3` and zero pending evidence.
- Final installed APK SHA-256: `D0E72582869815F58D0C3F15679D84440280E97DE3E120B95B378D2D6E3DCE29`, confirmed against the installed package. Reinstallation, force-stop/relaunch and mission reentry retained login, all eight placements, both connections and phase 3. Hosted evidence stayed at **27** records, including earlier activity, with exactly six assembly drags and two cable drags; mission and COC completions remain **zero**. No completion was fabricated. The emulator is open on COC1 M2 Connect ports. See the repair section in `docs/CSS_DRAG_WORKSPACE_UPDATE_2026-10-11.md`.
- Preserve the user's untracked PDF and dashboard `package-lock.json`. `.tmp/coc1-drag-device.ps1` is an ignored, credential-free device QA helper, not an application asset. Full hosted mission/quiz completion, independent TalkBack/device-matrix acceptance and successful live AI generation remain separate checks.

## Current continuation - 2026-10-11 practice canvas follow-up

This section supersedes the practice canvas/contracts status below. The user's
explicit branch choice remains `new`, tracking `bytequest-project/new`.

- Re-scanned all seven pages of `Computer-Systems-Servicing-NC-II_copy.pdf` and retained the existing TESDA SAG competency mapping. Source, behavior, migration mapping and acceptance limits are in `docs/CSS_DRAG_WORKSPACE_UPDATE_2026-10-11.md`.
- All fifteen COC1–COC3 practices now require equipment deployment before the first phase can advance. The main zoomable canvas supports actual equipment drops, compatible cable gestures, explicit keyed-part orientation and an equivalent tap path. Inspection, configuration, diagnosis, tests and review remain required. COC4 retains its progressive troubleshooting flow without draggable controls.
- `EquipmentWorkspace` composes the existing `SimulationScene`, controller, evidence transport and resume service. Source and destination canvas IDs are distinct for devices that serve both roles, while raw evidence preserves contract IDs. A horizontally scrollable mode selector prevents overflow in small, large-text workspaces.
- Created/applied forward migration `20261011043723_css_drag_workspace_contracts.sql`; hosted project `rslmteqipxqfifwftugk` records it as `20261011044331`. Local history now has **51** migrations and hosted history **49**. Fifteen COC1–COC3 definitions use `css-sag-20261011-v2`; five COC4 definitions retain `css-sag-20261009-v1`. All twenty local/hosted definition digests match. No schema, grant, RLS policy, evaluator function or official assessment contract changed.
- The existing production Vercel practice API reads the updated Supabase contracts; no dashboard source change or extra API deployment is required. Old evidence/completions remain; starting a new quiz requires mission verification against current contract versions. Completed COCs retain their progression records.
- Local rollback suite PASS **8 files / 19 assertions**, including foundation lifecycle, grants and new workspace coverage. All **20 raw mission replays**, four sequential COCs, quiz resume/failure/grading, idempotency, RLS and tampering checks PASS. Removing COC1 M1 placement evidence in a rollback transaction correctly blocks backend completion.
- Android API 35 device check PASS: a real motherboard drag saved hosted `placement_attempted` evidence with `input_method=drag`. Background/force-stop/relaunch and mission reentry restored the installed motherboard and phase 1, with exactly **one** drag-placement record, **five** total evidence records (including earlier discarded activity), and **zero** mission/COC completions. Existing login/data are preserved.
- Final mobile gates PASS: dependency resolution, analyzer **0 errors / 0 warnings / 212 existing infos**, **361/361 Flutter tests**, and debug APK build. This includes all-20 real-control work orders, all-phase portrait/landscape/2x-text matrices and 23 canvas regressions. Dashboard TypeScript/lint/production build PASS. The explicit temporary contract export matches the applied migration byte-for-byte. Production API still returns the expected anonymous JSON 401.
- Installed the final APK SHA-256 `C972A9091954D3D87FF5A88C2249AFAD49D264034A3175E39519457B31ACF923`, checked embedded hosted/public endpoints without printing keys, and confirmed the installed motherboard restores after the final rebuild. The learner remains signed in and the visible emulator is open on COC1 M1; hosted evidence remains five records with exactly one drag placement and no fabricated completion. Existing Kotlin plugin migration notices remain non-blocking.
- Preserve the user's untracked PDF and dashboard `package-lock.json`. Independent TalkBack/device-matrix acceptance, full hosted learner mission/quiz completion and successful live AI generation remain separate checks; do not fabricate learner completion.

## Current continuation - 2026-10-11 hosted activation

This section supersedes earlier hosted-activation blockers and pending-rollout
claims. The user explicitly authorized continuing on branch `new`.

- Completed the hosted rollout on Supabase project `rslmteqipxqfifwftugk`, Vercel project `bytequest` / `prj_vUXjALnNCLQWzzdScvwXMfYvppga`, and the visible Android API 35 emulator. Details and migration-history mappings are in `docs/HOSTED_PRACTICE_ACTIVATION_2026-10-11.md`.
- Hosted preflight found both the practice evidence table and learning-path RPC absent. Applied the existing evidence prerequisite, the two reviewed progression/contracts migrations, then the new forward migration `20261011040839_harden_practice_evidence_grants.sql`. Divergent foundation history was neither replayed nor repaired. A private pre-change schema/access snapshot is ignored under `.tmp/`; it is not a full database backup.
- The forward fix explicitly revokes inherited learner UPDATE/DELETE/TRUNCATE and sequence mutation privileges. Learner SELECT/INSERT/sequence USAGE remain, with RLS and existing server evaluator access intact. Added a meaningful rollback grant assertion. No new SECURITY DEFINER function was introduced.
- Hosted checks PASS: all twenty versioned mission contracts, four progression rows, COC1 availability and later-COC locks, private quiz-key denial, client evaluator denial, practice-table RLS and append-only evidence grants. No learner completion was fabricated; instructor release remains authoritative for official assessment.
- Deployed dashboard source `ccb3aef4d8e70c27e934a66f12d38fa40df38216` from `new` as staged production deployment `dpl_5rWf1YtWUC7DDVsy9stu9UZ6bY7a`, tested it, and promoted the same READY build. `https://bytequest-alpha.vercel.app` resolves to that deployment. Next.js build took 114.061 seconds. The connected Vercel plugin actor lacked team access; authenticated CLI operations used the same verified team/project.
- Staged and production API checks PASS: anonymous 401, active learner recognized (400 without a quiz attempt), incomplete mission 422, later-COC verification 403 and quiz-before-five-missions 403. Error-level runtime log scan returned no entries; no drains are configured and project monitoring settings did not show enabled products.
- Production stores the existing OpenRouter credential as a server-only Secret with `PRACTICE_OPENROUTER_MODEL=openrouter/free`. The live provider probe returned the grounded fallback bank; successful live AI generation remains unverified.
- Rebuilt and reinstalled the Android APK with the correct public practice endpoint and hosted Supabase URL embedded, preserving app data/login. The existing learner can open Learn → Practice → COC1 hardware inspection; a real motherboard inspection saved authenticated evidence to hosted Supabase. After background/force-stop/relaunch and mission reentry, phase 1 and the selected motherboard restored, with exactly one evidence row and zero mission/COC completions. The emulator remains open. No credential is stored in tracked source.
- Fresh mobile gates PASS: pub get, analyzer (0 errors / 0 warnings / 212 infos), **338/338 tests**, debug APK build. Dashboard TypeScript/lint/production build PASS (24 generated pages), practice/provider tests **13/13**. Local rollback database suite PASS **8 files / 18 assertions**, plus all-20 raw mission replay and four sequential quiz-completion checks.
- The implementation was previously fast-forwarded from `Dro-branch` to `new`, preserving feature commit `64dcbac`. Branch `new` tracks `bytequest-project/new` at `https://github.com/vincee08/bytequest-project.git`. Preserve the user's untracked PDF and dashboard `package-lock.json`.
- Full hosted learner mission/quiz completion, independent TalkBack/device-matrix acceptance and successful live AI generation remain separate checks. Do not repeat completed implementation work or bypass progression to award completion.

## Current continuation - 2026-10-09

- Read the full seven-page supplied `Computer-Systems-Servicing-NC-II_copy.pdf`: TESDA Self-Assessment Guide ELCCSS 213-0119, revision 00, 03/01/17. It is not the full Training Regulations or an official scoring rubric. The competency mapping, source hash, deployment configuration and acceptance limits are in `docs/CSS_NC_II_PRACTICE_IMPLEMENTATION_2026-10-09.md`.
- Created local `Dro-branch` from the existing `new` head to follow the standing development-branch rule. No remote push, merge to `main`, hosted migration or production deployment was performed. Preserve the user's untracked PDF and `ByteQuest-Web-Dashboard/package-lock.json`.
- Extended the existing 20 practice work orders and shared engine: real accessible hardware/device drops in COC1-3; server/client/switch placement and Ethernet links; boot media/licensed software/vendor updates; monitored load testing; protected cable route/PVC raceway; secured Wi-Fi/repeater/WAN/firewall settings; server user folders/modules/printer sharing; safety/environmental close-out and reports. COC4 uses no draggable placement or sequencing controls and requires contingency preparation before proceeding; preparation cannot replace inspection/diagnostics.
- Added strict server-owned COC1 -> COC2 -> COC3 -> COC4 progression. A restrictive evidence INSERT policy, route checks, private quiz data, service-only SECURITY INVOKER evaluators and versioned raw-action replay prevent direct completion writes, client snapshot/phase-completion claims, answer-key reads, cross-learner access and stale-test completion. No new SECURITY DEFINER function or official assessment/release rule was introduced. Official progress still loads if the optional practice progression service is unavailable.
- Each COC requires five verified practice missions plus a server-graded five-question quiz with a ByteQuest learning threshold of 80%. Quiz answers persist, failed attempts keep the lock, repeated submission returns the saved result, and completed COCs reopen the successful quiz. These supplementary scores are separate from instructor-released assessment results.
- Added server-only free OpenRouter question variants with a 32-question grounded fallback bank. Only `openrouter/free` or `:free` model selectors are accepted, provider prices are constrained to zero, and trusted choices/keys/explanations/page references stay under server control. Missing credentials, provider failures/quotas/timeouts, malformed output, duplicate stems or changed numeric work-order conditions use the bank. No AI credential is sent to Flutter. New quiz attempts are limited to eight per learner per 24 hours.
- Local Supabase now records **49 migrations**, including `20261009090000_coc_practice_progression.sql` and `20261009091000_css_practice_contracts.sql`, applied in order. Final development refinements were applied only to this disposable local stack. PostgreSQL rollback tests pass **8 files / 17 assertions**; DB lint reports no findings. Independent raw work-order replay verifies all **20/20 missions**, four sequential quiz completions, failed-quiz locks, idempotency, RLS and tampering resistance in a rollback transaction.
- Authenticated local HTTP integration passes anonymous/role checks, locked evidence, five real COC1 work-order verifications, answer-key privacy, saved-answer resume, cross-learner isolation, incomplete submission rejection, failed quiz explanations, 4/5 grading and next-COC-only unlocking. Two disposable QA identities were banned/deactivated with immutable evidence retained. The dedicated port-3006 server was stopped; hosted data was untouched.
- Mobile validation passes dependency resolution, **338/338 Flutter tests**, all-20 real-control work orders, portrait/landscape/2x-text matrices, actual drag gestures, COC4 no-drag checks, quiz resume/explanations, analyzer **0 errors / 0 warnings / 212 infos**, and Android debug APK build. Existing Kotlin plugin migration warnings remain non-blocking. Dashboard TypeScript/lint/production build and **30/30 tests** pass, including five new practice quiz tests.
- A live free-provider probe returned the five-question fallback bank with trusted keys preserved. Successful live AI generation is not claimed. `adb devices` reports no attached Android device; new device/TalkBack/performance acceptance remains unverified.
- Activation requires deploying `/api/learner/practice`, applying only the two reviewed new migrations to the hosted project after reconciling its divergent migration history, and setting the mobile public `PRACTICE_API_URL` or `BQ_PRACTICE_API_URL` build define. Server Supabase/AI secrets remain server-only. Do not blindly replay the repository foundation on hosted Supabase or claim these features are already deployed.

## Current continuation - 2026-09-29

- Branch `new` tracks `bytequest-project/new`; the previous published head was `51eb0a1162011593de162d4ae78dec74961c0a97`. The original `origin` and `main` remain untouched.
- Fixed the Vercel `/_not-found` prerender failure caused by `AuthProvider` constructing the browser Supabase client during server rendering. Supabase initialization now occurs inside browser effects/profile actions; public fallback pages can prerender without configuration, while middleware and server auth boundaries continue to fail closed.
- Login client construction now occurs inside the existing error boundary so a missing deployment configuration produces a handled form error instead of an unhandled event failure.
- Added `tests/auth-provider-prerender.test.tsx`, which removes all supported public Supabase variables and verifies server rendering of `AuthProvider`. Web tests pass **25/25**; TypeScript and Next lint pass; production builds pass both without `.env.local` (23/23 static pages, including `/_not-found`) and with the local environment restored.
- A functional Vercel deployment still requires `NEXT_PUBLIC_SUPABASE_URL` plus `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` or `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel before rebuilding. Server-side administrative operations also require the server-only `SUPABASE_SERVICE_ROLE_KEY`; never expose it with a `NEXT_PUBLIC_` prefix.
- Vercel production logs confirmed corrected commit `d086d4b` passed all 23 prerendered pages. The exact Supabase prerender failure came from an out-of-order deployment of older commit `51eb0a1`.
- Added the existing local Supabase URL and publishable key to Vercel Production/Preview/Development and stored the service-role value as a Vercel Secret. Values remain untracked and were not printed.
- Vercel then exposed a separate output-packaging failure: the project root `ByteQuest Web Dashboard` caused generated serverless paths such as `ByteQuest Web Dashboard/___next_launcher.cjs`, which Vercel rejects because function names cannot contain spaces. Renamed only that repository directory to `ByteQuest-Web-Dashboard`, updated repository path references, and changed the Vercel project Root Directory accordingly.
- After the directory correction, dashboard TypeScript, Next lint, all **25/25** focused tests, and `next build` pass. Commit `257c038` deployed successfully as Vercel production deployment `dpl_AwuwSRp9ApT6x8TcEnbo3L2rCMcC` with status **Ready**. Protected live checks verified `/` returns `307` to `/login` and `/login` returns `200`. Do not revert the directory name while the linked Vercel project uses `ByteQuest-Web-Dashboard`.

## Current continuation — 2026-09-28

This section supersedes the 2026-09-27 continuation below. The current branch remains `new`, based on `3d095aa2abf35acb305a067c571024b9945b64fe`. The worktree contains mixed pre-existing/user work; do not reset it, stage everything, push, or alter hosted Supabase.

- Principal-PDF reconciliation is complete in the verified local scope: **274/290 implemented, 16 partial acceptance, 0 broken, 0 non-compliant, 0 missing, 0 unknown, 0 blocked**. See `docs/BYTEQUEST_REMEDIATION_FINAL_VERIFICATION_2026-09-28.md` and the item-level `docs/BYTEQUEST_REMEDIATION_TRACEABILITY_2026-09-27.md`.
- The shared practice-only equipment simulation, 20 typed work orders, state-driven technical scenes, structured evidence, review/return/confirm flow and exact resume model are implemented. Do not move scoring/release authority into Flutter.
- COC1 M3 practice follows the PDF installation/configuration workflow. The separate `coc1-m3-installation-pdf-review-v1` package is review-only and non-publishable; `coc1-m3-authoritative-v1` and historical results are preserved. Instructor/security review and trusted-state mapping are required before any future publication.
- Final mobile gates after the compact-landscape repair: `flutter test` **333/333 PASS**; analyzer **0 errors, 0 warnings, 207 infos**; debug APK build PASS. Future Kotlin floor warning is non-blocking but should be scheduled separately.
- Android API 35 combined evidence covers all 20 real-UI save/process-restart workflows. One complete run passed 20/20 saves and 18/20 resumes; after fixing keyboard/scroll tap interception, COC2 M5 and COC4 M3 each passed complete isolated save/resume device runs. Do not describe this as one monolithic post-fix 20/20 rerun.
- Exact Android restoration assertions cover attempt, phase, accepted evidence, configuration, connections, placement and equipment state, plus no duplicate server evidence and no premature official evaluation. The test-completion/evidence-write race is fixed and regression-tested.
- Local unchanged published assessment packages pass all-20 trusted lifecycle, evaluation, idempotency, role/finalization/release and realtime/isolation checks. PostgreSQL rollback suite passes 7 files / 10 tests; DB lint has no schema errors. Dashboard type-check/lint/build passed earlier in the same remediation session.
- A compact 640x360 device run reproduced a 7.3 px COC1 M3 interpretation overflow. The mission layout now uses side-by-side controls from 600 dp in landscape; all mission phases pass 640x360 with 2x text, and the live failing action reran without overflow. The AVD then exited before completing resume, so device-matrix acceptance remains partial rather than being overstated.
- Sixteen retained disposable local Android QA identities were disabled while preserving evidence. No hosted database, remote branch or published package was changed.
- Remaining acceptance packages only: a second Android profile/on-device rotation; TalkBack and independent visual/PDF scorecard review; official assessment submit UI on Android; paired hosted Learner submit → Instructor review/release → Learner result UI. Reproduce a failure before changing working code.
- No commit was created because the worktree includes unrelated and pre-existing changes. The dedicated API 35 emulator was stopped after inspection.
- 2026-09-28 login run follow-up: the ignored mobile `.env` hosted project hostname returns public DNS NXDOMAIN, and Android logs reproduced `Failed host lookup`; this is not a credential rejection. `SupabaseConfig` now accepts `BQ_SUPABASE_URL` / `BQ_SUPABASE_ANON_KEY` build-time overrides before falling back to `.env`. The visible API 35 app was rebuilt against local Supabase at emulator host `10.0.2.2:57321`, initialized successfully, and remains foreground. Local signup is enabled with confirmations disabled; hosted accounts still require the correct active project URL. Focused `dart analyze lib/core/config/supabase_config.dart` passes with no issues. No key was printed or written into tracked source.
- The current dashboard dev server is running at `http://127.0.0.1:3000` against the same local Supabase stack and its login page returns 200. At the user's request, an existing matching local identity was safely reactivated as an active Instructor, its temporary password was reset and login/profile authorization was verified. The credential is intentionally not stored in repository documentation. Hosted Supabase was not contacted or changed.

## Current continuation — 2026-09-27

This section supersedes older completion claims below. The current branch is `new`, based on `3d095aa2abf35acb305a067c571024b9945b64fe`. The worktree contains unrelated user changes; do not reset it, stage everything, or push.

- User authorized remediation of the principal PDF audit's 171 open rows (120 partial, 3 broken, 7 non-compliant, 14 missing, 7 unknown, 20 blocked). Frozen baseline remains 290 requirements / 119 implemented. Do not treat all open rows as closed.
- Added a shared **practice-only** equipment simulator, action-derived readings, stale-test invalidation, physical compatibility/orientation/sequence constraints, real settings and corrective operations across 20 practice missions, classification, measured tool observations, camera persistence and return-to-phase corrections. Existing backend evaluation rules and the COC2 golden contract remain unchanged.
- COC1 M3 practice now simulates OS installation, drivers, restart and verification. On 2026-09-23 the user explicitly chose a separate reviewable assessment package. `docs/COC1_M3_INSTALLATION_ASSESSMENT_REVIEW_DRAFT.md` and `scripts/assessment-drafts/` contain the **unpublished, unapproved** proposal; legacy cabling package/history are preserved. Four draft-isolation/answer-leak tests passed. Trusted-state assessment mapping and instructor approval are still required before publication.
- Latest completed full Flutter run: **329 tests passed**. Subsequent focused equipment run: **62 passed**, including the newest COC1 M5 tool prerequisite and COC4 M5 priority consequences. A full final rerun must include these latest edits.
- All 20 real-control widget work orders passed. Every real phase passed compact portrait/landscape rendering at 320×568 and 800×360 with 2× text. These are widget results, not a TalkBack or Android-device acceptance claim.
- Latest completed analysis: **0 errors, 0 warnings, 209 infos**. Debug APK build passed, with SDK XML and future Kotlin migration warnings. Dashboard type-check, lint and production build passed. Local DB rollback tests: 7 files / 10 tests pass; DB lint reports no schema errors.
- Local-only authenticated lifecycle suites passed for the unchanged 20 published assessment packages, including golden COC2; local authenticated realtime/isolation suite passed. No hosted database was changed. Test fixtures were retired without deleting immutable history.
- Android AOSP API 35 image is now installed with its official SHA1 verified (`2D857D170C0D1B827149565DA34B3383E5306F7F`). Dedicated `ByteQuest_QA_API35` emulator is booted on `emulator-5554`. The previous attempt to launch the real-UI suite was interrupted; it is being rerun on 2026-09-27. **No successful Android lifecycle result is claimed yet.**
- `scripts/android-mission-runtime-e2e.ps1` creates a disposable LOCAL-only learner, invokes 20 save + 20 resume workflows across a process stop, checks database evidence idempotency/no official practice evaluation, and retires the fixture. `integration_test/mission_runtime_local_e2e_test.dart` captures screenshots in the app cache. Logs are in `%TEMP%/bytequest-android-runtime-e2e.log`; avoid printing credential-bearing process arguments.
- Still needed: finish Android suite, inspect screenshots/accessibility, reconcile all 171 RTM rows individually with scoped evidence, update scorecard honestly, run final gates and commit only scoped work. The current progress document is `docs/BYTEQUEST_REMEDIATION_PROGRESS_2026-09-22.md`.
- Local Flutter path: `C:/Users/HP/Tools/flutter/bin/flutter.bat`; JDK: `C:/Users/HP/Documents/Tools/jdk-17.0.20.1+1`. Set process-local `FLUTTER_WINDOWS=false` for Android validation to avoid unused desktop-plugin symlink requirements; no global Developer Mode changes were made.

## Snapshot

| Field | Value |
|---|---|
| Date | 2026-09-16 |
| Active branch | `new` (local audit/fix branch; nothing pushed) |
| Integrated implementation head | Working session based directly on `origin/main` `5b4aa3d7dcffccfee7dc0336fad90df19ca36891` |
| Remote | `origin/main` remains `5b4aa3d7dcffccfee7dc0336fad90df19ca36891`; no remote branch was changed |
| Primary build target | Android APK (Flutter) |
| Feature worktree | `.worktrees/bytequest-simulation-platform` preserved on `feature/bytequest-simulation-platform` |

## Completed implementation

### Simulation platform

- [x] Responsive reusable 2D scene engine with pan/zoom/reset, landscape support, scene-coordinate scaling, hotspots, connection painter, and object-list alternative.
- [x] Hotspot states: neutral, selected, completed, and error; minimum 48 × 48 dp targets and semantics.
- [x] Tool tray with compatibility checks and structured evidence.
- [x] Fourteen reusable interaction families: inspect, multi-select, tool, connect, configure, sequence, match, controlled placement, troubleshoot, test run, observe, decide, interpret, and evidence review.
- [x] State-driven connection, device, placement, test, and completion transitions with reduced-motion support.
- [x] Explicit review/return/confirm flow with terminal submission latch and pending-evidence retry.

### Twenty-mission catalog

- [x] COC1 M1–M5.
- [x] COC2 M1–M5; protected cable evaluator route retained.
- [x] COC3 M1–M5.
- [x] COC4 M1–M5.
- [x] Exactly 20 stable IDs (`coc1_m1` through `coc4_m5`).
- [x] 116/116 catalog phases render without `TechnicalUnavailableState`.
- [x] Every mission resolves to 2–4 actual rendered interaction families, a real technical decision, and observation/test/verification.
- [x] No mission is drag-drop-only.
- [x] Progressive troubleshooting facts, correction gates, stable retest IDs, and source-linked interpretation are enforced.

### Evidence, persistence, and authority

- [x] Immutable structured evidence actions with stable client IDs and serialized dispatch.
- [x] Assigned assessments retain the authoritative attempt-action gateway.
- [x] Standalone practice evidence uses learner-owned `practice_mission_actions`, active-learner RLS, ownership checks, append-only grants, and idempotent action keys.
- [x] Runtime restore rebuilds state from ordered acknowledged server actions, merges/de-duplicates pending local actions, and preserves local presentation preferences offline.
- [x] Practice and assessment storage are isolated by mode and assessment attempt ID.
- [x] Unknown restored phases fail closed; rejected placements never render success.
- [x] Test start and terminal completion use distinct evidence types; configured evaluator actions occur only on terminal events.
- [x] Supabase/PostgreSQL remains the evaluation authority. Flutter does not calculate score/pass/reward/release, and instructor release remains mandatory.

### Accessibility and quality

- [x] Tap alternatives for drag/connection interactions.
- [x] Semantics and 48 dp minimum targets across enabled interaction states.
- [x] Compact, landscape, 2× text, and reduced-motion widget matrices.
- [x] ByteQuest navy/blue tokens and 150–250 ms state transitions.
- [x] Four showcase candidates: COC1 M3, COC2 M3, COC3 M4, COC4 M5.

## Verification results

Fresh integrated `Dro-branch` evidence:

```text
flutter test                     PASS — 189/189
flutter analyze --no-fatal-infos PASS — 0 errors, 0 warnings, 213 infos
flutter build apk --debug        PASS
catalog phase render gate        PASS — 116/116, 0 unavailable
focused final acceptance gate    PASS — 100/100
static SQL/lifecycle sentinels   PASS — 8/8
whole-branch review              PASS — no Critical/High/Medium findings
```

APK location (ignored): `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk`; integrated size 195,186,392 bytes; SHA-256 `CE1663F11351B08461719AC4AA9284C251B0DF5346C320618B95A77D9F985410`.

## Durable evidence

- `docs/BYTEQUEST_20_MISSION_SCORECARD.md` — provisional mission-level scores and evidence limits.
- `docs/BYTEQUEST_EMULATOR_QA.md` — Android 16 device metadata and shell/lifecycle QA.
- `docs/BYTEQUEST_SIMULATION_COMPLETION_REPORT.md` — implementation coverage and external blockers.
- `docs/BYTEQUEST_IMPLEMENTATION_FAILURES.md` — timestamped failed operations, causes, fixes, and alternatives.
- `docs/BYTEQUEST_IMPLEMENTATION_FAILURE_INDEX.md` — anchored index of every failure entry.
- `supabase/migrations/20260822124500_practice_mission_evidence.sql` — practice evidence schema/RLS migration.

## External checks still unverified

- Authenticated execution of all 20 missions on the emulator. The APK reached onboarding/login and passed portrait, landscape, 2× text, reduced-motion, background/resume, and force-stop/relaunch checks, but no authorized disposable learner credentials were available.
- `pnpm test:all-missions` and `pnpm test:realtime`. The gitignored dashboard `.env.local` and `BYTEQUEST_E2E_PASSWORD` were unavailable, so both stopped before contacting Supabase.
- Live application of the new migration and rollback lifecycle SQL. Static security/lifecycle assertions pass, but no prepared local/live database connection was authorized.

## QA audit (2026-08-22)

- Added `QA_REPORT.md` after a read-only senior QA pass; no product code was changed during the audit.
- Confirmed startup, onboarding, login navigation, invalid-auth handling, offline cold start, force-stop/relaunch, static analysis, automated tests, and debug APK build.
- Prioritized findings: uncaught missing-Supabase-config startup failure (P1), first-frame/auth jank (P2), and future schematic metadata paths with no bundled assets (P3).
- Authenticated mission/evidence/scoring/realtime checks remain blocked because the supplied learner credentials were rejected by Supabase as invalid; this is recorded as a test-environment limitation in `QA_REPORT.md`.

## Practice regression fixes (2026-08-22)

- Issue found: the shared runtime scene rendered every hotspot as an icon. Existing component PNGs were still present and declared in `pubspec.yaml`, but the catalog's image references were unused metadata; COC3/COC4 had track artwork in `assets/images/` but no scene background binding.
- Fix applied: mission definitions now bind existing COC1/COC2 component assets (and COC3/COC4 track artwork) to every runtime scene object, while the shared hotspot and scene background render those assets with an error fallback. No mission interaction architecture was changed.
- Issue found: `MissionSimulationScreen.initState()` called `requestLandscape()` on every practice entry.
- Fix applied: removed the entry-time landscape request. The app-wide orientation allow-list remains portrait and landscape, so portrait is retained on entry and physical rotation remains natural; exit still restores the supported allow-list.
- Regression coverage: updated the mission orientation widget test and added a catalog-wide visual-asset test covering all 20 missions.
- Validation: `flutter analyze --no-fatal-infos` completed with 0 errors (214 existing informational findings); full `flutter test` passed (191 tests); and `flutter build apk --debug` produced `build/app/outputs/flutter-apk/app-debug.apk`.
- Emulator smoke check: installed the debug APK on `emulator-5554`, launched it, and confirmed the default display remained portrait (`320x640`, rotation `0`). The catalog-wide test covers all 20 mission definitions and their image bindings; interactive manual traversal was not repeated because the app remained at its startup/auth gate in this smoke session.

## Image pipeline follow-up (2026-08-22)

- Root cause confirmed: `MissionContentData.getCOC1M1Items()` had the correct motherboard path (`assets/COC1/Mission 1/motherboard.png`), the file exists, and `pubspec.yaml` registers `assets/COC1/Mission 1/`. However, practice launches `MissionSimulationScreen`; its `TapInspectInteraction` consumed presentation objects that carried labels/IDs only, so the image path stopped between content data and the UI. The previous scene-only metadata binding did not populate those inspection cards.
- A second audit caught one invalid fallback mapping (`assets/COC1/Mission 1/empty_system_unit_case.png`); the file is actually under Mission 2. It was replaced with the existing `assets/COC1/Mission 3/System Unit.png` asset.
- Fix applied: mission presentation objects now receive `imageAsset` metadata, `TapInspectInteraction` renders the asset with `Image.asset`, and visible error builders plus temporary `[ByteQuest image]` path/existence/error logging expose failures instead of silently showing a blank fallback. Scene hotspots and workspace artwork retain the same diagnostics.
- Validation: motherboard, CPU, RAM, PSU, and anti-static strap paths logged as existing through Flutter's asset bundle; the catalog-wide asset-bundle test passed for all COC1–COC4 mission scene assets; targeted scene tests passed (10 tests). Full analyze/test/build should be rerun after this follow-up patch.
- Failed operation: 2026-08-22 15:42 +08:00, first targeted `flutter test` attempt hit a Flutter test-cache `PathExistsException` at `build/test_cache/...cache.dill.track.dill` (transient concurrent cache write). Re-running after the cache settled passed; alternative resolution is to stop competing Flutter/Dart processes and clear only the generated `build/test_cache` directory before rerunning.

Do not weaken authentication, RLS, backend evaluation, or instructor-release controls to bypass these evidence gaps. Close them in an authorized test environment with disposable learner/instructor credentials and protected secrets.

## Targeted image propagation follow-up (2026-08-22)

- Root cause refinement: inspect phases without an explicit `objects` list fell back to bare IDs in `interactionItems`, dropping `description` and `imageAsset` before `TapInspectInteraction`.
- Fix applied: `InteractionItem` now carries typed `id`, `label`, `description`, and `imageAsset` fields; mission-definition normalization supplies explicit inspect objects from the mission catalog; `TapInspectInteraction` passes those fields into the shared `_InspectionImage`, which renders with `Image.asset`.
- Validation: targeted scene/screen tests passed (37 tests); COC1 M1 motherboard, CPU, RAM, PSU, and anti-static strap paths logged as existing; COC1 M2 fallback inspect objects logged bundled paths; catalog asset-bundle coverage passed; full `flutter test` passed (191 tests); `flutter analyze --no-fatal-infos` passed with 0 errors and 214 informational findings; `flutter build apk --debug` passed and produced `build/app/outputs/flutter-apk/app-debug.apk`.

## Inspection image layout follow-up (2026-08-22)

- Issue found: Flutter's renderer reported `Width is zero. 0,0` during emulator startup. The image asset pipeline itself was healthy; `_InspectionImage` had only a fixed height and relied on an upstream width that could be zero during an unconstrained frame.
- Fix applied: `_InspectionImage` now logs MediaQuery size, parent constraints, and final widget dimensions. It resolves a positive bounded width from its parent constraints, falling back to the current MediaQuery width when the parent reports zero/unbounded width, then passes explicit width and height to `Image.asset`.
- Validation: `flutter test test/mission_simulation_screen_test.dart` passed (27 tests); logs showed COC1 M1 images receiving 287.6x120 constraints and assets resolving. `flutter test` previously passed (191 tests). `flutter run -d emulator-5554 --debug` built, installed, and launched successfully; the remaining zero-width logs occurred before viewport metrics during startup, not in `_InspectionImage` layout logs. The account session was at the app gate, so direct COC1 M1 visual traversal remains pending.

## Technical workspace hotspot image fix (2026-08-22)

- Issue found: `HotspotWidget` did receive the correct COC1 M1 metadata and called `Image.asset`, but its default loose `Stack` sized itself from the 24dp state icon. The `Positioned.fill` image therefore rendered inside an icon-sized stack, appearing as an empty/tiny placeholder in the workspace.
- Fix applied: set the shared hotspot `Stack` to `StackFit.expand`, so workspace images fill the mapped hotspot bounds while preserving the existing icon/state overlay and interaction behavior. Added temporary workspace logs for object ID, label, image path, asset-call branch, and asset-bundle existence.
- Validation: live COC1 M1 emulator logs confirmed motherboard, CPU, RAM, PSU, and anti-static strap image branches and existing assets; hot-reloaded emulator screenshot visibly showed all five workspace images. `flutter analyze --no-fatal-infos` passed with 0 errors and 214 informational findings; full `flutter test` passed (191 tests).

## Phase 9 compliance audit (2026-08-22)

- Branch: `Dro-branch`; no commit was created for this audit.
- Completed: read `bytequest.md`/`README.md`; statically audited all 20 COC1–COC4 mission definitions, learning-loop coverage, interaction families, evidence/persistence contracts, accessibility gates, assessment safeguards, and reusable simulation systems.
- Validation: `flutter test` passed (191); `flutter analyze --no-fatal-infos` passed with 0 errors and 214 informational findings; `flutter build apk --debug` passed. Emulator practice shell launched and COC1 M1 was opened; workspace images were visible.
- Audit result: 90% structural to-do compliance (270/300 Phase 1 checklist points). All 20 missions satisfy static phase-count/family/decision/verification/review gates, but the broad literal loop is partial for missions that intentionally omit configuration or troubleshooting.
- Remaining risks: full manual COC1 M1–M5 and COC2–COC4 M1–M5 traversal was not completed; authenticated Supabase evidence writes/reconciliation, backend evaluation, realtime instructor receipt/release, learner result propagation, and process-death/offline reconnect remain unverified. COC3/COC4 scene visuals remain generic schematic/track artwork. Startup jank and missing Supabase-config fail-closed behavior remain documented QA findings.
- Next action: provision disposable learner/instructor fixtures, execute the 20-mission manual/runtime/backend acceptance matrix, capture evidence, then rerun QA_REPORT.md before any release decision.

## Phase 10 release validation (2026-08-22)

- Branch: `Dro-branch`. No Phase 10 commit or push was made.
- Automated gates: `flutter test` passed (191 tests); `flutter analyze --no-fatal-infos` passed with 0 errors and 214 informational findings; `flutter build apk --debug` passed.
- Emulator validation: entered Learn → Practice. COC1 M1–M5 launch checks were performed (M1/M2/M3/M5 visual captures; M4 launch returned to the catalog before capture). COC2 was only partially traversed. A saved-progress restore failure was reproduced while attempting a COC2 mission: retry/reset screen appeared, and reset allowed the mission to launch (BQ-P10-001). COC3 and COC4 were not reached in this pass.
- Backend validation: static code mapping confirms practice evidence upsert/reconciliation, authoritative attempt submission/evaluation, instructor release, and learner realtime listeners. A live learner → instructor → release → learner run was not completed because no disposable instructor fixture/authorized assessment account was available.
- Reliability/visual gaps: process-death resume, offline/reconnect synchronization, duplicate-evidence check, full submission/evaluation/realtime flow, and all-20 manual interaction checks remain unverified. COC3/COC4 visual quality remains an open audit area.
- Release status: **NO-GO** pending isolation/fix of BQ-P10-001, an authorized backend lifecycle fixture, and complete COC1–COC4 manual traversal.
- Exact next action: preserve the original restore exception in `MissionRuntimeController.restore()`, classify the failing snapshot/reconciliation condition, then rerun all 20 missions plus process-death/offline and instructor-release acceptance checks in a disposable Supabase test environment.

## Phase 10.1 — BQ-P10-001 restore fix (2026-08-22)

- Current branch: `Dro-branch`; no commit or push made.
- Root cause: authoritative assessment restore reads the full active-attempt action timeline. `MissionRuntimeController.restore()` replayed actions from other missions through the active mission reducer; COC2 M1 evidence therefore caused the COC2 M5 reducer to throw `FormatException`, which the screen previously hid behind a generic restore message.
- Fix: filter acknowledged actions by the active mission ID before reducer replay/reconciliation. Added structured restore diagnostics (mission ID, runtime schema version, snapshot timestamp, phase, evidence/pending counts, sync state, exception and stack trace). Local snapshot load and screen restore boundaries now retain stack diagnostics without deleting or resetting data.
- Regression coverage: added `restore ignores acknowledged actions from other missions`; it failed before the fix with the exact cross-mission `FormatException` and passes after the fix.
- Validation: `flutter test` passed (192 tests); `flutter analyze --no-fatal-infos` passed with 0 errors and 214 informational findings; `flutter build apk --debug` passed.
- Remaining risks: live authenticated COC2 M5 exit/reopen validation and full Supabase lifecycle still require a disposable authorized learner/instructor fixture. Existing Phase 10 risks BQ-P10-002 and BQ-QA-001/002/003 remain.
- Exact next action: install the new APK in an authorized session, create COC2 M5 progress, exit/reopen to verify the runtime snapshot and server reconciliation visually, then rerun the Phase 10 all-mission/backend release gate.

## Phase 10.2 — Live restore and release validation (2026-08-22)

- APK validation: latest debug APK installed and launched on `emulator-5554`.
- Live restore: COC2 M5 first showed the deployed-backend failure with no local snapshot. After an intentional reset and one diagnostic action, force-stop/relaunch plus reopening COC2 M5 restored the same local phase/evidence without a restore-error screen. Diagnostics identified `PGRST205`: `public.practice_mission_actions` is missing from the Supabase schema cache.
- Cross-mission isolation: controller regression test passes; local mission keys are isolated. Full live multi-mission proof remains blocked by the missing practice table.
- New findings: BQ-P10.2-001 (P1, missing deployed practice evidence table) and BQ-P10.2-002 (P2, process death returns to home instead of prior mission route; saved mission state is recoverable by reopening the mission).
- Manual smoke: COC2 M5 was launched and restored in the emulator. Full interaction traversal for every COC1–COC4 mission was not completed; COC3/COC4 were not reached in this pass.
- Backend/security: live learner → instructor → release → learner lifecycle was blocked by the missing table and lack of an instructor fixture. Static RLS, authoritative RPC, realtime, and key-exposure review found no new client security issue.
- Release status: **NO-GO** until the Supabase migration/schema cache is applied and the complete all-20 plus backend lifecycle run is completed.
- Exact next action: apply/verify `20260822124500_practice_mission_evidence.sql` in the authorized Supabase project, refresh PostgREST schema cache, then rerun practice evidence sync, live multi-mission restore, all 20 mission smoke checks, and instructor release verification.

## Supabase foundation schema repair (2026-08-23)

- Branch: `Dro-branch`.
- Added `supabase/migrations/20260807000000_initial_schema.sql` only; all existing incremental migrations remain unchanged.
- Baseline coverage: account/user enums, profiles and Auth trigger, catalog identity tables, legacy simulation/criteria/result/progress tables, gamification/settings/notification/report/log tables, timestamp trigger, compatibility helpers, indexes, and RLS enablement required by later migrations.
- Dependency audit source: every file in `supabase/migrations` plus `docs/CHECKPOINT_A_COLUMN_INVENTORY.md`; no seed rows or simplified replacements were added.
- Validation: `supabase db push --linked --include-all --yes` passed all 37 migrations sequentially. `supabase migration list --linked` shows local/remote parity through `20260822124500`. Linked queries confirmed foundation tables, enums, and compatibility functions.
- Local validation: `supabase db reset --local --no-seed --yes` is blocked because Docker/Podman is not installed (`LegacyLocalDbRunningError`); no local migration execution was possible.
- Remaining task: install/start Docker Desktop or Podman and rerun local `supabase db reset --local --no-seed --yes` plus `supabase db push --local` to complete local-engine verification.

## Known non-blocking maintenance

- Analyzer informational notices remain, primarily `prefer_const_constructors`, deprecated `.withOpacity`, and existing async-context notices.
- Android build warns that Kotlin 2.2.20 and legacy Kotlin Gradle Plugin application will require future migration; `shared_preferences_android` also applies KGP.
- Android SDK XML tooling versions are mismatched but do not block the current debug build.
- Code-drawn schematic scenes are approved placeholders; replace them with production art later without changing scene/evidence contracts.

## Git handoff

- Reviewed feature commits were transplanted locally onto `Dro-branch`; duplicate rename commit `7878107` was intentionally skipped because `Dro-branch` already contained the canonical `ByteQuest-Mobile-App` rename.
- `main` was not modified.
- Nothing was pushed.
- The feature branch/worktree is preserved for audit and must not be deleted without explicit authorization.

## Project checkpoint (2026-08-22 16:44 +08:00)

- Current branch: `Dro-branch`.
- Current worktree: uncommitted implementation changes are present; pre-existing `bytequest.md` edits and `QA_REPORT.md` remain preserved. No commit or push was made.
- Completed work:
  - Traced the COC1 M1 motherboard image from `MissionContentData` through mission definitions, presentation metadata, and the shared inspection/hotspot renderers.
  - Restored image delivery to practice inspection cards and scene hotspots using existing bundled assets.
  - Removed automatic landscape entry behavior while retaining natural device rotation and exit orientation restoration.
  - Added visible image error states and temporary asset path/existence diagnostics.
  - Added catalog-wide image-path and COC1 M1 motherboard regression coverage.
- Files changed by this work:
  - `ByteQuest-Mobile-App/lib/data/mission_simulation_definitions.dart`
  - `ByteQuest-Mobile-App/lib/screens/simulation/components/hotspot_widget.dart`
  - `ByteQuest-Mobile-App/lib/screens/simulation/components/simulation_scene.dart`
  - `ByteQuest-Mobile-App/lib/screens/simulation/interactions/tap_inspect_interaction.dart`
  - `ByteQuest-Mobile-App/lib/screens/simulation/mission_simulation_screen.dart`
  - `ByteQuest-Mobile-App/test/mission_simulation_screen_test.dart`
  - `ByteQuest-Mobile-App/test/simulation_scene_test.dart`
  - `CODEX_STATE.md`
- Validation results:
  - `flutter analyze --no-fatal-infos`: PASS, 0 errors; 214 existing informational findings.
  - `flutter test`: PASS, 191 tests.
  - `flutter build apk --debug`: PASS; APK generated at `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk`.
  - Flutter asset-bundle audit: PASS for all catalog COC1–COC4 scene assets; COC1 M1 motherboard, CPU, RAM, PSU, and anti-static strap paths logged as present.
  - `git diff --check`: PASS.
  - Emulator smoke: debug APK installed on `emulator-5554`; portrait launch confirmed. Full practice traversal was unavailable because the current emulator session showed no assigned/unlocked practice activities.
- Remaining tasks:
  - Review the uncommitted diff and approve the image/orientation changes before committing.
  - Repeat direct emulator traversal of COC1 M1–M5 and COC2–COC4 M1–M5 once practice activities are available in the account/session; confirm visual appearance, rotation, and exit behavior.
  - Decide whether temporary `[ByteQuest image]` diagnostics should be removed or retained behind a debug-only flag before release.
  - Resolve previously documented QA/environment blockers (Supabase-authenticated mission run, dashboard E2E/realtime checks, and live migration lifecycle verification) in an authorized environment.
- Exact next steps:
  1. Review `git diff --stat`, `git diff --check`, and the complete diff for scope/regressions.
  2. Install the freshly built APK and unlock/open COC1 M1 in the emulator.
  3. Confirm the motherboard image is visible in the inspection card and scene; inspect logcat for successful asset resolution and absence of error-builder output.
  4. Repeat the same check across all 20 practice missions, including portrait entry, physical rotation, and orientation restoration after exit.
  5. Remove or gate temporary diagnostics if the review approves, rerun analyze/test/build, then request explicit commit approval.

## Supabase cloud/application audit (2026-08-23)

- Branch: `Dro-branch`; audit was read-only. No `db pull`, local reset, commit, or production code change was made.
- Cloud migration history: local and remote match for all 37 migrations through `20260822124500`.
- Verified Flutter integration: `.env` URL + publishable key loading, PKCE/token refresh, auth-state listener, profile-trigger provisioning contract, learner-only sign-in checks, mission projection RPC, practice evidence upsert/read path, and authoritative attempt RPC path.
- Verified linked objects: `practice_mission_actions` exists with expected schema/index; `auth.users` has the profile provisioning trigger; all public base tables have RLS enabled; scoped policies exist for profiles, practice evidence, attempts, progress, results, and releases; mobile-referenced RPCs exist.
- Security finding: linked ACL metadata still grants `authenticated` UPDATE/DELETE/TRUNCATE (and other table privileges) on `practice_mission_actions`, although the migration intends SELECT/INSERT only. RLS prevents ordinary row mutation, but this violates least privilege. Recorded as BQ-QA-004 in `QA_REPORT.md`; follow-up revoke migration is recommended and has not been applied.
- No service-role key or JWT secret was found in committed mobile/dashboard source. Live learner→instructor→release→learner execution remains unverified without disposable authorized fixtures.
- Exact next action: review/approve a narrowly scoped ACL-hardening migration for `practice_mission_actions`, apply it through the normal cloud migration workflow, then rerun the linked privilege/RLS checks and a live authenticated evidence/lifecycle test.

## BQ-QA-004 remediation (2026-08-23)

- Added `supabase/migrations/20260823100000_restrict_practice_evidence_privileges.sql`; existing migrations and Flutter code were not modified.
- Applied successfully with `supabase db push --linked --include-all --yes`.
- Verified linked ACL: `authenticated` retains only SELECT/INSERT on `practice_mission_actions` and sequence USAGE; `anon` has no table/sequence privileges; `service_role` remains functional.
- Verified RLS policies are unchanged: learner-owned SELECT and INSERT policies remain active and scoped by `is_learner()` plus `auth.uid() = learner_id`.
- Verified local/remote migration parity through `20260823100000`.
- BQ-QA-004 status: **Resolved**.
- Remaining task: run a live authenticated practice evidence append/read test with a valid learner fixture; no commit yet.

## Live authenticated evidence validation (2026-08-23)

- A prior authenticated learner smoke test confirmed a learner-scoped active profile. The live user identifier is intentionally not retained in source control.
- Practice evidence validation is blocked by a new deployment issue BQ-QA-005: authenticated REST GET/POST/PATCH/DELETE requests for `practice_mission_actions` return HTTP 404 `PGRST205` (“table not found in schema cache”), despite linked PostgreSQL table, ACL, and RLS metadata being correct. Explicit PostgREST reload notifications did not clear it during this run.
- No evidence row was created, and no update/delete/isolation behavior was bypassed or simulated with an elevated role. Attempt completion/retry/reconnect remains unverified for the same reason.
- No Flutter or migration changes were made during this validation; no commit created.
- Exact next action: refresh/restart the deployed PostgREST schema cache via the Supabase project control plane, then repeat the live learner evidence lifecycle and attempt persistence checks.

## BQ-QA-005 PostgREST exposure investigation (2026-08-23)

- Confirmed exactly one lowercase `public.practice_mission_actions` base table in linked PostgreSQL; migration committed and table is persistent. No alternate schema or casing mismatch exists.
- `public` is exposed: authenticated REST reads of `profiles` and `attempt_actions` return HTTP 200. Only the practice evidence relation is absent from the API schema cache.
- Added and applied `supabase/migrations/20260823110000_reload_postgrest_schema_cache.sql`, containing only `NOTIFY pgrst, 'reload schema'`; also issued direct `NOTIFY` and `pg_notify` calls. REST continued returning PGRST205 after the refresh attempts.
- Finding: managed PostgREST cache/service is stale and not consuming database reload notifications. No Flutter, ACL, RLS, or table changes were made for this investigation.
- Exact next action: restart/invalidate the deployed PostgREST service through the Supabase project control plane/support, then rerun authenticated practice INSERT/read/isolation/update/delete and attempt persistence tests.

## BQ-QA-005 post-restart validation (2026-08-23)

- Restart was reported complete, but a fresh authenticated REST run still returns HTTP 404 `PGRST205` for `practice_mission_actions` INSERT, own SELECT, cross-user SELECT, DELETE, and final read.
- PATCH returned HTTP 400 `PGRST102` from request parsing, not an RLS authorization response; no row was created for mutation verification.
- BQ-QA-005 remains **OPEN / RELEASE BLOCKER**. The endpoint must become reachable before learner evidence isolation and append-only behavior can be validated.
- Exact next action: escalate the managed PostgREST schema-cache issue to Supabase project support/control plane, then repeat the five requested authenticated checks without changing application code.

## BQ-QA-005 deeper metadata comparison (2026-08-23)

- `/rest/v1/` OpenAPI metadata is intentionally unavailable to anon/authenticated clients (`Invalid API key`; service-role-only), but direct comparison proves `profiles` and `attempt_actions` are exposed while `practice_mission_actions` remains PGRST205.
- PostgreSQL confirms all compared relations are lowercase persistent `public` tables owned by `postgres`; practice evidence has the expected authenticated SELECT/INSERT ACL, comment, columns, and RLS. No schema, casing, owner, privilege, or transaction mismatch was found.
- Migration history records the practice table and cache-reload migrations as committed. `supabase/config.toml` exposes `public`; cloud `pgrst.*` settings are not query-visible.
- No safe database migration remains. The `NOTIFY pgrst` migration and service restart were ineffective; BQ-QA-005 is a managed PostgREST cache/platform issue.
- Exact next action: escalate to Supabase control-plane/support with the PGRST205 evidence, then rerun live learner INSERT/SELECT/isolation/append-only checks after cache repair. No Flutter or migration changes are authorized/needed.
-
## BQ-QA-005 live validation rerun (2026-08-23)

- `supabase db push --linked --include-all --yes`: `upToDate=true`; migration history synchronized.
- Public Data API exposure confirmed: `profiles` HTTP 200 and `attempt_actions` HTTP 200.
- Authenticated learner evidence probes all returned HTTP 404 `PGRST205`: INSERT, own SELECT, cross-user SELECT, PATCH, DELETE, and final read.
- No evidence row was created; RLS isolation and append-only enforcement remain untestable because PostgREST cannot resolve the relation.
- BQ-QA-005 remains **OPEN / RELEASE BLOCKER**. Escalate the managed PostgREST schema-cache issue with the exact response codes above; do not modify Flutter, ACLs, RLS, or migrations.

## Mission routing regression fix (2026-08-23)

- Restored legacy/template practice routing before the shared `MissionSimulationScreen` fallback.
- COC1 M1 now uses `IdentificationMissionScreenEnhanced` with `MissionContentData.getCOC1M1Questions()` and `getCOC1M1Items()`. The other 19 mission IDs now route to their intended identification, drag/drop, configuration, procedure, or troubleshooting templates; explicit assessment payload routes remain unchanged.
- Added launcher regression coverage for all 20 mission IDs and a COC1 M1 Motherboard/SSD content contract.
- Validation: focused launcher tests passed; full `flutter test` passed (193 tests); `flutter analyze --no-fatal-infos` passed with 0 errors and 214 informational findings.
- Emulator smoke: updated APK launched on `emulator-5554`; Learn → Practice → COC1 M1 displayed the identification grid with hardware images and the “Tap the correct item” prompt. No shared technical workspace/hotspot screen appeared.
- Note: emulator logs still show existing startup frame skips; unrelated to this routing fix.

## Final release audit after routing restoration (2026-08-23)

- Release decision: **NO-GO**.
- Automated mission routing/content contract: PASS for all 20 mission IDs; COC1 M1 manual emulator smoke matched the reference identification grid and hardware-image prompt.
- Full manual completion/retry traversal of all 20 missions was not completed; automated tests cover routing, interactions, accessibility, responsive layouts, and image contracts but do not replace live mission acceptance.
- `flutter analyze --no-fatal-infos`: PASS, 0 errors, 214 informational findings. `flutter test`: PASS, 193 tests.
- BQ-QA-005 remains OPEN: authenticated REST practice evidence endpoint returns HTTP 404/PGRST205 while `profiles` and `attempt_actions` return HTTP 200. Evidence creation, sync, retry, reconnect, and result propagation remain blocked.
- Exact next action: resolve managed PostgREST exposure for `public.practice_mission_actions`, rerun live evidence lifecycle validation, then complete the all-20 manual mission gate before reconsidering GO.

## Live practice evidence and release lifecycle validation (2026-08-23)

- Branch: `Dro-branch`. No production source, test, or migration file was changed during this validation. Dashboard dependencies were installed from the locked graph into the gitignored `node_modules/` directory only.
- BQ-QA-005 is resolved on the currently linked project: authenticated `practice_mission_actions` INSERT returned HTTP 201; own SELECT returned HTTP 200 with one row; cross-learner SELECT returned HTTP 200 with zero rows; UPDATE and DELETE returned HTTP 403 / PostgreSQL `42501`.
- Duplicate/idempotency behavior passed: a repeated `resolution=ignore-duplicates` request returned HTTP 201 with an empty representation, and the final SELECT still returned exactly one action for the original `client_action_id`.
- Transport-level offline retry/reconnect passed: the first action attempt failed against an unreachable endpoint, reconnect INSERT returned HTTP 201 with one row, repeated retry returned HTTP 201 with zero rows, and final own SELECT returned HTTP 200 with one row (`practice_mission_actions.id=3`).
- Emulator force-close restore passed for COC2 M5 local configuration state. Three stored field values survived process termination (`PID 24999`) and restored after relaunch (`PID 26566`) when the learner reopened the mission. The app returned to Home rather than automatically reopening COC2 M5; the saved mission state remained recoverable.
- Targeted runtime validation passed: `flutter test test/practice_mission_evidence_service_test.dart test/mission_runtime_controller_test.dart test/mission_simulation_screen_test.dart` completed with 45/45 tests, including offline snapshot preservation, pending-action retry, de-duplication, cross-mission isolation, and practice transport failure propagation.
- Confirmed application reachability gap: all 20 practice mission IDs are explicitly routed to legacy templates in `mission_launcher.dart`. `PracticeMissionEvidenceService` is instantiated only by the shared `MissionSimulationScreen` fallback, so no current practice route can originate `practice_mission_actions` evidence through the live UI. Legacy templates retain local resume behavior and call the authoritative assessment recorder, which has no active attempt in practice mode. Live UI-originated evidence retry/reconnect therefore remains unverified and is a release blocker.
- Confirmed authoritative-content blocker: linked counts are zero for `coc_modules`, `missions`, `tesda_sources`, `activity_versions`, `rubric_versions`, `classes`, `assignments`, `attempts`, `attempt_actions`, `score_revisions`, and `result_releases`. The unchanged COC2 lifecycle runner failed at `scripts/authenticated-coc2-lifecycle-e2e.mjs:200` with HTTP/PostgREST `PGRST116` because the required published activity package does not exist. Attempt submission, instructor review/release, and learner result/realtime propagation cannot be exercised until authoritative product content exists.
- Failed credential operation: at 2026-08-23 17:19:56.390 +08:00, the supplied learner credentials were rejected by the currently linked project at `ByteQuest-Mobile-App/lib/services/auth_service.dart:88` and wrapped at line 117 as `Invalid login credentials`. A current-project disposable learner was provisioned instead; it and all lifecycle fixtures were deactivated/banned after testing while immutable evidence rows were retained.
- Failed harness operation: at the start of lifecycle execution, Node could not resolve `@supabase/supabase-js` from `scripts/authenticated-coc2-lifecycle-e2e.mjs:2`. Installing the dashboard's frozen dependency graph and resolving the existing package from memory allowed the unchanged runner to execute. Alternatives are a root test workspace dependency or moving lifecycle runners under the dashboard package boundary.
- Release status remains **NO-GO**. Exact next actions: (1) restore/review authoritative COC1-COC4 content seeds and published rubric/activity packages; (2) connect legacy practice templates to the shared practice evidence runtime without changing their intended interactions; (3) rerun live offline UI evidence sync, attempt submit/instructor release/learner propagation, and all-20 manual completion gates.

## Controlled catalog restoration — Stage 1 (2026-08-23)

- Branch: `Dro-branch`. No commit, push, linked database write, local reset, or remote migration application was performed.
- Added local-only migration `supabase/migrations/20260823130000_seed_bytequest_catalog.sql`.
- Catalog manifest: exactly 4 competencies, 4 published COC modules, and 20 published mission identities (`coc1_m1` through `coc4_m5`); no activity/rubric versions, assignments, attempts, results, or practice evidence are seeded.
- Source fidelity: competency/module codes and titles match `scripts/publish-all-remaining-mission-assessments.mjs`; mission codes, titles, descriptions, interaction types, difficulty labels, and durations match `ByteQuest-Mobile-App/lib/data/missions_data.dart`.
- Safety: all three persistent inserts use `ON CONFLICT DO NOTHING`; post-insert assertions reject conflicting natural-key content without overwriting it. The migration contains no persistent UPDATE, DELETE, or TRUNCATE statement.
- Static validation: PASS — 28/28 manifest rows, 5 missions per COC, exactly three allowed target tables, zero forbidden/destructive statements, valid foundation columns/types/natural keys, final newline, and no trailing whitespace.
- Stage 2 remains unmodified. Exact next action: review the proposed `LegacyPracticeEvidenceScope` architecture and file list, then implement it test-first only after explicit approval.

## Legacy practice evidence integration — Stage 2 (2026-08-23)

- Branch: `Dro-branch`. No commit, push, migration edit, database write, navigation change, layout change, or shared-runtime routing change was made. The untracked Stage 1 catalog migration remains byte-for-byte untouched.
- Added `LegacyPracticeEvidenceScope`, a UI-transparent practice boundary that owns the existing `MissionRuntimeController` + `SharedPreferencesMissionRuntimeStore` + `MissionEvidenceGateway` + `PracticeMissionEvidenceService` pipeline for one authenticated learner and mission.
- All 20 default legacy practice routes are wrapped while retaining the same child screen and content arguments. Explicit authoritative/cable/opt-in assessment payload routes remain unwrapped and continue using authoritative attempt evidence.
- Migrated all 11 existing evidence callback sites across the eight routed legacy template families. Their action types, targets, and value payloads are preserved; stable phase IDs were added at the boundary.
- Practice evidence remains non-authoritative and writes only to `practice_mission_actions`. Stable generated client action IDs are saved locally before transport, retried on reconnect/resume, restored after widget/process recreation, and de-duplicated through the existing gateway/service contracts.
- Test-first evidence: the all-20 route test first failed because COC1 M1 returned `IdentificationMissionScreenEnhanced` directly; the callback-boundary test first failed because legacy templates had zero scope calls. Both passed after the minimal integration.
- Validation: focused Stage 2 tests PASS (9/9); full `flutter test` PASS (197/197); `flutter analyze --no-fatal-infos` PASS with 0 errors, 0 warnings, and 214 existing informational findings; `git diff --check` PASS before this documentation update.
- Failed operation at 2026-08-23 19:52 +08:00: the first analyzer gate reported an unused authoritative-service import at the former `step_procedure_mission_screen.dart:11`. Removing that stale import resolved it; the rerun passed. Alternative: apply the analyzer's targeted unused-import quick fix to that one file.
- Failed operation at 2026-08-23 19:53:20 +08:00: the first narrow patch for the same import did not match because the actual import order differed from the assumed hunk. Re-reading lines 1–16 and applying the exact-context patch succeeded. Alternative: use a one-line exact hunk anchored only on the unused import.
- Failed operation at 2026-08-23 19:56:32 +08:00: the first documentation patch did not match the mojibake-rendered Stage 1 heading. Anchoring the patch to the exact ASCII final line succeeded. Alternative: anchor an append-only patch to another stable ASCII line near end-of-file.
- Remaining validation risk: all 20 routes and all eight callback families are covered automatically, but a fresh authenticated emulator traversal has not yet proven live UI-originated writes/reconnect for every mission. The authoritative activity/rubric lifecycle remains separately blocked until reviewed content packages beyond the Stage 1 catalog exist.
- Exact next action: review the Stage 2 diff, then run a live authenticated practice action from each of the eight legacy template families (covering all 20 route mappings), including offline/reconnect and force-close, before applying Stage 1 or reconsidering release readiness.

## Five-blocker remediation (2026-08-24)

- Branch: `Dro-branch`. No commit, push, navigation redesign, shared-runtime reroute, or Supabase migration change was made for this remediation.
- Step-procedure restore: persisted `completionOrder` and added backward-compatible recovery from legacy `completedSteps` snapshots. COC1 M5, COC2 M3, COC3 M2, and COC4 M2 now retain valid procedure order across process recreation.
- COC1 M4: supplied the two missing validation answers directly from the existing hardware-items and OS-installation-steps content. The three configuration fields can now reach 3/3.
- COC1 M3: compact landscape now prioritizes the existing workspace, cable controls, and finish action without changing the portrait or non-compact layout.
- COC1 M2: the displayed/persisted human step number is clamped to the six-step installation sequence, preventing `Step 7 of 6` after the final placement.
- Auth provisioning: sign-up profile verification now waits for an authenticated session; confirmation-required sign-ups return without querying `profiles`, while session-backed sign-ups retain existing trigger verification and profile updates. RLS and authentication policy are unchanged.
- Targeted regression tests: PASS, 6/6. Full `flutter test`: PASS, 203/203. `flutter analyze --no-fatal-infos`: PASS with 0 errors and 214 informational notices. Debug APK build: PASS.
- Emulator: PASS for COC1 M2 terminal `Step 6 of 6`; COC1 M3 at 640x320 with visible workspace/cable/finish controls and no overflow; COC1 M4 completion at 100%; and restored legacy snapshots for COC1 M5 (10/10), COC2 M3 (4/4), COC3 M2 (8/8), and COC4 M2 (10/10), each completing at 100%. Natural rotation was restored after testing.
- Auth live-account creation was not repeated because it would create an external disposable identity; the production session-null branch is covered by the focused regression test. No remaining defect was found in the five scoped blockers.
- Diagnostic-only failure at 2026-08-24 12:43 +08:00: an emulator log filter used the stale package name `com.bytequest.app`, so PowerShell attempted `.Trim()` on an empty PID at command line 2. Re-running with the installed package `com.example.bytequest` passed with no fatal/overflow logs. Alternatives: resolve the foreground package from `dumpsys` first or guard an empty PID before invoking `logcat`.

## Practice UI/UX revision and scenario restore follow-up (2026-08-25)

- Branch: `Dro-branch`. No commit or push was performed. Supabase, migrations, RLS, evidence transport, scoring, mission routing, and instructor/release lifecycle files remain untouched.
- Shared practice chrome now removes the obsolete fullscreen action, identifies every route with `COC# M#`, and applies progress-aware Exit behavior: no-progress exits immediately, Cancel retains progress, intentional Exit clears only that mission snapshot, and force-close recovery remains intact.
- Identification progress is shown above the prompt; explanations remain learner-paced. Quiz, identification, and troubleshooting choices use deterministic shuffled mappings that survive restoration. Component feedback no longer reflows its workspace. COC2 M2 uses pins above a responsive 2x4 portrait / 4x2 landscape option grid.
- Resume validation found one release-blocking omission in `troubleshooting_mission_screen.dart`: snapshots persisted the shuffled order and score but not `selectedCause` or `hasAnswered`, so COC4 M3 reopened a submitted answer as unanswered. A test-first narrow fix now persists and restores both fields with backward-compatible defaults.
- Automated validation: focused UI/restoration suite PASS (49/49); full `flutter test` PASS (241/241); `flutter analyze --no-fatal-infos` PASS with 0 errors, 0 warnings, and 206 informational notices; debug APK build/install PASS; `git diff --check` PASS.
- Emulator validation: all 20 routes previously launched with correct identifiers. Tests A-C passed. Fresh COC4 M3 proof now confirms the same shuffled order, selected answer, explanation, and `Next Scenario` control after force-stop/relaunch; intentional Exit then cleared the test snapshot.
- Failed operation at 2026-08-25 21:55 +08:00: the first new regression-test run failed to compile because `dart:convert` was appended after declarations at former `practice_ui_revision_test.dart:356`. Moving the directive to the import block exposed the intended behavioral failure. Alternative: apply import and test-body patches as separate exact-context hunks.
- Failed operation at 2026-08-25 21:57 +08:00: test cleanup using `signOut(scope: SignOutScope.local)` removed the local fake session but the mocked endpoint returned HTTP 400. Catching the expected `AuthException` after the local removal kept cleanup deterministic. Alternative: place the authenticated restoration test last in the file and avoid explicit sign-out.
- Remaining non-blocking item: 206 analyzer informational suggestions, primarily deprecated `withOpacity` calls and optional `const` constructors. No scoped release blocker remains from this UI/UX revision.

## Dro-branch integration into main (2026-09-07)

- Git: created local safety branch `backup/main-before-dro-merge`; merged `Dro-branch` (`10adcbda9eacdcd36174df3ecaa26a21832109a3`) into `main` from `a162ecf767e9ce32a0749bfe6aa772d2d5f80acd` using a no-fast-forward merge (`d7cf313466826d15acac0d3295891b2d6b34dda6`). Git reported no textual conflicts. Nothing was pushed.
- Mission routing: all 20 normal mission IDs intentionally use the typed `MissionSimulationScreen` and typed catalog definitions. Server-issued `authoritative_mission_v1` payloads use `AuthoritativeMissionAssessmentScreen`; COC2 M2's `coc2_cable_termination` payload retains its dedicated golden assessment screen. Unknown IDs/templates fail closed. Routing tests cover the exact 20-ID set and all adapters.
- Mission integrity: preserved 4 COCs, 20 mission packages, 98 criteria, and 20 approved rubric packages. All COC4 definitions retain progressive Inspect -> Diagnose -> Test -> Interpret -> Repair/Configure -> Retest -> Verify content, including the complete COC4 M5 thermal-maintenance scenario. Practice mode never invokes authoritative final scoring.
- Persistence/UI: system back and visible exit share a save-and-exit path; failed persistence keeps the mission open; practice completion saves evidence without awarding competency. Dead callbacks are now truly disabled with accessible state. Workspace zoom in/out, fit/reset, responsive scaling, reduced-motion behavior, and fullscreen are wired and tested. COC2 M2 preserves non-color status icons, semantics, tap alternatives, and correctness withholding in assessment mode.
- Database architecture: moved the bootstrap schema to the already-known `20260807085500` baseline identity so deployed databases do not replay it, added `20260822123000_neutralize_legacy_mission_scoring.sql`, and added `20260824110000_restore_service_role_data_privileges.sql`. Unsupported numeric passing/rating bands fail closed; difficulty, account, and rating enums are typed and current. No migration repair or linked/production mutation was used.
- Fresh migration validation: PASS. All 43 migrations applied to a blank local database; database lint returned no findings; 4 COCs/4 modules/20 missions exist; all public base tables have RLS; no `USING/WITH CHECK (true)` policy or unsafe `SECURITY DEFINER` search path exists; all mission passing scores are neutral; trusted server publishing can access required tables.
- Existing-main upgrade validation: PASS. Reset to `20260814123000`, loaded the production catalog, simulated `passing_score=75`, mission XP 125, and module XP 500, then applied only later migrations. The score was neutralized to 0 while both XP values were preserved; all 43 migration versions and the practice evidence table were present; lint passed.
- Backend lifecycle validation: local trusted publishers created exactly 20 published activities, 20 approved rubrics, and 98 criteria. Authenticated boundary/RBAC smoke passed. The COC2 golden lifecycle passed evaluation, adjustment-reason, finalization, release, progress, gamification, analytics, and audit checks. COC1, COC2 (remaining four), COC3, and COC4 all-mission lifecycle suites passed correct/incorrect/missing evidence paths and learner finalization denial. Quiz lifecycle passed answer-key secrecy, save/resume, exactly-once submission, result isolation, Realtime, and cleanup.
- Realtime validation: PASS in the throwaway local stack for learner-scoped enrollment, class-scoped assignments/resources, learner submission to owning Instructor, Instructor release to owning Learner, quiz assignment/submission, isolation, unsubscription, and disposable cleanup.
- Mobile validation: `flutter analyze --no-fatal-infos` PASS with 0 errors/warnings and 201 informational notices; full `flutter test` PASS (227/227); debug APK build PASS at `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk`. Release signing is not configured and release APK/AAB is NOT VERIFIED.
- Web validation: frozen pnpm install PASS; TypeScript PASS; ESLint PASS with no warnings/errors; analytics 4/4, metric strip 3/3, and OpenRouter mock 6/6 PASS; Next.js 15.3.8 production build PASS with 23/23 static pages generated. Metric card contrast and skeleton stability were repaired.
- Security/cleanup: no committed or source-tree secret-like credential, unsafe `NEXT_PUBLIC_` secret, production empty callback, true conflict marker, simulation debug probe, or unfinished production marker was found. Mobile and web ignored environment files resolve to the same Supabase host. Removed obsolete `demonstration.mp4`, stale `QA_REPORT.md`, duplicate Kotlin Gradle files, and updated active documentation to `ByteQuest-Mobile-App`.
- Manual QA still required: physical Android device, TalkBack, device landscape/large text/reduced motion, low-end hardware, production Supabase authenticated smoke, responsive browser viewport inspection, and release signing. These are validation gaps, not known P0/P1 defects.
- Exact next action: review the final local commit and report, perform the listed human/device/production smoke tests, then explicitly authorize a normal push of local `main` if accepted. Do not force-push.

## Dro integration hardening and local validation (2026-09-08)

- Git safety: recorded starting `origin/main` at `a162ecf767e9ce32a0749bfe6aa772d2d5f80acd` and `origin/Dro-branch` at `10adcbda9eacdcd36174df3ecaa26a21832109a3`; performed all new work on `integrate-dro`. No branch was pushed and no remote database was contacted or mutated.
- Production routing: the exact authoritative IDs `coc1_m1` through `coc4_m5` route to `MissionSimulationScreen`; explicit server-issued authoritative and COC2 cable assessment adapters remain separate and fail closed. Runtime titles now match `missions_data.dart`.
- Mission/runtime hardening: restored five technically distinct COC4 M5 troubleshooting cases and legacy 20-point parity without making practice scores authoritative; fixed actual-background painting, removed unrelated cover-image hotspot fallbacks, stabilized option order, and made review readiness use actual completed phases and pending/failed server evidence.
- Evidence and persistence: authoritative action append now uses stable client IDs, server reconciliation, one safe sequence resynchronization, and a forward-only uniqueness migration. Practice evidence initialization/sync failures remain locally queued and visibly retryable. System back/save-and-exit preserves snapshots; only explicit discard clears them.
- Accessibility: shared buttons expose true disabled state and 48 dp targets. COC2 M2 pins have meaningful empty/connected semantics, tap and long-press actions, icon/text status cues, and withhold correctness during authoritative assessment.
- Migration architecture: fresh local reset applied the complete chain from the already-deployed `20260807085500` foundation identity; the empty bootstrap seed avoids phantom forward data. A separate throwaway database built to the exact `origin/main` migration set accepted only the nine later integration migrations. No repair, include-all push, or migration-history manipulation was used.
- Fresh local schema verification: PASS with 4 COCs, 4 modules, 20 missions, current generated enum values, 47/47 public tables protected by RLS, 53 policies, safe `SECURITY DEFINER` search paths, no anonymous privileged RPC access, and no nonzero authoritative passing score.
- Upgrade verification: PASS with 4 COCs, 4 modules, 20 missions, neutral scoring, full RLS coverage, the authoritative client-action idempotency index, and denied anonymous finalize/release/admin operations.
- Supabase tests: `supabase test db` PASS (5 files/5 TAP tests); local lint PASS. Local published packages contain 20 missions, 20 rubrics, and 98 criteria. COC1, COC2, COC3, COC4, golden COC2 M2, quiz save/resume/exactly-once submission, resource access, RBAC/isolation, analytics/audit, and Realtime lifecycle runners passed against the disposable local stack.
- Mobile gate: `flutter pub get` PASS; `flutter analyze` PASS with zero errors (205 informational lints); full `flutter test` PASS (235/235); debug APK PASS. Release AAB remains not verified because production signing is not configured.
- Web gate: frozen install, TypeScript, ESLint, analytics (4/4), metric-strip (3/3), OpenRouter contract (6/6), and Next.js production build (23 pages) PASS.
- Repository cleanup: removed obsolete planning/report artifacts and dangerous stale account-maintenance scripts containing personal/live fixture references; sanitized remaining harness defaults and corrected current mobile paths. No committed secret-like credential, client service-role exposure, conflict marker, production empty callback, or release-path simulation debug probe remains.
- Manual QA still required: physical Android device, TalkBack, physical large-text/landscape/reduced-motion behavior, low-end performance, real production-credential smoke testing, and production release signing. These are environment/manual gates, not known P0/P1 defects.

## New-branch audit, security, and runtime hardening (2026-09-15)

- Git isolation: created and used local branch `new`, based directly on `origin/main` `5b4aa3d7dcffccfee7dc0336fad90df19ca36891`. `origin/main` was not checked out, committed to, pushed, or otherwise changed. The pre-existing untracked `ByteQuest-Web-Dashboard/package-lock.json` was preserved and excluded from this work.
- Architecture audit: confirmed Flutter/Dart learner app, Next.js/TypeScript Instructor/Admin dashboard, Supabase Auth/PostgreSQL/Storage/Realtime backend, ordered SQL migrations, root lifecycle scripts, and the existing typed 2D simulation framework. No assessment authority or instructor-release boundary was moved into either client.
- Web security: upgraded Next.js and `eslint-config-next` from 15.3.8 to 15.5.24, refreshed patched compatible transitive dependencies, and reduced the production dependency audit from 58 findings (2 critical, 29 high, 23 moderate, 4 low) to zero at every severity. pnpm is pinned to 9.15.9 because the installed Node 22.12.0 does not satisfy pnpm 11.17.0's engine requirement.
- CSV and API hardening: both analytics and released-result exporters now use one formula-safe CSV serializer; failed released-result database queries return a controlled 500 rather than silently exporting incomplete data. Middleware now lets `/api` routes retain their own JSON authentication/error behavior instead of redirecting API clients to HTML login pages.
- Dashboard reliability: account creation/removal, role/status changes, and resource upload/archive operations now recover from transport and invalid-response failures with deterministic busy-state cleanup. Resource archive submissions are latched to prevent duplicate requests.
- Flutter data correctness: PostgreSQL `numeric` progress and task-result fields now parse through `num` and preserve decimal precision. Mission UI projections round only at the existing integer display boundary. Regression tests cover decimal payloads.
- Flutter lifecycle/security: logout flows capture services before asynchronous gaps, guard context use, reset local progress consistently, and no longer expose raw exception text. The remaining flow-control analyzer lint was corrected.
- Automated mobile gate: `flutter pub get` PASS; `flutter analyze --no-fatal-infos` PASS with zero errors, zero warnings, and 202 informational modernization notices; full `flutter test` PASS (242/242); `flutter build web` PASS with WASM dry-run success. A served headless Chrome launch reached the real onboarding UI. Dedicated viewport coverage passes without overflow at 320x568 and 412x915.
- Android gate: `flutter devices` found Windows, Chrome, and Edge but no Android target. `flutter build apk --debug` is BLOCKED with `No Android SDK found`; Android emulator/physical-device launch, permissions, and APK validation were not claimed.
- Automated web gate: frozen install PASS; TypeScript PASS; ESLint PASS with no warnings/errors; analytics/CSV/metric/middleware tests PASS (10/10); OpenRouter contract tests PASS (6/6); Next.js 15.5.24 production build PASS with all 23 static pages generated. Runtime smoke PASS: `/login` returned 200, unauthenticated `/` returned a 307 login redirect, and the report API returned a direct 403 with no HTML redirect.
- Backend/security gate: root frozen dependency install PASS and production audit reports zero vulnerabilities. Static scans found zero JWT-like committed secrets, populated service-role assignments, client-exposed service-role references, or unconditional `USING/WITH CHECK (true)` policies. Supabase CLI 2.117.0 runs, but `supabase test db` is BLOCKED by `ECONNREFUSED 127.0.0.1:57322`; Docker/local PostgreSQL is unavailable.
- Integration limits: ignored placeholder `.env`/`.env.local` files were used only for compilation and unauthenticated startup checks. Real login, database/storage operations, learner-to-Instructor realtime submission/release, production Supabase connectivity, and release signing remain unverified because authorized credentials, Docker, Android SDK/device, and signing material are unavailable.
- Exact next action: install/configure Android Studio SDK plus an emulator, start a disposable Supabase stack with Docker, replace ignored placeholders with authorized test credentials, then run the authenticated lifecycle/realtime scripts, Android device matrix, and signed release gate before deployment approval.

## Implementation-status audit and controlled Instructor review changes (2026-09-15)

- Branch `new`; `origin/main` remains untouched. Pre-existing untracked dashboard `package-lock.json` remains user-owned and excluded. The full requirement classification, issue matrix, validation table, and exact run configuration are in `docs/IMPLEMENTATION_STATUS_AUDIT_2026-09-15.md`.
- Preserved the existing Flutter 20-mission simulation runtime, Supabase assessment authority, Instructor-only finalization/release, RLS, approved TESDA source/rubric identities, class tables, and OpenRouter provider. Read-only connected-project inventory found 4 COC modules, 20 missions/activities/rubrics, 98 criteria, 9 classes, 21 assignments, 41 attempts, 64 revisions, and 22 releases.
- Instructor review now supports approved `binary_sum` / `all_required` criterion-level corrections, calculates rubric-derived technical total/percentage, suggests the competency outcome, requires an adjustment reason, and shows original and revised technical totals in immutable revision history. Other rubric methods retain the existing confirmation/outcome workflow rather than receiving invented score logic.
- Added `20260915090000_validate_instructor_score_revisions.sql`, a SECURITY INVOKER append-time guard against total/max/percentage and criterion-value inconsistencies; it preserves reasoned Instructor outcome authority and existing RPC signatures. Rollback-only negative tests and the disposable COC2 correction fixture were updated. **The migration was not applied** to the connected project because `supabase test db` failed before execution at local PostgreSQL `ECONNREFUSED 127.0.0.1:57322` (Docker/local stack unavailable). Do not claim backend fix complete until isolated rollback tests pass and authorized application is verified.
- AI quiz review now offers a one-question alternative for an AI draft through the existing Instructor-only grounded endpoint. The original item is kept until Instructor review/removal; the alternative is still a draft and is never auto-published. Live authenticated AI generation was not executed because the current connected project has no quiz records and no disposable isolated journey was available.
- Web verification: TypeScript, ESLint, Next.js 15.5.24 production build (23/23 static pages), configured analytics 4/4, CSV 2/2, middleware 1/1, metric strip 3/3, OpenRouter mock 6/6, and new focused tests 5/5 PASS. Dev server served login HTTP 200, unauthenticated root 307 to login, and protected report API 403 without HTML redirect.
- Flutter verification: `pub get` PASS; analyzer PASS with 0 errors and 202 existing info notices; full tests PASS (242/242). Chrome preview launched, main method ran, Supabase client initialized, and app entry GET returned 200. Android debug APK remains BLOCKED (`No Android SDK found`); no Android device was listed. Authenticated score edit/release, bypass, class/resource, AI, cross-client Realtime, and physical accessibility journeys remain NOT TESTED in this session.
- Immediate next action: install/run a disposable Docker/Supabase stack; test the complete migration chain plus `foundation_lifecycle_rollback.sql` and authenticated COC2 lifecycle; only then review/apply the migration to the connected project. Design a separate reasoned post-release score correction/re-release workflow with retained projections before adding any elevated RPC. Separately configure Android SDK/device and run APK/device accessibility checks. Continue with role-scoped concern workflow and optional scenario-video proof only after these validation foundations are available.

## Request implementation verification report (2026-09-15)

- Added `docs/REQUEST_IMPLEMENTATION_VERIFICATION_REPORT_2026-09-15.md` as the consolidated verification handoff requested by the user.
- The report separates pre-existing/preserved implementation, commit `3d095aa`, worktree-only changes, connected-project state, and unresolved or environment-blocked requirements. It does not label worktree code as deployed.
- It covers architecture, all prompt requirements, every changed area/file, actual automated/runtime evidence, the requested Admin identity's non-secret status, exact local commands, eight manual workflow procedures, migration acceptance gates, Android/device gates, and a final sign-off matrix.
- A configuration audit found that Next.js reads the current ignored `.env.local`, but Node `--env-file=.env.local` did not load assignments containing spaces around `=`. Authenticated lifecycle scripts require `VARIABLE_NAME=value`; no secret value was logged or added to source.
- No application, migration, environment, connected-database, account, or remote Git state was changed while producing this report. The new score-consistency migration remains unapplied and unverified; Android and authenticated journey blockers remain unchanged.

## Windows WSL/Docker and isolated Supabase validation (2026-09-16)

- Windows restarted after installation. WSL 2.7.14.0 is active with the `docker-desktop` WSL distribution. Docker Desktop 4.91.0 and its Linux Docker Engine 29.8.0 respond to `docker version`.
- Started the disposable ByteQuest Supabase CLI 2.117.0 stack. The local Auth health and Studio endpoints return HTTP 200; API `57321`, PostgreSQL `57322`, Studio `57323`, and local mail `57324` ports are listening. This is not the connected/hosted project.
- Fresh local start and `supabase db reset --local --no-seed --yes` both applied all 45 ordered SQL migrations, including `20260915090000_validate_instructor_score_revisions.sql`. `supabase db lint --local --level warning --fail-on error` passed with no schema errors.
- Initial `supabase test db --local` reached PostgreSQL but failed four test files at explicit fixture preconditions because the fresh local stack had no staff/learner Auth profiles. Created five generated-password, disposable local Auth identities only: one active Admin, one active Instructor, and three active Learners. No password or local key was printed or stored in the repository.
- Re-ran `supabase test db --local`: PASS, 5 files/5 tests, including `foundation_lifecycle_rollback.sql` and the new score-revision negative cases. An earlier inline Node fixture command failed at PowerShell argument quoting before any account creation; a base64-transported in-memory script completed the same local fixture setup safely.
- The test identities remain in the disposable local database and can be cleared by a future intentional `supabase db reset --local`; do not use `--linked` for this cleanup. Existing worktree changes and `origin/main` `5b4aa3d7dcffccfee7dc0336fad90df19ca36891` were preserved. No migration was applied to hosted Supabase and no Git commit/push was made.
- Still pending before a hosted migration or full completion claim: authenticated COC2 score-correction/release and Realtime client lifecycles against the isolated stack; existing hosted-data compatibility review; Android SDK/debug APK/device gate; signed release and manual accessibility QA. The previously documented product gaps remain separate from the resolved Docker blocker.

## Authenticated verification, concern workflow, and middleware fix (2026-09-16)

- Branch `new`; `origin/main` and hosted Supabase remain untouched. Pre-existing dirty worktree files and the user-owned untracked dashboard `package-lock.json` were preserved. The updated pre-change audit and final evidence report are `docs/IMPLEMENTATION_STATUS_AUDIT_2026-09-16.md` and `docs/REQUEST_IMPLEMENTATION_VERIFICATION_REPORT_2026-09-16.md`.
- Published the existing approved 20 mission/98 criterion packages only into the disposable local Supabase stack. Authenticated COC2 correction/finalization/release passed, including mismatched-role denial, mandatory adjustment reason, append-only provisional/adjusted/final history, learner release visibility, exact-once reward, analytics/audit, private resource scope, retention and cleanup.
- All-mission local lifecycle passed: COC1 14 checks/10 attempts, COC2 12/8, COC3 14/10 and COC4 14/10. The authenticated boundary and learner quiz suites passed every reported RBAC, class, Storage, account, audit, resume, idempotency, result-isolation and cleanup check.
- Added an additive role-scoped concern workflow: `support_concerns`, limited column grants, RLS, reasoned actor/time status history, Instructor-owned training intake/status, Admin-only system intake/status, Admin read-only training oversight, no learner/anonymous access and no client delete path. Added Instructor `/concerns` and Admin `/admin/concerns` pages plus navigation, types, rollback test and authenticated backend/SSR harness. pgTAP passes 6 files/6 tests; concern journey passes 17/17 checks.
- Runtime smoke found project-root `middleware.ts` did not execute beside a `src/app` layout. Moved it to `src/middleware.ts`, extended Instructor-only prefixes to resources/quizzes/concerns and kept API routes under route-owned JSON behavior. Unauthenticated protected pages now return real HTTP 307; authenticated Instructor/Admin concern pages render only in their matching role. Production build now emits a 93.3 kB middleware bundle.
- Realtime initially missed the first local CDC event even after channel subscription. Added a two-second post-subscription registration wait; two consecutive complete runs then passed 8/8 checks for enrollment, notifications, assignment, attempt submit/evaluate, release, resources, isolation and cleanup. The initial failures remain documented rather than hidden.
- Web gate: TypeScript PASS; ESLint PASS; focused tests 21/21; Next.js 15.5.24 production build PASS with 23/23 static pages plus both new dynamic routes. Flutter: `pub get` PASS; analyzer PASS with 0 errors/0 warnings and 202 info notices; 242/242 tests PASS; Chrome preview HTTP 200.
- Android remains BLOCKED: `flutter doctor` cannot find the Android SDK, no Android device is listed, and `flutter build apk --debug` fails with `No Android SDK found`. No APK/device/accessibility/signing pass is claimed.
- Local database now records 46 migrations, schema lint is clean and every public base table has RLS. `20260915090000_validate_instructor_score_revisions.sql` and `20260916090000_role_scoped_support_concerns.sql` remain unapplied to hosted Supabase.
- Remaining product decisions/gaps: post-release correction/re-release requires explicit elevated-function security review; per-item weighted quiz points require an institutional policy and must remain separate from TESDA; approved embedded scenario video/media fallback is not supplied/tested; live OpenRouter generation, Android/device accessibility, signing, hosted backup/migration/smoke and human responsive QA remain pending.

## Grounding, recovery, and live AI completion (2026-09-16)

- A backup/restore rehearsal used a 1.1 MB custom-format dump of the populated disposable stack. Restoring as ordinary `postgres` exposed expected Supabase Realtime/Vault ownership restrictions; restoring into a disposable database as local `supabase_admin` passed with identical counts: 46 migrations, 20 missions, 98 criteria, 4 concerns, and zero public tables without RLS. Temporary databases and dump files were removed.
- A clean reset revealed the 20 mission catalog rows had blank `scenario`, `objective`, and `skills_assessed` fields even though the same content already exists in `ByteQuest-Mobile-App/lib/data/mission_scenarios_data.dart`. Added `20260916100000_complete_mission_grounding_catalog.sql`, which fills only blank fields and preserves nonblank database curation. Added a four-assertion rollback-safe catalog test.
- Final empty-database rebuild applied all 47 migrations in order. Schema lint PASS; every public base table has RLS; 20/20 canonical missions have complete grounding; pgTAP PASS with 7 files / 10 assertions. The final local stack contains only the base catalog and five disposable role fixtures; previously published lifecycle data was removed by the reset.
- Live OpenRouter diagnostics found two independent issues: body-read aborts were mislabeled as malformed JSON at the 45-second deadline, and the random `openrouter/free` router was not reliable for the full grounded structured request. Timeout classification is corrected, the server-only timeout now defaults to a bounded 90 seconds, structured requests require parameter-capable routing, completion/reasoning budgets are bounded, and provider tests now pass 8/8.
- The current official models API listed `liquid/lfm-2.5-2.6b:free` as a free structured-output-capable route. The complete authenticated lifecycle `openrouter-live-20260916034347-ed9ddeca` passed 9/9: real Instructor session, grounded generation, draft-only storage, auto-publish denial, edit/approve/reject/remove, approved-only publish, audit provenance, and archival. The ignored local `.env.local` model selector was updated; the key remained unchanged and unlogged.
- Final web gate: TypeScript PASS; ESLint PASS with zero warnings/errors; focused tests 23/23; Next.js 15.5.24 production build PASS with all 23 static pages and the 93.3 kB middleware bundle.
- Final Flutter gate: dependency resolution PASS; analyzer PASS with zero errors/zero warnings and 202 informational notices; tests PASS 242/242. `flutter doctor` finds Windows, Chrome, and Edge but no Android SDK/device. `flutter build apk --debug` remains BLOCKED with `No Android SDK found`.
- Hosted Supabase, `origin/main`, and all remotes remain untouched. The three 2026-09-15/16 migrations are not hosted. No commit was created because the repository-mandated Android build gate cannot pass on this machine.
- Remaining decisions: post-release correction/re-release needs explicit SECURITY DEFINER review; weighted quiz points need an institutional rule; scenario video needs approved accessible media/fallback acceptance; Android SDK/device/TalkBack/signing and hosted backup/migration/smoke remain required.

## PDF revision audit and interaction decluttering follow-up (2026-09-17)

- Specification audit: extracted and reviewed `docs/reference/new-bytequest-revisions-to-do-list.pdf` before application changes. The named alternate path `docs/new-bytequest-revisions-to-do-list.pdf` does not exist. The complete BQ-001–BQ-032 evidence/gap/risk table is in `docs/BYTEQUEST_REVISION_CHECKLIST_AUDIT_2026-09-16.md`; the checkpoint handoff is in `docs/BYTEQUEST_REVISION_IMPLEMENTATION_REPORT_2026-09-17.md`.
- Narrow product change: completed evidence-backed placement, matching, connection, and authoritative `ComponentPlacement` workspaces now collapse dense source/destination controls into recorded-state summaries. A visible, accessible review/change control restores inputs without deleting persisted state or evidence. Connection sources remain available during incomplete multi-link work.
- Added focused widget coverage for compact completed placement/matching/connection views and the authoritative review path in `test/core_mission_interactions_test.dart`. No mission definition, scoring, TESDA rule, database schema, RLS policy, assessment authority, or COC access behavior was changed by this follow-up.
- Current shell gate: `git diff --check` PASS. Fresh Flutter, pnpm, Supabase CLI, and Docker checks are BLOCKED because the commands are not on the current shell `PATH` and Docker Desktop's Linux engine is stopped. The earlier 2026-09-16 local validation results remain historical evidence only; do not treat the new BQ-015 tests as run until the toolchain is restored and they pass.
- Branch/hosting safety: work remains on local `new`; `origin/main`, all remotes, and hosted Supabase remain untouched. No commit was created.

## Final local checklist verification and Android build closure (2026-09-21)

- Restored the local Flutter and Android toolchains without changing application architecture: Flutter 3.47.5 / Dart 3.13.4, Microsoft OpenJDK 17.0.20.1, Android SDK platform/build-tools 36, accepted Android licenses, and NDK 28.2.13676358. Official downloaded archives were checksum-verified before use.
- Re-ran the BQ-015 interaction changes: focused Flutter tests PASS 44/44; analyzer PASS with zero errors and zero warnings (202 informational suggestions); full Flutter tests PASS 245/245; Flutter web build and WebAssembly dry run PASS.
- Android debug build PASS. `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk` is 170,422,108 bytes with SHA-256 `AB48CC2215CF080B89F4E5C3E8B6FF1279B292CF780A1FD025CE671B07541B11`. No Android emulator or physical device was available, so launch, device permissions, TalkBack, and physical responsive acceptance remain untested.
- Dashboard verification PASS: TypeScript, ESLint (zero warnings/errors), 23/23 focused tests, and Next.js 15.5.24 production build with 23 static pages. Playwright visual review passed for the login page at 320x568, 800x1280, and 1440x900.
- Disposable local Supabase verification PASS: pgTAP 7 files / 10 tests and database lint with no schema errors. Hosted Supabase was not migrated or mutated.
- Flutter onboarding visual review passed at 320x568, 800x1280, and 1440x900. Mission widget tests separately cover portrait/landscape, 2x text, reduced motion, minimum tap targets, and overflow. These automated/browser checks do not replace physical Android/TalkBack acceptance.
- Final checklist report: `docs/BYTEQUEST_REVISION_FINAL_REPORT_2026-09-21.md`. It records every BQ-001 through BQ-032 item, exact local evidence, changed files, migrations, test results, and operational gates. `COMPLETE` is limited to implementation plus applicable local verification; it is not production-deployment approval.
- Remaining operational gates: physical Android/TalkBack testing, authenticated hosted smoke testing after an explicitly authorized migration, release signing, and production OpenRouter acceptance. Flutter also warns that Kotlin 2.2.20 should be upgraded to at least 2.3.20 for future compatibility; the current debug APK build passes.
- Branch/hosting safety: work remains on local `new`; `origin/main`, hosted Supabase, and remotes remain untouched. No commit was created because the worktree contains pre-existing mixed/user-owned changes, including the untracked dashboard `package-lock.json`.

## Local dashboard account provisioning (2026-09-28)

- Created and email-confirmed the disposable local Supabase Auth account `jbuladaco88@gmail.com` for dashboard testing. Its authoritative `public.profiles` row is active with the independent `admin` role.
- Verified password authentication against the local Auth endpoint and verified that the authenticated session can read its active Admin profile through RLS. The temporary password was returned only to the requester and was not written to the repository.
- This provisioning changed only the disposable local Supabase instance at `127.0.0.1:57321`. Hosted Supabase, migrations, application source, Git history, and remotes were not changed.

## Dashboard undefined-string runtime hardening (2026-09-29)

- Fixed the dashboard runtime failure `Cannot read properties of undefined (reading 'toLowerCase')` by guarding external/runtime strings before case normalization in account actions, Admin account API error handling, permanent-removal email verification, keyboard navigation, and metric-link accessibility labels.
- Added a metric regression case proving malformed runtime data receives the accessible `Summary metric` fallback instead of throwing. Focused verification passed: TypeScript with no emit, ESLint on all changed files, and metric-strip tests 4/4.
- No database schema, role, class, enrollment, assessment, hosted Supabase, or remote Git state was changed by this fix.

## Pre-push validation and isolated fixture hardening (2026-09-29)

- Prepared the accumulated implementation on local branch `new` for the separate empty repository `https://github.com/vincee08/bytequest-project.git`; the existing `origin` and `main` remain untouched. Credential-shaped source scanning reported no committed secret candidates, and the pnpm-incompatible generated `ByteQuest-Web-Dashboard/package-lock.json` remains intentionally untracked.
- Mobile gates PASS: dependency resolution; analyzer with zero errors/warnings and 207 informational notices; complete Flutter suite 333/333; Android debug APK build. The existing Kotlin 2.2.20 future-compatibility warning remains non-fatal.
- Dashboard gates PASS: TypeScript; prescribed Next.js lint with zero warnings/errors; focused tests 24/24; Next.js 15.5.24 production build with 23/23 static pages plus dynamic routes and middleware. Authenticated development traffic compiled and served Classes, Learners, and Instructor Dashboard after the undefined-string runtime fix.
- Supabase lint PASS with no schema errors. The first rollback run selected a real enrolled learner and correctly hit `LEARNER_HAS_OTHER_INSTRUCTOR_SCOPE`; `storage_and_account_hardening_rollback.sql` now selects only active learners without existing active memberships. The repeat suite passed 7/7 files and 10 assertions without deleting or changing current local accounts/classes.
- Published implementation commit `78313ca` from branch `new` to the separate remote `bytequest-project` at `https://github.com/vincee08/bytequest-project.git`. The pre-existing `origin` URL, its branches, and local/remote `main` were not changed. The local branch now tracks `bytequest-project/new`.

## Hosted Supabase login recovery and client connectivity verification (2026-09-29)

- Restored the exact ByteQuest Supabase project `rslmteqipxqfifwftugk`; its Management API state progressed from `INACTIVE` / `RESTORING` to `ACTIVE_HEALTHY`. No unrelated Supabase project was selected and no schema migration or assessment rule was changed.
- Root cause was operational configuration, not the login UI: the project had been inactive, its legacy `anon` / `service_role` keys were disabled on 2026-09-15, and the dashboard retained a stale server secret. Both clients already used the current publishable key.
- Verified the two requested hosted Auth users exist and are email-confirmed. Corrected only their authoritative active profile roles to the requested assignments: `vincebuladaco88@gmail.com` is `instructor`; `jbuladaco88@gmail.com` is `admin`. Passwords were not read, logged, changed, or stored.
- Replaced Vercel Production, Preview, and Development Supabase configuration with the current project URL, publishable key, and protected secret key. Redeployed production successfully as `dpl_47hdcD8g5YVNtQ8K7ssawyCkLa79`; `https://bytequest-alpha.vercel.app/login` returns HTTP 200 and `/` redirects to `/login` with HTTP 307.
- Dashboard validation PASS: TypeScript, Next.js lint with zero warnings/errors, and the Next.js production build including 23/23 static pages. Local ignored `.env.local` was synchronized without committing any secret.
- Mobile connection verification PASS at the transport/configuration boundary: the ignored `.env` targets the same hosted project with its current publishable key, `.env` is bundled as an asset, Android declares Internet permission, and the exact configured client values received HTTP 200 from Auth health and settings. An unauthenticated table probe reached PostgREST and was denied with expected `42501` privileges; no bypass or public-table grant was added.
- Mobile static gate PASS with zero analyzer errors/warnings and 207 existing informational modernization notices; focused Auth provisioning test PASS 1/1. No Android device/emulator is attached, so a physical mobile login was not claimed. The two repaired accounts remain dashboard-only by design; the mobile client accepts Learner profiles only.
- Application source, Supabase schema, evaluation authority, the original `origin`, and `main` were unchanged. Current API credentials remain only in ignored local files and protected Vercel environment storage.
- At the requester's direction, reset the hosted passwords for the active Admin and Instructor accounts and verified password authentication plus each account's role-scoped profile read. The shared temporary password was returned only in chat and was not logged or stored in the repository.

## Selective hosted database migration and learner enrollment (2026-09-29)

- Confirmed the hosted migration history uses older generated timestamps and diverges from the 47-file repository history. A normal `db push` would therefore attempt to replay foundational migrations and was not used. Applied only the missing approved changes through Supabase's transactional migration API.
- Before mutation, the local rollback suite passed 7 files / 10 tests and local database lint found no schema errors. Supabase reported no managed platform backups for this project, so an affected-data/migration-history snapshot was saved to ignored `.tmp/hosted-pre-migration-20260929-183253.json` (SHA-256 `09B476422622E47D5302978749187F1F65779BC34ED31F386013C182D6FF3067`).
- Hosted migration `20260929103316 validate_instructor_score_revisions` added the enabled score-revision consistency trigger. Hosted migration `20260929103333 role_scoped_support_concerns` added the RLS-protected concern table, three policies, scoped grants, history trigger, and indexes. The mission-grounding migration was deliberately not applied because preflight proved all 20 canonical hosted mission rows already had complete scenario, objective, and skills data; rewriting their timestamps was unnecessary.
- Migrated only the real local Learner `buladaco.johnvincent@dnsc.edu.ph` into hosted Supabase Auth. Preserved its bcrypt password hash and confirmed email state, copied the active Learner profile fields (`learner_id`, school, section, and name), and enrolled it through the authoritative Instructor RPC into the existing hosted `css nc II set b` class. No QA identities, archived test classes, duplicate class, attempts, or results were copied.
- Post-migration checks PASS: score trigger enabled; concern table RLS enabled with three policies; zero incomplete canonical mission rows; learner password hash preserved; one active hosted Learner profile and one active class membership. Instructor scope now returns exactly one owned class, one active Learner, and one membership.
- Hosted concern runtime checks PASS for Instructor training intake/update/isolation and Admin system intake/update/global oversight. All temporary concern verification rows were deleted. Supabase Security Advisor reported zero errors, 65 pre-existing warnings, and no finding for `support_concerns`.
