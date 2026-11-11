# Hosted Android testing — completed backend synchronization

**READY FOR HOSTED MOBILE TESTING**

Evidence date: **2026-11-11 UTC / 2026-11-12 Manila**. Owner-led physical
testing has **not** passed or been completed. The owner will download/install
the APK; USB connection and agent installation were declined. Approved Flutter
UI/UX and all dashboard product source files remain unchanged on `vince-branch`.

## Download and owner action

- [Hosted testing APK](../ByteQuest-Mobile-App/build/app/outputs/flutter-apk/ByteQuest-hosted-testing-20261112-debug.apk)
- [Non-secret build record](../ByteQuest-Mobile-App/build/app/outputs/flutter-apk/ByteQuest-hosted-testing-20261112-debug.json)
- QA email: `bytequest.mobile.qa.20261112@bytequest.invalid`. Use the new password
  entered in the hidden local prompt. It is absent from chat, Git and the APK.
- If ByteQuest is already installed, sign out before updating and keep its data.
  Do not uninstall or clear data to resolve an installation conflict. The owner
  controls Android's installation/update prompt; no agent replacement occurred.
- Sign in with this fresh hosted QA identity, start COC1 M1, then test the 20
  missions and four quizzes in order. Record actual phone behavior/results.

## Verified hosted connectivity

| Item | Verified result | Scope / limit |
|---|---|---|
| Supabase project | **ByteQuest**, `rslmteqipxqfifwftugk`, ACTIVE_HEALTHY | Authorized project, not a local or isolated QA database |
| Supabase account/access | Correct account has organization **Owner** role | Earlier 403 was account access; authorized read-only SQL and backup listing now succeed |
| Supabase / Auth | `https://rslmteqipxqfifwftugk.supabase.co`; `/auth/v1/signup`, `/auth/v1/token?grant_type=password` | Genuine hosted signup, password sign-in and server user confirmation passed for the approved QA identity |
| Practice API | `https://bytequest-alpha.vercel.app/api/learner/practice` | Authenticated GET for a random nonexistent quiz UUID returned expected **404 Quiz not found** after learner/profile authorization and database lookup |
| Vercel team/project | `vincee08s-projects` / `bytequest`; `prj_vUXjALnNCLQWzzdScvwXMfYvppga` | Official CLI sign-in completed; no deployment performed |
| Production deployment | `dpl_CM8Kh72voepkXTVm8zWSKJZ2rZhS`, READY/production | Created 2026-10-13 08:08:45.400 UTC; production alias `bytequest-alpha.vercel.app` |
| Production Git revision | `dff80603087522c7c0a0a070464696b9237580f7` | Practice route, practice libraries and server client match the approved current source; no API update was required |
| Production binding | Expected Supabase URL confirmed through authorized Vercel environment inspection; URL record predates deployment | Runtime API accepted a newly created learner/profile existing only in the correct hosted project; this is stronger than unsigned 401 or current environment inspection alone |
| Authenticated request trace | `sin1::iad1::fw7jg-1794413794353-6dc6c216a363`, 2026-11-11 16:16 UTC | Workstation API check, **not a physical-phone request** |
| Android runtime backend | Explicit hosted build prepared; **phone runtime unverified** | Requires owner installation, actual requests and project/deployment log correlation |

The owner explicitly approved the dedicated hosted test plan. Only normal Auth
signup/sign-in/session/profile provisioning and authenticated reads ran so far.
Automated checks submitted **zero practice actions, completions or quizzes**.
The learning-path RPC returned four COC rows. No fake JWT, fabricated progress
or direct completion/result manipulation was used.

## Backup and tested recovery

