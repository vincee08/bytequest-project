# Hosted Web rollout and production-connected debug APK — 2026-11-13

**Web deployment and requested debug APK: PASS, initially limited production release.** The owner explicitly deferred custom SMTP and authorized this rollout. That decision supersedes the SMTP-only hold in the two earlier release reports. Backup, migration, authorization and integrity gates were retained. Owner learner/device acceptance remains pending; this report does not claim a completed learner-to-instructor-to-learner manual test.

| Release item | Verified result |
|---|---|
| Production Web Supabase | **PASS:** `rslmteqipxqfifwftugk`, `https://rslmteqipxqfifwftugk.supabase.co` |
| Flutter Supabase | **PASS:** same project, checked in explicit build defines, the APK environment asset and compiled Dart payload |
| Web API origin | `https://bytequest-alpha.vercel.app` |
| Flutter API | `https://bytequest-alpha.vercel.app/api/learner/practice`; homework/uploads/recovery resolve against that same origin |
| Shared hosted backend | **PASS:** actual production browser bundle, accepted public keys, ordinary hosted staff sessions, deployed server operations and native bearer requests; no selected QA/local backend |
| Fresh backup/recovery | **PASS:** fresh encrypted consistent DB/Auth/roles backup; 116 relations / 6,248 rows restored with identical hashes |
| Migrations | **PASS:** seven ordered release migrations applied atomically; original public/Auth data preserved |
| Git source push | **PASS:** `8e7862dd54c46fd768ff898e3193621fe752cd79` pushed to `bytequest-project/vince-branch` and freshly confirmed remotely |
| Production deployment | **PASS:** READY `dpl_4QmfAdBJS7VpZgFTiGyQdMaEx9gR`, same source SHA, promoted to the existing production alias |
| Production APIs | **PASS:** staff authentication/role scope, learner search, native bearer homework, private uploads, quiz publication/deadlines/reopening, AI drafts and cleanup authentication; details below |
| New debug APK | **PASS:** new `app-debug.apk`, version `1.1.0+2`, verified debuggable |
| Signing/update | **PASS against preserved previous debug APK:** same certificate and application ID; physical installation not attempted |
| SMTP | **DEFERRED:** delivery and the hosted recovery email-template requirement remain limited |
| Learner synchronization | **PARTIAL:** configuration, schema/contracts and production server reads verified; new learner enrollment/submission/grading/notification UI acceptance awaits the owner |
| Remaining blockers | No unresolved non-SMTP deployment/build blocker identified. Owner manual acceptance, physical Android/TalkBack and email delivery remain unverified. |

## Connection verification before changes

Production environment values were pulled from the existing Vercel project; source/sample environment files were not treated as runtime evidence. The actual live browser JavaScript identified the expected hosted reference. Both configured public keys were accepted by that project's Auth settings endpoint. The server client uses the same verified `NEXT_PUBLIC_SUPABASE_URL`, without an alternate QA destination. Vercel's sensitive server/AI keys are deliberately non-exportable; empty sensitive values in an environment export were not treated as missing keys. Actual authenticated server operations subsequently verified them.

Flutter initialization uses `BQ_SUPABASE_URL` / `BQ_SUPABASE_ANON_KEY` defines before the bundled public `.env`. Practice, homework, uploads and recovery use `BQ_PRACTICE_API_URL` before the corresponding asset setting. This build supplies all three explicitly. Its environment asset and compiled payload contain the expected hosted URLs, with no selected localhost, emulator or isolated-QA target. Public client credentials were not printed. All 609 APK entries were checked against the configured server credentials; zero matches were found.

Web SSR cookies and native bearer tokens identify the same Supabase Auth UUIDs and authoritative `profiles.user_id`. The live native bearer homework request succeeded through the deployed server credential and RLS client. Final checks found zero orphan profiles/enrollments and zero public tables without RLS. Instructor class reads were checked against ownership **or the account's preserved active memberships**; an unrelated, unenrolled class was denied. Those historical memberships were not removed to simplify testing.

Before rollout the existing homework/upload/recovery feature routes were absent. Their presence was verified after deployment, rather than inferred from matching URL strings.

