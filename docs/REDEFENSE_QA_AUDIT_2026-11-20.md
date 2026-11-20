# ByteQuest Re-Defense QA Audit — 2026-11-20

End-to-end QA of the re-defense build (defense: Monday 2026-11-23). Everything below was exercised
by hand in the running applications — the web dashboard in Playwright, the learner app on an Android
emulator and in the Flutter web build — and cross-checked in the local database. Source code was read
only to locate the cause of a defect.

The audit ran in two passes on the same day. The **first pass** covered all 38 panel requirements and
left three items PARTIAL. The **second pass** completed those three items (AI quiz generation,
automatic quiz submission, the review-queue limit) with controlled test accounts and data, and
reviewed the remaining drag-and-drop realism issues (RAM latches, the CPU lever, part sizing, mobile
tap targets). Second-pass results are marked *(pass 2)*.

Screenshots referenced below are in [`qa-audit-2026-11-20/`](qa-audit-2026-11-20/).

## 1. Verdict

**Ready for the re-defense from the local stack.** All 38 panel requirements pass. The critical panel
requirement — a realistic, hands-on 2D hardware assembly — passes with both touch and mouse. Two
complete assessment runs (one by mouse, one by touch on the fixed build) were auto-evaluated
**11/11 criteria satisfied**, and a touch practice run was server-verified. Fifteen defects were found
and fixed with regression tests; none remain open that block a demonstration.

What still stands between the build and a *hosted* demonstration is deployment, not code (section 9):
the Vercel production dashboard still serves the old code, the 1.2.0 APK is not signed or released,
and the live AI provider depends on a server key that could not be checked from this PC.

## 2. Environment and safety

| Item | Value |
|---|---|
| Database / API | Local Supabase in Docker: API `http://127.0.0.1:57321`, DB `57322` |
| Dashboard | Local production build, `next start -p 3001` (rebuilt after the fixes) |
| Learner app | Debug APK 1.2.0 (3) on AVD `padala_pixel7` (Android 16 / API 36, 1080×2400, 420 dpi); Flutter web build on `127.0.0.1:3009` |
| Backend targets verified before writes | Dashboard `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:57321`; `BQ_AI_TEST_ENDPOINT` and `BQ_ISOLATED_QA` unset. Emulator builds: `http://10.0.2.2:57321` (first build) and `http://127.0.0.1:57321` with `adb reverse` (later builds) |
| AI provider *(pass 2)* | No `OPENROUTER_API_KEY` exists on this PC, so no request could or did reach OpenRouter. For R3.3 the local dashboard ran with a dummy key and a QA-only Node start-up hook that answers every OpenRouter call with the repository's offline simulator (`scripts/quiz-ai-local-provider.mjs` on `127.0.0.1:3007`) and refuses any other OpenRouter URL. The production code path was unchanged. The dashboard was restarted without the hook afterwards. The repository's own simulator mode could not be used: its fixed address `127.0.0.1:58921` falls inside a Windows-reserved port range (58827–58926) on this PC |
| Accounts | Local QA accounts only: `qa.admin`, `qa.instructor2` (`@bytequest.local`), learner *QA Assembly Tester* (`qa.assembly.a@bytequest.invalid`) and, in pass 2, eight throwaway learners *QA Queue Learner 01–08* (`qa.queue.NN@bytequest.invalid`) |
| Production | Not touched. No Vercel deploy, no production migration, no APK release, no deletion of learner records |

Test data created (local only):
- Class *QA Audit 2026-11-20 (test class)*.
- One technical assessment.
- One quiz with an essay.
- One homework.
- A 5-row roster import.
- One temporary curriculum topic that was published, unpublished and archived again.
- *(pass 2)* Two quizzes: *QA R3.3 AI draft quiz (simulated provider)* and *QA R3.5 deadline auto-submit quiz*.
- *(pass 2)* Eight queue learners with 6 submitted and 8 in-progress assessment attempts, driven through the learner API as the app does it.
- *(pass 2)* One practice phase replay on the device.

## 3. Critical requirement — 2D drag-and-drop hardware assembly (COC1 M2)

