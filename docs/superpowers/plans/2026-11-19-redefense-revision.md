# ByteQuest Re-Defense Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver every re-defense revision in the approved design (realistic assembly with simulation-based assessment, curriculum hierarchy and sequential unlocking, quiz upgrades with scenario essays, Evaluate → Finalize → Release, homework by COC/mission, analytics for instructors and learners, Excel roster import and search, gamification) locally on `vince-branch` before Monday 2026-11-23.

**Architecture:** Supabase/PostgreSQL stays authoritative. A foundation commit adds the shared schema every slice depends on; then independent vertical slices (database + dashboard + app per feature) run in parallel in isolated worktrees with reserved migration timestamps and disjoint file ownership; the coordinator merges, regenerates types, runs all gates, seeds demo data and writes the report.

**Tech Stack:** Flutter 3.44 / Dart 3.12 (`provider`, `supabase_flutter`), Next.js 15 / React 19 / TypeScript / recharts / Tailwind + Radix, Supabase PostgreSQL 17 (RLS, plpgsql, pgTAP), SheetJS 0.20.3 (official tarball) for Excel.

**Spec:** `docs/superpowers/specs/2026-11-19-redefense-revision-design.md` (audit: `docs/REDEFENSE_REVISION_AUDIT_2026-11-19.md`).

## Global Constraints

- RLS stays enabled on every public table; no table loses a policy.
- No new `SECURITY DEFINER` function. Only the definer functions listed in spec Section 9 may be modified. New server logic is `SECURITY INVOKER`: service-only functions (granted to `service_role`, called by authenticated Next.js routes that pass `p_actor`), RLS-scoped read functions, or triggers.
- Migrations are additive; never edit an existing migration file; never delete or rewrite learner records, attempts, results, practice actions/completions or audit events; published versions stay immutable.
- Reserved migration timestamps (one owner each, see Execution Model).
- Official TESDA text is copied verbatim from `docs/reference/tesda_sources/TR_current.txt` (Amended December 2013) with its line range in `source_reference`.
- Mobile: no hardcoded strings in widgets (mission feedback strings in `lib/data/mission_content_data.dart`; other feature strings may live in a feature file `lib/data/<feature>_content_data.dart`); never "Wrong"/"Correct"; 48×48 dp targets; `Semantics` labels; large text; reduced motion; transitions 150–250 ms; ByteQuest blue/navy; no glassmorphism, glow, giant cards.
- Assessment mode never exposes correct targets, compatible-slot highlights or guidance.
- Dashboard: server-side role checks on every route; `?tab=` deep links; loading, empty, error and success states on every new view; no hardcoded metrics.
- Do not edit `ByteQuest-Web-Dashboard/src/types/database.generated.ts` in slices; declare feature-local types. The coordinator regenerates it after merging.
- Gates per slice: `flutter analyze --no-fatal-infos` (native, 0 errors/0 warnings), Flutter tests through `pwsh scratchpad/flutter-test-docker.ps1` (Windows blocks `flutter_tester.exe`), `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test`, SQL suites through `docker exec -i supabase_db_ByteQuest psql`.
- Commits: imperative mood, specific files staged, never `git add .`, never `.env*`, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push, no hosted change, no deploy.

## Review Focus

1. **A learner with existing progress at cutover** (completions in later modules, an unfinished mission, a passed COC quiz) keeps every unlock and can finish in-progress work; test in Task A2.1 (`backfill_keeps_existing_progress`).
2. **The installed 1.1.0+2 APK against the new backend:** unchanged profile saves (same `learner_id`) succeed and evidence for unlocked modules is accepted; tests in Task A5.1 (`unchanged_learner_id_update_allowed`) and Task A2.1 (`legacy_unlocked_mission_accepts_evidence`).
3. **Quiz deadline edge cases:** expiry while answering, extension before expiry, reopen after expiry, attempts expired before the release; tests in Task A3.2.
4. **Messy roster files:** blank rows, header case/spacing variants, duplicate rows, mixed-case emails, `.xls` files, extra columns, an email that belongs to a staff account; tests in Task A5.2.
5. **Analytics with sparse or awkward data:** zero learners, pending evaluations, one learner in two classes, unpublished quizzes; tests in Task A7.1.

---

## Execution Model

