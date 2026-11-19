# ByteQuest Re-Defense Revision — Design

**Date:** 2026-11-19 · **Branch:** `vince-branch` (base `6548cb0`)
**Inputs:** the owner's re-defense revision brief (Phases 1–12), the audit `docs/REDEFENSE_REVISION_AUDIT_2026-11-19.md`, and the owner's decisions recorded in Section 4.

---

## 1. Intent

ByteQuest passed its first defense as a 2D simulation platform with automated evaluation. At the re-defense the panel asked for a platform that is complete, consistent and demonstrable end to end: a hardware assembly that feels like building a computer, a curriculum-organised quiz system with scenario essays, assignments organised by COC and mission, analytics that cover every learning activity, Excel learner import and search, one consistent COC structure across Learn, Practice, Progress, web and mobile, sequential module unlocking, a clear Evaluate → Finalize → Release workflow (Objective 4), and an approval-to-publication workflow for content.

Success means every panel item can be shown live with real data, every number on a dashboard can be traced to database records, and nothing that already works is lost.

## 2. Goals, non-goals and anti-goals

**Goals**
- Close every revision item in the audit checklist, prioritising: assembly simulation, quiz management, analytics, COC alignment, sequential unlocking, publication workflow.
- One curriculum source of truth (COC → Module → Topic → Learning Outcome) used by mobile, web, quizzes, assignments, missions and analytics.
- Practice and Assessment modes of the same 2D mission environment, with server-side evaluation and Evaluate → Finalize → Release.
- Honest, documented metrics.

**Non-goals**
- A public marketing website (owner decision: publication targets the learner app and dashboard).
- 3D simulation, a game engine, or any new client-side evaluation authority.
- Official TESDA certification claims; ByteQuest remains a supplementary platform.
- Email-dependent flows (SMTP is still deferred).

**Anti-goals (failure even if it "works")**
- Fabricated curriculum text, fabricated metrics, or fabricated grades (for example, inventing a score for unanswered work).
- A drag-and-drop that still reads as "cards into labelled boxes".
- Practice and assessment drifting apart again (two catalogs, two titles, two contents for one mission without an explicit reason).
- Losing or rewriting historical attempts, results, practice completions or audit history.
- Hidden or client-only enforcement of locks, attempts, deadlines or transitions.

## 3. Constraints

- Supabase/PostgreSQL stays authoritative for evaluation, locks, attempts, deadlines and transitions; RLS stays enabled on every table.
- No new `SECURITY DEFINER` function without explicit review. This design lists every proposed change to an existing definer function in Section 9; approving this design is that review. New server logic otherwise uses `SECURITY INVOKER` functions, service-only functions behind authenticated server routes, or RLS policies.
- Migrations are additive and versioned; published content versions stay immutable; destructive changes require separate owner approval.
- Official TESDA text is copied verbatim from `docs/reference/tesda_sources/TR_current.txt` with line references.
- All work is local on `vince-branch` with scoped commits. Push, hosted migration, Vercel deployment and APK distribution need explicit owner approval and follow the existing backup/rehearsal procedure.
- Mobile quality gates from `AGENTS.md` and `bytequest.md` still apply: 3–6 meaningful phases per mission, at least two interaction types, structured evidence for every meaningful action, technical feedback (never "Wrong"), assessment mode never exposes correct targets, pause/resume without duplicate evidence, 48 dp targets, Semantics labels, large text, reduced motion, feedback strings in `mission_content_data.dart`.

## 4. Owner decisions (2026-11-19)

