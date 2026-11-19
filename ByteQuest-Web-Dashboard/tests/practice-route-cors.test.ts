import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bearerRequest, withFakeSupabase } from './support/fake-supabase';

// The real /api/learner/practice handlers. The Flutter web preview
// (127.0.0.1:3009) calls this route cross-origin, so the browser sends a
// preflight first and reads every reply only with an Allow-Origin header.
const preview = 'http://127.0.0.1:3009';
const learner = '00000000-0000-4000-8000-0000000000a1';
const route = 'http://localhost:3008/api/learner/practice';
const preflight = (origin: string) => new Request(route, {
  method: 'OPTIONS',
  headers: {
    origin,
    'access-control-request-method': 'POST',
    'access-control-request-headers': 'authorization,content-type,x-bytequest-app-version',
  },
});

test('a preflight from the local web preview is answered with CORS access', async () => {
  const { OPTIONS } = await import('../src/app/api/learner/practice/route');
  const response = await OPTIONS(preflight(preview));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-origin'), preview);
  assert.match(response.headers.get('access-control-allow-methods') ?? '', /\bPOST\b/);
  const allowed = (response.headers.get('access-control-allow-headers') ?? '').toLowerCase();
  for (const header of ['authorization', 'content-type', 'x-bytequest-app-version']) {
    assert.ok(allowed.split(/,\s*/).includes(header), `${header} must be an allowed request header`);
  }
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
});

test('a preflight from an unknown origin gets no CORS access', async () => {
  const { OPTIONS } = await import('../src/app/api/learner/practice/route');
  const response = await OPTIONS(preflight('https://attacker.example'));
  assert.equal(response.headers.get('access-control-allow-origin'), null);
  assert.equal(response.headers.get('access-control-allow-headers'), null);
});

test('practice replies carry the CORS headers, so the preview can read errors and results', async () => {
  await withFakeSupabase({ userId: learner }, async () => {
    const { GET, POST } = await import('../src/app/api/learner/practice/route');
    const unauthenticated = await POST(new Request(route, {
      method: 'POST',
      headers: { origin: preview, 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'verify', mission: 'coc1_m2' }),
    }));
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.headers.get('access-control-allow-origin'), preview);
    assert.equal(unauthenticated.headers.get('cache-control'), 'private, no-store');

    const invalid = await GET(bearerRequest('/api/learner/practice?attempt=not-a-uuid', { headers: { origin: preview } }));
    assert.equal(invalid.status, 400);
    assert.equal(invalid.headers.get('access-control-allow-origin'), preview);

    const foreign = await GET(bearerRequest('/api/learner/practice?attempt=not-a-uuid', { headers: { origin: 'https://attacker.example' } }));
    assert.equal(foreign.status, 400);
    assert.equal(foreign.headers.get('access-control-allow-origin'), null);
  });
});
