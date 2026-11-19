import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  criteriaTotal, curriculumFromHomework, curriculumPayload, emptyCurriculum, homeworkActionSchema, homeworkErrorMessage,
  homeworkStatusLabel, learnerRecordView, learnerSubmissionView, selectCoc, selectMission, staffSubmissionView,
} from '../src/lib/evaluations/homework';
import type { CurriculumOptions, HomeworkSubmissionRecord } from '../src/lib/evaluations/types';

const options: CurriculumOptions = {
  cocs: [{ id: '00000000-0000-4000-8000-0000000c0c01', coc_code: 'coc1', title: 'Install and Configure Computer Systems' }, { id: '00000000-0000-4000-8000-0000000c0c02', coc_code: 'coc2', title: 'Set-up Computer Networks' }],
  missions: [{ mission_code: 'coc1_m2', title: 'Install Internal Components', coc_id: '00000000-0000-4000-8000-0000000c0c01' }, { mission_code: 'coc2_m2', title: 'Create Network Cables', coc_id: '00000000-0000-4000-8000-0000000c0c02' }],
  modules: [{ id: '00000000-0000-4000-8000-00000000a011', coc_module_id: '00000000-0000-4000-8000-0000000c0c01', coc_code: 'coc1', code: 'LO1.1', title: 'Assemble computer hardware', sequence_order: 1 },
    { id: '00000000-0000-4000-8000-00000000a021', coc_module_id: '00000000-0000-4000-8000-0000000c0c02', coc_code: 'coc2', code: 'LO2.1', title: 'Install network cables', sequence_order: 1 }],
  links: [{ mission_code: 'coc1_m2', module_id: '00000000-0000-4000-8000-00000000a011' }, { mission_code: 'coc2_m2', module_id: '00000000-0000-4000-8000-00000000a021' }],
};

test('authoring derives the module from the mission and keeps COC choices consistent', () => {
  const chosen = selectMission(emptyCurriculum(), 'coc1_m2', options);
  assert.equal(chosen.coc_module_id, '00000000-0000-4000-8000-0000000c0c01');
  assert.equal(chosen.module_id, '00000000-0000-4000-8000-00000000a011');
  const switched = selectCoc(chosen, '00000000-0000-4000-8000-0000000c0c02', options);
  assert.equal(switched.mission_code, '');
  assert.equal(switched.module_id, '');
  const kept = selectCoc(chosen, '00000000-0000-4000-8000-0000000c0c01', options);
  assert.equal(kept.mission_code, 'coc1_m2');
  const payload = curriculumPayload({ ...chosen, learning_objectives: [' Apply ESD precautions ', ''], criteria: [
    { id: 'safety', criterion: ' Safety checks ', description: '', max_points: '30' },
    { id: 'blank', criterion: '', description: '', max_points: '' },
  ], max_score: '80', submission_requirements: '  PDF  ' });
  assert.deepEqual(payload.criteria, [{ id: 'safety', criterion: 'Safety checks', description: null, max_points: 30 }]);
  assert.equal(payload.max_score, null, 'the server computes the maximum from the criteria');
  assert.deepEqual(payload.learning_objectives, ['Apply ESD precautions']);
  assert.equal(payload.submission_requirements, 'PDF');
  assert.equal(curriculumPayload(emptyCurriculum()).max_score, 100);
  assert.equal(curriculumPayload(emptyCurriculum()).mission_code, null);
  const restored = curriculumFromHomework({ criteria: [{ id: 'a', criterion: 'A', description: null, max_points: 5 }], max_score: 5 });
  assert.equal(restored.criteria[0].max_points, '5');
  assert.equal(restored.max_score, '5');
  assert.equal(homeworkActionSchema.safeParse({ action: 'edit', assignment_id: uuid(2), title: 'Report', instructions: 'Write it.', deadline_at: null, ...payload }).success, true);
});

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const base: HomeworkSubmissionRecord = {
  id: uuid(1), assignment_id: uuid(2), learner_id: uuid(3), answer: 'Report', submitted_at: '2026-11-19T01:00:00Z',
  effective_deadline_at: null, deadline_revision: 1, lateness_seconds: 0, status: 'submitted', feedback: null, score: null,
  graded_at: null, graded_by: null, criterion_scores: null, finalized_by: null, finalized_at: null, released_by: null, released_at: null,
};
const graded: HomeworkSubmissionRecord = {
  ...base, status: 'graded', score: 40, feedback: 'Clear safety checks.', criterion_scores: { safety: 25, order: 15 },
  graded_at: '2026-11-19T02:00:00Z', graded_by: uuid(9),
};

test('learner view hides every grade field until release', () => {
  for (const status of ['graded', 'finalized'] as const) {
    const view = learnerSubmissionView({ ...graded, status, finalized_at: status === 'finalized' ? '2026-11-19T03:00:00Z' : null, finalized_by: status === 'finalized' ? uuid(9) : null });
    assert.equal(view.evaluation_status, status);
    assert.equal(view.score, null);
    assert.equal(view.feedback, null);
    assert.equal(view.criterion_scores, null);
    assert.equal(view.graded_at, null);
    assert.equal(view.graded_by, null);
    assert.equal(view.finalized_by, null);
    // Installed app versions treat `graded` as "result visible".
    assert.equal(view.status, 'submitted');
  }
});

