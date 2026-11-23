import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { RosterImportWorkspace } from "../src/components/roster/RosterImportWorkspace";
import { RosterOutcomePanel } from "../src/components/roster/RosterOutcomePanel";
import { PendingRosterEntries } from "../src/components/roster/PendingRosterEntries";
import {
  rosterErrorReportCsv,
  rosterFileProblem,
  rosterGroupRows,
  type RosterFileInfo,
  type RosterOutcome,
  type RosterResultRow,
} from "../src/lib/roster/types";

const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
const withRouter = (node: React.ReactNode) => renderToStaticMarkup(<AppRouterContext.Provider value={router}>{node}</AppRouterContext.Provider>);

const row = (over: Partial<RosterResultRow> & Pick<RosterResultRow, "row_number" | "status" | "message">): RosterResultRow => ({
  student_id: null, last_name: "Cruz", first_name: "Juan", email: `row${over.row_number}@school.edu.ph`, course_section: null, ...over,
});

const outcome: RosterOutcome = {
  class_id: "75d06c08-b60b-4cbc-a26e-fc0bb344b58e",
  class_title: "BSIT 2A",
  applied: false,
  batch_id: null,
  file_name: null,
  summary: { total: 6, enroll_now: 1, already_enrolled: 1, enrolled_elsewhere: 0, pending_elsewhere: 0, pending: 1, conflict_student_id: 1, staff_account: 1, invalid: 1 },
  rows: [
    row({ row_number: 2, status: "enroll_now", message: "Registered learner account found. Enrolls when you confirm.", learner_name: "Juan Dela Cruz" }),
    row({ row_number: 3, status: "already_enrolled", message: "Already enrolled in this class." }),
    row({ row_number: 4, status: "pending", message: "No account yet. Enrolls automatically when this email signs up." }),
    row({ row_number: 5, status: "conflict_student_id", student_id: "2024-1", message: "Student ID already belongs to another learner account." }),
    row({ row_number: 6, status: "staff_account", message: "This email belongs to a staff account. Staff accounts are never enrolled as learners." }),
    row({ row_number: 7, status: "invalid", first_name: null, message: "Missing required field: first_name." }),
  ],
};
const file: RosterFileInfo = {
  name: "BSIT 2A roster.xlsx", size: 4096, sha256: "a".repeat(64), format: "xlsx", sheetName: "Roster", headerRow: 1,
  ignoredColumns: ["Middle Name"], blankRowsSkipped: 2, exampleRowsSkipped: 1,
};

test("the import workspace offers the template and an Excel-only, server-checked upload", () => {
  const html = withRouter(<RosterImportWorkspace classId={outcome.class_id} classTitle="BSIT 2A" />);
  assert.match(html, /href="\/api\/roster\/template"/);
  assert.match(html, /accept="\.xlsx,\.xls"/);
  assert.match(html, /type="file"/);
  assert.match(html, /nothing changes in BSIT 2A until you confirm/);
  const previewButton = html.split("<button").find((chunk) => chunk.includes("Preview roster")) ?? "";
  assert.match(previewButton, /^[^>]*disabled=""/, "preview stays disabled until a file is chosen");
});

test("the preview groups rows as Enroll now / Pending / Skip / Invalid with counts and messages", () => {
  const html = renderToStaticMarkup(<RosterOutcomePanel outcome={outcome} file={file} mode="preview" />);
  for (const [key, count] of [["enroll_now", 1], ["pending", 1], ["skip", 3], ["invalid", 1]] as const) {
    assert.match(html, new RegExp(`data-testid="roster-count-${key}">${count}<`));
  }
  assert.match(html, /Account: Juan Dela Cruz/);
  assert.match(html, /Missing required field: first_name\./);
  assert.match(html, /Student ID conflict/);
  assert.match(html, /2 blank rows skipped/);
  assert.match(html, /1 example row ignored/);
  assert.match(html, /Ignored columns: Middle Name/);
  assert.match(html, /download="roster-errors-BSIT-2A-roster\.csv"/);
  assert.match(html, /Download error report \(CSV, 3 rows\)/);
});

test("an applied result relabels enrolled and pending rows", () => {
  const html = renderToStaticMarkup(<RosterOutcomePanel outcome={{ ...outcome, applied: true }} file={file} mode="result" />);
  assert.match(html, />Enrolled</);
  assert.match(html, /Pending saved/);
});

