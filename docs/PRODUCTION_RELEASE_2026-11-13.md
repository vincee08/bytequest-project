# Production accounts and release status — 2026-11-13

**Overall: BLOCKED.** The two approved production account conversions are complete. The coordinated feature push, six production migrations, Vercel deployment and signed Android release did not run. This report records executed work, not deployment approval or a successful feature rollout.

The owner explicitly authorized production work and subsequently approved reviewing history and converting the existing accounts. That confirmation supersedes the earlier prohibition on changing these two existing learner roles. No password reset was authorized or performed for either existing account.

| Account | Executed result | Authentication and authorization |
|---|---|---|
| ivanmanguilimotan@gmail.com | **PASS** — existing identity converted to active Admin; one original profile retained | Real Supabase one-time-token session; production Admin Dashboard and Users HTTP 200; Instructor route redirects to Admin; regular `authenticated` JWT |
| manguilimotan.ivan@dnsc.edu.ph | **PASS** — existing identity converted to active Instructor; one original profile retained | Real Supabase one-time-token session; production Instructor Dashboard and Classes HTTP 200; Admin route redirects to Instructor; foreign-class SELECT returns no rows; `is_admin()` false |

Before conversion, the first identity had two membership records. The second had two memberships, two assessment attempts and 73 practice actions. These records remain under their original IDs. The owner approved reusing these identities; no unrelated learner account was adopted and no duplicate Auth identity/profile was created.

Conversion used an atomic, guarded maintenance transaction through the existing Supabase Management API authenticated as the organization Owner. It locked the two profiles, required the exact existing identities and active learner state, changed only role/timestamp fields, and called the existing audit writer twice. Audit metadata identifies the maintenance channel and owner authorization; no application actor was impersonated. No new function, client role grant, RLS change, account deletion or service-role dashboard session was introduced.

**Password status: NOT TESTED for existing password sign-in; unchanged.** Temporary passwords were not generated because both accounts already existed. No forced first-login password-change feature exists in the deployed dashboard. The authenticated `/profile` change-password form was verified without submitting a new password. The existing browser recovery-link flow failed to establish a session; it must not be advertised as working. There is no token-confirmation callback in the current application source. A real Auth token verification followed by normal SSR session cookies passed the independent dashboard/RLS tests; it does not prove the email-link browser flow or password sign-in.

Private owner instructions, with no passwords or unusable recovery links, are in `.tmp/production-initial-credentials-2026-11-13.txt`. Git exclusion was checked before writing. Windows inheritance is disabled and only the current owner account has access. No Auth admin key, session token or password is in this report or Git.

**Production Auth configuration: PASS for redirect settings only.** Changed the existing localhost Site URL to `https://bytequest-alpha.vercel.app` and added exact production `/login` and `/profile` redirect entries. The previous full configuration is encrypted in the recovery directory. All other settings were verified unchanged. Custom SMTP remains unconfigured; external invitation/reset-email delivery is **NOT TESTED**. No invitation/recovery email was sent.

**Backup and restore: PASS.** A new consistent, provider-enforced read-only backup covers all database schemas/data, Auth, hosted-only relations, migration history, and role/grant definitions without PostgreSQL login passwords. Location:

`C:\Users\HP\AppData\Local\ByteQuest\Recovery\rslmteqipxqfifwftugk-20261113`

The directory is restricted to the Windows owner. Archives use AES-256-GCM with a DPAPI CurrentUser-protected key. Preserve that Windows profile and key for recovery. Previous recovery artifacts were retained. Managed backups remain empty; the new encrypted local backup is the verified recovery artifact.

| Backup evidence | Result |
|---|---|
| Database archive | `database-full-readonly.dump.bqenc`, 2,171,608 encrypted bytes |
| SHA-256 | `cbfc7e148e3545fc9d08fbcf092d5b400fc5846f43fc92d28d681c73a6e0dbcf` |
| Integrity | GCM authentication and SHA-256 checks passed |
| Isolated restore | 116 relations / 6,069 rows; every original count/content hash matched |
| Isolation | Pinned Supabase PostgreSQL image; network disabled; no ports; non-root; read-only root; database in tmpfs; targets stopped after checks |
| Conversion rehearsal | Passed and rolled back; every restored relation hash returned to baseline |
| Storage / Vault | Zero objects and zero Vault secrets in the fresh snapshot; Storage configuration/metadata included |
| Freshness | All 116 relation hashes matched immediately before production conversion |
| Final preservation | All preexisting learning data hashes preserved; only the intended profiles/audit events and normal Auth session/token records changed |

The first isolated restore attempt hit a pipe EOF; a separate fresh restore passed. Private evidence: `restore-verification-attempt2.json` and `restore-verification-attempt3.json`; the latter also records the exact conversion rehearsal/hash. No restore ran against production or an existing populated local database.

