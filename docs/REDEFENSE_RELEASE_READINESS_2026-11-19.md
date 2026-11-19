# ByteQuest Re-Defense: Final Release-Readiness Review

**Prepared:** Thursday 2026-11-19 23:00 – Friday 2026-11-20 00:45 Manila
**Re-defense:** Monday 2026-11-23
**Scope:** read-only review before production approval. Nothing was pushed or deployed, and no production data or migration was touched.

The only call made to a hosted service was a read-only `supabase projects list`, to confirm the target project exists. There were also read-only `git ls-remote` calls to GitHub.

---

## 0. Verdict

| Question | Answer |
|---|---|
| Ready for a **local** re-defense? | **Yes.** All automated gates are green on the final code and the live local checks pass. One condition: a physical-device pass (Section 7) is still outstanding. |
| Ready for a **production** rollout? | **Not yet.** Four items block it (Section 9):<br>1. **(B1)** The 1.2.0 APK is signed with a different key than the installed 1.1.0, so it cannot update it in place.<br>2. **(B2)** No production backup exists on this machine, and the restore rehearsal has never run.<br>3. **(B3)** This machine has no Vercel access.<br>4. **(B4)** The owner has not yet approved the push and the rollout. |
| Data safety | **No migration loses learner records** (Section 5). Seven production-specific conditions could abort the apply, which is safe (it rolls back). The rehearsal and the pre-flight checks P1–P10 settle them. One product bug was found: learner account removal is blocked (B8, fail-safe). |
| Recommendation | Defend on the **local** stack. Run the production rollout only if B1–B4 are cleared by **Saturday 2026-11-21**, which leaves Sunday for smoke tests and rollback. Otherwise roll out after the defense. |

---

## 1. Repository state (item 1) — VERIFIED

| Check | Result |
|---|---|
| Current branch | `vince-branch` |
| HEAD | `00c65fc` "Add the re-defense implementation report and update the handoff state" |
| Commits since the revision base `6548cb0` | **113** at the start of this review (`git rev-list --count 6548cb0..vince-branch` = 113). This review added `c6d8081` (the local-write origin fix) and one documentation commit, so the push would now be **115** commits. |
| Working tree | Clean: there are no modified, staged or deleted tracked files. The only untracked entry is `.claude/`, which holds the harness's agent worktrees and is not part of the release. |
| Tracking | `origin/vince-branch`: **ahead 113, behind 0** |
| Live remote head (read-only `git ls-remote origin`) | `refs/heads/vince-branch` = `6548cb05` = the revision base. Nobody has pushed since, so the push would be a plain fast-forward. |

## 2. Base branch and commit (item 2) — VERIFIED

- **Revision base:** `6548cb0` "Record verified production rollout and debug APK" on `vince-branch`.
  - This is the remote head today.
  - It is also the commit the pre-revision audit, baseline gates and final review diffs were measured against.
- **Where `vince-branch` itself came from:** `vince-branch` is the repository's root line. Its history starts at `a162ecf` "Initial ByteQuest capstone project" (2026-08-19) and holds 191 commits. It was not branched from another branch in this repository.
- **The remote has no `main` or `new` branch.** `origin` (`github.com/vincee08/bytequest-project`) has exactly one branch, `vince-branch`. That disagrees with two documents:
  - `AGENTS.md` ("`main` is the stable/protected branch");
  - the older `CODEX_STATE.md` note that Vercel's production branch is `new`.
- **Consequence:** pushing `vince-branch` creates a Vercel preview deployment at most, never a production deployment. Production deployment is a separate, explicit Vercel CLI promotion.

## 3. Panel recommendations → feature → evidence (item 3)

The mapping covers the 38 checklist IDs of the audit (`docs/REDEFENSE_REVISION_AUDIT_2026-11-19.md`, Section 4), which were derived item by item from the panel's comments. The full table, with file paths and test names, is in `.superpowers/sdd/2026-11-19-redefense-revision/prerelease-panel-mapping.md`. Every test file and test name it cites exists.

| Status | Count | IDs |
|---|---|---|
| Verified (automated + live) | **19** | R2.1–R2.5 (assembly bench), R5.A–R5.G (analytics views), R7.A–R7.C (one catalog, Learn, Practice), R8 (sequential unlocking), R9.2 (Objective 2), R9.4 (Objective 4 Evaluate/Finalize/Release), **R9.6 (Objective 6, verified live during this review)** |
| Verified (automated only) | 13 | R3.1, R3.3–R3.6 (quiz organisation, AI grounding, scenario essay, one attempt/auto-submit, quiz dashboard); R4.1–R4.2 (homework authoring, learner view); R5.H (accuracy rules); R6.A–R6.B (roster import, search); R10 (publication workflow); R11.1–R11.2 (evaluator secrecy, UI fixes) |
| Partial | 6 | listed below |
| Not met | **0** | — |

**Partial items:**

- **R3.2: official LOs, not invented.**
  - All 76 performance-criteria statements and every module title appear verbatim in `TR_current.txt`.
  - However, **5 criteria cite a `source_reference` line range that does not contain their text**: LO2.1 PC 1.6 and 1.7, and LO3.2 PC 2.2, 2.3 and 2.4.
  - There is also no automated test comparing the seed with the source file.
  - Fix: a small corrective migration that updates those 5 `source_reference` values, plus a seed-against-source test. **This needs your approval, because it changes the release contents.**