1. **Module = official curriculum learning outcome.** 16 modules from the TR curriculum (COC1 LO1.1–1.4, COC2 LO2.1–2.4, COC3 LO3.1–3.3, COC4 LO4.1–4.5). Missions are grouped under modules; the official performance criteria are the selectable learning outcomes for quizzes; topics are admin-managed; unlocking runs module by module, then COC by COC.
2. **Publication workflow applies to:** curriculum content, quiz questions, and assessment results (no public website page).
3. **Excel import:** instructors upload a class roster; existing learner accounts are enrolled immediately; new emails become pending roster entries that auto-enroll when that learner signs up with the same email. Instructors never create accounts.
4. **Unify assessments on simulations, with separate modes:** Practice and Assessment share the same mission environment, components, objectives and simulation logic. Practice gives guidance, hints and repetition; Assessment evaluates independently without instructional assistance. Mission-specific technical requirements are preserved: where an assessment's practical task differs from the practice task (for example a LAN-tester diagnosis versus a topology build), they share mission context and competency mapping but remain distinct tasks. Evidence, completed steps, incorrect actions, attempts, time and criterion performance are recorded; results follow Evaluate → Finalize → Release; historical assessment records and practice progress are preserved.
5. **Defense environment: both.** Build and verify everything on the local stack first; then, with a separate owner approval, run the backed-up and rehearsed hosted migration, Vercel deployment and a new APK before the defense. The demo runs on production.
6. **Demo data: a clearly labelled demo class** (for example "DEMO – Re-defense") with synthetic learner accounts that perform real activities through the normal APIs, so every analytics number comes from genuine records; easy to remove later. Created locally first, on production only as part of the approved rollout.
7. **Assessment step scoring: thresholds.** A simulation assessment step is satisfied when it is completed with at most two incorrect attempts on that step; safety-critical steps (ESD/power isolation and CPU orientation in COC1 M2, and the equivalent safety steps in other missions) must be correct on the first attempt. The instructor can override any step, with a reason, during Evaluate.
8. **COC3 order: LO3.2 first.** Unlock order LO3.2 → LO3.1 → LO3.3; official codes and wording unchanged.
9. **Objectives (verbatim, supplied by the owner 2026-11-19):**
   - **Objective 2:** "Use points, levels, rewards, achievements and tracking progress in the learning process to motivate and engage the learner."
   - **Objective 4:** "Design & Develop an automated system for Skill Evaluation that will evaluate the learner's performance against the set competency criteria and the requirement for the completion of the competency tasks of TESDA CSS NC II."
   - **Objective 6:** "Create a performance analytics dashboard which allows learners and instructors to monitor learner progress, competency achievement, scores and assessment results in real time."
   The panel comments are the ones in the owner's revision brief. **Re-defense: Monday 2026-11-23.** The design was approved by the owner on 2026-11-19.

## 5. Approaches considered

| Decision | Options considered | Chosen and why |
|---|---|---|
| Simulation-based assessment evaluation | (a) Shared server replay of the mission contract, exposed as a new criterion evidence operator; (b) client computes step results and submits them; (c) keep the form-based assessment adapters | **(a).** It reuses the existing practice verifier semantics (no client trust), works for all 20 missions from their definitions, and keeps Evaluate → Finalize → Release. (b) violates server authority; (c) was rejected by the owner. |
| Assembly visuals | (a) Dedicated assembly-bench scene driven by the mission definition; (b) re-skin the existing two-column workspace over a case image; (c) adopt a game engine (Flame) | **(a).** Physical slot positions, visible rotation, levers/latches/screws and cable routing need their own scene; (b) cannot express physical positions convincingly; (c) adds a dependency and duplicates the engine. The existing runtime, reducer, evidence gateway and persistence remain the single engine. |
| Curriculum publication | (a) Topics with revisions, each revision moving through an explicit workflow with an event history; (b) one status column per topic | **(a).** Learners keep seeing the last published revision while a new one is drafted and evaluated; (b) would hide content during every edit. |
| Analytics | (a) New `SECURITY INVOKER` SQL RPCs plus class-scoped RLS read policies; (b) extend the existing definer analytics function; (c) aggregate in the browser | **(a).** Server-side aggregation keeps numbers consistent and testable without enlarging the definer surface; (c) is slow and inconsistent. |
| Excel parsing | (a) Server-side SheetJS 0.20.3 (official tarball; supports `.xlsx` and `.xls`); (b) `exceljs` (no `.xls`); (c) browser parsing | **(a).** Validation must run on the server anyway; the npm-registry `xlsx` 0.18.5 has known vulnerabilities, so the official 0.20.3 distribution is used. |
| Quiz auto-submission | (a) Server-side finalisation triggered lazily on every quiz read/write plus a scheduled job where available; (b) client timer | **(a).** Deadlines are already enforced by the database clock; a client timer cannot be trusted. |

## 6. Design by workstream

Workstreams are delivered in this order, each ending with tests and a scoped commit: WS0 → WS1 → WS2 → WS3 → WS4 → WS5 → WS6 → WS7 → WS8 → WS9 → WS10 → WS11.

### WS0 — Foundation and safety

