import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { CurriculumWorkspaceView } from "../src/components/curriculum/CurriculumWorkspace";
import { MarkdownPreview } from "../src/components/curriculum/MarkdownPreview";
import type { CurriculumWorkspace, TopicRevision } from "../src/lib/curriculum/types";

// Shared components such as PageHeader rely on Next's automatic JSX runtime;
// the Node test transform uses classic JSX, so expose React globally here.
(globalThis as { React?: typeof React }).React = React;

const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
const admin = "00000000-0000-4000-8000-0000000000a1";
const author = "00000000-0000-4000-8000-0000000000b2";

function revision(overrides: Partial<TopicRevision>): TopicRevision {
  return {
    id: "rev-1", topic_id: "topic-1", revision_number: 1, title: "ESD precautions", summary: "Why the strap comes first.",
    body_markdown: "# ESD\n\nWear the **wrist strap**.", outcome_ids: ["pc-14"], status: "draft", author_id: author,
    submitted_at: null, evaluated_by: null, evaluated_at: null, evaluation_notes: null, finalized_by: null, finalized_at: null,
    approved_by: null, approved_at: null, published_by: null, published_at: null, unpublished_by: null, unpublished_at: null,
    created_at: "2026-11-19T00:00:00Z", updated_at: "2026-11-19T00:00:00Z", ...overrides,
  };
}

function workspace(role: "admin" | "instructor", revisions: TopicRevision[], withTopic = true): CurriculumWorkspace {
  return {
    role,
    actorId: role === "admin" ? admin : author,
    cocs: [{ coc_code: "coc1", title: "Install and Configure Computer Systems", order_index: 1 }],
    modules: [
      { id: "lo11", coc_module_id: "c1", coc_code: "coc1", code: "LO1.1", title: "Assemble computer hardware", element_title: null,
        sequence_order: 1, source_reference: "TR curriculum LO 1.1, TR_current.txt L3038-3039", created_at: "" },
    ],
    outcomes: [
      { id: "pc-14", module_id: "lo11", code: "1.4", statement: "Computer hardware is assembled in accordance with established procedures and systems requirements",
        sequence_order: 4, source_reference: "TR L1936-1937", created_at: "" },
    ],
    topics: withTopic ? [{ id: "topic-1", module_id: "lo11", sequence_order: 1, created_by: author, created_at: "", archived_at: null }] : [],
    revisions,
    events: [{ id: 1, entity_type: "topic", entity_id: "topic-1", revision_id: "rev-1", from_status: null, to_status: "draft",
      actor_id: author, note: "Topic created", occurred_at: "2026-11-19T01:00:00Z" }],
    missions: [{ mission_code: "coc1_m2", module_id: "lo11", pc_codes: ["1.4"], sequence_order: 2, title: "Install Internal Components" }],
    people: { [author]: "QA Instructor", [admin]: "QA Admin" },
  };
}

const render = (data: CurriculumWorkspace) =>
  renderToStaticMarkup(
    <AppRouterContext.Provider value={router}>
      <CurriculumWorkspaceView workspace={data} initialTab="coc1" />
    </AppRouterContext.Provider>,
  );

test("module view shows the official outcome, criteria, source and linked missions read-only", () => {
  const html = render(workspace("instructor", [revision({})]));
  assert.match(html, /Assemble computer hardware/);
  assert.match(html, /Computer hardware is assembled in accordance with established procedures and systems requirements/);
  assert.match(html, /TR curriculum LO 1\.1, TR_current\.txt L3038-3039/);
  assert.match(html, /Install Internal Components/);
  assert.match(html, /official curriculum learning outcome \(read-only\)/);
});

test("an admin evaluates a submitted revision; an instructor cannot", () => {
  const submitted = [revision({ status: "submitted" })];
  const adminHtml = render(workspace("admin", submitted));
  assert.match(adminHtml, />Evaluate</);
  assert.match(adminHtml, /aria-current="step"[^>]*>Submitted/);
  assert.match(adminHtml, /Archive topic/);
  const instructorHtml = render(workspace("instructor", submitted));
  assert.doesNotMatch(instructorHtml, />Evaluate</);
  assert.doesNotMatch(instructorHtml, /Archive topic/);
  assert.match(instructorHtml, /Content locked/);
});

test("the author submits a draft and only an admin publishes an approved revision", () => {
  const draft = render(workspace("instructor", [revision({ status: "draft" })]));
  assert.match(draft, /Submit for evaluation/);
  assert.match(draft, /Edit draft/);
  const approvedInstructor = render(workspace("instructor", [revision({ status: "approved" })]));
  assert.doesNotMatch(approvedInstructor, />Publish</);
  const approvedAdmin = render(workspace("admin", [revision({ status: "approved" })]));
  assert.match(approvedAdmin, />Publish</);
});

test("a new draft keeps the published revision visible to learners", () => {
  const html = render(workspace("admin", [
    revision({ id: "rev-1", revision_number: 1, status: "published", published_at: "2026-11-19T02:00:00Z" }),
    revision({ id: "rev-2", revision_number: 2, status: "draft", title: "ESD precautions (update)" }),
  ]));
  assert.match(html, /Learners see revision 1/);
  assert.match(html, /Revision 2 in workflow/);
  assert.match(html, /Published · revision 1/);
  assert.match(html, />Unpublish</);
  assert.doesNotMatch(html, /Edit as a new revision/, "a second working revision cannot be opened");
});

test("a module without topics invites the first lesson", () => {
  const html = render(workspace("instructor", [], false));
  assert.match(html, /No topics yet — add the first lesson for this module/);
  assert.match(html, /Add topic/);
});

test("lesson preview renders formatting and shows HTML as text", () => {
  const html = renderToStaticMarkup(<MarkdownPreview source={"Wear the **strap**.\n\n<script>alert(1)</script>"} />);
  assert.match(html, /<strong>strap<\/strong>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<script>/);
});
