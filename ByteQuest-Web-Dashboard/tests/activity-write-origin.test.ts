import assert from 'node:assert/strict';
import { test } from 'node:test';
// Registers the server-only stub so the server module can load in tests.
import './support/fake-supabase';
import { activityWriteOriginAllowed } from '../src/lib/activities/server';

// Same-origin guard shared by every dashboard write route (evaluations,
// homework, quizzes, roster import, uploads, curriculum, student IDs...).
// Locally `next start` reports the request URL as localhost even when the
// browser opened 127.0.0.1 (and the reverse), so loopback names must count
// as the same origin; production hosts are compared exactly.
const post = (url: string, headers: Record<string, string> = {}) =>
  new Request(url, { method: 'POST', headers });

test('a local dashboard opened at 127.0.0.1 can write when Next reports localhost', () => {
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3001/api/evaluations', { origin: 'http://127.0.0.1:3001' })), true);
  assert.equal(activityWriteOriginAllowed(post('http://127.0.0.1:3001/api/evaluations', { origin: 'http://localhost:3001' })), true);
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3008/api/evaluations', { origin: 'http://127.0.0.1:3008' })), true);
});

test('loopback equivalence never crosses ports, schemes or real hosts', () => {
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3001/api/evaluations', { origin: 'http://127.0.0.1:3002' })), false);
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3001/api/evaluations', { origin: 'https://127.0.0.1:3001' })), false);
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3001/api/evaluations', { origin: 'http://evil.example' })), false);
  // A page on the learner's own machine must not write to production.
  assert.equal(activityWriteOriginAllowed(post('https://bytequest-alpha.vercel.app/api/evaluations', { origin: 'http://localhost:3001' })), false);
  assert.equal(activityWriteOriginAllowed(post('https://bytequest-alpha.vercel.app/api/evaluations', { origin: 'not a url' })), false);
});

test('production same-origin writes, origin-less clients and the bearer web preview keep working', () => {
  assert.equal(activityWriteOriginAllowed(post('https://bytequest-alpha.vercel.app/api/evaluations', { origin: 'https://bytequest-alpha.vercel.app' })), true);
  assert.equal(activityWriteOriginAllowed(post('https://bytequest-alpha.vercel.app/api/evaluations')), true);
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3001/api/learner/practice', { origin: 'http://127.0.0.1:3009', authorization: 'Bearer token' })), true);
  assert.equal(activityWriteOriginAllowed(post('http://localhost:3001/api/learner/practice', { origin: 'http://127.0.0.1:3009' })), false);
});
