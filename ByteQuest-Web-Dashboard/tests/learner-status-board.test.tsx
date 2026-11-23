import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { LearnerStatusBoard } from "../src/components/analytics/performance/LearnerStatusBoard";
import { OverviewPanel } from "../src/components/analytics/performance/OverviewPanel";
import { groupLearnersByStatus } from "../src/lib/analytics/learner-status";
import { learnerPerformanceSchema, overviewSchema } from "../src/lib/analytics/performance-types";
import { parseAnalyticsQuery } from "../src/lib/analytics/query";

(globalThis as { React?: typeof React }).React = React;

const NOW = new Date("2026-11-19T07:00:00.000Z");
const CLASS_A = "11111111-1111-4111-8111-111111111111";
const ANA = "22222222-2222-4222-8222-222222222222";
const BEN = "33333333-3333-4333-8333-333333333333";
const CARA = "44444444-4444-4444-8444-444444444444";
const DAN = "55555555-5555-4555-8555-555555555555";
const period = { from: "2026-10-20T16:00:00.000Z", to: NOW.toISOString() };
const generated_at = NOW.toISOString();
const query = parseAnalyticsQuery({}, NOW);
const engagement = { points: 0, points_in_period: 0, level: null, level_title: null, next_level_points: null, level_progress_percent: null };

function learner(id: string, name: string, status: string, reasons: unknown[], extra: Record<string, unknown> = {}) {
  return {
    id, name, student_id: `S-${name}`, email: `${name.toLowerCase()}@example.invalid`, classes: [{ id: CLASS_A, title: "CSS A" }],
    progress_percent: 12.5, completed_items: 3, total_items: 24, performance_score: 70, quiz_avg: 80, quizzes_scored: 1,
    assessment: { released: 0, competent: 0, pending: 0 }, missions_verified: 0, practice_runs: 0,
    assignments: { submitted: 0, missing: 0, late: 0, pending_evaluation: 0 }, last_activity_at: "2026-11-17T07:00:00Z",
    status, reasons, engagement, ...extra,
  };
}

const performance = learnerPerformanceSchema.parse({
  period,
  learners: [
    learner(BEN, "Ben", "falling_behind", [{ code: "inactive", kind: "falling_behind", threshold_days: 14, days_inactive: 20, last_activity_at: "2026-10-30T07:00:00Z" }]),
    learner(DAN, "Dan", "falling_behind", [{ code: "below_class_median", kind: "falling_behind", progress_percent: 0, class_median: 12.5, class_title: "CSS A" }]),
    learner(CARA, "Cara", "struggling", [{ code: "quiz_average_low", kind: "struggling", quiz_avg: 50, threshold: 75 }]),
    learner(ANA, "Ana", "on_track", []),
  ],
  thresholds: { inactivity_days: 14, progress_ratio_of_class_median: 0.5, quiz_average_below: 75, incomplete_runs_on_one_mission: 3 },
  counts: { on_track: 1, struggling: 1, falling_behind: 2 },
  generated_at,
});

const overview = overviewSchema.parse({
  period,
  population: { description: "Active learners in your active classes", enrolled: 4, active_in_period: 3, completed: 0 },
  classes: [{ id: CLASS_A, title: "CSS A", class_code: "CSS-A", enrolled: 4 }],
  assessments: { applicable: true, attempts: 0, submitted: 0, released: 0, competent: 0, not_yet_competent: 0, competent_rate: null, avg_percent: null, pending_release: 0 },
  quizzes: { applicable: true, submitted: 0, scored: 0, pending: 0, avg_percent: null, eligible: 0, completed: 0, completion_rate: null },
  homework: { applicable: true, eligible: 0, submitted: 0, released: 0, pending_evaluation: 0, missing: 0, late: 0, avg_percent: null, completion_rate: null },
  evaluation: {
    technical: { evaluate: 0, finalize: 0, release: 0, released: 0 },
    homework: { evaluate: 0, finalize: 0, release: 0, released: 0 },
    quiz: { evaluate: 0, finalize: 0, release: 0, released: 0 },
    total: { evaluate: 0, finalize: 0, release: 0, released: 0 },
  },
  missions: { applicable: true, verified: 0, learners_verified: 0, completion_rate: null, runs: 0, successful_runs: 0, failed_runs: 0, avg_duration_seconds: null },
  learning_progress: { applicable: true, avg_percent: null, items_total: 24, definition: "Completed required items divided by required items." },
  trend: [],
  generated_at,
});

