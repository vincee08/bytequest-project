import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { InstructorOverviewPanels } from "../src/components/dashboard/InstructorOverviewPanels";
import { buildUpcomingTasks } from "../src/components/dashboard/upcoming-tasks";
import { classQuizDeadlineRows, classTabHref, resolveClassTab } from "../src/components/dashboard/class-workspace";

const now = new Date("2026-11-20T00:00:00Z");
const classes = [
  { id: "c1", title: "BSIT 2A", status: "active" },
  { id: "c2", title: "Archived class", status: "archived" },
];

test("upcoming tasks merge quiz, homework and technical deadlines in date order", () => {
  const tasks = buildUpcomingTasks({
    now,
    classes,
    quizzes: [
      { id: "q1", class_id: "c1", due_at: "2026-11-22T09:00:00Z", status: "active", quiz_versions: { status: "published", quizzes: { title: "COC1 summative quiz" } } },
      { id: "q2", class_id: "c1", due_at: "2026-11-19T09:00:00Z", status: "active", quiz_versions: { status: "published", quizzes: { title: "Expired quiz" } } },
      { id: "q3", class_id: "c1", due_at: "2026-11-21T09:00:00Z", status: "active", quiz_versions: { status: "draft", quizzes: { title: "Draft quiz" } } },
    ],
    homework: [
      { id: "h1", class_id: "c1", title: "Cable color codes", status: "published", deadline_at: "2026-11-21T03:00:00Z" },
      { id: "h2", class_id: "c1", title: "Unpublished homework", status: "draft", deadline_at: "2026-11-21T04:00:00Z" },
      { id: "h3", class_id: "c2", title: "Archived class homework", status: "published", deadline_at: "2026-11-21T05:00:00Z" },
    ],
    assignments: [
      { id: "a1", class_id: "c1", title: "Assemble a computer", status: "active", assignment_type: "assessment", due_at: "2026-11-25T00:00:00Z" },
      { id: "a2", class_id: "c1", title: "No due date", status: "active", assignment_type: "practice", due_at: null },
      { id: "a3", class_id: "c1", title: "Closed", status: "closed", assignment_type: "assessment", due_at: "2026-11-24T00:00:00Z" },
    ],
  });
  assert.deepEqual(tasks.map((task) => `${task.kind}:${task.title}`), ["homework:Cable color codes", "quiz:COC1 summative quiz", "assignment:Assemble a computer"]);
  assert.equal(tasks[0].href, "/classes/c1?tab=assignments");
  assert.equal(tasks[0].classTitle, "BSIT 2A");
  assert.equal(tasks[2].detail, "Assessment");
  assert.equal(buildUpcomingTasks({ now, classes, quizzes: [], homework: [], assignments: [], limit: 3 }).length, 0);
});

test("class tabs resolve from ?tab= and summary cards link to real tabs", () => {
  assert.equal(resolveClassTab("assignments"), "assignments");
  assert.equal(resolveClassTab(["bypasses", "x"]), "bypasses");
  assert.equal(resolveClassTab("#resources"), "learners");
  assert.equal(resolveClassTab(undefined), "learners");
  assert.equal(classTabHref("c1", "resources"), "/classes/c1?tab=resources");
});

test("quiz deadline controls receive the quiz title and the class title in the right fields", () => {
  const rows = classQuizDeadlineRows([
    { id: "qa1", due_at: "2026-11-22T09:00:00Z", quiz_versions: { status: "published", quizzes: { title: "Network cabling quiz" } } },
    { id: "qa2", due_at: null, quiz_versions: { status: "draft", quizzes: { title: "Draft" } } },
  ], "BSIT 2A");
  assert.deepEqual(rows, [{ quizTitle: "Network cabling quiz", assignment: { id: "qa1", dueAt: "2026-11-22T09:00:00Z", classTitle: "BSIT 2A" } }]);
});

test("the pending review panel shows the exact total and links to the Evaluation Center", () => {
  const reviewRows = Array.from({ length: 5 }, (_, index) => ({ id: `r${index}`, class_id: "c1", assignment_id: "a1", learner_id: `l${index}`, status: "evaluated", submitted_at: "2026-11-19T01:00:00Z" }));
  const html = renderToStaticMarkup(
    <InstructorOverviewPanels
      classes={[{ id: "c1", title: "BSIT 2A", class_code: null, status: "active" }]}
      assignments={[{ id: "a1", class_id: "c1", title: "Assemble a computer", assignment_type: "assessment", status: "active", due_at: null }]}
      reviewRows={reviewRows}
      pendingReviewTotal={12}
      recentAttempts={[]}
      learnerNames={new Map([["l0", "Juan Dela Cruz"]])}
      revisions={[]}
      upcoming={buildUpcomingTasks({ now, classes, quizzes: [], homework: [{ id: "h1", class_id: "c1", title: "Cable color codes", status: "published", deadline_at: "2026-11-21T03:00:00Z" }], assignments: [] })}
    />,
  );
  assert.match(html, /Showing the 5 oldest of 12 items awaiting review/);
  assert.match(html, /href="\/evaluations"/);
  assert.match(html, /Juan Dela Cruz/);
  assert.match(html, /Cable color codes/);
  assert.match(html, /Homework/);
  assert.match(html, /quizzes, homework and technical assignments/);
  assert.doesNotMatch(html, /Only assignments with a configured due date are shown/);
});

test("an empty review queue and no deadlines show honest empty states", () => {
  const html = renderToStaticMarkup(
    <InstructorOverviewPanels classes={[]} assignments={[]} reviewRows={[]} pendingReviewTotal={0} recentAttempts={[]} learnerNames={new Map()} revisions={[]} upcoming={[]} />,
  );
  assert.match(html, /Review queue is clear/);
  assert.match(html, /No upcoming deadlines/);
});
