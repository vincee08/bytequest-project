# ByteQuest Re-Defense Implementation Report

**Re-defense:** Monday 2026-11-23
**Branch:** `vince-branch` (local; not pushed)
**Scope:** the panel's revision comments (Phases 2–12 of the revision brief), Objectives 2, 4 and 6
**Inputs:**
- Audit: `docs/REDEFENSE_REVISION_AUDIT_2026-11-19.md`
- Approved design: `docs/superpowers/specs/2026-11-19-redefense-revision-design.md`
- Plan: `docs/superpowers/plans/2026-11-19-redefense-revision.md`
- Hosted rollout plan (awaiting approval): `docs/REDEFENSE_HOSTED_ROLLOUT_PLAN.md`
- Demo data guide: `docs/DEMO_DATA.md`

> Status legend: **Verified (automated)**: covered by passing SQL, Node or Flutter tests. **Verified (live, local)**: exercised in the running local system (Flutter web preview + local dashboard + local Supabase). **Not tested**: physical Android device, TalkBack, and the hosted production stack. Nothing has been deployed to hosted services; that step waits for the owner's approval.

---

## 1. Summary

Every panel item in the revision checklist has been implemented on `vince-branch`:

- **Phase 2 — assembly.** A realistic COC1 M2 assembly bench.
  - Real part images, an open case and a motherboard close-up.
  - Visible rotation with orientation markers, snapping into physical slots, and sequential steps.
  - Operations such as levers, latches and screws.
  - Cable routing, a power-on self-test with measured readings, and an interpretation step.
  - Evidence is recorded and replayed by the database.
- **Assessment.** One simulation engine with separate Practice and Assessment modes.
  - Assessment mode hides guidance and correct targets.
  - Every step is scored on the server: at most 2 incorrect attempts, 0 on safety-critical steps, instructor override with a reason.
  - Results go through Evaluate → Finalize → Release.
- **Quizzes.**
  - Linked to COC → Module → Topic → Learning outcome.
  - Focus, difficulty, time limit and deadline; AI drafts grounded in the official curriculum; scenario-based essays with rubric scoring.
  - One attempt enforced in the database, automatic submission at the deadline or time limit, and draft / published / closed / archived states.
- **Homework.** Linked to COC and mission, with criteria, maximum score, submission management, missing work, and the same evaluation workflow.
- **Analytics.** Overall, class, learner, quiz, mission (including practice runs), criterion and engagement views. Every number is computed by the database from real records; pending evaluations are shown separately and excluded from averages.
- **Learner management.**
  - Excel/CSV roster import (preview → confirm). Existing accounts are enrolled; new emails are pre-registered and auto-enrol on sign-up. Instructors never create accounts.
  - Server-side learner search.
  - Staff-managed student IDs.
- **Alignment.** One canonical curriculum: 16 official TR modules (learning outcomes) and 76 performance criteria, copied verbatim with source line references. Learn, Practice, Progress and the dashboard all read it, using one progress method.
- **Sequential unlocking.** Enforced in the database. The app shows locks, prerequisites and progress.
- **Objectives:**
  - Objective 2: points, levels, rewards, achievements, an opt-in leaderboard and progress tracking.
  - Objective 4: an automated skill evaluation against competency criteria, completed by the instructor's Evaluate → Finalize → Release.
  - Objective 6: a performance analytics dashboard for instructors, and a learner Performance section, both refreshing in real time.
- **Publication.** A draft → submitted → approved → published workflow for curriculum content, quiz questions and assessment results. Approved and published items are what learners see.
- **Integrity.** Evaluator answer keys are hidden from clients. RLS is on every table. No new SECURITY DEFINER functions beyond the approved list. No learner history was deleted.

Remaining before or at the defense (Section 8):
- the owner-approved hosted rollout;
- a physical-device pass;
- the minor items listed in Section 7.

---

## 2. How the work was done

1. **Audit.** The codebase was audited against every panel comment and written up as `docs/REDEFENSE_REVISION_AUDIT_2026-11-19.md`.
2. **Owner decisions.** Two rounds, recorded in the design, Section 4:
   - modules are the official TR learning outcomes;
   - the publication workflow applies to curriculum content, quiz questions and results;
   - roster import enrols existing accounts and pre-registers new emails;
   - assessments are unified on simulations, with separate Practice and Assessment modes;
   - local demo first, then hosted rollout with approval;
   - a labelled demo class;
   - threshold scoring (≤2 incorrect attempts per step, 0 on safety-critical steps, instructor override with a reason);
   - COC3 teaches LO3.2 first.
