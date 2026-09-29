import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  DEFAULT_OPENROUTER_TIMEOUT_MS,
  getQuizAiConfiguration,
  OPENROUTER_CHAT_COMPLETIONS_URL,
  type QuizAiConfiguration,
} from "../src/lib/ai/config";
import { generateQuizDraftWithOpenRouter, QuizAiProviderError } from "../src/lib/ai/providers/openrouter";
import type { QuizDraftRequest } from "../src/lib/ai/quiz-draft";

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
  quizTitle: "Network cable review",
  topic: "Cable termination inspection",
  instructorContext: null,
  difficulty: "foundation",
  itemCount: 2,
  itemTypes: ["multiple_choice", "true_false"],
  grounding: {
    qualification: { code: "ELCCSS213", title: "Training Regulations: Computer Systems Servicing NC II" },
    source: {
      id: "source-id",
      title: "Training Regulations: Computer Systems Servicing NC II",
      edition: "Amended December 2013",
      reference: "https://tesda.gov.ph/official-source.pdf",
    },
    coc: { id: "coc-id", code: "COC2", title: "Set Up Computer Networks" },
    competency: {
      id: "competency-id",
      code: "ELC724332",
      title: "Set Up Computer Networks",
      sourceTrace: "ELC724332, pp.42-45",
    },
    module: { id: "module-version-id", title: "COC2 — Set-up Computer Networks", version: 1, sourceTrace: {} },
    activity: { id: "activity-id", title: "Cable Termination and Testing", version: 1, instructions: null },
    mission: {
      id: "mission-id",
      number: 2,
      title: "Create Network Cables",
      objective: "Arrange cable conductors correctly and verify the terminated cable.",
      scenario: "Prepare a network cable for a small office.",
      skillsAssessed: ["Cable preparation", "Cable testing"],
    },
    rubric: { id: "rubric-id", title: "COC2 Cable Termination Evidence Rubric", version: 1 },
    criteria: [
      {
        code: "COC2-M2-ARRANGE",
        title: "Arrange conductors chronologically",
        description: null,
        required: true,
        sourceTrace: "ELC724332",
      },
    ],
  },
};

function providerResponse(questions: unknown, status = 200, headers?: HeadersInit) {
  return new Response(
    JSON.stringify({ choices: [{ message: { content: JSON.stringify({ questions }) } }] }),
    { status, headers: { "content-type": "application/json", ...headers } },
  );
}

const validQuestions = [
  {
    question: "Which check verifies the cable after termination?",
    type: "multiple_choice",
    choices: ["Use a LAN tester", "Restart the router", "Format the workstation"],
    correctAnswer: "Use a LAN tester",
    explanation: "A LAN tester verifies the terminated conductor connections.",
    competency: "Set Up Computer Networks",
    coc: "COC2 - Set Up Computer Networks",
    learningOutcome: "Arrange cable conductors correctly and verify the terminated cable.",
  },
  {
    question: "A physical inspection should be completed after terminating the cable.",
    type: "true_false",
    choices: [],
    correctAnswer: "true",
    explanation: "Inspection helps identify visible termination defects before use.",
    competency: "Set Up Computer Networks",
    coc: "COC2 - Set Up Computer Networks",
    learningOutcome: "Arrange cable conductors correctly and verify the terminated cable.",
  },
];

