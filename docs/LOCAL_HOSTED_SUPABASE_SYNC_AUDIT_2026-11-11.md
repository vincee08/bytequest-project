# ByteQuest local versus hosted Supabase synchronization audit

**Date:** 2026-11-11

**Branch:** `vince-branch` (`dff8060` at inspection)
**Decision:** **LOCAL-ONLY CHANGES DETECTED.** The live hosted COC1 M1 practice contract is v2; the populated local and isolated QA databases use v3. Hosted migration history and several catalog objects remain unverified because the available Supabase account cannot run read-only hosted SQL. No database, deployment, environment, or Git history was changed by this audit.

## Scope and method

Read-only PostgreSQL catalog queries inspected the populated local and isolated QA databases. Hosted inspection used authenticated GET/HEAD requests to Supabase Auth, PostgREST OpenAPI and data endpoints, and Storage. The CLI's hosted read-only SQL call returned HTTP 403 (insufficient project privilege). The CLI migration-list call could not reach hosted Postgres over IPv6 and no authorized IPv4 pooler credential was available. A Vercel inspect attempt required interactive login and was stopped. These limits prevent a complete hosted migration-history, function-body, RLS, grants, trigger, index, and constraint comparison. PostgREST OpenAPI metadata is not a substitute for PostgreSQL catalogs.

