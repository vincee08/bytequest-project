import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  STAGE_COPY, evaluationActionSchema, evaluationErrorMessage, homeworkBulkResults, isMissingFunctionError,
  parseQueueQuery, queueFilters, summarizeBulk,
} from '../src/lib/evaluations/requests';

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

test('queue queries accept the four stages, known filters and bounded pages', () => {
  const parsed = parseQueueQuery(new URLSearchParams({ tab: 'finalize', class: uuid(1), kind: 'homework', coc: 'coc2', module: uuid(2), learner: uuid(3), limit: '25', offset: '50' }));
  assert.equal(parsed.success, true);
  if (!parsed.success) return;
  assert.equal(parsed.data.stage, 'finalize');
  assert.deepEqual(queueFilters(parsed.data), { class_id: uuid(1), kind: 'homework', coc_code: 'coc2', module_id: uuid(2), learner_id: uuid(3), limit: 25, offset: 50 });
  const defaults = parseQueueQuery(new URLSearchParams({ class: '', kind: '' }));
  assert.equal(defaults.success, true);
  if (defaults.success) {
    assert.equal(defaults.data.stage, 'evaluate');
    assert.deepEqual(queueFilters(defaults.data), { limit: 50, offset: 0 });
  }
  assert.equal(parseQueueQuery({ stage: 'released', class_id: uuid(4) }).success, true);
  const invalid: Record<string, string>[] = [{ tab: 'archive' }, { class: 'abc' }, { kind: 'essay' }, { coc: 'coc9' }, { limit: '101' }, { offset: '-1' }];
  for (const bad of invalid) {
    assert.equal(parseQueueQuery(new URLSearchParams(bad)).success, false, JSON.stringify(bad));
  }
});

test('evaluation actions validate kind, action and up to fifty distinct ids', () => {
  const ok = [
    { kind: 'technical', action: 'record_evaluation', attempt_id: uuid(1) },
    { kind: 'technical', action: 'record_evaluation', attempt_id: uuid(1), criterion_overrides: [{ criterion_id: uuid(2), observation: 'not_satisfied' }], outcome: 'not_yet_competent', reason: 'Evidence misread', note: 'Checked the sequence.' },
    { kind: 'technical', action: 'finalize', attempt_ids: [uuid(1), uuid(2)] },
    { kind: 'technical', action: 'release', attempt_ids: [uuid(1)], note: 'Released after review' },
    { kind: 'homework', action: 'grade', submission_id: uuid(3), score: 40, feedback: 'Good', criterion_scores: { safety: 25, order: 15 } },
    { kind: 'homework', action: 'finalize', submission_ids: [uuid(3)] },
    { kind: 'homework', action: 'release', submission_ids: Array.from({ length: 50 }, (_, i) => uuid(100 + i)) },
    { kind: 'quiz', action: 'finalize', attempt_ids: [uuid(4)] },
    { kind: 'quiz', action: 'release', attempt_ids: [uuid(4), uuid(5)] },
  ];
  for (const body of ok) assert.equal(evaluationActionSchema.safeParse(body).success, true, JSON.stringify(body));
  const bad = [
    { kind: 'technical', action: 'grade', attempt_id: uuid(1) },
    { kind: 'technical', action: 'record_evaluation', attempt_id: uuid(1), criterion_overrides: [{ criterion_id: uuid(2), observation: 'requires_review' }] },
    { kind: 'technical', action: 'record_evaluation', attempt_id: uuid(1), criterion_overrides: [{ criterion_id: uuid(2), observation: 'satisfied' }, { criterion_id: uuid(2), observation: 'not_satisfied' }] },
    { kind: 'technical', action: 'record_evaluation', attempt_id: uuid(1), outcome: 'pending_tesda_validation' },
    { kind: 'technical', action: 'finalize', attempt_ids: [] },
    { kind: 'technical', action: 'finalize', attempt_ids: [uuid(1), uuid(1)] },
    { kind: 'homework', action: 'release', submission_ids: Array.from({ length: 51 }, (_, i) => uuid(100 + i)) },
    { kind: 'quiz', action: 'record_evaluation', attempt_id: uuid(4) },
    { kind: 'quiz', action: 'release', attempt_ids: ['not-a-uuid'] },
    { kind: 'homework', action: 'finalize', submission_ids: [uuid(3)], extra: true },
    { kind: 'essay', action: 'release', attempt_ids: [uuid(4)] },
  ];
  for (const body of bad) assert.equal(evaluationActionSchema.safeParse(body).success, false, JSON.stringify(body));
});

test('bulk results keep one line per item with a technical reason', () => {
  const shaped = homeworkBulkResults({
    action: 'release',
    results: [
      { submission_id: uuid(1), ok: true, changed: true, status: 'released' },
      { submission_id: uuid(2), ok: true, changed: false, status: 'released' },
      { submission_id: uuid(3), ok: false, error: 'HOMEWORK_FINALIZE_REQUIRED', code: '55000' },
    ],
  });
  assert.deepEqual(shaped.map((r) => r.id), [uuid(1), uuid(2), uuid(3)]);
  assert.equal(shaped[1].changed, false);
  assert.match(shaped[2].error ?? '', /Finalize/);
  assert.deepEqual(summarizeBulk(shaped), { results: shaped, succeeded: 2, failed: 1 });
  assert.deepEqual(homeworkBulkResults(null), []);
});

test('errors explain the stage that is missing', () => {
  assert.match(evaluationErrorMessage({ message: 'UNDER_REVIEW_ATTEMPT_REQUIRED' })!.error, /Record the instructor evaluation/);
  assert.equal(evaluationErrorMessage({ message: 'FINALIZED_ATTEMPT_REQUIRED' })!.status, 409);
  assert.match(evaluationErrorMessage({ message: 'ADJUSTMENT_REASON_REQUIRED' })!.error, /reason/);
  assert.equal(evaluationErrorMessage({ code: '42501', message: 'CLASS_SCOPE_DENIED' })!.status, 403);
  assert.match(evaluationErrorMessage({ message: 'HOMEWORK_GRADE_LOCKED' })!.error, /finalized/);
  assert.equal(evaluationErrorMessage({ message: 'unexpected' }), null);
  assert.equal(isMissingFunctionError({ code: 'PGRST202', message: 'Could not find the function public.manage_quiz_evaluation' }), true);
  assert.equal(isMissingFunctionError({ code: '42883', message: 'function public.manage_quiz_evaluation(uuid, text, jsonb) does not exist' }), true);
  assert.equal(isMissingFunctionError({ code: '42501', message: 'denied' }), false);
});

test('every stage has an explanatory empty state', () => {
  assert.equal(STAGE_COPY.evaluate.empty, 'Nothing waiting for evaluation');
  for (const stage of ['evaluate', 'finalize', 'release', 'released'] as const) {
    assert.ok(STAGE_COPY[stage].label && STAGE_COPY[stage].empty && STAGE_COPY[stage].help);
  }
});