| Wave | Owner | Slice | Reserved migrations | Owned paths (exclusive) |
|---|---|---|---|---|
| 0 | Coordinator | F: foundation | `20261119100000`–`20261119100900` | `supabase/migrations/202611191000*`, `scripts/local-qa-fixtures.mjs`, `supabase/tests/foundation_redefense_rollback.sql` |
| 1 | Agent A1 | Assembly bench + simulation assessment | `20261119110000`–`20261119110900` | `lib/screens/simulation/**`, `lib/data/mission_definitions/**`, `lib/data/mission_simulation_definitions.dart`, `tool/export_practice_contracts.dart`, `scripts/publish-simulation-assessments.mjs`, `assets/COC1/Mission 2/**`, `ByteQuest-Web-Dashboard/src/app/api/learner/practice/**` |
| 1 | Agent A2 | Unlocking, Learn/Practice/Progress, curriculum publication | `20261119120000`–`20261119120900` | `lib/screens/{missions,courses,progress,dashboard}/**`, `lib/widgets/bytequest_bottom_nav.dart`, `lib/services/{practice_progress_service,curriculum_service}.dart`, `ByteQuest-Web-Dashboard/src/app/{curriculum,api/curriculum,api/learner/curriculum}/**`, `src/components/curriculum/**` |
| 1 | Agent A3 | Quizzes | `20261119130000`–`20261119130900` | `lib/screens/quizzes/**`, `lib/services/learner_quiz_service.dart`, `src/app/quizzes/**`, `src/components/quizzes/**`, `src/lib/quizzes/**`, `src/lib/ai/**`, `src/app/api/instructor/quizzes/**` |
| 1 | Agent A4 | Evaluation Center + homework | `20261119140000`–`20261119140900` | `src/app/{evaluations,submissions,attempts}/**`, `src/components/{attempts,evaluations,classes/Homework*}/**`, `src/app/api/{activities/homework,evaluations}/**`, `lib/screens/homework/**`, `lib/services/homework_service.dart` |
| 1 | Agent A5 | Roster import, search, student ID, UI fixes, app version | `20261119150000`–`20261119150900` | `src/app/{learners,users,progress,classes/[id]/import}/**`, `src/app/api/{roster,learners}/**`, `src/components/{users,learners,dashboard}/**`, `src/app/classes/[id]/page.tsx`, `lib/screens/settings/edit_profile_screen.dart`, `lib/screens/profile_setup/**`, `lib/screens/splash/**` |
| 1 | Agent A6 | Gamification | `20261119160000`–`20261119160900` | `lib/screens/leaderboard/**`, `lib/services/rewards_service.dart`, `lib/models/rewards_model.dart` |
| 2 | Agent A7 | Analytics (instructor + learner, real time) | `20261119170000`–`20261119170900` | `src/app/{analytics,reports,progress/learners}/**`, `src/components/analytics/**`, `src/lib/analytics/**`, `lib/screens/progress/performance_*`, `lib/services/performance_service.dart` |
| 3 | Coordinator | Merge, types, demo data, gates, report | — | `scripts/seed-demo-class.mjs`, docs, `CODEX_STATE.md` |

Shared files touched by several slices (navigation configs, `mission_content_data.dart`, `main_navigation_screen.dart`) are edited minimally and append-only; the coordinator resolves merge conflicts. Each agent works in its own worktree branched from the foundation commit and finishes with all gates green and one or more commits on its branch.

---

## Wave 0 — Foundation (coordinator)

### Task F1: Secure evaluator configuration and local test harness

**Files:**
- Create: `supabase/migrations/20261119100000_secure_activity_evaluator_config.sql`
- Create: `scripts/local-qa-fixtures.mjs`
- Create: `supabase/tests/foundation_redefense_rollback.sql`
- Modify (only if a client selects `*` from `activity_versions`): the reading service/page to list explicit columns

**Interfaces:**
- Produces: `node scripts/local-qa-fixtures.mjs` → idempotently creates local Auth users `qa.admin@bytequest.local`, `qa.instructor@bytequest.local`, `qa.instructor2@bytequest.local`, `qa.learner1..3@bytequest.local` (roles set via SQL), prints their IDs; refuses any API URL that is not `http://127.0.0.1:57321`.