- **R4.3: instructor cross-assignment view.** `/submissions` has filters, a missing-work view and grader names, but no test and no live check of them.
- **R7.D / R11.3: one progress methodology.** Each surface is tested on its own. No test ties the app's progress figure to the dashboard's figure, and populated Progress has not been checked live in the app.
- **R11.4: no new SECURITY DEFINER functions.** A scan confirms that every definer function touched is on the approved list. There is no automated guard against a future new one.
- **Phase 12: testing.** The physical device, TalkBack, hosted and restored-production passes are still outstanding.

**R9.6** moved from Partial to Verified during this review:
- The dashboard's live refresh was demonstrated live.
- An instructor released a result in the Evaluation Center.
- Without a page reload, the open analytics page changed from "2 released · 50% competent · 5 pending release" to "3 released · 66.7% competent · 4 pending release" within about 3 seconds.

**Implementation-report corrections made in this review.** The mapping found 12 claims that were inaccurate or not backed by evidence.
- 10 were wrong in the report and have been corrected in `docs/REDEFENSE_IMPLEMENTATION_REPORT_2026-11-23.md`:
  - roster import accepts `.xlsx` and `.xls`; CSV is refused;
  - 106 criteria, not 102;
  - the 39 → 43 migrations wording;
  - the suite name `simulation_assessment_sequence`;
  - the seed-versus-source claim;
  - the full publication workflow states;
  - quiz form and homework evidence wording;
  - Batch B is about 0.92 MB;
  - the dashboard real-time caveat.
- The other two, the practice-timer expiry message and the final analytics figures, were things the coordinator observed live but had not recorded. They are now recorded in the ledger.

## 4. Production rollout plan review (item 4)

**Plan:** `docs/REDEFENSE_HOSTED_ROLLOUT_PLAN.md`. It runs in 10 steps:
1. freeze and build the batches;
2. manual backup;
3. isolated restore rehearsal;
4. two-batch apply;
5. read-back;
6. Vercel deploy;
7. APK;
8. publish simulation packages;
9. demo class;
10. smoke test.

| Area | Assessment |
|---|---|
| **Migration order** | **Sound.**<br>- Batch A is `20261119130000` alone: an enum `ADD VALUE IF NOT EXISTS`, idempotent, committed first.<br>- Batch B is the other 42 migrations in timestamp order inside **one** transaction. The per-file `BEGIN`/`COMMIT` lines are stripped mechanically, with `lock_timeout` 5 s and `statement_timeout` 120 s.<br>- Guards refuse a missing Batch A or an already-applied Batch B version.<br>- The SQL fixer proved locally that Batch A + Batch B produces a schema identical to the per-file chain.<br>- `scripts/release-migration-batches.mjs` builds the manifest, so the version list is never typed by hand. |
| **Database backup** | **Gap, blocker B2.** Step 2 is manual. No repository script creates the encrypted backup. The 2026-11-13 recovery folder, key and backups are **not on this machine** (`%LOCALAPPDATA%\ByteQuest` does not exist). The DPAPI-encrypted format only decrypts for the Windows user who created it. A fresh backup must be made on this machine before step 3, and the restore rehearsal has never run here. |
| **Rehearsal** | **Good design.**<br>- Restore into a network-disabled tmpfs container.<br>- Apply the same two files.<br>- Compare every pre-existing row against the documented change list.<br>- Read back, load the QA fixture users, and run all suites.<br><br>Two caveats:<br>- The "Batch B slower than 30 s" stop is recorded but not enforced.<br>- Stop the container after a failed rehearsal, because the tmpfs holds plaintext. |
| **Rollback** | **Honest but limited.**<br>- A Batch B error rolls back automatically.<br>- **After Batch B commits, there is no in-place undo.** The realistic path is a rehearsed corrective migration. Restoring the backup means a **new** project, which changes the project URL and keys used by the app and the dashboard.<br>- So the rehearsal on a production copy is the real safety net. Do not skip it.<br>- Writes made between the backup and the apply would be lost on restore, so freeze learner and instructor writes from backup to read-back. |
| **Maintenance window** | **Required.** The old dashboard misbehaves against the new schema; for example, Finalize now needs the Evaluate step. Deploy the new dashboard right after the read-back. |
| **Vercel deployment** | **Under-specified.** The plan only says "build the exact commit and deploy". This machine has no Vercel CLI or login, and an older note records HTTP 403. Pushing `vince-branch` creates only a preview: Vercel's production branch is `new`, and that branch does not exist on the remote.<br><br>Recommended sequence:<br>1. `npx vercel@latest login`.<br>2. `vercel link --scope vincee08s-projects`; it must show project `bytequest`.<br>3. Deploy a preview with production environment variables.<br>4. Smoke-test the preview.<br>5. `vercel promote <deployment> --scope vincee08s-projects`.<br><br>Keep the previous production deployment ID for instant rollback. The build fetches SheetJS from `cdn.sheetjs.com`, so check that it is reachable. |
| **Environment variables** | **No new variables** in this revision. Check that the existing Vercel values are present. `BQ_AI_TEST_ENDPOINT` and `BQ_ISOLATED_QA` must **not** be set in production. |
| **APK release** | **Gap, blocker B1, and an ordering error.**<br><br>Signing:<br>- Step 7 builds a **debug-signed** APK on this machine. Its certificate is `271cbbf0…`.<br>- The 1.1.0 debug APK learners installed was signed with `a4d01056…`, according to `CODEX_STATE.md` for 2026-11-13.<br>- Android refuses a different signer as an update (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).<br><br>Ordering:<br>- The plan's precondition says "before step 4, tell learners to install 1.2.0", but the APK is only built at step 7.<br>- A 1.2.0 app installed **before** the migrations would call functions that do not exist yet.<br><br>Corrected ordering: build and check the production APK **before** the window, then distribute it right **after** steps 5–6. |
| **Simulation packages (step 8) and demo class (step 9)** | **Correctly gated:** publish only after learners are on 1.2.0. The packages are immutable once published, and the safety-critical thresholds are 0. The demo class creates 12 labelled synthetic accounts **in production**; that is a separate approval. |
| **Plan text** | One stale sentence: "39 files … plus the final-fix migrations on the SQL fix branch". There are now 43 merged files. It is harmless, because the manifest is authoritative. |

