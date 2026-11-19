import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  curriculumError, learnerActionSchema, revisionActions, staffActionSchema,
} from '../src/lib/curriculum/workflow';
import {
  handleLearnerCurriculumGet, handleLearnerCurriculumPost, handleStaffCurriculumPost, type CurriculumRpc,
} from '../src/lib/curriculum/handlers';
import { parseInline, parseMarkdown } from '../src/lib/curriculum/markdown';

const id = '6f1d8b7e-2a7c-4d5e-9f10-1c2b3a4d5e6f';
const other = '0b7c1a2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d';

function recordingRpc(result: { data?: unknown; error?: { code?: string; message?: string } | null } = {}) {
  const calls: { action: string; payload: Record<string, unknown> }[] = [];
  const rpc: CurriculumRpc = async (action, payload) => {
    calls.push({ action, payload });
    return { data: result.data ?? { ok: true }, error: result.error ?? null };
  };
  return { rpc, calls };
}

test('staff request schema accepts every workflow action and rejects unknown fields', () => {
  const valid = [
    { action: 'create_topic', module_id: id, title: 'ESD precautions', summary: '', body_markdown: '# ESD', outcome_ids: [other] },
    { action: 'edit_revision', revision_id: id, title: 'Updated title' },
    { action: 'edit_revision', revision_id: id, summary: null },
    { action: 'submit', revision_id: id },
    { action: 'evaluate', revision_id: id, result: 'needs_revision', notes: 'Add the grounding step.' },
    { action: 'finalize', revision_id: id },
    { action: 'approve', revision_id: id },
    { action: 'publish', revision_id: id },
    { action: 'unpublish', revision_id: id, note: 'Superseded by the new lesson' },
    { action: 'archive_topic', topic_id: id },
  ];
  for (const input of valid) assert.equal(staffActionSchema.safeParse(input).success, true, JSON.stringify(input));
  assert.equal(staffActionSchema.safeParse({ action: 'publish', revision_id: id, status: 'published' }).success, false);
  assert.equal(staffActionSchema.safeParse({ action: 'publish', revision_id: 'not-a-uuid' }).success, false);
  assert.equal(staffActionSchema.safeParse({ action: 'create_topic', module_id: id, title: 'x' }).success, false);
  assert.equal(staffActionSchema.safeParse({ action: 'evaluate', revision_id: id, result: 'passed', notes: 'ok' }).success, false);
  assert.equal(staffActionSchema.safeParse({ action: 'evaluate', revision_id: id, result: 'approved', notes: 'Looks fine to me.' }).success, false);
  assert.equal(staffActionSchema.safeParse({ action: 'delete_topic', topic_id: id }).success, false);
  assert.equal(staffActionSchema.safeParse({ action: 'create_topic', module_id: id, title: 'Long body', body_markdown: 'x'.repeat(60001) }).success, false);
});

test('learner request schema only accepts topic completion', () => {
  assert.equal(learnerActionSchema.safeParse({ action: 'complete_topic', topic_id: id }).success, true);
  assert.equal(learnerActionSchema.safeParse({ action: 'complete_topic', topic_id: id, learner_id: other }).success, false);
  assert.equal(learnerActionSchema.safeParse({ action: 'publish', revision_id: id }).success, false);
});

test('workflow controls follow the role and stage table', () => {
  const topic = { created_by: 'author', archived_at: null };
  const actions = (role: 'admin' | 'instructor', actorId: string, status: Parameters<typeof revisionActions>[0]['revision']['status'], inProgress = false) =>
    revisionActions({ role, actorId, revision: { status, author_id: 'author' }, topic, otherRevisionInProgress: inProgress });
  assert.deepEqual(actions('instructor', 'author', 'draft'), ['edit', 'submit']);
  assert.deepEqual(actions('instructor', 'someone', 'draft'), []);
  assert.deepEqual(actions('admin', 'admin', 'draft'), ['edit']);
  assert.deepEqual(actions('instructor', 'author', 'submitted'), []);
  assert.deepEqual(actions('admin', 'admin', 'submitted'), ['evaluate']);
  assert.deepEqual(actions('instructor', 'author', 'needs_revision'), ['edit', 'submit']);
  assert.deepEqual(actions('instructor', 'author', 'evaluated'), ['finalize']);
  assert.deepEqual(actions('admin', 'admin', 'evaluated'), ['finalize']);
  assert.deepEqual(actions('instructor', 'author', 'finalized'), []);
  assert.deepEqual(actions('admin', 'admin', 'finalized'), ['approve']);
  assert.deepEqual(actions('instructor', 'author', 'approved'), []);
  assert.deepEqual(actions('admin', 'admin', 'approved'), ['publish']);
  assert.deepEqual(actions('admin', 'admin', 'published'), ['unpublish', 'new_revision']);
  assert.deepEqual(actions('instructor', 'author', 'published'), ['new_revision']);
  assert.deepEqual(actions('instructor', 'author', 'published', true), []);
  assert.deepEqual(actions('admin', 'admin', 'unpublished'), ['publish', 'new_revision']);
  assert.deepEqual(revisionActions({ role: 'admin', actorId: 'admin', revision: { status: 'published', author_id: 'author' },
    topic: { created_by: 'author', archived_at: '2026-11-19T00:00:00Z' }, otherRevisionInProgress: false }), []);
});