The [Supabase CLI v3 change notice](https://supabase.com/changelog/supabase-cli-v3) confirms that database commands are local by default and require an explicit remote target. The [Supabase migration guide](https://supabase.com/docs/guides/deployment/database-migrations) warns that ad hoc remote schema changes can diverge from migration history. This repository's hosted history was already recorded with different timestamps in `docs/HOSTED_PRACTICE_ACTIVATION_2026-10-11.md`; those dated records are not treated as a fresh hosted migration-list result.

## A. Environment status

| Environment | Connected | Migration status | Notes |
|---|---|---|---|
| Populated local development | Yes, PostgreSQL 17.6 at `127.0.0.1:57322`; API `57321` | 52/52 repository versions recorded | `supabase_db_ByteQuest`; COC1 M1 v3 is active. This database has real local learner data. |
| Isolated QA | Yes, PostgreSQL container and API at `127.0.0.1:29453` | 52/52 files show `PASS` in QA replay log; user migration-history table absent | The isolated database's ByteQuest schema matches populated local. Its synthetic data is separate. |
| Hosted Supabase | Yes, `rslmteqipxqfifwftugk.supabase.co`; Auth, REST and Storage GET succeeded | **UNVERIFIED history**; v3 contract effect confirmed absent | Hosted SQL catalog request returned 403; direct CLI connection lacked IPv4 pooler credentials. |
| Local Next.js API | Yes, ports 3000 and 3001 respond | Not a database migration target | Anonymous practice GET returns expected 401; running process backend bindings were not independently attested. |
| Deployed Next.js API | Yes, `bytequest-alpha.vercel.app/api/learner/practice` responds 401 to anonymous GET | Deployed source version **UNVERIFIED** | Vercel CLI has no stored login. Endpoint availability does not prove current source commit or environment bindings. |
| Flutter source default | Configured | N/A | Ignored mobile `.env` points both Supabase and practice API at hosted services; `BQ_SUPABASE_URL` and `BQ_PRACTICE_API_URL` build defines override those defaults. The last recorded emulator build used local loopback overrides; no Android device is currently attached. A production release artifact/configuration was not verified. |

The ignored dashboard `.env.local` also points at the same hosted Supabase project. The local Next.js process can receive different process-only environment values, so its listening port alone does not prove its database target. No secret values or credential-bearing connection strings were printed or written here.

## B. Migration comparison

Repository files: **52**. Populated local history: **52** versions. QA replay log: **52** passes; QA has no `supabase_migrations.schema_migrations` table. Hosted history could not be read. For 49 local migrations, repository SQL and locally recorded statements match after normalizing statement separators and line endings. Two local recorded SQL bodies differ from the current files (`20261009090000`, `20261009091000`); this establishes source/history drift but does not date or explain it. Local v3 (`20261109120000`) has a version row without stored statements, so applied-source fidelity cannot be checked from history. The v3 SQL file is currently untracked.

In the table, **R** = local migration recorded, **Q** = QA replay log passed, **H?** = hosted migration-history status unknown. `Effect present` describes a live object/data observation, not proof that the same migration file or timestamp was applied. All 51 pre-v3 rows require read-only hosted history/catalog reconciliation before any write; **none should be replayed merely because its repository version is absent from hosted history**.

| Version | Migration file | Local | QA | Hosted history / observed effect | Difference | Required action |
|---|---|---|---|---|---|---|
| 20260807085500 | `20260807085500_initial_schema.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807090000 | `20260807090000_foundation_identity_and_audit.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807091000 | `20260807091000_classes_and_memberships.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807092000 | `20260807092000_tesda_and_content_versioning.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807093000 | `20260807093000_assignments_attempts_and_evidence.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807094000 | `20260807094000_gamification_resources_and_settings.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807095000 | `20260807095000_authoritative_workflow_rpcs.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807100000 | `20260807100000_evaluation_finalization_and_release.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807101000 | `20260807101000_admin_governance_rpcs.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807101500 | `20260807101500_class_and_content_management_rpcs.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807102000 | `20260807102000_authoritative_rls.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807103000 | `20260807103000_indexes_and_legacy_quarantine.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260807104000 | `20260807104000_fix_rls_policy_recursion.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260808110000 | `20260808110000_retire_merged_staff_role.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260808111000 | `20260808111000_quarantine_legacy_rating_policy.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260808112000 | `20260808112000_close_lifecycle_review_gaps.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260808112100 | `20260808112100_fix_evaluator_json_operator_precedence.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810100000 | `20260810100000_learning_resource_storage_workflow.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810101000 | `20260810101000_instructor_learner_account_deactivation.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810102000 | `20260810102000_audit_retention_safe_auth_deletion.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810103000 | `20260810103000_admin_account_removal_readiness.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810104000 | `20260810104000_security_definer_grant_hardening.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810110000 | `20260810110000_coc2_assessment_and_assignment_policy_support.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810111000 | `20260810111000_grant_activity_versions_select.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810112000 | `20260810112000_fix_extended_evaluator_json_precedence.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810113000 | `20260810113000_instructor_quiz_authoring_and_ai_drafts.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810114000 | `20260810114000_quiz_private_function_grant_hardening.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260810115000 | `20260810115000_openrouter_quiz_provider.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260811120000 | `20260811120000_scoped_analytics_and_reporting.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260812120000 | `20260812120000_learner_quiz_lifecycle.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260812130000 | `20260812130000_learner_learning_path_projection.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260812132000 | `20260812132000_learner_settings_update_grant.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260812133000 | `20260812133000_learner_settings_table_update_grant.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260814120000 | `20260814120000_scoped_realtime_publications.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260814123000 | `20260814123000_realtime_safe_quiz_scope_policies.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260822123000 | `20260822123000_neutralize_legacy_mission_scoring.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260822124500 | `20260822124500_practice_mission_evidence.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260823100000 | `20260823100000_restrict_practice_evidence_privileges.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260823110000 | `20260823110000_reload_postgrest_schema_cache.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260823120000 | `20260823120000_restore_practice_evidence_acl.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260823130000 | `20260823130000_seed_bytequest_catalog.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260824104724 | `20260824104724_restrict_handle_new_user_execute.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260824110000 | `20260824110000_restore_service_role_data_privileges.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260908120000 | `20260908120000_harden_authoritative_action_idempotency.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260915090000 | `20260915090000_validate_instructor_score_revisions.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260916090000 | `20260916090000_role_scoped_support_concerns.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20260916100000 | `20260916100000_complete_mission_grounding_catalog.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20261009090000 | `20261009090000_coc_practice_progression.sql` | R | Q | H?; practice tables/RPC visible | local recorded SQL drift | Reconcile history; no replay |
| 20261009091000 | `20261009091000_css_practice_contracts.sql` | R | Q | H?; 20 contracts visible | local recorded SQL drift | Reconcile history; no replay |
| 20261011040839 | `20261011040839_harden_practice_evidence_grants.sql` | R | Q | H? | none observed | Reconcile history; no replay |
| 20261011043723 | `20261011043723_css_drag_workspace_contracts.sql` | R | Q | H?; 15 v2 contracts visible | none observed | Reconcile history; no replay |
| 20261109120000 | `20261109120000_coc1_m1_identification_contract.sql` | R | Q | H?; **v3 effect absent** | local SQL not retained | Review targeted v3 after approval |

Live observations supporting the limited effect labels: hosted exposes practice tables and RPC names, 20 practice contracts, fifteen v2 COC1–COC3 contracts, and five v1 COC4 contracts. The v3 effect is absent because hosted COC1 M1 is still `css-sag-20261011-v2`. The older hosted report mapped four practice migration files to hosted timestamps `20261011035806`, `20261011035837`, `20261011035915`, and `20261011040956`; a later report mapped the drag migration to `20261011044331`. These mappings are historical evidence only. The hosted migration table may have changed since those reports.

## C. Mission compatibility

Every mission uses structured `practice_mission_actions` keyed by learner, mission, phase, action type, target, and JSON value; verification uses the server-side `practice_verify_mission(uuid,text)` RPC and its mission-specific JSON contract. Flutter records interactions and the Next.js practice route requests verification. Each mission has its own phases and interaction families below. The separate official assessment path uses versioned `activity_versions`, `rubric_versions`, `rubric_criteria`, `attempts`, evidence, score revisions, and instructor-controlled result release.

Live read-only comparison found exactly 20 hosted practice definitions. The 19 non-COC1-M1 definitions are structurally identical to populated local JSON, including their version strings. For official assessment, all 20 activity `learner_payload` and `evaluator_config` values matched local after canonical JSON comparison; 20 rubric versions and all 98 criterion records also matched. This checks stored contracts, not live scoring, RLS, or release behavior.

| Mission | Actual title | Interaction families / phase count | Local practice | Hosted practice | Official package | Result |
|---|---|---|---|---|---|---|
| COC1 M1 | Identify Computer Parts and Tools | inspect, select, observe, testRun / 5 | css-sag-20261109-v3 | css-sag-20261011-v2 | Payload + rubric match | **INCOMPATIBLE ? v3 absent** |
| COC1 M2 | Install Internal Components | inspect, place, sequence, testRun / 5 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC1 M3 | Install and Configure a Workstation OS | configure, sequence, testRun / 5 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC1 M4 | Connect and Configure Peripheral Devices | inspect, tool, connect, testRun / 5 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC1 M5 | Install Drivers and Test the System | troubleshoot, decide, testRun / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC2 M1 | Identify Network Devices and Tools | tool, sequence, connect, testRun / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC2 M2 | Create Network Cables | configure, sequence, connect, testRun / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC2 M3 | Construct and Verify a Network Topology | select, connect, testRun, decide / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC2 M4 | Configure Network Devices | configure, testRun, interpret / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC2 M5 | Troubleshoot Network Connectivity | troubleshoot, testRun, configure / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC3 M1 | Prepare Server Setup Requirements | inspect, decide, sequence, testRun / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC3 M2 | Install and Configure Server OS | configure, sequence, decide, testRun / 5 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC3 M3 | Manage Users, Groups, and Permissions | configure, testRun, troubleshoot / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC3 M4 | Configure and Test Server Services | inspect, configure, testRun, interpret / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC3 M5 | Test Client Access and Document Setup | troubleshoot, decide, testRun / 6 | css-sag-20261011-v2 | css-sag-20261011-v2 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC4 M1 | Identify System and Network Problems | inspect, observe, decide, testRun / 6 | css-sag-20261009-v1 | css-sag-20261009-v1 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC4 M2 | Diagnose and Repair Hardware Faults | troubleshoot, interpret, decide, testRun / 6 | css-sag-20261009-v1 | css-sag-20261009-v1 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC4 M3 | Diagnose Hardware and Software Faults | inspect, troubleshoot, interpret, testRun / 6 | css-sag-20261009-v1 | css-sag-20261009-v1 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC4 M4 | Replace and Reconfigure a Component | sequence, place, configure, testRun / 6 | css-sag-20261009-v1 | css-sag-20261009-v1 | Payload + rubric match | Contract match; hosted workflow unverified |
| COC4 M5 | Apply Repair Action and Create Report | troubleshoot, decide, testRun, observe / 6 | css-sag-20261009-v1 | css-sag-20261009-v1 | Payload + rubric match | Contract match; hosted workflow unverified |

**COC1 M1:** hosted v2 still requires placement evidence in phase 1, while the current Flutter identification flow and local v3 require seven inspection taps and tap-recorded component-role choices. The hosted/local contract JSON differs at 49 leaf paths. The v3 migration's read-only guard inputs currently match hosted: version v2, phase IDs `coc1_m1_p1` and `coc1_m1_p2`, and four v2 placement items. The migration also replaces `practice_begin_quiz` and `practice_submit_quiz` so historical v1/v2 verified COC1 M1 completions continue to count after v3. Hosted function *names and arguments* are visible, but their bodies cannot be inspected with the available access. No hosted COC1 M1 completion was present at audit time.

The shared Flutter → evidence → API → PostgreSQL path is therefore **incompatible for hosted COC1 M1 verification**. The other 19 stored practice definitions and official assessment packages match local, but end-to-end hosted mission completion and instructor release were not exercised in this read-only audit.

## D. Database differences and verification limits

**Confirmed or directly observed**

- The populated local and QA ByteQuest catalog fingerprints match: 54 relations (52 tables and two views), 356 constraints, 161 indexes, 71 non-extension public functions, 34 non-internal triggers, 60 public/storage policies, and 54 relation ACLs. QA's pgTAP extension objects were excluded from this comparison.
- Hosted PostgREST exposes all 54 ByteQuest relations with the same 662 column names and compatible OpenAPI type labels after accounting for qualified enum names and numeric default formatting. This does not verify exact numeric typmods, constraints, indexes, triggers, grants, or RLS.
- Hosted exposes all 68 non-trigger ByteQuest RPC names. Argument names match local for 67. `is_own_user(uuid)` is the exception: local uses `p_user_id`, hosted OpenAPI names the argument `target_user_id`. No current app call to this RPC was found; its function body and privileges remain unverified.
- Hosted PostgREST exposes 22 additional `td_*` relation definitions absent from this repository, plus `td_user_role`, `td_can_manage_class`, `td_create_school`, and `td_bootstrap_classroom` RPC names. It also exposes extension RPCs `show_trgm` and `show_limit`. Their PostgreSQL relation kinds, ownership, data, policies, and migration origin are unknown. Do not delete or overwrite them.
- The private `learning-resources` Storage bucket exists in both local and hosted. Its hosted Storage policy definitions and object metadata were not inspected.
- Hosted contains 37 profiles, 20 missions, 595 practice actions (297 for COC1 M1), one practice completion (COC1 M2), no COC progress rows, no practice quiz attempts, 45 official attempts, and 64 score revisions. These are read-only count snapshots, not a request to copy local data. Populated local has 48 profiles, 885 practice actions, six practice completions (two COC1 M1), 42 official attempts, and 64 score revisions; QA has synthetic records. The environments are distinct datasets.

**Unverified because hosted PostgreSQL catalog access is unavailable**

- Actual hosted `supabase_migrations.schema_migrations` contents, including hosted-only migration versions and recorded SQL statements.
- Hosted function definitions/volatility, trigger definitions, RLS enablement and policy expressions, table/function/sequence ACLs, check/unique/foreign-key definitions, indexes, exact column typmods/defaults, views, and Storage policies. PostgREST metadata and anonymous denial checks cannot certify these.
- Whether hosted-only `td_*` objects share application ownership, whether a managed full backup is available, and whether the deployed Vercel source/environment still matches the historical Oct 11 activation report.

## E. Deployment status

| Layer | Current observation | Decision |
|---|---|---|
| Flutter source | Current source includes the COC1 M1 identification flow and uncommitted learner UX changes; ignored default `.env` points to hosted, while build defines can target local. | The source's v3 COC1 M1 flow is incompatible with live hosted v2. Installed emulator/release artifact status is not a hosted deployment claim. |
| Next.js API | Repository practice route uses `practice_verify_mission`, `practice_begin_quiz`, and `practice_submit_quiz`; deployed route is reachable but exact Git SHA/environment is unknown. | Deployed compatibility **UNVERIFIED** beyond endpoint availability. |
| PostgreSQL | Local and QA v3; hosted COC1 M1 v2. Nineteen other practice definitions and all official assessment package data match. | One confirmed local-only migration effect; hosted catalog/history comparison incomplete. |
| Hosted Supabase configuration | Auth, REST, and private Storage bucket are reachable with configured keys. | Auth/RLS/Realtime settings and hosted grants are not fully certified by this audit. |
| Data migration | Local, QA, and hosted counts differ as expected for separate environments. | No learner evidence, completion, attempt, or score data should be copied as part of contract synchronization. |

## F. Proposed synchronization plan — not executed

1. Obtain project-scoped **read-only** hosted database catalog access (`database_read` Management API permission or a read-only PostgreSQL connection). Snapshot hosted migration history and catalog definitions, including the 22 hosted-only `td_*` relations. Compare every function body, RLS policy, ACL, trigger, index, constraint, Storage policy, and exact column type with the local catalog. Reconcile the known timestamp remaps and the two local recorded-SQL/source drifts. Do not run `db push` against divergent histories.
2. Establish and verify a recoverable hosted backup before any approved change. Include PostgreSQL application/auth/storage metadata and the hosted-only relations in the preservation scope. Verify restore on an isolated target. The current backup status is unknown.
3. Rehearse the **single** candidate forward migration `20261109120000_coc1_m1_identification_contract.sql` on an isolated copy with representative, de-identified hosted COC1 M1 evidence. Check the migration guard, the two quiz gate functions, grants, RLS, preserved historical evidence, in-progress learner behavior, and rollback/forward recovery. Review the source/history drift before basing any deployment on the local migration chain.
4. After explicit owner approval, arrange a controlled maintenance window and apply only the reviewed COC1 M1 forward change through the project's authorized migration process, with a hosted-specific migration-history mapping. The SQL updates one contract row and replaces two quiz functions; it does not delete or rewrite action, completion, attempt, score, or result rows. Existing in-progress v2 COC1 M1 evidence may not satisfy v3, so preserve it and plan learner recovery rather than assuming seamless continuation.
5. Verify afterward using read-only catalog/data checks: COC1 M1 version and definition v3; other 19 definitions unchanged; 20 official packages and 98 criteria unchanged; function bodies/grants/RLS correct; action/completion/attempt/score counts preserved; `td_*` objects unchanged. Separately establish the current Vercel deployment SHA and environment binding, then perform an approved authenticated learner/instructor smoke test without fabricating historical completions.

**Safety decision:** A narrow v3 forward change has a matching hosted row precondition, but it is **not yet safe to execute** without hosted catalog/history access, a verified backup/restore path, in-progress evidence rehearsal, and explicit project-owner approval. No migration or deployment was attempted in this audit.
