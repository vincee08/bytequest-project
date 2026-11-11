# Hosted Android testing gate — 2026-11-11

**BLOCKED — ACTION REQUIRED**

Focused read-only checks on `vince-branch`, application source commit
`5ae4dd6ba520685b40217847daf0b4d333634aa2`. The approved Flutter UI is preserved.
No hosted database write, login, registration, migration, API deployment,
environment modification, Git push, installation, or data clear was performed.
This report adds current connectivity evidence to the existing
[synchronization audit](LOCAL_HOSTED_SUPABASE_SYNC_AUDIT_2026-11-11.md) and
[v3 preflight/rehearsal](HOSTED_COC1_M1_V3_PREFLIGHT_2026-11-11.md).

## Connection evidence

Live checks ran at **2026-11-11 14:24–14:32 UTC (22:24–22:32 Manila)**.
Only GETs and explicitly read-only management requests were sent to hosted services.

| Item | Current evidence | Limit |
|---|---|---|
| Supabase project | **Verified:** `rslmteqipxqfifwftugk`; CLI identifies **ByteQuest · production** | Database catalog access still denied |
| Supabase URL | `https://rslmteqipxqfifwftugk.supabase.co` | Matches mobile default, dashboard default and cached Vercel environment files; cached files do not attest the live deployment |
| Production Auth | `/auth/v1/health` and `/auth/v1/settings`: **HTTP 200** with the mobile publishable key | Password login/registration not attempted; their source paths are `/auth/v1/token?grant_type=password` and `/auth/v1/signup` |
| Auth settings | Email enabled, signup enabled, `mailer_autoconfirm=true` | Observation only; no setting changed |
| Production Practice API | `https://bytequest-alpha.vercel.app/api/learner/practice`: **HTTP 401**, `Active Learner access is required.` | An unsigned GET returns before the route constructs its database client. It does not prove a functioning database binding or authenticated verification |
| Vercel request trace | `sin1::iad1::fqfwj-1794407077407-7b6ff0961ac9` | This is a request ID, **not a deployment revision** |
| Production deployment ID / Git SHA | **Unverified** | Vercel CLI has no credential; its login prompt was canceled. No deployment was initiated |
| Production API database binding | **Unverified** | Requires evidence for the deployment currently serving the production alias |
| Hosted SQL / migration history | **HTTP 403** from `db query --read-only --remote=rslmteqipxqfifwftugk` | No catalog/history reconciliation possible with this account |
| Hosted backups / recovery | **HTTP 403** from `backups list --remote=rslmteqipxqfifwftugk` | No recoverable backup or tested restoration established |
| Android runtime destination | **Unverified** | `adb devices -l` is empty; no physical device or emulator is attached |

The mobile publishable key received HTTP 401 / SQLSTATE `42501` when reading
`practice_mission_contracts`; that table is private by design. Contract and
OpenAPI metadata were therefore read on this workstation with the existing
project-specific dashboard server credential, using GET only against the
expected HTTPS project. No learner records or quiz answer keys were retrieved.
That credential never entered Flutter, command arguments, output, or this report.

The six shared relation definitions are exposed with the required columns:
`profiles`, `practice_mission_actions`, `practice_mission_contracts`,
`practice_mission_completions`, `practice_quiz_attempts`, `practice_coc_progress`.
OpenAPI also exposes the six expected RPC names: `practice_verify_mission`,
`practice_begin_quiz`, `practice_submit_quiz`, `get_practice_learning_path`,
`practice_coc_unlocked`, `practice_conditions_met`. Exposure proves neither
function implementation nor effective privileges, RLS, constraints or execution.

The October activation report identifies historical deployment
`dpl_5rWf1YtWUC7DDVsy9stu9UZ6bY7a`, source
`ccb3aef4d8e70c27e934a66f12d38fa40df38216`. These are **not verified current values**.
The practice route, practice library and admin client have no tracked source
difference between that historical commit and current application source.
An API code change has not been shown necessary for v3.

## Android configuration and artifact inspection

`SupabaseConfig.initialize()` loads the bundled `.env`, then gives precedence
to compile-time `BQ_SUPABASE_URL` and `BQ_SUPABASE_ANON_KEY`.
`PracticeProgressService` independently prefers `BQ_PRACTICE_API_URL` over
the bundled `PRACTICE_API_URL`. These `String.fromEnvironment` values are build
inputs, not Android settings that can be inferred from the current source `.env`.
Process and invocation overrides must be recorded for the particular build.

