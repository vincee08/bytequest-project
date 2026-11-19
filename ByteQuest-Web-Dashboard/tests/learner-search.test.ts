import assert from "node:assert/strict";
import { test } from "node:test";
import {
  LEARNER_PAGE_SIZE,
  accountSearchFilter,
  learnerSearchHref,
  learnerSearchRpcArgs,
  learnerSortHref,
  pageWindow,
  parseLearnerSearchParams,
  parseUserDirectoryParams,
  userDirectoryHref,
} from "../src/lib/learners/search";

const classId = "75d06c08-b60b-4cbc-a26e-fc0bb344b58e";

test("search params are normalised with safe defaults", () => {
  assert.deepEqual(parseLearnerSearchParams({}), { q: "", classId: null, status: "all", sort: "name", direction: "asc", page: 1 });
  assert.deepEqual(
    parseLearnerSearchParams({ q: "  Dela Cruz ", class: classId, status: "inactive", sort: "last_activity", page: "3" }),
    { q: "Dela Cruz", classId, status: "inactive", sort: "last_activity", direction: "desc", page: 3 },
  );
  assert.deepEqual(
    parseLearnerSearchParams({ q: ["first", "second"], class: "not-a-uuid", status: "archived", sort: "grade", dir: "sideways", page: "-2" }),
    { q: "first", classId: null, status: "all", sort: "name", direction: "asc", page: 1 },
  );
  assert.equal(parseLearnerSearchParams({ q: "x".repeat(300) }).q.length, 100);
  assert.equal(parseLearnerSearchParams({ q: "a\u0000b" }).q, "ab");
  assert.equal(parseLearnerSearchParams({ sort: "student_id", dir: "desc" }).direction, "desc");
});

test("filters become search_learners arguments with 25 rows per page", () => {
  assert.equal(LEARNER_PAGE_SIZE, 25);
  assert.deepEqual(learnerSearchRpcArgs({ q: "", classId: null, status: "all", sort: "name", direction: "asc", page: 1 }), {
    p_query: null, p_class_id: null, p_status: null, p_sort: "name.asc", p_limit: 25, p_offset: 0,
  });
  assert.deepEqual(learnerSearchRpcArgs({ q: "maria", classId, status: "active", sort: "created", direction: "desc", page: 3 }), {
    p_query: "maria", p_class_id: classId, p_status: "active", p_sort: "created.desc", p_limit: 25, p_offset: 50,
  });
});

test("links keep filters, omit defaults and reset to page one when filters change", () => {
  const filters = parseLearnerSearchParams({ q: "maria santos", class: classId, status: "inactive", page: "4" });
  assert.equal(learnerSearchHref("/learners", filters, {}), `/learners?q=maria+santos&class=${classId}&status=inactive&page=4`);
  assert.equal(learnerSearchHref("/learners", filters, { page: 1 }), `/learners?q=maria+santos&class=${classId}&status=inactive`);
  assert.equal(learnerSearchHref("/learners", parseLearnerSearchParams({}), {}), "/learners");
});

test("sortable headers toggle direction for the active column and use defaults for others", () => {
  const byName = parseLearnerSearchParams({ q: "ana", page: "2" });
  assert.equal(learnerSortHref("/progress", byName, "name"), "/progress?q=ana&dir=desc");
  assert.equal(learnerSortHref("/progress", byName, "last_activity"), "/progress?q=ana&sort=last_activity");
  const desc = parseLearnerSearchParams({ sort: "created", dir: "asc" });
  assert.equal(learnerSortHref("/progress", desc, "created"), "/progress?sort=created");
});

test("page windows describe the visible range", () => {
  assert.deepEqual(pageWindow(0, 1), { from: 0, to: 0, pages: 1 });
  assert.deepEqual(pageWindow(132, 1), { from: 1, to: 25, pages: 6 });
  assert.deepEqual(pageWindow(132, 6), { from: 126, to: 132, pages: 6 });
  // A page past the end has from > to; the page shows a "past the end" empty state.
  assert.deepEqual(pageWindow(50, 9), { from: 201, to: 50, pages: 2 });
});

test("the account search filter quotes values and escapes LIKE wildcards", () => {
  const filter = accountSearchFilter('Cruz, (Juan) "J"_100%');
  const quoted = JSON.stringify('%Cruz, (Juan) "J"\\_100\\%%');
  assert.equal(filter, `full_name.ilike.${quoted},email.ilike.${quoted},learner_id.ilike.${quoted}`);
});

test("the account directory filters by role and status and keeps links stable", () => {
  assert.deepEqual(parseUserDirectoryParams({}), { q: "", role: "all", status: "all", sort: "created", page: 1 });
  const filters = parseUserDirectoryParams({ q: " Cruz ", role: "instructor", status: "inactive", sort: "name", page: "2" });
  assert.deepEqual(filters, { q: "Cruz", role: "instructor", status: "inactive", sort: "name", page: 2 });
  assert.equal(userDirectoryHref(filters, { page: 1 }), "/users?q=Cruz&role=instructor&status=inactive&sort=name");
  assert.equal(userDirectoryHref(parseUserDirectoryParams({ role: "superuser", status: "gone" }), {}), "/users");
});
