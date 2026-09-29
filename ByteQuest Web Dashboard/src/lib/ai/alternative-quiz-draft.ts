export function buildAlternativeQuizDraftRequest(input: {
  quizVersionId: string;
  activityVersionId: string;
  topic: string;
  difficulty: "foundation" | "intermediate" | "advanced";
  itemType: "multiple_choice" | "true_false" | "identification" | "scenario_based";
  originalPrompt: string;
  instructorContext: string;
}) {
  const alternativeContext = [
    input.instructorContext.trim().slice(0, 900),
    `Generate a distinct alternative to this existing draft question, grounded only in the approved selected activity: ${input.originalPrompt.slice(0, 900)}`,
  ].filter(Boolean).join("\n").slice(0, 2000);

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
