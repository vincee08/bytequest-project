import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { EvaluationCenter } from "../src/components/evaluations/EvaluationCenter";
import type { EvaluationStage, QueueItem } from "../src/lib/evaluations/requests";

const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const base = { learner: { id: uuid(1), name: "Queue Learner One" }, class: { id: uuid(2), title: "Queue class one" }, submitted_at: "2026-11-19T01:00:00Z" };
const quiz = (status: string, score: number | null): QueueItem => ({
  ...base, kind: "quiz", id: uuid(10), title: "Queue essay quiz", status, score, max_score: 11,
  link: `/quizzes/${uuid(11)}?tab=results&attempt=${uuid(10)}`,
});
function render(stage: EvaluationStage, items: QueueItem[]) {
  const counts = { evaluate: 0, finalize: 0, release: 0, released: 0, [stage]: items.length };
  return renderToStaticMarkup(
    <AppRouterContext.Provider value={router}>
      <EvaluationCenter stage={stage} counts={counts} items={items} total={items.length} limit={50} offset={0}
        quizAvailable canAct query={{ tab: stage }} />
    </AppRouterContext.Provider>,
  );
}

test("a quiz awaiting essay scores links to the quiz results to score it", () => {
  const html = render("evaluate", [quiz("pending", null)]);
  assert.match(html, /Quiz essay/);
  assert.match(html, /Awaiting essay scores/);
  assert.match(html, /Essays awaiting scores/);
  assert.match(html, new RegExp(`href="/quizzes/${uuid(11)}\\?tab=results&amp;attempt=${uuid(10)}"`));
  assert.match(html, /Score essays/);
  assert.doesNotMatch(html, /type="checkbox"/, "Evaluate is always individual; no bulk selection");
});

test("Release lists mixed kinds with selection and one bulk Release action", () => {
  const html = render("release", [
    { ...base, kind: "technical", id: uuid(20), title: "Install internal components", status: "finalized", score: 1, max_score: 2, link: `/attempts/${uuid(20)}` },
    { ...base, kind: "homework", id: uuid(21), title: "Assembly report", status: "finalized", score: 40, max_score: 50, link: `/classes/${uuid(2)}/assignments/${uuid(3)}?submission=${uuid(21)}` },
    quiz("finalized", 9),
  ]);
  for (const title of ["Install internal components", "Assembly report", "Queue essay quiz"]) {
    assert.match(html, new RegExp(`aria-label="Select ${title} for Queue Learner One"`));
  }
  assert.match(html, /Technical assessment/);
  assert.match(html, /Homework/);
  assert.match(html, /Quiz essay/);
  assert.match(html, /9 \/ 11/);
  assert.match(html, /Release selected \(0\)<\/button>/);
  assert.match(html, /aria-label="Select all 3 items on this page"/);
});

test("each queued submission names the learner by email, not only the class", () => {
  const html = render("evaluate", [{ ...quiz("pending", null), learner: { ...base.learner, email: "queue.learner@example.test" } }]);
  assert.match(html, /Queue Learner One/);
  assert.match(html, /queue\.learner@example\.test/);
  assert.match(html, /Queue class one/);
  const missing = render("evaluate", [quiz("pending", null)]);
  assert.match(missing, /No email on record/);
});