### 3.1 Runs completed as a learner

| Run | Input | Build | Result |
|---|---|---|---|
| Practice | Touch (emulator) | Before fixes | Server-verified run 1: contract `css-assembly-20261119-v3`, 1,317 s, 46 actions, 5 invalid, per-step results recorded; +50 points; achievements *First Verified Mission* and *Assembly Ready*. Included a deliberate mistake (RAM in DIMM_A1/B2): the POST reported single-channel memory, the modules were reseated in A2/B2 and the re-test reported dual-channel. |
| Assessment 1 | Mouse (Flutter web) | Before fixes | 42 events; auto-evaluated **11/11**; instructor Evaluate → Finalize → Release; learner sees *Competent · 11/11 · 100 %*. |
| Assessment 2 | Touch (emulator) | **After fixes** | 35 actions accepted, **0 refused**, 0 corrections, 0 power-on faults; auto-evaluated **11/11** (attempt `5e4743fd…`; later evaluated, finalized and released during the live-refresh test). |
| Practice replay *(pass 2)* | Touch (emulator) | **Pass 2 build** | Returned to phase 2 of the practice run and worked the new physical rules by touch (3.3, fixes 10–14): refused removals and the blocked lever recorded nothing (counts stayed at 40 / 43 accepted, 5 refused). The module came out upright and went back in A2 by drag on the first try. |

### 3.2 Checklist

| Panel expectation | Result | Evidence |
|---|---|---|
| Select and drag individual components | PASS | Each part is a tray tile with its photograph; tap selects (Rotate and destination chips appear), drag lifts it. |
| Component follows the finger / cursor | PASS | Mid-drag captures show the part photograph (with its orientation marker) under the finger (`a02`) and under the cursor (`m01`). |
| Realistic placement and connection points | PASS | Socket, cooler mounting holes, four DIMM slots, rear I/O cutout, standoffs, PSU bay, drive bay, CPU_FAN, 8-pin EPS, 24-pin ATX, SATA data/power and F_PANEL headers sit on the board and case photographs. *(pass 2)* The drive and power-supply photographs now fill their bays (`a19`). |
| Correct component and position required | PASS | Category, prerequisite and orientation checks: CPU only with the lever open and the triangle aligned; RAM only with the latches open and the notch aligned; physically possible mistakes (wrong DIMM pair) are accepted and surface at POST. *(pass 2)* Removal follows the hardware too: a module only with its latches open, the CPU only with the cooler off and the load plate open. |
| Snapping | PASS | A drop inside a slot snaps the photograph into the exact slot rectangle with a 150–250 ms seat animation (widget-tested; visible in `a04`–`a07`). |
| Meaningful feedback on incorrect placement | PASS | Practice: technical reasons. Assessment: neutral ("Component not seated.", "Action recorded."). **Fixed:** a drop over no target now says *"Release the part over a slot, bay or header on the bench."* (`a03`); equipment that cannot be worked yet explains itself (`a01`); *(pass 2)* a held part or lever names what holds it (`a14`, `a18`). |
| Logical sequence | PASS | Six phases: prepare work area (ESD, inspection) → prepare motherboard → install into case → connect power and data → power-on test → review. Lever, latch and screwdriver prerequisites enforced. |
| Visual feedback when selected / moved / positioned / installed | PASS | Selected tile highlighted; drag ghost; hover frame on the target (`m02`); seat animation; installed tiles show a green check; levers, latches, screws, thermal compound and cables are drawn in their new state (`a04`–`a07`). |
| Learner actively involved | PASS | 35–46 deliberate actions per run, including rotation, levers, latches, thermal compound, screws, cable routing, a POST and a written interpretation. |
| Touch and mouse | PASS | Full runs by touch (emulator) and by mouse (web). Tap-to-place and screen-reader paths are covered by widget tests. *(pass 2)* Every ring now takes a touch at least 48 dp across (`a15`). |

### 3.3 Assembly defects found and fixed

First pass:

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