- [ ] Step 1: Write pgTAP test `authenticated_cannot_read_evaluator_config`: `ok(not has_column_privilege('authenticated','public.activity_versions','evaluator_config','SELECT'))` and `ok(has_column_privilege('authenticated','public.activity_versions','learner_payload','SELECT'))`.
- [ ] Step 2: Run it → FAIL (table-wide grant).
- [ ] Step 3: Migration: `revoke select on public.activity_versions from authenticated;` then re-grant the original column list (`id, mission_id, module_version_id, version_number, title, instructions, delivery_mode, learner_payload, status, published_at, created_at, updated_at`).
- [ ] Step 4: Run test → PASS; grep mobile and dashboard for `from('activity_versions')` / `activity_versions(` selects and make any `*` select explicit.
- [ ] Step 5: Run the fixture script, then all 15 legacy SQL suites → previously fixture-blocked suites pass.
- [ ] Step 6: Commit.

### Task F2: Curriculum foundation schema, official seed and shared tables

**Files:**
- Create: `supabase/migrations/20261119100100_curriculum_foundation.sql`
- Modify: `supabase/tests/foundation_redefense_rollback.sql`

**Interfaces (produced, used by every slice):**
- `public.content_publication_status` enum: `draft, submitted, needs_revision, evaluated, finalized, approved, published, unpublished, archived`.
- `public.curriculum_modules(id uuid pk, coc_module_id uuid → coc_modules, coc_code text, code text, title text, element_title text null, sequence_order int, source_reference text, created_at)`; unique `(coc_code, code)`; 16 rows; COC3 `sequence_order`: LO3.2=1, LO3.1=2, LO3.3=3.
- `public.learning_outcomes(id uuid pk, module_id → curriculum_modules, code text, statement text, sequence_order int, source_reference text)`; unique `(module_id, code)`; official PCs verbatim; COC1 element 2 PCs 2.1–2.3 attached to LO1.2 with `source_reference` noting "Element 2 Prepare installer (no curriculum LO)".
- `public.curriculum_topics(id uuid pk, module_id, sequence_order int, created_by uuid, created_at, archived_at)`.
- `public.curriculum_topic_revisions(id uuid pk, topic_id, revision_number int, title text, summary text, body_markdown text, outcome_ids uuid[], status content_publication_status default 'draft', author_id uuid, submitted_at, evaluated_by, evaluated_at, evaluation_notes, finalized_by, finalized_at, approved_by, approved_at, published_by, published_at, unpublished_by, unpublished_at, created_at, updated_at)`; unique `(topic_id, revision_number)`.
- `public.content_publication_events(id bigint identity, entity_type text, entity_id uuid, revision_id uuid, from_status, to_status, actor_id uuid, note text, occurred_at)` append-only (reuse `private.prevent_append_only_mutation`).
- `public.mission_curriculum_links(mission_code text pk, module_id, pc_codes text[], sequence_order int)` seeded per spec mapping table.
- `public.activity_curriculum_links(activity_version_id uuid pk → activity_versions, module_id, delivery_kind text check in ('simulation','form_based','protected_reference'))`.
- `public.learner_topic_progress(learner_id uuid, topic_id uuid, revision_id uuid, completed_at timestamptz, pk(learner_id, topic_id))`.
- `public.learner_module_unlocks(learner_id uuid, module_id uuid, unlocked_at timestamptz, reason text check in ('sequence','bypass','migration'), pk(learner_id, module_id))`.
- `public.practice_mission_runs(id uuid pk, learner_id, mission_id text, contract_version text, run_number int, started_at, ended_at, duration_seconds int, action_count int, invalid_count int, correction_count int, outcome text check in ('verified','incomplete'), step_results jsonb, failure_code text, created_at)`.
- `public.practice_mission_unlocked(p_mission text, p_learner uuid) returns boolean` stable invoker — **initial body:** `select public.practice_coc_unlocked(left(p_mission,4), p_learner)` (A2 replaces the body).
- `public.mission_catalog_history(mission_code, previous jsonb, replaced_at)` + canonical catalog update of `missions` (title, scenario, objective) to the effective Flutter titles/scenarios.
- RLS: learners read published modules/outcomes/topic revisions (status `published`), own progress, own unlocks, own runs; staff read all curriculum; instructors read runs/progress/unlocks of learners in classes they own; no client write grants (writes come from service-only functions owned by slices).

