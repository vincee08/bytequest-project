# ByteQuest Re-Defense QA Audit — 2026-11-20

End-to-end QA of the re-defense build (defense: Monday 2026-11-23). Everything below was exercised
by hand in the running applications — the web dashboard in Playwright, the learner app on an Android
emulator and in the Flutter web build — and cross-checked in the local database. Source code was read
only to locate the cause of a defect.

Screenshots referenced below are in [`qa-audit-2026-11-20/`](qa-audit-2026-11-20/).

## 1. Verdict

**Ready for the re-defense from the local stack.** The critical panel requirement — a realistic,
hands-on 2D hardware assembly — passes with both touch and mouse. Two complete assessment runs (one by
mouse, one by touch on the fixed build) were auto-evaluated **11/11 criteria satisfied**, and a touch
practice run was server-verified. Nine defects were found and fixed with regression tests; none
remain open that block a demonstration.

What still stands between the build and a *hosted* demonstration is deployment, not code (section 9):
the Vercel production dashboard still serves the old code, and the 1.2.0 APK is not signed or released.

## 2. Environment and safety

| Item | Value |
|---|---|
| Database / API | Local Supabase in Docker: API `http://127.0.0.1:57321`, DB `57322` |
| Dashboard | Local production build, `next start -p 3001` (rebuilt after the fixes) |
| Learner app | Debug APK 1.2.0 (3) on AVD `padala_pixel7` (Android 16 / API 36, 1080×2400, 420 dpi); Flutter web build on `127.0.0.1:3009` |
| Backend targets verified before writes | Dashboard `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:57321`; `BQ_AI_TEST_ENDPOINT` and `BQ_ISOLATED_QA` unset. Emulator builds: `http://10.0.2.2:57321` (first build) and `http://127.0.0.1:57321` with `adb reverse` (second build) |
| Accounts | Local QA accounts only: `qa.admin`, `qa.instructor2` (`@bytequest.local`) and learner *QA Assembly Tester* (`qa.assembly.a@bytequest.invalid`) |
| Production | Not touched. No Vercel deploy, no production migration, no APK release, no deletion of learner records |

Test data created (local only): class *QA Audit 2026-11-20 (test class)*, one technical assessment,
one quiz with an essay, one homework, a 5-row roster import, and one temporary curriculum topic that
was published, unpublished and archived again.

## 3. Critical requirement — 2D drag-and-drop hardware assembly (COC1 M2)

### 3.1 Runs completed as a learner

| Run | Input | Build | Result |
|---|---|---|---|
| Practice | Touch (emulator) | Before fixes | Server-verified run 1: contract `css-assembly-20261119-v3`, 1,317 s, 46 actions, 5 invalid, per-step results recorded; +50 points; achievements *First Verified Mission* and *Assembly Ready*. Included a deliberate mistake (RAM in DIMM_A1/B2): the POST reported single-channel memory, the modules were reseated in A2/B2 and the re-test reported dual-channel. |
| Assessment 1 | Mouse (Flutter web) | Before fixes | 42 events; auto-evaluated **11/11**; instructor Evaluate → Finalize → Release; learner sees *Competent · 11/11 · 100 %*. |
| Assessment 2 | Touch (emulator) | **After fixes** | 35 actions accepted, **0 refused**, 0 corrections, 0 power-on faults; auto-evaluated **11/11** (attempt `5e4743fd…`; later evaluated, finalized and released during the live-refresh test). |

### 3.2 Checklist