Second pass *(pass 2)*. The bench refuses these before the equipment rules, so the server contract
`css-assembly-20261119-v3` is unchanged:
- every refusal records nothing;
- practice names what holds the part;
- assessment says only *"… cannot be removed yet. Finish the work it depends on first."*

10. **RAM pulled out with the latches locked.** A seated module came out with one tap on Remove while the
    latches were shut (moving it to another slot already required open latches). Now the latches hold
    it: *"The DIMM latches hold the module in its slot. Open the latches to release it, then lift it
    out."* Verified by touch (`a14`): counts unchanged, module still seated.
11. **CPU lever worked under the mounted cooler.** The lever could be lifted with the cooler pressing on
    the load plate. The lever ring is now hidden while the cooler is mounted. The tray button
    explains instead: *"The mounted cooler presses on the socket load plate. Take the cooler off before
    lifting the load lever."* (`a18`).
    - Closing a lever left open stays possible. The server's repair scoring expects that move, so
      blocking it would charge an extra correction.
    - The processor can be lifted out only with the cooler off and the load plate open.
    - The I/O shield can come out only with the motherboard out.
12. **Removed parts returned "boxed".** A module taken out of its slot came back at its 180° packaging
    orientation and had to be turned twice again. It now keeps the orientation it was seated in. On the
    device it went back into DIMM_A2 by drag on the first try (`a16`, `a17`).
13. **Small drive and power-supply photographs.** Both photographs have wide transparent margins and
    were fitted by their full image frame. The visible part is now fitted to the bay (`a19`).
    - Drive: about 52 × 74 → 85 × 121 canvas units.
    - Power supply: fills the bay height.
14. **Rings ~24 dp on a phone.** Each ring now takes a tap anywhere in a reach area of at least 160
    canvas units: 48 dp on a 360 dp phone and 55 dp on the 412 dp emulator. Where reaches overlap,
    the nearest ring wins.
    - The drawn ring keeps its size.
    - A slot under a reach still takes the part in hand.
    - Parts on the mat keep their own taps.
    - Verified by touch: a tap 50 px beside the drawn latch ring opened the latches (`a15`).

### 3.4 Remaining assembly gaps (not fixed)

- **DIMM slots.**
  - Each slot is 13.6 dp wide at the default zoom on a 412 dp phone. That is the real slot pitch on
    the board photograph, so the slots cannot be widened without overlapping.
  - Mitigations: the hover frame shows which slot a dragged module will enter; every slot has a 48 dp
    destination chip in the tray; the bench zoom goes to 3×, which makes slots 41 dp.
- **Power supply.** The power-supply photograph shows the fan face, so in the side view of the case
  it fills the bay height but not its width. A side-view photograph would be needed.
- **Other realism gaps (unchanged):**
  - the fan cable's drag image is the fan photograph;
  - the I/O shield tile uses a generic icon;
  - the screwdriver exists only as a tray button;
  - the wrist strap is not drawn as worn.
- **Copy:**
  - tour page 3 mentions "Place equipment / Connect ports" tabs the bench does not have;
  - accessibility labels expose raw IDs (`cpu_fan_header`, `board_eps8`);
  - the step clock restarts at the first action;
  - long hints are cut at two lines (full text behind the info button).

