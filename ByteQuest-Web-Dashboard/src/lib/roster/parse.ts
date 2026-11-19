import "server-only";

import * as XLSX from "xlsx";
import { ROSTER_COLUMNS, ROSTER_MAX_BYTES, ROSTER_MAX_ROWS, type RosterColumn, type RosterInputRow } from "./types";

export { ROSTER_COLUMNS, ROSTER_MAX_BYTES, ROSTER_MAX_ROWS } from "./types";

/**
 * Server-side roster workbook parsing (SheetJS 0.20.3, official tarball).
 * Structure only: file type and size, header mapping, blank and example rows,
 * row limit, whitespace and email normalisation. Every business rule (required
 * fields, email format, duplicates, accounts, enrollment) is decided by the
 * database in preview_class_roster / import_class_roster.
 */

export type RosterParseErrorCode =
  | "FILE_TYPE"
  | "FILE_EMPTY"
  | "FILE_TOO_LARGE"
  | "FILE_UNREADABLE"
  | "HEADERS_MISSING"
  | "NO_DATA_ROWS"
  | "TOO_MANY_ROWS";

export type RosterParseSuccess = {
  ok: true;
  format: "xlsx" | "xls";
  sheetName: string;
  headerRow: number;
  columns: Partial<Record<RosterColumn, string>>;
  ignoredColumns: string[];
  rows: RosterInputRow[];
  blankRowsSkipped: number;
  exampleRowsSkipped: number;
};
export type RosterParseFailure = { ok: false; code: RosterParseErrorCode; message: string };
export type RosterParseResult = RosterParseSuccess | RosterParseFailure;

const REQUIRED_COLUMNS: readonly RosterColumn[] = ["last_name", "first_name", "email"];
const HEADER_SCAN_ROWS = 20;
const MAX_CELL_LENGTH = 500;
// A real roster workbook inflates to well under 1 MB; refuse ZIP bombs.
const MAX_UNCOMPRESSED_BYTES = 25 * 1024 * 1024;
const MAX_ZIP_ENTRIES = 500;
const TEMPLATE_HINT = `Use the template headers: ${ROSTER_COLUMNS.join(", ")}.`;

const HEADER_ALIASES: Record<RosterColumn, readonly string[]> = {
  student_id: ["studentid", "studentno", "studentnumber", "studentidnumber", "studentidno", "learnerid", "idnumber", "idno", "lrn", "uli"],
  last_name: ["lastname", "surname", "familyname", "lname"],
  first_name: ["firstname", "givenname", "forename", "fname"],
  email: ["email", "emailaddress", "emailadd", "mail", "eaddress", "emailid"],
  course_section: ["coursesection", "courseandsection", "section", "course", "set", "sectionset", "courseset", "coursesectionset", "classsection", "yearsection", "courseyearsection"],
};
const ALIAS_LOOKUP = new Map<string, RosterColumn>(
  (Object.entries(HEADER_ALIASES) as [RosterColumn, readonly string[]][]).flatMap(([column, aliases]) => aliases.map((alias) => [alias, column] as const)),
);

export const ROSTER_TEMPLATE_EXAMPLE: Record<RosterColumn, string> = {
  student_id: "EXAMPLE-0001",
  last_name: "Dela Cruz",
  first_name: "Juan",
  email: "juan.delacruz@example.com",
  course_section: "Example row - ignored on import",
};

/** Maps a header cell to a roster column, ignoring case, spaces, underscores and punctuation. */
export function normalizeRosterHeader(header: unknown): RosterColumn | null {
  const key = String(header ?? "").normalize("NFKC").toLowerCase().replace(/[^a-z0-9]+/g, "");
  return key ? ALIAS_LOOKUP.get(key) ?? null : null;
}

function cleanText(value: string) {
  return value
    .normalize("NFKC")
    .replace(/[​-‍⁠﻿]/g, "")
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_CELL_LENGTH);
}

function cellText(cell: XLSX.CellObject | undefined): string {
  if (!cell || cell.t === "e" || cell.t === "z") return "";
  const value = cell.v;
  if (cell.t === "n" && typeof value === "number" && Number.isInteger(value) && Math.abs(value) < 1e15
      && !(typeof cell.z === "string" && XLSX.SSF.is_date(cell.z))) {
    return String(value);
  }
  return cleanText(String(cell.w ?? value ?? ""));
}

function startsWith(bytes: Uint8Array, signature: readonly number[]) {
  return bytes.length >= signature.length && signature.every((byte, index) => bytes[index] === byte);
}
const ZIP_SIGNATURE = [0x50, 0x4b, 0x03, 0x04];
const OLE_SIGNATURE = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];

