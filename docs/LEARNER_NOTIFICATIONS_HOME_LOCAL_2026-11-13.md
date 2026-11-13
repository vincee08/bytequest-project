# Learner notifications and Home — local QA delivery

Built on `7e9ffbf`, on `vince-branch`. Owner acceptance is pending. No push,
deployment, hosted Supabase/Storage write, database reset or phone installation.

## Implemented behavior

The existing Home bell opens the updated Notification Center. Its accessible
label includes the unread count; the visual badge caps at `9+`. Notifications
show their actual title/message, activity category, class, Manila timestamp and
read state. Learners can open the activity, mark one read, mark all read, filter
unread, load older pages, refresh, or retry after a network error. A failed read
write cannot navigate or falsely clear the unread state. Read times come from
PostgreSQL and remain stable on retries. Mark-all covers older unloaded rows too.

Delivery is **in-app only**. Home/Notification Center fetch when opened, on
foreground return and after navigation, offer manual refresh, and poll every
30 seconds while active/current. Home refreshes technical records every 60
seconds as well. Existing Realtime invalidation remains an optional enhancement;
the isolated QA stack does not require Realtime. Hidden tabs/backgrounded apps
do not run the polling work. OS push, FCM and APNs are not implemented.

Home has a compact greeting, summary counts, priority shortcut, separate quiz,
homework and technical sections, and All/To Do/category/Completed views. Narrow
screens use a compact selector; wider screens use category chips. All Activities
shows short section previews and explicit View all activities controls. Items
sort unfinished first, then earliest deadline; overdue unsubmitted homework
therefore comes first. Submitted quizzes and homework awaiting grading do not
count as outstanding. Completed/closed/graded items remain accessible. Quizzes
never count as official technical assessments. Technical review/release status
comes from the learner's own authoritative attempts.

Cards share restrained blue styling, spacing, status placement and 48 dp actions.
Their content wraps at large text sizes. The responsive grid uses one/two/three
columns and caps a card at 460 dp; Home caps its content at 1120 dp. One main
vertical scroll view and the existing navigation shell's reserved bottom area
keep final card actions accessible. No simulation workspace was redesigned.

## Events and authorization

| Trusted existing action | Notification | Recipients / idempotency |
|---|---|---|
| `quiz.assigned` | New Quiz Assigned | Active enrolled learners; assignment ID + recipient |
| `homework.publish` | New Homework Assignment | Active enrolled learners; homework ID + recipient |
| `assignment.created` | Technical Activity Assigned | Existing supported technical/practice assignment; assignment ID + recipient |
| `homework.graded` | Assignment Graded | Only the submitted learner; submission ID + recipient |
| `quiz.reopened` | Quiz Reopened | Only affected class; actual audit event ID + recipient |
| `quiz.deadline_changed` | Quiz Deadline Updated | Affected class, only a real deadline change |
| `homework.deadline` | Homework Deadline Updated | Affected class, only a real deadline change |

The audit trigger runs inside the existing authorized mutation transaction. It
derives recipients, source titles and class names from persisted records and
checks active instructor ownership, class status, memberships and learner
profiles. Publication/assignment retries cannot manufacture additional new
assignment alerts. Reopening retries fail the existing expired-quiz condition;
unchanged deadline updates generate no notification. The database unique index
also prevents duplicate delivery of the same stable event to one recipient.
Notification failure rolls back the instructor mutation rather than losing an
event between separate requests. No notification payload is accepted from a
learner or from an untrusted instructor-supplied recipient list.

**Late-join policy:** no historical alert backfill, including pre-migration
activities. Current lists still use live membership and show published work to
newly enrolled learners. They receive subsequent real updates. Existing read
states are not reset. Historical notices remain private to their recipient
after access revocation; their destinations independently deny revoked access.

Deep links refetch the quiz availability RPC, homework API or technical
assignment query before navigation. A quiz assigned in multiple classes resolves
to the same canonical one-attempt record, after checking access to the notice's
original assignment/class. Opening a notice never creates an attempt, reopens a
quiz, submits work or changes grading. Technical links open the selected existing
task review/launch flow. Existing submission, late-duration, immutable-deadline,
one-attempt, quiz closure/reopening and instructor-release rules are retained.

