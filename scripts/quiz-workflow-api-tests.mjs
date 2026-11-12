import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
// Deliberately narrower than "any localhost": never mutate the owner's main stack.
if (url !== 'http://127.0.0.1:58921') throw new Error('Dedicated quiz QA API http://127.0.0.1:58921 required.');
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!key || !serviceKey) throw new Error('Local-only API keys are required.');
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(url, serviceKey, options);
const run = randomUUID().slice(0, 8);
const accounts = {};
const checks = [];
function pass(message) { checks.push(message); console.log(`PASS ${message}`); }
async function ok(request) { const result = await request; assert(!result.error, result.error?.message); return result.data; }
async function denied(request, code) { const result = await request; assert(result.error, 'Expected denial'); assert(result.error.message.includes(code), result.error.message); }
for (const [name, role] of [['instructor', 'instructor'], ['otherInstructor', 'instructor'], ['learner', 'learner'], ['resumeLearner', 'learner'], ['outsider', 'learner']]) {
  const email = `quiz.${name.toLowerCase()}.${run}@bytequest.invalid`;
  const password = randomBytes(24).toString('base64url') + 'Aa1!';
  const user = await ok(service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: `Quiz QA ${name}` } }));
  await ok(service.from('profiles').update({ role, status: 'active' }).eq('user_id', user.user.id));
  const client = createClient(url, key, options);
  const session = await ok(client.auth.signInWithPassword({ email, password }));
  accounts[name] = { email, password, id: user.user.id, client, session: session.session };
}
const teacher = accounts.instructor.client;
const learner = accounts.learner.client;
const resume = accounts.resumeLearner.client;
const a = await ok(teacher.rpc('create_class', { p_title: `Quiz QA A ${run}`, p_class_code: `QA-A-${run}` }));
const b = await ok(teacher.rpc('create_class', { p_title: `Quiz QA B ${run}`, p_class_code: `QA-B-${run}` }));
const foreign = await ok(accounts.otherInstructor.client.rpc('create_class', { p_title: `Private QA ${run}`, p_class_code: `QA-X-${run}` }));
for (const member of [accounts.learner, accounts.resumeLearner]) for (const cls of [a, b]) await ok(teacher.rpc('enroll_learner', { p_class_id: cls.id, p_learner_id: member.id }));
pass('authenticated instructor classes and multi-class enrollment');
const quiz = await ok(teacher.rpc('create_instructor_quiz', { p_title: `Workflow QA ${run}`, p_topic: 'Network testing', p_instructions: 'Answer all four questions.' }));
const version = await ok(teacher.from('quiz_versions').select('*').eq('quiz_id', quiz.id).single());
const questions = [];
for (const [type, prompt, choices, answer] of [
  ['multiple_choice', 'Which device routes network traffic?', ['Router', 'Switch'], 'Router'],
  ['true_false', 'A switch connects LAN devices.', [], 'true'],
  ['identification', 'Name the routing device.', [], 'Router'],
  ['scenario_based', 'Two IP networks need connectivity. Choose the routing device.', ['Router', 'Keyboard'], 'Router'],
]) questions.push(await ok(teacher.rpc('upsert_quiz_item', { p_quiz_version_id: version.id, p_item_type: type, p_prompt: prompt, p_options: choices, p_correct_answer: answer })));
pass('quiz creation and every supported question type');
await denied(teacher.rpc('publish_and_assign_quiz', { p_quiz_version_id: version.id, p_class_ids: [a.id] }), 'APPROVED_QUIZ_ITEM_REQUIRED');
await ok(teacher.rpc('reorder_quiz_items', { p_quiz_version_id: version.id, p_item_ids: questions.toReversed().map(item => item.id) }));
const order = await ok(teacher.from('quiz_items').select('id').eq('quiz_version_id', version.id).order('order_index'));
assert.deepEqual(order.map(item => item.id), questions.toReversed().map(item => item.id));
for (const item of questions) await ok(teacher.rpc('review_quiz_item', { p_item_id: item.id, p_decision: 'approved' }));
await denied(teacher.rpc('reorder_quiz_items', { p_quiz_version_id: version.id, p_item_ids: [questions[0].id, questions[0].id] }), 'QUIZ_ORDER_CHANGED');
await ok(teacher.rpc('upsert_quiz_item', { p_quiz_version_id: version.id, p_item_type: questions[0].item_type, p_prompt: questions[0].prompt + ' Review.', p_options: questions[0].options, p_correct_answer: questions[0].correct_answer, p_item_id: questions[0].id }));
await denied(teacher.rpc('publish_and_assign_quiz', { p_quiz_version_id: version.id, p_class_ids: [a.id] }), 'ALL_QUIZ_ITEMS_REQUIRE_APPROVAL');
await ok(teacher.rpc('review_quiz_item', { p_item_id: questions[0].id, p_decision: 'approved' }));
pass('reorder, editing invalidates approval, review remains mandatory');
await denied(teacher.rpc('publish_and_assign_quiz', { p_quiz_version_id: version.id, p_class_ids: [a.id, foreign.id] }), 'INSTRUCTOR_CLASS_SCOPE_REQUIRED');
assert.equal((await ok(teacher.from('quiz_versions').select('status').eq('id', version.id).single())).status, 'draft');
await Promise.all(Array.from({ length: 4 }, () => ok(teacher.rpc('publish_and_assign_quiz', { p_quiz_version_id: version.id, p_class_ids: [a.id, b.id] }))));
const assignments = await ok(teacher.from('quiz_assignments').select('*').eq('quiz_version_id', version.id));
assert.equal(assignments.length, 2);
pass('reason-free atomic publication, authorized classes, concurrent idempotent assignments');
const assignment = assignments.find(item => item.class_id === a.id);
await denied(accounts.outsider.client.rpc('start_learner_quiz', { p_assignment_id: assignment.id, p_client_start_key: randomUUID() }), 'QUIZ_NOT_AVAILABLE');
assert.deepEqual(await ok(learner.from('quiz_items').select('*')), []);
await denied(learner.rpc('publish_quiz_version', { p_quiz_version_id: version.id }), 'INSTRUCTOR_REQUIRED');
assert.deepEqual(await ok(accounts.otherInstructor.client.from('quizzes').select('*').eq('id', quiz.id)), []);
pass('learner and instructor authorization, class scope and private answer keys');
const starts = await Promise.all(Array.from({ length: 16 }, (_, index) => ok(learner.rpc('start_learner_quiz', { p_assignment_id: assignments[index % 2].id, p_client_start_key: randomUUID() }))));
assert.equal(new Set(starts.map(item => item.attempt_id)).size, 1);
const attemptId = starts[0].attempt_id;
assert(!JSON.stringify(starts).includes('correct_answer'));
await denied(learner.rpc('submit_learner_quiz', { p_attempt_id: attemptId, p_submission_key: randomUUID() }), 'ANSWER_EVERY_QUESTION');
for (const item of questions) await ok(learner.rpc('save_learner_quiz_answer', { p_attempt_id: attemptId, p_item_id: item.id, p_answer: item.item_type === 'identification' ? ' router ' : item.correct_answer }));
await ok(learner.auth.signOut());
const signedInAgain = await ok(learner.auth.signInWithPassword({ email: accounts.learner.email, password: accounts.learner.password }));
accounts.learner.session = signedInAgain.session;
const secondDevice = createClient(url, key, options);
await ok(secondDevice.auth.signInWithPassword({ email: accounts.learner.email, password: accounts.learner.password }));
const resumed = await ok(secondDevice.rpc('start_learner_quiz', { p_assignment_id: assignment.id, p_client_start_key: randomUUID() }));
assert.equal(resumed.attempt_id, attemptId); assert(resumed.questions.every(item => item.saved_answer));
pass('16 concurrent starts across classes create one attempt; relogin and second-device resume retain answers');
const results = await Promise.all(Array.from({ length: 12 }, () => ok(secondDevice.rpc('submit_learner_quiz', { p_attempt_id: attemptId, p_submission_key: randomUUID() }))));
assert(results.every(item => item.correct_count === 4));
assert.equal((await ok(service.from('quiz_results').select('id').eq('quiz_attempt_id', attemptId))).length, 1);
for (const target of assignments) await denied(secondDevice.rpc('start_learner_quiz', { p_assignment_id: target.id, p_client_start_key: randomUUID() }), 'QUIZ_ATTEMPT_ALREADY_SUBMITTED');
pass('12 concurrent submissions create one grade; one attempt enforced across classes');
const oldRun = await ok(resume.rpc('start_learner_quiz', { p_assignment_id: assignment.id, p_client_start_key: randomUUID() }));
await ok(resume.rpc('save_learner_quiz_answer', { p_attempt_id: oldRun.attempt_id, p_item_id: questions[0].id, p_answer: 'Router' }));
const next = await ok(teacher.rpc('create_quiz_version', { p_quiz_id: quiz.id, p_change_summary: 'Republication regression' }));
const nextItem = await ok(teacher.rpc('upsert_quiz_item', { p_quiz_version_id: next.id, p_item_type: 'true_false', p_prompt: 'A router connects different IP networks.', p_options: [], p_correct_answer: 'true' }));
await ok(teacher.rpc('review_quiz_item', { p_item_id: nextItem.id, p_decision: 'approved' }));
const nextAssigned = await ok(teacher.rpc('publish_and_assign_quiz', { p_quiz_version_id: next.id, p_class_ids: [a.id] }));
await denied(secondDevice.rpc('start_learner_quiz', { p_assignment_id: nextAssigned.assignments[0].id, p_client_start_key: randomUUID() }), 'QUIZ_ATTEMPT_ALREADY_SUBMITTED');
assert.equal((await ok(resume.rpc('start_learner_quiz', { p_assignment_id: nextAssigned.assignments[0].id, p_client_start_key: randomUUID() }))).attempt_id, oldRun.attempt_id);
const oldResult = await ok(secondDevice.rpc('get_learner_quiz_result', { p_attempt_id: attemptId }));
assert.equal(oldResult.correct_count, 4);
pass('republication grants no new attempt; retired in-progress version resumes and prior result survives');
await ok(service.from('class_memberships').update({ status: 'deactivated', deactivated_at: new Date().toISOString(), deactivated_by: accounts.instructor.id, deactivation_reason: 'Isolated quiz access regression' }).eq('class_id', a.id).eq('learner_id', accounts.resumeLearner.id));
await denied(resume.rpc('save_learner_quiz_answer', { p_attempt_id: oldRun.attempt_id, p_item_id: questions[0].id, p_answer: 'Switch' }), 'QUIZ_NOT_AVAILABLE');
await ok(service.from('class_memberships').update({ status: 'active' }).eq('class_id', a.id).eq('learner_id', accounts.resumeLearner.id));
pass('revoked enrollment blocks further answers without deleting the unfinished attempt');
const events = await ok(service.from('audit_events').select('reason,metadata').eq('action', 'quiz_version.published').eq('target_id', version.id));
assert.equal(events.length, 1); assert.equal(events[0].reason, null);
pass('publication audit retained exactly once with no invented reason');
if (process.env.BQ_QUIZ_QA_ACCOUNT_FILE) {
  const fs = await import('node:fs');
  const path = process.env.BQ_QUIZ_QA_ACCOUNT_FILE;
  if (!path.replaceAll('\\', '/').endsWith('/.tmp/quiz-preview-accounts.json')) throw new Error('Account output must be the ignored quiz-preview-accounts.json.');
  fs.writeFileSync(path, JSON.stringify({ accounts: Object.fromEntries(Object.entries(accounts).map(([name, value]) => [name, { email: value.email, password: value.password, id: value.id }])), quizId: quiz.id, classIds: [a.id, b.id] }, null, 2));
}
console.log(`${checks.length} authenticated API groups passed. Local QA fixtures retained for owner testing.`);