- [ ] Step 1: pgTAP tests: 16 modules; COC1 has 4, COC2 4, COC3 3, COC4 5; LO1.1 title equals `Assemble computer hardware`; PC `1.4` statement equals `Computer hardware is assembled in accordance with established procedures and systems requirements`; all 20 missions linked; `coc2_m3` catalog title equals `Construct and Verify a Network Topology`; learner cannot insert into `learner_module_unlocks`; learner sees only published topic revisions.
- [ ] Step 2: Run → FAIL. Step 3: write migration. Step 4: Run → PASS together with all legacy suites. Step 5: Commit, tag `redefense-foundation`.

---

## Wave 1 — Parallel slices

Each slice's brief below is complete for its agent: it lists the interfaces it consumes and produces, its tasks and its tests. Tasks run TDD (failing test → implement → pass → commit).

### Slice A1 — Realistic assembly bench and simulation-based assessment

**Consumes:** `practice_mission_runs`, `practice_mission_unlocked`, `mission_curriculum_links`, `activity_curriculum_links` (F2).
**Produces:**
- `private.simulation_replay(p_definition jsonb, p_actions jsonb) returns jsonb` (invoker, immutable, never raises). `p_actions` = ordered array of `{action_type, target, phase_id, value, occurred_at}`. Returns `{done:{phase_id:true}, state:{…}, invalid:{"item:cpu":1,…}, corrections:{"item:ram_a":1,…}, phase_invalid:{phase_id:n}, action_count, invalid_count, correction_count, first_at, last_at}`. Supports every action kind of the current verifier plus `placement_removed` (removes `placed.<item>`, counts a correction) and item-level `requires` conditions for placements.
- `public.practice_verify_mission(uuid,text)` keeps signature and behaviour, now built on the replay, checks `practice_mission_unlocked`, and writes a `practice_mission_runs` row (`outcome='verified'`). `public.practice_record_failed_verification(p_learner uuid, p_mission text, p_failure text) returns void` service-only, writes an `incomplete` run.
- Evidence operator `simulation_condition` in `private.evaluate_criterion_evidence` + `private.valid_evidence_rule`: rule `{operator:'simulation_condition', phase_ids:[…], conditions:[…same format as equipment completion…], counted_targets:['item:cpu','operation:cpu_lever_close',…], max_incorrect:int}`; satisfied iff all phases done, all conditions true on the final state and the sum of `invalid`+`corrections` over `counted_targets` ≤ `max_incorrect`; `observed_evidence` includes the counts.
- COC1 M2 contract version `css-assembly-20261119-v3` (≤ 6 phases: prepare & ESD; motherboard preparation — CPU lever/align/seat/close, cooler + CPU_FAN, RAM latches/notch into DIMM A2/B2; case installation — PSU, I/O shield, motherboard on standoffs + screws, storage; power and data — 24-pin, 8-pin EPS, SATA power, SATA data, front panel; power-on test + interpretation; review), exported by `tool/export_practice_contracts.dart` into `supabase/migrations/20261119110200_coc1_m2_assembly_contract.sql`.
- `AssemblyBench` widget (`lib/screens/simulation/components/assembly/assembly_bench.dart` + parts) used for COC1 M2 place/connect phases in both modes.
- `scripts/publish-simulation-assessments.mjs`: publishes one simulation assessment activity version per mission (learner payload `{mission_id, definition_version, mode:'assessment'}`, `evaluator_config.simulation_definition`, rubric criteria = steps with PC refs, `binary_sum`, threshold 2 / safety-critical 0), links each in `activity_curriculum_links` (`simulation`), and links existing form-based packages (`form_based`; COC2 M2 cable package `protected_reference`).