## 5. Migration data-loss and compatibility review (item 5)

The full report, with file:line evidence and copy-ready SQL, is `.superpowers/sdd/2026-11-19-redefense-revision/prerelease-migration-compat.md`. It covers all 43 migrations. It also checks every table, view and RPC that production's current clients call: the installed 1.1.0 APK and the old dashboard, both from the `6548cb0` era.

### 5.1 Verdict on data loss

**No migration deletes or loses learner, assessment, quiz, homework or practice records.**
- There are zero hits for `drop table`, `drop column`, `truncate` and learner-data `delete`.
- Every NOT NULL addition has a default.
- Unique indexes on legacy data are conditional.

There is one overwrite with no copy kept in the database:
- `20261119160000:197-232`: the achievements catalogue upsert rewrites unearned legacy `achievements` rows whose code matches one of the 12 new codes.
- **Export those rows before the apply.** This is pre-flight check P5.

The other documented changes to existing rows are intended:
- the mission title sync;
- COC1 M2 contract v3;
- the backfill of already-graded homework to `released`;
- audit rows;
- the achievement backfill.

The plan's "documented changes" list matches them exactly.

### 5.2 Statements that can abort Batch B on production data

These all fail safe: Batch B rolls back with nothing lost. The rehearsal on a restored copy catches them. The pre-flight checks P1–P10 settle them in advance.

| Risk | Migration | Aborts when | Pre-flight |
|---|---|---|---|
| R1 | `20261119140100:159-172` | any `submitted` homework row already has `graded_at`, `graded_by`, `score` or `feedback` set (the new lifecycle check) | P1 / P1b |
| R2 | `140100:150-152,222,583`, `120000:225` | a constraint, policy or trigger dropped by name has a different name on hosted | P2 |
| R3 | `20261119110200:14-23` | hosted `coc1_m2` is not at contract `css-sag-20261011-v2` | P3 |
| R4 | `20261119100100:40-78,246-270` | a mission code is missing (FK abort). **Worse: a missing `coc_modules` row silently skips those modules and mission links, so evidence for those missions is refused later.** Only the read-back catches this, after commit. | P4 (**must** pass before step 4) |
| R5 | `20261119160000:178-232` | `achievements` lacks a unique `achievement_code`, the condition enum lacks the 3 values, or an `icon` column with conflicting values already exists | P5 |
| R6 | any | a pre-existing object is not owned by `postgres` ("must be owner"; the 2026-11-13 rollout hit this for storage) | P8 |
| R7 | Batch B | it holds ACCESS EXCLUSIVE on `profiles`, `audit_events`, `practice_mission_actions`, `quiz_*` and `homework_*`, and SHARE ROW EXCLUSIVE on `auth.users` and `attempts`, until commit. Under live traffic it either aborts on the 5 s `lock_timeout` (harmless, retry) or stalls every login and request. | close the window to **all** traffic |

### 5.3 What breaks for production's current clients

**Installed 1.1.0 app** (affected from the moment Batch B commits):
- **B1:** saving or verifying practice on missions beyond the learner's unlocked module fails (403). The old app still shows them as open.
- **B2:** COC1 M2 practice can no longer be verified. The app sends v2 evidence and the server holds v3. Existing completions still count.
- **B3 / B4 (intended):** essay-quiz and simulation-assessment starts return `APP_UPDATE_REQUIRED`.
- **D1:** while the old dashboard is still live, its homework route hides every grade from 1.1.0.
- The 11 RPCs 1.1.0 calls keep their signatures. Its `activity_versions` reads use granted columns only.

**Old dashboard** (from the Batch B commit until the new deploy is live):
- **B5:** "Create quiz" fails with `QUIZ_FOCUS_REQUIRED` / `QUIZ_COC_REQUIRED`.
- **B6:** Finalize fails with `UNDER_REVIEW_ATTEMPT_REQUIRED`, because the old UI has no Evaluate step.
- **B7:** already-graded homework moves to `released`. The old UI then shows it as "Submitted for Grading", and grading it fails with `HOMEWORK_GRADE_LOCKED`.