- **Local test environment:** Docker Desktop with the repository's local Supabase stack (`supabase/config.toml`, ports 573xx), all migrations applied (verified on a fresh database 2026-11-19); a synthetic, gitignored mobile `.env` and dashboard `.env.local` pointing at the local stack; `pnpm install`, `flutter pub get`; the `pgtap` extension; and a local QA fixture script (synthetic admin, instructor, learners, class) so the six fixture-dependent SQL suites can run on a fresh database.
- **Security fix (R11.1):** replace the table-wide `SELECT` grant on `activity_versions` with an explicit column grant that excludes `evaluator_config`. Any staff view of evaluator rules reads them through an authorised server route. Mobile hydration must select explicit columns (verified by test).
- **Minimum app version (builder call):** a server-readable minimum supported app version; the new app checks it at startup and asks for an update, because older installed versions do not know about module locks or simulation-based assessments and would otherwise fail with generic save errors.
- **Misleading UI fixes (R11.2):** class summary cards link with `?tab=`; Upcoming Tasks uses real quiz, homework and assessment deadlines; quiz deadline dialog labels corrected; instructor review queue reads all pending items; homework grader shows a name; user lists filter by status.

### WS1 — Curriculum and canonical catalog

**Data model (new, additive):**
- `curriculum_modules` — one row per official curriculum LO: `coc_module_id`, `competency_id`, `code` (e.g. `LO1.1`), `title` (curriculum LO wording, verbatim), `element_title` (element wording where it differs), `sequence_order`, `source_reference` (TR line range), timestamps. Seeded as published system content; not editable except `sequence_order` (admin).
- `learning_outcomes` — official performance criteria under each module: `module_id`, `code` (e.g. `1.4`), `statement` (verbatim), `sequence_order`, `source_reference`. COC1 Element 2 "Prepare installer" (PC 2.1–2.3), which has no curriculum LO, is attached to module LO1.2 with an explicit source note.
- `curriculum_topics` (stable identity: `module_id`, `sequence_order`) and `curriculum_topic_revisions` (title, summary, sanitised Markdown body, linked `learning_outcomes`, optional attachments, workflow status and actor/time fields).
- `content_publication_events` — append-only history of every workflow transition (entity, from, to, actor, note, time).
- `mission_curriculum_links` — mission → primary module plus referenced performance criteria; `activity_curriculum_links` — assessment activity → module (used to place distinct legacy tasks under the right module without touching immutable versions).
- `learner_topic_progress` — learner, topic, `completed_at` (unique per learner/topic).

**Publication workflow** (`content_publication_status`): `draft → submitted → evaluated (passed | needs_revision) → finalized → approved → published`, plus `unpublished` and `archived`. One transition RPC enforces the order, role and audit:

| Action | Who | From |
|---|---|---|
| submit | author (instructor or admin) | draft |
| evaluate (passed / needs revision, notes required) | admin | submitted |
| finalize (content locked) | author or admin | evaluated-passed |
| approve | admin | finalized |
| publish / unpublish / republish | admin | approved / published / unpublished |

Learners and the learner app read only the latest **published** revision. Drafting a new revision never hides the published one.

**Canonical mission catalog:** the 20 missions learners actually run (effective titles from `missions_data.dart`, `_equipmentTitles`, practice contracts) become the canonical titles, scenarios and objectives in the database `missions` table, via a migration generated from the Flutter definitions, with the previous values retained in an audit/history record. A parity test fails if the database catalog and the Flutter catalog diverge again. The dashboard modules page, analytics, assignments and quizzes all read this catalog.

**Admin UI:** `/curriculum` — COC → module → learning outcomes (read-only official text), topics with revision workflow, mission and assessment links, publication history. Instructors can draft and submit topics; admins evaluate, approve and publish.

**Mission → module mapping (proposed; owner to confirm):**

