import assert from "node:assert/strict";
import test from "node:test";
import { escapeCsvCell } from "../src/lib/csv";

test("CSV cells escape delimiters and embedded quotes", () => {
  assert.equal(escapeCsvCell('Review cable, then "retry"'), '"Review cable, then ""retry"""');
  assert.equal(escapeCsvCell("line one\nline two"), '"line one\nline two"');
  assert.equal(escapeCsvCell(42), "42");
});

test("CSV cells neutralize spreadsheet formulas without changing numbers", () => {
  for (const value of ["=1+1", "+SUM(A1:A2)", "-2+3", "@SUM(A1:A2)", "\t=cmd"]) {
    assert.equal(escapeCsvCell(value).startsWith("'"), true, value);
  }
  assert.equal(escapeCsvCell(-42), "-42");
});