## Database and files

Applied **only** to `BQQuizQA20261112`, API `127.0.0.1:58921`, PostgreSQL port
`58922`: `supabase/migrations/20261113062554_learner_activity_notifications.sql`.
SHA-256: `499F91DCB5A2162D3E9A347B83817DD45243F3CC1195A6487820009E4DDBAC02`.

Also applied only to the same QA backend:
`supabase/migrations/20261113072038_notification_quiz_assignment_links.sql`,
SHA-256 `2E1FE520536A83186571DE4C64775712FD681115D4D54018FF54E45F68C0D52D`.
It extends the existing learner availability RPC with entitled assignment/class
references while preserving its canonical one-row-per-quiz result and existing
attempt/deadline behavior. The second-class link regression is tested directly.
Learners still cannot read staff-only quiz-version rows. No new elevated function
or weaker table policy was introduced.

The migration adds nullable `notifications.event_key`, a unique partial recipient
event index, recipient/date and unread indexes, an invoker audit delivery trigger
and an invoker read-timestamp trigger. It retains the existing own-recipient RLS
and restricted read-column update grants. No new SECURITY DEFINER function,
notification insert permission for clients, Storage change or historical backfill.
The QA runner checks the exact container/port and preserves protected row hashes.

Flutter files:

- `lib/screens/dashboard/dashboard_screen.dart`: compact Home, current technical
  status and unread refresh.
- `lib/widgets/assigned_class_activities.dart`: shared responsive cards, categories,
  priority sorting, independent quiz/homework errors and refresh.
- `lib/widgets/app_top_bar.dart`: existing accessible bell and count.
- `lib/screens/notifications/notifications_screen.dart`: functional center.
- `lib/models/learner_notification.dart`, `lib/models/home_activity_item.dart`:
  notification parsing and activity presentation/status rules.
- `lib/services/learner_notification_service.dart`: session-scoped persistent
  reads, exact unread count and bounded pagination.
- `lib/services/learner_activity_navigation.dart`: authorized activity resolution.
- `lib/services/learner_quiz_service.dart`: canonical multi-class quiz links.
- `lib/models/learner_quiz_model.dart`: authorized assignment-reference parsing.
- `lib/services/authoritative_assessment_service.dart`: own assignment states.
- `lib/services/homework_service.dart`: distinguish denied/missing activity links
  from network failures.
- `lib/screens/missions/class_details_screen.dart`: selected technical-task review.
- `lib/data/mission_content_data.dart`: new interface strings.
- `test/learner_notifications_home_test.dart`: behavior and layout regressions.

No Next product component needed changing: its existing trusted instructor
actions now deliver notifications transactionally. Updated/added local runners:
`scripts/quiz-preview.mjs`, `scripts/activity-browser-tests.mjs`, and
`scripts/notification-{db-tests,api-tests,browser-tests,owner-setup}.mjs`.
SQL coverage: `supabase/tests/learner_notifications_rollback.sql`.

## Executed validation

| Check | Result |
|---|---|
| Flutter full regression suite | PASS — 474/474, including all 20 mission regressions |
| Final affected Home/notifications/homework/quiz tests | PASS — 32/32; 16 new notification/Home cases |
| Flutter analyzer | PASS — zero errors/warnings; 214 informational lints tracked in local log |
| Next TypeScript / ESLint | PASS — no errors/warnings |
| Next production build against isolated QA | PASS |
| Dashboard Node unit tests | PASS — 49 server/general + 6 UI = 55 |
| Existing activity API/Storage groups | PASS — 7, including concurrent claims/submissions, one attempt, late submission, optional-score grading, private files and CORS |
| New notification API groups | PASS — 4: delivery/scope, concurrent retry/forgery denial, persisted reads/mark-all, real technical assignment |
| New notification SQL with controlled-clock quiz/homework lifecycle | PASS — rollback before and after QA migration, recipient isolation, duplicates, read timestamps, mark-all, revoked links, late enrollment |
| Technical assignment notification and foundation review/release SQL | PASS — rollback |
| Five existing SQL regression suites + activity SQL | PASS — rollback |
| Public/private database lint | PASS — no schema errors |
| Final Android debug compilation | PASS — explicit QA configuration; no device installation |
| Instructor + real Flutter activity browser workflow | PASS — 4 instructor/browser layout groups plus 6 real Flutter groups; text/file submission, grading, result persistence, refresh and revoked enrollment history |
| Notification/Home browser workflow | PASS — 5 groups: second-class canonical quiz link, automatic bell updates, quiz/homework/late/grading links, reopening/technical review, persisted reads and revoked-link denial; captures at 320/375/768/1440 px |
| Owner manual acceptance / physical Android / TalkBack | NOT TESTED — owner led |
| OS push delivery | NOT TESTED — not implemented or configured |