test("uses openrouter/free when no model override is configured", () => {
  const previousKey = process.env.OPENROUTER_API_KEY;
  const previousModel = process.env.OPENROUTER_MODEL;
  try {
    process.env.OPENROUTER_API_KEY = "test-only-key";
    delete process.env.OPENROUTER_MODEL;
    assert.equal(getQuizAiConfiguration().model, "openrouter/free");
  } finally {
    if (previousKey === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previousKey;
    if (previousModel === undefined) delete process.env.OPENROUTER_MODEL;
    else process.env.OPENROUTER_MODEL = previousModel;
  }
});

test("uses a bounded server timeout override and a safe default", () => {
  const previousKey = process.env.OPENROUTER_API_KEY;
  const previousTimeout = process.env.OPENROUTER_TIMEOUT_MS;
  try {
    process.env.OPENROUTER_API_KEY = "test-only-key";
    process.env.OPENROUTER_TIMEOUT_MS = "75000";
    assert.equal(getQuizAiConfiguration().timeoutMs, 75_000);

    process.env.OPENROUTER_TIMEOUT_MS = "999999";
    assert.equal(getQuizAiConfiguration().timeoutMs, DEFAULT_OPENROUTER_TIMEOUT_MS);
  } finally {
    if (previousKey === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previousKey;
    if (previousTimeout === undefined) delete process.env.OPENROUTER_TIMEOUT_MS;
    else process.env.OPENROUTER_TIMEOUT_MS = previousTimeout;
  }
});

test("normalizes schema-valid OpenRouter structured output", async () => {
  let providerRequest: unknown = null;
  globalThis.fetch = async (_input, init) => {
    providerRequest = JSON.parse(String(init?.body));
    return providerResponse(validQuestions);
  };
  const items = await generateQuizDraftWithOpenRouter(request, configuration);
  assert.equal(items.length, 2);
  assert.equal(items[0].item_type, "multiple_choice");
  assert.equal(items[1].correct_answer, "true");
  assert.ok(providerRequest && typeof providerRequest === "object");
  const providerBody = providerRequest as Record<string, unknown>;
  assert.equal(providerBody.max_tokens, 3_000);
  assert.deepEqual(providerBody.reasoning, { effort: "low", exclude: true });
  assert.deepEqual(providerBody.provider, { require_parameters: true });
});

test("rejects duplicate generated questions", async () => {
  globalThis.fetch = async () => providerResponse([validQuestions[0], validQuestions[0]]);
  await assert.rejects(
    generateQuizDraftWithOpenRouter(request, configuration),
    (error: unknown) => error instanceof QuizAiProviderError && error.code === "OPENROUTER_INVALID_RESPONSE",
  );
});

test("maps OpenRouter authentication failures without exposing provider payloads", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ error: { message: "sensitive-provider-detail" } }), { status: 401 });
  await assert.rejects(
    generateQuizDraftWithOpenRouter(request, configuration),
    (error: unknown) =>
      error instanceof QuizAiProviderError &&
      error.code === "OPENROUTER_AUTH_REJECTED" &&
      !error.publicMessage.includes("sensitive-provider-detail"),
  );
});

test("preserves Retry-After when OpenRouter rate-limits the request", async () => {
  globalThis.fetch = async () => new Response("{}", { status: 429, headers: { "retry-after": "30" } });
  await assert.rejects(
    generateQuizDraftWithOpenRouter(request, configuration),
    (error: unknown) =>
      error instanceof QuizAiProviderError && error.code === "OPENROUTER_RATE_LIMITED" && error.retryAfter === "30",
  );
});

test("rejects malformed provider JSON", async () => {
  globalThis.fetch = async () => new Response("not-json", { status: 200 });
  await assert.rejects(
    generateQuizDraftWithOpenRouter(request, configuration),
    (error: unknown) => error instanceof QuizAiProviderError && error.code === "OPENROUTER_INVALID_RESPONSE",
  );
});

test("classifies an abort while reading the provider body as a timeout", async () => {
  globalThis.fetch = async () =>
    ({
      ok: true,
      status: 200,
      json: async () => {
        const error = new Error("body read aborted");
        error.name = "AbortError";
        throw error;
      },
    }) as unknown as Response;

  await assert.rejects(
    generateQuizDraftWithOpenRouter(request, configuration),
    (error: unknown) =>
      error instanceof QuizAiProviderError && error.code === "OPENROUTER_TIMEOUT" && error.status === 504,
  );
});
