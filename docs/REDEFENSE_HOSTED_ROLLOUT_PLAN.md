# Re-Defense Hosted Rollout Plan

**Status:** awaiting owner approval. Nothing in this document has been run against hosted services.
**Target:** hosted Supabase project `rslmteqipxqfifwftugk` (ByteQuest), Vercel production `bytequest-alpha.vercel.app`, learner APK 1.2.0+3.
**Source:** `vince-branch` after the final fix wave (WEB, SQL and FLUTTER fixers merged, local gates green).
**Shell:** commands are for PowerShell on the release machine, run from the repository root.

## Why a targeted rollout

The hosted migration history differs from the repository history: hosted records an honest batch entry `20261111160000` and the seven 2026-11-13 versions instead of every repository file. `supabase db push`, `--include-all` and `migration repair` are therefore never used, because they would try to replay historical migrations.

Only the re-defense migrations are applied: **every migration version ≥ `20261119100000`** in `supabase/migrations`. At the time of writing that is 39 files from `20261119100000` to `20261119180000`, including `20261119170500_analytics_redefense_final_sources` and `20261119180000_instructor_assignable_rubric_visibility`, plus the final-fix migrations `202611201xxxxx` (`20261120100000`–`20261120100300` on the SQL fix branch). The exact list is whatever `scripts/release-migration-batches.mjs` writes into the release manifest at step 1; nobody types it by hand.

### Two transactions, not one

Every migration file has its own `begin;`/`commit;`. Sent as one script they would commit one by one, so a failure part-way would leave production half-migrated. Stripped into one transaction they cannot run either: `20261119130100` uses the enum value that `20261119130000` adds, and PostgreSQL refuses a new enum value inside the transaction that adds it (SQLSTATE 55P04). The release is therefore applied as two batches:

| Batch | Contents | Transaction | If it fails |
|---|---|---|---|
| A | every migration that adds enum values (`ALTER TYPE … ADD VALUE`), detected from the SQL. Today that is only `20261119130000_quiz_scenario_essay_item_type`. | One transaction, committed first. Every statement is `ADD VALUE IF NOT EXISTS` and the version rows use `ON CONFLICT DO NOTHING`, so Batch A is idempotent. An enum value left behind is harmless. | Nothing else has changed. Retry Batch A. |
| B | every other migration, in timestamp order. | ONE transaction. Each file's own top-level `BEGIN;`/`COMMIT;` is removed, and the tool checks mechanically that nothing else in the file changes. `lock_timeout = 5s` and `statement_timeout = 120s` are reset before each file, so a file's own `SET LOCAL` governs only that file. Each version row is inserted inside the same transaction. A guard refuses to run if Batch A is not recorded or if any Batch B version is already recorded. | PostgreSQL rolls the whole batch back. Batch A stays applied, which is harmless. Fix the cause and retry Batch B only. |

The rehearsal applies exactly these two files; production receives the same files, byte for byte. Their SHA-256 digests are in the manifest.

## Learners must install 1.2.0: the old app is not prompted

The installed 1.1.0 APK has no version gate. It never reads `app_release_config`, so it cannot prompt anyone to update. From step 4 on, the server protects the records instead:

- **The server refuses unsupported starts.** A client that does not send `x-bytequest-app-version` ≥ `app_release_config.min_supported_app_version` (1.2.0) cannot start a simulation-assessment attempt or an essay quiz. The start fails with `APP_UPDATE_REQUIRED: …` before anything is consumed or recorded. 1.2.0 sends the header on every request.
- **What 1.1.0 can no longer do correctly** after step 4:
  - It cannot answer essay questions.
  - It shows results that are still awaiting evaluation as "0 / N correct".
  - It does not show quiz time limits.
  - It cannot complete published lessons, so a module with a lesson never completes for that learner.
  - It cannot verify COC1 M2 practice (contract v3).
- **Evidence from a foreign definition version is not trusted.** If a simulation-assessment attempt holds evidence recorded with a definition version other than the package's, its criteria are marked `requires_review` for the instructor, not satisfied or failed automatically.

So, as a precondition:

1. Before step 4, tell every learner out of band (class group chat, in class) to install 1.2.0, and post a notification with the APK link. 1.1.0 renders notifications.
2. Instructors do not assign simulation assessments, essay quizzes, instructor-release or timed quizzes, and do not publish lessons, until their learners have confirmed 1.2.0.
3. An attempt affected anyway is handled by the instructor: override with a reason during Evaluate, or allow a retry.

## Maintenance window (steps 4–6)

- Announce a short window. Learners are told not to submit anything; instructors and admins take no dashboard action.
- The old dashboard misbehaves against the new schema (for example Finalize now needs the Evaluate step), so deploy the new dashboard (step 6) right after the read-back (step 5).
- **Release results before archiving a class.** Archived classes' unreleased items are hidden from the Evaluation Center's action stages, and the product has no unarchive path.

## Steps

