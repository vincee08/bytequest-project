import assert from 'node:assert/strict';
import { test } from 'node:test';
import { withFakeSupabase } from './support/fake-supabase';

// A chunked body has no content-length, so the size pre-check cannot bound
// it: the curriculum POST routes must answer 401/403 before reading it.
function streamedRequest(path: string, headers: Record<string, string> = {}) {
  let read = false;
  // highWaterMark 0: pull() runs only when someone reads the body.
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      read = true;
      controller.enqueue(new TextEncoder().encode('{"action":"complete_topic"}'));
      controller.close();
    },
  }, { highWaterMark: 0 });
  const request = new Request(`http://localhost:3008${path}`, {
    method: 'POST', body, headers: { 'content-type': 'application/json', ...headers }, duplex: 'half',
  } as RequestInit & { duplex: 'half' });
  return { request, wasRead: () => read };
}

test('the learner curriculum POST rejects an unauthenticated caller without reading the body', async () => {
  const { POST } = await import('../src/app/api/learner/curriculum/route');
  // No bearer token (the cookie path needs a Next request context).
  const { request, wasRead } = streamedRequest('/api/learner/curriculum', { authorization: 'Basic not-a-session' });
  const response = await POST(request);
  assert.equal(response.status, 401);
  assert.equal(wasRead(), false);
});

test('the learner curriculum POST rejects a staff caller without reading the body', async () => {
  await withFakeSupabase({ userId: '00000000-0000-4000-8000-0000000000a2', role: 'instructor' }, async () => {
    const { POST } = await import('../src/app/api/learner/curriculum/route');
    const { request, wasRead } = streamedRequest('/api/learner/curriculum', { authorization: 'Bearer test-token' });
    const response = await POST(request);
    assert.equal(response.status, 403);
    assert.equal(wasRead(), false);
  });
});

test('the staff curriculum POST rejects a learner without reading the body', async () => {
  await withFakeSupabase({ userId: '00000000-0000-4000-8000-0000000000a1', role: 'learner' }, async () => {
    const { POST } = await import('../src/app/api/curriculum/route');
    const { request, wasRead } = streamedRequest('/api/curriculum', { authorization: 'Bearer test-token' });
    const response = await POST(request);
    assert.equal(response.status, 403);
    assert.equal(wasRead(), false);
  });
});