3. **Design and plan.** These were approved by the owner. The work was split into a foundation wave and seven parallel slices (A1–A7), each with exclusive file ownership:
   - **A1:** assembly bench and simulation assessment
   - **A2:** sequential unlocking, Learn/Practice/Progress and curriculum publication
   - **A3:** quizzes
   - **A4:** Evaluation Center and homework
   - **A5:** roster import, search, student IDs, UI fixes and app version
   - **A6:** gamification
   - **A7:** analytics
4. **Review loop.** Each slice got its own specification and quality review, then fix rounds until every Critical and Important finding was resolved, with scoped re-reviews after each fix.
5. **Integration.** All 39 migrations were applied in order on a fresh local database, the database types were regenerated, and the full gates ran.
6. **Browser QA.** The dashboard was checked at 1366, 1280 and 390 px, and the learner app in the Flutter web preview.
7. **Final whole-branch review.** Six parallel reviewers covered SQL part A, SQL part B with the security inventory, dashboard server, dashboard UI, Flutter simulation, and the rest of Flutter. Then one fix wave and a scoped re-review (Section 6.3).

---

## 3. Panel items — what was built and how it was verified

### Phase 2 — Realistic 2D hardware assembly (COC1 M2 "Install Internal Components")

| Panel requirement | What was built | Verification |
|---|---|---|
| Components individually selectable and draggable, with rotation and realistic visuals | Assembly bench scene with a real motherboard close-up and an open case. The tray uses real part images. Parts can be dragged or tapped to select. A Rotate control shows the part's orientation marker, which turns with the part: gold triangle on the CPU, notch on the RAM, fan on the PSU. A larger preview shows marker position and angle, e.g. "Notch: left edge · 0°". | Widget tests for marker rotation and tap/drag placement. **Live:** CPU, RAM and PSU orientation visible and enforced. |
| Multiple sequential assembly steps | Six phases with ordered steps:<br>1. Prepare the work area: inspect parts, wrist strap, mat ground point.<br>2. Prepare the motherboard (9 steps): socket lever, CPU orientation, thermal compound, cooler, CPU_FAN, DIMM latches, DIMM_A2/B2.<br>3. Install into the case (8 steps): PSU fan facing the intake vent, screwdriver, screws, I/O shield, motherboard on the standoffs, drive.<br>4. Connect power and data (5 cables).<br>5. Power-on test: POST with measured output, then interpretation.<br>6. Evidence review. | Contract `css-assembly-20261119-v3`. SQL suites `simulation_coc1_m2_contract`, `simulation_replay` and `simulation_sequence`. **Live:** full practice run completed. |
| Logical placement areas, validation, prevention and correction | Physical slots with category and orientation rules. Prerequisites follow real assembly order. Wrong placements get concise technical feedback, e.g. "The processor only drops into the socket one way…". Parts can be removed and reseated. A failed POST reveals the faults of missing steps, which the learner then corrects. | Server replay tests (valid, invalid, out of order, correction). Flutter widget tests. |
| Smooth drag, snap, highlights, indicators, hints and feedback | Snap into the slot rectangle. Compatible slots are highlighted in practice only. Operation-specific confirmations such as "DIMM latches opened.". "Show me how" outlines that follow the target under zoom and pan. Labelled hotspots ("Wrist strap", "Mat ground point"). | Widget tests, including 4 screen sizes with and without zoom. **Live** check. |
| Record steps, incorrect attempts, attempts, time, completion, criteria and final performance | Every action is stored as evidence. On verification the database replays the actions against the contract and writes a practice run: run number, duration, incorrect and correction counts, per-step results. Assessment attempts are scored per criterion (COC1 M2 has 11 criteria). The results feed instructor analytics and learner progress. | SQL suites. **Live:** server verification of a correct run returned `verified: true`, run 1, 3,568 s, 3 incorrect attempts. |

**Practice vs Assessment.**
- *Practice* shows guidance, compatible-slot highlights and "Show me how".
- *Assessment* shows none of these. It uses neutral confirmations ("Action recorded."), enforces the confirmed step order, and counts every physically possible mistake that had to be corrected.
- Scoring thresholds: at most 2 incorrect attempts per step; 0 for safety-critical steps (ESD/wrist strap, CPU orientation).
- A failed test run adds at most one incorrect attempt per step.
- Discard markers only apply to practice attempts.
- Simulation assessment packages exist for all 20 missions (102 criteria).

### Phase 3 — Quiz creation and management

