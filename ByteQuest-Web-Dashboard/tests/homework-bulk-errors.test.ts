import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bearerRequest, withFakeSupabase } from './support/fake-supabase';

// manage_homework's bulk finalize/release returns per-item `error: sqlerrm`
// and `code: sqlstate` (exception when others). The instructor route maps them
// as /api/evaluations does, so raw database text never reaches the browser.
const instructor = '00000000-0000-4000-8000-0000000000a2';
const ok = '00000000-0000-4000-8000-0000000000c1';
const failed = '00000000-0000-4000-8000-0000000000c2';
const rawError = 'duplicate key value violates unique constraint "homework_submissions_pkey"';

test('instructor bulk homework replies carry mapped item errors, never raw SQL text', async () => {
  const bulk = { results: [
    { submission_id: ok, ok: true, changed: true, status: 'released' },
    { submission_id: failed, ok: false, error: rawError, code: '23505' },
  ] };
  await withFakeSupabase({ userId: instructor, role: 'instructor', rpc: { manage_homework: bulk } }, async () => {
    const { POST } = await import('../src/app/api/activities/homework/route');
    const response = await POST(bearerRequest('/api/activities/homework', {
      method: 'POST', body: JSON.stringify({ action: 'release', submission_ids: [ok, failed] }),
    }));
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.ok(!text.includes('duplicate key') && !text.includes('23505'), 'no raw database error or SQLSTATE in the reply');
    const { record } = JSON.parse(text);
    assert.deepEqual(record.results.map((row: { submission_id: string; ok: boolean }) => [row.submission_id, row.ok]), [[ok, true], [failed, false]]);
    assert.equal(record.results[0].status, 'released');
    assert.equal(record.results[1].error, 'This submission could not be updated.');
  });
});
