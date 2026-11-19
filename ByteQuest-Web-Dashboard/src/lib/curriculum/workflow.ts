import { z } from 'zod';
import type { ContentStatus, StaffCurriculumAction } from './types';

/**
 * Request validation and workflow rules for curriculum content. The database
 * function manage_curriculum_content is authoritative; these rules only decide
 * which controls the dashboard shows and reject malformed requests early.
 */
const uuid = z.string().uuid();
const title = z.string().trim().min(2, 'Use a title of at least 2 characters.').max(200);
const summary = z.string().trim().max(1000);
const body = z.string().max(60000);
const outcomeIds = z.array(uuid).max(40);
const note = z.string().trim().max(1000);

export const staffActionSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('create_topic'), module_id: uuid, title, summary: summary.optional(),
    body_markdown: body.optional(), outcome_ids: outcomeIds.optional() }).strict(),
  z.object({ action: z.literal('edit_revision'), revision_id: uuid, title: title.optional(), summary: summary.nullable().optional(),
    body_markdown: body.optional(), outcome_ids: outcomeIds.optional() }).strict(),
  z.object({ action: z.literal('submit'), revision_id: uuid, note: note.optional() }).strict(),
  z.object({ action: z.literal('evaluate'), revision_id: uuid, result: z.enum(['passed', 'needs_revision']),
    notes: z.string().trim().min(10, 'Evaluation notes must be at least 10 characters.').max(4000) }).strict(),
  z.object({ action: z.literal('finalize'), revision_id: uuid, note: note.optional() }).strict(),
  z.object({ action: z.literal('approve'), revision_id: uuid, note: note.optional() }).strict(),
  z.object({ action: z.literal('publish'), revision_id: uuid, note: note.optional() }).strict(),
  z.object({ action: z.literal('unpublish'), revision_id: uuid, note: note.optional() }).strict(),
  z.object({ action: z.literal('archive_topic'), topic_id: uuid, note: note.optional() }).strict(),
]);
export type StaffActionInput = z.infer<typeof staffActionSchema>;

export const learnerActionSchema = z.object({ action: z.literal('complete_topic'), topic_id: uuid }).strict();
export type LearnerActionInput = z.infer<typeof learnerActionSchema>;

export const adminOnlyActions: ReadonlySet<StaffCurriculumAction> = new Set(['evaluate', 'approve', 'publish', 'unpublish', 'archive_topic']);

export const statusLabels: Record<ContentStatus, string> = {
  draft: 'Draft', submitted: 'Submitted', needs_revision: 'Needs revision', evaluated: 'Evaluated',
  finalized: 'Finalized', approved: 'Approved', published: 'Published', unpublished: 'Unpublished', archived: 'Archived',
};

/** The ordered stages shown in the workflow stepper. */
export const workflowStages: ContentStatus[] = ['draft', 'submitted', 'evaluated', 'finalized', 'approved', 'published'];

export const inProgressStatuses: ReadonlySet<ContentStatus> = new Set(['draft', 'submitted', 'needs_revision', 'evaluated', 'finalized', 'approved']);

export type RevisionAction = 'edit' | 'new_revision' | 'submit' | 'evaluate' | 'finalize' | 'approve' | 'publish' | 'unpublish';

/** Mirrors manage_curriculum_content's role and stage rules for one revision. */
export function revisionActions(input: {
  role: 'admin' | 'instructor';
  actorId: string;
  revision: { status: ContentStatus; author_id: string | null };
  topic: { created_by: string | null; archived_at: string | null };
  otherRevisionInProgress: boolean;
}): RevisionAction[] {
  const { role, actorId, revision, topic } = input;
  if (topic.archived_at) return [];
  const admin = role === 'admin';
  const author = revision.author_id === actorId;
  const editor = admin || author || topic.created_by === actorId;
  switch (revision.status) {
    case 'draft':
    case 'needs_revision':
      return [...(editor ? ['edit' as const] : []), ...(author ? ['submit' as const] : [])];
    case 'submitted':
      return admin ? ['evaluate'] : [];
    case 'evaluated':
      return admin || author ? ['finalize'] : [];
    case 'finalized':
      return admin ? ['approve'] : [];
    case 'approved':
      return admin ? ['publish'] : [];
    case 'published':
      return [...(admin ? ['unpublish' as const] : []), ...(editor && !input.otherRevisionInProgress ? ['new_revision' as const] : [])];
    case 'unpublished':
      return [...(admin ? ['publish' as const] : []), ...(editor && !input.otherRevisionInProgress ? ['new_revision' as const] : [])];
    default:
      return [];
  }
}

/** Maps database workflow errors to safe, specific messages. */
export function curriculumError(error: { code?: string; message?: string }): { error: string; status: number } {
  const message = error.message ?? '';
  const known: [string, string, number][] = [
    ['MODULE_LOCKED', 'This module is still locked. Complete the previous module first.', 403],
    ['TOPIC_NOT_PUBLISHED', 'This lesson is not published.', 404],
    ['REVISION_IN_PROGRESS', 'Another revision of this topic is already in progress. Continue that revision instead.', 409],
    ['REVISION_LOCKED', 'This revision is locked by the workflow. Start a new revision after it is published.', 409],
    ['TRANSITION_NOT_ALLOWED', 'That step is not available from the current status. Refresh to see the latest status.', 409],
    ['TOPIC_ARCHIVED', 'This topic is archived.', 409],
    ['EVALUATION_NOTES_REQUIRED', 'Evaluation notes must be at least 10 characters.', 422],
    ['EVALUATION_RESULT_INVALID', 'Choose Passed or Needs revision.', 422],
    ['OUTCOME_NOT_IN_MODULE', 'Select learning outcomes from this module only.', 422],
    ['BODY_REQUIRED', 'Write the lesson content before submitting it.', 422],
    ['TITLE_REQUIRED', 'Use a title between 2 and 200 characters.', 422],
    ['CONTENT_TOO_LONG', 'The summary or lesson body is too long.', 422],
  ];
  for (const [code, text, status] of known) if (message.includes(code)) return { error: text, status };
  if (error.code === '42501') return { error: 'Your role cannot perform this curriculum action.', status: 403 };
  if (error.code === 'P0002') return { error: 'The module, topic or revision was not found.', status: 404 };
  if (error.code === '55000') return { error: 'The record changed. Refresh and try again.', status: 409 };
  if (['22023', '22P02', '23514'].includes(error.code ?? '')) return { error: 'Check the topic fields and try again.', status: 422 };
  return { error: 'The curriculum service is temporarily unavailable. Try again.', status: 503 };
}