| Requirement | What was built | Verification |
|---|---|---|
| COC → Module → Topic → LO organisation; focus, type, difficulty, time limit, deadline, attempts | Curriculum foreign keys and cascading selectors. Focus, difficulty and time limit are stored. One attempt is enforced in the database. | `quiz_redefense_*` SQL suites, form tests |
| No invented TESDA LOs | 16 modules and 76 performance criteria seeded verbatim from `docs/reference/tesda_sources/TR_current.txt` (Amended December 2013), each with a source line range | Foundation suite (seed against source references) |
| AI generation grounded in the curriculum | Prompts are grounded in the selected module, topic and LO, plus focus, difficulty and type. Generated items stay drafts until a human approves them. Single questions can be regenerated. | `quiz-ai-curriculum` Node tests with mocked provider |
| Scenario-based essay with rubric | `scenario_essay` item type with scenario, prompt, rubric criteria, points and word limits. The learner writes a long answer. The instructor scores against the rubric in the Evaluation Center. The result is final only after Finalize and Release. | `quiz_redefense_evaluation` suite; editor and mobile widget tests |
| One attempt, deadline, auto-submission, states | The server automatically submits saved answers at the deadline or when the time limit expires (deterministic). States: draft, published, closed and archived. Extensions and reopening are supported. Results are hidden from learners until released. | Clock-controlled SQL tests (expiry while answering, extension, reopen, expiry before release) |
| Management dashboard | Library filters by COC, module, topic and status. A results summary shows average, highest, lowest, completion, distribution and per-question difficulty, with links to the evaluation queue. | Node tests, browser QA |

### Phase 4 — Assignments (homework)

| Requirement | What was built | Verification |
|---|---|---|
| Categorised by COC and mission, with objectives, criteria, resources, maximum score and status | Optional COC and mission links. Objectives. A criteria list with points. Maximum score. Submission requirements. | `homework_redefense` suite |
| Learner view: filter, submit, upload, status, feedback, score | Mobile lists with COC and mission labels. Submission and upload flow. Grades and feedback appear only after release; learner replays are redacted until then. | SQL suite, including a leak regression; widget tests |
| Instructor view: filters, missing work, files, grading, late tracking | Submissions across assignments with filters, a missing-work view, late tracking, and grader names. Grading goes through Evaluate → Finalize → Release. | API tests, browser QA |

### Phase 5 — Performance analytics