| COC | Module (official LO) | Practice missions | Main PCs |
|---|---|---|---|
| COC1 | LO1.1 Assemble computer hardware | M1 Identify Computer Parts and Tools; M2 Install Internal Components | 1.1–1.4 |
| | LO1.2 Install operating system and drivers for peripherals/devices | M3 Install and Configure a Workstation OS; M4 Connect and Configure Peripheral Devices | 1.5, 2.1, 3.1–3.3 |
| | LO1.3 Install the computer application software | — (no practice mission yet) | 4.1–4.3 |
| | LO1.4 Conduct testing and documentation | M5 Install Drivers and Test the System | 5.1–5.4 |
| COC2 | LO2.1 Install network cables | M1 Identify Network Devices and Tools; M2 Create Network Cables; M3 Construct and Verify a Network Topology | 1.1–1.9 |
| | LO2.2 Set network configuration | M4 Configure Network Devices | 2.1–2.4 |
| | LO2.3 Set router/Wi-Fi/wireless access point/repeater configuration | — (no practice mission yet) | 3.1–3.5 |
| | LO2.4 Inspect and test the configured computer networks | M5 Troubleshoot Network Connectivity | 2.2, 4.1–4.3 |
| COC3 | LO3.1 Set-up user access | M3 Manage Users, Groups, and Permissions | 1.1–1.3 |
| | LO3.2 Configure network services | M1 Prepare Server Setup Requirements; M2 Install and Configure Server OS; M4 Configure and Test Server Services | 2.1–2.5 |
| | LO3.3 Perform testing, documentation and pre-deployment practices | M5 Test Client Access and Document Setup | 3.1–3.3 |
| COC4 | LO4.1 Plan and prepare for maintenance and repair | M1 Identify System and Network Problems | 1.1–1.5 |
| | LO4.2 Maintain computer systems and networks | — (no practice mission yet; existing form-based "Perform Preventive Computer Maintenance" assessment links here) | 2.1–2.5 |
| | LO4.3 Diagnose faults of computer systems | M2 Diagnose and Repair Hardware Faults; M3 Diagnose Hardware and Software Faults | 3.1–3.4 |
| | LO4.4 Rectify/correct defects in computer systems | M4 Replace and Reconfigure a Component | 4.1–4.4 |
| | LO4.5 Inspect and test the computer systems and networks | M5 Apply Repair Action and Create Report | 5.1–5.6 |

Three modules have no practice mission (LO1.3, LO2.3, LO4.2); they are completed through their published topics until missions exist, and the gap is reported, not hidden. COC3 uses the owner-approved teaching sequence LO3.2 → LO3.1 → LO3.3 (`sequence_order`), so server preparation and installation come before user access; every other COC follows the official LO order.

### WS2 — Realistic assembly and simulation-based assessment

**Assembly bench (COC1 M2, new contract version):**
- A new scene for placement/connection phases: an open case (side view) with the motherboard drawn in its installed position; physically placed slots (CPU socket with lever, DIMM slots with latches, M.2/SATA, PCIe, 24-pin, 8-pin EPS, SATA, front-panel and CPU_FAN headers), a PSU bay and drive bay; a parts tray and tool tray with real images (existing `assets/COC1/Mission 2/` plus the unused case and HDD images; new cable/connector art where missing).
- Interactions: drag with an image ghost (tap-to-select and tap-to-place alternative); magnetic snap into the exact slot rectangle with a seat animation; visible rotation (button and gesture) for parts whose orientation matters (CPU triangle, RAM notch, PSU fan); levers, latches and screws operated with the selected tool; cables drawn from PSU connectors to board headers; remove-and-reseat to correct mistakes.
- Realistic order, grouped into ≤ 6 phases with visible steps inside each phase: (1) prepare the work area and ESD protection and inspect parts; (2) prepare the motherboard on the anti-static mat — CPU (open lever, align, seat, close), thermal compound and cooler, CPU_FAN, RAM (open latches, align notch, seat in the recommended slots); (3) install into the case — PSU, I/O shield and motherboard on standoffs with screws, storage; (4) connect power and data — 24-pin, 8-pin EPS, SATA power and data, front panel; (5) power-on test and interpretation of the POST/firmware result; (6) evidence review.
- A step header shows step n of N, elapsed time, correct and incorrect actions.
- The contract is evaluated by the existing server verifier. One backward-compatible extension is needed: placement items may declare `requires` conditions (for example "lever open") checked at replay time. Items without it behave exactly as today.

**Practice vs Assessment presentation:**

| | Practice | Assessment |
|---|---|---|
| Step guidance, "Show me how", compatible-slot glow | Shown | Hidden |
| Feedback on an invalid action | Specific technical reason | Neutral physical feedback only ("Component not seated"), never the correct target |
| Retry | Unlimited; discard and restart supported | Governed by the assignment (attempts, retry wait) |
| Submission | Verify when all steps are done | Learner may submit at any time after confirmation; unfinished steps are evaluated as not satisfied |
| Timer | Existing COC practice timer | Attempt time recorded by the server (start → submit) |

**Realistic mistakes (builder call):** a part that physically cannot fit a slot (shape or connector mismatch) is refused with neutral feedback in both modes, as real hardware would. Mistakes that are physically possible — the wrong DIMM pair, an unfastened screw, an open CPU lever, a missing EPS or SATA cable — are allowed and recorded, and surface at the power-on test as a realistic POST/firmware symptom that the learner must interpret and correct. Incorrect attempts affect assessment criteria by the owner-approved threshold rule (decision 7): the server counts, per step, the invalid actions found by replay plus the physically possible mistakes that had to be corrected, and the generated rubric marks each step's criterion satisfied only within its threshold (two incorrect attempts, zero for safety-critical steps). Practice mode reports the same counts as learning feedback without failing the learner.