| # | Step | Command / method | Stop condition |
|---|---|---|---|
| 1 | Freeze source and build the release | `git rev-parse HEAD` on `vince-branch`, all local gates green: SQL suites on a freshly migrated local stack (`node scripts/local-qa-fixtures.mjs`, then `node scripts/run-local-sql-tests.mjs`), the Flutter suite and analyzer, dashboard `tsc`/`lint`/`test`/`build`. Then `node scripts/publish-simulation-assessments.mjs --dry-run` (runs the scoring assertions) and `node scripts/release-migration-batches.mjs --out .tmp/release-redefense`. Keep `.tmp/release-redefense/manifest.json`: it lists every version ≥ `20261119100000` and the SHA-256 of `batch-a.sql` and `batch-b.sql`. | Any red gate, any refused migration file, or a manifest whose version list is not every repository version ≥ `20261119100000`. |
| 2 | Fresh backup of hosted (**manual**) | An encrypted logical backup in the 2026-11-13 recovery format (`CODEX_STATE.md`, "PASS fresh backup/restore"), made with the logged-in Supabase CLI and a read-only login role. Store it owner-only under `%LOCALAPPDATA%\ByteQuest\Recovery\rslmteqipxqfifwftugk-<date>-redefense`. The restore script expects these files: `archive-key.dpapi`, `backup-manifest.json` (`recovery_verified: false`), the `*.dump.bqenc` database archive, `roles.sql.bqenc` and `snapshot-digests.json.bqenc`. No repository script creates this backup. | Dump fails, or the digests cannot be computed. |
| 3 | Isolated restore rehearsal | 1. `node scripts/rehearse-production-release.mjs --release=redefense --attempt=1 "--backup-dir=$env:LOCALAPPDATA\ByteQuest\Recovery\rslmteqipxqfifwftugk-<date>-redefense" --keep-running`. This restores into the network-disabled, read-only, tmpfs container `bytequest-recovery-rslm-redefense-release-1` on the pinned Postgres 17.6 image and verifies every relation's count and hash. 2. `node scripts/rehearse-release-batches.mjs --artifacts .tmp/release-redefense --container bytequest-recovery-rslm-redefense-release-1 --with-suites --evidence "<backup dir>\batch-rehearsal-attempt1.json"`. This applies Batch A, then Batch B, as `postgres` (the role the Management API uses). It then compares every pre-existing row's pre-existing columns with the documented changes below, runs `scripts/release-readback.sql`, loads `supabase/tests/fixtures/qa_fixture_users.sql` (the `qa.*` users, because the container has no Auth API) and runs every rollback suite on the migrated copy. 3. `docker stop bytequest-recovery-rslm-redefense-release-1`: the tmpfs holds the plaintext copy. | Any batch error; Batch B slower than 30 s; any pre-existing row change outside the documented list, or any deleted row; a read-back mismatch; any failed suite or plan mismatch. A failure here means production is not touched. |
| 4 | Apply to hosted (maintenance window) | First check that `Get-FileHash .tmp\release-redefense\batch-a.sql, .tmp\release-redefense\batch-b.sql -Algorithm SHA256` equals the manifest and the step-3 evidence. If the repository is not linked yet, run `supabase link --project-ref rslmteqipxqfifwftugk`. Then `supabase db query --linked -f .tmp/release-redefense/batch-a.sql`, and only when it succeeds, `supabase db query --linked -f .tmp/release-redefense/batch-b.sql`. | Batch A error: retry Batch A. Batch B error: it rolled back automatically, and Batch A stays (harmless). Record the error, fix forward (a new migration, regenerated artifacts, step 3 again), then retry Batch B. Never split Batch B. If the CLI or the API refuses the request size (Batch B is about 0.8 MB), stop and ask the owner for a direct connection (`supabase db query --db-url …`), rather than splitting it. |
| 5 | Read-back verification | `supabase db query --linked -f scripts/release-readback.sql`. Expect: `redefense_versions` equal to the manifest's version list, which is every version ≥ `20261119100000`, including `20261119170500`, `20261119180000` and the `202611201xxxxx` fixes; `public_tables_without_rls` empty; `practice_contracts` 20 with `coc1_m2_contract_version` `css-assembly-20261119-v3`; `curriculum_modules` 16; `performance_criteria` 76; `mission_curriculum_links` 20; `min_supported_app_version` `1.2.0`; `scenario_essay_enum` true. | Any mismatch: corrective migration, or restore from the step-2 backup. |
| 6 | Dashboard deploy | Build the exact commit and deploy it to Vercel production. This needs a Vercel login with access to the `bytequest` project. The build fetches SheetJS from `cdn.sheetjs.com` (`ByteQuest-Web-Dashboard/package.json`), so check that the CDN is reachable. Smoke-test: login, curriculum, quizzes, evaluations, analytics, roster import pages. | Build or smoke failure: keep the previous production deployment (Vercel instant rollback). |
| 7 | Learner APK | `flutter build apk --debug` with the production defines (`BQ_SUPABASE_URL`, the publishable key, `BQ_PRACTICE_API_URL=https://bytequest-alpha.vercel.app/api/learner/practice`), version 1.2.0+3, then a secret scan of the APK. The APK is debug-signed (no release signing key on this machine). Distribute it with the step-4 notice. | Secret scan hit or build failure. |
| 8 | Simulation assessments | Only after learners are on 1.2.0. With `$env:NEXT_PUBLIC_SUPABASE_URL='https://rslmteqipxqfifwftugk.supabase.co'`, `$env:NEXT_PUBLIC_SUPABASE_ANON_KEY='<publishable key>'`, `$env:SUPABASE_SERVICE_ROLE_KEY='<service role key>'` and `$env:BYTEQUEST_E2E_PASSWORD='<one-time password>'`: first `node scripts/publish-simulation-assessments.mjs --target hosted --confirm --dry-run`, which must report `"drift": []`; then `node scripts/publish-simulation-assessments.mjs --target hosted --confirm`. The 20 packages are immutable once published. Safety-critical steps (ESD, PPE, power isolation, CPU orientation) allow no incorrect attempt, and failed final verification tests charge the step that owns the faulty state. | Script error, a non-empty drift list, or a failed scoring assertion. |
| 9 | Demo class | `$env:BYTEQUEST_DEMO_WEB_URL='https://bytequest-alpha.vercel.app'`, `$env:BYTEQUEST_DEMO_INSTRUCTOR_PASSWORD='<demo instructor password>'`, `$env:BYTEQUEST_DEMO_ADMIN_PASSWORD='<admin password>'`, plus the three Supabase variables of step 8. Then `node scripts/seed-demo-class.mjs --target hosted --confirm --instructor-email <demo instructor email> --admin-email <admin email>`. Add `--publish-topics` to publish the first lesson; that lesson is visible to every learner, and 1.1.0 cannot complete it. Prerequisites: steps 6 and 8 done, and `.tmp/demo-practice-evidence.json` exported from the 1.2.0 build (`docs/DEMO_DATA.md`). Without step 8 the script stops before writing, unless `--publish-assessments` is given. Learner credentials go to `.tmp/demo-accounts.hosted-rslmteqipxqfifwftugk.supabase.co.json`. | Script error. |
| 10 | Live smoke test | Instructor: the Evaluation Center queues, the analytics tabs with the demo class, the roster import preview, and "Assign published content", where a simulation assessment defaults to Assessment with the "Simulation assessment" label. Learner (1.2.0 APK): Learn, Practice, Progress, COC1 M2 assembly (practice), Rewards. | Any blocking defect: fix, re-verify locally, redeploy. |

