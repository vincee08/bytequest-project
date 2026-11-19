import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { buildRegenerationRequest } from "../src/lib/ai/alternative-quiz-draft";
import {
  OPENROUTER_CHAT_COMPLETIONS_URL,
  type QuizAiConfiguration,
} from "../src/lib/ai/config";
import { generateQuizDraftWithOpenRouter } from "../src/lib/ai/providers/openrouter";
import {
  normalizeAndValidateQuizDraft,
  outcomeLabel,
  quizDraftAlignment,
  type QuizDraftRequest,
} from "../src/lib/ai/quiz-draft";

const originalFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = originalFetch;
});

const configuration: QuizAiConfiguration = {
  provider: "openrouter",
  apiKey: "test-only-key",
  model: "openrouter/free",
  endpoint: OPENROUTER_CHAT_COMPLETIONS_URL,
  timeoutMs: 1_000,
};

const request: QuizDraftRequest = {
  quizTitle: "Hardware assembly check",
  topic: "Safe CPU installation",
  instructorContext: null,
  difficulty: "intermediate",
  itemCount: 2,
  itemTypes: ["scenario_essay", "multiple_choice"],
  curriculum: {
    coc: { id: "coc1", code: "coc1", title: "Install and Configure Computer Systems" },
    modules: [{ id: "lo11", code: "LO1.1", title: "Assemble computer hardware" }],
    outcomes: [
      {
        id: "pc14",
        code: "1.4",
        module: "LO1.1",
        statement: "Computer hardware is assembled in accordance with established procedures and systems requirements",
      },
    ],
    topic: { id: "topic", title: "ESD-safe assembly", summary: null, excerpt: "Wear a wrist strap." },
    focus: "Safe installation of the CPU and memory",
    quizType: "formative",
    difficulty: "intermediate",
  },
};

const alignment = {
  competency: "COC1 Install and Configure Computer Systems",
  coc: "COC1",
  learningOutcome: "PC 1.4 (LO1.1)",
};

const essayQuestion = {
  question: "Explain how you would install the processor and verify the build.",
  type: "scenario_essay",
  choices: [],
  correctAnswer: "Grounds self, opens the lever, aligns the triangle, closes the lever, checks POST.",
  explanation: "Scored by the instructor with the rubric.",
  ...alignment,
  scenario: "A client left an unassembled workstation and an anti-static mat on your bench.",
  rubric: [
    { criterion: "Safety", description: "Uses ESD precautions before handling parts", maxPoints: 4 },
    { criterion: "Procedure", description: "Correct orientation and seating", maxPoints: 6 },
  ],
  minWords: 60,
  maxWords: 250,
};
const choiceQuestion = {
  question: "Which tool prevents electrostatic discharge damage?",
  type: "multiple_choice",
  choices: ["Anti-static wrist strap", "Crimping tool"],
  correctAnswer: "Anti-static wrist strap",
  explanation: "The strap equalises static charge.",
  ...alignment,
  scenario: "",
  rubric: [],
  minWords: 0,
  maxWords: 0,
};

test("curriculum alignment uses the quiz COC and its performance criteria", () => {
  const value = quizDraftAlignment(request);
  assert.equal(value.competency, alignment.competency);
  assert.equal(value.coc, "COC1");
  assert.deepEqual(value.learningOutcomes, ["PC 1.4 (LO1.1)"]);
  assert.equal(outcomeLabel({ code: "3.1", module: "LO1.2" }), "PC 3.1 (LO1.2)");
});

test("AI essays keep their scenario, rubric points and word guidance; other items get none", () => {
  const items = normalizeAndValidateQuizDraft({ questions: [essayQuestion, choiceQuestion] }, request);
  assert.equal(items[0].item_type, "scenario_essay");
  assert.deepEqual(items[0].rubric?.map((row) => row.max_points), [4, 6]);
  assert.equal(items[0].min_words, 60);
  assert.match(items[0].scenario ?? "", /unassembled workstation/);
  assert.equal(items[1].rubric, undefined);
  assert.equal(items[1].correct_answer, "Anti-static wrist strap");
});

