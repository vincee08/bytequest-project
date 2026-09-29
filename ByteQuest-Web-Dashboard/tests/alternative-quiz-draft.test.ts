import assert from "node:assert/strict";
import test from "node:test";
import { buildAlternativeQuizDraftRequest } from "../src/lib/ai/alternative-quiz-draft";

test("single-item alternative uses the existing approved activity and original item type", () => {
  const request = buildAlternativeQuizDraftRequest({
    quizVersionId: "version-id",
    activityVersionId: "activity-id",
    topic: "Network cable testing",
    difficulty: "intermediate",
    itemType: "scenario_based",
    originalPrompt: "What action verifies the cable run?",
    instructorContext: "Focus on test interpretation.",
  });
  assert.equal(request.itemCount, 1);
  assert.deepEqual(request.itemTypes, ["scenario_based"]);
  assert.equal(request.activityVersionId, "activity-id");
  assert.match(request.instructorContext, /distinct alternative/);
  assert.match(request.instructorContext, /approved selected activity/);
  assert.match(request.instructorContext, /What action verifies the cable run/);
});

test("alternative context stays within the server's validated size limit", () => {
  const request = buildAlternativeQuizDraftRequest({
    quizVersionId: "version-id",
    activityVersionId: "activity-id",
    topic: "Testing",
    difficulty: "foundation",
    itemType: "multiple_choice",
    originalPrompt: "P".repeat(4000),
    instructorContext: "C".repeat(4000),
  });
  assert.ok(request.instructorContext.length <= 2000);
});
