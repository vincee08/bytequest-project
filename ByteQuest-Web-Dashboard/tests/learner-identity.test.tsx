import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { InstructorOverviewPanels } from "../src/components/dashboard/InstructorOverviewPanels";
import { LearnerDirectoryTable } from "../src/components/learners/LearnerDirectoryTable";
import { learnerDisplayName, learnerSecondaryEmail, UNNAMED_LEARNER } from "../src/lib/learners/identity";
import { parseLearnerSearchParams } from "../src/lib/learners/search";

// A class titled like the product is what read as "ByteQuest" in the identity slot.
const demoClass = { id: "c1", title: "ByteQuest Demo Class", class_code: null, status: "active" };
const assignment = { id: "a1", class_id: "c1", title: "Assemble a computer", assignment_type: "assessment", status: "active", due_at: null };
const juan = { user_id: "l1", full_name: "Juan Dela Cruz", email: "juan@school.edu.ph" };
const nameless = { user_id: "l2", full_name: "  ", email: "ana@school.edu.ph" };

function panels(profiles: { user_id: string; full_name: string | null; email: string | null }[]) {
  const attempt = (learnerId: string, id: string) => ({ id, class_id: "c1", assignment_id: "a1", learner_id: learnerId, status: "submitted", submitted_at: "2026-11-23T01:00:00Z", created_at: "2026-11-23T01:00:00Z" });
  return renderToStaticMarkup(
    <InstructorOverviewPanels
      classes={[demoClass]}
      assignments={[assignment]}
      reviewRows={[{ id: "r1", class_id: "c1", assignment_id: "a1", learner_id: "l1", status: "evaluated", submitted_at: "2026-11-23T01:00:00Z" }]}
      pendingReviewTotal={1}
      recentAttempts={profiles.map((profile, index) => attempt(profile.user_id, `t${index}`))}
      learnerNames={new Map(profiles.map((profile) => [profile.user_id, learnerDisplayName(profile)]))}
      learnerEmails={new Map(profiles.flatMap((profile) => {
        const email = learnerSecondaryEmail(profile);
        return email ? [[profile.user_id, email] as [string, string]] : [];
      }))}
      revisions={[]}
      upcoming={[]}
    />,
  );
}

test("a learner is named by profile name, then email, never by a product or class label", () => {
  assert.equal(learnerDisplayName({ full_name: "Juan Dela Cruz", email: "juan@school.edu.ph" }), "Juan Dela Cruz");
  assert.equal(learnerDisplayName({ full_name: "  ", email: "ana@school.edu.ph" }), "ana@school.edu.ph");
  assert.equal(learnerDisplayName({ full_name: null, email: null }), UNNAMED_LEARNER);
  assert.equal(learnerDisplayName(undefined), "Unnamed learner");
  assert.equal(learnerSecondaryEmail({ full_name: "Juan Dela Cruz", email: "juan@school.edu.ph" }), "juan@school.edu.ph");
  assert.equal(learnerSecondaryEmail({ full_name: "", email: "ana@school.edu.ph" }), null, "the name line already shows the email");
});

test("recent attempts show the learner's name and email, with the class beside the assignment", () => {
  const html = panels([juan]);
  assert.match(html, /font-semibold">Juan Dela Cruz<\/span><span class="mt-0\.5 block truncate text-\[11px\] text-muted-foreground">juan@school\.edu\.ph<\/span><\/span>/);
  assert.match(html, /Assemble a computer<\/span><span class="mt-0\.5 block truncate text-\[11px\] text-muted-foreground">ByteQuest Demo Class<\/span>/);
  assert.doesNotMatch(html, /Juan Dela Cruz<\/span><span[^>]*>ByteQuest Demo Class/, "the class title must not sit under the name");
  // The review queue line names the learner and their email before the class.
  assert.match(html, /Juan Dela Cruz · juan@school\.edu\.ph · ByteQuest Demo Class · /);
  assert.doesNotMatch(html, />Learner</);
});

test("a learner without a profile name is shown by email once", () => {
  const html = panels([nameless]);
  assert.match(html, /font-semibold">ana@school\.edu\.ph<\/span><\/span>/);
  assert.equal((html.match(/ana@school\.edu\.ph/g) ?? []).length, 1);
});

test("the learner directory names each learner and shows the email only when it differs", () => {
  const filters = parseLearnerSearchParams({});
  const row = (overrides: Partial<{ user_id: string; full_name: string; email: string }>) => ({
    user_id: "u1", full_name: "Juan Dela Cruz", email: "juan@school.edu.ph", learner_id: null, learner_id_managed: false,
    status: "active" as const, classes: [{ id: "c1", title: "ByteQuest Demo Class" }], last_activity_at: null, created_at: "2026-11-01T02:00:00Z",
    ...overrides,
  });
  const html = renderToStaticMarkup(
    <LearnerDirectoryTable
      basePath="/progress"
      filters={filters}
      result={{ total: 3, limit: 25, offset: 0, rows: [row({}), row({ user_id: "u2", full_name: "", email: "ana@school.edu.ph" }), row({ user_id: "u3", full_name: "", email: "" })] }}
      rowHref={(learner) => `/progress/learners/${learner.user_id}`}
      emptyTitle="No learners"
      emptyText="None"
    />,
  );
  assert.match(html, />Juan Dela Cruz<\/a><p[^>]*>juan@school\.edu\.ph<\/p>/);
  assert.match(html, />ana@school\.edu\.ph<\/a><\/td>/);
  assert.equal((html.match(/ana@school\.edu\.ph/g) ?? []).length, 1);
  assert.match(html, />Unnamed learner<\/a>/);
  assert.doesNotMatch(html, />Learner<\/a>/);
});
