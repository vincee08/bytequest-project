import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { allRemainingMissionPackages, validateMissionPackages } from '../all-mission-assessment-packages.mjs';
import { coc1M3InstallationDraft as draft, installationDraftLearnerPreview, installationDraftRubricProposal } from './coc1-m3-installation-draft.mjs';

test('draft identity cannot collide with the preserved cabling package', () => {
  const legacy = allRemainingMissionPackages.find(item => item.missionCode === 'coc1_m3');
  assert.equal(legacy.packageId, draft.preservesPackageId);
  assert.notEqual(legacy.packageId, draft.definition.packageId);
  assert.ok(legacy.criteria.some(item => item.stage.action_type === 'coc1_m3_connections_submitted'));
  assert.ok(!allRemainingMissionPackages.some(item => item.packageId === draft.definition.packageId));
  assert.equal(draft.publishable, false);
  assert.deepEqual(Object.values(draft.approval), [null, null, null]);
});

test('review draft has complete unique five-stage contracts without approved scoring', () => {
  assert.equal(validateMissionPackages([draft.definition]).criteria, 5);
  const rules = installationDraftRubricProposal();
  assert.ok(rules.every(rule => rule.scoring_rule.status === 'PENDING_INSTRUCTOR_VALIDATION'));
  assert.ok(rules.every(rule => rule.source_trace.startsWith('PROPOSED')));
  assert.equal(draft.resultVisibility, 'released_only');
  assert.equal(draft.releaseAuthority, 'authenticated_instructor');
});

test('learner preview strips expected values and trusted evaluation rules recursively', () => {
  const forbidden = new Set(['expected', 'expected_targets', 'evidence_rule', 'scoring_rule', 'equipment_effects']);
  function check(value) {
    if (!value || typeof value !== 'object') return;
    for (const [key, child] of Object.entries(value)) {
      assert.ok(!forbidden.has(key), `Answer metadata leaked: ${key}`);
      check(child);
    }
  }
  const preview = installationDraftLearnerPreview();
  check(preview);
  assert.equal(preview.review_only, true);
  assert.equal(preview.publishable, false);
  assert.equal(preview.stages.length, 5);
});

test('draft is tied to the actual PDF and has mandatory trusted-state review gates', () => {
  const pdf = readFileSync(new URL('../../docs/reference/ByteQuest_Interactive_2D_Mobile_App_Todo_List.pdf', import.meta.url));
  assert.equal(createHash('sha256').update(pdf).digest('hex'), draft.reference.sha256);
  assert.ok(draft.reviewGates.some(gate => gate.includes('never trust client')));
  assert.ok(draft.reviewGates.some(gate => gate.includes('latest configuration revision')));
  assert.ok(draft.reviewGates.some(gate => gate.includes('detached answer form')));
});