Real-data RPCs, all SECURITY INVOKER and role-scoped:
- `get_analytics_overview`
- `get_class_performance`
- `get_learner_performance`
- `get_learner_profile_analytics`
- `get_quiz_analytics`
- `get_mission_analytics`
- `get_criteria_analytics`
- `get_my_performance` (the learner's own released results)

Filters cover class, COC, mission and period, including a custom date range.

What the analytics cover:
- **Quizzes.** Essays count only after release; until then they appear as pending evaluation.
- **Missions.** Assessment attempts plus practice runs: runs, verified runs, most-missed steps, average incorrect attempts per step, best times.
- **Criteria.** Assessment criteria, simulation conditions with step titles, and essay rubric criteria.
- **Engagement.** Points and level are shown separately from competency and scores.

Accuracy rules:
- unpublished quizzes are excluded;
- learners are counted from their enrolment date;
- there is no double counting;
- a learner in two classes is handled.

The dashboard refreshes through realtime, with 30-second polling as a fallback.

Verification: the `analytics_redefense` SQL suite (257 assertions), covering zero learners, pending evaluations, one learner in two classes, unpublished quizzes, and scope denial. Node tests check the dashboard data shapes. Browser QA covered the analytics tabs.

### Phase 6 — Learner management

- **Excel bulk import.**
  - Accepts `.xlsx`, `.xls` and `.csv` (SheetJS 0.20.3 from the official tarball) and offers a template download.
  - Validates rows and tolerates header case and spacing variants.
  - Detects duplicates, invalid emails and staff-account emails.
  - Shows a preview before you confirm, then a summary.
  - Existing learner accounts are enrolled. New emails are pre-registered and claimed automatically when that person signs up.
- **Search.** Server-side search by name, student ID, email and class, with status filter, sorting and pagination.
- **Student IDs.** Staff-managed, with a lock indicator; learners cannot change a managed ID.

Verification: the `roster_import` and `learner_search` SQL suites, roster parser Node tests (malformed files, duplicates, extra columns, `.xls`), and browser QA.

### Phase 7 — Align COC, Learn, Practice and Progress

One canonical catalog lives in the database:
- 4 COCs;
- 16 modules (COC1 4, COC2 4, COC3 3, COC4 5);
- topics;
- mission links.

Mission titles follow the practice contracts through a catalog sync trigger.

In the app:
- **Learn:** COC → modules with lock state, required items and completion.
- **Practice:** missions grouped by COC and module, with lock and prerequisite text.
- **Progress:** one methodology, the completion of required lessons, practice missions and COC practice quizzes. Per-COC and per-module completion, released results, class quiz scores, homework status, and a Performance section.

COC3 teaches LO3.2 first, as the owner decided.

Verification: the `module_progression` and `module_progression_projection` suites, Flutter widget tests, and live checks of Learn, Practice and Progress.

### Phase 8 — Sequential unlocking

- **Enforcement in the database.** A module unlocks only when the previous module's required items are complete. Evidence for a locked module is rejected by the database, so the API cannot be used to bypass it.
- **Existing progress.** Unlocks are permanent and were backfilled from existing progress, so no learner loses access.
- **Older app.** The installed 1.1.0 app keeps working for modules that are already unlocked.
- **In the app.** Lock icons, the prerequisite ("Complete Module 1 · LO1.1 … to unlock") and progress.

Verification:
- SQL suites, including the review-focus tests `backfill_keeps_existing_progress` and `legacy_unlocked_mission_accepts_evidence`;
- Flutter widget tests;
- live checks.

### Phase 9 — Objectives 2, 4 and 6 (verbatim from the owner)

| Objective | How it is met | Where to show it |
|---|---|---|
| **2.** "Use points, levels, rewards, achievements and tracking progress in the learning process to motivate and engage the learner." | **Points rules:**<br>- practice mission verified: 50<br>- topic completed: 10<br>- module completed: 100<br>- COC completed: 300<br>- quiz submitted: 20<br>- homework on time: 15<br>- assessment released: 40<br><br>**Levels:** six, from Trainee to Lead Technician (0 / 100 / 300 / 600 / 1000 / 1500 points).<br><br>**Achievements:** 12, such as First Verified Mission, Assembly Ready and COC 1–4 Complete.<br><br>**Also:** an opt-in leaderboard with privacy-preserving names, and progress tracking in Progress. Points are idempotent and motivational only; they never change competency results. | App: Rewards tab and Progress. Dashboard: the learner profile's "Engagement" section. |
| **4.** "Design & Develop an automated system for Skill Evaluation that will evaluate the learner's performance against the set competency criteria and the requirement for the completion of the competency tasks of TESDA CSS NC II." | The database replays simulation evidence against each mission's competency criteria and scores every criterion automatically. Thresholds and safety-critical rules are applied, and completion requirements are enforced.<br><br>The instructor's **Evaluation Center** then takes each item through **Evaluate → Finalize → Release**. This covers technical attempts, quiz essays and homework. Stages can't be skipped (the server enforces it), and an override needs a reason. | Dashboard: Evaluation Center (queues Evaluate, Finalize, Release and Released). App: Progress → released results. |
| **6.** "Create a performance analytics dashboard which allows learners and instructors to monitor learner progress, competency achievement, scores and assessment results in real time." | Instructor analytics (Phase 5) and the learner Performance section (`get_my_performance`) both refresh in real time. | Dashboard: Analytics. App: Progress → Performance. |

### Phase 10 — Approval and publication

- **Statuses.** Curriculum topics, topic revisions and quiz questions move through draft → submitted → approved → published. Unpublishing is supported. Who and when is recorded in `content_publication_events`.
- **What learners see.** Only approved and published content reaches the Learn page and quizzes.
- **Assessment results.** These follow Evaluate → Finalize → Release; nothing is released automatically.
- **"Website" interpretation.** ByteQuest has no public website, so "the website" means the instructor/admin dashboard and the learner app, as the owner decided.

Verification: the `curriculum_publication` suite and the quiz review/publish tests.

### Phase 11 — System-wide integrity

- **Answer keys protected.** `activity_versions.evaluator_config` is no longer readable by clients: there is a column grant that excludes it. Practice contract definitions are also unreadable; learners can read only the generated `step_titles` column.
- **Database safety.**
  - RLS is enabled on every table.
  - New logic runs as SECURITY INVOKER. Service-only functions are granted to `service_role` and called by authenticated routes with `p_actor`.
  - Only the SECURITY DEFINER functions listed in the design (Section 9) were modified.
- **Results privacy.** Learners never see unreleased results. This covers quiz totals and correctness, homework grades and essay scores, and is enforced by row gates plus redacted replays.
- **Migrations.** All are additive. No learner records, attempts, results, practice actions or audit events were deleted or rewritten.
- **UI fixes.** `?tab=` deep links, real upcoming deadlines, grader names, filtered user lists, and the header, filter and table layout fixes found in browser QA.
- **App version.** The app is at 1.2.0+3, and `app_release_config.min_supported_app_version` is 1.2.0.
  - The app sends its version on every request.
  - Simulation-assessment starts and essay-quiz starts are refused for apps that don't report at least that version.
  - From 1.2.0 onward, the app itself prompts for updates when the minimum version is raised.
  - The installed 1.1.0 app has no gate, so learners must install 1.2.0 after the rollout.

### Phase 12 — Testing

See Section 6.

---

## 4. Database changes

There are 43 additive migrations, `20261119100000` through `20261120100300`; see the commit history for each. They fall into these groups:

- **Foundation (3):** evaluator-config secrecy, the curriculum foundation with verbatim TR seed and mission links, and learner module completions.
- **A1, simulation (7):** the shared simulation replay, the `simulation_condition` evidence operator, the COC1 M2 v3 contract, unified completion acceptance, failed-check counting, confirmed-order answers, and assessment integrity.
- **A2, progression and publication (3):** sequential module unlocking, curriculum content publication, and the learner curriculum projection.
- **A3, quizzes (7):** the essay item type, curriculum links and essay authoring, time limits and auto-submission, essay evaluation and release, AI curriculum drafts, learner result visibility, and essay score ordering.
- **A4, evaluation (4):** the technical Evaluate step, the homework evaluation workflow, the evaluation queue, and homework replay redaction.
- **A5, learner management (5):** staff-managed student IDs, the app release config, class roster import, the roster claim on sign-up, and learner search.
- **A6, gamification (3):** points and achievements, rewards and the leaderboard, and a leaderboard refresh fix.
- **A7, analytics (6):** access, helpers, staff functions, learner performance, integration, and final sources.
- **Integration (1):** lets instructors read approved rubric versions of published activities, so they can assign the centrally published simulation assessments.
- **Final fix wave (4):**
  - the client app version guard;
  - Evaluation Center quiz items limited to active classes;
  - learners can no longer execute the provisional evaluation;
  - decision changes in assessments count as corrections, and foreign evidence is flagged for review.

**Hosted apply.** It runs in two batches:
- Batch A is `20261119130000` alone. It adds an enum value, which must be committed before it is used.
- Batch B is the other 42 migrations, in one transaction.

**Preservation.** Migrations are additive only. The backfills keep existing unlocks and completions. The only data changes to existing rows are the homework release backfill and the catalog title sync, both documented.

---

## 5. Demo data

`scripts/seed-demo-class.mjs` creates a clearly labelled demo class with 12 synthetic learners (surname "Demo") and realistic activity:

- practice runs, including failed ones;
- quizzes with essays;
- homework that is on time, late or missing;
- simulation assessment attempts at every evaluation stage;
- rewards and the leaderboard.

The script is idempotent and refuses non-local targets unless you pass `--target hosted --confirm`. `--remove` cleans up. See `docs/DEMO_DATA.md`.

---

## 6. Verification evidence

### 6.1 Automated gates (final run on the merged branch)

These gates ran on the merged branch after the final fix wave, on 2026-11-19, at head `afe4db9`.

| Gate | Result |
|---|---|
| Fresh local stack: `supabase stop --no-backup` + `supabase start` | PASS: all 102 migrations applied in order (59 earlier + 43 re-defense) |
| SQL rollback suites on the fresh database with QA fixtures | **41/41 suites passed** |
| Demo seed on the fresh database (`scripts/seed-demo-class.mjs`) | PASS. A rerun left all 81 public table counts identical (idempotent). |
| SQL rollback suites again, with the demo class loaded | **41/41 suites passed** (data-independent) |
| Dashboard `pnpm exec tsc --noEmit` | PASS (0 errors) |
| Dashboard `pnpm lint` | PASS (0 problems) |
| Dashboard `pnpm test` | **217/217** (154 + 47 + 16) |
| Dashboard `pnpm build` | PASS |
| Flutter `flutter analyze --no-fatal-infos` | PASS: 0 errors, 0 warnings (210 infos, as before) |
| Flutter tests (Docker `ghcr.io/cirruslabs/flutter:3.44.0`, with `supabase/` mounted so the contract-export parity tests run) | **711/711 passed** |
| `flutter build apk --debug` | PASS (`app-debug.apk`) |

The final gate run turned up two seed-script problems on the fresh-database path, both fixed in `dffcd21`:
- an unquoted path with spaces was passed through `cmd.exe`;
- the app-version lookup still pointed at a file the Flutter fix had moved.

The baseline before the revision was 480 Flutter tests, 28 dashboard tests and 15 SQL suites.

### 6.2 Live checks (local)
- **Dashboard browser sweep.** 60 page loads at 1366, 1280 and 390 px as admin and instructor: no errors and no console errors. The header, filter and table layout issues it found are fixed.
- **Learner app (Flutter web preview).**
  - Home, Learn, Practice, Progress and Rewards all render correctly with an empty account: locks, prerequisites, one progress method, the Performance section, and Rewards with 0 of 12 achievements.
  - A full COC1 M2 practice run was completed:
    - resume after Save and Exit;
    - visible rotation markers;
    - orientation enforcement;
    - operations;
    - cable routing;
    - POST readings;
    - interpretation;
    - evidence review with 43 synchronized events.
  - Server verification of that run: `verified: true`, run 1, 3,568 s, 3 incorrect attempts.
- **Practice timer.** The COC practice timer expired during the run. The app preserved the evidence and offered "Start a new timed practice session".
- **After the fix wave** (fresh database plus demo class, local production dashboard build):
  - **Practice API CORS.** A preflight from the app preview origin returns `Access-Control-Allow-Origin: http://127.0.0.1:3009` and allows `x-bytequest-app-version`. Unknown origins get no allow header.
  - **Evaluation Center.** The queue shows the demo class in every stage: Evaluate 9, Finalize 5, Release 3, Released 8. Items include the automatically evaluated COC1 M2 assessment (10/11), homework and quiz essays.
  - **Assign published content.** It starts with no activity selected. Choosing any simulation assessment switches the type to Assessment, and the form explains that it is "Published for assessment only: learners' attempts go to Evaluate, Finalize and Release".
  - **Analytics.**
    - The population line reads "12 learners, 11 active in the period". Assessment results show 95.5%, with 5 pending release. Quiz scores show 71.1%, with 6 awaiting evaluation.
    - Pending items are counted separately and never averaged in.
    - Live updates are on, every filter works, and every tab is present.
  - **Demo learner statuses.**
    - On track: 7.
    - Struggling: Fran (quiz average), Gale (repeated incomplete runs) and Hal (not yet competent).
    - Falling behind: Kai and Lou.
    - The leaderboard shows "Alex D. 935 · Bea D. 445 · …".

### 6.3 Reviews
- **Per-slice reviews.** Each of the seven slices got a specification and quality review. Fix rounds resolved every Critical and Important finding, and each fix got a scoped re-review. The ledger (`.superpowers/sdd/2026-11-19-redefense-revision/progress.md`) lists every finding and fix round.
- **Notable findings fixed during review:**
  - learners could read quiz totals and correctness before release (A3);
  - unreleased homework grades leaked through submit replays (A4);
  - award-trigger faults could abort the learner's own write, and a legacy unique index could fail on production duplicates (A6);
  - assessment controls were hidden for 19 missions, and assessment text revealed answers (A1);
  - mistakes corrected after a failed POST cost nothing (A1);
  - assessment sequence steps could be retried for free (A1);
  - discard markers could erase assessment mistakes (A1);
  - instructors could not see the rubrics of centrally published simulation assessments (integration).
- **Final whole-branch review.** Six parallel layer reviews. _Results and the fix wave are recorded in Section 6.4._

### 6.4 Final review and fix wave

The final whole-branch review ran as six parallel layer reviews against base `6548cb0`, which is the code before the revision. The findings were:

| Layer | Critical | Important | Minor |
|---|---|---|---|
| SQL part A: foundation, simulation, progression, quizzes | 1 | 4 | 4 |
| SQL part B: evaluation, roster, gamification, analytics, plus the security inventory | 0 | 3 | 10 |
| Dashboard server, API routes and scripts | 0 | 3 | 7 |
| Dashboard UI | 0 | 1 | 13 |
| Flutter simulation | 1 | 5 | 6 |
| Flutter, rest of the app | 0 | 3 | 14 |

Live QA added the coordinator's own findings Q1–Q6. Three fixers then worked in parallel, each owning one layer. Each fix set got a scoped re-review before it was merged.

**Fixed (highlights):**

*Assembly bench on phones*
- **Critical.** On a phone, swiping the parts tray picked a part up instead of scrolling, so the last cables could not be reached and COC1 M2 could not be finished. The tray now scrolls on horizontal swipes, drags start on a deliberate drag toward the bench, and tap-to-select still works. This is covered by touch-gesture tests at 360×640.
- In assessment, the orientation readout no longer shows an angle, which had revealed the answer.
- TalkBack can now select parts.
- The DIMM drop targets no longer overlap.

*Evidence and scoring*
- Evidence is sent strictly in action order. Before, one failed write could reorder the replay and fail a correct learner.
- In 19 simulation assessments, failed final tests and changed decisions used to cost nothing, and decision steps never checked the decision. Now:
  - a failed final check charges the step that owns it;
  - changing a decision during an assessment counts as a correction;
  - decision criteria require a correct choice;
  - safety-critical steps allow 0 incorrect attempts in all 20 missions.

  A brute-force COC4 M2 run is now not competent. One mistake that the learner corrects stays within the threshold.

*Privacy and old app versions*
- A pre-existing leak let learners call the provisional evaluation function and read unreleased results. The grant has been revoked.
- The installed 1.1.0 app has no version gate. The server now refuses simulation-assessment and essay-quiz starts from apps that do not report version ≥ 1.2.0 (`APP_UPDATE_REQUIRED`), before any attempt is consumed. Settings shows the real version.
- Evidence recorded against a different contract version is flagged for instructor review instead of being scored.

*Dashboard and app fixes*
- The practice verification API now answers browser CORS preflight requests, which fixes verification in the web preview.
- "Assign published content" now assigns simulation assessments as Assessments, so they enter the Evaluation Center. It uses the matching approved rubric version.
- Progress shows "Awaiting instructor evaluation" until release, then the released points.
- Quiz auto-submit recovers after network loss or a deadline extension.
- The Evaluation Center quiz queue skips archived classes.

*Rollout*
- The hosted rollout now runs in two batches:
  1. Batch A, the enum addition, committed first.
  2. Batch B, everything else, in one transaction inside a maintenance window, with a documented recovery procedure.
- This is proven to give a schema identical to the per-file chain.
- There is now rehearsal tooling for an isolated restored copy, including QA fixtures that do not need the Auth API.

**Skipped as "can wait"** (listed in the fix reports): cosmetic and low-risk minors.

---

## 7. Known limitations and minor items

- The COC1 M2 bench in Practice shows two progress views. The header follows the contract steps; the guidance bar follows the required placements. Non-required steps deliberately surface as POST faults, so the learner can continue before finishing them.
- In COC1 M2 assessment, fixing a wrong DIMM pair before POST costs criterion C5 two incorrect attempts, against one after POST. Both stay within the threshold.
- The `/tesda-sources` definition list overflows at a 390 px phone width (admin page; pre-existing).
- The leaderboard shows "First name + last initial" by design.
- **Installed 1.1.0 app.** It has no version gate. After the hosted rollout, learners must install 1.2.0. The server refuses simulation-assessment and essay-quiz starts from older apps, so no attempt is wasted. Other screens in the old app (topics, pending results, time limits) cannot use the new features.
- **Archived classes.** Their unreleased quiz items no longer appear in the Evaluation Center action stages, and the product has no unarchive path. Release results before you archive a class, or before running the demo seed's `--remove`.
- **COC2 M2 PPE.** The safety criterion checks only the final state, so toggling PPE off and on again is not counted as an incorrect attempt.
- **Tap counting.** In assessment, the parts' starting orientation is fixed. A learner who memorised the number of Rotate taps could seat the CPU without reading the marker. Randomising the starting orientation per attempt would close this.
- **Server-side assignment check.** `assign_activity` does not reject a Practice assignment of an assessment-only activity. The dashboard form prevents it.
- **Hosted rollout limits not yet verified:**
  - the backup step is still manual;
  - the restored-production rehearsal has not run, because there is no backup on this machine;
  - Batch B is about 0.83 MB, and its fit within the Management API size and time limits is unverified (the plan says stop rather than split);
  - hosted Supabase CORS for the custom version header matters only for web builds; the APK has no CORS.
- **"Can wait" minors** skipped in the fix wave are listed in the three fix reports under `.superpowers/sdd/2026-11-19-redefense-revision/`.

---

## 8. What still needs the owner

1. **Hosted rollout approval.** Nothing has been applied to hosted Supabase or Vercel. Follow `docs/REDEFENSE_HOSTED_ROLLOUT_PLAN.md`:
   1. backup;
   2. isolated restore rehearsal;
   3. the two-batch migration apply in a maintenance window: Batch A is the enum addition, Batch B is one transaction;
   4. read-back;
   5. Vercel deploy;
   6. the 1.2.0 APK with production defines;
   7. publish the simulation assessments;
   8. seed the demo class;
   9. smoke tests.

   This needs:
   - an explicit "approve rollout";
   - Vercel access on this machine or a teammate who can deploy;
   - approval to push `vince-branch`.
2. **Physical device pass.** Install the 1.2.0 APK on a phone and run the defense script (Section 9) once, including TalkBack and large text.
3. **Defense mode.** Decide whether the defense runs on the local stack (recommended if the hosted rollout is not approved in time) or on the hosted stack.

---

## 9. Re-defense demo checklist

**Before the defense:**
- Start the local stack (`supabase start`).
- Start the dashboard (`pnpm build && pnpm start -p 3001` in `ByteQuest-Web-Dashboard`).
- Start the learner app: the APK, or `flutter run -d web-server --web-port 3009 --dart-define-from-file=../.tmp/local-web-defines.json`.
- Run `node scripts/seed-demo-class.mjs` (idempotent) and then `--summary-only`.
- Sign in as the QA instructor and the QA learner.

**Demo script:**
1. **Assembly (panel's top item).** In the app, open Practice → COC 1 → Mission 2:
   - inspect the parts and wear the wrist strap;
   - rotate the CPU until its triangle matches the socket, then seat it and close the lever;
   - apply thermal compound and mount the cooler; connect CPU_FAN, not SYS_FAN;
   - open the latches and seat the RAM in DIMM_A2/B2;
   - in the case: PSU fan toward the intake vent, screws, I/O shield, motherboard, drive;
   - connect the 5 cables;
   - run the POST and read the measured output; record the interpretation;
   - review the evidence and confirm.
   Then show the incorrect-attempt counter and the run time.
2. **Assessment mode.** The same mission, assigned as a simulation assessment: no hints, neutral feedback, criteria scored on the server.
3. **Evaluation Center (Objective 4).** Walk the Evaluate → Finalize → Release queues with the demo class. Score an essay against its rubric, finalize, then release. In the app, the learner's Progress shows the released result.
4. **Quizzes.** Create a quiz: COC → Module → Topic → LO, focus, difficulty, time limit and deadline. Generate AI drafts, review and approve them, add a scenario essay, then publish and assign. Show the results summary.
5. **Homework.** COC and mission link, criteria, maximum score, missing work, late tracking.
6. **Analytics (Objective 6).** Overall, class, learner profile (with Engagement), quiz, mission (practice runs, most-missed steps), criteria; apply filters. Show a realtime update after a release.
7. **Learner management.** Import the roster template (preview → confirm → summary); search learners; show a staff-managed student ID.
8. **Learn / Practice / Progress (Objective 2).**
   - Module locks and prerequisites.
   - One progress method.
   - Rewards: points, level, achievements, opt-in leaderboard.
9. **Publication.** Take a curriculum topic or quiz question from draft through approved to published. Show it on Learn.

---

## 10. Rulings made on the owner's behalf

These are the decisions taken during implementation where the spec left a choice. Each one shows what it costs if it is wrong, so it can be reversed.

**Scoring:**
1. A failed check in a completed power-on or test run adds one incorrect attempt to the step that check belongs to. A run adds at most one incorrect attempt per step, so a single corrected mistake never exceeds the threshold by itself. *Cost if wrong:* stricter scoring, which the instructor can override with a reason.
2. In simulation assessments, two things count:
   - a failed final verification check charges the step that owns it;
   - changing a recorded decision counts as a correction.

   One wrong repair, a failed retest and then the fix stay within ≤2. Brute force exceeds it. *Cost if wrong:* troubleshooting scoring is stricter than intended; the instructor can override with a reason.
3. The server refuses simulation-assessment starts and essay-quiz starts from apps that don't report a version of at least `min_supported_app_version` (`APP_UPDATE_REQUIRED`). *Cost if wrong:* a 1.2.0 build with a broken header would be refused. Tests cover this.

**Access:**

4. Learners may read the contract step titles through a generated titles-only column. Answer keys stay unreadable. *Cost if wrong:* step titles become readable through the REST API.
5. Active instructors may read approved rubric versions of published activities, so they can assign the centrally published assessments. *Cost if wrong:* instructors see rubric metadata for packages they did not author.

**Implementation:**

6. Award-trigger faults were regraded to Important: they must never abort a learner's write, and the production unique index must not fail. *Cost:* one extra fix round.
7. A foundation `learner_module_completions` table records durable module-completion events for gamification and analytics.
8. Quiz items enter the Evaluation Center through A3's queue and action functions, so A4 did not depend on A3's schema.

**Process (no product effect):**

9. Slices ran in parallel with exclusive file ownership.
10. Each slice got one combined review, plus the final whole-branch review.
11. Each slice used its own database copy.
12. Feature strings live in per-feature content files.
13. A7 started early.
14. The final review was split into six layer reviewers, and the fix wave into three layer fixers.
15. The review workspace is kept as evidence.
