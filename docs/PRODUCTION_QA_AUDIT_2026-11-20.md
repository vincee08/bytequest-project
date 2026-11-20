# ByteQuest production QA audit — 2026-11-20

Production end-to-end audit before the Monday 2026-11-23 re-defense, run against the live system
with authorized test accounts and controlled TEST ONLY data. The local-stack audit of the same day is
`docs/REDEFENSE_QA_AUDIT_2026-11-20.md`. Screenshots: `docs/qa-production-2026-11-20/`.

## 1. Verdict and readiness

**Production works end to end for all three roles.** The 2D hardware assembly was completed in
production by touch (Android APK) and by mouse (Chrome). Evaluate → Finalize → Release reached the
learner for an assessment, a quiz essay and homework. Analytics, monitoring, notifications and live
updates reflect the work.

| Status | Count |
|---|---|
| PASS | 34 |
| PARTIAL | 3 (R2.4, R10, R11.2) |
| BLOCKED | 1 (R3.3, OpenRouter) |
| FAIL | 0 |

The assembly passes in practice mode. In production an *assigned* COC1 M2 assessment still opens
the legacy form package, not the bench, because the simulation assessment packages are not
published there. That is blocker B1, noted under R2.2 rather than counted as a separate row.

Ten defects were found in production and fixed in the working tree, each with tests (section 5). None
is deployed yet: the dashboard needs a Vercel promotion, the app needs a new APK and the release
notification needs one approved migration. **Readiness:** demo-ready for practice-mode assembly,
quizzes, homework, evaluation, analytics and administration. Before Monday, three things depend on
the owner (section 7): publish the simulation assessment packages if an *assigned* COC1 M2 assessment
should open the bench, restore OpenRouter capacity for a live AI demo, and approve the deploy of the
fixes.

## 2. Targets, safety and data

