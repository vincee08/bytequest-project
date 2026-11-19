# Re-defense demo data

`scripts/seed-demo-class.mjs` creates a clearly labelled demo class whose synthetic learners perform real activities through the same API routes and RPCs the learner app and the dashboard use. Every analytics number, Evaluation Center item, point, level, achievement and unlock is computed by the server from those records. Nothing is inserted directly into result, attempt, evidence, point or completion tables.

Spec: `docs/superpowers/specs/2026-11-19-redefense-revision-design.md`, section 4, decision 6, and WS11.

## What it creates

| Item | Details |
|---|---|
| Class | **DEMO – Re-defense (synthetic learners)**, class code `DEMO-REDEF`, owned by the demo instructor. |
| Learners | Twelve synthetic learners with the surname **Demo**: Alex, Bea, Cris, Dani, Eli, Fran, Gale, Hal, Iya, Jules, Kai and Lou Demo (learners 01–12 in that order). These are invented names, not project members. The leaderboard shows "First name L.", so they appear as "Alex D.", "Bea D." and so on: distinct, and still obviously demo data. Emails are `demo.learner01..12@bytequest.invalid` and student IDs `DEMO-RD-01..12`. Each account signs up through Supabase Auth as the app does. The instructor imports an Excel roster through the dashboard (`/api/roster/template`, `/preview`, `/import`). Learners 01–08 already have accounts and enroll immediately. Learners 09–12 are pending entries that enroll automatically when they sign up ("Joined via roster"). Credentials go only to a gitignored store per target: `.tmp/demo-accounts.local.json` for the local stack and `.tmp/demo-accounts.hosted-<host>.json` for a hosted project, so a hosted run never reuses local passwords or user ids. An earlier `.tmp/demo-accounts.json` is adopted only by the target it was written for. Like the 1.2.0 app, the synthetic learners send `x-bytequest-app-version` on every request. |
| Lessons (LO1.1) | **DEMO · ESD precautions at the workbench** and **DEMO · Handling and seating components**. These are accurate, generic CSS NC II content, visible to every learner once published. The instructor drafts and submits each lesson; the admin evaluates it; the instructor finalizes it; the admin approves it. The first lesson is then published. The second stays **approved**, so an admin can publish it live during the defense. |
| Practice | The typed work orders exported from the app (`tool/export_practice_test_evidence.dart`), the same action generators as `scripts/test-practice-api-all-missions.mjs`. They are written to `practice_mission_actions` with each learner's own token and verified through `/api/learner/practice`. Some runs include realistic mistakes: a CPU placed in the wrong orientation, memory seated in DIMM_A1 and then reseated, or the screwdriver used on the ESD ground point. Some learners press Verify too early, which records a failed verification. One learner completes all of COC1 and passes the COC1 practice quiz. Two learners barely start. |
| Simulation assessment | **DEMO · COC1 M2 assembly assessment** (the published simulation package, 2 attempts, retry after 1 hour). It is assigned exactly as the dashboard's "Assign published content" form does it. First the instructor's own session reads the approved rubric that matches the package (row-level security). Then the instructor calls `assign_activity`, with no availability window or due date, like the form. Seven learners submit through `start_attempt` / `append_attempt_action` / `submit_attempt`: perfect runs, two CPU orientation errors (fails the safety-critical C3), three memory reseats (exceeds the C5 threshold) and an unfinished submission. The instructor records evaluations, finalizes and releases through `/api/evaluations`, so every Evaluation Center stage has items. |
| Quiz | **DEMO · Assembly safety check**. COC1 / LO1.1, PCs 1.1 and 1.4, with focus text, a 15-minute limit and instructor release. It has three multiple-choice items, two true/false items and one scenario essay with a 10-point rubric. Every question is approved before publication. Nine learners submit. Essays are scored through `/api/quizzes/evaluation`, then finalized and released through `/api/evaluations`, at different stages. One learner starts, saves three answers and leaves; the server submits the attempt automatically when the time limit ends. |
| Homework | **DEMO · Document a safe assembly checklist**. Linked to COC1 M2, with two criteria (10 + 10, max 20) and a deadline 4 minutes after creation. It has on-time, late (after the deadline) and missing submissions, graded, finalized and released at different stages. |
| Gamification | Follows automatically from these events. Learners 01, 02, 03 and 05 opt into the class leaderboard from their own profile. |

The activity mix is designed so that learner statuses differ:

- Most learners are on track: Alex, Bea, Cris, Dani, Eli, Iya and Jules.
- Three are struggling, for three different reasons:
  - Fran's released quiz average is below 75 %;
  - Gale has three failed verifications on one mission;
  - Hal has a released "not yet competent" result.
- Two are falling behind: Kai and Lou. Their progress is below half the class median.

The analytics RPCs compute the actual statuses from the records, and each run's summary prints them. `--summary-only` recomputes them, for example after an analytics change.

## Run it locally

Prerequisites:

