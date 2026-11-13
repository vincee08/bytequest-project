# Local quiz and homework integration — 2026-11-13

Implementation and automated local verification: **PASS**. Owner manual acceptance: **NOT TESTED / pending owner confirmation**. This is not a production release or production-readiness claim.

## 1. Exact quiz visibility cause and fix

The issue was reproduced in the existing isolated QA database, not attributed to a hosted/local mismatch:

- Class: `sample class A`, `9e029e59-81b1-4963-82d9-3943df536f1a`.
- Published quiz: `sample quiz`, version **2**, version ID `f2bbd68f-e118-45b8-b246-ed8766968115`.
- Persisted class assignment: `ac99155f-5955-4760-a166-3c34e014e071`.
- One active learner membership. The original learner availability RPC returned this exact assignment, `is_available: true`, three approved questions, and no previous attempt.

Home loaded only official technical activity assignments; the class list inferred classes from those assignments and resources. The class detail page likewise omitted supplementary quizzes. A separate quiz screen already existed behind a Learn-page button. Zero technical assignments therefore obscured a valid quiz assignment and, for a quiz-only class, could omit the class entirely.

Home and class detail now expose **Assigned Quizzes** and **Homework Assignments** separately. Class discovery uses active learner memberships, including classes with no technical assignments or resources. Technical assignment counters remain separate and are labeled accordingly. Quiz cards show class, deadline, one-attempt status, Start/Continue/View Result or Closed. Learner contracts and screens do not expose AI provenance. The original Sample Class A quiz still has **zero attempts** after this work.

## 2. Homework creation, submission and grading

- Instructor: **Classes → class → Assignments → Create Assignment**. Save a draft with title, instructions, target class and optional Manila date/time. Add private instruction files, edit unpublished content, then explicitly publish. Publishing a quiz never creates homework.
- Learner: open homework from Home or the class, read instructions, download authorized instruction files, complete work outside ByteQuest, enter an answer and/or upload completed files, review, then Submit Assignment.
- Text-only, file-only and combined submissions are supported and tested. Supported files are PDF, JPG/JPEG, PNG, WebP and UTF-8 TXT, up to **10 MiB each / five files**. MIME, extension, content signature/text and streamed body size are validated before Storage upload.
- Submission success appears after backend persistence. A database unique key and assignment row lock enforce one immutable submission per learner/homework. Retries return the existing submission; concurrent requests cannot create duplicates. A local draft is scoped to learner and homework, while submitted records and grading persist in PostgreSQL across refresh/relogin.
- Instructor workspace lists submitted and unsubmitted learners, text, files, submission time, applicable deadline, on-time/late metadata, optional feedback and optional 0–100 score. **Mark Graded** records instructor ID and server grading time. No numeric score is required; there is no AI homework grading or automatic late penalty.
- Visible workflow: **Assigned → Submitted for Grading → Graded**. Late metadata is separate. Published instruction/content edits are blocked; authorized deadline changes remain available.
- RLS-scoped Realtime invalidation includes homework. Visible published instructor workspaces and learner views also refetch every 20 seconds, supporting the minimal QA stack without its optional Realtime container. Refresh and app resume fetch authoritative records. Pending draft inputs are preserved.
- Historical submission names remain available to the authorized class instructor after membership removal through a narrow server-only profile projection. Its input IDs come only from the already-authorized class membership/submission records; general profile RLS is unchanged.

## 3. Homework deadline and lateness semantics

Homework remains submittable after its deadline. The submission transaction locks its assignment, samples server time, snapshots `effective_deadline_at` and the deadline revision, then inserts once. A generated numeric column computes:

```text
lateness_seconds = deadline absent ? 0 : max(0, submitted_at - effective_deadline_at)
```

At the exact homework deadline, lateness is zero. Later deadline edits affect future submissions and retain prior audit values; existing submission snapshots and lateness do not change. UTC timestamps are displayed explicitly in **Asia/Manila**, independent of browser/device timezone. Duration formatting retains days, hours and minutes; positive sub-minute lateness is shown as “Less than 1 minute.”

The learner sees **Deadline Passed — Late Submission Allowed** before submission, **Submitted for Grading** after it, and a separate **Late by …** indicator. The instructor sees both the submission/grading state and exact lateness. A controlled-clock test records exactly **2 days, 6 hours, 15 minutes** and verifies that a later deadline edit does not rewrite it.

## 4. Quiz deadlines, reopening and one attempt