test('database workflow errors map to specific messages and statuses', () => {
  assert.deepEqual(curriculumError({ code: '42501', message: 'MODULE_LOCKED' }).status, 403);
  assert.match(curriculumError({ code: '42501', message: 'MODULE_LOCKED' }).error, /previous module/);
  assert.equal(curriculumError({ code: '55000', message: 'TRANSITION_NOT_ALLOWED' }).status, 409);
  assert.equal(curriculumError({ code: '55000', message: 'REVISION_IN_PROGRESS' }).status, 409);
  assert.equal(curriculumError({ code: '22023', message: 'EVALUATION_NOTES_REQUIRED' }).status, 422);
  assert.equal(curriculumError({ code: '42501', message: 'ADMIN_REQUIRED' }).status, 403);
  assert.equal(curriculumError({ code: 'P0002', message: 'REVISION_NOT_FOUND' }).status, 404);
  assert.equal(curriculumError({ code: 'XX000', message: 'connection reset' }).status, 503);
  for (const sample of ['MODULE_LOCKED', 'TRANSITION_NOT_ALLOWED', 'connection reset']) {
    const { error } = curriculumError({ message: sample });
    assert.doesNotMatch(error, /wrong|correct/i);
    assert.doesNotMatch(error, /MODULE_LOCKED|TRANSITION/);
  }
});

test('staff handler authenticates, validates and blocks admin-only actions before the database', async () => {
  const { rpc, calls } = recordingRpc();
  assert.equal((await handleStaffCurriculumPost(null, '{}', rpc)).status, 401);
  assert.equal((await handleStaffCurriculumPost({ role: 'learner' }, JSON.stringify({ action: 'submit', revision_id: id }), rpc)).status, 403);
  assert.equal((await handleStaffCurriculumPost({ role: 'instructor' }, '{bad json', rpc)).status, 400);
  assert.equal((await handleStaffCurriculumPost({ role: 'instructor' }, 'x'.repeat(100_001), rpc)).status, 413);
  const invalid = await handleStaffCurriculumPost({ role: 'admin' }, JSON.stringify({ action: 'evaluate', revision_id: id, result: 'passed', notes: 'ok' }), rpc);
  assert.equal(invalid.status, 400);
  assert.match(String(invalid.body.error), /10 characters/);
  for (const action of ['evaluate', 'approve', 'publish', 'unpublish']) {
    const body = action === 'evaluate' ? { action, revision_id: id, result: 'passed', notes: 'Accurate and complete.' } : { action, revision_id: id };
    assert.equal((await handleStaffCurriculumPost({ role: 'instructor' }, JSON.stringify(body), rpc)).status, 403, action);
  }
  assert.equal((await handleStaffCurriculumPost({ role: 'instructor' }, JSON.stringify({ action: 'archive_topic', topic_id: id }), rpc)).status, 403);
  assert.equal(calls.length, 0, 'nothing reached the database');

  const created = await handleStaffCurriculumPost({ role: 'instructor' }, JSON.stringify({ action: 'create_topic', module_id: id, title: '  ESD precautions  ' }), rpc);
  assert.equal(created.status, 200);
  assert.deepEqual(calls, [{ action: 'create_topic', payload: { module_id: id, title: 'ESD precautions' } }]);
  const published = await handleStaffCurriculumPost({ role: 'admin' }, JSON.stringify({ action: 'publish', revision_id: id }), rpc);
  assert.equal(published.status, 200);
  assert.deepEqual(calls[1], { action: 'publish', payload: { revision_id: id } });
});