**Shared server replay:** the replay logic inside `practice_verify_mission` becomes a pure function `private.simulation_replay(definition, actions)` that returns phase completion, final state, invalid-action counts and timestamps without raising. `practice_verify_mission` keeps its exact behaviour on top of it (regression-tested).

**Practice run metrics:** each run (actions between restart markers) is summarised at verification by the server — run number, start/end, duration, total and invalid actions, per-step results, outcome — and stored in `practice_mission_runs`. Failed verifications are recorded too. These rows feed learner progress and instructor analytics (R2.5, R5.E).

**Simulation-based assessment packages:** for each mission an assessment activity version is generated from its Flutter definition: `learner_payload` names the mission, the definition version and `mode: assessment` (no `simulation_template`, so the existing launcher opens `MissionSimulationScreen` in assessment mode); `evaluator_config` holds a snapshot of the simulation contract; rubric criteria are the mission's steps, each with the new evidence operator `simulation_condition` (replay + condition) and its performance-criteria references. Scoring stays `binary_sum`, all-required. The client refuses to start an assessment whose definition version it does not have. Evaluation, finalization and release use the existing attempt lifecycle.

**Distinct tasks and history:** existing form-based packages stay published and assignable, are linked to their correct module through `activity_curriculum_links`, and are labelled "Form-based assessment" in the dashboard; their historical attempts and results are untouched. The protected COC2 M2 cable-termination assessment keeps its current evaluation rules. Converting the distinct legacy tasks into simulations is WS9.

### WS3 — Sequential unlocking and one progress methodology

**Completion methodology (documented and shared by every screen and the dashboard):**
- *Topic complete:* the learner opened the latest published revision and confirmed completion.
- *Mission complete (practice):* a server-verified completion exists for an accepted contract version (existing rule, including legacy versions).
- *Module complete:* every published topic in the module is complete and every mission whose primary module is this module is complete. A module with no required items shows "No required activities yet" and does not block progression.
- *COC complete:* every module complete and the existing COC practice quiz passed (existing `practice_coc_progress` row).
- *Unlocked:* the first module of COC1 is always unlocked; each next module unlocks when the previous module (by `sequence_order`) is complete; the first module of COC n+1 unlocks when COC n is complete. An instructor COC bypass unlocks that COC's modules for practice (fixing the current gap where bypass does not reach the practice lock).
- *Unlocks are permanent (builder call):* an unlock is stored in `learner_module_unlocks` (learner, module, unlocked_at, reason `sequence | bypass | migration`) the first time it is earned and is never revoked by later content changes. Publishing a new topic, adding a mission link or changing `sequence_order` only affects learners who have not yet unlocked the affected module; a completed module that gains new content shows "New content available" without re-locking anything after it. At cutover, unlocks are backfilled from existing completions and every existing `practice_coc_progress` row keeps the next COC open.
- *Progress percentages:* learning progress = completed required items / total required items (topics + missions + COC quiz) per module and COC. Performance (quiz, assessment, homework scores) is reported separately and never mixed into completion.

**Enforcement:** one server function determines module unlock state and is used by the restrictive RLS insert policy on `practice_mission_actions`, by the verifier and by the topic-completion RPC, so direct API calls cannot bypass prerequisites. Existing completions and COC progress rows are preserved; a learner who already completed missions in a later module keeps that credit.

**Mobile restructure:** bottom navigation becomes Home · Learn · Practice · Progress · Rewards.
- *Learn:* COC → modules (lock/complete state, prerequisite text, progress) → module detail: published topics, official learning outcomes, linked quizzes and resources.
- *Practice:* COC → modules → missions with lock icons, prerequisite text, verified state, best time and attempts.
- *Progress:* overall COC progress, module and topic completion, missions and attempts, quiz scores, assignment status and released assessment results, all from one server projection.
- *Home:* to-do (quizzes, homework, assessments), notifications, resume; classes remain reachable from Home.

### WS4 — Quiz management