test("groups follow the rule priority and count learners beyond the limit", () => {
  const groups = groupLearnersByStatus(performance, 1);
  assert.deepEqual(groups.map((group) => [group.status, group.count, group.learners.map((row) => row.name), group.hidden]), [
    ["falling_behind", 2, ["Ben"], 1],
    ["struggling", 1, ["Cara"], 0],
    ["on_track", 1, ["Ana"], 0],
  ]);
});

test("the analytics overview names falling-behind, struggling and on-track learners with reasons", () => {
  const html = renderToStaticMarkup(
    <OverviewPanel data={overview} learnerStatus={{ state: "ready", data: performance }} query={query} pathname="/analytics" />,
  );
  assert.match(html, /aria-label="Learner status"/);
  const order = ["Falling behind", "Struggling", "On track"].map((label) => html.indexOf(`>${label}</h3>`));
  assert.ok(order.every((index) => index > 0) && order[0] < order[1] && order[1] < order[2], "columns appear in rule order");
  assert.match(html, /No recorded activity for 20 days/);
  assert.match(html, /below half of the CSS A median \(12\.5%\)/);
  assert.match(html, /Quiz average 50% is below 75%/);
  assert.match(html, /Progress 12\.5% · Last activity/, "on-track learners show progress instead of a reason");
  assert.match(html, new RegExp(`href="/progress/learners/${BEN}\\?tab=overview&amp;range=30"`), "each name links to the learner profile");
  assert.match(html, /href="\/analytics\?tab=learners&amp;range=30"/, "the full list is one click away");
  assert.match(html, />2<span class="sr-only"> learners<\/span>/, "counts are announced with their noun");
  assert.ok(html.indexOf('aria-label="Learner status"') < html.indexOf("Assessment results"), "status comes before the summary cards");
});

test("the dashboard summary lists a few learners per status and links the rest", () => {
  const html = renderToStaticMarkup(
    <LearnerStatusBoard status={{ state: "ready", data: performance }} scopeLabel="your active classes" limit={1} allHref="/analytics?tab=learners" />,
  );
  assert.match(html, /Ben/);
  assert.doesNotMatch(html, />Dan</);
  assert.match(html, /\+1 more falling behind in the learner list/);
  assert.match(html, new RegExp(`href="/progress/learners/${ANA}"`));
});

test("empty, missing-status and unavailable states stay truthful", () => {
  const none = renderToStaticMarkup(
    <LearnerStatusBoard status={{ state: "ready", data: { ...performance, learners: [], counts: { on_track: 0, struggling: 0, falling_behind: 0 } } }} scopeLabel="your active classes" />,
  );
  assert.match(none, /No active learners in scope/);
  const onlyOnTrack = renderToStaticMarkup(
    <LearnerStatusBoard status={{ state: "ready", data: { ...performance, learners: performance.learners.filter((row) => row.status === "on_track") } }} scopeLabel="your active classes" />,
  );
  assert.match(onlyOnTrack, /No learner is falling behind in this scope\./);
  assert.match(onlyOnTrack, /No learner meets a struggling rule in this scope\./);
  const unavailable = renderToStaticMarkup(<LearnerStatusBoard status={{ state: "unavailable" }} scopeLabel="your active classes" />);
  assert.match(unavailable, /Learner status could not be loaded right now/);
  const admin = renderToStaticMarkup(<OverviewPanel data={overview} query={query} pathname={null} />);
  assert.doesNotMatch(admin, /aria-label="Learner status"/, "the admin overview is unchanged");
});