| Panel expectation | Result | Evidence |
|---|---|---|
| Select and drag individual components | PASS | Each part is a tray tile with its photograph; tap selects (Rotate and destination chips appear), drag lifts it. |
| Component follows the finger / cursor | PASS | Mid-drag captures show the part photograph (with its orientation marker) under the finger (`a02`) and under the cursor (`m01`). |
| Realistic placement and connection points | PASS | Socket, cooler mounting holes, four DIMM slots, rear I/O cutout, standoffs, PSU bay, drive bay, CPU_FAN, 8-pin EPS, 24-pin ATX, SATA data/power and F_PANEL headers sit on the board and case photographs. |
| Correct component and position required | PASS | Category, prerequisite and orientation checks: CPU only with the lever open and the triangle aligned; RAM only with the latches open and the notch aligned; physically possible mistakes (wrong DIMM pair) are accepted and surface at POST. |
| Snapping | PASS | A drop inside a slot snaps the photograph into the exact slot rectangle with a 150–250 ms seat animation (widget-tested; visible in `a04`–`a07`). |
| Meaningful feedback on incorrect placement | PASS | Practice: technical reasons. Assessment: neutral ("Component not seated.", "Action recorded."). **Fixed:** a drop over no target now says *"Release the part over a slot, bay or header on the bench."* (`a03`); equipment that cannot be worked yet explains itself (`a01`). |
| Logical sequence | PASS | Six phases: prepare work area (ESD, inspection) → prepare motherboard → install into case → connect power and data → power-on test → review. Lever, latch and screwdriver prerequisites enforced. |
| Visual feedback when selected / moved / positioned / installed | PASS | Selected tile highlighted; drag ghost; hover frame on the target (`m02`); seat animation; installed tiles show a green check; levers, latches, screws, thermal compound and cables are drawn in their new state (`a04`–`a07`). |
| Learner actively involved | PASS | 35–46 deliberate actions per run, including rotation, levers, latches, thermal compound, screws, cable routing, a POST and a written interpretation. |
| Touch and mouse | PASS | Full runs by touch (emulator) and by mouse (web). Tap-to-place and screen-reader paths are covered by widget tests. |

### 3.3 Assembly defects found and fixed

1. **Dead rings (major).** The socket lever, thermal-compound and PSU/motherboard/drive screw rings
   did not respond to taps. With a part in hand, a tap on a ring was recorded as an incorrect placement,
   which cost assessment points. The slot frame's `DecoratedBox` absorbed the hit test. The frame is now
   paint-only, and a tap on a ring is routed to the ring. Verified by touch: with the CPU in hand, the
   lever ring opened the lever (10 accepted, 0 refused); every screw ring worked.
2. **Silent missed drop.** A part released over no slot returned to the tray without a word (DIMM slots
   are ~14 dp wide on a phone). It now shows the hint above; nothing is recorded.
3. **Silent blocked equipment.** Tapping the mat ground stud before wearing the strap did nothing. It now
   says *"Clip the strap to the mat ground is not possible yet. Finish the work it depends on first."*,
   neutral in both modes and not recorded.
4. **Invisible thermal paste; lingering rings.** The compound was painted beneath the CPU photograph; it
   is now drawn over it (`a04`). Rings of operations that would change nothing (strap already worn,
   compound applied) are hidden.
5. **"Run test again" out of reach.** The button sat below the 11-line POST readout; it now sits under
   the test status (`a08`).
6. **Screen-reader regression caught before release.** The fix in (1) routed taps by position; a
   screen-reader double-tap has no position and could work the compound ring instead of installing the
   cooler. A new test reproduced it; slots and headers now carry their own semantic tap.

### 3.4 Remaining assembly gaps (not fixed)

- Realism: the PSU and drive photographs are small and portrait inside landscape bays; the fan cable's
  drag image is the fan photograph; the I/O shield tile uses a generic icon; the screwdriver exists only
  as a tray button; the wrist strap is not drawn as worn.
- Physical rules: RAM can be removed without opening the latches (and returns at 180°); the socket
  lever stays operable with the cooler mounted.
- Touch targets: rings measure ~24 dp and DIMM slots ~14 dp on a 412 dp phone. Every ring and slot has
  a 48 dp tray alternative, and a missed drop is now explained.
- Copy: tour page 3 mentions "Place equipment / Connect ports" tabs the bench does not have;
  accessibility labels expose raw IDs (`cpu_fan_header`, `board_eps8`); the step clock restarts at the
  first action.

