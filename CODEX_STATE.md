# ByteQuest — Codex Handoff State

> Read this file with `AGENTS.md`, `README.md`, and `bytequest.md` before changing the repository.

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
- Application source, Supabase schema, evaluation authority, passwords, the original `origin`, and `main` were unchanged. Current API credentials remain only in ignored local files and protected Vercel environment storage.