| Target | Identified as | Version |
|---|---|---|
| `https://bytequest-alpha.vercel.app` | Production dashboard (Vercel) | `c842f6f` (main, PR #5), confirmed from the live login bundle |
| Supabase `rslmteqipxqfifwftugk` | Production database | migrations through `20261120100400` |
| `ByteQuest App.apk` 1.2.0 | Debug-signed build with production public defines | emulator `padala_pixel7` (Pixel 7 profile, Android) |
| Flutter web build of the working tree | Mouse test client on `http://localhost:3009`, the production CORS preview origin | Chrome 412 × 915 |

Rules kept: no deploy, no production migration, no settings change, no real learner record read into
this report or changed, no shared-content publication. Release was done only for the test learner (owner
decision). The curriculum topic stopped at *Submitted* and the Excel import at the validation preview
(owner decision).

**TEST ONLY data created in production** (safe to delete after the defense):
- learner *QA Test Learner 1120* (`bytequest.qa.learner.20261120@bytequest.invalid`);
- class *TEST ONLY – QA 2026-11-20* (QA-1120);
- quiz *TEST ONLY QA quiz – ESD and memory (2026-11-20)*: v1 published, v2 an empty draft from the
  AI retry;
- homework *TEST ONLY QA homework – assembly checklist*, deadline moved to 22 Nov for the live-update
  test;
- assessment assignment *TEST ONLY QA: COC1 M2 hardware assembly assessment* and its released attempt;
- two verified COC1 M2 practice runs;
- curriculum topic *TEST ONLY QA topic 2026-11-20 (do not publish)*, Submitted.

The test learner's generated password appeared in this session's tool log; delete or rotate that
account after the defense. The admin and instructor test passwords are weak; change them after the
defense.

## 3. The 2D hardware assembly in production (COC1 M2, practice)

| Run | Input | Client | Result |
|---|---|---|---|
| #1 | Touch | APK 1.2.0 on the emulator | Verified · 16 m 33 s · 35 accepted · 0 refused · 0 faults |
| #2 | Mouse (real button events) | Chrome, web build | Verified · 34 m 04 s · 38 accepted · 4 refused · 1 correction · 2 power-on faults |

Run #2 deliberately exercised validation and troubleshooting:
- CPU dragged at the wrong orientation: refused with "The processor only drops into the socket one way…" (`m01`).
- A module dragged before alignment: refused with "The module notch does not meet the slot key…" (`m04`).
- The cooler hides the lever ring (`m03`).
- A module dropped one slot off (A1) was removed with the latches open and reseated in A2 (`m05`,
  `m06`). The header counted 1 correction.
- Both SATA cables left off on purpose. The POST reported "Drive power: …SATA power is not connected"
  and "Boot device: …The SATA data cable is not connected" (`m09`). Both were fixed on the bench and
  the second POST passed (`m10`).

Other run #2 actions:
- rotation by button and by double-click (human timing);
- zoom, pan and fit by mouse;
- Shift+wheel tray scrolling;
- drag and click-to-place for parts and cables;
- a typed interpretation.

All 49 evidence writes went through the production practice API (82 × 200 and 49 × 201 responses).

The instructor's learner view shows both runs, with "#2 … 4 invalid · Missed: Step 2 Prepare the
motherboard (2 incorrect); Step 5 Power-on test (4 incorrect)" (`d03`).

## 4. Panel requirements (38) — production

| ID | Requirement | Status | Production evidence |
|---|---|---|---|
| R2.1 | Selectable/draggable components, rotation, visual response, realistic visuals | PASS | Section 3. Touch and mouse drags, rotation previews ("Triangle: top-left · 90°"), bay-filling PSU and drive (`t01`, `t02`). |
| R2.2 | Multiple sequential assembly steps | PASS | Six phases, 3–9 bench steps each, in both runs. **Assigned assessments** in production open the legacy form package, not the bench (blocker B1). |
| R2.3 | Logical placement, validation, prevention, correction, progress | PASS | Orientation refusals, lever/latch holds, Remove → reseat, POST faults → bench repair → re-test (section 3). |
| R2.4 | Smooth drag, snap, highlight, indicators, hints, feedback | PARTIAL | Works by touch and mouse. Defect D3: a click or drop on the upper 40 % of the highlighted drive power port reached the data port (`b02`). Fixed locally. |
| R2.5 | Record steps, incorrect attempts, time, completion; feed analytics | PASS | `d03` run table; analytics: 2 runs, average 25 m 19 s, invalid per run, most-missed steps. |
| R3.1 | Quizzes by COC → module → LO with focus, type, difficulty, limits, deadline, attempts | PASS | Test quiz COC1 · LO1.1, focus, foundation, 3-minute limit, deadline, one attempt. |
| R3.2 | Official topics and LOs, correctly associated | PASS | Curriculum shows LO1.1 performance criteria with TR line references; the quiz maps to LO1.1. |
| R3.3 | AI generation and editing | BLOCKED | OpenRouter answered 429 to every attempt (again 06:58 UTC: "OpenRouter is rate-limited right now…"). The failure is graceful and manual authoring works. The pipeline passed locally. |
| R3.4 | Scenario essay, rubric scoring, instructor evaluation | PASS | Scored 5 + 4 with feedback and history, finalized, released; the learner sees rubric scores and feedback (`r02`). |
| R3.5 | One attempt, deadline, auto-submission, statuses, essay pending | PASS | Auto-submitted at the 3-minute limit; "Submitted — Attempt used"; the essay stayed pending until scored. |
| R3.6 | Library filters, drafts, review, results, class performance | PASS | Library status counts and filters; Results tab with class performance. Archive not exercised in production. |
| R4.1 | Homework by COC/mission with objectives, criteria, requirements, max score | PASS | Test homework COC1 · M2 · LO1.1, 10-point criterion. |
| R4.2 | Learner views, submits, uploads, sees status, feedback, score | PASS | PNG upload; the instructor download is byte-identical; released 8/10 with feedback (`r03`). |
| R4.3 | Instructor filters, missing work, files, grading, late tracking, grader | PASS | `/submissions` filters, Missing work tab, late counts; audit line "Graded … Finalized … Released by …". |
| R5.A | Overall performance with period and population | PASS | Population and period sentence; four score sources (`d02`). |
| R5.B | Class performance and comparison | PASS | Comparison table: 83.9 % average, 91.7 % quiz, 0 % competent, 5 % missions, 100 % homework, 4.2 % progress, drill-down. |
| R5.C | Individual learner progress | PASS | Learner page: status reasons, measures, evaluation stages, engagement, COC tree, runs (`d03`). |
| R5.D | Quiz analytics | PASS | 1/1 participants, 100 % completion, average/high/low 91.7 %, 0 pending. |
| R5.E | Mission performance with real attempt counts | PASS | 2 runs (2 ok), runs per learner, average time, invalid per run, most-missed steps. |
| R5.F | Criterion-based analysis | PASS | Strongest/weakest across essay, assessment and homework criteria. Defect D8 (raw id label) fixed locally. |
| R5.G | Charts, tables, filters | PASS | Class, COC, module, topic, mission, quiz, learner and period filters; six tabs. |
| R5.H | Accuracy rules | PASS | 80 % = 4/5; 91.7 % = 11/12; 80 % = 8/10; 83.9 % = mean of the three; 4.2 % = 1/24. Matches the app. |
| R6.A | Excel bulk import | PASS | Preview only (owner decision): 4 rows, giving 0 enroll, 1 pending, 1 skipped (already enrolled), 2 invalid, plus a CSV error report. Not confirmed. |
| R6.B | Search, filter, sort, paginate learners | PASS | Search "QA Test" → "Showing 1–1 of 1 learners · Page 1 of 1"; class and status filters. |
| R7.A | One COC/module/topic/LO structure everywhere | PASS | Same titles and codes in Learn, Practice and the dashboard. |
| R7.B | Learn page with real completion | PASS | COC 1 unlocked, 2–4 locked; Module 1 "1 of 2 required items"; the submitted draft topic is not shown to learners. |
| R7.C | Practice grouped by COC/module with locks | PASS | COC chips, module sections, Mission 2 "Verified · 2 runs · Best 16:33", later modules locked. |
| R7.D | One progress methodology | PASS | 1 of 6 (COC 1) in the app, 1 of 24 = 4.2 % on the dashboard. The TalkBack value said 17 % for a visible 16 % (D4, fixed locally). |
| R8 | Sequential unlocking enforced server-side | PASS | Module 2 and COC 2–4 locked with prerequisite text (first production pass). |
| R9.2 | Gamification | PASS | Rewards: 125 points, Level 2 Apprentice, 3 of 12 achievements; mirrored on the dashboard. |
| R9.4 | Evaluate / Finalize / Release | PASS | Assessment (4/5, not yet competent), essay (9/10) and homework (8/10) each went through all three stages; nothing was visible before release. Defect D5: no notification for quiz or assessment releases (migration written). |
| R9.6 | Analytics and live updates | PASS | "Live updates on". A deadline change raised the learner bell from 4 to 5 live on the APK and on web. |
| R10 | Curriculum workflow | PARTIAL | Draft → Submitted verified, and the admin sees Evaluate. Later stages were not exercised in production by owner decision; all stages passed locally. |
| R11.1 | `evaluator_config` exposure | PASS | Learner token: `activity_versions.evaluator_config` returns 403 (42501); rubric versions and quiz versions return empty. |
| R11.2 | No nonfunctional or misleading UI | PARTIAL | Breadcrumbs to `/classes/<id>/assignments` and `/progress/learners` return 404, and their prefetches log 404s (D1). A saved practice run said "Complete the missing task" (D2). Both fixed locally. |
| R11.3 | Mobile/web consistency | PASS | Same results on the APK, the web app and the dashboard; cross-device resume of a saved run. |
| R11.4 | Role checks on every action | PASS | Learner `release_attempt` returns 403 `CLASS_SCOPE_DENIED`; the learner Evaluation Center API returns 403; other profiles are hidden. All 14 admin pages load with no 4xx/5xx. |
| P12 | Testing | PASS | Section 6. Emulator and browser only; no physical phone or TalkBack session. |

## 5. Defects found in production (all fixed locally, with tests)

| # | Severity | Defect | Fix | Tests |
|---|---|---|---|---|
| D1 | Moderate | Breadcrumb links to pages that do not exist (`/classes/<id>/assignments`, `/progress/learners`, `/users/<id>`) returned 404 and logged 404 RSC prefetches | Redirect pages (class → Assignments tab, learner list, user edit); crumb logic moved to `breadcrumbTrail`; record ids read "Class", "Assignment"… | Every crumb of every dashboard page leads to a page (fails without the pages); labels |
| D2 | Moderate | After a saved practice run the guide said "Complete the missing task, then review again" and pointed to Return to mission | The review step reads "Saved successfully. Use Back to leave this mission"; Show me where outlines Back | Widget test; verified live on web against production (`m11`) |
| D3 | Moderate | Drive SATA data port's padded touch area covered 40 % of the power port's highlight; clicks and drops there reached the wrong port (SYS_FAN also overlapped the 24-pin header) | Cable-header targets meet halfway between neighbouring ports, like the memory slots | No-overlap unit test; click tests at both facing edges (one fails without the fix) |
| D4 | Minor (a11y) | Progress bar announced "17 percent" beside a visible "16%" | The bar announces the percentage the screen shows | Widget test |
| D5 | Moderate | No learner notification for a released quiz result or assessment result (homework only) | Migration `20261120110000_result_release_notifications.sql`: two dispatcher branches; idempotent per attempt; an assessment release has no "Open activity" (a retry would start an attempt) | SQL suites: fail before the migration, pass after; 42/42 local SQL suites; app label test |
| D6 | Minor (mouse) | A plain mouse wheel did not scroll the bench tray (only Shift+wheel or a trackpad) | A vertical wheel turn scrolls the tray sideways | Widget test (fails without the fix) |
| D7 | Moderate | Logcat: "Looking up a deactivated widget's ancestor is unsafe" from the 30-second activity poll (`assigned_class_activities.dart:73`); the dashboard poll had the same pattern | Poll reads ticker and route state cached in `didChangeDependencies` | Widget test: polls only while its route is current, no exception |
| D8 | Cosmetic | Criteria analytics showed a homework criterion as "Homework · 15645138-7d5e-…" | Record ids never shown; the homework title names it | Panel test (fails without the fix) |
| D9 | Cosmetic | Admin pages titled "ByteQuest \| Instructor Dashboard" | Title "ByteQuest \| Dashboard" | Build |
| D10 | Minor | Login password field without `autocomplete` (Chrome warning) | `current-password` | Build |

## 6. Automated results (after all fixes)

| Suite | Result |
|---|---|
| Flutter full suite (Docker, Flutter 3.44.0) | 735 passed, 1 skipped, 0 failed (727 before + 8 new) |
| `assembly_bench_test` | 61 passed (overlap, both-edge clicks, mouse wheel added) |
| `flutter analyze` | 0 errors, 0 warnings; 210 infos, all pre-existing (unchanged count) |
| Dashboard `tsc --noEmit` | 0 errors |
| Dashboard lint | no warnings or errors |
| Dashboard tests | 226 passed (163 + 47 + 16; 222 before + 4 new) |
| Dashboard `next build` | succeeded; the three redirect routes are built |
| Local SQL rollback suites (with the new migration) | 42 / 42 (the two release suites fail before the migration) |

Each new regression test was run once without its fix and failed, then passed with it (D1, D3, D5,
D6, D8). D2 was additionally verified live against production from the web build.

## 7. Remaining issues and blockers

| # | Item | Owner action |
|---|---|---|
| B1 | **Resolved 2026-11-20 (owner-approved publish, verified read-only: +20 versions, +20 rubrics, +106 criteria, +40 links, no existing row changed).** Before: production had no published simulation assessment packages. An **assigned** COC1 M2 assessment opens the legacy five-stage form, not the bench; practice uses the bench. | Dry-run, then `node scripts/publish-simulation-assessments.mjs --target hosted --confirm` with the production service-role key (needs approval). |
| B2 | OpenRouter answers 429 on every AI generation (also today). | Add credits or change the model/key in Vercel production; re-test one generation. |
| B3 | D1–D10 are local only. **Update 2026-11-20:** `20261120110000` is applied to production and verified (§9). The push to `vince-branch` and a PR into `main` follow the §9 commit. | Remaining: the Vercel production deploy of `main` (the teammate) and a new APK (blocked: the original signing key is not on this PC, §9). |
| O1 | One transient production 500 on `criterion_results` (learner app); the same request returned 200 at once. | Watch; not reproducible. |
| O2 | Opening a released assessment that allows retries starts a new attempt without a confirmation (from the local audit). | Not changed; D5 avoids offering that path from the notification. |
| O3 | An open homework screen does not refresh itself on release (from the local audit). | Not changed; notification and Progress update live. |
| O4 | A new quiz draft version starts empty (by design: "Add and review its questions"). | Suggestion: offer to copy the published questions. |
| O5 | The COC practice timer is per device (by design: it controls local practice availability only). | None. |
| O6 | Dashboard page loads take 3–11 s on Vercel (server render). | Monitor; consider a closer region or caching. |

## 8. Post-publish verification (2026-11-20, after B1)

Production stayed read-only except one authorized TEST ONLY assignment and the test learner's attempt
on it. Nothing was evaluated, finalized, released, pushed, merged, deployed or migrated.

**COC1 M2 simulation assessment, end to end (PASS).**

- Instructor: in the TEST ONLY class, the form selected "Install Internal Components — simulation
  assessment" (v2, `28fc0297-…`, label "Simulation assessment", type Assessment), and
  `assign_activity` returned 200. The new row appeared after a page reload.
- Learner (emulator, 1.2.0 debug): the assignment appeared and opened the 2D bench in assessment
  mode ("No hints are shown"), not the form.
- The run took 22 m 37 s:
  - 38 actions accepted, 2 refused, 1 correction and 1 power-on fault.
  - Deliberate errors:
    - a processor in the wrong orientation (refused, "Component Not Seated");
    - memory in DIMM_A1 (accepted silently, as assessment mode intends), then removed and reseated
      in A2/B2;
    - a SATA power cable on the 24-pin header (refused);
    - SATA data left off, so the first POST measured "No boot device detected"; after the cable was
      connected, the second POST reported "Boot drive detected".
  - The typed interpretation was recorded, then the evidence review showed 5 phases and 46
    synchronized events, and the submit confirmed "Evidence submitted for authoritative evaluation
    and review".
- Learner Home showed "Official assessment · Awaiting instructor review". No result was visible.
- Instructor Evaluation Center listed the attempt as 10 / 11, "Evaluated (automatic)", provisional,
  stage Evaluate, with 48 chronological evidence events.
- The rubric is "COC1_M2 simulation step rubric", with 11 criteria. C3 "CPU seated in the correct
  orientation with the lever closed" is not satisfied:
  - its rule is `Max Incorrect: 0`, and the one wrong-orientation attempt counts even after the
    correct reseat;
  - C1 (ESD) has the same zero tolerance;
  - the other nine allow two incorrect actions, so C5, C9 and C10 (one incorrect each) are
    satisfied.

**All 20 packages, read-only through the admin session (PASS).**

- Totals:
  - 20 missions, each with v1 (published) and v2 (published, assessment, bench payload);
  - 40 activity versions and no duplicate version numbers;
  - 20 approved rubrics with 106 criteria, numbered 1..n with no duplicate codes;
  - 40 links (20 simulation, 19 form_based, 1 protected_reference), with no orphans or duplicates.
- Every link resolves to a curriculum module, and v1 and v2 of each mission link to the same
  learning outcome.
- Each v2 payload and its criteria are hash-identical to the locally emitted package (20 / 20).
  Each `definition_version` equals `MissionSimulationDefinitions.contractVersion()` for its mission,
  so `requiresAppUpdate` is false for all 20.
- COC1 M2 uses `css-assembly-20261119-v3` with the 11 criteria above.
- `evaluator_config` returns 403 even for an admin session, by design.

**APK.** The working tree at `6c41503` builds a debug APK with the production defines:
- 236,675,164 bytes, 1.2.0 (3);
- signed with this PC's debug certificate `271cbbf0…`.

The new build was installed in place on the emulator:
- D4: the screen shows 16 % and announces "16 percent".
- D7: no "deactivated widget" error during about 100 s of navigation across three polls. The
  pre-fix build had logged one; the error was intermittent, so the widget test remains the proof.

The release signing decision is still open:
- learners' 1.1.0 is signed with `a4d01056…`;
- the 2026-11-13 production key `dc85ef75…` and `android/key.properties` are not on this PC.

**New minor findings (not fixed).**

| # | Finding | Suggestion |
|---|---|---|
| F1 | Phone portrait, phase 5: the task panel is about 300 px tall, so the readout, the interpretation field and its button need inner scrolling, and a tap on the card does not focus the field. | Scroll the field into view when a test completes, or give the panel more height in that phase. |
| F2 | After submitting, Exit shows "Your current mission progress will remain available when you return." | Use submitted-state copy, or skip the dialog. |
| F3 | The class sheet lists the submitted assessment with only "Open activity" (Home shows "Awaiting instructor review"); with retry enabled, opening it can start attempt 2. | Show the status in the class sheet. |
| F4 | `test_run_interaction.dart` hardcodes "Run test", "Record test interpretation" and related labels (AGENTS 3.2). | Move them to `mission_content_data.dart`. |

## 9. Production migration `20261120110000` (D5) and release state (2026-11-20)

The owner approved this step; the owner signed in to the Supabase dashboard themselves.

| Step | Result |
|---|---|
| Target | The dashboard and the CLI both show the ByteQuest project `rslmteqipxqfifwftugk` (production, Free plan). The dashboard states "Free Plan does not include project backups". |
| Backup | A fresh encrypted read-only logical backup in `%LOCALAPPDATA%\ByteQuest\Recovery\rslmteqipxqfifwftugk-20261120-d5`: snapshot `0000000E-00002DE7-1`, 148 relations, 7,430 rows, TLS verify-full, AES-256-GCM with a DPAPI key. The first two attempts failed before reading any data, because the pooler did not yet accept the fresh temporary login-role password. The script now probes with `SELECT 1` and retries that error only (commit `002b2d7`). |
| Restore check | The backup was restored into a network-disabled tmpfs container. All 148 relations' row hashes match. |
| Rehearsal | `scripts/release-migration-batches.mjs --from 20261120110000` produced one batch containing only this migration, plus an already-applied guard, timeouts and the version record (sha256 `6a4a6310…`). On the restored copy it ran in 0.13 s, changed none of the 7,158 pre-existing rows checked, and 42/42 SQL suites passed. |
| Pre-check (production) | The version was not recorded (101 versions), and the old function and trigger were present (md5 `22a60882…` / `3585e971…`). |
| Apply | The batch hash matched the manifest and the rehearsal evidence; then `supabase db query --linked -f .tmp/release-d5/batch-b.sql` ran, exit 0. `db push` was not used. |
| Verification | Production now equals the rehearsed copy on all nine fingerprint fields: version recorded (102), function md5 `ba034ddc…`, trigger md5 `6ae35387…` with `quiz_result.released` and `result.released`, SECURITY INVOKER, `search_path=''`, ACL `postgres` only, trigger enabled. `scripts/release-readback.sql` reports latest version `20261120110000`, no public table without RLS, and 20 published simulation assessments. |

**Screenshots.** OCR of all 24 screenshots at 3× scale found the instructor's display name only in d01–d03 (the header account chip). Those three were redacted ("Name redacted"), and OCR then found no part of the name. The unpushed commits were rewritten so the original images never reach GitHub.

**APK.** The release is blocked on signing:
- the learners' 1.1.0 is signed with `a4d01056…`;
- this PC's only Android key is its own debug key `271cbbf0…`, created 2026-07-31;
- the 11-13 production key `dc85ef75…` and `android/key.properties` are absent;
- a full-disk search found only two Expo template debug keys (`FA:C6:17:45…`).

An APK signed with any of these keys would not install over the learners' app without an uninstall, so none was built.
