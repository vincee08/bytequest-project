# Re-defense demo data

`scripts/seed-demo-class.mjs` creates a clearly labelled demo class whose synthetic learners perform real activities through the same API routes and RPCs the learner app and the dashboard use. Every analytics number, Evaluation Center item, point, level, achievement and unlock is computed by the server from those records. Nothing is inserted directly into result, attempt, evidence, point or completion tables.

Spec: `docs/superpowers/specs/2026-11-19-redefense-revision-design.md`, section 4, decision 6, and WS11.

## What it creates

| Item | Details |
|---|---|
| Class | **DEMO – Re-defense (synthetic learners)**, class code `DEMO-REDEF`, owned by the demo instructor. |
| Learners | **Demo Learner 01 … 12**, `demo.learner01..12@bytequest.invalid`, student IDs `DEMO-RD-01..12`. Each account signs up through Supabase Auth as the app does. The instructor imports an Excel roster through the dashboard (`/api/roster/template`, `/preview`, `/import`). Learners 01–08 already have accounts and enroll immediately. Learners 09–12 are pending entries that enroll automatically when they sign up ("Joined via roster"). Credentials go only to the gitignored `.tmp/demo-accounts.json`. |
| Lessons (LO1.1) | **DEMO · ESD precautions at the workbench** and **DEMO · Handling and seating components**. These are accurate, generic CSS NC II content, visible to every learner once published. The instructor drafts and submits each lesson; the admin evaluates it; the instructor finalizes it; the admin approves it. The first lesson is then published. The second stays **approved**, so an admin can publish it live during the defense. |
| Practice | The typed work orders exported from the app (`tool/export_practice_test_evidence.dart`), the same action generators as `scripts/test-practice-api-all-missions.mjs`. They are written to `practice_mission_actions` with each learner's own token and verified through `/api/learner/practice`. Some runs include realistic mistakes: a CPU placed in the wrong orientation, memory seated in DIMM_A1 and then reseated, or the screwdriver used on the ESD ground point. Some learners press Verify too early, which records a failed verification. One learner completes all of COC1 and passes the COC1 practice quiz. Two learners barely start. |
| Simulation assessment | **DEMO · COC1 M2 assembly assessment** (the published simulation package, 2 attempts, retry after 1 hour). Seven learners submit through `start_attempt` / `append_attempt_action` / `submit_attempt`: perfect runs, two CPU orientation errors (fails the safety-critical C3), three memory reseats (exceeds the C5 threshold) and an unfinished submission. The instructor records evaluations, finalizes and releases through `/api/evaluations`, so every Evaluation Center stage has items. |
| Quiz | **DEMO · Assembly safety check**. COC1 / LO1.1, PCs 1.1 and 1.4, with focus text, a 15-minute limit and instructor release. It has three multiple-choice items, two true/false items and one scenario essay with a 10-point rubric. Every question is approved before publication. Nine learners submit. Essays are scored through `/api/quizzes/evaluation`, then finalized and released through `/api/evaluations`, at different stages. One learner starts, saves three answers and leaves; the server submits the attempt automatically when the time limit ends. |
| Homework | **DEMO · Document a safe assembly checklist**. Linked to COC1 M2, with two criteria (10 + 10, max 20) and a deadline 4 minutes after creation. It has on-time, late (after the deadline) and missing submissions, graded, finalized and released at different stages. |
| Gamification | Follows automatically from these events. Learners 01, 02, 03 and 05 opt into the class leaderboard from their own profile. |

The activity mix is designed so that learner statuses differ:

- Most learners are on track.
- Three are struggling, for three different reasons: a quiz average below 75 %, a released "not yet competent" result, and three failed verifications on one mission.
- Two are falling behind: their progress is below half the class median.

The analytics RPCs compute the actual statuses from the records, and each run's summary prints them. `--summary-only` recomputes them, for example after an analytics change.

## Run it locally

Prerequisites:

1. The local Supabase stack is running and fully migrated.
2. The QA fixtures exist: `node scripts/local-qa-fixtures.mjs`. The script uses `qa.instructor@bytequest.local` and `qa.admin@bytequest.local` from `.tmp/local-qa-accounts.json`.
3. Root dependencies are installed (`corepack pnpm install --frozen-lockfile`).
4. The dashboard is running against the local stack at `http://127.0.0.1:3000`: `corepack pnpm build` and `corepack pnpm start -p 3000` (or `pnpm dev`) in `ByteQuest-Web-Dashboard`, with a gitignored `.env.local` holding the local keys.
5. The simulation assessments are published. When the COC1 M2 package is missing, the seed script runs `node scripts/publish-simulation-assessments.mjs` itself for the same target. The publisher is idempotent, and its temporary governance principal gets a one-time password.
6. The practice work orders are exported to `.tmp/demo-practice-evidence.json`:
   - Natively: `cd ByteQuest-Mobile-App && flutter pub get && dart run tool/export_practice_test_evidence.dart ../.tmp/demo-practice-evidence.json`. When `ByteQuest-Mobile-App/.dart_tool` already exists, the seed script runs this export itself.
   - Or inside the Flutter container (`ghcr.io/cirruslabs/flutter:3.44.0`): mount the app read-only and copy it, then run `flutter pub get` and the same `dart run` command, writing to a mounted output folder.

   The script checks the work orders against the published practice contracts and stops if they drifted.

