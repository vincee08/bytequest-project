import assert from "node:assert/strict";
import test from "node:test";
import { buildCriterionAdjustment, type ReviewCriterion } from "../src/lib/attempts/criterion-adjustment";

const criteria: ReviewCriterion[] = [
  { id: "c1", code: "SAFE_INSPECTION", title: "Safe inspection", isRequired: true, maxValue: 1, scoringRule: { status: "APPROVED", method: "binary", satisfied_value: 1, not_satisfied_value: 0 } },
  { id: "c2", code: "TEST_RESULT", title: "Test result", isRequired: true, maxValue: 1, scoringRule: { status: "APPROVED", method: "binary", satisfied_value: 1, not_satisfied_value: 0 } },
];
const provisional = [
  { criterion_id: "c1", observation: "satisfied", score_value: 1, observed_evidence: { tool: "tester" } },
  { criterion_id: "c2", observation: "not_satisfied", score_value: 0, observed_evidence: { result: "fail" } },
];

test("instructor correction recalculates rubric total without changing original evidence", () => {
  const reviewed = buildCriterionAdjustment(provisional, criteria, { c2: "satisfied" });
  assert.ok(reviewed);
  assert.equal(reviewed.totalValue, 2);
  assert.equal(reviewed.maxValue, 2);
  assert.equal(reviewed.percentage, 100);
  assert.equal(reviewed.suggestedOutcome, "competent");
  assert.equal(reviewed.changed, true);
  assert.deepEqual(provisional[1].observed_evidence, { result: "fail" });
  assert.deepEqual((reviewed.criterionValues as typeof provisional)[1].observed_evidence, { result: "fail" });
});

test("unchanged review preserves the criterion-based provisional values", () => {
  const reviewed = buildCriterionAdjustment(provisional, criteria, {});
  assert.ok(reviewed);
  assert.equal(reviewed.totalValue, 1);
  assert.equal(reviewed.percentage, 50);
  assert.equal(reviewed.suggestedOutcome, "not_yet_competent");
  assert.equal(reviewed.changed, false);
});

test("invalid or incomplete rubric values cannot be used to calculate a correction", () => {
  assert.equal(buildCriterionAdjustment(provisional.slice(0, 1), criteria, {}), null);
  assert.equal(buildCriterionAdjustment(provisional, [{ ...criteria[0], maxValue: 0 }, criteria[1]], {}), null);
  assert.equal(buildCriterionAdjustment(provisional, [{ ...criteria[0], scoringRule: { status: "PENDING_TESDA_VALIDATION" } }, criteria[1]], {}), null);
});