**Both dashboards: product bug B8, found in this review.**
- Permanent removal of any learner who exists at migration time is refused. The backfilled `learner_module_unlocks` rows (`ON DELETE RESTRICT` to `profiles`) block profile deletion.
- The removal readiness check still says "safe", but nothing is deleted.
- It fails safe: no data loss. But account removal no longer works for those learners.
- **Fix:** a small later migration, needing approval, that extends `admin_account_removal_readiness` and the delete path to the new FKs.

### 5.4 Consequences for the rollout
- **The old dashboard is not a rollback target once Batch B commits.** Replace "Vercel instant rollback" in plan step 6 with **fix forward**. The only true rollback is a database restore, which discards every write after the apply.
- **Build the exact commit as a Vercel preview before the window**, so the `cdn.sheetjs.com` build dependency is outside it. Promote it right after the read-back.
- **Close the window to all traffic**, not only to submissions. Freeze instructors and admins until the new dashboard is live: no quiz creation, Finalize, grading or account removal.
- **1.1.0 learners must stop using the app from the start of the window until they install 1.2.0** (B1/B2). The 1.2.0 app cannot be installed early either: against the old schema it would call functions that don't exist yet. So distribute it right after the read-back and the dashboard promotion.
- **Brief instructors:**
  - attempts already `evaluated` now need the new Evaluate step (P10 counts them);
  - previously graded homework shows as Released;
  - in-progress quiz attempts auto-submit at their deadline with their saved answers.

## 6. Production targets (item 6) — VERIFIED for Supabase; Vercel only by documentation

| Target | Evidence | Status |
|---|---|---|
| Supabase project | The read-only `supabase projects list` shows the logged-in CLI account can reach `rslmteqipxqfifwftugk` "ByteQuest" (ap-northeast-1, ACTIVE_HEALTHY, Postgres 17.6.1.127). That ref is the only one in the rollout plan and tooling (`scripts/lib/recovery-archive.mjs`), and no other Supabase project ref appears anywhere in tracked files. The repository is **not linked** (`supabase/.temp/project-ref` is absent), so step 4 must run `supabase link --project-ref rslmteqipxqfifwftugk`. Check the ref printed by `supabase link` before any query. | **Verified** |
| Vercel project | According to `CODEX_STATE.md`, the project is `bytequest` (`prj_vUXjALnNCLQWzzdScvwXMfYvppga`), team `vincee08s-projects`, alias `bytequest-alpha.vercel.app`. No `.vercel/project.json` exists here, the Vercel CLI is not installed or logged in, and an earlier note records HTTP 403 with a saved credential. | **Not verifiable from this machine.** Verify at deploy time: `vercel link` / `vercel project ls --scope vincee08s-projects` must show `bytequest`. |
| Dashboard environment variables | The revision added **no new** `process.env` names: the HEAD and `6548cb0` sets are identical. Production needs the existing set:<br>- `NEXT_PUBLIC_SUPABASE_URL`<br>- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` or `NEXT_PUBLIC_SUPABASE_ANON_KEY`<br>- server-only `SUPABASE_SERVICE_ROLE_KEY`<br>- `OPENROUTER_*`<br>- `PRACTICE_OPENROUTER_MODEL`<br>- `CRON_SECRET`<br>- `BYTEQUEST_SITE_URL`<br><br>The QA-only `BQ_AI_TEST_ENDPOINT` and `BQ_ISOLATED_QA` **must not** be set in production. | Verified in code; Vercel values are unverified |
| App production defines | The app reads exactly `BQ_SUPABASE_URL`, `BQ_SUPABASE_ANON_KEY` and `BQ_PRACTICE_API_URL`. Defines override the bundled `.env`. Plain `http` is accepted only for `127.0.0.1`, `localhost` and `10.0.2.2`. | Verified |

## 7. Physical Android testing checklist (item 7)

### 7.1 Setup for a local device test, before any production change

**1. Build a device test APK** from `ByteQuest-Mobile-App`:

```
flutter build apk --debug --dart-define-from-file=../.tmp/local-web-defines.json
```

Those defines point to `http://127.0.0.1:57321` (Supabase) and `http://127.0.0.1:3001/api/learner/practice`.

**2. Connect the phone by USB** with USB debugging on, then run:

```
adb reverse tcp:57321 tcp:57321
adb reverse tcp:3001 tcp:3001
```

The phone's `127.0.0.1` then reaches the PC. The app only accepts plain `http` for loopback addresses, so a PC LAN IP will not work.

**3. Install with `adb install -r <apk>`.**
- On a phone that has the old 1.1.0, this fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` because the signing key differs (blocker B1).
- Use a test phone without ByteQuest, or uninstall it first. Before uninstalling, make sure the old app has no unsynced work.

**4. Use the local QA and demo accounts.**
- QA learner: `qa.learner1@bytequest.local`, from `.tmp/local-qa-accounts.json`.
- Demo learners: from `.tmp/demo-accounts.local.json`.
- The instructor works on the dashboard at `http://127.0.0.1:3001` or `http://localhost:3001`. Both work after fix `c6d8081`.

**5. Use two phones if possible:** one small (about 360×640 dp) and one large. Android 10 or later.

**6. Record every result:** device model, Android version, pass/fail per item, and a screenshot of each failure.

