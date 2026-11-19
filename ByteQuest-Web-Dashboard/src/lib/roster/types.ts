import { escapeCsvCell } from "@/lib/csv";

/** Client-safe roster import types and helpers (no SheetJS, no server code). */

export const ROSTER_COLUMNS = ["student_id", "last_name", "first_name", "email", "course_section"] as const;
export type RosterColumn = (typeof ROSTER_COLUMNS)[number];
export const ROSTER_MAX_BYTES = 2 * 1024 * 1024;
export const ROSTER_MAX_ROWS = 1000;
export const ROSTER_ACCEPT = ".xlsx,.xls";

export type RosterInputRow = { row_number: number } & Record<RosterColumn, string>;

export type RosterRowStatus =
  | "enroll_now"
  | "already_enrolled"
  | "pending"
  | "conflict_student_id"
  | "staff_account"
  | "invalid";

export type RosterResultRow = {
  row_number: number;
  student_id: string | null;
  last_name: string | null;
  first_name: string | null;
  email: string | null;
  course_section: string | null;
  status: RosterRowStatus;
  message: string;
  learner_name?: string | null;
  student_id_assigned?: boolean;
};

export type RosterSummary = Record<RosterRowStatus, number> & { total: number };

export type RosterOutcome = {
  class_id: string;
  class_title: string;
  applied: boolean;
  batch_id: string | null;
  file_name: string | null;
  summary: RosterSummary;
  rows: RosterResultRow[];
};

export type RosterFileInfo = {
  name: string;
  size: number;
  sha256: string;
  format: "xlsx" | "xls";
  sheetName: string;
  headerRow: number;
  ignoredColumns: string[];
  blankRowsSkipped: number;
  exampleRowsSkipped: number;
};

export type RosterEntryRow = {
  id: string;
  class_id: string;
  email_normalized: string;
  student_id: string | null;
  last_name: string;
  first_name: string;
  course_section: string | null;
  status: "pending" | "enrolled" | "cancelled";
  import_batch_id: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  claimed_user_id: string | null;
  claimed_at: string | null;
};

export type RosterBatchRow = {
  id: string;
  class_id: string;
  instructor_id: string;
  file_name: string | null;
  row_count: number;
  enrolled_count: number;
  pending_count: number;
  skipped_count: number;
  invalid_count: number;
  created_at: string;
};

export type RosterPreviewResponse = { file: RosterFileInfo; preview: RosterOutcome };
export type RosterImportResponse = { file: RosterFileInfo; result: RosterOutcome };

export type RosterGroupKey = "enroll_now" | "pending" | "skip" | "invalid";

export const rosterGroups: { key: RosterGroupKey; title: string; description: string; statuses: RosterRowStatus[] }[] = [
  { key: "enroll_now", title: "Enroll now", description: "Registered learner accounts that are enrolled when you confirm.", statuses: ["enroll_now"] },
  { key: "pending", title: "Pending", description: "No account yet. Each enrolls automatically after signing up with the same email.", statuses: ["pending"] },
  { key: "skip", title: "Skip", description: "Already enrolled, a student ID conflict, or a staff account. Not changed by the import.", statuses: ["already_enrolled", "conflict_student_id", "staff_account"] },
  { key: "invalid", title: "Invalid", description: "Rows with a missing field, an invalid email or a duplicate in the file. Never imported.", statuses: ["invalid"] },
];

export const rosterStatusLabels: Record<RosterRowStatus, string> = {
  enroll_now: "Enroll now",
  already_enrolled: "Already enrolled",
  pending: "Pending sign-up",
  conflict_student_id: "Student ID conflict",
  staff_account: "Staff account",
  invalid: "Invalid",
};

export const rosterAppliedLabels: Record<RosterRowStatus, string> = {
  ...rosterStatusLabels,
  enroll_now: "Enrolled",
  pending: "Pending saved",
};

export function rosterGroupRows(rows: readonly RosterResultRow[]) {
  return rosterGroups.map((group) => ({ ...group, rows: rows.filter((row) => group.statuses.includes(row.status)) }));
}

export function rosterProblemRows(rows: readonly RosterResultRow[]) {
  return rows.filter((row) => row.status === "invalid" || row.status === "conflict_student_id" || row.status === "staff_account");
}

/** CSV of every row that was not imported because of a problem. */
export function rosterErrorReportCsv(rows: readonly RosterResultRow[]) {
  const header = ["row_number", ...ROSTER_COLUMNS, "status", "message"];
  const lines = rosterProblemRows(rows).map((row) => [
    row.row_number, row.student_id, row.last_name, row.first_name, row.email, row.course_section, rosterStatusLabels[row.status], row.message,
  ].map(escapeCsvCell).join(","));
  return `${[header.join(","), ...lines].join("\r\n")}\r\n`;
}

/** Client pre-check mirroring the server limits for immediate feedback. */
export function rosterFileProblem(file: { name: string; size: number } | null): string | null {
  if (!file) return "Choose an Excel roster file (.xlsx or .xls).";
  const name = file.name.toLowerCase();
  if (!name.endsWith(".xlsx") && !name.endsWith(".xls")) return "Upload an Excel workbook (.xlsx or .xls). CSV, PDF and other file types are not accepted.";
  if (file.size === 0) return "The file is empty. Fill in the roster template and upload it again.";
  if (file.size > ROSTER_MAX_BYTES) return "The file is larger than 2 MB. Remove unused sheets or split the roster.";
  return null;
}

export function rosterImportableCount(summary: RosterSummary) {
  return summary.enroll_now + summary.pending;
}
