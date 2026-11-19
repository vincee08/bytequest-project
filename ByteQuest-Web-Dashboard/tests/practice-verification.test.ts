import assert from 'node:assert/strict';
import test from 'node:test';
import {
  practiceFailureCode,
  verifyPracticeMission,
  type PracticeRpcError,
  type PracticeRunRow,
  type PracticeVerificationPort,
} from '../src/lib/practice/verification';

type Call = { name: string; args: unknown[] };

function port({
  verifyError = null,
  recordError = null,
  runs = [],
}: {
  verifyError?: PracticeRpcError;
  recordError?: PracticeRpcError;
  runs?: PracticeRunRow[];
}) {
  const calls: Call[] = [];
  const stored = [...runs];
  const fake: PracticeVerificationPort = {
    async verify(...args) {
      calls.push({ name: 'verify', args });
      if (!verifyError) {
        stored.push({ run_number: stored.length + 1, duration_seconds: 312, invalid_count: 2, correction_count: 1, outcome: 'verified', failure_code: null });
      }
      return verifyError;
    },
    async recordFailure(...args) {
      calls.push({ name: 'recordFailure', args });
      if (!recordError) {
        stored.push({ run_number: stored.length + 1, duration_seconds: 95, invalid_count: 4, correction_count: 0, outcome: 'incomplete', failure_code: args[2] });
      }
      return recordError;
    },
    async latestRun(...args) {
      calls.push({ name: 'latestRun', args });
      return stored.at(-1) ?? null;
    },
  };
  return { fake, calls };
}

test('a verified practice run returns its server-computed metrics', async () => {
  const { fake, calls } = port({});
  const reply = await verifyPracticeMission(fake, 'learner-1', 'coc1_m2');
  assert.equal(reply.status, 200);
  assert.deepEqual(reply.body, { verified: true, run: { run_number: 1, duration_seconds: 312, invalid_count: 2, correction_count: 1 } });
  assert.deepEqual(calls.map((call) => call.name), ['verify', 'latestRun']);
  assert.deepEqual(calls[0].args, ['learner-1', 'coc1_m2']);
});

test('an incomplete run is recorded as a failed verification with its metrics', async () => {
  const { fake, calls } = port({ verifyError: { code: '22023', message: 'PRACTICE_WORK_INCOMPLETE:coc1_m2_p5' } });
  const reply = await verifyPracticeMission(fake, 'learner-1', 'coc1_m2');
  assert.equal(reply.status, 422);
  assert.deepEqual(reply.body, {
    error: 'Complete and verify each work phase before submitting practice evidence.',
    failure: 'PRACTICE_WORK_INCOMPLETE:coc1_m2_p5',
    run: { run_number: 1, duration_seconds: 95, invalid_count: 4, correction_count: 0 },
  });
  assert.deepEqual(calls.find((call) => call.name === 'recordFailure')?.args,
    ['learner-1', 'coc1_m2', 'PRACTICE_WORK_INCOMPLETE:coc1_m2_p5']);
});

test('locked missions are refused without recording a run', async () => {
  const { fake, calls } = port({ verifyError: { code: '42501', message: 'PRACTICE_COC_LOCKED' } });
  const reply = await verifyPracticeMission(fake, 'learner-1', 'coc2_m1');
  assert.equal(reply.status, 403);
  assert.deepEqual(reply.body, {
    error: 'Complete and verify each work phase before submitting practice evidence.', failure: null, run: null,
  });
  assert.deepEqual(calls.map((call) => call.name), ['verify']);
});

test('infrastructure errors are not recorded as learner runs and expose no internals', async () => {
  const { fake, calls } = port({ verifyError: { code: 'XX000', message: 'relation "x" does not exist' } });
  const reply = await verifyPracticeMission(fake, 'learner-1', 'coc1_m1');
  assert.equal(reply.status, 422);
  assert.equal('failure' in reply.body && reply.body.failure, null);
  assert.equal(JSON.stringify(reply.body).includes('relation'), false);
  assert.deepEqual(calls.map((call) => call.name), ['verify']);
});

test('a failed recording still answers the learner without metrics', async () => {
  const { fake } = port({
    verifyError: { code: 'P0001', message: 'PRACTICE_EVIDENCE_REQUIRED' },
    recordError: { code: '42501', message: 'permission denied' },
  });
  const reply = await verifyPracticeMission(fake, 'learner-1', 'coc1_m1');
  assert.equal(reply.status, 422);
  assert.equal('run' in reply.body && reply.body.run, null);
});

test('a stale run from an earlier failure is never reported as the current run', async () => {
  const { fake } = port({
    verifyError: { code: '22023', message: 'PRACTICE_WORK_INCOMPLETE:coc1_m2_p2' },
    recordError: null,
    runs: [{ run_number: 1, duration_seconds: 10, invalid_count: 0, correction_count: 0, outcome: 'verified', failure_code: null }],
  });
  const reply = await verifyPracticeMission({ ...fake, recordFailure: async () => null }, 'learner-1', 'coc1_m2');
  assert.equal('run' in reply.body && reply.body.run, null);
});

test('only the verifier codes are accepted as failure codes', () => {
  assert.equal(practiceFailureCode({ message: 'PRACTICE_WORK_INCOMPLETE:coc3_m1_p4' }), 'PRACTICE_WORK_INCOMPLETE:coc3_m1_p4');
  assert.equal(practiceFailureCode({ message: 'PRACTICE_EVIDENCE_REQUIRED' }), 'PRACTICE_EVIDENCE_REQUIRED');
  assert.equal(practiceFailureCode({ message: "PRACTICE_WORK_INCOMPLETE:x'; drop" }), null);
  assert.equal(practiceFailureCode({ message: 'PRACTICE_COC_LOCKED' }), null);
  assert.equal(practiceFailureCode(null), null);
});
