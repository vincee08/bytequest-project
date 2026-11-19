# ByteQuest analytics — metric definitions (Objective 6)

Objective 6: "Create a performance analytics dashboard which allows learners and instructors to monitor learner progress, competency achievement, scores and assessment results in real time."

Every number on `/analytics`, `/progress/learners/[userId]`, `/admin/analytics` and in the app's Performance section comes from one of the PostgreSQL functions below. All of them are `STABLE SECURITY INVOKER`: they aggregate only rows the caller can already read under row-level security, and they never write data.

| Function | Used by |
|---|---|
| `get_analytics_filter_options()` | filter bar options (classes, COCs, modules, topics, missions, quizzes, learners) |
| `get_analytics_overview(p_filters)` | Overview tab, admin overview |
| `get_class_performance(p_filters)` | Classes tab |
| `get_learner_performance(p_filters)` | Learners tab |
| `get_learner_profile_analytics(p_learner, p_filters)` | learner profile page |
| `get_quiz_analytics(p_quiz_id, p_filters)` | Quizzes tab (summary list + one quiz) |
| `get_mission_analytics(p_filters)` | Missions tab |
| `get_criteria_analytics(p_filters)` | Criteria tab |
| `get_my_performance()` | learner app, Performance section |

Source: `supabase/migrations/20261119170000`–`20261119170400` (170400: integration with slices A2, A4 and A5). Tests with known expected values: `supabase/tests/analytics_redefense_rollback.sql`.

## 1. Scope, population and period

**Filters** (`p_filters` JSON object): `class_id`, `coc_code` (`coc1`–`coc4`, case-insensitive), `module_id`, `topic_id`, `mission_code` (`coc1_m1`…), `quiz_id`, `learner_id`, `from`, `to` (ISO dates or timestamps). Unknown keys, malformed UUIDs/dates, unknown COC/mission/module/topic, `from` after `to`, and periods longer than 366 days are rejected with `ANALYTICS_FILTER_INVALID`. A class, quiz or learner outside the caller's scope is rejected with `ANALYTICS_SCOPE_DENIED`. Callers that are not an active instructor or admin get `ANALYTICS_ACCESS_DENIED` (the learner function requires an active learner: `ANALYTICS_LEARNER_REQUIRED`).

**Class scope.** Instructors: the active classes they own. Admins: every active class. `class_id` narrows to one class. Archived classes are not analysed.

**Population.** Learners with an active membership in a scoped class (`class_memberships.status = 'active'`, profile role learner). A learner enrolled in two scoped classes is counted **once** in every population count and average.

**Period.** Default: the last 30 days ending now. The dashboard presets are 7, 30, 90 and 365 days or a custom range (Asia/Manila calendar days). How each source is attributed to the period:

| Source | Attributed by |
|---|---|
| Technical assessment attempt | `submitted_at` (`started_at` while unsubmitted) |
| Quiz result | `submitted_at` |
| Quiz eligibility | the quiz assignment was open at some time in the period (opened on/before the period end, not due/closed before the period start) and the learner was enrolled (`class_memberships.enrolled_at`) before it closed |
| Homework submission | `submitted_at` |
| Homework eligibility | published by the period end and not due before the period start; a learner enrolled after the deadline is eligible only if they submitted |
| Missing homework | the deadline passed inside the period (and before now) without a submission, for learners enrolled before the deadline |
| Practice run | `ended_at` (or `created_at`) |
| Practice completion (verified) | `verified_at`; completion *rates* use every completion verified by the period end |
| Learning progress | completions recorded by the period end (cumulative) |

**Curriculum filters** (COC, module, topic, mission, quiz). A record is included only when it is positioned at every curriculum filter that is set. Sources that cannot be positioned on a filter are excluded and reported with `applicable: false` (the dashboard says "Not linked to this filter" instead of showing zero):