1. The local Supabase stack is running and fully migrated. The assignment step needs `20261119180000_instructor_assignable_rubric_visibility.sql`: without it the instructor cannot read the approved rubric of a centrally published package, and the script stops with that message, as the dashboard form would.
2. The QA fixtures exist: `node scripts/local-qa-fixtures.mjs`. The script uses `qa.instructor@bytequest.local` and `qa.admin@bytequest.local` from `.tmp/local-qa-accounts.json`.
3. Root dependencies are installed (`corepack pnpm install --frozen-lockfile`).
4. The dashboard is running against the local stack at `http://127.0.0.1:3000`: `corepack pnpm build` and `corepack pnpm start -p 3000` (or `pnpm dev`) in `ByteQuest-Web-Dashboard`, with a gitignored `.env.local` holding the local keys.
5. The simulation assessments are published. Locally, when the COC1 M2 package is missing, the seed script runs `node scripts/publish-simulation-assessments.mjs` itself. The publisher is idempotent, and its temporary governance principal gets a one-time password. It refuses a database that already holds a different package for the same contract version, because published versions are immutable; start from a fresh reset in that case.
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
- learners by email. A seeded learner whose profile name differs from the list above is renamed. The learner updates their own `full_name`, as the app's Edit profile screen does, and the server refreshes the leaderboard entry. Accounts seeded as "Demo Learner NN" by an earlier version of the script are renamed this way;
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
  --instructor-email <demo instructor> --admin-email <admin> [--publish-topics] [--publish-assessments]
```

- Without `--target hosted --confirm --instructor-email <email>` the script refuses to run.
- Both URLs must be `https`.
- Prerequisites on hosted:
  - the rollout's migrations are applied (`docs/REDEFENSE_HOSTED_ROLLOUT_PLAN.md`);
  - the 20 simulation assessments are published (rollout step 8);
  - the work orders are exported from the 1.2.0 app build.
- **Publishing the simulation assessments is an explicit opt-in.** If they are not published, the script stops before writing anything, unless you pass `--publish-assessments`. With that flag it runs `node scripts/publish-simulation-assessments.mjs --target hosted --confirm` itself, which writes 20 production packages (not demo-labelled) and a temporary governance principal.
- **Real learners must install 1.2.0. The installed 1.1.0 app is not prompted to update.**
  - The server refuses simulation-assessment and essay-quiz starts from a client that does not send `x-bytequest-app-version` ≥ `app_release_config.min_supported_app_version` (`APP_UPDATE_REQUIRED`).
  - 1.1.0 also cannot answer essays, shows pending results as "0 / N", shows no time limits, cannot complete published lessons and cannot verify COC1 M2 v3.
  - Simulation-assessment evidence recorded with a foreign definition version is flagged `requires_review` for the instructor.
- Learner credentials go to `.tmp/demo-accounts.hosted-<host>.json`.
- **Lessons are visible to every learner.** On hosted, the first lesson is published only with `--publish-topics`. Without it, both lessons stop at **approved**.
- Never put the service-role key or the passwords into a file in the repository.

## Remove it

```
node scripts/seed-demo-class.mjs --remove [--archive-topics]
```

The same target flags apply (`--target hosted --confirm --instructor-email … --admin-email …`).

**Release results before archiving.** Once the class is archived, its unreleased quiz, homework and technical results are hidden from the Evaluation Center's action stages, and the product has no unarchive path. Finalize and release every demo item first, or decide on purpose to leave it unreleased.

What it does:

- The instructor deactivates the twelve demo learners (`instructor_deactivate_learner_account`).
- The instructor archives the demo quiz and the class.
- With `--archive-topics`, the admin also archives the two demo lessons. Lessons are curriculum content every learner sees, so archiving one changes the required items of every learner's LO1.1: a learner who verified both LO1.1 missions but skipped the lesson completes the module at that moment. This is why lesson archiving is opt-in.

No history is deleted. Attempts, results, evidence, points and audit events stay, as required for append-only records. A removed demo is not re-seeded: the script refuses an archived class or deactivated demo learners.

## Effect on the rollback SQL suites

None. The demo data can stay in the database while the suites in `supabase/tests` run: every suite passes with or without it. Eight suites used to depend on the database having no other curriculum content, classes or notifications. Each of them now isolates itself inside its own rolled-back transaction, and every assertion is unchanged:

| Isolation (inside the suite's transaction) | Suites |
|---|---|
| Topics that already exist are archived before the fixtures run. Published lessons are required items of every learner, so only the suite's own fixture topics count. | `module_progression_projection_rollback.sql`, `module_progression_rollback.sql`, `gamification_rollback.sql`, `coc1_m1_identification_rollback.sql`, `simulation_coc1_m2_contract_rollback.sql`, and already `analytics_redefense_rollback.sql` |
| The admin overview population is recorded before the fixture classes exist. The fixtures must add exactly their own 5 learners to it. | `analytics_redefense_rollback.sql` |
| The expected admin Evaluate count also counts the quiz attempts that already await essay scores, as the queue lists them. | `evaluation_center_queue_rollback.sql` |
| Notifications that existed before the transaction are excluded from the release-notification check. | `homework_redefense_rollback.sql` |

`node scripts/run-local-sql-tests.mjs` (all 39 suites) passes in three places: on the seeded main database, on a clone of it, and on a database built from the migrations alone with only the QA fixtures.

## Notes

- The synthetic learners answer quiz items from the authored answer key and the COC1 practice quiz from the server's stored key. The service role only reads that key; the server grades every submission.
- Client timestamps are the real times at which the script sends each action. Practice and assessment durations are therefore short; they are genuine records of synthetic learners.
- The service role is used for three things only:
  - account administration, as the dashboard also does it: email confirmation on hosted, and a password reset when `.tmp/demo-accounts.json` was lost;
  - running the simulation publisher;
  - read-only lookups and the summary counts.
- The assessment is assigned through the instructor's own session only. Migration `20261119180000` lets active instructors read the approved rubrics of published activities. The dashboard form and the script both depend on it.