## Backup, integrity and migration execution

The final pre-migration recovery point completed at **2026-11-13 10:53:10 UTC**:

`C:\Users\HP\AppData\Local\ByteQuest\Recovery\rslmteqipxqfifwftugk-20261113-rollout-final`

- `database-full-readonly.dump.bqenc`: **2,188,770 bytes**, SHA-256 `ffd653fb9a012222f57e01ca85ab852701e38b9710a60ff6025264765b2bf4af`.
- Consistent provider-enforced read-only snapshot, all database schemas/data including Auth and hosted-only relations; role/grant definitions exclude PostgreSQL login passwords.
- AES-256-GCM authentication and archive SHA-256 passed; encryption key is protected by Windows DPAPI CurrentUser. The directory is restricted to the Windows owner. Preserve that Windows profile/key and the private recovery directory.
- Storage objects and Vault secrets were both zero at backup. Storage bucket/policy metadata was included. The later synthetic upload objects are post-backup test artifacts, not preexisting student files.
- Isolated attempt **11** restored all **116 relations / 6,248 rows** with matching count/content hashes. It also rehearsed the exact maintenance transaction, all seven migrations and eight regression SQL files. The new network-disabled, non-root, read-only-root, tmpfs container was stopped afterwards.
- All 116 source fingerprints matched immediately before the production transaction. An earlier recovery point was refreshed after live practice actions changed its fingerprints; it was not misrepresented as current.

Only the following reviewed, unchanged release migrations were applied, in this order:

1. `20261112111620_quiz_publishing_and_single_attempt.sql`
2. `20261112151434_resource_quiz_sources_and_request_safety.sql`
3. `20261113024352_homework_and_quiz_deadlines.sql`
4. `20261113031014_quiz_deadline_admission_timestamps.sql`
5. `20261113062554_learner_activity_notifications.sql`
6. `20261113072038_notification_quiz_assignment_links.sql`
7. `20261113084656_direct_storage_uploads.sql`

The exact guarded transaction SHA-256 is `87ff474bc633cd50d51e65ca5d6efae9fbf27e38a3af0a2cff3ac68e578b9b2f`. It checked original public/Auth row hashes over their original columns, preserved existing bucket rows, required RLS, and recorded migration versions only after the SQL succeeded. Hosted versions were then read back. Existing passwords, identities, classes, memberships, attempts, answers, progress and notifications were retained. No production reset, historical foundation replay, ownership workaround, new elevated function or RLS disable occurred.

Recovery procedure: use the private manifest and DPAPI key with the existing recovery tools, first restoring into a new guarded isolated target. The successful rehearsal command was `node .tmp/rollout-20261113/rehearse-exact-release.mjs --attempt=11 --backup-dir=C:/Users/HP/AppData/Local/ByteQuest/Recovery/rslmteqipxqfifwftugk-20261113-rollout-final`; use an unused attempt number for another rehearsal. The durable base tool is `scripts/rehearse-production-release.mjs`. Do not restore a stale snapshot over live users. For an application regression, prefer traffic rollback to `dpl_CM8Kh72voepkXTVm8zWSKJZ2rZhS`, retaining additive tables and newer user data; a destructive database recovery requires a separate reviewed incident procedure.

## Git and Vercel

All 12 approved source commits and their 213 changed paths were reviewed/scanned. No configured credential match, prohibited private/build path, JWT-like secret or private key was found. Unrelated untracked owner files were excluded and preserved.

The existing project remains `bytequest` / `prj_vUXjALnNCLQWzzdScvwXMfYvppga`, team `team_9kWTkm9JMxTpNKitR90fUDiV`. Its production branch remains **`new`**, with Git deployments enabled; `vince-branch` pushes produce previews. Nothing was pushed to `main` and no protection was bypassed or force-push used.

An exact `git archive` of the verified source SHA was deployed to that existing project with production environment settings and `--skip-domain`. Staged tests used the project's existing supported automation-access token while ordinary Supabase sessions still enforced application authorization. The final tested build was promoted with explicit team scope; the production project target and source SHA were read back. The two earlier staged candidates were not promoted. The final deployment URL is `https://bytequest-d9aabui4a-vincee08s-projects.vercel.app`; public users should use [the production Dashboard](https://bytequest-alpha.vercel.app).

