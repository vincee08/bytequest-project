# Production release follow-up — 2026-11-13

> Latest: [Verified production Web rollout and requested debug APK](PRODUCTION_DEBUG_ROLLOUT_2026-11-13.md). The owner subsequently deferred SMTP and authorized the completed rollout. The hold and resumption instructions below are historical.

**BLOCKED: production remains on hold at the owner's explicit instruction because SMTP delivery is not configured.** No push, production migration, Vercel deployment, Auth configuration change, production password reset, or Android distribution was performed in this follow-up. This report supersedes the unresolved-blocker descriptions in [the previous handoff](PRODUCTION_RELEASE_2026-11-13.md); its account conversion and backup history remain valid.

## Fixed blockers and verification

| Gate | Result | Executed evidence |
|---|---|---|
| Restored-production migration permissions | **PASS** | The restore omitted the hosted `supautils.policy_grants` and trigger grant settings. Read-only hosted inspection confirms the existing supported delegation allows `postgres` to manage policies on `storage.objects`, although `supabase_storage_admin` owns it. Mirroring the source settings in the isolated restore resolves the ownership error. No production owner, role membership, grants, or RLS changed. |
| Full migration rehearsal | **PASS** | Six original feature migrations plus the new upload migration succeeded under `SET LOCAL ROLE postgres`. Eight rollback SQL files passed, including foundation instructor-release, quiz lifecycle/single attempt, resources, enrollment, homework/deadlines, notifications, and upload authorization. All 116 original relations / 6,069 rows restored with matching hashes; old public columns retain identical data after migration; rollback returned every relation to the original hash. |
| Resource/homework direct uploads | **PASS — isolated QA** | Actual private Storage transfers at exactly 50 MiB and 10 MiB; browser and native transport contracts; MIME/signature/hash/size validation; origin/role/class checks; revoked membership; private downloads; immutable retries; cleanup and referenced-file preservation. Production execution is **NOT TESTED**, because no release occurred. |
| Password recovery | **PASS — isolated QA** | Real locally captured recovery email, explicit token confirmation, normal Auth session, reload continuation, password update on a synthetic account, old password denial, expired/reused/invalid links, cross-origin rejection, and mobile request/responsive browser flow. Production delivery is **BLOCKED** on SMTP and the undeployed recovery route/template. |
| Vercel authorization | **PASS** | Official `vercel login` completed as `vincee08`; team switch, project inspection, environment-name access, and project API inspection succeeded for the existing project. No replacement project/account or access-control bypass. |
| Production backup freshness for the next rollout | **BLOCKED until resumption** | The earlier encrypted snapshot's integrity and isolated recovery passed again. It predates the previous account conversion and Auth sessions. A new consistent backup, source digest comparison, and isolated restore are required immediately before production changes. No older snapshot is represented as a current recovery point. |
| Production configuration | **BLOCKED** | Read-only hosted check: correct production Site URL, old exact `/login` and `/profile` redirects, SMTP absent, new recovery template absent. Vercel server env names are accessible; production `CRON_SECRET` is not configured. Apply the compatible configuration only during the resumed ordered release. |
| Git/release | **BLOCKED** | Local work is committed on `vince-branch`; nothing pushed or merged. Neither `main`, `new`, nor repository protections were changed. See the final owner handoff for the exact local commit SHA. |

Private rehearsal evidence: `%LOCALAPPDATA%/ByteQuest/Recovery/rslmteqipxqfifwftugk-20261113/restore-verification-attempt8.json` and its encrypted diagnostics. The guarded container `bytequest-recovery-rslm-20261113-release-8` had no network or published ports, ran as a non-root user with a read-only root and tmpfs database, and was stopped after verification.

The six original migrations remain unchanged. The release order is:

1. `20261112111620_quiz_publishing_and_single_attempt.sql`
2. `20261112151434_resource_quiz_sources_and_request_safety.sql`
3. `20261113024352_homework_and_quiz_deadlines.sql`
4. `20261113031014_quiz_deadline_admission_timestamps.sql`
5. `20261113062554_learner_activity_notifications.sql`
6. `20261113072038_notification_quiz_assignment_links.sql`
7. `20261113084656_direct_storage_uploads.sql`

