import assert from "node:assert/strict";
import test from "node:test";
import {
  activeFilterCount,
  analyticsHref,
  analyticsSearchParams,
  applyFilterChange,
  manilaBoundary,
  parseAnalyticsQuery,
  toRpcFilters,
  type FilterCatalog,
} from "../src/lib/analytics/query";
import {
  NO_DATA,
  describePeriod,
  formatClock,
  formatDuration,
  formatPercent,
  reasonText,
  statusPresentation,
} from "../src/lib/analytics/format";
import {
  analyticsCsvFilename,
  analyticsTable,
  classesTable,
  criteriaTable,
  learnersTable,
  missionsTable,
  overviewTable,
  quizzesTable,
  tableToCsv,
} from "../src/lib/analytics/performance-csv";
import {
  analyticsErrorCode,
  classPerformanceSchema,
  criteriaAnalyticsSchema,
  learnerPerformanceSchema,
  missionAnalyticsSchema,
  overviewSchema,
  quizAnalyticsSchema,
} from "../src/lib/analytics/performance-types";

const NOW = new Date("2026-11-19T07:00:00.000Z");
const CLASS_A = "11111111-1111-4111-8111-111111111111";
const CLASS_B = "22222222-2222-4222-8222-222222222222";
const MODULE_11 = "33333333-3333-4333-8333-333333333333";
const MODULE_21 = "44444444-4444-4444-8444-444444444444";
const TOPIC = "55555555-5555-4555-8555-555555555555";
const QUIZ = "66666666-6666-4666-8666-666666666666";
const LEARNER = "77777777-7777-4777-8777-777777777777";
const period = { from: "2026-10-21T16:00:00.000Z", to: "2026-11-19T07:00:00.000Z" };

const catalog: FilterCatalog = {
  modules: [{ id: MODULE_11, coc_code: "coc1" }, { id: MODULE_21, coc_code: "coc2" }],
  topics: [{ id: TOPIC, module_id: MODULE_11, coc_code: "coc1" }],
  missions: [
    { mission_code: "coc1_m1", coc_code: "coc1", module_id: MODULE_11 },
    { mission_code: "coc2_m1", coc_code: "coc2", module_id: MODULE_21 },
  ],
  quizzes: [{ id: QUIZ, coc_code: "coc1" }],
  learners: [{ id: LEARNER, class_ids: [CLASS_A] }],
};

test("default query: overview tab, last 30 Manila days, no filters", () => {
  const query = parseAnalyticsQuery({}, NOW);
  assert.equal(query.tab, "overview");
  assert.equal(query.range, "30");
  assert.equal(query.toDate, "2026-11-19");
  assert.equal(query.fromDate, "2026-10-21");
  assert.equal(query.from, "2026-10-20T16:00:00.000Z");
  assert.equal(query.to, NOW.toISOString());
  assert.equal(activeFilterCount(query), 0);
});

test("filters are validated: junk ids, unknown tabs and invalid codes are dropped", () => {
  const query = parseAnalyticsQuery({ tab: "secrets", class: "not-a-uuid", coc: "COC9", mission: "coc1_m9", quiz: QUIZ.toUpperCase() }, NOW);
  assert.equal(query.tab, "overview");
  assert.equal(query.classId, null);
  assert.equal(query.cocCode, null);
  assert.equal(query.missionCode, null);
  assert.equal(query.quizId, QUIZ, "valid uuids are normalized to lower case");
});

test("URL round-trip preserves every filter and the custom range", () => {
  const source = new URLSearchParams({
    tab: "quizzes", class: CLASS_A, coc: "COC1", module: MODULE_11, topic: TOPIC, mission: "coc1_m1",
    quiz: QUIZ, learner: LEARNER, range: "custom", from: "2026-11-01", to: "2026-11-15",
  });
  const query = parseAnalyticsQuery(source, NOW);
  const again = parseAnalyticsQuery(analyticsSearchParams(query), NOW);
  assert.deepEqual(again, query);
  assert.equal(query.cocCode, "coc1");
  assert.equal(query.from, "2026-10-31T16:00:00.000Z");
  assert.equal(query.to, "2026-11-15T15:59:59.999Z");
  assert.equal(activeFilterCount(query), 7);
  assert.match(analyticsHref("/analytics", query, { tab: "learners" }), /^\/analytics\?tab=learners&class=/);
});