- **Curriculum and settings on the quiz:** COC required for new quizzes; scope either the whole COC (pre-assessment or summative quizzes) or one or more modules (`quiz_modules`); optional `topic_id`; linked performance criteria (`quiz_learning_outcomes`); `focus` (required: what the quiz assesses); `quiz_type` (`pre_assessment`, `formative`, `summative`), `difficulty` (`foundation`, `intermediate`, `advanced`), `time_limit_minutes` (optional), `result_release_mode` (`immediate` or `instructor_release`). Existing quizzes stay valid and are flagged "Not mapped to a module" until edited.
- **Scenario essay item type (`scenario_essay`):** scenario text, prompt, rubric (criteria with descriptors and points), optional word limits. Learners write long-form answers (autosaved). Quizzes with essays always use `instructor_release`.
- **Grading:** objective items are graded at submission as today; essay criteria are scored by the instructor with feedback (append-only evaluation rows, consistent with the immutable results model); the result then moves through Finalize and Release (WS5).
- **Rules:** one attempt per learner (existing, server-enforced); time limit enforced by the server (the effective expiry is the earlier of start + limit and the class deadline in force at that moment, so a deadline extended *before* expiry also extends in-progress attempts); automatic submission of saved answers at deadline or time-limit expiry, marked "Auto-submitted", unanswered items scored zero, nothing invented; explicit availability status `draft / published / closed / archived` with a "Close now" action; submission timestamps; status indicators for learners. This replaces the earlier rule that expired unfinished work stays unsubmitted, as the panel requested.
- **Auto-submission semantics (builder call):** an attempt is treated as submitted at its effective expiry time, whenever the server actually processes it, so the outcome never depends on when someone next opens the quiz. Reopening or extending a quiz *after* its deadline first finalises every attempt that expired under the old deadline; reopening therefore lets learners who never started take the quiz but does not revive auto-submitted attempts. Attempts that expired before this release are left exactly as they are (no retroactive grading).
- **AI generation:** grounded in the selected module, topic, performance criteria and focus, difficulty and type; settings persisted on the quiz; can draft scenario essays with rubrics; "Regenerate this question" replaces a question in one audited step (original kept in history); nothing is published without instructor approval (existing).
- **Quiz questions publication (owner decision 2):** the existing instructor approval stays the workflow for quizzes (the six-stage admin workflow applies to curriculum content only): each question shows Draft / Approved / Rejected; a version can be published only when every active question is approved (existing rule); each quiz shows its published version and the classes that can see it; learners only see published versions.
- **Dashboard:** library filters by COC, module, topic, type and status with sorting; results tab with participants, completion rate, average, highest, lowest, distribution, per-question correctness and links to essay evaluation; deadlines and archive (existing).
- **Mobile:** essay answer screen, countdown for timed quizzes, auto-submitted and awaiting-evaluation states, released results with rubric feedback.

### WS5 — Evaluation Center (Objective 4)

One instructor page with four queues and filters (class, item type, COC/module, learner):

| Queue | Technical assessments | Quizzes (instructor release) | Homework |
|---|---|---|---|
| **Evaluate** | automatically evaluated, awaiting instructor review of criteria | essays not yet scored | submitted, not graded |
| **Finalize** | instructor evaluation recorded (`under_review`) | all essays scored | grade and feedback saved |
| **Release** | finalized | finalized | finalized |
| **Released** | visible to learner | visible to learner | visible to learner |

- Technical attempts gain an explicit "record evaluation" step (`evaluated → under_review`) before finalization, so no stage can be skipped; existing `evaluated` attempts appear in Evaluate; existing finalized/released attempts keep their state.
- Homework grading becomes draft → finalize → release; existing graded submissions are migrated as released (they are already visible to learners), preserving their scores and feedback.
- Transitions are server-enforced and audited; bulk finalize/release requires confirmation.

### WS6 — Analytics

- New `SECURITY INVOKER` RPCs with one shared, server-validated filter set (class, COC, module, topic, mission, quiz, date range, learner) and class-scoped RLS read policies for instructors on practice tables, runs and homework:
  - **Overview:** learners (enrolled, active in period, completed), classes, average assessment/quiz/homework performance, mission completion, overall learning progress; every card states its population and period.
  - **Classes:** comparison table (enrolled, average, quiz performance, mission completion, assignment completion, progress, highest/lowest) and class detail.
  - **Learners:** list with status (on track / struggling / falling behind, thresholds documented) and a learner profile combining COC/module/topic progress, missions and attempts, quizzes, assignments and released assessment results.
  - **Quizzes:** participants, individual scores, average, highest, lowest, completion rate, submission status, distribution, per-question correctness.
  - **Missions:** total, completed, incomplete, completion rate, attempts per learner, successful and failed attempts, average completion time — from practice runs and assessment attempts, labelled separately.
  - **Criteria:** assessment criteria, simulation steps and essay rubric criteria with maximum, learner score, percentage, class average, strongest and weakest.
