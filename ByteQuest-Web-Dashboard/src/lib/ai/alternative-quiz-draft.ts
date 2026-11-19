export function buildAlternativeQuizDraftRequest(input: {
  quizVersionId: string;
  activityVersionId: string;
  topic: string;
  difficulty: "foundation" | "intermediate" | "advanced";
  itemType:
    | "multiple_choice"
    | "true_false"
    | "identification"
    | "scenario_based";
  originalPrompt: string;
  instructorContext: string;
  sourceMode?: "approved_coc" | "class_resource";
}) {
  const alternativeContext = [
    input.instructorContext.trim().slice(0, 900),
    `Generate a distinct alternative to this existing draft question, grounded only in the ${input.sourceMode === "class_resource" ? "selected class resource" : "approved selected activity"}: ${input.originalPrompt.slice(0, 900)}`,
  ]
    .filter(Boolean)
    .join("\n")
    .slice(0, 2000);

  return {
    quizVersionId: input.quizVersionId,
    activityVersionId: input.activityVersionId,
    topic: input.topic,
    instructorContext: alternativeContext,
    difficulty: input.difficulty,
    itemCount: 1,
    itemTypes: [input.itemType],
  };
}

export type DraftItemType =
  | "multiple_choice"
  | "true_false"
  | "identification"
  | "scenario_based"
  | "scenario_essay";

/**
 * "Regenerate this question": one replacement of the same type, grounded in
 * the same source. The server removes the original with the reason and puts
 * the replacement in its position in one audited step.
 */
export function buildRegenerationRequest(input: {
  quizVersionId: string;
  sourceMode: "curriculum" | "approved_coc" | "class_resource";
  activityVersionId?: string;
  topic: string;
  difficulty: "foundation" | "intermediate" | "advanced";
  itemType: DraftItemType;
  itemId: string;
  originalPrompt: string;
  reason: string;
  instructorContext: string;
}) {
  const context = [
    input.instructorContext.trim().slice(0, 700),
    `Write one replacement for this draft question. Keep the same question type and learning outcome but fix this issue: ${input.reason.trim().slice(0, 300)}. Original question: ${input.originalPrompt.slice(0, 800)}`,
  ]
    .filter(Boolean)
    .join("\n")
    .slice(0, 2000);
  return {
    quizVersionId: input.quizVersionId,
    sourceMode: input.sourceMode,
    activityVersionId:
      input.sourceMode === "approved_coc" ? input.activityVersionId : undefined,
    topic: input.topic,
    instructorContext: context,
    difficulty: input.difficulty,
    itemCount: 1,
    itemTypes: [input.itemType],
    replaceItemId: input.itemId,
    replaceReason: input.reason.trim(),
  };
}
