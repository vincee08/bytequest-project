import { z } from 'zod';
import { homeworkErrorMessage } from './homework';

/** Objective 4: every item moves Evaluate -> Finalize -> Release -> Released. */
export const EVALUATION_STAGES = ['evaluate', 'finalize', 'release', 'released'] as const;
export type EvaluationStage = (typeof EVALUATION_STAGES)[number];
export const EVALUATION_KINDS = ['technical', 'quiz', 'homework'] as const;
export type EvaluationKind = (typeof EVALUATION_KINDS)[number];

export const STAGE_COPY: Record<EvaluationStage, { label: string; help: string; empty: string; emptyHelp: string }> = {
  evaluate: {
    label: 'Evaluate',
    help: 'Automatically evaluated assessments, essays not yet scored and homework not yet graded.',
    empty: 'Nothing waiting for evaluation',
    emptyHelp: 'New submissions appear here after learners submit them.',
  },
  finalize: {
    label: 'Finalize',
    help: 'Your evaluation is recorded. Finalizing locks the result before release.',
    empty: 'Nothing waiting for finalization',
    emptyHelp: 'Items appear here once you record an evaluation or save a grade.',
  },
  release: {
    label: 'Release',
    help: 'Finalized results that learners cannot see yet.',
    empty: 'Nothing waiting for release',
    emptyHelp: 'Finalized items appear here until you release them to learners.',
  },
  released: {
    label: 'Released',
    help: 'Results learners can see, newest first.',
    empty: 'No released results yet',
    emptyHelp: 'Released results stay here as the learner-visible record.',
  },
};
export const KIND_LABEL: Record<EvaluationKind, string> = { technical: 'Technical assessment', quiz: 'Quiz essay', homework: 'Homework' };

export type QueueItem = {
  kind: EvaluationKind; id: string; title: string;
  learner: { id: string | null; name: string | null; email?: string | null };
  class: { id: string | null; title: string | null };
  submitted_at: string | null; status: string; score: number | null; max_score: number | null; link: string;
  coc_code?: string | null; module_id?: string | null; mission_code?: string | null; late?: boolean; outcome?: string | null;
};
export type QueueResult = {
  stage: EvaluationStage; counts: Record<EvaluationStage, number>; total: number; limit: number; offset: number;
  quiz_available: boolean; items: QueueItem[];
};

const uuid = z.string().uuid();
const distinct = (ids: string[]) => new Set(ids).size === ids.length;
const ids = z.array(uuid).min(1).max(50).refine(distinct, 'Choose each item once.');

const queueQuery = z.object({
  stage: z.enum(EVALUATION_STAGES).default('evaluate'),
  class_id: uuid.optional(),
  kind: z.enum(EVALUATION_KINDS).optional(),
  coc_code: z.string().regex(/^coc[1-4]$/).optional(),
  module_id: uuid.optional(),
  learner_id: uuid.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).max(100000).default(0),
}).strict();
export type QueueQuery = z.infer<typeof queueQuery>;

// Dashboard deep links use short names (?tab=finalize&class=...).
const aliases: Record<string, keyof QueueQuery> = { tab: 'stage', class: 'class_id', coc: 'coc_code', module: 'module_id', learner: 'learner_id' };

export function parseQueueQuery(input: URLSearchParams | Record<string, string | string[] | undefined>) {
  const entries = input instanceof URLSearchParams ? [...input.entries()] : Object.entries(input);
  const raw: Record<string, string> = {};
  for (const [key, value] of entries) {
    const text = Array.isArray(value) ? value[0] : value;
    if (text === undefined || text === '') continue;
    raw[aliases[key] ?? key] = text;
  }
  return queueQuery.safeParse(raw);
}

/** p_filters for public.get_evaluation_queue (unset filters omitted). */
export function queueFilters(query: QueueQuery) {
  const { stage: _stage, ...rest } = query;
  void _stage;
  return Object.fromEntries(Object.entries(rest).filter(([, value]) => value !== undefined)) as Record<string, string | number>;
}

