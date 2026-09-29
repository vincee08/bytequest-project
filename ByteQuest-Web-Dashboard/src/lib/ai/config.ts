import "server-only";

export const OPENROUTER_CHAT_COMPLETIONS_URL = "https://openrouter.ai/api/v1/chat/completions";
export const DEFAULT_OPENROUTER_MODEL = "openrouter/free";
export const DEFAULT_OPENROUTER_TIMEOUT_MS = 90_000;
const MIN_OPENROUTER_TIMEOUT_MS = 10_000;
const MAX_OPENROUTER_TIMEOUT_MS = 120_000;

export interface QuizAiConfiguration {
  provider: "openrouter";
  apiKey: string;
  model: string;
  endpoint: typeof OPENROUTER_CHAT_COMPLETIONS_URL;
  timeoutMs: number;
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
  const apiKey = process.env.OPENROUTER_API_KEY?.trim();
  if (!apiKey) throw new QuizAiConfigurationError();

  return {
    provider: "openrouter",
    apiKey,
    model: process.env.OPENROUTER_MODEL?.trim() || DEFAULT_OPENROUTER_MODEL,
    endpoint: OPENROUTER_CHAT_COMPLETIONS_URL,
    timeoutMs: getOpenRouterTimeoutMs(),
  };
}
