import { z } from 'zod';
import type { CurriculumOptions, HomeworkCriterion, HomeworkFileTypes, HomeworkRecord, HomeworkStatus, HomeworkSubmissionFormat, HomeworkSubmissionRecord } from './types';

export const SUBMISSION_FORMATS: readonly HomeworkSubmissionFormat[] = ['answer_or_file', 'answer', 'file', 'answer_and_file'];
export const submissionFormatLabels: Record<HomeworkSubmissionFormat, string> = {
  answer_or_file: 'Written answer or file',
  answer: 'Written answer only',
  file: 'File only',
  answer_and_file: 'Written answer and file',
};
const fileModes = new Set<HomeworkSubmissionFormat>(['file', 'answer_and_file']);
export const formatTakesFiles = (format: HomeworkSubmissionFormat) => format !== 'answer';
export const formatRequiresFiles = (format: HomeworkSubmissionFormat) => fileModes.has(format);

/** Editable form state for COC -> mission -> module, objectives and criteria. */
export type CurriculumDraft = {
  coc_module_id: string; mission_code: string; module_id: string;
  learning_objectives: string[];
  criteria: { id: string; criterion: string; description: string; max_points: string }[];
  max_score: string; submission_requirements: string;
  submission_format: HomeworkSubmissionFormat; required_file_count: string; accepted_file_types: HomeworkFileTypes;
};
export function emptyCurriculum(): CurriculumDraft {
  return {
    coc_module_id: '', mission_code: '', module_id: '', learning_objectives: [], criteria: [], max_score: '100', submission_requirements: '',
    submission_format: 'answer_or_file', required_file_count: '1', accepted_file_types: 'any',
  };
}
export function curriculumFromHomework(h: Partial<HomeworkRecord>): CurriculumDraft {
  const format = h.submission_format ?? 'answer_or_file';
  return {
    coc_module_id: h.coc_module_id ?? '', mission_code: h.mission_code ?? '', module_id: h.module_id ?? '',
    learning_objectives: [...(h.learning_objectives ?? [])],
    criteria: (h.criteria ?? []).map((c) => ({ id: c.id, criterion: c.criterion, description: c.description ?? '', max_points: String(c.max_points) })),
    max_score: String(h.max_score ?? 100), submission_requirements: h.submission_requirements ?? '',
    submission_format: format,
    required_file_count: String(formatRequiresFiles(format) ? Math.max(1, Number(h.required_file_count ?? 1)) : 1),
    accepted_file_types: h.accepted_file_types ?? 'any',
  };
}