The remaining documentation changes are committed/pushed separately on `vince-branch`; they do not replace the verified application source SHA above.

## Executed hosted checks and their limits

- **PASS:** existing Admin and Instructor identities remain active/confirmed. Real one-time-token verification established ordinary `authenticated` sessions, protected dashboards/features returned 200, cross-role routes redirected correctly, and class RLS denied an unrelated class. Existing passwords were unchanged; password-based sign-in was not tested.
- **PASS:** Instructor-owned disposable class, authenticated learner directory search, native bearer API, reviewed-only manual quiz publication, persisted single-attempt assignment, server-clock deadline expiry and class-specific reopening.
- **PASS:** actual hosted **50 MiB** resource and **10 MiB** homework instruction transfers directly to private Storage, streamed server verification, idempotent finalization, cross-origin rejection, persisted publication/private metadata and denial of instructor-as-learner submission. Legacy multipart and older mobile/RPC contracts remain available; existing quiz/progress keys and records were retained. No physical older-app upgrade is claimed.
- **PASS:** real hosted AI generation from a synthetic private PDF, packaged PDF worker and editable draft-only persistence. The original `openrouter/free` route exhausted its output budget. The previous QA model was also scheduled to retire that day. Current model discovery plus the real application provider code validated **`particle-ai/particle-1:free` / `OPENROUTER_REASONING_EFFORT=none`**, then the final staged runtime generated a draft successfully. No AI key was changed, exposed or embedded in Flutter. Instructor review/publication remains mandatory.
- **PASS:** cleanup denies missing credentials and accepts the configured production secret; the safe invocation cleaned zero objects. The deployed schedule is **18:00 UTC daily / 02:00 Manila**. New service-only upload/homework/deadline functions remain invoker functions, and clients cannot execute them directly. Both Storage buckets remain private.
- **PASS after promotion:** actual production native bearer retrieval returns the persisted published test homework/private instruction; the quiz assignment remains reopened with one allowed attempt, AI items remain unpublished drafts, public Storage access is denied, unsigned protected APIs return 401, and recovery does not grant readiness without verified proof.
- Final-deployment 5xx logs were queried for the staged/post-promotion window; no matching entries were returned. The initial unpromoted provider failure is recorded separately, not hidden as a production success.

Only isolated test content was added under **`TEST ONLY Release verification 1cbf353d`**, class code **`REL-1cbf353d`**, ID `f876b0b2-ae3e-4655-be6d-61c17fad843b`, owned by the existing authorized Instructor. It has **zero learner memberships**. Its synthetic files/quizzes/homework are retained for owner inspection. No new Auth user, duplicate staff account, arbitrary verified learner or existing student work was created/changed for smoke testing. The owner chose to register the learner personally.

The actual live learner-enrollment → published quiz visibility → learner submission → instructor grade → notification/read state loop has **not** been executed with that new learner. Restored-production regression tests cover those authoritative rules, and the mobile polling/refresh tests pass, but these are not a claim that the owner/device completed synchronization. Notifications are in-app; OS push is not implemented.

## SMTP and recovery limitations

Custom SMTP remains unconfigured and is **not a release gate for this owner-authorized rollout**. Supabase's default sender restricts delivery to authorized project-team recipients and is not a general production email service. Sign-up verification/resend, email invitations, magic-link email delivery and password-recovery delivery to arbitrary learners are unverified/limited. See [official SMTP guidance](https://supabase.com/docs/guides/auth/auth-smtp).

Read-only verification found **sign-up enabled and email auto-confirm already true before this rollout**. Both remain unchanged. Current learner signup is therefore not blocked by a newly enabled confirmation requirement; it does not prove email ownership or confirmation-email delivery. No confirmation setting/password policy was weakened to bypass SMTP, and no learner was administratively verified by this rollout. If confirmation is required later, external learners may be unable to complete it until delivery is configured.