- **Accuracy rules:** only published quiz versions and submitted attempts count; pending evaluations are shown separately and excluded from averages; one learner counted once per population; class scope never mixes unrelated classes; empty states instead of zeros when there is no data. Metric definitions are documented in code and in `docs/`.
- Charts use recharts with titles, axis labels and readable values; tables back every chart; CSV export extends the existing report export.

### WS7 — Homework (assignments)

- Optional `coc_module_id`, `module_id` and `mission_id` links; learning objectives; criteria with points; `max_score`; submission requirements. Existing assignments remain valid (unlinked, max score 100).
- Instructor submissions workspace across assignments with filters (class, learner, COC, mission, status, late) and a missing-work view; grading by criteria within the WS5 flow; grader name shown.
- Mobile: filter by COC and mission; criteria and maximum score visible; scores visible only after release.

### WS8 — Learner management

- **Student ID:** `profiles.learner_id` becomes staff-managed once set by an import or an admin: a profile trigger rejects a learner's change to a staff-managed value (the column grant stays, so older installed app versions that resend the unchanged value keep working); the new app shows it read-only. Uniqueness among learners is enforced by a partial unique index if the existing data has no duplicates, otherwise enforced at import and reported.
- **Roster import** (instructor, per class): download `.xlsx` template (`student_id, last_name, first_name, email, course_section`); upload `.xlsx`/`.xls` (size and row limits); server-side parsing and validation (required fields, email format, duplicates within the file, conflicts with existing profiles, non-learner accounts, already-enrolled learners); preview grouped as Enroll now / Pending / Skip / Invalid; confirm; summary and downloadable error report. Nothing is imported without confirmation and invalid rows are never silently imported.
- **Pending roster entries** (`class_roster_entries`): claimed when a learner signs up with the same email (and the same student ID when both are present); the learner is enrolled, the student ID is set if empty, an audit event is written and the roster shows "Joined via roster". Because sign-up email is not verified while SMTP is deferred, the instructor can remove a claimed enrollment; this limitation is documented.
- **Search:** server-side search (name, student ID, email, class), status and class filters, sorting and pagination on `/learners`, `/users` and the instructor learner list, with loading, empty and error states.

### WS9 — Remaining simulation assessments and distinct tasks

- Generate and publish simulation-based assessment versions for all 20 missions (WS2 pipeline).
- Build 2D simulation tasks for distinct legacy assessment tasks and for the three modules without missions, in priority order (LO4.2 preventive maintenance, COC2 LAN-tester diagnosis, LO1.3 application software, LO2.3 router/Wi-Fi). Anything not finished is reported as remaining, with its form-based assessment still available.

### WS10 — Objectives 2 and 6

- **Objective 2 (points, levels, rewards, achievements, progress tracking):** server-side, motivational gamification kept separate from competency: points awarded exactly once per qualifying event (verified practice mission, completed topic, completed module, completed COC, submitted quiz, on-time homework, released assessment), levels from cumulative points, achievements (badges) for milestones, and a Rewards tab showing real points, level progress, earned and locked achievements, and an opt-in class points leaderboard. Awards are written by the server from real events; nothing is mixed into competency results.
- **Objective 6 (learners and instructors, real time):** the instructor analytics of WS6 plus a learner-facing analytics view in the app (progress, competency achievement per criterion, scores, released results) that refreshes in real time through Supabase Realtime where available, with a short polling fallback; the instructor dashboard refreshes the same way.

### WS11 — Demo data, QA, documentation and handoff

A repeatable demo-data script creates the labelled demo class and synthetic learner accounts and drives real activities through the normal APIs and RPCs (practice runs, simulation assessments taken and evaluated, quizzes with essays, homework, topic progress), so analytics show genuine aggregates; it is idempotent, clearly labelled and reversible. Full Flutter analyzer/tests/debug build, dashboard type-check/lint/tests/build, rollback-only SQL suites for every new migration on the local stack, browser checks of the dashboard, the final implementation report (audit → revisions → verification → tests → remaining → re-defense checklist), and `CODEX_STATE.md`.

## 7. Migration and preservation strategy

