import assert from 'node:assert/strict';
import { test } from 'node:test';

// Drives the real route handlers. Supabase Auth and PostgREST are replaced by
// a fake global fetch, so the assertions cover exactly what a learner's app
// receives from the dashboard API. `server-only` is a bundler guard; it is
// stubbed so the handlers load under plain Node (as Jest's module mappers do).
const serverOnly = require.resolve('server-only');
require.cache[serverOnly] = { id: serverOnly, filename: serverOnly, loaded: true, exports: {} } as unknown as NodeJS.Module;

const learner = '00000000-0000-4000-8000-0000000000a1';
const teacher = '00000000-0000-4000-8000-0000000000a2';
const assignment = '00000000-0000-4000-8000-0000000000b1';
const submission = '00000000-0000-4000-8000-0000000000c1';
const classId = '00000000-0000-4000-8000-0000000000d1';
const gradedRow = {
  id: submission, assignment_id: assignment, learner_id: learner, answer: 'Safety report', submitted_at: '2026-11-19T01:00:00Z',
  effective_deadline_at: null, deadline_revision: 1, lateness_seconds: 0, status: 'graded',
  feedback: 'Clear safety checks.', score: 40, criterion_scores: { safety: 25, order: 15 },
  graded_at: '2026-11-19T02:00:00Z', graded_by: teacher, finalized_by: null, finalized_at: null, released_by: null, released_at: null,
};

type Fake = { rpc?: Record<string, unknown>; tables?: Record<string, unknown>; role?: string };
async function withFakeSupabase(fake: Fake, run: (calls: string[]) => Promise<void>) {
  const calls: string[] = [];
  const originalFetch = globalThis.fetch;
  const env = { url: process.env.NEXT_PUBLIC_SUPABASE_URL, anon: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, service: process.env.SUPABASE_SERVICE_ROLE_KEY };
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'http://supabase.test';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-test-key';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-test-key';
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    calls.push(`${init?.method ?? 'GET'} ${url.pathname}`);
    if (url.pathname === '/auth/v1/user') {
      return Response.json({ id: learner, aud: 'authenticated', role: 'authenticated', email: 'learner@qa.invalid', app_metadata: {}, user_metadata: {}, created_at: '2026-11-19T00:00:00Z' });
    }
    if (url.pathname === '/rest/v1/profiles') return Response.json({ role: fake.role ?? 'learner', status: 'active' });
    const name = url.pathname.replace(/^\/rest\/v1\/(rpc\/)?/, '');
    if (url.pathname.startsWith('/rest/v1/rpc/') && fake.rpc && name in fake.rpc) return Response.json(fake.rpc[name]);
    if (fake.tables && name in fake.tables) return Response.json(fake.tables[name]);
    return Response.json({ message: `unexpected request ${url.pathname}` }, { status: 500 });
  }) as typeof fetch;
  try {
    await run(calls);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [['NEXT_PUBLIC_SUPABASE_URL', env.url], ['NEXT_PUBLIC_SUPABASE_ANON_KEY', env.anon], ['SUPABASE_SERVICE_ROLE_KEY', env.service]] as const) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
}
const learnerRequest = (path: string, init: RequestInit = {}) => new Request(`http://localhost:3008${path}`, {
  ...init, headers: { authorization: 'Bearer learner-token', 'content-type': 'application/json', ...(init.headers ?? {}) },
});
const assertNoGrade = (record: Record<string, unknown>) => {
  for (const field of ['score', 'feedback', 'criterion_scores', 'graded_by', 'graded_at', 'finalized_by', 'finalized_at', 'released_by']) {
    assert.equal(record[field], null, `${field} must be hidden before release`);
  }
};

test('a learner submit retry never receives an unreleased grade from the route', async () => {
  // Even if the RPC ever returned a graded row, the route redacts it.
  await withFakeSupabase({ rpc: { manage_homework: gradedRow } }, async (calls) => {
    const { POST } = await import('../src/app/api/activities/homework/route');
    const response = await POST(learnerRequest('/api/activities/homework', {
      method: 'POST', body: JSON.stringify({ action: 'submit', assignment_id: assignment, answer: 'Retry', file_ids: [] }),
    }));
    assert.equal(response.status, 200);
    const { record } = await response.json();
    assert.equal(record.id, submission);
    assertNoGrade(record);
    assert.equal(record.evaluation_status, 'graded');
    assert.equal(record.status, 'submitted', 'installed apps keep treating it as not yet graded');
    assert.ok(calls.includes('POST /rest/v1/rpc/manage_homework'));
  });
});

test('a learner submit retry after release receives the released result', async () => {
  const released = { ...gradedRow, status: 'released', finalized_by: teacher, finalized_at: '2026-11-19T03:00:00Z', released_by: teacher, released_at: '2026-11-19T04:00:00Z' };
  await withFakeSupabase({ rpc: { manage_homework: released } }, async () => {
    const { POST } = await import('../src/app/api/activities/homework/route');
    const response = await POST(learnerRequest('/api/activities/homework', {
      method: 'POST', body: JSON.stringify({ action: 'submit', assignment_id: assignment, answer: 'Retry', file_ids: [] }),
    }));
    const { record } = await response.json();
    assert.equal(record.score, 40);
    assert.equal(record.feedback, 'Clear safety checks.');
    assert.equal(record.status, 'graded');
    assert.equal(record.graded_by, null, 'instructor identifiers stay hidden from learners');
  });
});

test('the learner homework read hides a graded-but-unreleased submission', async () => {
  const homework = { id: assignment, class_id: classId, instructor_id: teacher, title: 'Assembly safety report', instructions: 'Document the checks.', status: 'published',
    deadline_at: null, published_at: '2026-11-18T00:00:00Z', revision: 1, created_at: '2026-11-18T00:00:00Z', updated_at: '2026-11-18T00:00:00Z',
    coc_module_id: null, module_id: null, mission_code: null, learning_objectives: [], criteria: [], max_score: 100, submission_requirements: null };
  await withFakeSupabase({ tables: { homework_assignments: [homework], homework_submissions: [gradedRow], homework_files: [], classes: [{ id: classId, title: 'Sample Class A' }] } }, async () => {
    const { GET } = await import('../src/app/api/activities/homework/route');
    const response = await GET(learnerRequest(`/api/activities/homework?id=${assignment}`));
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.submissions.length, 1);
    assertNoGrade(body.submissions[0]);
    assert.equal(body.submissions[0].evaluation_status, 'graded');
  });
});

test('learners cannot read or act through the Evaluation Center API', async () => {
  await withFakeSupabase({ rpc: { get_evaluation_queue: { items: [] }, record_attempt_evaluation: {} } }, async (calls) => {
    const { GET, POST } = await import('../src/app/api/evaluations/route');
    assert.equal((await GET(learnerRequest('/api/evaluations?tab=evaluate'))).status, 403);
    const post = await POST(learnerRequest('/api/evaluations', { method: 'POST', body: JSON.stringify({ kind: 'homework', action: 'release', submission_ids: [submission] }) }));
    assert.equal(post.status, 403);
    assert.ok(!calls.some((call) => call.includes('/rpc/')), 'no evaluation RPC is reached for a learner');
  });
});
