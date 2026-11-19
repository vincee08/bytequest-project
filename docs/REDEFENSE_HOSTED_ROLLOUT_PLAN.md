# Re-Defense Hosted Rollout Plan

**Status:** awaiting owner approval. Nothing in this document has been run against hosted services.
**Target:** hosted Supabase project `rslmteqipxqfifwftugk` (ByteQuest), Vercel production `bytequest-alpha.vercel.app`, learner APK 1.2.0+3.
**Source:** `vince-branch` after the re-defense integration (all slices merged, local gates green).

## Why a targeted rollout

The hosted migration history differs from the repository history (hosted records an honest batch entry `20261111160000` and the seven 2026-11-13 versions instead of every repository file). `supabase db push`, `--include-all` and `migration repair` are therefore never used: they would try to replay historical migrations. Only the **new re-defense migrations** (39 at the time of writing, `20261119100000` … `20261119180000`; recount at the freeze step) are applied, in timestamp order, inside one maintenance transaction, with each version recorded in `supabase_migrations.schema_migrations`.

## Steps

| # | Step | Command / method | Stop condition |
|---|---|---|---|
| 1 | Freeze source | Confirm `vince-branch` HEAD, all local gates green (SQL suites on a freshly migrated database, Flutter suite, analyzer, dashboard tsc/lint/test/build). | Any red gate. |
| 2 | Fresh backup of hosted | Logical dump of hosted (schema, data, roles, Auth/Storage metadata) with the logged-in Supabase CLI, stored owner-only under `%LOCALAPPDATA%\ByteQuest\Recovery\rslmteqipxqfifwftugk-<date>-redefense`, encrypted, with SHA-256 digests and per-table row counts. | Dump fails or digests cannot be computed. |
| 3 | Isolated restore rehearsal | Restore the dump into a new network-disabled local container on the hosted Postgres version (17.6.1). Apply the re-defense migrations in one transaction exactly as planned for production. Run the re-defense SQL suites against the restored copy and compare row counts/hashes of every pre-existing table before and after. | Any migration error, failed assertion, or any pre-existing row changed except the documented homework release backfill and catalog title sync. |
| 4 | Apply to hosted | Send the same single transaction through the authorised Supabase Management API (logged-in CLI). Record every applied version. | Transaction error → automatic rollback, production unchanged. |
| 5 | Read-back verification | Every new table has RLS; all 20 practice contracts present (COC1 M2 = `css-assembly-20261119-v3`); 16 modules / 76 performance criteria; `app_release_config.min_supported_app_version = 1.2.0`; pre-existing row counts unchanged except documented backfills. | Any mismatch → restore plan from step 2. |
| 6 | Dashboard deploy | Build the exact commit and deploy to Vercel production (requires a Vercel login with access to the `bytequest` project); smoke-test login, curriculum, quizzes, evaluations, analytics, roster import pages. | Build or smoke failure → keep the previous production deployment (Vercel instant rollback). |
| 7 | Learner APK | `flutter build apk --debug` with production defines (`BQ_SUPABASE_URL`, publishable key, `BQ_PRACTICE_API_URL=https://bytequest-alpha.vercel.app/api/learner/practice`), version 1.2.0+3; secret scan of the APK. Debug-signed (no release signing key on this machine). | Secret scan hit or build failure. |
| 8 | Simulation assessments | `node scripts/publish-simulation-assessments.mjs --target hosted --confirm` — only after the 1.2.0 APK is available, because older apps cannot run them. | Script error. |
| 9 | Demo class | `node scripts/seed-demo-class.mjs --target hosted --confirm --instructor-email <owner instructor email>`; topics published only with `--publish-topics`. | Script error. |
| 10 | Live smoke test | Instructor: Evaluation Center queues, analytics tabs with the demo class, roster import preview. Learner (APK): Learn/Practice/Progress, COC1 M2 assembly (practice), Rewards. | Any blocking defect → fix, re-verify locally, redeploy. |

## What the owner must provide or approve

- Explicit approval of steps 2–9 (production writes: migrations, deployment, demo accounts/class, simulation assessment packages).
- Vercel access on this machine (`npx vercel login` with an account that can deploy the `bytequest` project in team `vincee08s-projects`), or a teammate who can deploy the given commit.
- Approval to push `vince-branch` to `origin` (GitHub `vincee08/bytequest-project`) so the deployed commit is traceable.

## Rollback

- Database: the maintenance transaction is atomic; if it commits and a defect appears, restore from the step-2 backup into a new project or apply targeted corrective migrations (never destructive changes to learner history).
- Dashboard: Vercel instant rollback to the previous production deployment.
- App: the previous APK keeps working against the old schema only until step 4; after step 4 learners must install 1.2.0 (the version gate prompts them).