test('every learner action reply is redacted before release', () => {
  const view = learnerRecordView(graded) as Record<string, unknown>;
  assert.equal(view.score, null);
  assert.equal(view.feedback, null);
  assert.equal(view.criterion_scores, null);
  assert.equal(view.graded_by, null);
  assert.equal(view.evaluation_status, 'graded');
  const file = { id: uuid(7), assignment_id: uuid(2), owner_id: uuid(3), kind: 'answer', filename: 'report.pdf', size_bytes: 10 };
  assert.deepEqual(learnerRecordView(file), file, 'non-submission records pass through unchanged');
  assert.equal(learnerRecordView(null), null);
});

test('learner view exposes the released grade and keeps old apps working', () => {
  const released = { ...graded, status: 'released' as const, finalized_at: '2026-11-19T03:00:00Z', finalized_by: uuid(9), released_at: '2026-11-19T04:00:00Z', released_by: uuid(9) };
  const view = learnerSubmissionView(released);
  assert.equal(view.evaluation_status, 'released');
  assert.equal(view.status, 'graded');
  assert.equal(view.score, 40);
  assert.equal(view.feedback, 'Clear safety checks.');
  assert.deepEqual(view.criterion_scores, { safety: 25, order: 15 });
  assert.equal(view.released_at, '2026-11-19T04:00:00Z');
  assert.equal(view.graded_by, null, 'instructor identifiers are not exposed to learners');
  assert.equal(learnerSubmissionView(base).status, 'submitted');
  assert.equal(staffSubmissionView(graded).evaluation_status, 'graded');
  assert.equal(staffSubmissionView(graded).score, 40);
});

test('homework actions validate the new curriculum, criteria and workflow fields', () => {
  const create = homeworkActionSchema.safeParse({
    action: 'create', class_id: uuid(5), title: 'Assembly safety report', instructions: 'Document the checks.', deadline_at: null,
    coc_module_id: uuid(6), mission_code: 'coc1_m2', module_id: uuid(7), learning_objectives: ['Apply ESD precautions'],
    criteria: [{ id: 'safety', criterion: 'Safety checks', description: 'Power and ESD', max_points: 30 }],
    submission_requirements: 'PDF report',
  });
  assert.equal(create.success, true);
  // Previous-version payloads stay valid.
  assert.equal(homeworkActionSchema.safeParse({ action: 'create', class_id: uuid(5), title: 'Report', instructions: 'Write it.', deadline_at: null }).success, true);
  assert.equal(homeworkActionSchema.safeParse({ action: 'grade', assignment_id: uuid(2), submission_id: uuid(1), feedback: 'Fine', score: null }).success, true);
  assert.equal(homeworkActionSchema.safeParse({ action: 'grade', submission_id: uuid(1), feedback: '', score: 40, criterion_scores: { safety: 25, order: 15 } }).success, true);
  for (const invalid of [
    { action: 'create', class_id: uuid(5), title: 'Report', instructions: 'Write it.', deadline_at: null, mission_code: 'drop table' },
    { action: 'create', class_id: uuid(5), title: 'Report', instructions: 'Write it.', deadline_at: null, criteria: [{ criterion: 'Zero', max_points: 0 }] },
    { action: 'create', class_id: uuid(5), title: 'Report', instructions: 'Write it.', deadline_at: null, criteria: [{ id: 'a', criterion: 'One', max_points: 5 }, { id: 'a', criterion: 'Two', max_points: 5 }] },
    { action: 'grade', submission_id: uuid(1), feedback: '', score: -1 },
    { action: 'grade', submission_id: uuid(1), feedback: '', score: 5, criterion_scores: { 'bad key!': 5 } },
    { action: 'finalize', submission_ids: [] },
    { action: 'release', submission_ids: Array.from({ length: 51 }, (_, i) => uuid(100 + i)) },
    { action: 'release', submission_ids: [uuid(1), uuid(1)] },
    { action: 'finalize', submission_ids: ['not-a-uuid'] },
    { action: 'publish', assignment_id: uuid(2), extra: true },
  ]) assert.equal(homeworkActionSchema.safeParse(invalid).success, false, JSON.stringify(invalid));
  assert.equal(homeworkActionSchema.safeParse({ action: 'release', submission_ids: [uuid(1), uuid(2)] }).success, true);
});

test('criteria totals and status labels follow Evaluate, Finalize and Release', () => {
  assert.equal(criteriaTotal([{ id: 'a', criterion: 'A', description: null, max_points: 30 }, { id: 'b', criterion: 'B', description: null, max_points: 20.5 }]), 50.5);
  assert.equal(criteriaTotal([]), 0);
  assert.equal(homeworkStatusLabel('submitted'), 'Awaiting evaluation');
  assert.equal(homeworkStatusLabel('graded'), 'Evaluated (draft)');
  assert.equal(homeworkStatusLabel('finalized'), 'Finalized');
  assert.equal(homeworkStatusLabel('released'), 'Released');
});

test('homework errors explain the technical reason', () => {
  assert.match(homeworkErrorMessage({ message: 'HOMEWORK_SCORE_EXCEEDS_MAX' })!.error, /maximum score/);
  assert.equal(homeworkErrorMessage({ message: 'HOMEWORK_GRADE_LOCKED' })!.status, 409);
  assert.match(homeworkErrorMessage({ message: 'HOMEWORK_MAX_SCORE_MUST_EQUAL_CRITERIA_TOTAL' })!.error, /criteria/);
  assert.match(homeworkErrorMessage({ message: 'HOMEWORK_CURRICULUM_MISMATCH' })!.error, /COC/);
  assert.equal(homeworkErrorMessage({ message: 'SOMETHING_ELSE' }), null);
});