/** Sums the uncompressed sizes in a ZIP central directory; null when malformed. */
function zipUncompressedBytes(bytes: Uint8Array): number | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const floor = Math.max(0, bytes.length - 65557);
  let end = -1;
  for (let index = bytes.length - 22; index >= floor; index -= 1) {
    if (view.getUint32(index, true) === 0x06054b50) { end = index; break; }
  }
  if (end < 0) return null;
  const entries = view.getUint16(end + 10, true);
  let offset = view.getUint32(end + 16, true);
  if (entries > MAX_ZIP_ENTRIES) return Number.POSITIVE_INFINITY;
  let total = 0;
  for (let entry = 0; entry < entries; entry += 1) {
    if (offset + 46 > bytes.length || view.getUint32(offset, true) !== 0x02014b50) return null;
    const size = view.getUint32(offset + 24, true);
    if (size === 0xffffffff) return Number.POSITIVE_INFINITY;
    total += size;
    offset += 46 + view.getUint16(offset + 28, true) + view.getUint16(offset + 30, true) + view.getUint16(offset + 32, true);
  }
  return total;
}

function formatMegabytes(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function failure(code: RosterParseErrorCode, message: string): RosterParseFailure {
  return { ok: false, code, message };
}

type HeaderMatch = { rowIndex: number; columns: Map<number, RosterColumn>; labels: Partial<Record<RosterColumn, string>>; ignored: string[]; required: number };

function matchHeader(row: (XLSX.CellObject | undefined)[] | undefined, rowIndex: number): HeaderMatch {
  const columns = new Map<number, RosterColumn>();
  const labels: Partial<Record<RosterColumn, string>> = {};
  const ignored: string[] = [];
  (row ?? []).forEach((cell, columnIndex) => {
    const label = cellText(cell);
    if (!label) return;
    const column = normalizeRosterHeader(label);
    if (column && !labels[column]) {
      columns.set(columnIndex, column);
      labels[column] = label;
    } else {
      ignored.push(label);
    }
  });
  return { rowIndex, columns, labels, ignored, required: REQUIRED_COLUMNS.filter((column) => labels[column]).length };
}

export function parseRosterFile(file: { name: string; size: number; bytes: Uint8Array }): RosterParseResult {
  const name = file.name.trim().toLowerCase();
  if (!name.endsWith(".xlsx") && !name.endsWith(".xls")) {
    return failure("FILE_TYPE", "Upload an Excel workbook (.xlsx or .xls). CSV, PDF and other file types are not accepted.");
  }
  const size = Math.max(file.size, file.bytes.byteLength);
  if (size === 0) return failure("FILE_EMPTY", "The file is empty. Fill in the roster template and upload it again.");
  if (size > ROSTER_MAX_BYTES) {
    return failure("FILE_TOO_LARGE", `The file is ${formatMegabytes(size)}; the limit is 2 MB. Remove unused sheets or split the roster.`);
  }

  const bytes = file.bytes;
  const isZip = startsWith(bytes, ZIP_SIGNATURE);
  const isOle = startsWith(bytes, OLE_SIGNATURE);
  if (!isZip && !isOle) {
    return failure("FILE_TYPE", "This file is not an Excel workbook (it may be a CSV or web page saved with an Excel name). Open it in Excel and save it as .xlsx.");
  }
  if (isZip) {
    const inflated = zipUncompressedBytes(bytes);
    if (inflated === null) return failure("FILE_UNREADABLE", "The workbook could not be read. Open it in Excel, save it again as .xlsx and retry.");
    if (inflated > MAX_UNCOMPRESSED_BYTES) {
      return failure("FILE_TOO_LARGE", "The workbook contains too much data to process. Keep only the roster sheet and at most 1,000 learners.");
    }
  }

  let book: XLSX.WorkBook;
  try {
    book = XLSX.read(bytes, {
      type: "array",
      dense: true,
      cellFormula: false,
      cellHTML: false,
      cellStyles: false,
      bookVBA: false,
      WTF: false,
    });
  } catch {
    return failure("FILE_UNREADABLE", "The workbook could not be read. It may be damaged or password-protected. Open it in Excel, save it again as .xlsx and retry.");
  }

  let best: { sheetName: string; match: HeaderMatch } | null = null;
  for (const sheetName of book.SheetNames) {
    const data = (book.Sheets[sheetName]?.["!data"] ?? []) as (XLSX.CellObject | undefined)[][];
    let scanned = 0;
    for (const key of Object.keys(data)) {
      const rowIndex = Number(key);
      if (scanned >= HEADER_SCAN_ROWS) break;
      const match = matchHeader(data[rowIndex], rowIndex);
      if (match.columns.size === 0) continue;
      scanned += 1;
      if (!best || match.required > best.match.required) best = { sheetName, match };
      if (match.required === REQUIRED_COLUMNS.length) break;
    }
    if (best?.match.required === REQUIRED_COLUMNS.length) break;
  }

  if (!best || best.match.required < REQUIRED_COLUMNS.length) {
    const missing = REQUIRED_COLUMNS.filter((column) => !best?.match.labels[column]);
    return failure("HEADERS_MISSING", `The roster is missing required column${missing.length === 1 ? "" : "s"}: ${missing.join(", ")}. ${TEMPLATE_HINT}`);
  }

  const { sheetName, match } = best;
  const data = (book.Sheets[sheetName]["!data"] ?? []) as (XLSX.CellObject | undefined)[][];
  const rows: RosterInputRow[] = [];
  let exampleRowsSkipped = 0;
  let lastContentRow = match.rowIndex;
  for (const key of Object.keys(data)) {
    const rowIndex = Number(key);
    if (rowIndex <= match.rowIndex) continue;
    const values: Record<RosterColumn, string> = { student_id: "", last_name: "", first_name: "", email: "", course_section: "" };
    match.columns.forEach((column, columnIndex) => {
      values[column] = cellText(data[rowIndex]?.[columnIndex]);
    });
    if (ROSTER_COLUMNS.every((column) => values[column] === "")) continue;
    lastContentRow = rowIndex;
    values.email = values.email.replace(/^mailto:/i, "").toLowerCase();
    if (values.student_id.toLowerCase().startsWith("example") || values.email.endsWith("@example.com")) {
      exampleRowsSkipped += 1;
      continue;
    }
    rows.push({ row_number: rowIndex + 1, ...values });
    if (rows.length > ROSTER_MAX_ROWS) {
      return failure("TOO_MANY_ROWS", `The roster has more than ${ROSTER_MAX_ROWS.toLocaleString("en-US")} learner rows. Split it into files of at most ${ROSTER_MAX_ROWS.toLocaleString("en-US")} learners and import each one.`);
    }
  }

  if (rows.length === 0) {
    return failure("NO_DATA_ROWS", exampleRowsSkipped
      ? "The roster has no learner rows yet; the example row is ignored. Add one learner per row below the headers."
      : "The roster has headers but no learner rows. Add one learner per row below the headers.");
  }

  return {
    ok: true,
    format: isZip ? "xlsx" : "xls",
    sheetName,
    headerRow: match.rowIndex + 1,
    columns: match.labels,
    ignoredColumns: match.ignored,
    rows,
    blankRowsSkipped: lastContentRow - match.rowIndex - rows.length - exampleRowsSkipped,
    exampleRowsSkipped,
  };
}

/** The downloadable template: exact headers, one marked example row and instructions. */
export function buildRosterTemplate(): Buffer {
  const roster = XLSX.utils.aoa_to_sheet([
    [...ROSTER_COLUMNS],
    ROSTER_COLUMNS.map((column) => ROSTER_TEMPLATE_EXAMPLE[column]),
  ]);
  roster["!cols"] = [{ wch: 16 }, { wch: 22 }, { wch: 22 }, { wch: 34 }, { wch: 32 }];
  const instructions = XLSX.utils.aoa_to_sheet([
    ["ByteQuest class roster template"],
    [""],
    ["Required columns: last_name, first_name, email. Optional: student_id, course_section."],
    ["Row 2 is an example (student ID starts with EXAMPLE). It is ignored on import, so you can keep or delete it."],
    ["Enter one learner per row. Blank rows and extra columns are ignored. Emails are matched without regard to letter case."],
    [`Limits: .xlsx or .xls file, at most 2 MB and ${ROSTER_MAX_ROWS.toLocaleString("en-US")} learner rows per import.`],
    ["Learners who already have a ByteQuest account are enrolled when you confirm the import."],
    ["New emails are saved as pending and enroll automatically when the learner signs up with the same email."],
    ["Nothing changes until you review the preview and confirm the import."],
  ]);
  instructions["!cols"] = [{ wch: 110 }];
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, roster, "Roster");
  XLSX.utils.book_append_sheet(book, instructions, "Instructions");
  return XLSX.write(book, { type: "buffer", bookType: "xlsx", compression: true }) as Buffer;
}