**Tasks:**
- [ ] A1.1 Replay function + verifier refactor. Tests (`supabase/tests/simulation_replay_rollback.sql`): replaying the 20 current contracts with their recorded happy-path actions gives the same `done` set as the old verifier (parity); invalid placement increments `invalid["item:<id>"]`; `placement_removed` then re-placement increments `corrections`; placement with unmet item `requires` is invalid; verify on a locked mission raises `PRACTICE_COC_LOCKED`; verified run row written with duration = last − first action seconds.
- [ ] A1.2 `simulation_condition` operator. Tests: satisfied with ≤ threshold; not satisfied when a counted target exceeds threshold; not satisfied when a phase is missing; safety-critical criterion with `max_incorrect 0` fails after one invalid attempt; learner role cannot execute the evaluator.
- [ ] A1.3 Assembly bench UI + COC1 M2 v3 definition (practice + assessment presentation). Widget tests: image drag ghost; tap-select then tap-slot places; rotate button changes rendered rotation and recorded `orientation`; snap animation lands within the slot rect (reduced motion → no animation); operations (lever, latch, screw) only enabled when `requires` met; physically incompatible part refused with neutral feedback; assessment mode hides guidance, step hints and compatible highlights and allows "Submit assessment" after confirmation; 48 dp targets and Semantics labels; 320×568 and 640×360 layouts without overflow.
- [ ] A1.4 Contract export + migration + parity test (`test/practice_contract_export_test.dart` asserts the SQL file content equals a fresh export).
- [ ] A1.5 Practice API route records failed verifications (`practice_record_failed_verification`) and returns run metrics; Node test for the route helper.
- [ ] A1.6 Publish script + SQL lifecycle test: start an assessment attempt for COC1 M2, append a perfect action set → all criteria satisfied, outcome competent; append a run with two CPU orientation errors → CPU criterion not satisfied.

### Slice A2 — Sequential unlocking, Learn/Practice/Progress and curriculum publication

