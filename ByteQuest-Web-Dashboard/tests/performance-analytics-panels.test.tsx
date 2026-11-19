import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ClassesPanel } from "../src/components/analytics/performance/ClassesPanel";
import { CriteriaPanel } from "../src/components/analytics/performance/CriteriaPanel";
import { LearnersPanel } from "../src/components/analytics/performance/LearnersPanel";
import { MissionsPanel } from "../src/components/analytics/performance/MissionsPanel";
import { OverviewPanel } from "../src/components/analytics/performance/OverviewPanel";
import { QuizzesPanel } from "../src/components/analytics/performance/QuizzesPanel";
import {
  classPerformanceSchema,
  criteriaAnalyticsSchema,
  learnerPerformanceSchema,
  missionAnalyticsSchema,
  overviewSchema,
  quizAnalyticsSchema,
} from "../src/lib/analytics/performance-types";
import { parseAnalyticsQuery } from "../src/lib/analytics/query";

// tsx compiles JSX with the classic runtime; shared dashboard components rely
// on Next's automatic runtime and do not import React themselves.
(globalThis as { React?: typeof React }).React = React;

const NOW = new Date("2026-11-19T07:00:00.000Z");
const CLASS_A = "11111111-1111-4111-8111-111111111111";
const LEARNER_A = "22222222-2222-4222-8222-222222222222";
const LEARNER_B = "33333333-3333-4333-8333-333333333333";
const QUIZ = "44444444-4444-4444-8444-444444444444";
const ITEM = "55555555-5555-4555-8555-555555555555";
const CRITERION = "66666666-6666-4666-8666-666666666666";
const period = { from: "2026-10-20T16:00:00.000Z", to: NOW.toISOString() };
const generated_at = NOW.toISOString();
const query = parseAnalyticsQuery({}, NOW);

const emptyOverview = overviewSchema.parse({
  period,
  population: { description: "Active learners in your active classes", enrolled: 0, active_in_period: 0, completed: 0 },
  classes: [],
  assessments: { applicable: true, attempts: 0, submitted: 0, released: 0, competent: 0, not_yet_competent: 0, competent_rate: null, avg_percent: null, pending_release: 0 },
  quizzes: { applicable: true, submitted: 0, scored: 0, pending: 0, avg_percent: null, eligible: 0, completed: 0, completion_rate: null },
  homework: { applicable: true, eligible: 0, submitted: 0, released: 0, pending_evaluation: 0, missing: 0, late: 0, avg_percent: null, completion_rate: null },
  evaluation: {
    technical: { evaluate: 0, finalize: 0, release: 0, released: 0 },
    homework: { evaluate: 0, finalize: 0, release: 0, released: 0 },
    total: { evaluate: 0, finalize: 0, release: 0, released: 0 },
  },
  missions: { applicable: true, verified: 0, learners_verified: 0, completion_rate: null, runs: 0, successful_runs: 0, failed_runs: 0, avg_duration_seconds: null },
  learning_progress: { applicable: true, avg_percent: null, items_total: 24, definition: "Completed required items divided by required items." },
  trend: [],
  generated_at,
});

test("overview renders an honest empty state instead of zero averages", () => {
  const html = renderToStaticMarkup(<OverviewPanel data={emptyOverview} query={query} pathname="/analytics" />);
  assert.match(html, /No submissions in this period/);
  assert.match(html, /No scored work in this period/);
  assert.match(html, /No submitted work in this period/);
  assert.doesNotMatch(html, />0%</, "a missing average is never displayed as 0%");
  assert.match(html, /Population:/);
  assert.match(html, /Period:/);
});