**Git and deployment: BLOCKED.** Application source at task start is `b392de87eaab20b1b660c5be27ac7161e083360b` on `vince-branch`. The actual remote branch read returned `dff80603087522c7c0a0a070464696b9237580f7`; ten approved local commits were pending before this handoff commit. No push, force-push, merge or repository-protection bypass occurred. The existing Vercel project is `bytequest` / `prj_vUXjALnNCLQWzzdScvwXMfYvppga`; production URL remains [ByteQuest](https://bytequest-alpha.vercel.app).

The stored Vercel credential returns HTTP 403 `forbidden` / `Not authorized` for the project, current-user and team endpoints. Consequently the current production Git branch, automatic deployment triggers, effective production environment (including OpenRouter), active deployment revision and promotion/rollback controls could not be freshly verified. Historical deployment evidence is not fresh confirmation. Pushing before this is resolved could trigger an incompatible deployment, so the coordinated push was withheld.

The 179 changed release paths and ten pending commit patches were scanned: no prohibited environment/build/release paths and no exact matches for either configured server secret. Existing unrelated untracked owner files remain untouched. Only this report and the handoff state belong in the new documentation commit.

**Production migrations: BLOCKED; zero feature migrations applied.** The existing divergent production history was read, not repaired or replayed. The six pending files, in order, are:

1. `20261112111620_quiz_publishing_and_single_attempt.sql`
2. `20261112151434_resource_quiz_sources_and_request_safety.sql`
3. `20261113024352_homework_and_quiz_deadlines.sql`
4. `20261113031014_quiz_deadline_admission_timestamps.sql`
5. `20261113062554_learner_activity_notifications.sql`
6. `20261113072038_notification_quiz_assignment_links.sql`

A fresh restored-production copy passed restoration, then the ordered migration rehearsal under `postgres` failed with **`must be owner of table objects`** when adding the homework Storage policy. That transaction rolled back and the isolated target stopped. The actual Management API maintenance connection also identifies as non-superuser `postgres`; a supported authorized Storage-policy migration path must therefore be validated before production application. No table owner, role membership or permission was changed to bypass the failure. Private evidence: `restore-verification-attempt4.json` and its encrypted diagnostics. The dedicated existing QA rollback suites pass, but that does not override this production-copy failure or prove installed-mobile compatibility with a completed release.

**Upload compatibility: FAIL as a production release gate.** The current 50 MiB class-resource upload and 10 MiB homework uploads send multipart file bytes through Next.js Functions. Vercel documents a [4.5 MB payload limit](https://vercel.com/docs/functions/limitations). The local middleware workaround does not remove that limit. Secure direct-to-Storage upload and server-side finalization remain required and were not implemented or deployed in this blocked rollout. No claim is made that these maximum-size uploads work in production. Storage remains private. [Supabase's backup documentation](https://supabase.com/docs/guides/platform/backups) also distinguishes database metadata from object bytes; the fresh zero-object inventory is why no object-byte archive was needed here.

**Android release: BLOCKED.** Package identity remains `com.example.bytequest`. `pubspec.yaml` is `1.0.0+1`; Gradle currently fixes versionName `1.0` / versionCode `1`. No new release version was assigned. The required private `ByteQuest-Mobile-App/android/key.properties` is absent; only the example exists. Release signing continuity and an actual production delivery channel cannot be established from the available configuration. No Play/Fastlane/distribution workflow was found. Existing records describe a manually delivered, debug-signed testing APK, not a production store release.

No release APK/AAB was built or published, no signing key was created or substituted, and no owner installation was modified. The fresh debug APK at `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk` is solely a validation artifact. It is not a production release or a Play Store deployment. Resume requires the original approved signing setup, certificate/upgrade continuity, a newer versionCode and the supported distribution access.

| Fresh verification | Status |
|---|---|
| Flutter dependencies | **PASS** |
| Flutter analyzer | **PASS** — zero errors/warnings; 214 informational findings |
| Full Flutter tests | **PASS** — 474/474 |
| Android debug validation build | **PASS** — existing Kotlin migration notices remain |
| TypeScript / ESLint / Next production build | **PASS** — 27 static pages plus dynamic routes |
| Node server / component regressions | **PASS** — 49 + 6 = 55 |
| Existing isolated QA activity SQL | **PASS** — homework/deadlines, one-attempt, learner quiz lifecycle, foundation instructor-release, resources and enrollment |
| Existing isolated QA notification SQL | **PASS** — delivery/read persistence and technical assignment/instructor-release lifecycle |
| Production unsigned login/protected-route probes | **PASS** — login 200, staff pages redirect unsigned users, practice API 401 |
| Production authenticated staff dashboards/RLS | **PASS** — both roles; Instructor foreign-class isolation |
| Production recovery-link browser flow | **FAIL** — no established browser session; passwords retained |
| Restored-production migration rehearsal | **FAIL** — Storage-policy ownership; no production application |
| New-feature production class/enrollment/quiz/homework/grading/notification workflows | **NOT TESTED** — required release migrations/web/mobile not deployed |
| Physical Android/TalkBack and installed-app release compatibility | **NOT TESTED** |
| Production data preservation | **PASS** — preexisting learning records retained; all 74 public tables retain RLS |

Do not mark the overall release complete. Resume after Vercel authentication/team access and Android signing/distribution access are available, then resolve the Storage-policy migration path, implement/test direct Storage uploads and the secure recovery callback, rehearse again on a fresh restored copy, coordinate migrations with automatic deployment controls, and run the requested production workflows using isolated safe fixtures. Existing owner authorization to release persists; it does not waive these blockers.