Managed backup inspection succeeded: `backups=[]`, PITR disabled. The owner did
not know the existing database password. No password reset occurred. After
explicit approval, the official project-scoped temporary login endpoint issued
`cli_login_supabase_read_only_user` for **300 seconds**. Its NOINHERIT membership
allows SET ROLE to `supabase_read_only_user`; no new grants were added manually.
TLS hostname/certificate verification used the official Supabase production CAs.
See the [temporary login API](https://supabase.com/docs/reference/api/v1-create-login-role)
and [PSQL certificate guidance](https://supabase.com/docs/guides/database/psql).

- One consistent READ ONLY snapshot exported all database schemas/data, Auth,
  migration history and hosted-only objects; roles/grants were exported without
  PostgreSQL role passwords. Auth learner password hashes are retained in Auth data.
- AES-256-GCM archives and a Windows DPAPI CurrentUser-protected key reside in
  `%LOCALAPPDATA%/ByteQuest/Recovery/rslmteqipxqfifwftugk-20261111`.
  Directory inheritance is disabled; only the Windows account and SYSTEM have access.
  No plaintext database dump or credential was written to Git or disk.
- Database archive: **2,116,946 encrypted bytes**, SHA-256
  `13fb80319663c62d83dab89f45a0ef26a7550b31f76ad12ddfdc9be4cee4ee3c`.
  GCM authentication and checksums passed for the database, roles and row digests.
- Full restore on pinned PostgreSQL 17.6/Supabase image passed: **116 relations,
  5,453 rows**, all row counts/content hashes equal to the source snapshot.
- Target was a new, guarded container with **network none, zero published ports,
  non-root user, read-only root filesystem and tmpfs database storage**. It was
  stopped after verification, removing the plaintext restored copy. Existing
  populated local Supabase and isolated QA stacks were preserved.
- Tested procedure initializes the original `supabase_admin` bootstrap role,
  replays original role attributes/grantors, loads Supautils, restores database
  ownership/ACLs with `pg_restore --create`, and restores event triggers as
  their original owners. Earlier failed recovery attempts are retained privately;
  success evidence is `restore-verification-attempt8.json`.
- Storage objects and Vault secrets were **zero** in the consistent snapshot.
  Storage configuration/metadata are backed up. If future objects appear, their
  actual bytes need a separate encrypted export; database dumps do not contain
  them. See [Supabase backup scope](https://supabase.com/docs/guides/platform/backups).
- Immediately before production modification, a read-only check again matched
  all 116 relations to this backup. Recovery is tied to this Windows DPAPI account;
  retain its profile and protected key. No production restore was performed.

## Exact approved production changes

The [approved SQL batch](../scripts/hosted-mobile-compatibility-20261111.sql),
SHA-256 `412420f9ef8d742bb02ced545e3b71d4b5eadb64ac8bd09486e053fc85b86ab4`,
was explicitly approved and applied once at **2026-11-11 16:06 UTC**. Its original
pre-approval header remains immutable so the approved byte hash stays verifiable.
The single DO statement is atomic and guards history, function bodies/ACLs,
protected data and the 19 unaffected mission definitions.

It reuses exactly these existing migration bodies:

1. `20260908120000_harden_authoritative_action_idempotency.sql`, SHA-256
   `1b8cfd6fc6b70ef1706a9152f86debff5baa67220f391bfbafedb54390863385`.
   This additional dependency was **demonstrated on the restored hosted copy**:
   the unchanged foundation test failed CLIENT_ACTION_ID_IDEMPOTENCY_FAILED.
   Hosted lacked the client-action unique index and its assessment append RPC
   only deduplicated sequence numbers. A read-only duplicate-key preflight found
   zero conflicts. The existing fix adds that index and updates the existing
   SECURITY DEFINER append function, preserving role checks and learner evidence.
2. `20261109120000_coc1_m1_identification_contract.sql`, SHA-256
   `95d60bdc4ecc09a728814c3a31156e170b8be7ebc1873e30ca580abaf81e9a3f`.
   Changes M1 v2 to v3 identification and replaces two SECURITY INVOKER quiz
   functions so verified historical v1/v2 M1 completions continue to count.
   Quiz functions remain server-only; no client verification grant was introduced.

Exact batch execution and existing v2 evidence/restart, v3 identification,
historical quiz-gate and instructor finalization/release rollback tests passed
on the restored copy. All protected rows remained unchanged after rehearsal.

Hosted history was **49**, including remapped and hosted-only entries; it is now
**50**. All 49 entries remain unchanged. New actual batch entry:
`20261111160000 / hosted_mobile_v3_and_action_idempotency`, containing the two
executed SQL bodies. Source versions were not falsely marked as previously
applied. No history repair, database reset or replay of all 52 files occurred.
Future automatic `db push` remains inappropriate for this divergent history.

Post-write read-only verification found only the intended contract/history
tables changed. All other **114 relation** row counts/content hashes were
identical to backup. Before/after the SQL batch, before approved QA signup:

| Preserved records | Before | After |
|---|---:|---:|
| Profiles / Auth users | 37 / 37 | 37 / 37 |
| Practice evidence / COC1 M1 evidence | 595 / 297 | 595 / 297 |
| Practice completions / COC progress / quizzes | 1 / 0 / 0 | 1 / 0 / 0 |
| Assessment attempts | 45 | 45 |
| Score revisions / result releases | 64 / 22 | 64 / 22 |

Hosted-only TeacherDesk objects/data were retained. Seven shared practice /
assessment RPC bodies now match the approved local source, with appropriate
SECURITY INVOKER/DEFINER and effective grants verified read-only. Realtime
publication includes practice completions and COC progress; phone event delivery
still needs owner verification.

Unfinished v2 sessions retain all historical evidence. Partial old work must not
automatically earn v3 completion. Use the existing learner-confirmed **Discard
progress** restart only with the affected learner's informed choice. No real
learner's progress was discarded or rewritten during synchronization.

If further verification fails, stop and inspect; do not repeat the batch. Its
guards intentionally reject reapplication. Prefer a reviewed forward correction.
A production restore/cutover requires separate approval and reconciliation of
writes after the backup, including the subsequently approved QA account.

## All 20 mission compatibility results

Fresh read-only comparison after synchronization found **20/20 exact definition
matches**, including M1 v3, using the existing approved Flutter export. Each
definition covers phases, required evidence, verification and completion rules.
The shared evidence table, verifier, learning-path and quiz/progression contracts
were checked; hosted **authenticated mission submission and phone execution**
remain untested. Earlier all-20 local QA results keep their local-only scope.

| Mission | Mission name | Hosted / approved Flutter definition | Physical completion / persistence |
|---|---|---|---|
| COC1 M1 | Identify Computer Parts and Tools | Exact match | Pending owner |
| COC1 M2 | Install Internal Components | Exact match | Pending owner |
| COC1 M3 | Install and Configure a Workstation OS | Exact match | Pending owner |
| COC1 M4 | Connect and Configure Peripheral Devices | Exact match | Pending owner |
| COC1 M5 | Install Drivers and Test the System | Exact match | Pending owner |
| COC2 M1 | Identify Network Devices and Tools | Exact match | Pending owner |
| COC2 M2 | Create Network Cables | Exact match | Pending owner |
| COC2 M3 | Construct and Verify a Network Topology | Exact match | Pending owner |
| COC2 M4 | Configure Network Devices | Exact match | Pending owner |
| COC2 M5 | Troubleshoot Network Connectivity | Exact match | Pending owner |
| COC3 M1 | Prepare Server Setup Requirements | Exact match | Pending owner |
| COC3 M2 | Install and Configure Server OS | Exact match | Pending owner |
| COC3 M3 | Manage Users, Groups, and Permissions | Exact match | Pending owner |
| COC3 M4 | Configure and Test Server Services | Exact match | Pending owner |
| COC3 M5 | Test Client Access and Document Setup | Exact match | Pending owner |
| COC4 M1 | Identify System and Network Problems | Exact match | Pending owner |
| COC4 M2 | Diagnose and Repair Hardware Faults | Exact match | Pending owner |
| COC4 M3 | Diagnose Hardware and Software Faults | Exact match | Pending owner |
| COC4 M4 | Replace and Reconfigure a Component | Exact match | Pending owner |
| COC4 M5 | Apply Repair Action and Create Report | Exact match | Pending owner |

The earlier audit's 20 official activity packages and 98 rubric criteria were
not re-audited. No definition migration was created for the other 19 missions.

## APK provenance and limits

| Field | Result |
|---|---|
| Build checkout | `73257c1b4b71af15c3d8e71e81f799a4b9635fd4` |
| Approved app implementation | `5ae4dd6ba520685b40217847daf0b4d333634aa2`; no Flutter source diff |
| Flutter / variant | 3.47.7 / **debug** |
| Package / version | `com.example.bytequest` / 1.0 (1) |
| Android / ABIs | min API 24, target 36; arm64-v8a, armeabi-v7a, x86_64 |
| Size | 211997300 bytes |
| APK SHA-256 | `63c336d3938487c85b26e4acce02ce6430306e919b1f09e937e29a6df777bfc0` |
| Android Debug signer SHA-256 | `a4d01056c847034cf2fdc199d4a5dbfa203af5e716d715f560f6db9755bd1d37` |
| Build inputs | Explicit hosted BQ_SUPABASE_URL, BQ_SUPABASE_ANON_KEY (verified public client key), BQ_PRACTICE_API_URL |
| Credential/config inspection | 600 nonempty decompressed entries checked; no configured server secret match; bundled environment contains only three public client settings; no explicit local backend override URL in compiled Dart |
| Installation / actual phone backend | **Pending owner**; no install, replacement, uninstall or data clear performed |

This is a debug-signed owner testing artifact, not a store distribution release.
No release-signing bypass, debug authentication bypass or synthetic completion
switch was enabled. Runtime hosts on a phone cannot be attested from static
APK inspection alone. The old local emulator build is not this artifact.

## Owner testing and remaining acceptance dependencies

Use only the approved QA account. Test login, Learn Page, instructions,
identification/tap/drag interactions, timer, submission, server verification,
completion, sequential quizzes/unlocks, backgrounding, restart/resume and
persistence for all 20 missions. Record actual device model/Android version and
observed outcomes. Registration and login passed through hosted Auth from the
workstation; registration UI on a phone remains unverified. Another QA identity
for a successful phone registration test requires a bounded additional approval.

After the owner performs real work, correlate its timestamps/QA identity with
the expected Supabase rows/logs and Vercel deployment requests. Do not record
tokens, cookies or evidence request bodies in shared logs. Retain test evidence;
deletion/cleanup was not approved.

**Instructor practice visibility remains a specific acceptance gap.** The checked
deployed source's progress and instructor dashboard views read official
assessment attempts/score revisions, not practice completions/COC progress.
Practice completion therefore must not be promised as visible in those views.
No dashboard feature revision was started. A related minimal integration, if
required after phone testing, needs scoped implementation and separate deployment
approval. Official assessments/results remain instructor-finalized and released.
Optional QA class/enrollment/assigned assessments were not created or approved.

## Validation and next action

The hosted build, certificate verification, 20-definition comparison, authenticated
Auth/API reads, exact hosted-copy recovery/rehearsal and production post-checks
passed. Existing 436-test local QA remains valid for the unchanged application.
Fresh required local gates passed: Flutter dependency resolution, analyzer (0 errors / 0 warnings / 217 infos), **436/436 tests**, explicit hosted debug APK build, dashboard TypeScript/lint/build, and Git whitespace checks. No application source changed.

**Owner next action:** download/install the linked APK, sign in with the dedicated
QA account/password entered locally, test COC1 M1 and then all 20 missions, and
report actual phone results. USB is not required. **Do not label physical testing
passed until the owner has completed and approved it.** No Git push, API
deployment or production environment modification occurred.