test('staff handler surfaces database workflow refusals', async () => {
  const { rpc } = recordingRpc({ error: { code: '55000', message: 'TRANSITION_NOT_ALLOWED' } });
  const result = await handleStaffCurriculumPost({ role: 'admin' }, JSON.stringify({ action: 'publish', revision_id: id }), rpc);
  assert.equal(result.status, 409);
  assert.match(String(result.body.error), /current status/);
});

test('learner handler completes a topic and returns the refreshed projection', async () => {
  const { rpc, calls } = recordingRpc({ data: { already_completed: false } });
  const projection = async () => ({ data: { cocs: [] }, error: null });
  assert.equal((await handleLearnerCurriculumPost(null, '{}', { rpc, projection })).status, 401);
  assert.equal((await handleLearnerCurriculumPost({ role: 'instructor' }, JSON.stringify({ action: 'complete_topic', topic_id: id }), { rpc, projection })).status, 403);
  assert.equal((await handleLearnerCurriculumPost({ role: 'learner' }, JSON.stringify({ action: 'complete_topic', topic_id: 'x' }), { rpc, projection })).status, 400);
  assert.equal(calls.length, 0);
  const done = await handleLearnerCurriculumPost({ role: 'learner' }, JSON.stringify({ action: 'complete_topic', topic_id: id }), { rpc, projection });
  assert.equal(done.status, 200);
  assert.deepEqual(calls, [{ action: 'complete_topic', payload: { topic_id: id } }]);
  assert.deepEqual(done.body, { record: { already_completed: false }, curriculum: { cocs: [] } });

  const locked = recordingRpc({ error: { code: '42501', message: 'MODULE_LOCKED' } });
  const refused = await handleLearnerCurriculumPost({ role: 'learner' }, JSON.stringify({ action: 'complete_topic', topic_id: id }), { rpc: locked.rpc, projection });
  assert.equal(refused.status, 403);
});

test('learner projection handler is learner-only and hides database detail', async () => {
  assert.equal((await handleLearnerCurriculumGet({ role: 'admin' }, async () => ({ data: null, error: null }))).status, 403);
  const ok = await handleLearnerCurriculumGet({ role: 'learner' }, async () => ({ data: { cocs: [1] }, error: null }));
  assert.deepEqual(ok, { status: 200, body: { curriculum: { cocs: [1] } } });
  const failed = await handleLearnerCurriculumGet({ role: 'learner' }, async () => ({ data: null, error: { code: 'XX000', message: 'relation does not exist' } }));
  assert.equal(failed.status, 503);
  assert.doesNotMatch(String(failed.body.error), /relation/);
});

test('lesson Markdown renders as structured blocks and never as HTML', () => {
  const blocks = parseMarkdown('# ESD\n\nWear the **wrist strap** and use the `mat`.\n\n- Ground the strap\n- Check the *mat*\n\n1. Power off\n2. Unplug\n\n> Never work on a live PSU.\n\n```\nipconfig /all\n```\n\n<script>alert(1)</script>');
  assert.deepEqual(blocks.map((block) => block.type), ['heading', 'paragraph', 'list', 'list', 'quote', 'code', 'paragraph']);
  assert.deepEqual(blocks[1], { type: 'paragraph', inlines: [
    { kind: 'text', text: 'Wear the ' }, { kind: 'strong', text: 'wrist strap' }, { kind: 'text', text: ' and use the ' },
    { kind: 'code', text: 'mat' }, { kind: 'text', text: '.' }] });
  assert.equal(blocks[2].type === 'list' && !blocks[2].ordered && blocks[2].items.length, 2);
  assert.equal(blocks[3].type === 'list' && blocks[3].ordered, true);
  assert.deepEqual(blocks[6], { type: 'paragraph', inlines: [{ kind: 'text', text: '<script>alert(1)</script>' }] });
  assert.deepEqual(parseInline('See [TR](https://tesda.gov.ph)'), [{ kind: 'text', text: 'See ' }, { kind: 'text', text: 'TR (https://tesda.gov.ph)' }]);
});