- Optional deadline picker during publication/assignment, plus class-specific **Set deadline** controls in the quiz library, Publishing tab and class page. Existing versions and assignments are retained.
- Quiz taking requires server time **strictly before** the selected assignment deadline. At equality and afterward, start, answer-save and submission RPCs reject taking. Device timestamps are not accepted as authority.
- Assignment share locks serialize learner operations with deadline edits. Final server-time availability checks occur after waiting for locks and immediately before admission. Start/answer/submission timestamps use that checked admission time, rather than a potentially old transaction-start timestamp. A submission admitted before the cutoff can finish atomic evaluation afterward; a request admitted at or after cutoff cannot submit.
- Expiry is an availability state (`closed_reason: deadline_passed`); an unfinished original attempt and saved answers remain intact. Expiry does not fabricate a submission, result or grade. Flutter disables answer/submission controls with a server-calibrated relative timer and rechecks availability periodically and after resume.
- **Reopen Quiz** is directly visible for expired published class assignments. Its dialog shows quiz, affected class and previous deadline, requires a new future deadline, and confirms reopening without a publication reason.
- Reopening updates only that class assignment. It records actor, quiz, class/assignment, previous/new deadline and reopening time in the append-only audit. Never-started learners can take their first attempt; unfinished learners resume the same original attempt; submitted learners cannot retake.
- Existing private `(learner_id, quiz_id)` canonical claims, insert guard and exactly-once result handling remain authoritative across devices, classes, version changes, relogin and reopening. Manual and AI authoring share these same protections. The original single-attempt and resource/AI migrations are unchanged.

## 5. Backend and Storage changes

Both migrations were applied **only** to `supabase_db_BQQuizQA20261112`, API `http://127.0.0.1:58921`, database port `58922`, after rollback rehearsals. Target guards reject the primary stack and hosted environments. Application data was not reset or deleted.

| Migration | Purpose | SHA-256 |
|---|---|---|
| `20261113024352_homework_and_quiz_deadlines.sql` | Independent homework records, scoped reads, trusted writes, private files, quiz cutoff/reopening | `FA7B11FE01E10FD231A5E4377BD047992D92C87687EC60CB1AB9320FE208BE36` |
| `20261113031014_quiz_deadline_admission_timestamps.sql` | Final locked admission checks and accurate quiz start/answer/submit timestamps | `12553B3C0C2F23E2D8ECE01904ADEDCD02186616B5075BE875817FE754AF5547` |

New tables: `homework_assignments`, `homework_submissions`, `homework_files`. All retain RLS and expose scoped SELECT only to authenticated clients. New write RPCs `manage_homework` and `set_quiz_assignment_deadline` are **SECURITY INVOKER**, callable only by the server service role. They independently validate the active persisted actor role, owned active class and/or active learner membership. HTTP endpoints derive the actor from a verified Supabase session, rejecting supplied grading statuses or timestamps. No new SECURITY DEFINER function was added.

The private `homework-files` bucket has scoped read policies and no client write/update/delete policy. Signed downloads expire after two minutes and require current authorization to create. Upload retries use a content-addressed identity; existing objects cannot be overwritten. An uncertain upload/metadata response is not followed by a destructive delete that could race a successful retry. Unreferenced objects remain private; automatic orphan cleanup is intentionally absent. The final QA check found **zero unreferenced homework Storage objects**.

The targeted migration applications checked unchanged row-content hashes for protected profiles, classes, memberships, technical assignments, quiz assignments/content/attempts/answers/results and resources. Original Sample Class A data remains present. All public base tables still have RLS, and the three new helper/write functions are invokers.

## 6. Main files/components changed

| Area | Files |
|---|---|
| Instructor/class UI | `src/components/classes/HomeworkManager.tsx`, `HomeworkWorkspace.tsx`; `src/app/classes/[id]/page.tsx`; new `classes/[id]/assignments/[assignmentId]/page.tsx` |
| Quiz UI | `QuizDeadlineControls.tsx`, `QuizLibrary.tsx`, `QuizAuthoringWorkspace.tsx`; quiz library/detail pages |
| Server contracts | `src/app/api/activities/{homework,files,quiz-deadline}/route.ts`; `src/lib/activities/{server,types,dates}.ts`; existing generated publication signature |
| Dashboard refresh | `src/components/realtime/RealtimeRouteRefresh.tsx` |
| Learner UI | `lib/widgets/assigned_class_activities.dart`; `screens/homework/homework_details_screen.dart`; Home, class, membership discovery and quiz listing/briefing/taking screens |
| Learner data/services | `models/homework_model.dart`, extended quiz model; `services/homework_service.dart`, learner Realtime coordinator; centralized `mission_content_data.dart` labels |
| Local preview/assets | `scripts/quiz-preview.mjs`; approved Plus Jakarta Sans font weights and SIL license in `assets/fonts/`; pubspec/lock and generated macOS plugin registration |
| Verification | `scripts/activity-{api-tests,browser-tests,db-tests,owner-setup}.mjs`; controlled-clock SQL; Flutter homework/deadline tests; Node date tests; isolated fixture improvements to existing rollback tests |