const observation = z.enum(['satisfied', 'not_satisfied']);
const overrides = z.array(z.object({ criterion_id: uuid, observation }).strict()).max(200)
  .refine((items) => distinct(items.map((item) => item.criterion_id)), 'Override each criterion once.');

export const evaluationActionSchema = z.union([
  z.object({
    kind: z.literal('technical'), action: z.literal('record_evaluation'), attempt_id: uuid,
    criterion_overrides: overrides.optional(),
    outcome: z.enum(['competent', 'not_yet_competent']).optional(),
    reason: z.string().trim().max(1000).optional(),
    note: z.string().trim().max(2000).optional(),
  }).strict(),
  z.object({ kind: z.literal('technical'), action: z.literal('finalize'), attempt_ids: ids, remarks: z.string().trim().max(2000).optional() }).strict(),
  z.object({ kind: z.literal('technical'), action: z.literal('release'), attempt_ids: ids, note: z.string().trim().max(1000).optional() }).strict(),
  z.object({
    kind: z.literal('homework'), action: z.literal('grade'), submission_id: uuid, assignment_id: uuid.optional(),
    score: z.number().min(0).max(1000).nullable(), feedback: z.string().trim().max(10000),
    criterion_scores: z.record(z.string().regex(/^[A-Za-z0-9_-]{1,64}$/), z.number().min(0).max(1000)).nullable().optional(),
  }).strict(),
  z.object({ kind: z.literal('homework'), action: z.literal('finalize'), submission_ids: ids }).strict(),
  z.object({ kind: z.literal('homework'), action: z.literal('release'), submission_ids: ids }).strict(),
  z.object({ kind: z.literal('quiz'), action: z.literal('finalize'), attempt_ids: ids }).strict(),
  z.object({ kind: z.literal('quiz'), action: z.literal('release'), attempt_ids: ids }).strict(),
]);
export type EvaluationAction = z.infer<typeof evaluationActionSchema>;

export type BulkItemResult = { id: string; ok: boolean; status?: string; changed?: boolean; error?: string };

export function summarizeBulk(results: BulkItemResult[]) {
  return { results, succeeded: results.filter((r) => r.ok).length, failed: results.filter((r) => !r.ok).length };
}