## 4. Panel requirements (38)

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| R2.1 | Selectable/draggable components, rotation, visual response, realistic visuals | PASS | Section 3; rotation markers (CPU triangle, RAM notch, PSU fan) in tile, ghost and preview. Bay photographs fill their bays (pass 2). Remaining cosmetic gaps in 3.4. |
| R2.2 | Multiple sequential assembly steps | PASS | Six phases derived from the learner's actions. |
| R2.3 | Logical placement, validation, prevention, correction, progress | PASS | Prerequisites, orientation, POST-revealed mistakes, reseat and re-test; server verifier. Pass 2: removals and the lever follow the latches, load plate and cooler (3.3, 10–11). |
| R2.4 | Smooth drag, snap, highlight, indicators, animation, hints, feedback | PASS | After fixes 1–5 and 12–14 (3.3). |
| R2.5 | Record steps, incorrect attempts, time, completion; feed analytics | PASS | `practice_mission_runs` row (1,317 s, 5 invalid, step results); analytics Missions tab shows runs, time, invalid actions per run and most-missed steps. |
| R3.1 | Quizzes by COC → module → topic → LO with focus, type, difficulty, time limit, deadline, attempts | PASS | Authoring cascade, 10-minute limit, one attempt, deadline; pass 2 added a 1-minute and a deadline-only quiz. |
| R3.2 | Official topics and LOs, correctly associated | PASS | Curriculum with TR line references; admin curriculum management. |
| R3.3 | AI generation, regenerate one question, edit/delete/add/preview/draft/publish | PASS | **Pass 2.** Quiz COC1 · LO1.1 · PC 1.1 + PC 1.4 · focus · foundation · 1-minute limit. **Generate:** "Quiz curriculum" source; the generate button stays disabled until the OpenRouter consent box is ticked (`w07`); 4 drafts (multiple choice, true/false, identification, scenario essay with a 2-criterion rubric), each *Needs review · AI draft*; `ai_quiz_generations` row: `source_mode curriculum`, 1 module, 2 outcomes, consent recorded. **Regenerate one question** (with reason): replaced in position 2; the original kept as removed with its reason. **Edit** the MC question, **delete** the essay (with note), **add** a manual true/false, **approve** all 4 (`w08`), **preview** (`w09`), **publish** to the class with a deadline. **Failure path:** an invalid model reply → *"OpenRouter returned incomplete, duplicated, or unsupported questions. No question was saved"*; generation logged `failed / OPENROUTER_INVALID_RESPONSE`, 0 items. **Audit:** `quiz.ai_draft.requested` / `completed`, `quiz_item.regenerated`, `quiz_item.removed`. **Limit:** the OpenRouter call itself was answered by the offline simulator (section 2); a live model call needs a server key (section 9). |
| R3.4 | Scenario essay, rubric scoring, instructor evaluation | PASS | Essay with 2-criterion rubric; scored 5 + 4 with feedback; finalized, released; learner sees 10/11. |
| R3.5 | One attempt, deadline, auto-submission, statuses, timestamps, essay pending | PASS | First pass: one attempt ("Submitted — Attempt used"), timer, autosave, deadline, "Awaiting instructor evaluation". **Pass 2, time limit** (phone, 1-minute quiz, 1 of 4 answered): the app warned *"Less than a minute left…"* (`a20`); at expiry it opened *"Auto-submitted when the time limit ended"* · 1/4 (`a21`). DB: `submission_kind auto_time_limit`, submitted exactly 1:00 after start, system audit `quiz_attempt.auto_submitted`. **Pass 2, deadline** (deadline 08:52 Manila, 1 of 2 answered, app force-stopped): at 08:52:05 the attempt was still `in_progress` (processing is lazy). Opening the instructor's results finalised it (`auto_deadline`, submitted at exactly 08:52:00). Results showed *"Auto-submitted at the deadline · 1/2"* and per-question answered counts (`w10`). On reopening the app the learner saw the same result (`a22`). |
| R3.6 | Library filters, drafts, published review, results, class performance, archive | PASS | Search, COC, module, topic, type, status filters and sort; results summary, distribution and per-question analysis. |
| R4.1 | Homework by COC/mission with objectives, criteria, requirements, max score, status | PASS | Created with COC1/M2/LO1.1, objectives, 10-point criterion; shown on mobile. |
| R4.2 | Learner views, submits, uploads, sees status, feedback, score | PASS | Written answer + PNG upload + review + single submit on the emulator; after release: *Score 9/10*, criterion score and feedback (`a09`). See 8.3 for the emulator upload note. |
| R4.3 | Instructor filters, missing work, files, grading, late tracking, grader name | PASS | `/submissions`: class/learner/COC/mission/status/late filters, missing-work view, file download, *On time* label, "Graded by QA Second Instructor" (`w03`). |
| R5.A | Overall performance with period and population | PASS | Population and period labels; pending evaluations separate. |
| R5.B | Class performance and comparison | PASS | Comparison table with averages, rates, highest/lowest, drill-down (one class in scope). |
| R5.C | Individual learner progress | PASS | Learner profile: progress 1 of 25, performance 95.5 %, evaluation stages, engagement, COC → module → topic tree. |
| R5.D | Quiz analytics | PASS | Participants, completion, average/high/low, pending, 10-point distribution, per-question correctness; pass 2 also showed the auto-submitted count. |
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
| R11.2 | Nonfunctional or misleading UI | PASS | First pass verified: `?tab=` class card links, upcoming tasks from real deadlines, quiz-deadline dialog order, filtered `/users?status=inactive`, real Rewards tab. **Pass 2, review queue.** Eight learners; 6 submitted attempts awaiting review, then 8 newer attempts in progress. The old logic (pending among the 8 newest) gives **0 of 8**; the exact count is 6. The overview showed *Awaiting review 6*, the banner *"6 assessments waiting for review"* and the queue *"Showing the 5 oldest of 6 items awaiting review"* (`w05`). *View all* → Evaluation Center *Evaluate · 6 items* (`w06`). **Pass 2 fix:** Upcoming tasks titles were squeezed to 0 px at 1440 px (fixed, 8.1 #15, `w11`). Cosmetic issues in 8.4. |
| R11.3 | Mobile/web consistency | PASS | Same catalog and progress figures (R7). |
| R11.4 | Role checks on every action | PASS | Learner refused on the dashboard; learner `release_attempt` → `CLASS_SCOPE_DENIED`; learner Evaluation Center API → 403; all staff pages scope-checked. |
| P12 | Testing | PASS | Section 7. Physical-device and TalkBack runs were not part of this audit. |

**Totals:** 38 PASS · 0 PARTIAL · 0 FAIL · 0 BLOCKED. R3.3 passes on the app's own pipeline. The
OpenRouter model itself was stood in for by the offline simulator because no key exists on this PC.

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
- *(pass 2)* **AI quiz generation** end to end (R3.3), **quiz results** with automatic submissions
  (R3.5), **review queue** with more than eight attempts (R11.2), and the **Upcoming tasks** fix
  (titles visible at 1440 px; `w11`).

## 6. Android results

- Install, upgrade and launch of 1.2.0 (3); sign-in; onboarding skip.
- Home "Needs your attention", class space, quizzes, homework, files.
- **Class-space assessment opens.** It used to fail with *"no installed mobile simulation mapping"* (fixed).
- Practice tab with the COC timer; Learn tab; Progress (released results, quiz score, homework status).
- Rewards; notifications, including *Homework Result Released*.
- The full touch assessment from section 3.
- *(pass 2)* The emulator had restarted from an old snapshot with app 1.0; the 1.2.0 build was
  reinstalled. Both automatic quiz submissions (time limit in the foreground, deadline with the app
  closed) were completed as the learner (R3.5). The new assembly rules were checked by touch (3.1).

## 7. Automated results (after all fixes)

| Suite | First pass | Pass 2 |
|---|---|---|
| Flutter full suite (Docker `ghcr.io/cirruslabs/flutter:3.44.0`) | 720 passed, 1 skipped, 0 failed | **727 passed, 1 skipped, 0 failed** (3:56) |
| Flutter `assembly_bench_test` | 50 passed | **57 passed** (7 new: holds, assessment wording, lever under cooler, ring reach, slot priority inside a reach, mat taps, bay fill) |
| `flutter analyze --no-fatal-infos` | 0 errors, 0 warnings, 210 infos | 0 errors, 0 warnings, 210 infos (all pre-existing); changed files: *No issues found* |
| Dashboard `tsc --noEmit` | exit 0 | exit 0 |
| Dashboard `pnpm lint` | no warnings or errors | no warnings or errors |
| Dashboard `pnpm test` | 222 passed | 222 passed; the Upcoming tasks assertion fails without the fix and passes with it |
| Dashboard `pnpm build` | success | success |
| SQL rollback suites | not re-run (no SQL changed); 42/42 in the production rehearsal | not re-run (no SQL changed) |

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
| 10 | Moderate *(pass 2)* | RAM removable with the latches locked | Bench refuses the removal and names the latches; neutral in assessment; nothing recorded | 3 widget tests (incl. the POST repair flow), verified by touch |
| 11 | Moderate *(pass 2)* | Socket lever worked under the mounted cooler; CPU and I/O shield removable while held | Lever ring hidden and tray button explains; CPU only with cooler off and lever open; I/O shield only with the board out | widget test, verified by touch |
| 12 | Minor *(pass 2)* | Removed part returned at its packaging orientation | Keeps its seated orientation | 2 widget tests, verified by touch |
| 13 | Minor *(pass 2)* | Drive and power supply small inside their bays | Visible photograph content fitted to the bay | widget test, verified on device |
| 14 | Moderate *(pass 2)* | Rings ~24 dp on a phone (below the 48 dp minimum) | Reach area ≥ 160 canvas units (≥ 48 dp from 360 dp width), nearest ring wins, slots keep priority with a part in hand | 3 widget tests, verified by touch |
| 15 | Moderate *(pass 2)* | Upcoming tasks titles and classes squeezed to 0 px wide in the overview card at 1440 px | Due date moved under the title; full title on hover | node test (fails before, passes after), verified in the browser |

Test tooling *(pass 2)*: the offline AI simulator answered only the approved-COC source. It now also
answers curriculum requests (one of the allowed performance criteria) and scenario essays. Every
simulated prompt starts with *"Simulated draft"*.

### 8.2 Open, not fixed

- **No notification when an assessment or quiz result is released.** The homework release notifies, but
  the learner-notification trigger has no case for `result.released` or `quiz_result.released`. This
  predates the revision and needs a database migration, so it was left for an approved change.
  *Update (production pass):* reproduced in production and fixed by migration
  `20261120110000_result_release_notifications.sql` (local only, awaiting approval); see
  `docs/PRODUCTION_QA_AUDIT_2026-11-20.md`, defect D5.
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
- The quiz start button label reads as a status ("Not started — 1 attempt available").
- Long feedback banners are cut at two lines (full text behind the info button).
- Staff *Sign out* still uses the global scope.
- *(pass 2)* The quiz result shows the submission time in device time without a zone. It read
  "12:52 AM" on the GMT emulator next to a deadline labelled "8:52 AM (Manila)". On a phone set to
  Manila time both read 8:52 AM.
- *(pass 2)* Truncated text in the narrow overview cards: titles in Upcoming tasks and names in
  Recent learner attempts.

## 9. Blockers outside the code

1. **Vercel.** Production still serves the old dashboard (production branch `new`). The account owner
   must promote the `main` deployment that contains this audit's dashboard fixes and set the
   production branch to `main`.
2. **APK.** 1.2.0 needs the signing decision (the 1.1.0 key is not on this PC) before release.
3. **AI provider *(pass 2)*.** AI quiz generation in a hosted demo needs `OPENROUTER_API_KEY` (with
   available credits) in the Vercel production environment. This PC has no key, so no live model call
   was made in this audit; earlier live calls passed on 2026-08-11 and 2026-09-16. To run one locally,
   put the key in the git-ignored `.tmp/quiz-ai.env` yourself (never in chat). Manual authoring works
   without a key.
4. **Supabase plan.** The organization is over its Free-plan quota; projects are restricted from
   14 Dec 2026.

## 10. Demo guidance for Monday

- **Assembly (touch path, section 3.1).**
  - Seat the CPU with the triangle aligned; work the lever, compound and screws at their rings.
  - Put the RAM in A2/B2, or show the A1 mistake surfacing at POST and its correction. To reseat a
    module, open the latches first; it comes out upright and goes straight back in.
- **Small DIMM slots on a phone.** Zoom the bench in (up to 3×) or use the slot chips in the tray.
- **Evaluation Center.** Move an attempt through Evaluate → Finalize → Release with the dashboard
  analytics open: the update appears without a reload.
- **AI quiz generation.** Use the hosted dashboard only after confirming the OpenRouter key is set
  there (section 9). Otherwise show manual authoring and the review/approve/publish gate.
- **Phone demo against the local stack.** Install the loopback build and run the two `adb reverse`
  commands first.