The actual hosted migration history is divergent from the repository's older foundation history. Do not replay all historical files or run a destructive reset. Reconcile only the verified pending release versions through the existing authorized migration workflow. The existing hosted `postgres` policy delegation is the supported path; it does not require changing ownership or applying the rehearsal container's startup settings to production. [Supautils policy delegation](https://github.com/supabase/supautils) documents this model; the permission was also verified directly in the hosted catalog.

## Upload behavior and limits

`POST /api/uploads` accepts only small JSON metadata. A verified cookie/bearer identity is checked against the active profile, class, enrollment and homework state. A service-only invoker function records an immutable upload intent, enforces quotas and returns one exact private path. Only its short-lived signed upload permission reaches the client; privileged credentials do not. Storage forbids overwrite even if a client changes the upsert header.

Browser XHR and Flutter PUT send bytes directly to Storage. Both recognize the deployed Storage server's HTTP 400 `KeyAlreadyExists`/`Duplicate` response with internal status 409, as well as HTTP 409. A retry then proceeds through server verification. The browser regression deliberately delivers the bytes and drops the acknowledgement, then verifies that retry saves one resource. Arbitrary Storage failures are not treated as duplicate success.

The server streams a bounded private Storage download to verify actual length, MIME/signature and SHA-256 before an atomic metadata/audit commit. Authorization is checked again at finalization. Verification leases prevent concurrent finalizers; cleanup leases and fresh path generations prevent an old cleanup request from deleting a new retry. Existing resources, submissions and multipart contracts remain intact. Read-only Vercel project inspection confirms Fluid is enabled with a 300-second default timeout, compatible with the upload route's 180-second and cleanup route's 240-second ceilings.

The new `file_upload_intents` table has RLS and no anon/authenticated table or RPC privileges. Both new functions use **SECURITY INVOKER** with service-only execution; no new SECURITY DEFINER function was added. Public download routes and existing Storage SELECT policies still enforce membership/ownership. Learner answer files remain private before submission, then become reviewable by their authorized instructor through the existing contract.

Cleanup runs through `/api/internal/uploads/cleanup` using constant-time `CRON_SECRET` authentication. The daily Vercel schedule is 18:00 UTC / 02:00 Manila. It claims at most 20 expired intents per invocation, waits beyond the signed token lifetime, retains any historically referenced bytes, and retries interrupted leases. Configure the secret and verify the cron during the resumed release. The same authenticated endpoint supports an operator-triggered additional batch if needed.

AI extraction accepts text PDFs up to 10 MiB, 50 pages and 48,000 characters. It fetches private bytes from Storage internally, uses a worker with a 15-second deadline and 192 MiB old-generation cap, and rejects a 50 MiB resource before downloading it for AI. External AI consent and existing review/publication rules remain. No large file request or response passes through a Vercel Function's external payload pipeline. The actual hosted function behavior remains a deployment smoke-test gate; local success is not a production deployment claim. [Vercel Function limits](https://vercel.com/docs/functions/limitations) still apply to the preserved legacy multipart endpoints.

## Recovery and existing staff identities

The recovery email template is `supabase/templates/recovery.html`. It uses a TokenHash fragment, which the browser removes from history before explicit confirmation. `verifyOtp(type: recovery)` establishes the ordinary user session. A signed, HTTP-only, SameSite Strict proof binds the password form to that verified user/session for 15 minutes. Ordinary sessions do not acquire reset permission through this endpoint. Password update clears the proof and globally signs out sessions; users then sign in again. No service-role session reaches the dashboard.

Flutter requests the reset through the existing production API origin; the email opens the responsive recovery page in a browser, then the learner returns to the app. An app deep-link session is not claimed. The supported browser flow avoids relying on a PKCE verifier left on a different device.

| Production account | Result |
|---|---|
| `ivanmanguilimotan@gmail.com` | **PASS:** original Auth identity retained; active Admin profile and confirmed email freshly verified read-only. |
| `manguilimotan.ivan@dnsc.edu.ph` | **PASS:** original distinct Auth identity retained; active Instructor profile and confirmed email freshly verified read-only. |
| Passwords / profiles / learner history | **PASS:** no reset, recreation, profile overwrite, enrollment change or learner write in this follow-up. Passwords remain the owner's existing passwords. |
| First-login forced change | **NOT IMPLEMENTED / NOT REQUIRED:** no claim of a forced first-login change. No plaintext temporary Auth passwords generated. |
| Password-based production sign-in after this release | **NOT TESTED:** no release occurred and existing passwords were not requested. Earlier genuine authenticated dashboard/role/RLS checks remain in the previous report. |
| Local access instructions | `.tmp/production-initial-credentials-2026-11-13.txt` remains private and Git ignored; it contains instructions, not new passwords. |

SMTP is a genuine delivery blocker: Supabase's default sender restricts recipients to project organization members and is not a general production recovery service. [Official SMTP guidance](https://supabase.com/docs/guides/auth/auth-smtp). The owner explicitly selected **Keep production release blocked** when asked to configure delivery. No real owner recovery email or password change was attempted.

## Android preparation

The owner confirmed that only a debug APK existed and explicitly authorized the first production key and APK for fresh installations. Package identity remains `com.example.bytequest`. The new version is **1.1.0 / versionCode 2**, and Gradle now uses Flutter's version values instead of the old hardcoded code/name.

**PASS — signing configuration:** first production PKCS12 key, RSA 3072, alias `bytequest-release`; restricted owner-only Windows ACLs. Certificate SHA-256: `dc85ef75a3a7adf3429cfa8c23cf460bea6a78ef0ebfa0c6d0e080e8d67e0d68`.

Private owner files:

- `%LOCALAPPDATA%/ByteQuest/Signing/production-20261113/bytequest-production.p12`
- `%LOCALAPPDATA%/ByteQuest/Signing/production-20261113/signing-credentials.txt`
- `ByteQuest-Mobile-App/android/key.properties` — ignored and owner-only.

No signing password appears in this report, source, migration, command arguments, or Git. The key-generation command reads passwords from a temporary process environment and clears it. Preserve an encrypted offline backup of the private signing directory before distribution; future production updates must use this identity.

**PASS — signed release APK:** `C:\Users\HP\Documents\Projects\ByteQuest\ByteQuest-Mobile-App\build\app\outputs\flutter-apk\app-release.apk`, **74,083,870 bytes**. APK SHA-256: `049471671666a60df11fa220db90e8300041da969833fa91727a3445c45807da`. `apksigner verify --verbose --print-certs` confirms the approved production certificate and one signer. AAPT confirms package/version continuity. Inspection of the actual APK's environment asset confirms the production Supabase/API origins, a public client key and no server-only settings. Evidence: ignored `.tmp/release-20261113/android-artifact-verification.json`; repeat with `scripts/verify-android-release.ps1` using the installed Android tools and JDK.

The release build initially found the old `android.nonFinalResIds=false` setting incompatible with AGP 9's optimized resource shrinking. Setting it to `true` preserves the required optimization; no shrinker or validation was disabled. An overlapping Flutter test command also regenerated a test plugin during release compilation. After all Flutter tests finished, sequential debug and release builds passed; the generated release registrant excludes the integration-test plugin. Keep Flutter test/build commands sequential because they share generated files. Existing Kotlin migration and SDK metadata warnings are nonfatal follow-up maintenance, not waived build failures. [Android optimization guidance](https://developer.android.com/topic/performance/app-optimization/enable-app-optimization).

**Distribution remains BLOCKED** until the production backend/web gates pass. There is no configured Google Play channel, and no store publication is claimed. A different production certificate cannot update the existing debug-signed installation. No owner app was installed, uninstalled, reset or overwritten; use a fresh installation target after release.

## Validation and production state

| Check | Result |
|---|---|
| Dedicated QA upload SQL regression | **PASS** — rollback authorization, caps, leases, metadata idempotency, revocation and cleanup; migration applied only to QA 58922. |
| Restored-production SQL | **PASS** — seven migrations and eight regression files; original data hashes preserved. |
| Browser/API/Storage/recovery integration | **PASS** — small and boundary-size files; private/class scope; retry and cleanup; real local email/session/password lifecycle. |
| Existing activity API groups | **PASS** — 7/7, including concurrent one-attempt enforcement, deadlines/reopening, homework submission/grading and late snapshots. |
| Existing notification API groups | **PASS** — 4/4; exact recipients, retry deduplication, own-only reads and read persistence. |
| Web automated tests | **PASS** — 59/59 (31 component/general + 28 server/security). |
| TypeScript / ESLint / production web build | **PASS** — zero errors/warnings from ESLint; all 31 static pages generated plus dynamic routes. |
| Flutter analyzer / tests | **PASS** — zero errors/warnings; 215 informational findings (including a new const-constructor suggestion in recovery feedback); 480/480 tests. |
| Android debug / signed release build | **PASS** — sequential builds; approved certificate, package, version, production endpoint and packaged client-environment checks passed. |
| Production unsigned surface smoke | **PASS** — `/login` 200; `/admin/dashboard` and `/instructor/dashboard` 307 to `/login`. These check the existing live version. |
| Production schema/Storage inspection | **PASS — read-only:** zero release migrations applied, zero Storage objects, zero public tables without RLS, supported `postgres` Storage-policy delegation present. |
| New-feature production workflows and post-release role sign-in | **NOT TESTED** — production hold. |
| Physical Android, TalkBack, installed-debug upgrade | **NOT TESTED** — no owner-device operation. Debug and production certificates differ. |

No production write occurred in this follow-up. Existing COC missions, learner attempts, answers, results, homework, enrollments and Storage objects were not modified. The existing production alias remains [ByteQuest](https://bytequest-alpha.vercel.app); its active deployment is still `dpl_CM8Kh72voepkXTVm8zWSKJZ2rZhS`, source `dff80603087522c7c0a0a070464696b9237580f7`.

## Ordered resumption and recovery

1. **Owner action:** configure the existing project's SMTP privately in Supabase Authentication → Email → SMTP Settings with an authorized provider/sender, then explicitly resume the held release. Keep credentials out of chat and Git.
2. Refresh the consistent encrypted DB/Auth/roles backup and object inventory into a new private subdirectory; retain the previous snapshot. Preserve object bytes separately if the inventory is no longer zero. Verify encryption and a fresh isolated restore; mirror the source's current Supautils delegation. Run `node scripts/rehearse-production-release.mjs --attempt=<unused-number> --backup-dir="<current-private-backup-directory>"` from the repository root. The directory must stay inside `%LOCALAPPDATA%/ByteQuest/Recovery`. Never restore over production while rehearsing.
3. Recheck `vince-branch` tracking, exact commits, remote state and the Git secret scan. Vercel currently links `vincee08/bytequest-project`, production branch **`new`**, auto-deployments enabled, no deploy hooks/ignore command. A `vince-branch` push produces a preview, not an automatic production promotion. Production environment names include the Supabase URL/publishable/server key and OpenRouter key. Keep all server values confidential; configure `CRON_SECRET` and validate actual values during the resumed rollout.
4. Apply only the seven verified migrations in order with the existing authorized migration role and atomic failure handling. Keep the old live web/mobile contracts working while the additive schema is introduced. Record migration versions only after their exact SQL succeeds. Do not repair unrelated foundation history to force a bulk push.
5. Push the approved `vince-branch` commits through the existing remote without force or protection bypass. Build/deploy the same SHA to the **existing** Vercel project using the supported staged production deployment/promotion workflow; do not push to `main`, change the production branch, or create a new project as a shortcut. Verify source SHA, runtime environment, PDF worker packaging and private uploads before exposing production traffic.
6. Once the new recovery route is reachable, update the recovery template and add the exact production `/auth/recover` redirect, preserving existing allowed redirects and the production Site URL. Verify real delivery/session/update on a dedicated safe account, never by resetting the two owner staff accounts. Test cron authentication/cleanup and the large-file path in the actual hosted runtime.
7. Verify Admin/Instructor separation and the requested quiz/homework/notification/mission workflows using synthetic classes/accounts with cleanup. Promote the staged release only after critical gates pass. Prepare the signed APK from that exact source/environment, verify the certificate/package/version again, then distribute through an explicitly supported delivery method for fresh installs. No Play channel is configured.
8. If a critical gate fails, stop promotion/distribution. Roll back application traffic to the recorded existing deployment while retaining backward-compatible tables and all learner history. Prefer a reviewed forward migration for schema defects; do not drop new tables/policies containing data or automatically restore an old snapshot over live users. Use the verified backup only through an explicit disaster-recovery procedure that accounts for newer Auth/data/Storage state.

Repeatable local commands: `node scripts/direct-upload-db-tests.mjs`; `node scripts/quiz-preview.mjs setup-recovery`; `node scripts/quiz-preview.mjs dev`; `node scripts/quiz-preview.mjs release-gates`; `node scripts/test-web.mjs`. The QA launcher is guarded to local Supabase 58921/58922, captures mail locally, uses a private local cron secret and never supports hosted reset/migration commands. Final integration evidence is in ignored `.tmp/release-20261113/release-gates-results.json` (10/10 groups, run `a14fd9fc`); diagnostics are private. The final local Vercel/production web build passed after the QA preview was stopped; no local production-connected preview is left running on port 3008.
