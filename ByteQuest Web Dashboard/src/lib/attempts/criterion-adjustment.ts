import type { Json } from "@/types/database.generated";

export type CriterionObservation = "satisfied" | "not_satisfied" | "not_evaluated" | "requires_review";

export interface ReviewCriterion {
  id: string;
  code: string;
  title: string;
  isRequired: boolean;
  maxValue: number | null;
  scoringRule: Json;
}

interface CriterionValue {
  criterion_id: string;
  observation: CriterionObservation;
  score_value: number;
  observed_evidence?: Json;
  [key: string]: Json | undefined;
}

export interface CriterionAdjustment {
  criterionValues: Json;
  totalValue: number;
  maxValue: number;
  percentage: number;
  suggestedOutcome: "competent" | "not_yet_competent";
  changed: boolean;
}

function isRecord(value: Json): value is { [key: string]: Json | undefined } {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function readValue(value: Json): CriterionValue | null {
  if (!isRecord(value)) return null;
  if (typeof value.criterion_id !== "string" || typeof value.score_value !== "number") return null;
  if (!["satisfied", "not_satisfied", "not_evaluated", "requires_review"].includes(String(value.observation))) return null;
  return value as unknown as CriterionValue;
}

export function buildCriterionAdjustment(
  provisionalValues: Json,
  definitions: ReviewCriterion[],
  overrides: Readonly<Partial<Record<string, "satisfied" | "not_satisfied">>>,
): CriterionAdjustment | null {
  if (!Array.isArray(provisionalValues) || provisionalValues.length !== definitions.length || definitions.length === 0) return null;
  const values = provisionalValues.map(readValue);
  if (values.some((value) => value === null)) return null;
  const byId = new Map(values.map((value) => [value!.criterion_id, value!]));
  if (byId.size !== definitions.length) return null;

  let totalValue = 0;
  let maxValue = 0;
  let requiredSatisfied = true;
  let changed = false;
  const adjusted: CriterionValue[] = [];

  for (const definition of definitions) {
    const original = byId.get(definition.id);
    const rule = definition.scoringRule;
    if (!original || !isRecord(rule) || rule.status !== "APPROVED" || rule.method !== "binary"
      || typeof rule.satisfied_value !== "number" || typeof rule.not_satisfied_value !== "number"
      || definition.maxValue === null || definition.maxValue <= 0) return null;
    const observation = overrides[definition.id] ?? original.observation;
    const scoreValue = observation === "satisfied" ? rule.satisfied_value : rule.not_satisfied_value;
    if (scoreValue < 0 || scoreValue > definition.maxValue) return null;
    adjusted.push({ ...original, observation, score_value: scoreValue });
    totalValue += scoreValue;
    maxValue += definition.maxValue;
    if (definition.isRequired && observation !== "satisfied") requiredSatisfied = false;
    if (observation !== original.observation || scoreValue !== original.score_value) changed = true;
  }

  return {
    criterionValues: adjusted as Json,
    totalValue,
    maxValue,
    percentage: Math.round((totalValue / maxValue) * 1_000_000) / 10_000,
    suggestedOutcome: requiredSatisfied ? "competent" : "not_yet_competent",
    changed,
  };
}