Ignored logs/screenshots are under `.tmp/notifications-*`,
`.tmp/notification-browser/` and `.tmp/activity-browser/`. Early browser selector,
preview restart and synthetic fixture issues were diagnosed; only completed
final reruns count as passing. The installed requested skill subset was used;
separate Superpowers and Flutter/Dart SKILL.md packages were unavailable, so the
repository Flutter rules and installed UI/UX Flutter guidance were followed.

Useful rerun order (each API run creates its own synthetic fixture set; never run
the older `seed` command during owner testing):

```text
node scripts/notification-db-tests.mjs
node scripts/activity-db-tests.mjs
node scripts/quiz-preview.mjs activity-tests
node scripts/quiz-preview.mjs notification-tests
node scripts/quiz-preview.mjs activity-browser-tests
node scripts/quiz-preview.mjs notification-browser-tests
```

## Local owner testing

- Instructor login: http://localhost:3008/login
- Instructor quizzes: http://localhost:3008/quizzes
- Owner class: http://localhost:3008/classes/f7c5ebd4-1844-45ad-85a9-bc05f187c410?tab=assignments
- Learner preview: http://127.0.0.1:3009
- Existing private QA account details: `.tmp/activity-owner-logins.txt` (not committed).
- New fixture IDs: `.tmp/notification-owner-setup.json` (not committed).
- New quiz, homework and technical notification fixtures are additive and leave
  the prior owner attempts/submissions and existing read states intact. Technical
  fixture content is clearly synthetic QA practice, not an official TESDA source
  or assessment. The prior future/late/no-deadline homework and expired/resumable/
  submitted quiz fixtures remain available.

Use a private browser session for each role. Restart commands are
`node scripts/quiz-preview.mjs ai-start` and, separately,
`node scripts/quiz-preview.mjs learner`. These use the isolated QA configuration;
no real AI request was made for this task. `notification-owner-setup` is additive
and idempotent; it does not recreate alerts when records already exist.

1. Open learner Home and verify the compact greeting and separate summary counts.
2. Inspect quiz, homework and technical sections; change activity views.
3. Scroll through all cards and verify the last action clears bottom navigation.
4. Check phone-width and wide browser layouts, keyboard access and large text.
5. Open the existing bell and verify the prepared actual activity notifications.
6. Mark one read and verify its count/status changes.
7. As instructor, create, approve, publish and assign a new quiz to the owner class.
8. Return to Home or refresh; active polling should discover it within 30 seconds.
9. Open its notification and verify the correct quiz, class and current deadline.
10. Confirm simply opening the notice does not consume an attempt.
11. As instructor, create/publish homework with instructions and optional files.
12. Refresh/open notifications and follow its link to the homework details.
13. Submit a written answer/file and verify Submitted for Grading after saving.
14. Use the late-homework fixture and verify submission is accepted with exact lateness.
15. As instructor, grade the submission with optional feedback and no required score.
16. Check that only the submitting learner gets Assignment Graded; open it to see Graded.
17. Reopen an expired quiz from the instructor Quizzes page with a future deadline.
18. Open Quiz Reopened and verify current eligibility; completed attempts stay locked,
    and an unfinished learner resumes the original attempt.
19. Open a technical notification and verify the selected task review, then use its
    explicit launch action only if ready; opening the notice itself starts nothing.
20. Mark all read, refresh/relogin, and verify the read state and bell persist.

Owner acceptance remains pending. Physical-device rendering/performance,
TalkBack and OS delivery are not claimed. Keep this local revision with the
previous approved work for one later explicitly authorized coordinated release.