## Documented changes to pre-existing rows

The rehearsal (step 3) fails on any pre-existing row change that is not in this list, and on every deletion. Columns added by the release are not compared. New tables are not "pre-existing".

| Table | Expected change | Source |
|---|---|---|
| `public.missions` | updated titles, scenario, objective and skills | catalog title sync (`20261119100100` contract trigger) |
| `public.practice_mission_contracts` | updated rows | catalog sync touch; COC1 M2 contract v3 (`20261119110200`) |
| `public.homework_submissions` | updated rows | release backfill of already graded homework (`20261119140100`) |
| `public.audit_events` | new rows only | backfill audit records (for example `homework.release_backfill`) |
| `public.achievements` | updated and new rows | achievement catalogue upsert (`20261119160000`) |
| `public.user_achievements` | new rows only | achievement backfill (`20261119160000`) |

## What the owner must provide or approve

- Explicit approval of steps 2–9. These are production writes: migrations, deployment, demo accounts and class, simulation assessment packages.
- Vercel access on this machine (`npx vercel login` with an account that can deploy the `bytequest` project in team `vincee08s-projects`), or a teammate who can deploy the given commit.
- Approval to push `vince-branch` to `origin` (GitHub `vincee08/bytequest-project`), so the deployed commit is traceable.

## What is manual

- **Step 2, the backup.** No repository script creates the encrypted backup; it follows the 2026-11-13 procedure.
- **The learner notice and the 1.2.0 confirmation.**
- **Step 4 and the Vercel deployment.** These are run by hand with the commands above, after the owner's approval.
- **The smoke tests.**
- **The direct-connection fallback in step 4,** which needs the database password.

Everything else is a script: building and checking the batches, restoring, rehearsing, comparing data, read-back, the SQL suites, publishing and seeding.

## Rollback

- **Database.** A Batch B error rolls back automatically, and Batch A stays applied, which is harmless. If Batch B committed and a defect appears, apply a targeted corrective migration, rehearsed the same way, or restore the step-2 backup into a new project. Never make destructive changes to learner history.
- **Dashboard.** Vercel instant rollback to the previous production deployment.
- **App.** 1.1.0 keeps signing in after step 4, but the server refuses its simulation-assessment and essay-quiz starts, and the features listed above do not work in it. Learners must install 1.2.0.