## 4. Panel requirements (38)

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| R2.1 | Selectable/draggable components, rotation, visual response, realistic visuals | PASS | Section 3; rotation markers (CPU triangle, RAM notch, PSU fan) in tile, ghost and preview. Cosmetic gaps in 3.4. |
| R2.2 | Multiple sequential assembly steps | PASS | Six phases derived from the learner's actions. |
| R2.3 | Logical placement, validation, prevention, correction, progress | PASS | Prerequisites, orientation, POST-revealed mistakes, reseat and re-test; server verifier. Gaps in 3.4. |
| R2.4 | Smooth drag, snap, highlight, indicators, animation, hints, feedback | PASS | After fixes 1–5 (3.3). |
| R2.5 | Record steps, incorrect attempts, time, completion; feed analytics | PASS | `practice_mission_runs` row (1,317 s, 5 invalid, step results); analytics Missions tab shows runs, time, invalid actions per run and most-missed steps. |
| R3.1 | Quizzes by COC → module → topic → LO with focus, type, difficulty, time limit, deadline, attempts | PASS | Authoring cascade, 10-minute limit, one attempt, deadline. |
| R3.2 | Official topics and LOs, correctly associated | PASS | Curriculum with TR line references; admin curriculum management. |
| R3.3 | AI generation, regenerate one question, edit/delete/add/preview/draft/publish | PARTIAL | Manual add/edit/preview/review/approve/publish verified. AI generation was **not run**: it sends content to the external AI provider, which this audit did not authorise. |
| R3.4 | Scenario essay, rubric scoring, instructor evaluation | PASS | Essay with 2-criterion rubric; scored 5 + 4 with feedback; finalized, released; learner sees 10/11. |
| R3.5 | One attempt, deadline, auto-submission, statuses, timestamps, essay pending | PARTIAL | One attempt ("Submitted — Attempt used"), timer, autosave, deadline, "Awaiting instructor evaluation" verified. Automatic submission at expiry not exercised live (dialog states it; covered by the SQL clock tests). |
| R3.6 | Library filters, drafts, published review, results, class performance, archive | PASS | Search, COC, module, topic, type, status filters and sort; results summary, distribution and per-question analysis. |
| R4.1 | Homework by COC/mission with objectives, criteria, requirements, max score, status | PASS | Created with COC1/M2/LO1.1, objectives, 10-point criterion; shown on mobile. |
| R4.2 | Learner views, submits, uploads, sees status, feedback, score | PASS | Written answer + PNG upload + review + single submit on the emulator; after release: *Score 9/10*, criterion score and feedback (`a09`). See 8.3 for the emulator upload note. |
| R4.3 | Instructor filters, missing work, files, grading, late tracking, grader name | PASS | `/submissions`: class/learner/COC/mission/status/late filters, missing-work view, file download, *On time* label, "Graded by QA Second Instructor" (`w03`). |
| R5.A | Overall performance with period and population | PASS | Population and period labels; pending evaluations separate. |
| R5.B | Class performance and comparison | PASS | Comparison table with averages, rates, highest/lowest, drill-down (one class in scope). |
| R5.C | Individual learner progress | PASS | Learner profile: progress 1 of 25, performance 95.5 %, evaluation stages, engagement, COC → module → topic tree. |
| R5.D | Quiz analytics | PASS | Participants, completion, average/high/low, pending, 10-point distribution, per-question correctness. |
| R5.E | Mission performance with real attempt counts | PASS | Runs from `practice_mission_runs`, average time 21m 57s, 5 invalid actions per run, most-missed steps (`w02`). |
| R5.F | Criterion-based analysis | PASS | Strongest/weakest across assessment criteria, simulation steps and essay rubric criteria. |
| R5.G | Charts, tables, filters | PASS | Class, COC, module, topic, mission, quiz, learner and period filters; mission filter changes the result. |
| R5.H | Accuracy rules | PASS | Figures reconciled with the database (90.9 % = 10/11; 95.5 % = mean of 100 % and 90.9 %; 5 % = 1/20; 4 % = 1/25). A pre-enrolment practice run counts by the documented rule (practice belongs to the learner). |
| R6.A | Excel bulk import | PASS | 5 rows: 1 enrolled, 1 pending, 1 staff skipped, 2 invalid; CSV error report. |
| R6.B | Search, filter, sort, paginate learners | PASS | Search by name/ID/email; class and status filters; sortable columns; "Showing 1–16 of 16 · Page 1 of 1". |
| R7.A | One COC/module/topic/LO structure everywhere | PASS | Identical titles and codes on mobile and dashboard. |
| R7.B | Learn page with COC, modules, topics, outcomes, real completion | PASS | A topic published on the dashboard appeared in Learn (COC1 1 of 7 → 1 of 8) and disappeared when unpublished. |
| R7.C | Practice grouped by COC/module with locks | PASS | COC chips with lock state, module sections, mission status and runs, prerequisite text. |
| R7.D | One progress methodology | PASS | COC1 1 of 7 (14 %) on mobile Progress, Practice and the dashboard learner profile (14.3 %). |
| R8 | Sequential unlocking enforced server-side | PASS | Locks with prerequisite text; a learner-token insert for locked `coc1_m3` returned 403 (`practice_actions_progression_gate`). |
| R9.2 | Objective 2 — gamification | PASS | Rewards tab: 125 points, Level 2 Apprentice, 3 of 12 achievements with progress (`a10`); opt-in class leaderboard: the toggle set `profiles.show_on_leaderboard` to true and back to false (`a13`). |
| R9.4 | Objective 4 — Evaluate / Finalize / Release | PASS | Assessment, quiz essay and homework each moved through all three stages; the learner saw nothing before release. |
| R9.6 | Objective 6 — analytics and learner performance, live | PASS | Dashboard: with analytics open, a mobile homework submission updated it without reload (03:52:39 → 03:53:10, 0 → 1 submitted). Learner: with Progress open on the phone, an instructor release at 20:28:05 UTC changed "1 attempt awaiting release" to "You are all caught up" and added the result within ~8 s, untouched (`a11`, `a12`). The open homework detail screen is the exception (8.2). |
| R10 | Draft → Submitted → Evaluated → Finalized → Approved → Published, visible, audited, unpublish | PASS | Temporary topic through every stage, visible to the learner, unpublished and archived; each stage in `audit_events` with actor and time. |
| R11.1 | `evaluator_config` exposure | PASS | Learner-token read: *permission denied*. |
| R11.2 | Nonfunctional or misleading UI | PARTIAL | Verified fixed: `?tab=` class card links, upcoming tasks from real deadlines, quiz-deadline dialog order, filtered `/users?status=inactive`, real Rewards tab. Not exercisable: the 8-attempt review-queue limit. New cosmetic issues in 8.4. |
| R11.3 | Mobile/web consistency | PASS | Same catalog and progress figures (R7). |
| R11.4 | Role checks on every action | PASS | Learner refused on the dashboard; learner `release_attempt` → `CLASS_SCOPE_DENIED`; learner Evaluation Center API → 403; all staff pages scope-checked. |
| P12 | Testing | PASS | Section 7. Physical-device and TalkBack runs were not part of this audit. |