**Consumes:** F2 tables; `practice_mission_runs` (read).
**Produces:**
- Replaces `public.practice_mission_unlocked` body: COC unlocked (existing rule, or a `coc_bypasses` row for the learner's class) AND (module first in COC by `sequence_order`, OR `learner_module_unlocks` row, OR bypass). RLS gate `practice_actions_progression_gate` re-created to call it.
- Triggers (invoker) on `practice_mission_completions`, `learner_topic_progress`, `practice_coc_progress` → `public.refresh_learner_unlocks(p_learner uuid)` inserts newly earned unlock rows (never deletes).
- Migration backfill: unlock rows (`migration`) for every module containing a completed mission or any recorded action, every module before those in its COC, and the first module of every unlocked COC.
- `public.get_learner_curriculum() returns jsonb` (invoker): `{cocs:[{coc_code,title,unlocked,completed,lock_reason,progress:{done,total,percent},quiz:{eligible,passed},modules:[{id,code,title,sequence_order,unlocked,completed,lock_reason,progress:{done,total,percent},new_content:boolean,topics:[{id,revision_id,title,summary,completed}],outcomes:[{code,statement}],missions:[{mission_code,title,verified,runs,best_seconds}]}]}]}`.
- `public.manage_curriculum_content(p_actor uuid, p_action text, p_payload jsonb) returns jsonb` service-only: actions `create_topic, edit_revision, submit, evaluate(result passed|needs_revision, notes), finalize, approve, publish, unpublish, archive, complete_topic(learner)`; enforces roles/transitions from spec WS1 table; writes `content_publication_events` and `audit_events`.
- Dashboard: `/curriculum` (admin full workflow; instructor author/read) + `src/app/api/curriculum/route.ts`; learner route `src/app/api/learner/curriculum/route.ts` (`GET` projection, `POST {action:'complete_topic', topic_id}`).
- App: bottom navigation Home · Learn · Practice · Progress · Rewards; Learn = COC → modules → module detail (topics with reader + "Mark as complete", outcomes, linked quizzes/resources); Practice = COC → modules → missions with lock icon, prerequisite text, verified state, runs and best time; Progress = one projection (COC/module/topic completion, missions/runs, quiz scores, assignments, released results); Home keeps to-do/notifications/classes.

**Tasks:**
- [ ] A2.1 Unlock logic + backfill + gate. SQL tests: `backfill_keeps_existing_progress` (learner with COC1 M4 completion keeps LO1.2 unlocked); `legacy_unlocked_mission_accepts_evidence`; locked module insert denied for direct REST insert; completing LO1.1 missions + its published topics unlocks LO1.2; publishing a new LO1.1 topic does not re-lock LO1.2; COC3 unlock order LO3.2 → LO3.1 → LO3.3; bypass unlocks a locked COC's modules; existing `practice_coc_progress` keeps next COC open.
- [ ] A2.2 Publication workflow function + tests: every allowed transition; instructor cannot evaluate/approve/publish; skip (draft → published) denied; learners see only published revision; a new draft revision keeps the published one visible; events appended.
- [ ] A2.3 Learner projection + API routes + Node tests.
- [ ] A2.4 Dashboard `/curriculum` UI (module list with official text, topics, revision editor with Markdown preview, workflow buttons per role, history timeline) + browser smoke.
- [ ] A2.5 App navigation + Learn/Practice/Progress screens + `CurriculumService`; widget tests for locked/unlocked/completed states, prerequisite text, topic completion flow, large text, 320 px width.

### Slice A3 — Quiz management

**Consumes:** `curriculum_modules`, `learning_outcomes`, `curriculum_topics` (F2).
**Produces:**
- Enum value `scenario_essay` on `public.quiz_item_type`; `quiz_items.rubric jsonb` (`[{id, criterion, description, max_points}]`), `quiz_items.points numeric`; `quizzes` adds `focus text, quiz_type text ('pre_assessment','formative','summative'), difficulty text ('foundation','intermediate','advanced'), topic_id uuid`; `quiz_modules(quiz_id, module_id)`, `quiz_learning_outcomes(quiz_id, outcome_id)`; `quiz_versions` adds `time_limit_minutes int null (1–240)`, `result_release_mode text default 'immediate'` (forced `instructor_release` when any essay exists).
- `quiz_attempts` adds `time_limit_minutes`, `auto_submitted boolean default false`, `submission_kind text ('learner','auto_deadline','auto_time_limit')`, `evaluation_status text ('not_required','pending','evaluated','finalized','released')`.
- `quiz_essay_scores(attempt_id, item_id, criterion_scores jsonb, total numeric, feedback text, evaluated_by, evaluated_at)` append-only (latest per attempt/item wins); `quiz_result_finalizations(attempt_id pk, objective_points, essay_points, total_points, max_points, percent, finalized_by/at, released_by/at)`.
- `private.quiz_attempt_effective_expiry(attempt_id) returns timestamptz` and `private.auto_submit_expired_quiz_attempts(p_assignment_id uuid default null) returns integer` (invoker, private; called from the learner RPCs, from instructor result reads and from `set_quiz_assignment_deadline` before applying a reopen/extension; skips attempts whose expiry precedes the release cutover recorded by the migration).
- Modified definer RPCs (spec Section 9) with backward-compatible signatures (new parameters have defaults).
- Dashboard: create/edit form fields; essay editor with rubric; library filters (COC, module, topic, type, status) and sort; results tab with participants, completion, average, highest, lowest, distribution chart, per-question correctness, essay status; AI grounding by module/topic/PCs and "Regenerate this question" (replace + history); "Close now".
- App: essay answer UI (multi-line, word count, autosave), countdown for timed quizzes, auto-submitted / awaiting evaluation / released states, rubric feedback on released results.

**Tasks:**
- [ ] A3.1 Schema + authoring RPCs. Tests: essay item requires rubric with ≥1 criterion and positive points; publishing a version with an essay forces `instructor_release`; existing quizzes remain valid with null module.
- [ ] A3.2 Time limit + auto-submission. Tests (controlled clock via explicit timestamps): `expiry_while_answering_auto_submits_saved_answers`; `extension_before_expiry_extends_attempt`; `reopen_after_expiry_finalizes_first`; `pre_release_expired_attempt_untouched`; save after expiry denied; one-attempt claim still holds.
- [ ] A3.3 Essay grading and release states. Tests: submission with essay → `evaluation_status='pending'`, learner result shows objective subtotal only as "awaiting evaluation"; scores within rubric bounds; finalize requires all essays scored; release makes the result visible; append-only history.
- [ ] A3.4 Dashboard authoring/library/results/AI changes + Node tests for validators and result statistics.
- [ ] A3.5 App quiz screens + widget tests (essay autosave/restore, countdown expiry, auto-submitted state, pending evaluation, released rubric feedback).

### Slice A4 — Evaluation Center (Objective 4) and homework

**Consumes:** F2 tables; A3's `quiz_result_finalizations`/`quiz_essay_scores` contract (read through A3's RPCs after merge; A4 builds against the declared shapes).
**Produces:**
- Technical attempts: `public.record_attempt_evaluation(p_actor uuid, p_attempt_id uuid, p_criterion_overrides jsonb, p_reason text, p_note text) returns jsonb` service-only (evaluated → `under_review`, instructor adjustment revision, audit); `public.finalize_attempt` requires `under_review`.
- Homework: `homework_assignments` adds `coc_module_id, module_id, mission_code, learning_objectives text[], criteria jsonb, max_score numeric default 100, submission_requirements text`; `homework_submissions` adds `criterion_scores jsonb, finalized_by/at, released_by/at`; status values `submitted, graded, finalized, released`; `manage_homework` actions `grade` (editable until finalized; score ≤ `max_score`), `finalize`, `release` (single or bulk); backfill existing graded rows to `released`.
- `public.get_evaluation_queue(p_stage text, p_filters jsonb) returns jsonb` invoker: stages `evaluate, finalize, release, released`; kinds `technical, quiz, homework`; filters `class_id, kind, coc_code, module_id, learner_id`; returns `{counts:{evaluate,finalize,release,released}, items:[{kind,id,title,learner:{id,name},class:{id,title},submitted_at,status,score,max_score,link}]}`.
- Dashboard `/evaluations` (four queues, filters, bulk finalize/release with confirmation) and `/submissions` (homework across assignments, filters class/learner/COC/mission/status/late, missing-work view); attempt detail shows Record evaluation → Finalize → Release; homework grading by criteria; grader name.
- App: homework filters (COC, mission), criteria and max score shown, score/feedback only after release.

