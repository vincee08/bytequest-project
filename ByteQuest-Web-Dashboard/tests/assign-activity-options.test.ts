import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  approvedRubricFor,
  assignmentTypesFor,
  defaultAssignmentType,
  deliveryKindLabel,
} from '../src/lib/activities/assignment-options';

const simulation = '00000000-0000-4000-8000-00000000a001';
const other = '00000000-0000-4000-8000-00000000a002';

test('assessment-only activities (the 20 simulation assessments) are assigned as Assessment only', () => {
  assert.equal(defaultAssignmentType('assessment'), 'assessment');
  assert.deepEqual(assignmentTypesFor('assessment'), ['assessment']);
});

test('practice and dual-mode activities keep Practice as the default and allow both types', () => {
  for (const mode of ['practice', 'both'] as const) {
    assert.equal(defaultAssignmentType(mode), 'practice');
    assert.deepEqual(assignmentTypesFor(mode), ['practice', 'assessment']);
  }
});

test('the delivery kind is labelled as the spec (WS2) names it', () => {
  assert.equal(deliveryKindLabel('simulation'), 'Simulation assessment');
  assert.equal(deliveryKindLabel('form_based'), 'Form-based assessment');
  assert.equal(deliveryKindLabel('protected_reference'), 'Form-based assessment');
  assert.equal(deliveryKindLabel(null), null);
  assert.equal(deliveryKindLabel('unexpected'), null);
});

test('the rubric is always the newest approved version of the selected activity version', () => {
  const rubrics = [
    // Another activity's rubric sorts first by title and has a higher version.
    { id: 'r-other', activityVersionId: other, title: 'A rubric', versionNumber: 9 },
    { id: 'r-old', activityVersionId: simulation, title: 'B rubric', versionNumber: 1 },
    { id: 'r-new', activityVersionId: simulation, title: 'C rubric', versionNumber: 2 },
  ];
  assert.equal(approvedRubricFor(rubrics, simulation)?.id, 'r-new');
  assert.equal(approvedRubricFor([...rubrics].reverse(), simulation)?.id, 'r-new');
  assert.equal(approvedRubricFor(rubrics, other)?.id, 'r-other');
  assert.equal(approvedRubricFor(rubrics, '00000000-0000-4000-8000-00000000a003'), undefined);
  assert.equal(approvedRubricFor(rubrics, ''), undefined);
});