**Totals:** 35 PASS · 3 PARTIAL · 0 FAIL · 0 BLOCKED.

## 5. Web dashboard results

- **Admin (15 pages)** and **instructor (14 pages)**: every page returned 200 with no error text and
  no console errors.
- **Instructor workflows:**
  - class creation; Excel roster import;
  - learner search; technical assignment;
  - quiz authoring with essay and publish;
  - homework creation;
  - Evaluation Center for all three evaluation types;
  - `/submissions`;
  - analytics (6 tabs, quiz detail, learner profile);
  - deadline dialog.
- **Admin workflows:**
  - curriculum publication workflow end to end;
  - audit log;
  - users / learners / instructors lists with filters.
- **Learner on the dashboard:** refused with *"Learner accounts must use the ByteQuest mobile application."*
  After the fix the learner's mobile session survives the refusal. A learner token issued before the
  attempt still returned 200 from `getUser`, from the dashboard homework API and on refresh; before the
  fix it returned "Session not found" and 401.

## 6. Android results

- Install, upgrade and launch of 1.2.0 (3); sign-in; onboarding skip.
- Home "Needs your attention", class space, quizzes, homework, files.
- **Class-space assessment opens.** It used to fail with *"no installed mobile simulation mapping"* (fixed).
- Practice tab with the COC timer; Learn tab; Progress (released results, quiz score, homework status).
- Rewards; notifications, including *Homework Result Released*.
- The full touch assessment from section 3.

## 7. Automated results (after all fixes)

| Suite | Result |
|---|---|
| Flutter full suite (Docker `ghcr.io/cirruslabs/flutter:3.44.0`) | **720 passed, 1 skipped, 0 failed** (5:37) |
| Flutter `assembly_bench_test` + `assigned_mission_resolution_test` | 54 passed |
| `flutter analyze --no-fatal-infos` | 0 errors, 0 warnings, 210 infos (all pre-existing `prefer_const…`) |
| Dashboard `tsc --noEmit` | exit 0 |
| Dashboard `pnpm lint` | no warnings or errors |
| Dashboard `pnpm test` | 222 passed (159 + 47 + 16), 0 failed |
| Dashboard `pnpm build` | success |
| SQL rollback suites | not re-run (no SQL changed); 42/42 in the production rehearsal |


