import { z } from 'zod';
import type { HomeworkCriterion, HomeworkStatus, HomeworkSubmissionRecord } from './types';

const uuid = z.string().uuid();
const deadline = z.string().datetime({ offset: true }).nullable();
const criterionId = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/);
const distinctIds = (ids: string[]) => new Set(ids).size === ids.length;

const criterion = z.object({
  id: criterionId.optional(),
  criterion: z.string().trim().min(1).max(200),
  description: z.string().trim().max(1000).nullable().optional(),
  max_points: z.number().positive().max(1000),
}).strict();
const curriculum = {
  coc_module_id: uuid.nullable().optional(),
  module_id: uuid.nullable().optional(),
  mission_code: z.string().regex(/^coc[1-4]_m[1-9]$/).nullable().optional(),
  learning_objectives: z.array(z.string().trim().max(500)).max(20).optional(),
  criteria: z.array(criterion).max(20)
    .refine((items) => distinctIds(items.flatMap((item) => (item.id ? [item.id] : []))), 'Criterion identifiers must be unique.')
    .optional(),
  max_score: z.number().positive().max(1000).nullable().optional(),
  submission_requirements: z.string().trim().max(5000).nullable().optional(),
};
const fields = { title: z.string().trim().min(2).max(300), instructions: z.string().trim().min(1).max(20000), deadline_at: deadline };
const submissionIds = z.array(uuid).min(1).max(50).refine(distinctIds, 'Choose each submission once.');

/** Every previous action and payload stays valid; new fields are optional. */
export const homeworkActionSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('create'), class_id: uuid, ...fields, ...curriculum }).strict(),
  z.object({ action: z.literal('edit'), assignment_id: uuid, ...fields, ...curriculum }).strict(),
  z.object({ action: z.literal('publish'), assignment_id: uuid }).strict(),
  z.object({ action: z.literal('deadline'), assignment_id: uuid, deadline_at: deadline }).strict(),
  z.object({ action: z.literal('submit'), assignment_id: uuid, answer: z.string().trim().max(20000), file_ids: z.array(uuid).max(5) }).strict(),
  z.object({
    action: z.literal('grade'), assignment_id: uuid.optional(), submission_id: uuid,
    feedback: z.string().trim().max(10000), score: z.number().min(0).max(1000).nullable(),
    criterion_scores: z.record(criterionId, z.number().min(0).max(1000)).nullable().optional(),
  }).strict(),
  z.object({ action: z.literal('finalize'), submission_ids: submissionIds }).strict(),
  z.object({ action: z.literal('release'), submission_ids: submissionIds }).strict(),
]);
export type HomeworkAction = z.infer<typeof homeworkActionSchema>;

export function criteriaTotal<T extends Pick<HomeworkCriterion, 'max_points'>>(criteria: readonly T[]) {
  return Math.round(criteria.reduce((sum, item) => sum + Number(item.max_points || 0), 0) * 10000) / 10000;
}

const statusLabels: Record<HomeworkStatus, string> = {
  submitted: 'Awaiting evaluation',
  graded: 'Evaluated (draft)',
  finalized: 'Finalized',
  released: 'Released',
};
export function homeworkStatusLabel(status: HomeworkStatus) {
  return statusLabels[status] ?? status;
}

/** Instructor reads keep every field and gain the explicit workflow status. */
export function staffSubmissionView(row: HomeworkSubmissionRecord) {
  return { ...row, evaluation_status: row.status };
}

/**
 * Learner reads expose score, feedback and criterion scores only after
 * release. `status` keeps the meaning installed app versions rely on
 * ("graded" = result visible); `evaluation_status` carries the workflow state.
 */
export function learnerSubmissionView(row: HomeworkSubmissionRecord) {
  const released = row.status === 'released';
  return {
    ...row,
    evaluation_status: row.status,
    status: released ? 'graded' : 'submitted',
    score: released ? row.score : null,
    feedback: released ? row.feedback : null,
    criterion_scores: released ? row.criterion_scores : null,
    graded_at: released ? row.graded_at : null,
    finalized_at: released ? row.finalized_at : null,
    released_at: released ? row.released_at : null,
    graded_by: null,
    finalized_by: null,
    released_by: null,
  };
}

const messages: Record<string, { error: string; status: number }> = {
  HOMEWORK_SCORE_EXCEEDS_MAX: { error: "The score is above this assignment's maximum score.", status: 422 },
  HOMEWORK_SCORE_INVALID: { error: 'A score cannot be negative.', status: 422 },
  HOMEWORK_CRITERION_SCORES_INVALID: { error: 'Score every criterion once, between 0 and its points.', status: 422 },
  HOMEWORK_CRITERION_SCORES_REQUIRED: { error: 'This assignment is graded by criteria. Score each criterion.', status: 422 },
  HOMEWORK_SCORE_MUST_EQUAL_CRITERIA_TOTAL: { error: 'The total must equal the sum of the criterion scores.', status: 422 },
  HOMEWORK_MAX_SCORE_MUST_EQUAL_CRITERIA_TOTAL: { error: 'The maximum score must equal the total points of the criteria.', status: 422 },
  HOMEWORK_MAX_SCORE_INVALID: { error: 'Choose a maximum score between 1 and 1000.', status: 422 },
  HOMEWORK_CRITERIA_INVALID: { error: 'Each criterion needs a name and positive points (up to 20 criteria).', status: 422 },
  HOMEWORK_OBJECTIVES_INVALID: { error: 'Each learning objective must be 1 to 500 characters (up to 20).', status: 422 },
  HOMEWORK_CURRICULUM_MISMATCH: { error: 'The mission and module must belong to the selected COC.', status: 422 },
  HOMEWORK_GRADE_LOCKED: { error: 'This grade is finalized. It can no longer be edited.', status: 409 },
  HOMEWORK_GRADE_REQUIRED: { error: 'Save a grade before finalizing this submission.', status: 409 },
  HOMEWORK_FINALIZE_REQUIRED: { error: 'Finalize the grade before releasing it.', status: 409 },
  HOMEWORK_SUBMISSION_IDS_INVALID: { error: 'Choose between 1 and 50 different submissions.', status: 422 },
  HOMEWORK_SCOPE_DENIED: { error: 'This submission is not in one of your active classes.', status: 403 },
};

/** Specific technical reasons for homework workflow errors, or null. */
export function homeworkErrorMessage(error: { message?: string }) {
  const code = Object.keys(messages).find((key) => error.message?.includes(key));
  return code ? messages[code] : null;
}
