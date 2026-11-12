import assert from "node:assert/strict";
import { test } from "node:test";
import { enrollLearnerSchema, learnerSearchSchema, learnerSearchFilter, learnerEnrollmentState, enrollmentFailure } from "../src/lib/learners/enrollment";

test("search accepts partial names and email, trims whitespace and bounds pagination", () => {
  for (const q of ["Juan Dela Cruz", "dela", "MARIA@EXAMPLE.COM", "Cruz, Juan", "O'Neil", "first_last@school.edu"]) {
    assert.equal(learnerSearchSchema.parse({ q: ` ${q} ` }).q, q);
  }
  for (const input of [{ q: "a" }, { q: "**" }, { q: "ab", page: -1 }, { q: "ab", page: 101 }, { q: "ab", page: "invalid" }, { q: "a".repeat(101) }]) {
    assert.equal(learnerSearchSchema.safeParse(input).success, false);
  }
});

test("search quotes reserved filter characters and escapes literal LIKE wildcards", () => {
  const term = 'Cruz, (Juan) "J"_100%\\';
  const filter = learnerSearchFilter(term);
  const expected = JSON.stringify('%Cruz, (Juan) "J"\\_100\\%\\\\%');
  assert.equal(filter, `full_name.ilike.${expected},email.ilike.${expected}`);
  assert.match(learnerSearchFilter("MARIA"), /^full_name\.ilike\./);
});

test("enrollment accepts a stable learner UUID, never a name or email", () => {
  const id = "b3189cf1-9dd4-4ee4-a6b2-9856b8310c99";
  assert.deepEqual(enrollLearnerSchema.parse({ learnerId: id }), { learnerId: id });
  for (const input of [{ learnerId: "Maria Santos" }, { email: "maria@example.com" }, { learnerId: id, fullName: "Maria" }]) {
    assert.equal(enrollLearnerSchema.safeParse(input).success, false);
  }
});

test("active enrollment takes precedence over retained inactive membership history", () => {
  assert.equal(learnerEnrollmentState([]), "not_enrolled");
  assert.equal(learnerEnrollmentState(["deactivated"]), "previously_enrolled");
  assert.equal(learnerEnrollmentState(["deactivated", "active"]), "active");
});

test("enrollment errors distinguish duplicate, eligibility and class scope without raw database details", () => {
  assert.equal(enrollmentFailure("23505").status, 409);
  assert.equal(enrollmentFailure("22023").status, 422);
  assert.equal(enrollmentFailure("42501").status, 403);
  assert.equal(enrollmentFailure("sensitive-database-error").status, 503);
  assert(!enrollmentFailure("sensitive-database-error").message.includes("sensitive-database-error"));
});