test("AI essays without a rubric or outside the quiz criteria are rejected", () => {
  assert.throws(
    () => normalizeAndValidateQuizDraft({ questions: [{ ...essayQuestion, rubric: [] }, choiceQuestion] }, request),
    /AI_DRAFT_QUESTION_INVALID/,
  );
  assert.throws(
    () =>
      normalizeAndValidateQuizDraft(
        { questions: [{ ...essayQuestion, learningOutcome: "PC 9.9 (LO9.9)" }, choiceQuestion] },
        request,
      ),
    /AI_DRAFT_QUESTION_INVALID/,
  );
  assert.throws(
    () =>
      normalizeAndValidateQuizDraft(
        { questions: [essayQuestion, { ...choiceQuestion, rubric: essayQuestion.rubric }] },
        request,
      ),
    /AI_DRAFT_QUESTION_INVALID/,
  );
});

test("the provider request carries curriculum context and the essay schema", async () => {
  let body: Record<string, unknown> = {};
  globalThis.fetch = async (_input, init) => {
    body = JSON.parse(String(init?.body));
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify({ questions: [essayQuestion, choiceQuestion] }) } }],
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  const items = await generateQuizDraftWithOpenRouter(request, configuration);
  assert.equal(items.length, 2);
  const messages = body.messages as { role: string; content: string }[];
  assert.match(messages[0].content, /performance criteria/);
  assert.match(messages[0].content, /scenario_essay/);
  const user = JSON.parse(messages[1].content);
  assert.equal(user.source_mode, "curriculum");
  assert.equal(user.curriculum_context.focus, "Safe installation of the CPU and memory");
  assert.deepEqual(user.curriculum_context.allowed_learning_outcomes, ["PC 1.4 (LO1.1)"]);
  const schema = (body.response_format as { json_schema: { schema: { properties: { questions: { items: { required: string[]; properties: Record<string, { enum?: string[] }> } } } } } })
    .json_schema.schema.properties.questions.items;
  assert.ok(schema.required.includes("rubric"));
  assert.deepEqual(schema.properties.learningOutcome.enum, ["PC 1.4 (LO1.1)"]);
});

test("objective-only requests keep the previous schema without essay fields", async () => {
  let body: Record<string, unknown> = {};
  globalThis.fetch = async (_input, init) => {
    body = JSON.parse(String(init?.body));
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify({ questions: [choiceQuestion] }) } }],
      }),
      { status: 200 },
    );
  };
  await generateQuizDraftWithOpenRouter({ ...request, itemCount: 1, itemTypes: ["multiple_choice"] }, configuration);
  const schema = (body.response_format as { json_schema: { schema: { properties: { questions: { items: { required: string[] } } } } } })
    .json_schema.schema.properties.questions.items;
  assert.equal(schema.required.includes("rubric"), false);
});

test("regeneration requests replace exactly one question of the same type with a reason", () => {
  const value = buildRegenerationRequest({
    quizVersionId: "version",
    sourceMode: "curriculum",
    activityVersionId: "ignored",
    topic: "Safe CPU installation",
    difficulty: "foundation",
    itemType: "scenario_essay",
    itemId: "item",
    originalPrompt: "Explain the CPU steps.",
    reason: "  Too vague  ",
    instructorContext: "C".repeat(3000),
  });
  assert.equal(value.itemCount, 1);
  assert.deepEqual(value.itemTypes, ["scenario_essay"]);
  assert.equal(value.replaceItemId, "item");
  assert.equal(value.replaceReason, "Too vague");
  assert.equal(value.activityVersionId, undefined);
  assert.ok(value.instructorContext.length <= 2000);
  assert.match(value.instructorContext, /Too vague/);
});
