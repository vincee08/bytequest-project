import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bearerRequest, withFakeSupabase, type FakeReply } from './support/fake-supabase';
import { quizActionPayload, quizItemResult, runQuizAction, type QuizEvaluationCall } from '../src/lib/evaluations/quiz-actions';
import { evaluationErrorMessage } from '../src/lib/evaluations/requests';
import { bulkRequestBodies, queueActionLabel, queueScoreText, queueStatusText } from '../src/lib/evaluations/display';

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const teacher = uuid(900);
const rpcError = (message: string, code = '55000'): FakeReply => ({ status: 400, body: { code, message, details: null, hint: null } });

test('quiz actions use slice A3 payloads: finalize {attempt_id}, release {attempt_ids:[id]}', () => {
  assert.deepEqual(quizActionPayload('finalize', uuid(1)), { attempt_id: uuid(1) });
  assert.deepEqual(quizActionPayload('release', uuid(1)), { attempt_ids: [uuid(1)] });
  assert.deepEqual(quizItemResult('finalize', uuid(1), { attempt_id: uuid(1), evaluation_status: 'finalized', already: false }),
    { id: uuid(1), ok: true, status: 'finalized', changed: true });
  assert.deepEqual(quizItemResult('finalize', uuid(1), { attempt_id: uuid(1), evaluation_status: 'released', already: true }),
    { id: uuid(1), ok: true, status: 'released', changed: false });
  assert.deepEqual(quizItemResult('release', uuid(1), { released: [uuid(1)], already_released: [] }), { id: uuid(1), ok: true, status: 'released', changed: true });
  assert.deepEqual(quizItemResult('release', uuid(1), { released: [], already_released: [uuid(1)] }), { id: uuid(1), ok: true, status: 'released', changed: false });
});

test('bulk quiz actions call once per attempt and report each item', async () => {
  const sent: [string, Record<string, unknown>][] = [];
  const call: QuizEvaluationCall = async (action, payload) => {
    sent.push([action, payload]);
    if (payload.attempt_id === uuid(2)) return { data: null, error: { code: '55000', message: 'QUIZ_ESSAYS_NOT_SCORED' } };
    return { data: { attempt_id: payload.attempt_id, evaluation_status: 'finalized', already: false }, error: null };
  };
  const outcome = await runQuizAction(call, 'finalize', [uuid(1), uuid(2), uuid(3)]);
  assert.equal(outcome.unavailable, false);
  assert.deepEqual(sent.map(([, payload]) => payload), [{ attempt_id: uuid(1) }, { attempt_id: uuid(2) }, { attempt_id: uuid(3) }]);
  assert.deepEqual(outcome.results.map((r) => r.ok), [true, false, true]);
  assert.match(outcome.results[1].error ?? '', /Score every answered essay/);
  const missing = await runQuizAction(async () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } }), 'release', [uuid(1), uuid(2)]);
  assert.equal(missing.unavailable, true);
});

test('every slice A3 evaluation error has a clear technical message', () => {
  const cases: [string, RegExp, number][] = [
    ['QUIZ_EVALUATION_SCOPE_DENIED', /another instructor/, 403],
    ['QUIZ_ESSAYS_NOT_SCORED', /Score every answered essay/, 409],
    ['QUIZ_RESULT_NOT_FINALIZED', /Finalize the quiz result/, 409],
    ['QUIZ_EVALUATION_NOT_REQUIRED', /immediately/, 409],
    ['QUIZ_EVALUATION_STATE_INVALID', /another stage/, 409],
    ['QUIZ_EVALUATION_SELECTION_INVALID', /up to 50/, 422],
    ['QUIZ_ESSAY_NOT_ANSWERED', /unanswered/, 422],
    ['QUIZ_ESSAY_SCORE_INVALID', /between 0 and its maximum/, 422],
    ['QUIZ_ESSAY_SCORE_OUT_OF_RANGE', /between 0 and its maximum/, 422],
    ['QUIZ_ESSAY_FEEDBACK_TOO_LONG', /5,000/, 422],
    ['FINALIZED_QUIZ_RESULT_IS_IMMUTABLE', /cannot be changed/, 409],
    ['INSTRUCTOR_REQUIRED', /instructor/, 403],
  ];
  for (const [code, pattern, status] of cases) {
    const mapped = evaluationErrorMessage({ message: code });
    assert.ok(mapped, code);
    assert.match(mapped!.error, pattern, code);
    assert.equal(mapped!.status, status, code);
  }
});