### 7.2 Checks

**A. Install and version**
1. Settings → About shows **1.2.0 (3)**.
2. Sign in and out.
3. Launch with the network off: the app does not lock you out (the version gate fails open) and shows offline states.

**B. Assembly simulation: COC1 M2, Practice mode, portrait and landscape**
1. **Tray:** a horizontal swipe scrolls the tray, and every chip is reachable, including SATA power, SATA data and the front-panel connector. A deliberate drag from a chip toward the bench drags the part. A tap selects.
2. **Work area:**
   - Inspect every part.
   - The "Wrist strap" and "Mat ground point" hotspots are labelled and respond to a tap.
3. **CPU:**
   - Rotate turns the gold marker, and the preview shows its position and the angle.
   - A wrong orientation is refused with a technical reason.
   - The lever opens and closes, then thermal compound and the cooler go on.
   - CPU_FAN versus SYS_FAN is a real choice.
4. **Memory:**
   - The latches open.
   - The notch marker rotates.
   - DIMM_A2 and DIMM_B2 seat.
   - Try every slot to confirm no drop target overlaps.
   - The latches lock.
5. **Case:**
   - The PSU fans toward the intake vent.
   - Screwdriver, then screws.
   - I/O shield.
   - Motherboard on the standoffs.
   - Drive and its screws.
6. **Cables:** all 5 connect and are drawn as routed cables.
7. **POST and review:**
   - The POST shows its measured output.
   - Record an interpretation.
   - The evidence review shows the event count.
   - Confirm, and the server verifies it.
   - Practice shows "verified" and the run count; the incorrect-attempt counter and time are correct.
8. **Pause and resume:** use Save and Exit mid-phase, force-close the app, and reopen. It resumes on the same step with the same counters, and the verified run shows sensible counts (no duplicates).
9. **Network drop:** switch airplane mode on mid-mission, do 2–3 actions, switch it off. The actions sync in order, and verification succeeds.
10. **Practice timer:** start a fresh session. The warning labels read as thresholds ("Under 10 minutes left"). At expiry the evidence is preserved and the restart offer appears.

**C. Assessment scoring:** an instructor assigns "DEMO · COC1 M2 assembly assessment", or any simulation assessment, with type **Assessment**.
1. Assessment mode shows **no** guidance, no compatible-slot highlight, no "Show me how" and **no angle**. Confirmations are neutral ("Action recorded.").
2. **Correct run:** the dashboard Evaluate queue shows the automatic score (for example 11/11). The instructor finalizes, then releases with confirmation. The learner's Progress shows the released result.
3. **Safety-critical mistake:** one wrong CPU orientation leaves C3 unsatisfied and the result is not competent. A corrected wrong DIMM pair (≤2) is still satisfied.
4. **COC4 M2 troubleshooting:** one wrong repair, a failed retest, then the fix gives competent. Trying every repair (brute force) gives not competent.
5. An instructor override needs a reason and is recorded.
6. Attempt limits (2 attempts, retry after 1 hour) are enforced.

**D. Module unlocking**
1. A new learner: Module 1 is open, and Module 2 shows a lock with "Complete Module 1 · LO1.1 … to unlock".
2. A locked mission cannot be opened.
3. Finish the required items of Module 1, then refresh: Module 2 unlocks.
4. Learn, Practice and Progress agree.

**E. Quizzes:** a timed quiz with a scenario essay.
1. The timer is visible.
2. The essay shows a word count and autosaves.
3. Background the app for 30 s and return: the answers are kept.
4. **Time expires with the network off:** the app retries and the quiz auto-submits, with no stuck "Time is up".
5. A second start is refused (one attempt).
6. Until release, the result shows "Awaiting instructor evaluation". After release it shows the points and the rubric feedback.

**F. Progress and Rewards**
1. **Progress:**
   - per-COC and per-module completion;
   - released results;
   - quiz scores (awaiting vs released points);
   - homework status;
   - the Performance section updates after an instructor release, without reopening the app.
2. **Rewards:** points, level, achievements, and the leaderboard opt-in toggle with "First name L." display.

**G. Homework**
1. Open an assignment, attach a photo or file, and submit.
2. A late submission is labelled late.
3. A grade appears only after release.

**H. TalkBack:** Settings → Accessibility → TalkBack.
1. Every control on Home, Learn, Practice, Progress and Rewards announces a meaningful label, and swipe navigation reaches everything.
2. **Bench:**
   - Select a part with a double-tap.
   - Rotate.
   - Choose a destination chip.
   - Hotspots are announced.
   - The tray scrolls with a two-finger swipe.
3. **Quiz:** the question, options, essay field and submit button are announced.
4. Dialogs such as Exit Mission and confirmations are reachable and announced.

**I. Large text, display size and reduced motion**
1. Set the largest font size and the largest display size. Nothing is clipped or overlapping on Home, Learn, Practice, Progress, Rewards, quiz or homework.
2. **Bench at the largest font:**
   - the tray chips are readable;
   - the step header does not overflow;
   - the guidance panel scrolls.
3. Turn on Accessibility → Remove animations. Transitions are minimal and everything is still usable.

**J. Old-app refusal (only if a phone still has 1.1.0)**
1. Starting a simulation assessment or an essay quiz is refused.
2. The instructor queue shows no consumed attempt.

