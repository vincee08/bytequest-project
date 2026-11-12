import assert from "node:assert/strict";
import test from "node:test";
import {
  questionSchema,
  publicationReadiness,
  type QuizItem,
} from "../src/lib/quizzes/authoring";

test("all four question types preserve the supported answer contract", () => {
  for (const itemType of [
    "multiple_choice",
    "scenario_based",
    "true_false",
    "identification",
  ] as const) {
    const choice = ["multiple_choice", "scenario_based"].includes(itemType);
    assert(
      questionSchema.safeParse({
        itemType,
        prompt: "A clear technical question",
        options: choice ? ["Router", "Switch"] : [],
        correctAnswer: itemType === "true_false" ? "false" : "Router",
        explanation: "",
      }).success,
    );
  }
});
test("choice answers must match an option; limits and true/false choices are validated", () => {
  const question = {
    itemType: "multiple_choice",
    prompt: "Choose the network device",
    options: ["Router", "Switch"],
    correctAnswer: "Other",
    explanation: "",
  };
  assert(!questionSchema.safeParse(question).success);
  assert(
    !questionSchema.safeParse({
      ...question,
      options: Array(7).fill("Router"),
      correctAnswer: "Router",
    }).success,
  );
  assert(
    !questionSchema.safeParse({
      ...question,
      itemType: "true_false",
      options: [],
      correctAnswer: "yes",
    }).success,
  );
});
test("empty, rejected and unreviewed AI drafts cannot become ready to publish", () => {
  assert.equal(publicationReadiness([]).ready, false);
  const item = { reviewStatus: "approved" } as QuizItem;
  assert.equal(publicationReadiness([item]).ready, true);
  for (const reviewStatus of ["draft", "rejected"] as const) {
    assert.equal(
      publicationReadiness([
        item,
        { ...item, reviewStatus, origin: "ai_generated_draft" },
      ]).ready,
      false,
    );
  }
});