test("invalid or oversized custom ranges fall back to the default preset", () => {
  assert.equal(parseAnalyticsQuery({ range: "custom", from: "2026-11-15", to: "2026-11-01" }, NOW).range, "30");
  assert.equal(parseAnalyticsQuery({ range: "custom", from: "2025-01-01", to: "2026-11-01" }, NOW).range, "30");
  assert.equal(parseAnalyticsQuery({ range: "custom", from: "2026-02-31", to: "2026-03-01" }, NOW).range, "30");
  assert.equal(manilaBoundary("2026-02-31", "start"), null);
  assert.equal(parseAnalyticsQuery({ range: "365" }, NOW).fromDate, "2025-11-20");
});

test("RPC filters use the server keys and omit unset filters", () => {
  const query = parseAnalyticsQuery({ class: CLASS_A, coc: "coc2", range: "7" }, NOW);
  assert.deepEqual(Object.keys(toRpcFilters(query)).sort(), ["class_id", "coc_code", "from", "to"]);
  assert.equal(toRpcFilters(query).coc_code, "coc2");
  assert.equal(toRpcFilters(parseAnalyticsQuery({}, NOW)).class_id, undefined);
});

test("changing a parent filter clears inconsistent dependent filters", () => {
  const base = parseAnalyticsQuery({ coc: "coc1", module: MODULE_11, topic: TOPIC, mission: "coc1_m1", quiz: QUIZ }, NOW);
  const switched = applyFilterChange(base, "cocCode", "coc2", catalog);
  assert.equal(switched.cocCode, "coc2");
  assert.equal(switched.moduleId, null);
  assert.equal(switched.topicId, null);
  assert.equal(switched.missionCode, null);
  assert.equal(switched.quizId, null);
  const topicPicked = applyFilterChange(parseAnalyticsQuery({}, NOW), "topicId", TOPIC, catalog);
  assert.equal(topicPicked.moduleId, MODULE_11, "a topic selects its module");
  assert.equal(topicPicked.cocCode, "coc1", "a topic selects its COC");
  const learnerScoped = applyFilterChange(parseAnalyticsQuery({ learner: LEARNER }, NOW), "classId", CLASS_B, catalog);
  assert.equal(learnerScoped.learnerId, null, "a learner outside the class is cleared");
});

const overview = overviewSchema.parse({
  period,
  population: { description: "Active learners in your active classes", enrolled: 3, active_in_period: 3, completed: 0 },
  classes: [{ id: CLASS_A, title: "CSS A", class_code: "CSS-A", enrolled: 2 }],
  assessments: { applicable: true, attempts: 4, submitted: 4, released: 3, competent: 1, not_yet_competent: 2, competent_rate: 33.3, avg_percent: 66.7, pending_release: 1 },
  quizzes: { applicable: true, submitted: 3, scored: 3, pending: 0, avg_percent: 50, eligible: 3, completed: 3, completion_rate: 100 },
  homework: { applicable: false, eligible: 0, submitted: 0, released: 0, pending_evaluation: 0, missing: 0, late: 0, avg_percent: null, completion_rate: null },
  evaluation: {
    technical: { evaluate: 1, finalize: 1, release: 0, released: 3 },
    homework: { evaluate: 0, finalize: 0, release: 0, released: 0 },
    quiz: { evaluate: 0, finalize: 1, release: 0, released: 1 },
    total: { evaluate: 1, finalize: 2, release: 0, released: 4 },
  },
  missions: { applicable: true, verified: 5, learners_verified: 2, completion_rate: 8.3, runs: 7, successful_runs: 3, failed_runs: 4, avg_duration_seconds: 206.7 },
  learning_progress: { applicable: true, avg_percent: 6.9, items_total: 24, definition: "Completed required items." },
  trend: [{ date: "2026-11-18", assessments: 1, quizzes: 0, homework: 0, practice_runs: 2, verified: 1 }],
  generated_at: NOW.toISOString(),
});

test("payload schemas keep null averages as null instead of zero", () => {
  assert.equal(overview.homework.avg_percent, null);
  assert.equal(overview.assessments.avg_percent, 66.7);
  assert.throws(() => overviewSchema.parse({ ...overview, population: { ...overview.population, enrolled: -1 } }));
});