## 8. APK (item 8)

| Check | Result |
|---|---|
| Has a 1.2.0 APK been built? | **Yes, but only as a local test build.**<br>- File: `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk`.<br>- Built from the final mobile code: merge `c76dfba`. No mobile file has changed since.<br>- SHA-256 `654081fc4a3c37286e39f9d2e8d2366fb6946862c9f2c50731b246b0d45b6537`. |
| Package and version | `com.example.bytequest`, **versionName 1.2.0, versionCode 3** (from `aapt2 dump badging`), targetSdk 36. This matches `pubspec.yaml` `1.2.0+3` and `kAppVersion = '1.2.0'` / `kAppBuildNumber = '3'`, and a test enforces that they agree. versionCode 3 is higher than 1.1.0's versionCode 2, as an update requires. |
| Backend it points to | **Local only.** It was built without defines, so it uses the bundled `.env`: `SUPABASE_URL=http://127.0.0.1:57321` and `PRACTICE_API_URL=http://127.0.0.1:3000/…`. Note the port 3000 in that file. |
| Production 1.2.0 APK | **Not built yet** (rollout step 7, which needs approval). It needs:<br>- `--dart-define` values `BQ_SUPABASE_URL=https://rslmteqipxqfifwftugk.supabase.co`, `BQ_SUPABASE_ANON_KEY=<publishable key>` and `BQ_PRACTICE_API_URL=https://bytequest-alpha.vercel.app/api/learner/practice`;<br>- the bundled `.env` replaced with production **public** values or neutral ones, so the APK carries no local endpoints;<br>- a secret scan. |
| Signing (**blocker B1**) | Debug certificate **`271cbbf03bc425bca53dff1ab35391929116c16a530df7276612275e602b9889`**, from this PC's `~/.android/debug.keystore` (created 2026-07-31). The installed 1.1.0 was signed with **`a4d01056…`**, and the production release key (`dc85ef75…`) was on another machine. Neither is here: there is no `key.properties` and no `%LOCALAPPDATA%\ByteQuest\Signing`.<br><br>Fix, choose one:<br>- **(a)** Copy the keystore that produced `a4d01056…` from the machine that built 1.1.0, then rebuild. The 1.2.0 APK then updates in place.<br>- **(b)** Accept uninstall + install. Learners keep their server data but lose on-device state, so they must sync first. |
| Update requirements | **Correct.**<br>- The server has `app_release_config.min_supported_app_version = 1.2.0` (migration `20261119150100`).<br>- 1.2.0 sends `x-bytequest-app-version: 1.2.0` on every request.<br>- The server refuses simulation-assessment and essay-quiz starts from anything lower (`APP_UPDATE_REQUIRED`), before any attempt is consumed. SQL tests cover a missing header, 1.1.9, 1.2.0, 1.10.0 and service contexts.<br>- **1.1.0 has no client gate**, so it is never prompted. Learners must be told to install 1.2.0. |

## 9. Remaining known issues, and features verified only by automated tests (item 9)

### 9.1 Fixed during this review
- **Every dashboard write was refused locally** when the browser opened `http://127.0.0.1:3001`. The error was 403 "Origin not allowed.". It affected Release, grading, assignments, roster import, uploads and more.
- **Cause:** `next start` reports the request URL as `localhost`.
- **Production was not affected.**
- **Fix:** commit `c6d8081`, with a unit test written to fail first and then pass, and dashboard gates passing (220/220).
- **Verified live:** a release from the Evaluation Center succeeded.

### 9.2 Known issues still open (none blocks a local defense)
1. **R3.2:** 5 performance criteria cite a wrong `source_reference` line range. Their text is verbatim. Needs a corrective migration, which needs your approval.
2. **Installed 1.1.0 app:** no update prompt. After the rollout it cannot answer essays, shows pending results as "0/N", hides time limits, cannot complete published lessons and cannot verify COC1 M2 v3. The server protects simulation assessments and essay quizzes.
3. **COC2 M2 PPE:** the zero-threshold safety criterion checks only the final state, so a PPE toggle is not counted.
4. **Assessment orientation:** the starting orientation is not randomised, so memorising the number of Rotate taps would work.
5. **`assign_activity`:** it does not reject a Practice assignment of an assessment-only activity on the server. The form prevents it.
6. **Archived classes:** their unreleased quiz items are hidden from the action stages, and there is no unarchive. Release before you archive.
7. **Local `.env`:** the bundled `.env` still uses practice port 3000 while the local dashboard uses 3001. This matters only for builds without defines.
8. **Docs:** `AGENTS.md` mentions a `main` branch that does not exist on the remote.
9. **Can-wait minors:** the three final-fix reports list the minors skipped as "can wait".

### 9.3 Passed automated tests only, never verified manually or live
Run these on the device (Section 7) or in a browser smoke before the defense, in order of risk.