test("a preview with nothing importable explains why confirm is unavailable", () => {
  const blocked: RosterOutcome = { ...outcome, summary: { ...outcome.summary, enroll_now: 0, pending: 0 }, rows: outcome.rows.filter((r) => r.status !== "enroll_now" && r.status !== "pending") };
  const html = renderToStaticMarkup(<RosterOutcomePanel outcome={blocked} file={file} mode="preview" />);
  assert.match(html, /Nothing in this file can be imported/);
});

test("the CSV error report lists only problem rows and neutralises formulas", () => {
  const csv = rosterErrorReportCsv([...outcome.rows, row({ row_number: 9, status: "invalid", last_name: "=HYPERLINK(\"x\")", message: "Email address is not valid." })]);
  const lines = csv.trim().split("\r\n");
  assert.equal(lines[0], "row_number,student_id,last_name,first_name,email,course_section,status,message");
  assert.equal(lines.length, 5);
  assert.ok(lines.some((line) => line.startsWith("5,2024-1,Cruz,Juan,")));
  assert.ok(lines.every((line) => !line.startsWith("2,") && !line.startsWith("3,") && !line.startsWith("4,")));
  assert.ok(lines.some((line) => line.includes("\"'=HYPERLINK(\"\"x\"\")\"")));
  assert.deepEqual(rosterGroupRows(outcome.rows).map((group) => group.rows.length), [1, 1, 3, 1]);
});

test("the client pre-check mirrors the server file limits", () => {
  assert.match(rosterFileProblem({ name: "roster.csv", size: 10 }) ?? "", /\.xlsx or \.xls/);
  assert.match(rosterFileProblem({ name: "roster.xlsx", size: 2 * 1024 * 1024 + 1 }) ?? "", /2 MB/);
  assert.match(rosterFileProblem({ name: "roster.xlsx", size: 0 }) ?? "", /empty/);
  assert.equal(rosterFileProblem({ name: "Roster.XLS", size: 2048 }), null);
});

test("pending roster entries render with a cancel action only for the owning instructor", () => {
  const entries = [{ id: "e1", name: "Pending, Paula", email: "paula@school.edu.ph", studentId: "2024-9", courseSection: "A", createdAt: "2026-11-19T02:00:00Z" }];
  assert.match(withRouter(<PendingRosterEntries classId={outcome.class_id} entries={entries} canManage />), /Cancel entry/);
  assert.doesNotMatch(withRouter(<PendingRosterEntries classId={outcome.class_id} entries={entries} canManage={false} />), /Cancel entry/);
  assert.match(withRouter(<PendingRosterEntries classId={outcome.class_id} entries={[]} canManage />), /No pending roster entries/);
});

test("learners in another class and emails waiting for another class are skipped, labelled and reported", () => {
  const oneClass = "This learner is already enrolled in another class. A learner can belong to only one class at a time.";
  const waiting = "This email is already waiting to join another class. A learner can belong to only one class at a time.";
  const rows = [
    row({ row_number: 2, status: "enrolled_elsewhere", message: oneClass, learner_name: "Juan Dela Cruz" }),
    row({ row_number: 3, status: "pending_elsewhere", message: waiting }),
    row({ row_number: 4, status: "enroll_now", message: "Registered learner account found. Enrolls when you confirm." }),
  ];
  const skipped: RosterOutcome = {
    ...outcome,
    summary: { total: 3, enroll_now: 1, already_enrolled: 0, enrolled_elsewhere: 1, pending_elsewhere: 1, pending: 0, conflict_student_id: 0, staff_account: 0, invalid: 0 },
    rows,
  };
  assert.deepEqual(rosterGroupRows(rows).map((group) => group.rows.length), [1, 0, 2, 0]);
  const html = renderToStaticMarkup(<RosterOutcomePanel outcome={skipped} file={file} mode="preview" />);
  assert.match(html, /data-testid="roster-count-skip">2</);
  assert.match(html, /In another class/);
  assert.match(html, /Waiting for another class/);
  assert.match(html, /A learner can belong to only one class at a time\./);
  const csv = rosterErrorReportCsv(rows).trim().split("\r\n");
  assert.equal(csv.length, 3, "both skipped rows are in the error report; the enrollable row is not");
  assert.ok(csv.some((line) => line.startsWith("2,") && line.includes("In another class")));
});