## 8. Defects

### 8.1 Fixed in this audit (with tests)

| # | Severity | Defect | Fix | Test |
|---|---|---|---|---|
| 1 | Major | Lever, compound and screw rings dead; ring tap with a part in hand scored as an incorrect placement | `_TargetFrame` paint-only; ring taps routed to the ring | 3 widget tests, verified by touch |
| 2 | Moderate | Missed drop silent | `onDraggableCanceled` hint | widget test |
| 3 | Moderate | Blocked mat ground stud silent | Blocked hotspot explains itself; nothing recorded | widget test, verified by touch |
| 4 | Minor | Thermal paste invisible; idle rings linger | Overlay painter; idle operations hidden | widget test, verified by touch |
| 5 | UX | "Run test again" below the readout | Button moved under the status | verified on device and web |
| 6 | Major | Dashboard refusal signed the learner out everywhere (global scope), breaking mobile dashboard-API features | `signOut({ scope: 'local' })` for refusals | 2 node tests, verified live |
| 7 | Major | Assigned assessment could not be opened from the class space (UUID looked up as a mission code) | `MissionsData.resolveAssigned` by mission code | 4 unit tests, verified on device |
| 8 | Moderate | Screen-reader tap on a slot could work an overlapping ring (introduced by #1, caught before release) | Explicit `Semantics.onTap` on slots and headers | widget test (failed before, passes after) |
| 9 | Minor | Progress screen debug assertion (`ListTile` ink inside a coloured card) | Transparent `Material` wrapper | analyzer clean; console clean |

### 8.2 Open, not fixed

- **No notification when an assessment or quiz result is released.** The homework release notifies, but
  the learner-notification trigger has no case for `result.released` or `quiz_result.released`. This
  predates the revision and needs a database migration, so it was left for an approved change.
- The open homework screen does not refresh itself when the grade is released (the notification and the
  Progress tab do show it).
- Opening a released assessment whose assignment allows retries starts a new attempt immediately, without
  a confirmation.

### 8.3 Environment note (not a product defect)

- **What fails.** With the emulator build that uses `10.0.2.2`, a homework file upload fails with
  "File could not be uploaded".
- **Why.** The dashboard signs upload URLs against its own `127.0.0.1` address. The app's origin guard
  (`homework_service.dart:160`) therefore rejects them, as designed.
- **Production.** Both sides use the same Supabase URL, so this cannot happen there.
- **Local demo.** Use the loopback build and `adb reverse tcp:57321 tcp:57321` plus
  `adb reverse tcp:3001 tcp:3001`. The upload worked that way.

### 8.4 Cosmetic

- Raw IDs in dashboard breadcrumbs ("96d10016 090f…").
- No toast after class creation.
- Activity option accessible names run together.
- The attempt evidence page title-cases IDs ("Css-Assembly-20261119-V3").
- The password input lacks `autocomplete`.
- Quiz essay *Finalize* uses a native `confirm()` while the other dialogs are styled.
- The duplicated "1 of 7 required items" in the Practice summary's accessibility label.
- The quiz start button label reads as a status.
- Long feedback banners are cut at two lines (full text behind the info button).
- Staff *Sign out* still uses the global scope.

## 9. Blockers outside the code

1. **Vercel.** Production still serves the old dashboard (production branch `new`). The account owner
   must promote the `main` deployment that contains this audit's dashboard fix and set the production
   branch to `main`.
2. **APK.** 1.2.0 needs the signing decision (the 1.1.0 key is not on this PC) before release.
3. **Supabase plan.** The organization is over its Free-plan quota; projects are restricted from
   14 Dec 2026.

## 10. Demo guidance for Monday

- Use the touch path shown in section 3.1. Seat the CPU with the triangle aligned; work the lever,
  compound and screws at their rings. Put the RAM in A2/B2, or show the A1 mistake surfacing at POST and
  its correction.
- Show the Evaluation Center moving an attempt through Evaluate → Finalize → Release, with the dashboard
  analytics open: the update appears without a reload.
- For a phone demo against the local stack, install the loopback build and run the two `adb reverse`
  commands first.