**Learner app**
- **Assessment mode in the app**, never driven live (only Practice was): hidden guidance, neutral feedback, no angle, confirmed order.
- **Phone touch gestures on the bench:** this was the Critical fix. Also the five cables at 360×640.
- **TalkBack, large text and reduced motion.**
- **Native practice verification:** live checks used the web preview and a direct server call.
- **Scenario-essay answering and quiz auto-submit recovery:** offline expiry and a late extension.
- **Lesson completion → module unlock**, live checks used an empty account.
- **Populated Progress and Rewards in the app:** earned points, leaderboard toggle, performance refresh.
- **Homework submission from the device.**
- **The `APP_UPDATE_REQUIRED` refusal against a real 1.1.0 app.**

**Dashboard**
- **Essay rubric scoring and the homework grading UI.** The live Release worked; the scoring screens have not been clicked through.
- **Roster import end to end:** template, preview, confirm, summary, and the sign-up claim.
- **`/submissions` filters, the missing-work view and grader names.**
- **AI quiz generation with the real provider:** the tests mock it.
- **Curriculum publish and unpublish through to Learn.**

**Hosted**
- **Everything hosted:** nothing has been deployed. That includes the backup/restore rehearsal, Batch B against the Management API size and time limits, and hosted CORS for the version header (relevant to web builds only).

## 10. Dates (item 10) — VERIFIED

- **The calendar.**
  - 2026-11-19 is a Thursday (the gates and reports were dated then).
  - 2026-11-23 is a **Monday**, which matches "Re-defense: Monday 2026-11-23" in the implementation report, the design, the memory notes and `CODEX_STATE.md`.
  - The report's filename date `2026-11-23` names the defense day.
- **Demo data timing.**
  - The demo quiz is due 7 days after seeding, so a seed on 2026-11-19 means 2026-11-26 23:12 Manila. It stays **open through the defense**.
  - The demo homework deadline is 4 minutes after seeding, by design, so the on-time, late and missing examples are fixed at seed time and do not change by Monday.
  - The demo simulation assessment has no due date: 2 attempts, retry after 1 hour.
  - Analytics uses "last 30 days" by default, which still covers a Thursday seed on Monday.
  - Re-seeding nearer the defense is safe and idempotent. It refreshes the quiz deadline.
- **Live-demo timing traps.**
  - **The COC practice timer is 60 minutes per COC session.** In QA it expired mid-mission ("Practice time has ended"). Start a new timed practice session less than an hour before you demonstrate COC1 M2.
  - **Migration timestamps.** The last migration is `20261120100300`, which is dated ahead of today. Any new migration must be timestamped **after** `20261120100300`. `supabase migration new` on 2026-11-19 or 20 would generate an earlier timestamp and sort before the fix-wave migrations.

---

## 11. Items requiring your approval

