import { z } from "zod";

/** Requests accepted by /api/quizzes/evaluation (owning instructor only). */
export const quizEvaluationRequestSchema = z.discriminatedUnion("action", [
  z
    .object({
      action: z.literal("score_essay"),
      attempt_id: z.string().uuid(),
      item_id: z.string().uuid(),
      criterion_scores: z
        .record(
          z.string().regex(/^[A-Za-z0-9_-]{1,40}$/),
          z.number().min(0).max(100),
        )
        .refine((value) => Object.keys(value).length > 0, {
          message: "Score every rubric criterion.",
        }),
      feedback: z.string().trim().max(5000).optional(),
    })
    .strict(),
  z
    .object({
      action: z.literal("finalize"),
      attempt_ids: z.array(z.string().uuid()).min(1).max(50),
    })
    .strict(),
  z
    .object({
      action: z.literal("release"),
      attempt_ids: z.array(z.string().uuid()).min(1).max(50),
    })
    .strict(),
]);
export type QuizEvaluationRequest = z.infer<typeof quizEvaluationRequestSchema>;

/** Server payload for public.manage_quiz_evaluation. */
export function evaluationRpcPayload(input: QuizEvaluationRequest) {
  if (input.action === "score_essay") {
    return {
      action: input.action,
      payload: {
        attempt_id: input.attempt_id,
        item_id: input.item_id,
        criterion_scores: input.criterion_scores,
        feedback: input.feedback ?? null,
      },
    };
  }
  return { action: input.action, payload: { attempt_ids: input.attempt_ids } };
}

const knownErrors: [string, number, string][] = [
  ["QUIZ_EVALUATION_SCOPE_DENIED", 403, "Only the instructor of this class can evaluate this attempt."],
  ["INSTRUCTOR_REQUIRED", 403, "Active Instructor access is required."],
  ["QUIZ_ESSAY_SCORE_INVALID", 422, "Give every rubric criterion a score from 0 to its maximum points."],
  ["QUIZ_ESSAY_FEEDBACK_TOO_LONG", 422, "Keep feedback under 5,000 characters."],
  ["QUIZ_ESSAY_ITEM_NOT_FOUND", 404, "This essay question is not part of the attempt."],
  ["QUIZ_ESSAYS_NOT_SCORED", 409, "Score every answered essay before finalizing."],
  ["QUIZ_RESULT_NOT_FINALIZED", 409, "Finalize each result before releasing it."],
  ["QUIZ_EVALUATION_STATE_INVALID", 409, "This result is already finalized. Refresh to see its current stage."],
  ["QUIZ_EVALUATION_NOT_REQUIRED", 409, "This quiz shows results at submission; there is nothing to release."],
  ["QUIZ_EVALUATION_SELECTION_INVALID", 422, "Select between 1 and 50 attempts."],
];

export function evaluationError(message: string | undefined) {
  const match = knownErrors.find(([code]) => message?.includes(code));
  return match
    ? { status: match[1], error: match[2] }
    : {
        status: 503,
        error: "The evaluation could not be saved. Refresh to check its stage before retrying.",
      };
}
