import type { EvaluationKind, EvaluationStage, QueueItem } from './requests';

/** Each kind names its own workflow statuses (a quiz "evaluated" means its essays are scored). */
const STATUS_TEXT: Record<EvaluationKind, Record<string, string>> = {
  technical: { evaluated: 'Evaluated (automatic)', under_review: 'Evaluation recorded', finalized: 'Finalized', released: 'Released' },
  homework: { submitted: 'Submitted', graded: 'Grade saved', finalized: 'Finalized', released: 'Released' },
  quiz: { pending: 'Essays awaiting scores', evaluated: 'Essays scored', finalized: 'Finalized', released: 'Released' },
};

export function queueStatusText(item: Pick<QueueItem, 'kind' | 'status'>) {
  return STATUS_TEXT[item.kind]?.[item.status] ?? item.status.replaceAll('_', ' ');
}

export function queueScoreText(item: Pick<QueueItem, 'kind' | 'score' | 'max_score'>) {
  if (item.score === null || item.score === undefined) {
    return item.kind === 'quiz' ? 'Awaiting essay scores' : item.kind === 'homework' ? 'No score' : '—';
  }
  return item.max_score ? `${Number(item.score)} / ${Number(item.max_score)}` : String(Number(item.score));
}

/** Essays are scored on the quiz results page; other items open their own review. */
export function queueActionLabel(stage: EvaluationStage, item: Pick<QueueItem, 'kind'>) {
  if (stage !== 'evaluate') return 'Open';
  return item.kind === 'quiz' ? 'Score essays' : 'Evaluate';
}

/** Bulk Finalize/Release across mixed kinds: one request per kind with that kind's id field. */
export function bulkRequestBodies(items: Pick<QueueItem, 'kind' | 'id'>[], action: 'finalize' | 'release') {
  const groups = new Map<EvaluationKind, string[]>();
  for (const item of items) groups.set(item.kind, [...(groups.get(item.kind) ?? []), item.id]);
  return [...groups].map(([kind, ids]) => (kind === 'homework'
    ? { kind, action, submission_ids: ids }
    : { kind, action, attempt_ids: ids }));
}
