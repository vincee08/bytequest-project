import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bearerRequest, withFakeSupabase } from './support/fake-supabase';

// The 1.2.0+ learner app sends x-bytequest-app-version on every dashboard API
// request. A route that calls PostgREST as the learner forwards it, so the
// server's version check sees the real client (final fix wave, client version
// marker). Service-role calls are not app clients and do not need it.
const learner = '00000000-0000-4000-8000-0000000000a1';
const header = 'x-bytequest-app-version';
const learnerRpc = (calls: { path: string; headers: Record<string, string> }[]) =>
  calls.find((call) => call.path === '/rest/v1/rpc/get_learner_curriculum');

test('a learner route forwards the app version header to PostgREST calls made as the learner', async () => {
  await withFakeSupabase({ userId: learner, rpc: { get_learner_curriculum: { cocs: [] } } }, async (calls) => {
    const { GET } = await import('../src/app/api/learner/curriculum/route');
    const response = await GET(bearerRequest('/api/learner/curriculum', { headers: { [header]: '1.2.0' } }));
    assert.equal(response.status, 200);
    const call = learnerRpc(calls);
    assert.ok(call, 'the projection is read with the learner client');
    assert.equal(call.headers.authorization, 'Bearer test-token');
    assert.equal(call.headers[header], '1.2.0');
  });
});

test('a request without the header (an installed 1.1.0 app) is forwarded without one', async () => {
  await withFakeSupabase({ userId: learner, rpc: { get_learner_curriculum: { cocs: [] } } }, async (calls) => {
    const { GET } = await import('../src/app/api/learner/curriculum/route');
    await GET(bearerRequest('/api/learner/curriculum'));
    assert.equal(learnerRpc(calls)?.headers[header], undefined);
  });
});

test('a malformed version value is not forwarded', async () => {
  await withFakeSupabase({ userId: learner, rpc: { get_learner_curriculum: { cocs: [] } } }, async (calls) => {
    const { GET } = await import('../src/app/api/learner/curriculum/route');
    await GET(bearerRequest('/api/learner/curriculum', { headers: { [header]: `1.2.0 ${'x'.repeat(80)}` } }));
    assert.equal(learnerRpc(calls)?.headers[header], undefined);
  });
});