The existing debug APK inspected before validation:

| Field | Observed value |
|---|---|
| Path | `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk` |
| APK modified time | 2026-11-11 13:52:38 UTC |
| SHA-256 | `75A8E67CB1A167E7A4DB2DAD1D1A181E842485D8BE4E437EE2CED335086B478E` |
| Build variant / package | `debug` / `com.example.bytequest` |
| Version metadata | versionCode `1`, versionName `1.0` |
| Bundled environment | Only `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `PRACTICE_API_URL`; defaults are the hosted endpoints above |
| Source attestation | No artifact-to-commit provenance record; current checkout alone cannot certify its build source |
| Installed identity / runtime | Unverified; no device attached |

A binary string scan found no specific local Supabase or local Practice API
URL in that APK's Dart kernel. SDK strings for `localhost:8080` and
`localhost:9999` were present; their presence does not establish the app's
active backend. Static inspection is not a runtime request trace.
The latest recorded **installed emulator build** used local loopback endpoints;
that is historical handoff evidence, not a fresh device observation.

Production code uses real Supabase Auth, learner-owned evidence upserts, and a
Bearer-authenticated Practice API request. No synthetic completion or fake-auth
switch was found in these production paths. Test constructors/harnesses are
not the normal app route. The release variant requires private signing material;
`BYTEQUEST_ALLOW_DEBUG_SIGNING=true` is an explicit local smoke-build override.
No release-signing override was enabled for this work.

**No APK is approved for hosted testing at this gate.** A local validation build
does not satisfy compatibility, deployment, runtime or physical-device checks.

## All 20 missions

Fresh GETs found **20 hosted contracts**. Canonical JSON comparison against
definitions exported directly from the current Flutter catalog found **19 exact
matches and one mismatch**. This includes every phase, action requirement,
equipment constraint and completion condition stored in each definition.
The result also agrees with the current repository migration definitions.

`v1` = `css-sag-20261009-v1`; `v2` = `css-sag-20261011-v2`;
`v3` = `css-sag-20261109-v3`.

| Mission | Mission name | Flutter / hosted | Definition result | Hosted evidence, API verification, progress and device completion |
|---|---|---|---|---|
| COC1 M1 | Identify Computer Parts and Tools | v3 / v2 | **Incompatible** | Blocked by contract mismatch; other dependencies unverified |
| COC1 M2 | Install Internal Components | v2 / v2 | Exact match | Unverified |
| COC1 M3 | Install and Configure a Workstation OS | v2 / v2 | Exact match | Unverified |
| COC1 M4 | Connect and Configure Peripheral Devices | v2 / v2 | Exact match | Unverified |
| COC1 M5 | Install Drivers and Test the System | v2 / v2 | Exact match | Unverified |
| COC2 M1 | Identify Network Devices and Tools | v2 / v2 | Exact match | Unverified |
| COC2 M2 | Create Network Cables | v2 / v2 | Exact match | Unverified |
| COC2 M3 | Construct and Verify a Network Topology | v2 / v2 | Exact match | Unverified |
| COC2 M4 | Configure Network Devices | v2 / v2 | Exact match | Unverified |
| COC2 M5 | Troubleshoot Network Connectivity | v2 / v2 | Exact match | Unverified |
| COC3 M1 | Prepare Server Setup Requirements | v2 / v2 | Exact match | Unverified |
| COC3 M2 | Install and Configure Server OS | v2 / v2 | Exact match | Unverified |
| COC3 M3 | Manage Users, Groups, and Permissions | v2 / v2 | Exact match | Unverified |
| COC3 M4 | Configure and Test Server Services | v2 / v2 | Exact match | Unverified |
| COC3 M5 | Test Client Access and Document Setup | v2 / v2 | Exact match | Unverified |
| COC4 M1 | Identify System and Network Problems | v1 / v1 | Exact match | Unverified |
| COC4 M2 | Diagnose and Repair Hardware Faults | v1 / v1 | Exact match | Unverified |
| COC4 M3 | Diagnose Hardware and Software Faults | v1 / v1 | Exact match | Unverified |
| COC4 M4 | Replace and Reconfigure a Component | v1 / v1 | Exact match | Unverified |
| COC4 M5 | Apply Repair Action and Create Report | v1 / v1 | Exact match | Unverified |

All missions share the same checked source contract: authenticated evidence to
`practice_mission_actions` with a stable `client_action_id`; learner-scoped
read/reconciliation; API `POST {action:"verify",mission:"cocN_mN"}`; server
`practice_verify_mission(uuid,text)`; verified completion projection through
`get_practice_learning_path()`. None of those mutating operations ran on hosted.
Hosted evaluator bodies, grants, append-only/unique constraints and RLS must
still be compared to the source before declaring production compatibility.
The mobile Realtime coordinator subscribes to the QA learner's practice
completion/COC progress rows and refetches trusted projections. Hosted publication
membership and actual event delivery remain unverified; the evidence query
collects publication metadata for that check.

Source progression requires five verified missions and a server-graded
five-question practice quiz with an 80% learning threshold before the next COC
unlocks. Each earlier COC must be completed. No unlock/progress bypass is proposed.
The local 60-minute COC timer is checkpointed convenience state, not an attested
server deadline. Physical-device persistence/expiry remains to be tested.

The previous isolated QA run passed 138 API checks across all 20 missions plus
four quizzes, raw PostgreSQL replay, and instructor release tests. Those results
are retained with their [local-only scope](practice_all_missions_qa_2026-11-11.md).
The earlier hosted audit also matched all 20 official activity packages and 98
rubric criteria; that comparison was not repeated here. Official assessment
and instructor release remain a separate workflow from practice completion.
**No new migration is indicated for the other 19 missions.**

### Instructor visibility dependency

The checked source's `/progress`, `/progress/learners/[userId]`, and
`/instructor/dashboard` query assessment `attempts` and `score_revisions`.
They do not read `practice_mission_completions` or `practice_coc_progress`.
A search of dashboard source found those practice completion/progress tables
only in the Practice API type layer. Consequently, practice verification cannot
be assumed to appear in the existing instructor UI. The live dashboard revision
is unknown, so no live UI failure is claimed. Record this as a specific remaining
acceptance dependency; no dashboard feature revision was started.

## Smallest synchronization change and approval gate

The sole confirmed database candidate remains the **existing, now tracked**
`supabase/migrations/20261109120000_coc1_m1_identification_contract.sql`, SHA-256
`95D60BDC4ECC09A728814C3A31156E170B8BE7EBC1873E30CA580ABAF81E9A3F`.
It changes one active COC1 M1 definition to v3 and replaces two SECURITY INVOKER
quiz-gate functions to continue recognizing historical v1/v2 M1 completions.
It preserves evidence, completions, accounts, official attempts, scores and
instructor releases. It does not replace the generic verifier. Its v2 row guard
still matches the observed hosted version and four first-phase placement items.

The [existing preflight](HOSTED_COC1_M1_V3_PREFLIGHT_2026-11-11.md) records the
successful isolated, rollback-only rehearsal of that exact SQL, unfinished v2
evidence rejection, explicit-discard recovery, historical quiz-gate compatibility,
all-20 replay and instructor lifecycle checks. Repeating it against unchanged
local fixtures adds no hosted assurance. Rehearse again on a secured isolated
target if the newly obtained hosted catalog or data shapes differ.

Before requesting migration approval:

1. Obtain authorized read-only hosted history/catalog evidence and current Vercel
   deployment evidence. Reconcile all 52 repository versions with hosted history,
   including the five historical timestamp remaps in the earlier reports and
   known local source/history drift. Verify the v3 migration's hosted history
   status and effective absence. Preserve hosted-only `td_*` objects.
2. Establish a completed backup/PITR point, retention window, preservation scope
   and a **tested restore on a separate secured target**. Include Auth/application
   data, migration history, official results and hosted-only objects. Database
   backup metadata alone is insufficient; Storage object bytes need separate
   coverage. See [Supabase backups](https://supabase.com/docs/guides/platform/backups).
3. Freeze reviewed SQL/hash and history mapping, pre-change aggregate baselines,
   maintenance window, API revision/binding evidence and unfinished-session plan.
4. **STOP for explicit owner approval** of that exact hosted migration. Any API
   deployment, environment change or backup restore is also a separate approved
   operation. Do not run `db push`, repair history, replay all 52 files, or reset.
5. After an approved change, read back v3 and its two function bodies/grants;
   compare the 19 unaffected contracts, official packages, catalog protections and
   preserved records/hosted-only objects. Account for legitimate concurrent writes.
   Obtain separate hosted test-data approval before authenticated smoke tests.

For unfinished v2 sessions, preserve existing actions. Partial v2 evidence must
not automatically earn v3 completion. Use the existing learner-confirmed
**Discard progress** path only with the affected learner's informed choice; it
appends a discard marker and starts a fresh v3 timeline without deleting history.
Do not discard or rewrite anyone's progress during synchronization. Already
verified v1/v2 M1 completions continue to count for the quiz gate.

On failure, stop rollout and preserve evidence. Prefer a reviewed forward fix.
A full production restore requires a tested procedure, owner approval, an agreed
data-loss window for writes after the backup, and reconciliation of those writes.
Do not roll back by deleting learner evidence or resetting the contract blindly.

## Evidence the authorized project owner/admin can retrieve

The owner replied **“i cant”** to the request to retrieve dashboard evidence.
No such evidence has been supplied. Supabase and Vercel plugins were found
available and suggested; **neither is confirmed installed or connected**.
An authorized account holder can install/connect those integrations to allow
direct read-only inspection. A connector cannot elevate an account's permissions.
Keep all keys, tokens, passwords and connection strings out of chat.

If another authorized administrator handles the evidence, these are the exact tasks:

1. Open [the expected Supabase project](https://supabase.com/dashboard/project/rslmteqipxqfifwftugk).
   Confirm the project reference in the URL and General settings. In SQL Editor,
   run [the SELECT-only evidence file](../scripts/hosted-mobile-readonly-evidence.sql)
   as written. Export the `hosted_mobile_evidence` result privately. It includes
   migration versions/recorded-SQL hashes, practice function bodies, catalog/RLS/
   ACL metadata, hosted-only object inventory and aggregate preservation counts;
   it contains no learner row payloads. If a permission/missing-object error occurs,
   return the error; do not grant privileges or create objects to make it pass.
2. In Database → Backups, record type, completion time, status and recoverable
   window. Supply the existing isolated restore-test record and its recovery
   procedure, or record that none exists. Do not trigger a restore or paid feature
   change merely to gather evidence. An approved restore rehearsal is then required.
3. Open Vercel team `vincee08s-projects`, project `bytequest`
   (`prj_vUXjALnNCLQWzzdScvwXMfYvppga`). Find the deployment currently serving
   `bytequest-alpha.vercel.app`; record deployment ID, exact URL, Ready status,
   production target, build time, source Git SHA and root directory.
4. For **that deployment**, confirm the effective Supabase URL/reference and that
   its server credential belongs to the same project, without disclosing the
   credential. The current Project Settings environment alone is insufficient:
   [Vercel environment changes affect new deployments](https://vercel.com/docs/environment-variables).
   With an already authorized CLI session, `vercel inspect bytequest-alpha.vercel.app
   --format=json --scope vincee08s-projects` retrieves deployment metadata
   ([reference](https://vercel.com/docs/cli/inspect)). No redeploy is requested.

The evidence SQL was executed successfully **only on the existing local database**
in a read-only transaction: `transaction_read_only=on`, 52 migration entries,
20 contracts, and practice verifier definitions returned. The transaction rolled
back. This validates the collection query, not hosted access or hosted parity.

## Hosted build and owner test plan — pending prerequisites and approval

After synchronization and API binding are verified:

1. Build the approved application source with explicit hosted `BQ_SUPABASE_URL`
   and `BQ_PRACTICE_API_URL` values above, using only the publishable client key.
   Record Git SHA, Flutter version, exact non-secret defines, build variant,
   package/version, signing-certificate fingerprint and final APK SHA-256.
   Inspect bundled environment/assets for server credentials and local overrides.
   Never put a server secret or service-role key in the app.
2. Connect the owner's physical Android device with USB debugging. Record device
   model/Android version and inspect the existing package first. If ByteQuest is
   installed, **stop for permission before replacement**. Never uninstall, clear
   data, use `install -r`, or discard saved work without approval. Use a separate
   device/Android profile if needed to preserve an existing local installation.
3. Use a **new hosted QA learner**, distinct from local identities and real
   learners. Local runtime cache keys use learner/mission/mode rather than project
   reference; reusing an identity with pending local evidence risks reconciling
   that evidence to the newly selected backend. Do not use the owner's old local
   session for this hosted test.
4. Obtain explicit approval for the bounded operations below **before login,
   registration or any test write**, including automatic session/profile writes.
   Owner credentials stay on the device. No harness will synthesize work or write
   completions directly.

| Proposed operation requiring approval | Intended hosted effect |
|---|---|
| Register one dedicated QA learner; complete normal profile setup | Auth identity/profile and ordinary provisioning/settings records; possible confirmation email |
| Sign in/out and restart/resume | Auth sessions/refreshes and normal app activity/settings updates |
| Operate all 20 missions through the real UI | QA learner's append-only evidence; legitimate verifier-produced completions only |
| Complete four quizzes normally | QA quiz attempts/answers and server-issued COC progression |
| Retry verification and resume after background/process restart | Idempotent evidence reconciliation and persisted state, no fabricated actions |
| Optional dedicated QA class/enrollment/assigned attempt | Only if separately approved and needed for instructor scope; existing instructor reviews and releases the QA assessment explicitly |
| Finish testing | Retain evidence; no account/record deletion or cleanup writes without separate approval |

For **each** matrix row, the owner records launch/instructions, identification or
placement/tap/drag as applicable, technical feedback, review, evidence submission,
server verification, completion projection, exit/reentry, restart/resume and
duplicate-evidence results. Verify the Learn Page and all four sequential COCs,
quiz locks/unlocks, timer countdown/background/expiry, and physical screen behavior.
All manual results are currently **PENDING**.

Prove the active backend with correlated runtime evidence from this particular
APK and QA session: actual resolved Auth/REST request hosts on the device, and
matching timestamp/path/status records in the expected Supabase project's logs;
matching Practice API request in Vercel runtime logs for the **identified production
deployment**; the same QA learner's evidence/completion in the expected project.
The owner performs genuine interactions after approval. Redact tokens, cookies,
emails and request/response bodies. A `.env`, successful initialization message,
DNS/TCP probe or unsigned 401 alone does not pass this runtime gate.

Verify instructor visibility in the real hosted UI and record the page and data
source used. The source gap above prevents promising practice-progress visibility
today. For an approved assigned assessment, separately demonstrate learner submit
→ instructor review/finalize/release → learner released result, with no automatic
result release. Practice completions must not be represented as official results.

## Local verification and final handoff

Fresh hosted checks confirmed the project, Auth availability, unsigned API
availability, 20 stored definitions, and expected table/RPC exposure. They did not
perform hosted end-to-end tests. The evidence SQL passed locally read-only.

Repository-required local checks all passed:

| Check | Result |
|---|---|
| `flutter pub get` | PASS; existing dependency lock retained |
| `flutter analyze --no-fatal-infos` | PASS; 0 errors, 0 warnings, 217 informational notices |
| `flutter test` | PASS; **436/436** |
| `flutter build apk --debug` | PASS; validation artifact only, not installed |
| Dashboard `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm build` | PASS; local build only, no deployment |
| Evidence SQL | PASS on existing local database in read-only transaction, then rollback |
| `git diff --check` | PASS |

Flutter **3.47.7** reproduced the inspected APK exactly: 211,997,300 bytes,
SHA-256 `75A8E67CB1A167E7A4DB2DAD1D1A181E842485D8BE4E437EE2CED335086B478E`.
This validation invocation used `flutter build apk --debug` with no `BQ_*`
defines and the inspected hosted-only three-key client environment. Application
source is the commit above; only this report, the read-only query and handoff
were changed. Package/variant remain `com.example.bytequest` / `debug`;
ABIs are `arm64-v8a`, `armeabi-v7a`, `x86_64`.
`apksigner verify --print-certs` passed with the Android Debug certificate,
SHA-256 `A4D01056C847034CF2FDC199D4A5DBFA203AF5E716D715F560F6DB9755BD1D37`.
This is not a production distribution signature.

All **601 decompressed APK entries** were checked for the currently configured
Supabase server secret, OpenRouter credential and Vercel identity token; none
matched. The only bundled environment asset contains the public URL,
publishable client key and Practice API URL. No explicit local backend URL for
ports 57321/57322/29453/3000/3001 was found in the app's compiled Dart payload.
These static checks do not replace the pending runtime request attestation.

The initial dependency command encountered desktop-plugin symlink requirements.
The successful Android-only validation used process-local `FLUTTER_WINDOWS=false`,
`FLUTTER_LINUX=false` and `FLUTTER_MACOS=false`; global Flutter settings and Windows
Developer Mode were not changed. Existing SDK/Kotlin migration warnings remain
non-blocking. Build artifacts and private local evidence are ignored by Git.

**Next action:** an account holder with access to the actual Supabase project and
Vercel team must connect the relevant integrations or perform the evidence tasks
above. Access/evidence comes first; this is not a request to approve a migration
with incomplete safeguards. APK installation and physical testing remain pending.