test("overview cards state population and period and mark unlinked sources", () => {
  const data = overviewSchema.parse({
    ...emptyOverview,
    population: { description: "Active learners in CSS A", enrolled: 3, active_in_period: 3, completed: 0 },
    classes: [{ id: CLASS_A, title: "CSS A", class_code: "CSS-A", enrolled: 3 }],
    assessments: { ...emptyOverview.assessments, released: 3, competent: 1, not_yet_competent: 2, competent_rate: 33.3, avg_percent: 66.7, pending_release: 1, submitted: 4, attempts: 4 },
    homework: { ...emptyOverview.homework, applicable: false },
    evaluation: {
      technical: { evaluate: 1, finalize: 1, release: 0, released: 3 },
      homework: { evaluate: 1, finalize: 1, release: 1, released: 2 },
      total: { evaluate: 2, finalize: 2, release: 1, released: 5 },
    },
    trend: [{ date: "2026-11-18", assessments: 1, quizzes: 2, homework: 0, practice_runs: 3, verified: 1 }],
  });
  const html = renderToStaticMarkup(<OverviewPanel data={data} query={query} pathname="/analytics" />);
  assert.match(html, /66\.7%/);
  assert.match(html, /1 pending release/);
  assert.match(html, /Not linked/);
  assert.match(html, /3 learners · /, "each card footer states the population");
  assert.match(html, /tab=learners&amp;class=11111111/, "class rows drill down to the learner list");
  assert.ok(html.includes('<div class="relative overflow-x-auto"><table'),
    "wide tables scroll in a positioned box, so their visually hidden link text cannot widen the page on phones");
  assert.ok(html.includes("Evaluation status (Evaluate → Finalize → Release)"), "the evaluation pipeline panel is shown");
  assert.ok(html.includes('>Finalize</td><td class="py-2 text-right">1</td><td class="py-2 text-right">1</td><td class="py-2 text-right font-semibold">2</td>'),
    "the stage table backs the chart");
  const adminHtml = renderToStaticMarkup(<OverviewPanel data={data} query={query} pathname={null} scopeLabel="every active class" />);
  assert.doesNotMatch(adminHtml, /href="\/analytics/, "the admin overview never links into instructor-only routes");
  assert.match(adminHtml, /Active members of every active class/);
});

test("class comparison renders the summary, chart table and drill-down", () => {
  const data = classPerformanceSchema.parse({
    period,
    classes: [{ id: CLASS_A, title: "CSS A", class_code: "CSS-A", enrolled: 2, active_in_period: 2, avg_score: 66.3, quiz_avg: 75, assessment_competent_rate: 50, mission_completion_rate: 7.5, assignment_completion_rate: 50, progress_avg: 6.3, highest: { learner_id: LEARNER_A, name: "Ana", score: 82.5 }, lowest: { learner_id: LEARNER_B, name: "Ben", score: 50 } }],
    summary: { enrolled: 3, active_in_period: 3, avg_score: 56.4, quiz_avg: 50, assessment_competent_rate: 33.3, mission_completion_rate: 8.3, assignment_completion_rate: 50, progress_avg: 6.9 },
    generated_at,
  });
  const html = renderToStaticMarkup(<ClassesPanel data={data} query={query} pathname="/analytics" />);
  assert.match(html, /All selected classes/);
  assert.match(html, /56\.4%/);
  assert.match(html, /Ana <span class="text-muted-foreground">\(82\.5%\)/);
  assert.match(html, /Learners<svg/);
  const empty = renderToStaticMarkup(<ClassesPanel data={{ ...data, classes: [] }} query={query} pathname="/analytics" />);
  assert.match(empty, /No active class is in scope/);
});

test("learner list shows status badges, readable reasons and profile links", () => {
  const data = learnerPerformanceSchema.parse({
    period,
    learners: [
      { id: LEARNER_B, name: "Ben", student_id: "S-2", email: "ben@example.invalid", classes: [{ id: CLASS_A, title: "CSS A" }], progress_percent: 0, completed_items: 0, total_items: 24, performance_score: 50, quiz_avg: 50, quizzes_scored: 1, assessment: { released: 0, competent: 0, pending: 1 }, missions_verified: 0, practice_runs: 0, assignments: { submitted: 0, missing: 1, late: 0, pending_evaluation: 0 }, last_activity_at: "2026-10-30T07:00:00Z", status: "falling_behind", reasons: [{ code: "inactive", kind: "falling_behind", threshold_days: 14, days_inactive: 20, last_activity_at: "2026-10-30T07:00:00Z" }] },
      { id: LEARNER_A, name: "Ana", student_id: "S-1", email: "ana@example.invalid", classes: [{ id: CLASS_A, title: "CSS A" }], progress_percent: 12.5, completed_items: 3, total_items: 24, performance_score: 82.5, quiz_avg: 100, quizzes_scored: 1, assessment: { released: 2, competent: 1, pending: 0 }, missions_verified: 3, practice_runs: 4, assignments: { submitted: 1, missing: 1, late: 0, pending_evaluation: 1 }, last_activity_at: "2026-11-17T07:00:00Z", status: "on_track", reasons: [] },
    ],
    thresholds: { inactivity_days: 14, progress_ratio_of_class_median: 0.5, quiz_average_below: 75, incomplete_runs_on_one_mission: 3 },
    counts: { on_track: 1, struggling: 0, falling_behind: 1 },
    generated_at,
  });
  const html = renderToStaticMarkup(<LearnersPanel data={data} query={query} />);
  assert.match(html, /Falling behind/);
  assert.match(html, /On track/);
  assert.match(html, /No recorded activity for 20 days/);
  assert.match(html, new RegExp(`href="/progress/learners/${LEARNER_A}\\?tab=overview&amp;range=30"`));
  assert.match(html, /aria-pressed="false"/, "status filters are toggle buttons");
});

test("quiz list and detail render distribution, per-question and results tables", () => {
  const data = quizAnalyticsSchema.parse({
    period,
    quizzes: [{ id: QUIZ, title: "Hardware quiz", coc_code: "coc1", status: "published", participants: 3, pending: 0, eligible: 3, completion_rate: 100, average: 50, highest: 100, lowest: 0 }],
    quiz: { id: QUIZ, title: "Hardware quiz", coc_code: "coc1", status: "published", question_count: 2 },
    participants: 3, pending: 0, eligible: 3, completed: 3, completion_rate: 100, average: 50, highest: 100, lowest: 0,
    distribution: Array.from({ length: 10 }, (_, index) => ({ bucket: index === 9 ? "90-100" : `${index * 10}-${index * 10 + 9}`, min: index * 10, max: index === 9 ? 100 : index * 10 + 9, count: [0, 5, 9].includes(index) ? 1 : 0 })),
    per_question: [{ item_id: ITEM, code: "Q-1", prompt: "A router connects networks.", type: "true_false", version_number: 1, answered: 3, correct: 2, correct_rate: 66.7 }],
    results: [{ learner_id: LEARNER_A, name: "Ana", student_id: "S-1", class_id: CLASS_A, class_title: "CSS A", score: 2, max_score: 2, percent: 100, status: "scored", submitted_at: NOW.toISOString() }],
    generated_at,
  });
  const html = renderToStaticMarkup(<QuizzesPanel data={data} query={{ ...query, tab: "quizzes", quizId: QUIZ }} pathname="/analytics" />);
  assert.match(html, /Score distribution/);
  assert.match(html, />90-100</);
  assert.match(html, /2 \(66\.7%\)/);
  assert.match(html, /2 \/ 2/);
  const filtered = renderToStaticMarkup(<QuizzesPanel data={{ ...data, quiz: null }} query={{ ...query, moduleId: ITEM }} pathname="/analytics" />);
  assert.match(filtered, /not linked to the selected curriculum filter/);
});

test("mission panel separates practice runs from technical assessments", () => {
  const data = missionAnalyticsSchema.parse({
    period,
    missions: [{ mission_code: "coc1_m4", title: "Connect peripherals", coc_code: "coc1", module: { id: ITEM, code: "LO1.2", title: "Install OS" }, learners_in_scope: 3, learners_attempted: 1, learners_verified: 0, learners_verified_to_date: 0, completion_rate_to_date: 0, runs: 3, successful_runs: 0, failed_runs: 3, avg_runs_per_learner: 3, avg_duration_seconds: null, avg_invalid_actions: 2 }],
    assessments: [{ mission_code: "coc1_m2", title: "Install components", coc_code: "coc1", attempts: 4, submitted: 4, released: 3, competent: 1, not_yet_competent: 2, pending: 1, avg_percent: 66.7 }],
    generated_at,
  });
  const html = renderToStaticMarkup(<MissionsPanel data={data} query={query} />);
  assert.match(html, /Practice missions/);
  assert.match(html, /Technical assessments by mission/);
  assert.match(html, /3 \(0 ok · 3 incomplete\)/);
  assert.ok(html.includes(">Completion to date<") && html.includes(">Runs (period)<"), "practice columns are labelled period or to date");
  const none = renderToStaticMarkup(<MissionsPanel data={{ ...data, missions: [], assessments: [] }} query={query} />);
  assert.match(none, /No practice activity in this period/);
});

test("criteria panel lists strongest and weakest skills", () => {
  const strong = { source: "assessment", criterion_id: CRITERION, code: "CR-A", title: "Wears ESD strap", mission_code: "coc1_m2", mission_title: "Install components", max: 1, avg: 1, percent: 100, evaluated_learners: 2, satisfied: 2, not_satisfied: 0 };
  const weak = { ...strong, criterion_id: ITEM, code: "CR-B", title: "Seats the CPU", avg: 0.5, percent: 50, satisfied: 1, not_satisfied: 1 };
  const homework = { ...strong, source: "homework", criterion_id: `${ITEM}:HW-1`, code: "HW-1", title: "Report structure", activity_title: "Workstation report", max: 30, avg: 25, percent: 83.3, evaluated_learners: 1, satisfied: null, not_satisfied: null };
  const data = criteriaAnalyticsSchema.parse({ period, criteria: [strong, weak, homework], strongest: [strong], weakest: [weak], generated_at });
  const html = renderToStaticMarkup(<CriteriaPanel data={data} query={query} />);
  assert.match(html, /Strongest skills/);
  assert.match(html, /Wears ESD strap/);
  assert.match(html, /Seats the CPU/);
  assert.match(html, /50%/);
  assert.ok(html.includes("Points-based"), "homework criteria have no satisfied count");
  assert.ok(html.includes("HW-1 · Workstation report"), "homework criteria name their homework");
});