- Additive tables, nullable or defaulted columns, new enum values; existing rows remain valid.
- Function replacements keep their signatures and are covered by before/after regression tests (`practice_verify_mission`, quiz submission, homework, attempt finalization).
- Catalog title changes keep previous values in history; mission IDs never change.
- Published activity, quiz and topic versions are never edited; changes create new versions.
- Historical attempts, results, practice actions and completions are never deleted or rewritten. The only data migration that changes visible state is homework: already-graded submissions are marked released (they are visible today).
- Hosted application later follows the existing procedure: fresh encrypted backup, isolated restore rehearsal, ordered migrations, smoke tests, owner approval.

## 8. Testing

- SQL rollback suites per migration: workflow transitions and role denials, unlock enforcement including direct-API bypass attempts, replay parity with the old verifier, assessment criterion evaluation, quiz auto-submission with a controlled clock, essay evaluation and release, homework release migration, roster claim on sign-up, analytics fixtures with known expected values.
- Dashboard: unit tests (parsers, validators, metric helpers), API route tests, browser checks at 320/768/1440 px.
- Flutter: widget tests for the assembly bench (drag, tap, rotate, snap, operations, reduced motion, large text), assessment-mode hiding of guidance, Learn/Practice/Progress lock states, essay quiz, auto-submitted state; definition/contract export parity.
- The 23 scenarios of the revision brief are tracked in the final report with pass/fail evidence. Device, TalkBack and hosted checks are recorded separately and never inferred.

## 9. Changes to existing SECURITY DEFINER functions (explicit review)

| Function | Change |
|---|---|
| `private.evaluate_criterion_evidence` / `private.valid_evidence_rule` | Add the `simulation_condition` operator (replays the attempt's actions against the activity's contract snapshot). |
| `public.handle_new_user` | After creating the profile, claim matching pending roster entries (enroll, set student ID if empty, audit). |
| `public.finalize_attempt` | Require the new `under_review` evaluation step (Objective 4) while preserving adjustment validation. |
| `public.create_instructor_quiz`, `public.update_instructor_quiz` | New curriculum scope and settings fields. |
| `public.upsert_quiz_item`, `public.publish_quiz_version` | `scenario_essay` validation (rubric, points). |
| `public.start_learner_quiz`, `public.save_learner_quiz_answer`, `public.submit_learner_quiz`, `public.get_available_learner_quizzes`, `public.get_learner_quiz_result` | Time limit, automatic submission, essay answers, pending-evaluation and release states. |

No other definer function is added. New behaviour otherwise lives in `SECURITY INVOKER` or service-only functions.

## 10. Delivery checkpoints

After each workstream: tests green, scoped commit, short status note to the owner, `CODEX_STATE.md` updated. The owner can stop, reorder or review at any checkpoint. Nothing is pushed or deployed without approval. When the local work is complete, a separate hosted rollout package (fresh encrypted backup, restored-production rehearsal of every new migration, ordered application, Vercel deployment, new APK, demo data, smoke tests) is presented for explicit approval before the defense.

**Test environment note:** this machine's Windows Application Control policy blocks `flutter_tester.exe`, so Flutter widget/unit tests run in a Linux container (`ghcr.io/cirruslabs/flutter:3.44.0`) against a read-only copy of the app; the analyzer and the Android build run natively.

## 11. Left to the builder

Component and file structure, visual styling within the existing design system, exact metric thresholds for "struggling / falling behind" (documented), naming of enum values not fixed above, pagination sizes, whether topic attachments reuse the direct-upload pipeline in this release (text-only topics are acceptable if attachments do not fit), and whether a GPU is added to the assembly.

## 12. Risks

- **Scope:** WS9 (new simulations for distinct tasks) is the most likely to remain partially complete; it is last for that reason.
- **Definition/version skew:** a learner with an old app cannot take a newer simulation assessment; the version check blocks it with an update message.
- **Unverified sign-up email:** roster auto-enrollment trusts the sign-up email until SMTP exists; mitigated by the matching rules, audit and instructor removal.
- **Hosted rollout:** every migration must pass the restored-production rehearsal before the owner approves hosted application.

## 13. Open questions for the owner

- **O1 —** Confirm the mission → module mapping table (WS1) as part of approving this design.
- O2–O5 were answered on 2026-11-19 and are recorded as decisions 5–8 in Section 4.

## 14. Pending input

Verbatim Objectives 2, 4 and 6 from the final manuscript and the panel's exact comment on each, and the re-defense date. WS5 already covers the Evaluate/Finalize/Release request; WS10 depends on this input; the date decides how much of WS9 can be completed before the hosted rollout.