test("metric formatting shows a dash for missing data and readable units", () => {
  assert.equal(formatPercent(null), NO_DATA);
  assert.equal(formatPercent(66.7), "66.7%");
  assert.equal(formatPercent(100), "100%");
  assert.equal(formatPercent(0), "0%");
  assert.equal(formatDuration(206.7), "3m 27s");
  assert.equal(formatDuration(45), "45s");
  assert.equal(formatDuration(3720), "1h 2m");
  assert.equal(formatDuration(null), NO_DATA);
  assert.equal(formatClock("2026-11-19T07:05:09.000Z"), "15:05:09");
  assert.match(describePeriod(period), /Oct 22, 2026 – Nov 19, 2026/);
});

test("status badges map every learner status with a documented rule", () => {
  assert.equal(statusPresentation("on_track").label, "On track");
  assert.equal(statusPresentation("struggling").tone, "attention");
  assert.equal(statusPresentation("falling_behind").tone, "critical");
  assert.match(statusPresentation("falling_behind").description, /14 days/);
  assert.match(reasonText({ code: "quiz_average_low", kind: "struggling", quiz_avg: 50, threshold: 75 }), /Quiz average 50% is below 75%/);
  assert.match(reasonText({ code: "below_class_median", kind: "falling_behind", progress_percent: 0, class_median: 6.3, class_title: "CSS A" }), /below half of the CSS A median \(6\.3%\)/);
  assert.match(reasonText({ code: "repeated_incomplete_runs", kind: "struggling", threshold: 3, missions: [{ mission_code: "coc1_m4", title: "Peripherals", incomplete_runs: 3 }] }), /Peripherals \(3 incomplete runs\)/);
  assert.match(reasonText({ code: "inactive", kind: "falling_behind", threshold_days: 14, days_inactive: 20, last_activity_at: "2026-10-30T07:00:00Z" }), /20 days/);
});

test("overview CSV states population and period on every metric row", () => {
  const table = overviewTable(overview);
  const avg = table.rows.find((row) => row.metric === "Average released score");
  assert.equal(avg?.value, 66.7);
  assert.equal(table.rows.find((row) => row.section === "Homework" && row.metric === "Average released score")?.value, null, "no data stays empty, not zero");
  assert.equal(table.rows.find((row) => row.section === "Evaluation" && row.metric === "Finalize")?.value, 2, "evaluation stages are exported (all kinds)");
  assert.equal(table.rows.find((row) => row.metric === "Quizzes awaiting evaluation, finalization or release")?.value, 1,
    "instructor-release quizzes awaiting evaluation are exported");
  assert.equal(table.rows.find((row) => row.metric === "Completion to date")?.value, 8.3, "practice completion is labelled to date");
  assert.ok(table.rows.every((row) => String(row.population).includes("(3)") && String(row.period).includes("2026")));
  const csv = tableToCsv(table);
  assert.ok(csv.startsWith("﻿Section,Metric,Value,Unit,Population,Period\r\n"));
  assert.match(csv, /Assessments,Average released score,66\.7,%/);
});