**Tasks:**
- [ ] A4.1 Technical evaluation step + tests (cannot finalize from `evaluated`; cannot release before finalize; adjustment reason required; audit rows).
- [ ] A4.2 Homework schema/actions/backfill + tests (score > max denied; learner API hides unreleased grade; backfilled rows released; bulk release idempotent).
- [ ] A4.3 Queue function + tests (counts per stage per kind; instructor sees own classes only).
- [ ] A4.4 Dashboard pages + Node tests; A4.5 app homework changes + widget tests.

### Slice A5 — Roster import, learner search, student ID, UI fixes, app version

**Produces:**
- `profiles.learner_id_managed boolean default false`; trigger `protect_staff_managed_learner_id` (learner changing a managed value → `STUDENT_ID_STAFF_MANAGED`); partial unique index on `lower(btrim(learner_id))` for learners when no duplicates exist (migration logs and skips otherwise).
- `class_roster_entries(id, class_id, email_normalized, student_id, last_name, first_name, course_section, status ('pending','enrolled','cancelled'), import_batch_id, created_by, created_at, claimed_user_id, claimed_at)`, unique `(class_id, email_normalized)`; `roster_import_batches(...)`.
- `public.preview_class_roster(p_actor uuid, p_class_id uuid, p_rows jsonb) returns jsonb` and `public.import_class_roster(p_actor uuid, p_class_id uuid, p_rows jsonb, p_file_name text) returns jsonb` service-only. Row statuses: `enroll_now, already_enrolled, pending, conflict_student_id, staff_account, invalid`.
- `public.handle_new_user` claims pending entries (enroll, set `learner_id` if empty and mark managed, audit).
- `public.search_learners(p_query text, p_class_id uuid, p_status text, p_sort text, p_limit int, p_offset int) returns jsonb` invoker (RLS scope).
- `public.app_release_config` row (`min_supported_version`) readable by all authenticated users; app checks at startup.
- Dashboard `/classes/[id]/import` (template `.xlsx` download, upload `.xlsx/.xls` ≤ 2 MB and ≤ 1000 rows, server parse with SheetJS 0.20.3, preview, confirm, summary, error report CSV); search/filter/sort/pagination on `/learners`, `/users`, `/progress`; UI fixes from spec WS0.

**Tasks:**
- [ ] A5.1 Student ID + version config + tests (`unchanged_learner_id_update_allowed`, changed managed value denied, admin can change it).
- [ ] A5.2 Roster preview/import/claim + tests (all row statuses; duplicates within file; idempotent re-import; sign-up with a pending email enrolls; staff email never enrolled) and Node parser tests (header variants, blank rows, `.xls`, extra columns, mixed-case emails, oversized file).
- [ ] A5.3 Search function + pages + tests; A5.4 UI fixes; A5.5 app student ID read-only + version check + widget tests.

### Slice A6 — Gamification (Objective 2)