| Source | Can be filtered by |
|---|---|
| Technical assessments | COC, module (mission's module), mission |
| Quizzes | COC (quiz COC), quiz |
| Homework | COC (`coc_module_id`, or the module's / mission's COC), module (`module_id`, or the mission's module), mission (`mission_code`); unlinked homework is excluded under any curriculum filter |
| Practice runs/completions | COC, module, mission |
| Learning progress | COC, module, topic, mission |

## 2. Overview

| Metric | Formula | Source tables |
|---|---|---|
| Enrolled | distinct population learners | `class_memberships`, `profiles` |
| Active in period | population learners with any recorded learning activity in the period (assessment or quiz attempt, homework submission, practice run or completion, topic completion) | `attempts`, `quiz_attempts`, `homework_submissions`, `practice_mission_runs`, `practice_mission_completions`, `learner_topic_progress` |
| Completed | learners whose learning progress is 100 % of the required items in scope | see §7 |
| Assessments: released | assessment attempts in the period with a current `result_releases` row | `attempts`, `assignments` (type `assessment`), `result_releases`, `score_revisions` |
| Assessments: pending release | submitted assessment attempts in the period with no current release (`submitted`, `evaluated`, `under_review`, `finalized`) — never part of any average | same |
| Assessments: average | mean of released `score_revisions.percentage` | same |
| Assessments: competent rate | competent ÷ (competent + not yet competent) among released results | same |
| Quizzes: submitted | counted quiz attempts in the period (see §5) | `quiz_attempts`, `quiz_versions`, `quiz_results` |
| Quizzes: average | mean percent of scored counted attempts (`correct_count ÷ question_count × 100`) | `quiz_results` |
| Quizzes: completion rate | completed (learner, quiz) pairs ÷ eligible (learner, quiz) pairs | `quiz_assignments`, `quiz_attempts` |
| Homework: submitted / late | submissions in the period / of which `lateness_seconds > 0` | `homework_submissions` |
| Homework: released / pending evaluation | submissions in the period whose status is `released` / `submitted`, `graded` or `finalized` (pending evaluation never enters an average) | `homework_submissions` |
| Homework: missing | eligible pairs whose deadline passed in the period without a submission | `homework_assignments`, `homework_submissions` |
| Homework: average | mean of `score ÷ max_score × 100` over **released** submissions in the period; graded or finalized grades, released work without a score and missing work are never turned into a number | `homework_submissions`, `homework_assignments` |
| Evaluation status | technical assessment attempts and homework submitted in the period, by their current stage. Technical: `submitted`/`evaluated` → Evaluate, `under_review` → Finalize, `finalized` → Release, `released` → Released. Homework: `submitted` → Evaluate, `graded` → Finalize, `finalized` → Release, `released` → Released (the Evaluation Center mapping) | `attempts`, `homework_submissions` |
| Missions: verified | server-verified practice completions (accepted contract version, `practice_completion_accepted`) in the period | `practice_mission_completions` |
| Missions: completion to date | verified (learner, mission) pairs by the period end ÷ (population × missions in scope) | `practice_mission_completions`, `mission_curriculum_links` |
| Missions: runs / successful / failed | recorded practice runs in the period / outcome `verified` / outcome `incomplete` | `practice_mission_runs` |
| Missions: average completion time | mean `duration_seconds` of verified runs in the period | `practice_mission_runs` |
| Learning progress | mean over population learners of each learner's learning progress (§7) | see §7 |
| Daily trend | per Manila calendar day: assessment submissions, quiz submissions, homework submissions, practice runs, verified completions | as above |

## 3. Classes

Assessment, quiz and homework results belong to the class of the attempt or submission. Practice and learning progress belong to the learner and therefore appear in every class the learner is enrolled in.

| Metric | Formula |
|---|---|
| Enrolled / active in period | as in the overview, for the class |
| Learner performance score | mean of the learner's scored results in the class and period: released assessment percentages, quiz percentages, released homework percentages of `max_score` (each result once) |
| Average score | mean of learner performance scores in the class (each learner once; learners without a scored result are excluded) |
| Highest / lowest | learner with the highest / lowest performance score in the class |
| Quiz average | mean quiz percent of the class's counted attempts |
| Assessment competent rate | as in the overview, for the class |
| Mission completion rate | verified (learner, mission) pairs of class members ÷ (members × missions in scope) |
| Assignment completion rate | submitted ÷ eligible homework pairs of the class |
| Progress average | mean learning progress of class members |
| Summary | the same metrics over the distinct population of all selected classes (never an average of class averages) |

## 4. Learners and status rules

Per learner: learning progress, performance score, quiz average, released/competent/pending assessments (`evaluated` and `under_review` are pending), verified missions, practice runs in the period, homework submitted/pending evaluation/missing/late, last activity.

| Status | Rule (any reason triggers it) |
|---|---|
| **Falling behind** | no recorded learning activity for **14 days** before the period end (counted from enrolment if the learner has none), **or** learning progress below **half of the class median** (the highest median among the learner's scoped classes; medians are computed over the whole class even when a learner filter is set) |
| **Struggling** | quiz average below **75 %**, **or** the latest released result on a mission is *not yet competent*, **or** **3 or more incomplete practice runs** on one mission that is still not verified |
| **On track** | none of the above |

Falling behind takes precedence over struggling; every matching reason is listed with its values (`reasons[].code`: `inactive`, `below_class_median`, `quiz_average_low`, `not_yet_competent`, `repeated_incomplete_runs`). Thresholds are returned in `thresholds`.

## 5. Quizzes

* Only quiz versions that were published count (`quiz_versions.published_at` set; status `published` or `retired`). Draft quizzes never appear.
* Only submitted attempts count (`submitted`/`completed` with `submitted_at`). A submitted attempt without a `quiz_results` row is **pending** and excluded from averages.
* One attempt per learner per quiz: the earliest submitted attempt (the server already enforces a single attempt; this also neutralises legacy duplicates).
* **Participants**: counted attempts in the scoped classes and period. **Eligible**: distinct learners with an open assignment of the quiz. **Completion rate**: eligible learners who submitted ÷ eligible learners. A learner's single attempt completes the quiz in every class it is assigned to, but its score counts only for the class where it was taken.
* **Average / highest / lowest**: over scored counted attempts.
* **Distribution**: ten buckets `0-9`, `10-19`, …, `80-89`, `90-100` (100 % falls in `90-100`); bucket counts add up to the scored participants.
* **Per question**: for each approved item of the counted versions, answered = answers in scored counted attempts, correct rate = correct ÷ answered.
* **Results**: one row per learner — `scored`, `pending`, `not_submitted`, or `other_class` (taken in another class; score shown there).

## 6. Missions and criteria

**Practice** (labelled separately from technical assessments). Every column is either *in the period* or explicitly *to date* (by the period end); a mission is listed when it has activity in the period or a verified completion to date:

| Metric | Window | Formula |
|---|---|---|
| Learners attempted | period | distinct learners with a recorded run or a verified completion in the period |
| Learners verified | period | distinct learners whose accepted completion was verified in the period |
| Runs, successful, failed | period | recorded runs (outcome `verified` / `incomplete`) — attempt counts always come from `practice_mission_runs`, never from completion counts |
| Runs per learner | period | runs ÷ learners with a run |
| Average completion time | period | mean duration of verified runs |
| Invalid actions per run | period | mean `invalid_count` of runs |
| Learners verified to date | to date | learners with an accepted, server-verified completion by the period end |
| Completion to date | to date | learners verified to date ÷ population |

An incomplete run never counts as a completion. Runs are recorded from the release of run tracking onward; completions verified earlier have no run rows.

**Technical assessments by mission**: attempts (started or submitted in the period), submitted, released, competent, not yet competent, pending (submitted, `evaluated` or `under_review`, or `finalized`, and not yet released), average released percentage.

**Criteria**: from released results only. *Assessment* criteria (`source: 'assessment'`): The released score revision's `criterion_values` are authoritative (they include instructor adjustments); `criterion_results` are the fallback for revisions without criterion values. Each learner counts once per criterion: their latest released result. *Average* = mean criterion score, *percent* = average ÷ criterion maximum × 100 (or the satisfied share when a criterion has no numeric maximum). *Strongest* = up to 3 highest percentages, *weakest* = up to 3 lowest (the two lists never overlap). *Homework* criteria (`source: 'homework'`, slice A4): each assignment criterion (`criteria[].id`, `max_points`) scored by `criterion_scores` of **released** submissions in the period; one value per learner (one submission per learner and homework); percent = average points ÷ `max_points`; satisfied counts do not apply (points-based). Simulation steps and essay rubric criteria are added after integration of slices A1 and A3.

## 7. Learning progress (shared WS3 methodology)

Required items: every **published topic** (latest published revision, not archived), every **mission placed in a module** (`mission_curriculum_links`) and one **COC practice quiz** per COC. Completion: a `learner_topic_progress` row, a server-verified `practice_mission_completions` row **of an accepted contract version** (`public.practice_completion_accepted`, slice A2), a `practice_coc_progress` row. Learning progress = completed required items ÷ required items in scope. Performance scores (quiz, assessment, homework) are reported separately and never mixed into progress.

Instructor analytics: a module is complete when it has at least one required item and all are complete by the period end (or a `learner_module_completions` row exists). The learner app uses slice A2's `public.learner_module_states` for its module counts (every module of the COC; a module without required items completes once unlocked), exactly like the Progress screen.

## 8. Learner view (`get_my_performance`)

The learner sees only their own rows: overall and per-COC learning progress (from `learner_module_states`: (completed topics + verified missions + passed COC quiz) ÷ (topics + missions + 1) per COC); competency per criterion of their **latest released result per mission** (outcome = released criterion observation); quiz scores of their completed attempts; homework submissions visible to them (A4: only `submitted` or `released`), with the score and its share of `max_score` only once released; every currently released assessment result; verified missions (accepted versions), recorded runs and best verified time per mission; and a `summary` (quiz average, released homework average, released/competent assessments, criteria achieved) shown in the Progress screen. Unreleased (pending) assessment results and unreleased homework grades never appear.

## 9. Real time

Dashboard: `RealtimeRouteRefresh` refreshes on assessment, quiz and homework changes; the analytics page additionally listens to practice runs/completions, COC progress, topic and module progress and polls every 30 seconds while the page is visible. The app's Performance section (the Progress screen's Performance slot) refetches on realtime changes to the learner's own rows and polls every 30 seconds while visible; changes that arrive while it is hidden (another tab, a covered route or the app in the background) are fetched once when it is shown again. Events only trigger a refetch; numbers always come from the functions above.