Then, from the repository root:

```
node scripts/seed-demo-class.mjs
node scripts/seed-demo-class.mjs --summary-only
```

The first command seeds. It takes about 5 minutes, including the wait for the homework deadline. The second only prints the summary.

The target is printed before anything is written. The script refuses any Supabase URL other than `http://127.0.0.1:57321` and any non-local dashboard URL. Pass `--qa-accounts <file>` if the QA credentials live elsewhere, and `--pace-ms <ms>` to change the pause between learner actions (default 150 ms).

**Idempotent:** a re-run looks everything up and skips what exists:

- the class by code `DEMO-REDEF`;
- learners by email;
- lessons by title;
- the quiz, homework and assessment by their `DEMO ·` titles;
- attempts, submissions, completions and topic progress per learner.

It only moves items forward to their planned stage. Each run writes the counts per record type, the Evaluation Center stage counts, the analytics overview JSON, the learner statuses and the rewards to `.tmp/demo-seed-summary.json`.

## Run it on the hosted project (approved rollout only)

```
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co \
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key> \
SUPABASE_SERVICE_ROLE_KEY=<service role key> \
BYTEQUEST_DEMO_WEB_URL=https://<dashboard> \
BYTEQUEST_DEMO_INSTRUCTOR_PASSWORD=<password> \
BYTEQUEST_DEMO_ADMIN_PASSWORD=<password> \
node scripts/seed-demo-class.mjs --target hosted --confirm \
  --instructor-email <demo instructor> --admin-email <admin> [--publish-topics]
```

- Without `--target hosted --confirm --instructor-email <email>` the script refuses to run.
- Both URLs must be `https`.
- Prerequisites on hosted:
  - the rollout's migrations are applied;
  - the new app version is installed (the assessment requires its contract version);
  - the work orders are exported from the same app build.
- If the simulation assessments are not published yet, the seed script runs `node scripts/publish-simulation-assessments.mjs --target hosted --confirm` itself.
- **Lessons are visible to every learner.** On hosted, the first lesson is published only with `--publish-topics`. Without it, both lessons stop at **approved**.
- Never put the service-role key or the passwords into a file in the repository.

## Remove it

```
node scripts/seed-demo-class.mjs --remove [--archive-topics]
```

The same target flags apply (`--target hosted --confirm --instructor-email … --admin-email …`).

What it does:

- The instructor deactivates the twelve demo learners (`instructor_deactivate_learner_account`).
- The instructor archives the demo quiz and the class.
- With `--archive-topics`, the admin also archives the two demo lessons. Lessons are curriculum content every learner sees, so archiving one changes the required items of every learner's LO1.1: a learner who verified both LO1.1 missions but skipped the lesson completes the module at that moment. This is why lesson archiving is opt-in.

No history is deleted. Attempts, results, evidence, points and audit events stay, as required for append-only records. A removed demo is not re-seeded: the script refuses an archived class or deactivated demo learners.

## Effect on the rollback SQL suites

The SQL suites in `supabase/tests` assume a database without other curriculum content or classes. With the demo data present, 30 of the 38 suites pass and 8 fail. Each failure was attributed on a scratch clone, and none is a product defect:

| Cause | Failing suites (assertions) |
|---|---|
| The published demo lesson is an extra required item of LO1.1 for every learner, including the suites' fixture learners. Archiving the demo lessons on the clone makes all five pass. | `module_progression_projection_rollback.sql` (11, 12, 18–20, 24–27, 29), `module_progression_rollback.sql` (23–26, 28, 30, 31), `gamification_rollback.sql` (23, 24, `PRACTICAL_COMPLETION_REQUIRED`), `coc1_m1_identification_rollback.sql` (`PRACTICAL_COMPLETION_REQUIRED`), `simulation_coc1_m2_contract_rollback.sql` (26) |
| Global count: the admin overview expects exactly the fixture's 5 enrolled learners. | `analytics_redefense_rollback.sql` (73) |
| Global count: the expected admin Evaluate count leaves out pending quiz essays. | `evaluation_center_queue_rollback.sql` (26) |
| Global count: the suite expects no `homework.released` notifications for other learners. | `homework_redefense_rollback.sql` (48) |

Run the suites on a database that has no demo data, for example a clone made before seeding (`node scripts/clone-local-db.mjs bq_<name>`), or a fresh reset with the QA fixtures. Then seed again; the script is idempotent and takes about 5 minutes.

## Notes

- The synthetic learners answer quiz items from the authored answer key and the COC1 practice quiz from the server's stored key. The service role only reads that key; the server grades every submission.
- Client timestamps are the real times at which the script sends each action. Practice and assessment durations are therefore short; they are genuine records of synthetic learners.
- The service role is used for three things only:
  - account administration, as the dashboard also does it: email confirmation on hosted, and a password reset when `.tmp/demo-accounts.json` was lost;
  - running the simulation publisher;
  - read-only lookups and the summary counts.
- The demo instructor's dashboard cannot read the approved rubric of a simulation package before it is assigned (RLS `rubric_versions_staff_select`). The script therefore resolves that rubric id with a read-only service lookup and assigns with the instructor's own `assign_activity`. See the run notes in the summary file.
