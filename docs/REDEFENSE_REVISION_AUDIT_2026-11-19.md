# ByteQuest Re-Defense Revision Audit and Plan

**Date:** 2026-11-19
**Branch / base commit:** `vince-branch` at `6548cb0` (clean worktree)
**Method:** read-only audit of the Flutter app, Next.js dashboard, 59 Supabase migrations, 15 SQL rollback suites, scripts and project documentation, plus spot verification of the highest-impact findings. No source, database, hosted service or deployment was changed while producing this document.

This document maps every re-defense panel recommendation to the existing implementation, the identified problem, the required modification, the affected components and the test evidence still required. Items that depend on information only the owner or the panel can supply are marked **Blocked – decision needed** and are listed in Section 6.

---

## 1. Current architecture

| Layer | Implementation |
|---|---|
| Learner app | Flutter/Dart (`ByteQuest-Mobile-App`, version 1.1.0+2), `provider`, `supabase_flutter`. Bottom navigation: Home, Learn, Progress, Rewards. |
| Simulation engine | Typed 2D runtime under `lib/screens/simulation/` (scene, hotspots, equipment workspace, reducer, evidence gateway, persistence). 20 missions, 115 phases, 13 interaction families. Mission definitions in `lib/data/mission_definitions/`. |
| Practice evidence | Actions written to `practice_mission_actions`; completion is verified by the server function `practice_verify_mission` (called through the dashboard API `/api/learner/practice`), which replays every action against a versioned `practice_mission_contracts` definition. |
| Formal assessment | Instructor-assigned activities (`assignments`, `attempts`, `attempt_actions`) evaluated in PostgreSQL against 98 rubric criteria, then instructor finalization and release (`finalize_attempt`, `release_attempt`). |
| Staff dashboard | Next.js 15 App Router, React 19, Tailwind/Radix UI, recharts, Supabase SSR. Separate Instructor and Admin workspaces enforced by middleware, page guards, RPC role checks and RLS. |
| Database | Supabase PostgreSQL with RLS on every public table; writes go through audited role-checked RPCs; private Storage buckets; append-only evidence, results and audit tables. |
| AI | OpenRouter, server-only key, draft-only quiz generation that always requires instructor review. |
| Hosting | Production dashboard on Vercel (`bytequest-alpha.vercel.app`) and the hosted Supabase project; production rollout recorded on 2026-11-13. |
| Not used | Unity and Firebase are not part of the implementation (the PRD notes that the manuscript's Chapter 2 still mentions them). |

## 2. Existing functionality that must be preserved (not redone)

- All 20 missions route through the typed 2D simulation; evidence is idempotent and resumable; COC-level practice locking is enforced by the database.
- Instructor quiz workspace: manual and AI-drafted questions (multiple choice, true/false, identification, scenario-based multiple choice), per-question approval, publish-and-assign, immutable published versions, preview, archive, version history.
- Server-enforced **one attempt per learner per quiz** across classes, devices and versions (`private.quiz_attempt_claims`), per-class deadlines enforced by the database clock, audited reopening.
- Homework: drafts, instruction files, publication, one immutable submission per learner, lateness snapshot, feedback and score, notifications.
- Technical assessments: automated PostgreSQL evaluation, criterion-level instructor review with mandatory reasons, append-only score revisions, finalization and release.
- Class management, learner enrollment search (name/email), resources with private Storage, notifications, support concerns, TESDA source approval, admin account governance, CSV report export.
- Instructor analytics over assessment attempts (filters: class, COC, mission, period) with criterion-level tables and charts; admin system analytics.

## 3. Findings

### 3.1 Critical issues

1. **Assessment answer rules readable by learners (security).** `supabase/migrations/20260810111000_grant_activity_versions_select.sql:7` grants `SELECT` on the whole `activity_versions` table to `authenticated`, overriding the earlier column list that deliberately excluded `evaluator_config` (`20260807102000_*.sql:79-92`). Any learner who can see an assigned activity version through RLS can request its evaluator configuration through the REST API. This contradicts the rule that assessment mode never exposes correct targets.
2. **Three different mission catalogs for the same mission IDs.** The database catalog (`missions`, used by the dashboard and analytics), the mobile catalog and practice contracts (`missions_data.dart`, `practice_mission_contracts`), and the published assessment packages (`scripts/mission-assessment-packages*.mjs`) use different titles, and for several missions different content. Example `coc2_m3`: catalog "Test Cable Connectivity", practice "Construct and Verify a Network Topology", assessment "Diagnose Cable Connectivity with a LAN Tester". Nine practice titles differ from the catalog. This is the root cause of the panel's COC/Learn/Practice/Progress alignment comment.
3. **The COC1 M2 assembly does not look or feel like assembly.** Parts are a column of labelled tiles and destinations are a second column of text boxes ("CPU socket", "RAM slot") on a grid background. There is no case or motherboard visual, the CPU socket is not on the board, nothing rotates visually (orientation is a text choice), there is no snapping animation into a physical position, no latches, levers, screws or standoffs, the drag ghost is a text label, and the unused `empty_system_unit_case.png` and `hdd.png` assets are never shown (`equipment_workspace.dart:464-505`, `simulation_scene.dart:854-901`, `mission_simulation_definitions.dart:299-331`).
4. **Practice simulation results are invisible to instructors.** Dashboard analytics read only formal assessment attempts. Practice completions, attempts, incorrect placements and time spent are not recorded as metrics and do not appear in any instructor view. There is no per-mission attempt counter or timer.
5. **Analytics cover only one assessment type.** `get_instructor_analytics` aggregates technical assessment attempts only; quizzes, homework and practice simulations are absent; the learner detail page shows only technical attempts; quiz results have no averages, distribution or per-question analysis even though per-question results are stored.
6. **No curriculum hierarchy below COC.** There are no `topics` or `learning_outcomes` tables. Quizzes store a free-text `topic`; "learning outcome" in the AI panel is the mission objective. `coc_modules` has exactly one module per COC whose `module_name` equals the COC title. The official TR defines Learning Outcomes and Performance Criteria per unit but no Module or Topic level (see Section 5.1).
7. **Gamification is not visible.** The Rewards tab is an intentional placeholder (`leaderboard_screen.dart:6-8`), and release XP/points are configured as zero. This is relevant to Objective 2 as summarised in the project documents (Gamification).
8. **Inconsistent learner progress.** Learn/Practice shows "practice missions verified" with a hard-coded denominator of 5; the Learning path and Progress screens show "results released" with the database mission count; Home shows neither. There is no single documented completion methodology.

### 3.2 Incomplete or missing features

- **Quizzes:** no module, topic, learning outcome, quiz focus, difficulty or time limit stored on the quiz (difficulty and focus are only logged with an AI request); no essay or long-answer type; no manual or rubric grading; no automatic submission of unfinished attempts at the deadline (unfinished work is left unsubmitted); no closed status (derived in the browser); library filters only by text and status.
- **Homework:** no COC or mission association, learning objectives, assessment criteria or maximum score (fixed 0–100); no cross-assignment missing-work view; no filters by class, student, COC, mission or status; the "graded by" line shows a raw user ID.
- **Objective 4 workflow visibility:** evaluation, finalization and release exist for technical assessments, but `/attempts` is one flat list without stage queues; the `under_review` status is counted but never set; practice-type attempts stay `submitted` forever; essays and homework are not part of any evaluation queue.
- **Learner management:** no search, pagination, sorting or filters on `/learners`, `/users` or `/progress`; no bulk import (`/users/import` redirects); the `profiles.learner_id` column exists but is optional, not unique, learner-editable and unused by the dashboard.
- **Sequential unlocking:** only whole COCs lock (after five verified missions and the COC practice quiz); missions inside a COC are not sequenced; the lock icon component never renders; the prerequisite text is only in the screen-reader label on the Practice tab. An instructor COC bypass is likely still refused by the practice lock (`practice_coc_unlocked` does not consult `coc_bypasses`; observed from code, not executed).
- **Publication:** the only approval UI is the admin TESDA source workflow; rubric, module and activity publication are script-only; there is no public website (only `/login`, `/signup` and `/auth/recover` are public).

### 3.3 Nonfunctional or misleading UI

- Class summary cards link to `#assignments`, `#resources`, `#bypasses` anchors that are not rendered unless the tab is open (`app/classes/[id]/page.tsx:127-132`).
- "Upcoming tasks" reads technical assignment due dates that the assign form never sets, and ignores quiz and homework deadlines (`InstructorOverviewPanels.tsx:56-59`).
- The quiz deadline dialog receives the class and quiz titles in swapped order (`app/classes/[id]/page.tsx:188`).
- The instructor dashboard review queue only inspects the eight newest attempts while its counter is exact.
- `/users` "Inactive profiles" and the review links on `/learners` and `/instructors` open the same unfiltered list.
- The Rewards tab is a static placeholder.

---

## 4. Revision checklist

Status values: **Done** (existing, verified by audit) · **Partial** · **Not started** · **Blocked – decision needed**.

### Phase 2 – Realistic 2D hardware assembly (critical)

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R2.1 | Individually selectable/draggable components, rotation, visual response, realistic visuals | `EquipmentWorkspace` drag/tap placement with part images on tiles | Tiles and text boxes, no rotation, text drag ghost | Assembly bench scene: open case with motherboard drawn in place, parts tray with real images, image drag ghost, visible rotation control and gesture, lift/highlight on selection | `lib/screens/simulation/components/` (new assembly bench widgets), `equipment_workspace.dart`, `assets/COC1/Mission 2/` | Not started | Widget tests for drag, tap-to-place, rotate, reduced motion, 48 dp targets |
| R2.2 | Multiple sequential assembly steps | Five phases; one placement phase for six parts; reorder list afterwards | Order is a separate list, not taken from what the learner does | Step-based assembly derived from actual actions: prepare/ESD, PSU, motherboard on standoffs, CPU with lever, cooler, RAM with latches, storage, power and data cables, verification | `coc1_definitions.dart`, `equipment_content.dart`, new practice contract version for `coc1_m2` | Not started | Contract export parity test, all-phase completion test |
| R2.3 | Logical placement areas, step validation, prevention, correction, progress | Category/orientation/prerequisite checks client- and server-side | Labels match one-to-one; every part asks for orientation | Physical slots on the board; prerequisites follow real assembly order; orientation only where physically meaningful (CPU, RAM, PSU fan); remove/reseat to correct | Same as R2.2; server verifier reused (`practice_verify_mission` already supports prerequisites, orientation, operations with `requires`/`effects`) | Not started | Server replay tests (valid, invalid, out of order, correction) |
| R2.4 | Smooth drag, snap, highlight, indicators, animations, hints, feedback | Border colour while dragging, 200 ms transitions, 5 s banners | No positional snap, no installation animation | Magnetic snap into the exact slot rectangle, seat/latch animation, slot glow for compatible targets, step instructions, concise technical feedback strings in `mission_content_data.dart` | Assembly bench widgets | Not started | Golden/widget tests incl. reduced-motion path |
| R2.5 | Record steps, incorrect attempts, attempts, time, completion, criteria, final performance; connect to progress and analytics | Every action stored with timestamp; completion row on success | No attempt count, no time, no per-step result, nothing reaches instructor analytics | Server-computed run metrics at verification (attempt number, incorrect actions, duration, per-step results) stored in a new run table; exposed to instructor analytics and learner progress | New migration (run table + verifier wrapper), `/api/learner/practice`, analytics RPC | Not started | SQL rollback suite, API test, analytics accuracy test |

### Phase 3 – Instructor quiz creation and management (critical)

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R3.1 | Organise quizzes COC → Module → Topic → Learning Outcome; focus, instructions, type, difficulty, time limit, deadline, attempts | Title, free-text topic, optional COC, instructions, description; deadline at publish; attempts fixed to one | No module/topic/LO links; focus/difficulty/time limit not stored | Curriculum foreign keys on quizzes; persisted focus, difficulty, time limit; cascading selectors | New curriculum tables (Section 5.1), `CreateQuizForm.tsx`, quiz RPCs | Blocked – decision needed (Q1) | RPC validation tests, form tests |
| R3.2 | Audit topics and learning outcomes; associate correctly; no invented TESDA LOs | None exist | — | Seed official TR learning outcomes and performance criteria verbatim; admin curriculum management | New migration + admin pages | Blocked – decision needed (Q1) | Seed verification against `TR_current.txt` line references |
| R3.3 | AI generation from COC/module/topic/LO/focus/difficulty/type; regenerate one question; edit, delete, add, preview, draft, publish | AI panel with COC activity or class PDF source, focus, difficulty, types, count; "Generate alternative"; review/approve/publish | Context is mission-based, not LO-based; alternative only for AI items | Ground prompts in the selected module/topic/LO; allow replacing a question with a regenerated one while keeping history | `lib/ai/quiz-grounding.ts`, `AiQuizPanel.tsx`, generation route | Partial | Provider contract tests with mocked responses |
| R3.4 | Scenario-based essay with long answers, rubric scoring, instructor evaluation | Scenario-based multiple choice only | No essay type or manual grading | New `scenario_essay` item type with scenario, prompt, rubric criteria and points; learner long-text answer; instructor rubric scoring and feedback; result becomes final only after evaluation | Quiz migrations, quiz editor, mobile `quiz_taking_screen.dart`, result screens | Not started | SQL lifecycle test, editor and mobile widget tests |
| R3.5 | One attempt; deadline; automatic submission; draft/published/closed/archived; timestamps; scores; essay evaluation; status indicators | One attempt and deadlines enforced server-side; archive; timestamps | No auto-submission; closed derived in browser | Server-side automatic submission of saved answers at deadline or time-limit expiry; explicit availability status; essay pending state | Quiz RPCs, mobile quiz screens | Partial | Clock-controlled SQL tests, duplicate-submission tests |
| R3.6 | Dashboard: filters by COC/module/topic/status; edit drafts; review published; submissions; essay evaluation; scores; class performance; deadlines; archive; versioning safety | Library with text/status filter; results list; deadlines; archive; immutable versions | No curriculum filters; no class average, distribution or per-question analysis | Curriculum filters, results summary (average, highest, lowest, completion, distribution, per-question difficulty), evaluation queue link | `QuizLibrary.tsx`, `QuizAuthoringWorkspace.tsx`, new results components | Partial | Analytics accuracy tests with fixtures |

### Phase 4 – Assignments (homework)

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R4.1 | Categorise by COC and mission; objectives, criteria, resources, requirements, max score, status | Title, instructions, deadline, instruction files, draft/published | No COC/mission, objectives, criteria or max score | Optional COC and mission links, learning objectives, criteria list with points, maximum score, submission requirements | `homework_assignments` migration, `manage_homework`, `HomeworkManager.tsx`, `HomeworkWorkspace.tsx` | Not started | SQL tests incl. existing rows remain valid |
| R4.2 | Students filter by COC/mission, view, submit, upload, status, feedback, score | Full submission flow on mobile | No COC/mission filters | Filters and labels on mobile activity lists | `assigned_class_activities.dart`, homework screens | Partial | Widget tests |
| R4.3 | Instructor filters by class/student/COC/mission/status; missing work; files; grading; late tracking | Per-assignment roster with submitted/unsubmitted, lateness, grading | No cross-assignment view or filters; grader shown as UUID | Submissions workspace across assignments with filters and missing-work view; show grader name | New dashboard page and API | Partial | API and browser tests |

### Phase 5 – Performance analytics (critical)

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R5.A | Overall performance with period and population | Assessment-only summary | Quizzes, homework, practice missing | Unified overview with explicit population and period labels | New analytics RPC(s), `InstructorAnalyticsDashboard.tsx` | Partial | Fixture-based aggregation tests |
| R5.B | Class performance and comparison | One "Class Performance" report row per class | No class drill-down across activity types | Class comparison table and class detail | Analytics RPC, new components | Partial | Same |
| R5.C | Individual learner progress | Technical attempt history only | No quiz, homework, practice | Learner profile combining all activity types and COC/module progress | `progress/learners/[userId]` | Partial | Same |
| R5.D | Quiz score analytics | Raw result list | No averages, distribution, completion | Quiz analytics (participants, average, highest, lowest, completion, distribution, per-question) | Quiz analytics RPC/components | Not started | Same |
| R5.E | Mission performance incl. real attempt counts | Assessment attempts and retries | Practice runs not recorded | Mission analytics from assessment attempts plus practice runs (R2.5) | Same | Partial | Same |
| R5.F | Criterion-based analysis | Assessment rubric criteria table and chart | Practice steps and essay rubric criteria not included | Criterion analysis across assessment criteria, simulation steps and essay rubric criteria, with strongest/weakest | Same | Partial | Same |
| R5.G | Charts, tables, filters (class, COC, module, topic, mission, quiz, date, learner) | recharts; class/COC/mission/period filters | No module/topic/quiz/learner filters | Extend filters end to end (server-validated) | `AnalyticsFilters.tsx`, RPC parameters | Partial | Filter tests |
| R5.H | Accuracy: no double counting, unpublished quizzes excluded, pending evaluation shown | Server aggregation, no fabricated values | New sources need the same rules | Documented metric definitions in code and docs; pending-evaluation states shown separately | Analytics RPC + docs | Partial | Accuracy tests against SQL fixtures |

### Phase 6 – Learner management

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R6.A | Excel bulk import with template, validation, duplicates, preview, summary | None | — | Template download, `.xlsx`/`.xls` parsing on the server, validation, duplicate detection, preview, confirm, summary; behaviour depends on Q3 | New import page/API; reliable student ID column | Blocked – decision needed (Q3) | Parser tests incl. malformed files, duplicate rows, large files |
| R6.B | Search by name, student ID, email, class; filter, sort, paginate | Enrollment combobox only | Lists have no search | Server-side search/filter/sort/pagination on learner lists | `/learners`, `/users`, `/progress` | Not started | API and browser tests |

### Phase 7 – Align COC, Learn, Practice and Progress (critical)

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R7.A | One COC/module/topic/LO structure everywhere | Three mission catalogs (Section 3.1-2) | Inconsistent names and content | One canonical catalog in the database (titles, modules, learning outcomes) read by mobile and web; assessment alignment per Q4 | Catalog migration, mobile catalog, dashboard queries | Blocked – decision needed (Q1, Q4) | Parity test: database catalog equals mobile definitions |
| R7.B | Learn page shows COC, modules, topics, outcomes; completion from real activity | Learn tab = tasks/classes/practice/files | No curriculum content view | Learn page: COC → modules → topics/outcomes with linked resources, quizzes and missions and real completion | Mobile Learn screens | Blocked – decision needed (Q1) | Widget tests |
| R7.C | Practice page shows missions of the correct COC/module | Practice sub-tab grouped by COC | Not grouped by module; names differ from web | Practice grouped by COC and module with canonical titles and lock states | Mobile Practice screen | Partial | Widget tests |
| R7.D | Progress page reflects real activity with one methodology | Two unrelated metrics | Inconsistent denominators | Single progress definition (documented) used by Learn, Practice, Progress, Home and dashboard | Shared progress RPC, mobile screens | Not started | Unit tests for the methodology |

### Phase 8 – Sequential unlocking (mobile)

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R8 | Module 2 locked until Module 1 completed, etc.; lock icon, prerequisite, progress; backend enforcement; no API bypass; preserve completions | COC-level lock enforced by RLS and verifier | No module/mission-level sequence; lock UI weak; bypass likely ineffective | Server-side prerequisite function used by the evidence insert policy and verifier; lock/complete UI with prerequisite text and progress; bypass honoured; existing completions preserved | Practice progression migration, mobile Learn/Practice | Blocked – decision needed (Q1) | SQL tests for direct-API bypass attempts; widget tests |

### Phase 9 – Objectives 2, 4 and 6

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R9.2 | Objective 2 mapped and genuinely satisfied | Project documents summarise Objective 2 as Gamification; rewards placeholder, XP zero | Gamification not visible | Depends on the verbatim objective and panel comment | — | Blocked – decision needed (Q5) | — |
| R9.4 | Objective 4: classify items as Evaluate, Finalize, Release | RPCs exist for technical assessments; flat list UI | No stage queues; essays and homework outside the flow | Evaluation Center with Evaluate / Finalize / Release / Released queues covering technical assessments, scenario essays and homework; no stage skipping (server-enforced) | Dashboard page, RPCs for essay/homework evaluation | Partial (verbatim wording still requested, Q5) | Transition tests incl. skip attempts |
| R9.6 | Objective 6 mapped and demonstrable | Project documents list only five objectives | Objective 6 unknown | Depends on the verbatim objective | — | Blocked – decision needed (Q5) | — |

### Phase 10 – Approval and publication on the website

| ID | Panel requirement | Existing implementation | Problem | Required modification | Affected components | Status | Tests required |
|---|---|---|---|---|---|---|---|
| R10 | Draft → Submitted → Evaluated → Finalized → Approved → Published; approved items visible on the website; who/when recorded; unpublish | Quiz items require approval before publication; TESDA source approval; no public site | Unclear which items and which website | Depends on Q2 | — | Blocked – decision needed (Q2) | Role and transition tests |

### Phase 11 – System-wide integrity

| ID | Requirement | Required modification | Status |
|---|---|---|---|
| R11.1 | Fix the `activity_versions.evaluator_config` exposure | Replace the table-wide grant with an explicit column grant; move any staff read of evaluator rules behind an authorised server path; verify mobile hydration still works | Not started |
| R11.2 | Fix nonfunctional or misleading UI (Section 3.3) | Tab links via `?tab=`, upcoming tasks from real deadlines, swapped labels, full review queue, grader name, filtered user lists | Not started |
| R11.3 | Mobile/web consistency | Canonical catalog and progress methodology (R7) | Blocked with R7 |
| R11.4 | Role checks on every new action | New RPCs follow the existing audited, role-checked pattern; no new SECURITY DEFINER function without explicit review | Applies to all work |

### Phase 12 – Testing

All 23 required test scenarios are covered by the test columns above. The rollback-only SQL suites need a local Supabase stack (Docker); the Flutter and dashboard suites run locally. Physical-device, TalkBack and hosted end-to-end checks are recorded separately and never inferred from automated tests.

---

## 5. Proposed design direction

### 5.1 Curriculum hierarchy without invented content

Official source (`docs/reference/tesda_sources/TR_current.txt`, Amended December 2013) defines, per core unit: the unit (COC), its Elements, the curriculum Learning Outcomes (TR §3.1, lines 3028–3124) and Performance Criteria. It defines no Module titles and no per-LO Topics.

| COC | Official learning outcomes (TR curriculum) |
|---|---|
| COC1 ELC724331 | LO1.1 Assemble computer hardware · LO1.2 Install operating system and drivers for peripherals/devices · LO1.3 Install the computer application software · LO1.4 Conduct testing and documentation |
| COC2 ELC724332 | LO2.1 Install network cables · LO2.2 Set network configuration · LO2.3 Set router/Wi-Fi/wireless access point/repeater configuration · LO2.4 Inspect and test the configured computer networks |
| COC3 ELC724333 | LO3.1 Set-up user access · LO3.2 Configure network services · LO3.3 Perform testing, documentation and pre-deployment practices |
| COC4 ELC724334 | LO4.1 Plan and prepare for maintenance and repair · LO4.2 Maintain computer systems and networks · LO4.3 Diagnose faults of computer systems · LO4.4 Rectify/correct defects in computer systems · LO4.5 Inspect and test the computer systems and networks |

Recommended mapping (pending Q1): **Module = official curriculum learning outcome** (16 modules), **Learning outcomes selectable for quizzes = the official performance criteria under that module**, **Topics = admin-managed lessons under each module** (initially empty or seeded only from an official source the owner supplies). Missions attach to modules using their existing performance-criteria mapping in `docs/MISSION_TESDA_ALIGNMENT_AUDIT.md`. Sequential unlocking then runs module by module and COC by COC.

### 5.2 Assembly bench (COC1 M2)

```
┌────────────────────────────────────────────────────────────────────┐
│ Step 4 of 9 · Seat the CPU            Time 06:12   Correct 3  Retry 1│
├──────────────┬─────────────────────────────────────────────────────┤
│ PARTS        │  OPEN CASE (side panel removed)                      │
│ [img] CPU  ⟳ │  ┌──────────────── MOTHERBOARD ───────────┐ ┌──────┐ │
│ [img] RAM ×2 │  │  ┌──────┐  lever    ▌▌ ▌▌  DIMM A2/B2   │ │ PSU  │ │
│ [img] Cooler │  │  │socket│  ◢        ▌▌ ▌▌  latches open │ │ bay  │ │
│ [img] SSD    │  │  └──────┘                               │ └──────┘ │
│ [img] PSU    │  │   ═══════ PCIe x16                      │ ┌──────┐ │
│ TOOLS        │  │  ▭24-pin ▭8-pin EPS ▭SATA ▭FAN          │ │drive │ │
│ screwdriver  │  └─────────────────────────────────────────┘ │ bay  │ │
│ wrist strap  │                                              └──────┘ │
└──────────────┴─────────────────────────────────────────────────────┘
```

Parts are dragged (or tapped then placed) onto physically positioned slots and snap into place; the CPU and RAM show their alignment marks and rotate visibly; levers, latches and screws are tapped with the selected tool; cables are drawn from PSU connectors to board headers. The assembly is expressed as a new versioned practice contract evaluated by the existing server verifier (placement prerequisites, orientation, operations with `requires`/`effects`, connections), so no client value is trusted. Earlier evidence and completions remain valid under their recorded contract version.

### 5.3 Evaluation Center (Objective 4)

One instructor page with four queues: **Evaluate** (submitted work needing instructor judgement: technical attempts pending review, scenario essays, homework), **Finalize** (evaluated, not finalized), **Release** (finalized, not visible to the learner), **Released**. Transitions remain server-enforced, so a stage cannot be skipped.

---

## 6. Decisions needed from the owner

- **Q1 – Meaning of "Module".** See Section 5.1. Recommended: module = official curriculum learning outcome, unless an official CBC/CBLM module and topic list is supplied.
- **Q2 – "Approved items … published on the website."** Which items, and which website (dashboard, learner app, or a new public page)?
- **Q3 – Excel import behaviour.** Enroll existing learners and pre-register new emails, or create accounts with temporary passwords (no email delivery is configured).
- **Q4 – Practice versus assessment alignment.** Make assigned technical assessments run the same 2D simulations (criteria derived from mission steps), or align names only and keep the current form-based assessment packages.
- **Q5 – Objectives 2, 4 and 6.** Verbatim wording from the final manuscript and the panel's exact comment for each. Project documents list five objectives; no Objective 6 exists in the repository.

## 7. Working defaults

- Work stays local on `vince-branch` with scoped commits; no push, hosted migration, Vercel deployment or APK distribution without explicit owner approval.
- Schema changes are additive and versioned; no destructive migration, no deletion of learner records or assessment history; published content stays immutable.
- No new SECURITY DEFINER function without explicit review; new writes use the existing audited, role-checked pattern.
- Official TESDA text is copied verbatim with line references; nothing is invented.
- Local testing needs Docker Desktop (local Supabase stack), a synthetic gitignored mobile `.env`, and dashboard dependencies (`pnpm install`).
