import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

// The hosted dashboard renders on a UTC server (Vercel) and hydrates in a
// Manila browser. Dates must use the fixed Asia/Manila zone, or the two
// renders differ (hydration errors) and dates near midnight show the wrong
// day. Each test file runs in its own process, so this only affects this file.
process.env.TZ = "UTC";

// 23:30 UTC on 22 Nov is 07:30 on 23 Nov in Manila.
const lateEvening = "2026-11-22T23:30:00Z";

test("the curriculum publication history shows Manila time on a UTC server", async () => {
  const { PublicationTimeline } = await import("../src/components/curriculum/PublicationTimeline");
  const html = renderToStaticMarkup(
    <PublicationTimeline
      events={[{ id: 1, entity_type: "topic", entity_id: "topic-1", revision_id: null, from_status: null, to_status: "published", actor_id: null, note: null, occurred_at: lateEvening }]}
      revisions={[]}
      people={{}}
    />,
  );
  assert.match(html, /Nov 23, 2026/);
  assert.match(html, /7:30/);
});

test("the shared date formatters of the quiz and curriculum views use Manila time", async () => {
  const { formatDate, formatDateTime } = await import("../src/lib/analytics/format");
  assert.equal(formatDate(lateEvening), "Nov 23, 2026");
  assert.match(formatDateTime(lateEvening), /^Nov 23, 2026.*7:30/);
});
