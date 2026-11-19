import assert from "node:assert/strict";
import { test } from "node:test";
import { studentIdFailure, studentIdInputSchema } from "../src/lib/learners/student-id";

test("student ID input is trimmed, bounded and may be cleared", () => {
  assert.deepEqual(studentIdInputSchema.parse({ student_id: " 2026-0001 " }), { student_id: "2026-0001" });
  assert.deepEqual(studentIdInputSchema.parse({ student_id: "   " }), { student_id: null });
  assert.deepEqual(studentIdInputSchema.parse({ student_id: null }), { student_id: null });
  for (const input of [{ student_id: "x".repeat(65) }, { student_id: "a\u0000b" }, { student_id: 42 }, {}, { student_id: "ok", extra: true }]) {
    assert.equal(studentIdInputSchema.safeParse(input).success, false, JSON.stringify(input));
  }
});

test("database refusals map to specific, safe messages", () => {
  assert.equal(studentIdFailure({ code: "23505", message: "STUDENT_ID_IN_USE" }).status, 409);
  assert.match(studentIdFailure({ code: "23505", message: "STUDENT_ID_IN_USE" }).message, /another learner/);
  assert.equal(studentIdFailure({ code: "22023", message: "LEARNER_PROFILE_REQUIRED" }).status, 422);
  assert.equal(studentIdFailure({ code: "42501", message: "ADMIN_ACCESS_REQUIRED" }).status, 403);
  const unknown = studentIdFailure({ code: "XX000", message: "relation profiles exploded" });
  assert.equal(unknown.status, 503);
  assert.doesNotMatch(unknown.message, /relation|exploded/);
});