No COC mission definitions, simulation interactions, official grading logic or instructor-release rules were redesigned.

## 7. Automated verification

| Gate | Result | Executed evidence |
|---|---|---|
| Flutter dependencies | **PASS** | Online resolution after process-local desktop-plugin setting; final cached/offline resolution |
| Flutter analyzer | **PASS** | Exit 0, zero errors/warnings, 217 existing infos |
| Full Flutter suite | **PASS** | **458/458**, final rerun includes bundled fonts and all 20 mission regressions |
| Focused learner workflow tests | **PASS** | **16/16**, including failure-before-success behavior, large text, separate lists and server-calibrated expiry |
| Android debug APK | **PASS** | Final normal cached build, explicit QA defines; font assets verified in APK. No device installation/launch |
| TypeScript / ESLint | **PASS** | No type errors or lint warnings/errors; final Next build repeats both checks |
| Node unit/component tests | **PASS** | **55/55**: 49 TypeScript tests plus six React/prerender tests |
| Next production build | **PASS** | 27 static pages plus dynamic activity endpoints and homework workspace; local production server running |
| Existing quiz API regressions | **PASS** | **10 groups**: four question types, review, publication, 16 concurrent starts, second-device/relogin, 12 concurrent submissions, republication and revoked access |
| New activity API + Storage | **PASS** | **Seven groups**: visibility, exact authorization paths, deadline closure, reopening, private uploads/downloads, text/file/both submissions, lateness snapshots, optional score, grading, concurrency, forged status/timestamp rejection, local CORS |
| Dashboard + real Flutter browser E2E | **PASS** | **Ten groups**: homework authoring/files/publish/roster; grading; library reopening; four responsive widths; real learner login/quiz visibility; real quiz take/submit/instructor result; real homework text/file/review/submit; instructor auto-refresh/grade and learner Graded; refresh/session persistence with QA origins; historical learner identity |
| Isolated PostgreSQL | **PASS** | Controlled-clock activity lifecycle plus five existing rollback suites: quiz claims, quiz lifecycle, foundation assessment/release, resource/AI and enrollment |
| Database lint/security checks | **PASS** | Public/private lint clean; zero public tables without RLS; zero new definer functions; zero homework orphan objects |
| Original frozen migrations | **PASS** | Single-attempt hash `08FEEBBC…94701`; resource/AI hash `CC24CCAE…8A671`, unchanged |
| Owner manual acceptance | **NOT TESTED** | Owner performs and confirms acceptance |
| Physical Android/TalkBack | **NOT TESTED** | No physical application was installed or launched |
| Live QA Realtime transport | **NOT TESTED** | Optional QA container remains stopped; 20-second authoritative refresh fallback tested in both directions |
| Hosted migration/deployment | **NOT TESTED / not authorized** | No hosted Supabase/Storage operation, production migration, deployment or push |

Initial failed checks were corrected and rerun: timestamp regression; older SQL fixtures assuming an empty QA database; browser hydration/slow development compilation and Flutter semantics selectors; external CanvasKit/font DNS; and Android dependency downloads. Final build used real Google font assets with a temporary build-process resolver; no system DNS configuration was changed. Final Android rebuild succeeded normally after dependencies were cached. The pre-existing Kotlin/SDK compatibility warnings remain non-fatal.

Logs and screenshots are ignored local artifacts under `.tmp/activity-*` and `.tmp/activity-browser/`. They are evidence of automated checks, not owner acceptance.

## 8. Working local owner QA