test('quiz rows show essay states, the score or Awaiting essay scores, and a link to score essays', () => {
  const pending = { kind: 'quiz' as const, status: 'pending', score: null, max_score: 11 };
  assert.equal(queueScoreText(pending), 'Awaiting essay scores');
  assert.equal(queueStatusText(pending), 'Essays awaiting scores');
  assert.equal(queueActionLabel('evaluate', pending), 'Score essays');
  assert.equal(queueScoreText({ kind: 'quiz', score: 9, max_score: 11 }), '9 / 11');
  assert.equal(queueStatusText({ kind: 'quiz', status: 'evaluated' }), 'Essays scored');
  assert.equal(queueStatusText({ kind: 'technical', status: 'evaluated' }), 'Evaluated (automatic)');
  assert.equal(queueStatusText({ kind: 'homework', status: 'graded' }), 'Grade saved');
  assert.equal(queueScoreText({ kind: 'homework', score: null, max_score: 100 }), 'No score');
  assert.equal(queueActionLabel('release', pending), 'Open');
  assert.deepEqual(bulkRequestBodies([
    { kind: 'technical', id: uuid(1) }, { kind: 'quiz', id: uuid(2) }, { kind: 'homework', id: uuid(3) }, { kind: 'quiz', id: uuid(4) },
  ], 'release'), [
    { kind: 'technical', action: 'release', attempt_ids: [uuid(1)] },
    { kind: 'quiz', action: 'release', attempt_ids: [uuid(2), uuid(4)] },
    { kind: 'homework', action: 'release', submission_ids: [uuid(3)] },
  ]);
});

test('the Evaluation Center route finalizes quizzes one attempt at a time through A3', async () => {
  const a = uuid(11), b = uuid(12);
  await withFakeSupabase({
    userId: teacher, role: 'instructor',
    rpc: { manage_quiz_evaluation: (body) => (body.p_payload as { attempt_id?: string }).attempt_id === a
      ? { status: 200, body: { attempt_id: a, evaluation_status: 'finalized', total_points: 9, max_points: 11, percent: 81.82, already: false } }
      : rpcError('QUIZ_ESSAYS_NOT_SCORED') },
  }, async (calls) => {
    const { POST } = await import('../src/app/api/evaluations/route');
    const response = await POST(bearerRequest('/api/evaluations', { method: 'POST', body: JSON.stringify({ kind: 'quiz', action: 'finalize', attempt_ids: [a, b] }) }));
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.succeeded, 1);
    assert.equal(body.failed, 1);
    assert.deepEqual(body.results[0], { id: a, ok: true, status: 'finalized', changed: true });
    assert.match(body.results[1].error, /Score every answered essay/);
    assert.deepEqual(calls.filter((c) => c.path === '/rest/v1/rpc/manage_quiz_evaluation').map((c) => c.body), [
      { p_actor: teacher, p_action: 'finalize', p_payload: { attempt_id: a } },
      { p_actor: teacher, p_action: 'finalize', p_payload: { attempt_id: b } },
    ]);
  });
});

test('the Evaluation Center route releases quizzes with {attempt_ids:[id]} and reports scope denials', async () => {
  const a = uuid(21), b = uuid(22), c = uuid(23);
  await withFakeSupabase({
    userId: teacher, role: 'instructor',
    rpc: { manage_quiz_evaluation: (body) => {
      const [id] = (body.p_payload as { attempt_ids: string[] }).attempt_ids;
      if (id === a) return { status: 200, body: { released: [a], already_released: [] } };
      if (id === b) return { status: 200, body: { released: [], already_released: [b] } };
      return rpcError('QUIZ_EVALUATION_SCOPE_DENIED', '42501');
    } },
  }, async (calls) => {
    const { POST } = await import('../src/app/api/evaluations/route');
    const body = await (await POST(bearerRequest('/api/evaluations', { method: 'POST', body: JSON.stringify({ kind: 'quiz', action: 'release', attempt_ids: [a, b, c] }) }))).json();
    assert.deepEqual(body.results.map((r: { changed?: boolean; ok: boolean }) => [r.ok, r.changed ?? null]), [[true, true], [true, false], [false, null]]);
    assert.match(body.results[2].error, /another instructor/);
    assert.deepEqual(calls.filter((call) => call.path === '/rest/v1/rpc/manage_quiz_evaluation').map((call) => (call.body as { p_payload: unknown }).p_payload),
      [{ attempt_ids: [a] }, { attempt_ids: [b] }, { attempt_ids: [c] }]);
  });
});

test('quiz actions answer 501 when the quiz evaluation function is not installed', async () => {
  await withFakeSupabase({ userId: teacher, role: 'instructor' }, async () => {
    const { POST } = await import('../src/app/api/evaluations/route');
    const response = await POST(bearerRequest('/api/evaluations', { method: 'POST', body: JSON.stringify({ kind: 'quiz', action: 'release', attempt_ids: [uuid(31)] }) }));
    assert.equal(response.status, 501);
    assert.match((await response.json()).error, /not available on this server yet/);
  });
});