**Produces:**
- `gamification_point_rules(event_type text pk, points int, label text, active boolean)` seeded: `practice_mission_verified 50`, `topic_completed 10`, `module_completed 100`, `coc_completed 300`, `quiz_submitted 20`, `homework_submitted_on_time 15`, `assessment_released 40`.
- `learner_point_events(id, learner_id, event_type, source_id text, points, awarded_at)` unique `(learner_id, event_type, source_id)`; triggers (invoker) on the source tables award exactly once; migration backfills from existing records.
- `gamification_levels(level int pk, min_points int, title text)` (1 Trainee 0, 2 Apprentice 100, 3 Junior Technician 300, 4 Technician 600, 5 Senior Technician 1000, 6 Lead Technician 1500); `achievements(code pk, title, description, rule jsonb)` + `learner_achievements(learner_id, code, earned_at)`; rewards = level titles and achievement badges.
- `public.get_learner_rewards() returns jsonb` invoker: `{points, level:{level,title,min_points,next_min_points}, achievements:[{code,title,description,earned_at|null}], recent:[{event_type,label,points,awarded_at}], leaderboard:[{rank,display_name,points,is_me}]}` (leaderboard = learners sharing an active class with the caller, opt-in flag `profiles.show_on_leaderboard default false`, caller always included).
- App Rewards tab: points, level progress bar, achievements grid (earned/locked), recent points, opt-in leaderboard toggle.

**Tasks:**
- [ ] A6.1 Schema, triggers, backfill + tests (award once on duplicate events; backfill counts equal source records; learner cannot insert points; levels computed from thresholds).
- [ ] A6.2 Rewards RPC + tests (leaderboard excludes non-opted learners except self; no cross-class leakage).
- [ ] A6.3 App Rewards screen + widget tests (empty state, earned/locked achievements, level progress, toggle).

---

## Wave 2 — Analytics (Agent A7, after Wave 1 merges)

**Consumes:** all Wave 1 tables.
**Produces:** invoker RPCs with shared filter object `{class_id, coc_code, module_id, topic_id, mission_code, quiz_id, learner_id, from, to}` validated server-side: `get_analytics_overview`, `get_class_performance`, `get_learner_performance`, `get_learner_profile_analytics(p_learner uuid, p_filters jsonb)`, `get_quiz_analytics(p_quiz_id uuid, p_filters jsonb)`, `get_mission_analytics`, `get_criteria_analytics`, and learner-facing `get_my_performance()`; documented metric definitions (`docs/ANALYTICS_METRIC_DEFINITIONS.md`); dashboard pages under `/analytics` (Overview, Classes, Learners, Quizzes, Missions, Criteria) with recharts, tables, filters and CSV export; Realtime refresh (instructor classes' attempts, quiz attempts, homework, practice runs) with 30 s polling fallback; app Progress "Performance" section with the same refresh.

- [ ] A7.1 RPCs + fixture-based accuracy tests (zero data, pending evaluations excluded from averages, learner in two classes counted once per population, unpublished quizzes excluded, instructor cannot read other classes).
- [ ] A7.2 Dashboard pages + Node tests; A7.3 app performance view + widget tests.

---

## Wave 3 — Integration, demo data and report (coordinator)

- [ ] C1 Merge slices in order F → A1 → A2 → A3 → A4 → A5 → A6 → A7, resolving shared-file conflicts; regenerate `database.generated.ts` from the local database.
- [ ] C2 `scripts/seed-demo-class.mjs`: idempotent labelled class "DEMO – Re-defense" with synthetic learners driving real activities through the APIs/RPCs (practice runs incl. mistakes, assessments evaluated/finalized/released, quizzes with essays, homework graded/released, topics completed); refuses non-local targets unless `--target hosted --confirm` is passed during the approved rollout.
- [ ] C3 Full gates: Flutter analyzer, full Flutter suite (Docker), debug APK, `tsc`, lint, `pnpm test`, `next build`, every SQL suite; browser smoke of every new dashboard page at 320/768/1440 px.
- [ ] C4 Final report `docs/REDEFENSE_IMPLEMENTATION_REPORT_2026-11-23.md` (audit → revisions → verification classification → tests → remaining → re-defense checklist) and `CODEX_STATE.md` update; commit.
- [ ] C5 Hosted rollout package for owner approval (backup, rehearsal, ordered migrations, Vercel, APK, demo data, smoke tests).
- [ ] C6 WS9 (new 2D simulations for distinct legacy tasks: LO4.2 preventive maintenance, COC2 LAN-tester diagnosis, LO1.3, LO2.3) starts only after C3 is green; whatever is not finished before the rollout is reported as remaining, with the form-based assessment still assignable and linked to its module.