/** Plain-language rule shown to instructors, e.g. "Written answer and at least 1 image (JPG, PNG or WEBP)". */
export function submissionRuleSummary(h: Pick<HomeworkRecord, 'submission_format' | 'required_file_count' | 'accepted_file_types'>) {
  const format = h.submission_format ?? 'answer_or_file';
  const images = h.accepted_file_types === 'image';
  const count = Number(h.required_file_count ?? 0);
  const files = (n: number) => images ? `${n} image${n === 1 ? '' : 's'} (JPG, PNG or WEBP)` : `${n} file${n === 1 ? '' : 's'}`;
  switch (format) {
    case 'answer': return 'Written answer only — files are not accepted.';
    case 'file': return `File only — at least ${files(count)}; no written answer.`;
    case 'answer_and_file': return `Written answer and at least ${files(count)}.`;
    default: return images ? 'A written answer or images (JPG, PNG or WEBP).' : 'A written answer or a file.';
  }
}
/** Request fields for manage_homework create/edit (server recomputes and validates). */
export function curriculumPayload(draft: CurriculumDraft) {
  const criteria = draft.criteria
    .filter((c) => c.criterion.trim() || c.max_points.trim())
    .map((c) => ({ id: c.id, criterion: c.criterion.trim(), description: c.description.trim() || null, max_points: Number(c.max_points) }));
  return {
    coc_module_id: draft.coc_module_id || null,
    mission_code: draft.mission_code || null,
    module_id: draft.module_id || null,
    learning_objectives: draft.learning_objectives.map((o) => o.trim()).filter(Boolean),
    criteria,
    max_score: criteria.length ? null : Number(draft.max_score || 100),
    submission_requirements: draft.submission_requirements.trim() || null,
    submission_format: draft.submission_format,
    required_file_count: formatRequiresFiles(draft.submission_format) ? Math.min(5, Math.max(1, Math.trunc(Number(draft.required_file_count) || 1))) : 0,
    accepted_file_types: draft.submission_format === 'answer' ? 'any' as const : draft.accepted_file_types,
  };
}
/** Choosing a mission selects its COC and, by default, its curriculum module. */
export function selectMission(draft: CurriculumDraft, missionCode: string, options: CurriculumOptions): CurriculumDraft {
  const mission = options.missions.find((m) => m.mission_code === missionCode);
  const link = options.links.find((l) => l.mission_code === missionCode);
  return {
    ...draft,
    mission_code: missionCode,
    coc_module_id: mission?.coc_id ?? draft.coc_module_id,
    module_id: link?.module_id ?? (missionCode ? draft.module_id : draft.module_id),
  };
}
/** Changing the COC clears a mission or module that belongs to another COC. */
export function selectCoc(draft: CurriculumDraft, cocId: string, options: CurriculumOptions): CurriculumDraft {
  const missionOk = options.missions.some((m) => m.mission_code === draft.mission_code && m.coc_id === cocId);
  const moduleOk = options.modules.some((m) => m.id === draft.module_id && m.coc_module_id === cocId);
  return { ...draft, coc_module_id: cocId, mission_code: missionOk ? draft.mission_code : '', module_id: moduleOk ? draft.module_id : '' };
}

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
  submission_format: z.enum(['answer_or_file', 'answer', 'file', 'answer_and_file']).optional(),
  required_file_count: z.number().int().min(0).max(5).optional(),
  accepted_file_types: z.enum(['any', 'image']).optional(),
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

const isSubmissionRow = (record: unknown): record is HomeworkSubmissionRecord =>
  Boolean(record) && typeof record === 'object' && !Array.isArray(record)
  && ['assignment_id', 'learner_id', 'submitted_at', 'status'].every((key) => key in (record as Record<string, unknown>));

/**
 * Every learner-facing homework action reply passes through this view: a
 * submission row is redacted by learnerSubmissionView; other records (for
 * example file metadata) carry no grade and pass through unchanged.
 */
export function learnerRecordView(record: unknown) {
  return isSubmissionRow(record) ? learnerSubmissionView(record) : record;
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
  HOMEWORK_SUBMISSION_RULES_INVALID: { error: 'Choose what learners submit: file tasks need 1 to 5 required files, and written-answer-only tasks take no files.', status: 422 },
  HOMEWORK_ANSWER_REQUIRED: { error: 'This homework requires a written answer.', status: 422 },
  HOMEWORK_ANSWER_NOT_ACCEPTED: { error: 'This homework accepts files only. Remove the written answer, then submit your file.', status: 422 },
  HOMEWORK_FILES_REQUIRED: { error: 'Attach the required number of files before submitting.', status: 422 },
  HOMEWORK_FILES_NOT_ACCEPTED: { error: 'This homework accepts a written answer only. Remove the attached files.', status: 422 },
  HOMEWORK_IMAGE_FILES_REQUIRED: { error: 'This homework accepts images only (JPG, PNG or WEBP).', status: 422 },
  ANSWER_OR_FILE_REQUIRED: { error: 'Write an answer or attach a file before submitting.', status: 422 },
};

/** Specific technical reasons for homework workflow errors, or null. */
export function homeworkErrorMessage(error: { message?: string }) {
  const code = Object.keys(messages).find((key) => error.message?.includes(key));
  return code ? messages[code] : null;
}