test("class, learner, quiz, mission and criteria CSV shapes", () => {
  const classes = classPerformanceSchema.parse({
    period,
    classes: [{ id: CLASS_A, title: "CSS A", class_code: null, enrolled: 2, active_in_period: 2, avg_score: 66.3, quiz_avg: 75, assessment_competent_rate: 50, mission_completion_rate: 7.5, assignment_completion_rate: 50, progress_avg: 6.3, highest: { learner_id: LEARNER, name: "Ana", score: 82.5 }, lowest: { learner_id: LEARNER, name: "Ben", score: 50 } }],
    summary: { enrolled: 3, active_in_period: 3, avg_score: 56.4, quiz_avg: 50, assessment_competent_rate: 33.3, mission_completion_rate: 8.3, assignment_completion_rate: 50, progress_avg: 6.9 },
    generated_at: NOW.toISOString(),
  });
  const classTable = classesTable(classes);
  assert.equal(classTable.rows.length, 2, "one row per class plus the summary row");
  assert.equal(classTable.rows.at(-1)?.class, "All selected classes");
  assert.equal(classTable.rows[0].highest, "Ana (82.5)");

  const learners = learnerPerformanceSchema.parse({
    period,
    learners: [{ id: LEARNER, name: "Ben", student_id: "S-2", email: "ben@example.invalid", classes: [{ id: CLASS_A, title: "CSS A" }], progress_percent: 0, completed_items: 0, total_items: 24, performance_score: 50, quiz_avg: 50, quizzes_scored: 1, assessment: { released: 0, competent: 0, pending: 1 }, missions_verified: 0, practice_runs: 0, assignments: { submitted: 0, missing: 1, late: 0, pending_evaluation: 0 }, last_activity_at: null, status: "falling_behind", reasons: [{ code: "inactive", kind: "falling_behind", threshold_days: 14, days_inactive: 20, last_activity_at: null }, { code: "quiz_average_low", kind: "struggling", quiz_avg: 50, threshold: 75 }], engagement: { points: 120, points_in_period: 40, level: 2, level_title: "Apprentice", next_level_points: 300, level_progress_percent: 10 } }],
    thresholds: { inactivity_days: 14, progress_ratio_of_class_median: 0.5, quiz_average_below: 75, incomplete_runs_on_one_mission: 3 },
    counts: { on_track: 0, struggling: 0, falling_behind: 1 },
    generated_at: NOW.toISOString(),
  });
  const learnerRow = learnersTable(learners).rows[0];
  assert.equal(learnerRow.status, "Falling behind");
  assert.match(String(learnerRow.reasons), /since enrolment.*; Quiz average 50%/);
  assert.ok(learnerRow.points === 120 && learnerRow.points_in_period === 40 && learnerRow.level === "Apprentice",
    "engagement points and level are exported in their own columns");
  assert.ok(learnersTable(learners).columns.some((column) => column.label === "Engagement: points"));

  const quiz = quizAnalyticsSchema.parse({
    period,
    quizzes: [{ id: QUIZ, title: "Networking quiz", coc_code: "coc2", status: "published", release_mode: "instructor_release", participants: 2, pending: 0, eligible: 3, completion_rate: 66.7, average: 75, highest: 100, lowest: 50 }],
    quiz: null, participants: 0, pending: 0, eligible: 0, completed: 0, completion_rate: null, average: null, highest: null, lowest: null,
    distribution: [], per_question: [], results: [], generated_at: NOW.toISOString(),
  });
  assert.equal(quizzesTable(quiz).rows[0].coc, "COC2");
  assert.equal(quizzesTable(quiz).rows[0].release_mode, "After instructor release");
  const detail = quizAnalyticsSchema.parse({
    ...quiz,
    quiz: { id: QUIZ, title: "Networking quiz", coc_code: "coc2", status: "published", question_count: 2 },
    participants: 1, eligible: 2, completed: 1, completion_rate: 50, average: 100, highest: 100, lowest: 100,
    results: [
      { learner_id: LEARNER, name: "Ana", student_id: null, class_id: CLASS_A, class_title: "CSS A", score: 2, max_score: 2, percent: 100, status: "scored", submitted_at: NOW.toISOString() },
      { learner_id: CLASS_B, name: "Ben", student_id: null, class_id: CLASS_A, class_title: "CSS A", score: null, max_score: null, percent: null, status: "not_submitted", submitted_at: null },
      { learner_id: TOPIC, name: "Cara", student_id: null, class_id: CLASS_A, class_title: "CSS A", score: null, max_score: null, percent: null, status: "pending", stage: "finalize", submitted_at: NOW.toISOString() },
    ],
  });
  const quizTable = quizzesTable(detail);
  assert.equal(quizTable.title, "Quiz results - Networking quiz");
  assert.equal(quizTable.rows[1].status, "not submitted");
  assert.equal(quizTable.rows[2].stage, "finalize", "pending results export their Evaluation Center stage");
  assert.equal(quizTable.rows[1].stage, null, "a missing stage parses as null");

  const missions = missionAnalyticsSchema.parse({
    period,
    missions: [{ mission_code: "coc1_m4", title: "Peripherals", coc_code: "coc1", module: { id: MODULE_11, code: "LO1.2", title: "Install OS" }, learners_in_scope: 3, learners_attempted: 1, learners_verified: 0, learners_verified_to_date: 0, completion_rate_to_date: 0, runs: 3, successful_runs: 0, failed_runs: 3, avg_runs_per_learner: 3, avg_duration_seconds: null, avg_invalid_actions: 2,
      steps: [
        { phase_id: "coc1_m4_p1", step: 1, title: "Inspect peripherals", runs: 3, missed: 0, missed_rate: 0, not_completed: 0, avg_incorrect: 0 },
        { phase_id: "coc1_m4_p2", step: 2, title: "Choose a tool", runs: 3, missed: 3, missed_rate: 100, not_completed: 1, avg_incorrect: 1.33 },
      ],
      most_missed: [{ phase_id: "coc1_m4_p2", step: 2, title: "Choose a tool", runs: 3, missed: 3, missed_rate: 100, avg_incorrect: 1.33 }] }],
    assessments: [{ mission_code: "coc1_m2", title: "Install components", coc_code: "coc1", attempts: 4, submitted: 4, released: 3, competent: 1, not_yet_competent: 2, pending: 1, avg_percent: 66.7 }],
    generated_at: NOW.toISOString(),
  });
  const missionRows = missionsTable(missions).rows;
  assert.equal(missionRows.length, 2, "practice and assessment missions are merged by mission code");
  assert.equal(missionRows.find((row) => row.mission === "COC1 M4")?.duration, null);
  assert.equal(missionRows.find((row) => row.mission === "COC1 M2")?.a_attempts, 4);
  assert.equal(missionRows.find((row) => row.mission === "COC1 M4")?.most_missed, "Step 2 Choose a tool (3/3 runs, 1.33 incorrect per run)",
    "most-missed steps are exported per mission");
  const missionColumns = missionsTable(missions).columns.map((column) => column.label);
  assert.ok(missionColumns.includes("Practice: runs (period)") && missionColumns.includes("Practice: completion rate (%) (to date)"),
    "every practice column states whether it is in the period or to date");

  const criterion = { source: "assessment", criterion_id: TOPIC, code: "CR-A", title: "Criterion A", mission_code: "coc1_m2", mission_title: "Install components", max: 1, avg: 1, percent: 100, evaluated_learners: 2, satisfied: 2, not_satisfied: 0 };
  const homeworkCriterion = { source: "homework", criterion_id: `${QUIZ}:HW-1`, code: "HW-1", title: "Report structure", mission_code: null, mission_title: null, activity_title: "Workstation report", max: 30, avg: 25, percent: 83.3, evaluated_learners: 1, satisfied: null, not_satisfied: null };
  const simulationCriterion = { ...criterion, source: "simulation", criterion_id: MODULE_11, code: "SIM-C3", title: "CPU seated", satisfied: 0, not_satisfied: 1, percent: 0, avg: 0,
    steps: [{ id: "coc1_m2_p2", step: 2, title: "Prepare the motherboard" }] };
  const essayCriterion = { ...homeworkCriterion, source: "essay", criterion_id: `${QUIZ}:E1`, code: "E1", title: "Diagnosis", activity_title: "Essay quiz · ESSAY-1", max: 4, avg: 4, percent: 100 };
  const criteria = criteriaAnalyticsSchema.parse({ period, criteria: [criterion, homeworkCriterion, simulationCriterion, essayCriterion], strongest: [criterion], weakest: [homeworkCriterion], generated_at: NOW.toISOString() });
  const criteriaRows = criteriaTable(criteria).rows;
  assert.equal(criteriaRows[2].steps, "Step 2 Prepare the motherboard", "simulation criteria export their step");
  assert.equal(criteriaRows[2].source, "simulation");
  assert.equal(criteriaRows[3].source, "essay");
  assert.equal(criteriaRows[0].steps, null, "criteria without steps export an empty cell");
  assert.equal(criteriaTable(criteria).rows[0].rank, "Strongest");
  assert.equal(criteriaTable(criteria).rows[1].activity, "Workstation report", "homework criteria name their homework");
  assert.equal(criteria.criteria[0].activity_title, null, "a missing activity title parses as null");
  assert.equal(analyticsTable({ tab: "criteria", data: criteria }).title, "Criterion analysis");
  assert.equal(analyticsCsvFilename("learners", NOW), "bytequest-analytics-learners-2026-11-19.csv");
});

test("PostgreSQL error messages map to typed analytics errors", () => {
  assert.equal(analyticsErrorCode("ANALYTICS_SCOPE_DENIED"), "ANALYTICS_SCOPE_DENIED");
  assert.equal(analyticsErrorCode("ANALYTICS_FILTER_INVALID"), "ANALYTICS_FILTER_INVALID");
  assert.equal(analyticsErrorCode("connection reset"), "ANALYTICS_UNAVAILABLE");
});