The recovery UI/API and exact production `/auth/recover` redirect are present, preserving existing redirects/Site URL. Supabase rejected the secure recovery email-template update with **`entitlement_required`**: free-tier projects using the default email provider cannot modify email templates. The rejected request was verified atomic; the original template remains. The prior Auth configuration is encrypted in the recovery directory. Applying `supabase/templates/recovery.html` remains SMTP/plan-dependent. No recovery/invitation email, password reset or claim of a working production email-link lifecycle was made. Preserve the two existing staff passwords.

## New debug APK and validation

Owner copy:

`C:\Users\HP\Documents\Projects\ByteQuest\ByteQuest-Mobile-App\build\app\outputs\flutter-apk\ByteQuest-production-connected-20261113-debug.apk`

Canonical build output:

`C:\Users\HP\Documents\Projects\ByteQuest\ByteQuest-Mobile-App\build\app\outputs\flutter-apk\app-debug.apk`

| Artifact check | Result |
|---|---|
| Variant / package | Debuggable **debug**, `com.example.bytequest` |
| Version | `1.1.0`, versionCode **2** |
| Size | **202,082,029 bytes** |
| APK SHA-256 | `dce98bfa2b473183e300c9b75613d8e58f7d881988c6b4aea5613a8cfc5ab5a6` |
| Signing certificate SHA-256 | `a4d01056c847034cf2fdc199d4a5dbfa203af5e716d715f560f6db9755bd1d37` |
| Update continuity | Matches both the preserved previous debug APK and original installed-APK copy; package unchanged and prior testing artifact versionCode was 1 |
| Backend/API | Explicit production defines, bundled environment and compiled payload verified |
| Secrets | Zero configured server-secret matches across 609 entries; only public client configuration bundled |
| Device/store action | No automatic install, uninstall, data clear, release build or Play publication in this rollout |

Build command: `flutter build apk --debug --dart-define-from-file=../.tmp/rollout-20261113/flutter-production-defines.json`. That ignored file contains only the three supported public `BQ_` settings. It was generated from verified production client inputs, not a QA define file.

Fresh local gates: Flutter dependency resolution PASS; analyzer **0 errors / 0 warnings, 215 informational notices**; **480/480 Flutter tests**; debug build PASS. Web TypeScript, ESLint, **59/59 Node tests** and production build PASS; Vercel generated all 31 static pages plus dynamic routes. Existing Kotlin migration notices remain nonfatal. No app source changed after these checks; the final commit is release documentation only.

Transfer the owner-copy APK to the phone, open it in Android Files, allow installation from that chosen source if prompted, and select **Update**. This is eligible for an in-place update for the verified debug signing identity. The actual phone installation has not been inspected. If Android rejects the update, keep the existing installation/data and report the message; do not uninstall as a workaround.

## Owner manual acceptance — pending

Register the hosted learner yourself, as requested. Then:

1. Sign in to [the live Instructor Dashboard](https://bytequest-alpha.vercel.app).
2. Open an authorized test class, using the retained isolated test class above if desired.
3. Search for and enroll the newly registered test learner.
4. Publish a **new** test quiz to that class.
5. Open the updated debug APK after installing it manually.
6. Log in with that same hosted learner.
7. Refresh Home and confirm the assigned quiz appears.
8. Confirm the new quiz notification appears; open it and check that its read state survives refresh/relogin.
9. Create and publish a **new** homework assignment for that class.
10. Refresh the APK and confirm the homework/instructions appear.
11. Submit homework as the test learner.
12. Mark that submission **Graded** as the Instructor.
13. Refresh/relogin in the APK and confirm the graded state and notification.

Also test an expired quiz and Instructor reopening. Newly enrolled learners can see existing published work, but previous notifications are deliberately not backfilled, which is why the checklist publishes new items after enrollment. Manual refresh, foreground refresh and active polling support updates when Realtime is unavailable; actual owner-device behavior remains to be observed.

Private evidence is under ignored, owner-restricted `.tmp/rollout-20261113/` and the recovery directory above. It includes before/after connection checks, migration execution/freshness, staged/live staff and functional smoke checks, model probes, runtime log queries, recovery entitlement evidence, build/test logs and APK verification. Credentials, tokens, environment files, signing material and APKs remain outside Git.