| # | Item | Why it needs you |
|---|---|---|
| A1 | **Push `vince-branch`** to `origin` (`github.com/vincee08/bytequest-project`): a fast-forward of 115 local commits (113 reviewed + `c6d8081` local-write fix + this review's docs commit). | Outward-facing. It creates a Vercel *preview* deployment, not a production one. |
| A2 | **Signing decision (B1).** Either supply the keystore that signed 1.1.0 (`a4d01056…`) for an in-place update, or accept that learners must uninstall 1.1.0 before installing 1.2.0. | Only you or your teammates have that keystore. Uninstalling loses on-device state. |
| A3 | **Production backup (B2).** A fresh encrypted logical backup of `rslmteqipxqfifwftugk` on this machine, then the isolated restore rehearsal. | It reads all production data. The DPAPI-bound backup can only be decrypted by this Windows user. |
| A4 | **Vercel access (B3).** `npx vercel login` with an account on team `vincee08s-projects`, or a teammate who deploys the given commit. | Credentials are yours. |
| A5 | **Rollout steps 4–7.** Batch A, Batch B, the read-back, the dashboard promotion and the production APK, inside an announced maintenance window. | Production writes. |
| A6 | **Steps 8–9.** Publish the 20 immutable simulation packages, and create the demo class with its 12 synthetic accounts **in production**. | Production data. Run them only after learners confirm 1.2.0. |
| A7 | **Optional, before rollout:** a corrective migration for the 5 wrong `source_reference` line ranges (R3.2), plus a seed-versus-source test. | It changes the release contents, so the rehearsal runs again. |
| A9 | **Recommended before rollout:** fix B8 (learner account removal is blocked by the new module-unlock rows) with a small additive migration and a test. | It changes the release contents, so the rehearsal runs again. Without it, admin learner removal stays refused (fail-safe). |
| A10 | **Run the pre-flight checks P1–P10 on the restored production copy** and export the achievements rows from P5 before step 4. | They read production data, on the restored copy only. |
| A8 | **Defense mode:** local stack (recommended) or production. | Your call, and it depends on A1–A6 timing. |

## 12. Outstanding risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| **Installed 1.1.0 phones cannot be updated in place** (signer mismatch) | Certain unless A2(a) is done / high | Get the original keystore, or plan an uninstall + install with a "sync first" notice. |
| **Batch B has no in-place undo once committed** | Low if rehearsed / high | Rehearse on the restored production copy (step 3). Freeze writes from the backup to the read-back. Keep the backup. Fix forward with a rehearsed corrective migration. |
| **The production rehearsal has never run, and Batch B (≈0.92 MB) may exceed the CLI/Management-API request limits** | Medium / delays the rollout | Do step 3 first. If the size is refused, use a direct DB connection, which needs the database password, and never split the batch. |
| **The old dashboard and the 1.1.0 app run against the new schema during the window** | Certain during the window / medium | Maintenance window. Deploy the new dashboard right after the read-back. Distribute 1.2.0 right after that. |
| **Features verified only by automated tests** (Section 9.3), especially assessment mode in the app, phone touch on the bench, and TalkBack | Medium / visible at the defense | Run the Section 7 device pass before Monday. |
| **The COC practice timer expires mid-demo** (60 min per COC session) | Medium / embarrassing | Start a fresh timed practice session less than an hour before demonstrating. |
| **A new migration created now would sort before the fix-wave migrations** | Low / ordering bug | Timestamp any new migration after `20261120100300`. |
| **Vercel production branch `new` does not exist on the remote** | Low / confusion | Deploy production by explicit CLI promotion only. |
| **Local demo uses `127.0.0.1` vs `localhost`** | Fixed by `c6d8081` | Both addresses now work locally. |
| **Batch B aborts on production-specific data or names** (R1–R6) | Unknown until the pre-flight checks / safe (rollback) | Run P1–P8 on the restored copy, then the rehearsal. R4 (a missing `coc_modules` row) is the dangerous one, because it commits silently with links missing. P4 must pass. |
| **The old dashboard breaks after Batch B** (B5–B7), so there is no dashboard rollback | Certain in the window / high | Promote the pre-built preview immediately after the read-back, and fix forward. |
| **Learner account removal blocked** (B8) | Certain for pre-existing learners / low (fail-safe) | Approve the A9 fix, or tell admins. |

## 13. Backup and rollback requirements

1. **Before anything else:** a fresh encrypted logical backup of `rslmteqipxqfifwftugk` (schema, data, roles, Auth/Storage metadata) in the 2026-11-13 recovery format, stored owner-only under `%LOCALAPPDATA%\ByteQuest\Recovery\rslmteqipxqfifwftugk-<date>-redefense`. Record SHA-256 digests and per-table row counts.
2. **Prove that the backup restores** (rehearsal step 3):
   - restore into the network-disabled tmpfs container;
   - apply Batch A then Batch B;
   - compare every pre-existing row;
   - read back;
   - run all 41 suites with the SQL QA fixtures.

   Stop the container afterwards.
3. **Freeze writes from the backup to the read-back:**
   - learners are told not to submit;
   - instructors and admins take no dashboard actions;
   - a short announced window.
4. **Keep the previous Vercel production deployment ID** before promoting. Rollback is `vercel rollback` / promote the old deployment.
5. **Database rollback, in order of preference:**
   - **(a)** A Batch B failure rolls back automatically: fix, re-rehearse, retry B.
   - **(b)** A defect found after commit: a rehearsed corrective, additive migration.
   - **(c)** A severe defect: restore the backup into a **new** project and repoint the dashboard environment and the app defines, which means a new APK.

   Never use destructive edits of learner history.
6. **App rollback:** none in place. The previous APK cannot run the new features. Keep the 1.2.0 APK and its SHA-256 for redistribution.

## 14. Recommended deployment sequence (only after your explicit approval)

0. **Decide the defense mode.** If production is not live by **Saturday 2026-11-21 evening**, defend locally and roll out after the defense.
1. **Freeze and prepare (no production change).**
   - Confirm HEAD is green: the gates are already green at `c6d8081`.
   - Run `node scripts/publish-simulation-assessments.mjs --dry-run` and `node scripts/release-migration-batches.mjs --out .tmp/release-redefense`.
   - Build the **production APK now**:
     - with production defines and a production-safe `.env`;
     - signed with the 1.1.0 keystore if available (A2);
     - verify `aapt2` 1.2.0/3, the certificate, the defines, and a secret scan.
2. **Device pass (Section 7)** on the local stack with the local test APK. Fix anything blocking.
3. **Push `vince-branch`** (A1). Check the Vercel *preview* build succeeds.
4. **Backup (A3)**, then the **isolated restore rehearsal**: Batch A + Batch B + row comparison + read-back + suites. Any failure means stop; production stays untouched.
5. **Announce the maintenance window and close it to all traffic.** Learners close the app and stop using 1.1.0 until 1.2.0 is out. Instructors and admins close the dashboard. Have the Vercel preview of the exact commit already built and smoke-tested (step 3). Run the pre-flight checks P1–P10 on the restored copy and export the P5 achievements rows (A10).
6. **Apply Batch A, then Batch B** (`supabase link --project-ref rslmteqipxqfifwftugk`, then `supabase db query --linked -f …`). First check the batch SHA-256 against the manifest and the rehearsal evidence.
7. **Read-back** (`scripts/release-readback.sql`). Every expected value must match.
8. **Vercel:** **promote** the pre-built, smoke-tested preview right after the read-back. Keep the old deployment ID for the record, but after Batch B the rule is **fix forward**: the old dashboard is not a working fallback (B5–B7).
9. **Distribute the 1.2.0 APK immediately**, with the signing decision from A2, and post the notification. Learners install it before using ByteQuest again. Wait for confirmation before step 10.
10. **Publish the 20 simulation packages** (step 8; `--dry-run` must show `"drift": []` first). Then the **demo class** (step 9) if you want it in production.
11. **Live smoke test (step 10)**, on the dashboard and on a phone. End the window.