- Instructor login: **http://localhost:3008/login**
- Prepared class/assignments: **http://localhost:3008/classes/f7c5ebd4-1844-45ad-85a9-bc05f187c410?tab=assignments**
- Quiz library/reopening: **http://localhost:3008/quizzes**
- Learner preview: **http://127.0.0.1:3009**
- Existing Sample Class A: **http://localhost:3008/classes/9e029e59-81b1-4963-82d9-3943df536f1a?tab=assignments**
- Private QA account details: ignored **`.tmp/activity-owner-logins.txt`**. Existing passwords/accounts were reused. No credentials are in this report or Git.
- Public fixture IDs/URLs: ignored **`.tmp/activity-owner-setup.json`**.
- Sample instruction/completed-file input: **`.tmp/homework-network-instructions.txt`**. A tiny synthetic PDF from earlier work is also retained at `.tmp/bytequest-sample-networking.pdf`.

Prepared class: **Owner Quiz & Homework QA**. Its three homework assignments are **Owner — Network Inspection Homework**, **Owner — Late Homework Allowed**, and **Owner — No Deadline Homework**. All are published with private instruction attachments, and remain unsubmitted for owner testing.

Prepared quizzes:

| Quiz | Prepared owner state |
|---|---|
| Owner — One Attempt Quiz | No deadline; both QA learners have an unused first attempt |
| Owner — Reopen & Resume Quiz | Expired; `learner` has never started, `resumeLearner` has an unfinished original attempt with a saved answer |
| Owner — Submitted Result Stays Locked | Expired; `learner` has a persisted submitted result; reopening must not grant a retake |

Automated browser runs use separate synthetic Activities QA classes and accounts. They do not consume the prepared owner homework or the first owner quiz.

### Owner checklist — pending confirmation

- [ ] Sign in to Instructor and learner with the local QA accounts. Home shows separate quizzes/homework, and Learn → Classes includes the prepared class. Check the original Sample Class A with its original enrolled learner as desired.
- [ ] Start **One Attempt Quiz**, answer, review and submit. Confirm instructor Results and learner View Result, then refresh/relogin and verify no retake.
- [ ] Set a near-future deadline on a fresh/unused quiz assignment, start an unfinished attempt, let the deadline pass, and verify answer/submission closure. Saved work must remain intact.
- [ ] Reopen **Reopen & Resume Quiz** with a future Manila deadline. Confirm `learner` can use the first attempt and `resumeLearner` continues its original saved attempt.
- [ ] Reopen **Submitted Result Stays Locked** and confirm `learner` still has View Result and no retake. Check another class's deadline remains unchanged.
- [ ] Create a homework draft, edit instructions, attach a file, set a deadline, and publish to the prepared class. Verify learner instructions and authorized file download.
- [ ] Submit text only, a completed file only, and both on different homework/learner combinations. Confirm review precedes submission and status becomes Submitted for Grading only after saving.
- [ ] Submit **Late Homework Allowed**, confirm it is accepted and displays exact days/hours/minutes separately from Submitted for Grading. Check no-deadline and future-deadline homework too.
- [ ] Open the submission as Instructor, read/download its answer/files, enter optional feedback or score, and Mark Graded. Confirm learner Graded after refresh or the automatic refresh interval.
- [ ] Change an assignment deadline after a submission and confirm the recorded applicable deadline/lateness is unchanged. Verify a foreign class/account cannot access the work or files.

### Local restart / repeat checks

```powershell
node scripts/quiz-preview.mjs ai-start
# In a separate terminal:
node scripts/quiz-preview.mjs learner
```

`ai-start` retains the existing ignored private AI configuration; no new real provider request was made by this task. The learner launcher explicitly uses QA 58921, practice API 3008, local CanvasKit and bundled fonts.

```powershell
node scripts/activity-db-tests.mjs
node scripts/quiz-preview.mjs activity-tests
node scripts/quiz-preview.mjs activity-browser-tests
node scripts/quiz-preview.mjs quiz-regression
node scripts/quiz-preview.mjs activity-owner-setup
```

Run `activity-tests` before a fresh full `activity-browser-tests` run: it provisions separate synthetic fixtures without deleting previous history. Owner setup is idempotent and preserves existing work. Do not run the older `seed` command during owner UAT; it would replace the private preview-account fixture file with a different fixture set.

## 9. Git and remaining work

Changes are local on **vince-branch**. A scoped local commit is recorded in the final delivery; no push, deployment or hosted write is authorized or performed. Pre-existing untracked `.agents/`, dashboard `package-lock.json`, copied PDF, `skills.md` and `skills-lock.json` are preserved and excluded.

No reproduced product blocker remains in the implemented local workflows. Remaining gates are owner manual acceptance, physical accessibility/device checks if desired, and any separately authorized future coordinated release. Automatic orphan cleanup and live Realtime transport are not claimed as tested features. This work does not finalize the overall dashboard release.
