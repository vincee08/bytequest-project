import "server-only";

export const OPENROUTER_CHAT_COMPLETIONS_URL =
  "https://openrouter.ai/api/v1/chat/completions";
export const DEFAULT_OPENROUTER_MODEL = "openrouter/free";
export const DEFAULT_OPENROUTER_TIMEOUT_MS = 90_000;
const MIN_OPENROUTER_TIMEOUT_MS = 10_000;
const MAX_OPENROUTER_TIMEOUT_MS = 120_000;

export interface QuizAiConfiguration {
  provider: "openrouter";
  apiKey: string;
  model: string;
  endpoint: string;
  timeoutMs: number;
  reasoningEffort?: "low" | "none";
}

export class QuizAiConfigurationError extends Error {
  constructor() {
    super("OPENROUTER_NOT_CONFIGURED");
    this.name = "QuizAiConfigurationError";
  }
}

function getOpenRouterTimeoutMs() {
  const configured = process.env.OPENROUTER_TIMEOUT_MS?.trim();
  if (!configured) return DEFAULT_OPENROUTER_TIMEOUT_MS;

  const parsed = Number(configured);
  return Number.isInteger(parsed) &&
    parsed >= MIN_OPENROUTER_TIMEOUT_MS &&
    parsed <= MAX_OPENROUTER_TIMEOUT_MS
    ? parsed
    : DEFAULT_OPENROUTER_TIMEOUT_MS;
}

export function getQuizAiConfiguration(): QuizAiConfiguration {
  // Only the fixed isolated QA backend can use the fixed loopback simulator.
  // Never accept a caller-supplied provider URL or forward a real key to it.
  if (process.env.BQ_AI_TEST_ENDPOINT) {
    if (
      process.env.BQ_ISOLATED_QA !== "BQQuizQA20261112" ||
      process.env.NEXT_PUBLIC_SUPABASE_URL !== "http://127.0.0.1:58921" ||
      process.env.BQ_AI_TEST_ENDPOINT !==
        "http://127.0.0.1:3007/chat/completions"
    )
      throw new QuizAiConfigurationError();
    return {
      provider: "openrouter",
      apiKey: "isolated-simulator-only",
      model: "qa-simulator",
      endpoint: process.env.BQ_AI_TEST_ENDPOINT,
      timeoutMs: 10_000,
    };
  }
  const apiKey = process.env.OPENROUTER_API_KEY?.trim();
  if (!apiKey) throw new QuizAiConfigurationError();

  return {
    provider: "openrouter",
    apiKey,
    model: process.env.OPENROUTER_MODEL?.trim() || DEFAULT_OPENROUTER_MODEL,
    endpoint: OPENROUTER_CHAT_COMPLETIONS_URL,
    timeoutMs: getOpenRouterTimeoutMs(),
    // Operators may disable optional reasoning only for a compatible model.
    // Mandatory-reasoning models must retain the default setting.
    reasoningEffort:
      process.env.OPENROUTER_REASONING_EFFORT?.trim() === "none" ? "none" : "low",
  };
}