const technicalMessages: Record<string, { error: string; status: number }> = {
  UNDER_REVIEW_ATTEMPT_REQUIRED: { error: 'Record the instructor evaluation before finalizing this attempt.', status: 409 },
  FINALIZED_ATTEMPT_REQUIRED: { error: 'Finalize the result before releasing it.', status: 409 },
  EVALUATED_ATTEMPT_REQUIRED: { error: 'Only an automatically evaluated attempt can receive an instructor evaluation.', status: 409 },
  EVALUATION_ALREADY_RECORDED: { error: 'The evaluation is already recorded. Make any correction when you finalize.', status: 409 },
  ADJUSTMENT_REASON_REQUIRED: { error: 'Give a reason when you change the automated result.', status: 422 },
  INVALID_CRITERION_OVERRIDE: { error: 'Each override must mark a criterion of this rubric satisfied or not satisfied.', status: 422 },
  INVALID_EVALUATION_OUTCOME: { error: 'Choose Competent or Not yet competent.', status: 422 },
  CRITERION_OVERRIDE_UNSUPPORTED: { error: 'This rubric is not scored per criterion. Review the outcome instead.', status: 422 },
  INCONSISTENT_SCORE_AGGREGATE: { error: 'The total, maximum and percentage do not match.', status: 422 },
  INCONSISTENT_CRITERION_SCORE: { error: 'The criterion scores do not match the approved rubric.', status: 422 },
  PROVISIONAL_REVISION_REQUIRED: { error: 'The automated evaluation for this attempt is missing.', status: 409 },
  CLASS_SCOPE_DENIED: { error: 'This attempt is not in one of your active classes.', status: 403 },
  INSTRUCTOR_REQUIRED: { error: 'Only the class instructor can evaluate this attempt.', status: 403 },
  STAFF_REQUIRED: { error: 'The Evaluation Center is available to instructors and admins.', status: 403 },
  INVALID_EVALUATION_STAGE: { error: 'Choose Evaluate, Finalize, Release or Released.', status: 422 },
  // Slice A3: public.manage_quiz_evaluation (quiz essays, instructor release).
  QUIZ_EVALUATION_SCOPE_DENIED: { error: 'This quiz attempt is not in your class, or the quiz belongs to another instructor.', status: 403 },
  QUIZ_ESSAYS_NOT_SCORED: { error: 'Score every answered essay on the quiz results page before finalizing.', status: 409 },
  QUIZ_RESULT_NOT_FINALIZED: { error: 'Finalize the quiz result before releasing it.', status: 409 },
  QUIZ_EVALUATION_NOT_REQUIRED: { error: 'This quiz releases results immediately, so there is nothing to finalize.', status: 409 },
  QUIZ_EVALUATION_STATE_INVALID: { error: 'This quiz result has moved to another stage. Refresh to see where it is.', status: 409 },
  QUIZ_EVALUATION_SELECTION_INVALID: { error: 'Choose each quiz attempt once (up to 50 at a time).', status: 422 },
  QUIZ_EVALUATION_ACTION_INVALID: { error: 'This quiz evaluation action is not supported.', status: 422 },
  QUIZ_ESSAY_NOT_ANSWERED: { error: 'The learner left this essay unanswered; it counts as zero and cannot be given points.', status: 422 },
  QUIZ_ESSAY_SCORE_INVALID: { error: 'Score each rubric criterion once, between 0 and its maximum points.', status: 422 },
  // Named by the integration brief; slice A3 currently raises QUIZ_ESSAY_SCORE_INVALID for this case.
  QUIZ_ESSAY_SCORE_OUT_OF_RANGE: { error: 'Score each rubric criterion once, between 0 and its maximum points.', status: 422 },
  QUIZ_ESSAY_ITEM_NOT_FOUND: { error: 'That essay question is not part of this quiz attempt.', status: 404 },
  QUIZ_ESSAY_FEEDBACK_TOO_LONG: { error: 'Essay feedback can be up to 5,000 characters.', status: 422 },
  FINALIZED_QUIZ_RESULT_IS_IMMUTABLE: { error: 'A finalized quiz result cannot be changed.', status: 409 },
  RELEASED_QUIZ_RESULT_IS_IMMUTABLE: { error: 'A released quiz result cannot be changed.', status: 409 },
};

/** Specific technical reason for an evaluation workflow error, or null. */
export function evaluationErrorMessage(error: { code?: string; message?: string }) {
  const message = error.message?.trim() ?? '';
  // Exact codes first (RPC errors carry the bare code), then a contained code.
  const code = technicalMessages[message] ? message : Object.keys(technicalMessages).find((key) => message.includes(key));
  return code ? technicalMessages[code] : homeworkErrorMessage(error);
}

/** PostgREST/PostgreSQL "function does not exist" (e.g. quiz evaluation not installed yet). */
export function isMissingFunctionError(error: { code?: string; message?: string }) {
  return error.code === 'PGRST202' || error.code === '42883';
}

type HomeworkBulkRow = { submission_id?: unknown; ok?: unknown; changed?: unknown; status?: unknown; error?: unknown };

/** Shapes manage_homework's bulk finalize/release response into per-item results. */
export function homeworkBulkResults(record: unknown): BulkItemResult[] {
  const rows = (record && typeof record === 'object' && Array.isArray((record as { results?: unknown }).results))
    ? (record as { results: HomeworkBulkRow[] }).results : [];
  return rows.map((row) => {
    const ok = row.ok === true;
    const raw = typeof row.error === 'string' ? row.error : undefined;
    return {
      id: String(row.submission_id ?? ''),
      ok,
      ...(typeof row.status === 'string' ? { status: row.status } : {}),
      ...(typeof row.changed === 'boolean' ? { changed: row.changed } : {}),
      ...(ok ? {} : { error: (raw && evaluationErrorMessage({ message: raw })?.error) ?? 'This submission could not be updated.' }),
    };
  });
}
