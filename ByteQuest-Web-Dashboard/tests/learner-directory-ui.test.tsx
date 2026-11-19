import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { DirectorySearchControls, directoryHref } from "../src/components/learners/DirectorySearchControls";
import { DirectoryError, LearnerDirectoryTable } from "../src/components/learners/LearnerDirectoryTable";
import { parseLearnerSearchParams, type LearnerSearchResult } from "../src/lib/learners/search";

const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
const withRouter = (node: React.ReactNode) => renderToStaticMarkup(<AppRouterContext.Provider value={router}>{node}</AppRouterContext.Provider>);

const result: LearnerSearchResult = {
  total: 2,
  limit: 25,
  offset: 0,
  rows: [
    { user_id: "u1", full_name: "Juan Dela Cruz", email: "juan@school.edu.ph", learner_id: "S-1002", learner_id_managed: true, status: "active", classes: [{ id: "c1", title: "BSIT 2A" }, { id: "c2", title: "BSIT 2B" }], last_activity_at: "2026-11-18T02:00:00Z", created_at: "2026-11-01T02:00:00Z" },
    { user_id: "u2", full_name: "Pedro Inactive", email: "pedro@school.edu.ph", learner_id: null, learner_id_managed: false, status: "deactivated", classes: [], last_activity_at: null, created_at: "2026-11-02T02:00:00Z" },
  ],
};

test("results show learners with sortable headers, classes, managed IDs and pagination", () => {
  const filters = parseLearnerSearchParams({ q: "cruz", sort: "student_id" });
  const html = renderToStaticMarkup(<LearnerDirectoryTable basePath="/learners" filters={filters} result={result} rowHref={(row) => `/users/${row.user_id}/edit`} showCreated emptyTitle="No learners" emptyText="None yet" />);
  assert.match(html, /href="\/users\/u1\/edit"/);
  assert.match(html, /aria-sort="ascending"/);
  assert.equal((html.match(/aria-sort="none"/g) ?? []).length, 3);
  assert.match(html, /href="\/learners\?q=cruz&amp;sort=student_id&amp;dir=desc"/);
  assert.match(html, /href="\/learners\?q=cruz&amp;sort=last_activity"/);
  assert.match(html, /\(staff-managed\)/);
  assert.match(html, /BSIT 2A<\/li><li>BSIT 2B/);
  assert.match(html, /No active class/);
  assert.match(html, /No activity yet/);
  assert.match(html, /Showing 1–2 of 2 learners/);
  assert.match(html, /aria-disabled="true"[^>]*>.*Previous/);
});

test("empty, filtered-empty and past-the-end states are distinct", () => {
  const empty = { total: 0, limit: 25, offset: 0, rows: [] };
  const none = renderToStaticMarkup(<LearnerDirectoryTable basePath="/progress" filters={parseLearnerSearchParams({})} result={empty} rowHref={() => "#"} emptyTitle="No learners in your classes yet." emptyText="Enroll learners." />);
  assert.match(none, /No learners in your classes yet\./);
  const filtered = renderToStaticMarkup(<LearnerDirectoryTable basePath="/progress" filters={parseLearnerSearchParams({ q: "zzz" })} result={empty} rowHref={() => "#"} emptyTitle="x" emptyText="y" />);
  assert.match(filtered, /No learners match these filters\./);
  assert.match(filtered, /href="\/progress"[^>]*>Clear filters/);
  const past = renderToStaticMarkup(<LearnerDirectoryTable basePath="/progress" filters={parseLearnerSearchParams({ page: "9" })} result={{ total: 30, limit: 25, offset: 200, rows: [] }} rowHref={() => "#"} emptyTitle="x" emptyText="y" />);
  assert.match(past, /This page is past the last result\./);
  assert.match(past, /href="\/progress"[^>]*>First page/);
});

test("the search form is a labelled GET form with filters that keep sort state", () => {
  const html = withRouter(
    <DirectorySearchControls
      action="/learners"
      label="Search learners"
      placeholder="Name, email, student ID or class"
      query="maria"
      hidden={{ sort: "created" }}
      clearHref="/learners"
      filtered
      selects={[{ name: "status", label: "Account status", value: "inactive", options: [{ value: "all", label: "All" }, { value: "inactive", label: "Inactive" }] }]}
    />,
  );
  assert.match(html, /<form[^>]*action="\/learners"[^>]*method="get"/);
  assert.match(html, /role="search"/);
  assert.match(html, /aria-label="Search learners"/);
  assert.match(html, /type="search"[^>]*value="maria"|value="maria"[^>]*type="search"/);
  assert.match(html, /<option value="inactive" selected="">/);
  assert.match(html, /type="hidden" name="sort" value="created"/);
  assert.match(html, /Clear filters/);
  assert.equal(directoryHref("/learners", [["q", " maria "], ["class", "all"], ["status", "inactive"], ["sort", "created"]]), "/learners?q=maria&status=inactive&sort=created");
  assert.equal(directoryHref("/learners", [["q", ""], ["status", "all"]]), "/learners");
});

test("directory errors are announced with a retry link and no implementation details", () => {
  const html = renderToStaticMarkup(<DirectoryError message="Learner search is unavailable right now. Try again in a moment." retryHref="/learners?q=ana" />);
  assert.match(html, /role="alert"/);
  assert.match(html, /href="\/learners\?q=ana"/);
  assert.doesNotMatch(html, /SQL|PostgREST|exception/i);
});
