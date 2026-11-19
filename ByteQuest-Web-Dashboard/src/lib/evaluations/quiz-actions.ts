import { evaluationErrorMessage, isMissingFunctionError, type BulkItemResult } from './requests';

/**
 * Quiz Finalize/Release through slice A3's service-only
 * public.manage_quiz_evaluation(p_actor, p_action, p_payload). Essay scoring
 * stays on the quiz results page (each queue item links there).
 *
 * A3's bulk forms are all-or-nothing (one unscored essay fails the whole
 * call), so the Evaluation Center sends one attempt per call and reports a
 * result per item: finalize {attempt_id}, release {attempt_ids:[id]}.
 */
export type QuizEvaluationAction = 'finalize' | 'release';
export type QuizEvaluationCall = (
  action: QuizEvaluationAction,
  payload: Record<string, unknown>,
) => Promise<{ data: unknown; error: { code?: string; message?: string } | null }>;

export function quizActionPayload(action: QuizEvaluationAction, attemptId: string) {
  return action === 'finalize' ? { attempt_id: attemptId } : { attempt_ids: [attemptId] };
}

/** One per-item result from A3's response for a single attempt. */
export function quizItemResult(action: QuizEvaluationAction, attemptId: string, data: unknown): BulkItemResult {
  const record = data && typeof data === 'object' && !Array.isArray(data) ? (data as Record<string, unknown>) : {};
  if (action === 'finalize') {
    // {attempt_id, evaluation_status, total_points, max_points, …, already}
    return {
      id: attemptId,
      ok: true,
      status: typeof record.evaluation_status === 'string' ? record.evaluation_status : 'finalized',
      changed: record.already !== true,
    };
  }
  // {released:[ids], already_released:[ids]}
  const released = Array.isArray(record.released) && record.released.includes(attemptId);
  return { id: attemptId, ok: true, status: 'released', changed: released };
}

export async function runQuizAction(call: QuizEvaluationCall, action: QuizEvaluationAction, attemptIds: string[]) {
  const results: BulkItemResult[] = [];
  for (const id of attemptIds) {
    const { data, error } = await call(action, quizActionPayload(action, id));
    if (error && isMissingFunctionError(error)) return { unavailable: true as const, results };
    results.push(error
      ? { id, ok: false, error: evaluationErrorMessage(error)?.error ?? 'This quiz result could not be updated. Refresh to check its status.' }
      : quizItemResult(action, id, data));
  }
  return { unavailable: false as const, results };
}
