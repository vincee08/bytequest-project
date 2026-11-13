import assert from 'node:assert/strict';
import fs from 'node:fs';
import { randomBytes, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL, 'http://127.0.0.1:58921', 'Dedicated QA backend required.');
const base = 'http://127.0.0.1:3008';
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, options);
const fixture = JSON.parse(fs.readFileSync('.tmp/quiz-preview-accounts.json','utf8'));
const run = randomUUID().slice(0,8);
const pass = message => console.log(`PASS ${message}`);
async function ok(promise) { const r = await promise; assert(!r.error, r.error?.message); return r.data; }
async function login(account) { const client = createClient(url,key,options); const data = await ok(client.auth.signInWithPassword(account)); return { client, id: data.user.id, token: data.session.access_token }; }
const teacher = await login({ email: fixture.accounts.instructor.email, password: fixture.accounts.instructor.password });
const foreign = await login({ email: fixture.accounts.otherInstructor.email, password: fixture.accounts.otherInstructor.password });
const learners = [];
for (let i=0;i<3;i++) {
  const account = { email: `activity.${run}.${i}@bytequest.invalid`, password: `${randomBytes(24).toString('base64url')}Aa1!` };
  await ok(service.auth.admin.createUser({ ...account, email_confirm: true, user_metadata: { full_name: `Activity QA ${run} Learner ${i+1}` } }));
  learners.push({ ...await login(account), ...account });
}
const [completed,resumable,unused] = learners;
async function api(actor, path, body, expected=200) {
  const response = await fetch(`${base}/api/activities/${path}`, { method: body ? 'POST' : 'GET', headers: { ...(actor ? { Authorization: `Bearer ${actor.token}` } : {}), ...(body && !(body instanceof FormData) ? { 'Content-Type':'application/json' } : {}) }, body: body instanceof FormData ? body : body ? JSON.stringify(body) : undefined });
  const result = await response.json(); assert.equal(response.status,expected,result.error ?? JSON.stringify(result)); return result;
}
const classA = await ok(teacher.client.rpc('create_class',{p_title:`Activities QA A ${run}`,p_class_code:`ACT-A-${run}`}));
const classB = await ok(teacher.client.rpc('create_class',{p_title:`Activities QA B ${run}`,p_class_code:`ACT-B-${run}`}));
for(const learner of learners) for(const classroom of [classA,classB]) await ok(teacher.client.rpc('enroll_learner',{p_class_id:classroom.id,p_learner_id:learner.id}));
const quiz = await ok(teacher.client.rpc('create_instructor_quiz',{p_title:`Activities quiz ${run}`,p_topic:'Networking'}));
const version = await ok(teacher.client.from('quiz_versions').select('*').eq('quiz_id',quiz.id).single());
const item = await ok(teacher.client.rpc('upsert_quiz_item',{p_quiz_version_id:version.id,p_item_type:'true_false',p_prompt:'A router connects IP networks.',p_options:[],p_correct_answer:'True',p_order_index:1}));
await ok(teacher.client.rpc('review_quiz_item',{p_item_id:item.id,p_decision:'approved'}));
await ok(teacher.client.rpc('publish_and_assign_quiz',{p_quiz_version_id:version.id,p_class_ids:[classA.id,classB.id]}));
const assignments = await ok(teacher.client.from('quiz_assignments').select('*').eq('quiz_version_id',version.id));
const a = assignments.find(a=>a.class_id===classA.id); const b = assignments.find(a=>a.class_id===classB.id);
assert.equal((await ok(teacher.client.from('homework_assignments').select('id').eq('class_id',classA.id))).length,0);
const listed = await ok(completed.client.rpc('get_available_learner_quizzes'));
const summary = listed.find(q=>q.quiz_id===quiz.id); assert(summary?.is_available); assert.equal(summary.quiz_version_id,version.id);
assert(!JSON.stringify(summary).match(/ai_generated|provider|origin|correct_answer/i));
pass('same QA backend, active membership, published quiz visibility, no AI label, no automatic homework');
const starts = await Promise.all(Array.from({length:12},(_,i)=>ok(completed.client.rpc('start_learner_quiz',{p_assignment_id:i%2?a.id:b.id,p_client_start_key:randomUUID()}))));
assert.equal(new Set(starts.map(s=>s.attempt_id)).size,1);
const first = starts[0];
await ok(completed.client.rpc('save_learner_quiz_answer',{p_attempt_id:first.attempt_id,p_item_id:item.id,p_answer:'True'}));
await Promise.all(Array.from({length:8},()=>ok(completed.client.rpc('submit_learner_quiz',{p_attempt_id:first.attempt_id,p_submission_key:randomUUID()}))));
assert.equal((await ok(service.from('quiz_results').select('id').eq('quiz_attempt_id',first.attempt_id))).length,1);
const resumeAttempt = await ok(resumable.client.rpc('start_learner_quiz',{p_assignment_id:a.id,p_client_start_key:randomUUID()}));
await ok(resumable.client.rpc('save_learner_quiz_answer',{p_attempt_id:resumeAttempt.attempt_id,p_item_id:item.id,p_answer:'True'}));
await api(teacher,'quiz-deadline',{assignment_id:a.id,deadline_at:new Date(Date.now()+86400000).toISOString(),reopen:false});
// Dedicated QA fixture transition; boundary equality is tested separately with
// a transaction-local controlled PostgreSQL clock, never a client override.
await ok(service.from('quiz_assignments').update({due_at:new Date(Date.now()-1000).toISOString()}).eq('id',a.id));
for(const request of [unused.client.rpc('start_learner_quiz',{p_assignment_id:a.id,p_client_start_key:randomUUID()}),resumable.client.rpc('save_learner_quiz_answer',{p_attempt_id:resumeAttempt.attempt_id,p_item_id:item.id,p_answer:'False'}),resumable.client.rpc('submit_learner_quiz',{p_attempt_id:resumeAttempt.attempt_id,p_submission_key:randomUUID()})]) {
  const result = await request; assert(result.error?.message.includes('QUIZ_NOT_AVAILABLE'));
}
const expired = (await ok(resumable.client.rpc('get_available_learner_quizzes'))).find(q=>q.quiz_id===quiz.id);
assert.equal(expired.closed_reason,'deadline_passed'); assert.equal(expired.is_available,false);
assert.equal((await ok(service.from('quiz_attempts').select('status').eq('id',resumeAttempt.attempt_id).single())).status,'in_progress');
assert.equal((await ok(service.from('quiz_results').select('id').eq('quiz_attempt_id',resumeAttempt.attempt_id))).length,0);
pass('deadline closes starts, answer writes and submissions; saved unfinished history retained without fabricated result');
await api(foreign,'quiz-deadline',{assignment_id:a.id,deadline_at:new Date(Date.now()+172800000).toISOString(),reopen:true},403);
await api(teacher,'quiz-deadline',{assignment_id:a.id,deadline_at:null,reopen:true},422);
await api(teacher,'quiz-deadline',{assignment_id:a.id,deadline_at:new Date(Date.now()+172800000).toISOString(),reopen:true});
assert.equal((await ok(service.from('quiz_assignments').select('due_at').eq('id',b.id).single())).due_at,null);
assert((await unused.client.rpc('start_learner_quiz',{p_assignment_id:a.id,p_client_start_key:randomUUID()})).data);
assert((await completed.client.rpc('start_learner_quiz',{p_assignment_id:a.id,p_client_start_key:randomUUID()})).error?.message.includes('ALREADY_SUBMITTED'));
const resumed = await ok(resumable.client.rpc('start_learner_quiz',{p_assignment_id:a.id,p_client_start_key:randomUUID()}));
assert.equal(resumed.attempt_id,resumeAttempt.attempt_id); assert.equal(resumed.questions[0].saved_answer,'True');
assert.equal((await ok(service.from('audit_events').select('id').eq('target_id',a.id).eq('action','quiz.reopened'))).length,1);
pass('authorized reason-free class-specific reopening, first attempt available, completed locked, original unfinished attempt resumed, audit persisted');
async function createHomework(deadline) { return (await api(teacher,'homework',{action:'create',class_id:classA.id,title:`Homework ${run}`,instructions:'Inspect the home network and submit a written report or a file.',deadline_at:deadline})).record; }
const h = await createHomework(null);
await api(resumable,`homework?id=${h.id}`,null,404);
await api(foreign,'homework',{action:'publish',assignment_id:h.id},403);
await api(teacher,'homework',{action:'edit',assignment_id:h.id,title:`Homework edited ${run}`,instructions:'Write the network inspection report and attach supporting evidence.',deadline_at:null});
async function upload(actor, homework, filename, content, type='text/plain', expected=200) { const form = new FormData(); form.set('file',new Blob([content],{type}),filename); return api(actor,`files?assignment=${homework}`,form,expected); }
const instruction = (await upload(teacher,h.id,'instructions.txt','Inspect cables and write the observed network topology.')).file;
await api(teacher,'homework',{action:'publish',assignment_id:h.id});
await api(teacher,'homework',{action:'edit',assignment_id:h.id,title:'Forbidden edit',instructions:'Changed',deadline_at:null},409);
const detail = await api(resumable,`homework?id=${h.id}`);
assert.equal(detail.files[0].id,instruction.id); assert.equal(detail.homework[0].status,'published');
await api(resumable,`files?id=${instruction.id}`);
await api(foreign,`files?id=${instruction.id}`,null,404);
await api(resumable,'homework',{action:'grade',assignment_id:h.id,submission_id:randomUUID(),feedback:'',score:null},403);
const direct = await resumable.client.rpc('manage_homework',{p_actor:teacher.id,p_action:'publish',p_payload:{assignment_id:h.id}}); assert(direct.error);
await api(null,'homework',null,401);
pass('homework draft/edit/publication, learner discoverability, private instructions, role and direct-RPC authorization');
await upload(resumable,h.id,'fake.pdf','not a PDF','application/pdf',415);
const uploaded = await Promise.all(Array.from({length:4},()=>upload(resumable,h.id,'report.txt','Observed: all cables are secured.')));
assert.equal(new Set(uploaded.map(r=>r.file.id)).size,1);
const file = uploaded[0].file;
await api(unused,`files?id=${file.id}`,null,404);
const path = (await ok(service.from('homework_files').select('object_path').eq('id',file.id).single())).object_path;
assert((await unused.client.storage.from('homework-files').createSignedUrl(path,60)).error);
assert((await resumable.client.storage.from('homework-files').upload(`${h.id}/forbidden.txt`,'forbidden',{contentType:'text/plain'})).error);
const publicRead = await fetch(`${url}/storage/v1/object/public/homework-files/${path}`); assert.notEqual(publicRead.status,200);
await api(unused,'homework',{action:'submit',assignment_id:h.id,answer:'',file_ids:[file.id]},422);
const submissions = await Promise.all(Array.from({length:10},()=>api(resumable,'homework',{action:'submit',assignment_id:h.id,answer:'The inspection report is attached.',file_ids:[file.id]})));
assert.equal(new Set(submissions.map(r=>r.record.id)).size,1); assert.equal(submissions[0].record.lateness_seconds,0); assert.equal(submissions[0].record.effective_deadline_at,null);
const downloadLink=await api(resumable,`files?id=${file.id}`); await api(teacher,`files?id=${file.id}`);
const downloaded=await fetch(downloadLink.url);assert.equal(downloaded.status,200);assert.match(await downloaded.text(),/all cables are secured/);
assert.equal((await api(resumable,`homework?id=${h.id}`)).submissions[0].status,'submitted');
pass('safe file validation, private Storage and signed links, no cross-learner access, concurrent uploads/submissions produce one persisted submission');
const lateDeadline = new Date(Date.now() - (2*86400 + 6*3600 + 15*60)*1000).toISOString();
const late = await createHomework(lateDeadline); await api(teacher,'homework',{action:'publish',assignment_id:late.id});
const lateSubmission = (await api(unused,'homework',{action:'submit',assignment_id:late.id,answer:'Late network report.',file_ids:[]})).record;
assert(lateSubmission.lateness_seconds >= 195300 && lateSubmission.lateness_seconds < 195360);
const lateness = lateSubmission.lateness_seconds;
await api(teacher,'homework',{action:'deadline',assignment_id:late.id,deadline_at:new Date(Date.now()+86400000).toISOString()});
const stored = (await api(unused,`homework?id=${late.id}`)).submissions[0];
assert.equal(stored.lateness_seconds,lateness); assert.equal(stored.effective_deadline_at,lateSubmission.effective_deadline_at);
const grades = await Promise.all(Array.from({length:8},()=>api(teacher,'homework',{action:'grade',assignment_id:late.id,submission_id:lateSubmission.id,feedback:'Reviewed; late submission accepted.',score:null})));
assert(grades.every(g=>g.record.status==='graded')); assert(grades.every(g=>g.record.score===null));
assert.equal((await api(unused,`homework?id=${late.id}`)).submissions[0].status,'graded');
assert.equal((await ok(service.from('audit_events').select('id').eq('action','homework.graded').eq('target_id',lateSubmission.id))).length,1);
const onTime = await createHomework(new Date(Date.now()+86400000).toISOString()); await api(teacher,'homework',{action:'publish',assignment_id:onTime.id});
const onTimeRecord = (await api(completed,'homework',{action:'submit',assignment_id:onTime.id,answer:'On-time report.',file_ids:[]})).record; assert.equal(onTimeRecord.lateness_seconds,0);
await api(completed,'homework',{action:'submit',assignment_id:onTime.id,answer:'Forged date',file_ids:[],submitted_at:'2000-01-01T00:00:00Z'},400);
await api(completed,'homework',{action:'submit',assignment_id:onTime.id,answer:'Forged grade',file_ids:[],status:'graded'},400);
const fileOnly=await createHomework(null);await api(teacher,'homework',{action:'publish',assignment_id:fileOnly.id});
const fileOnlyAttachment=(await upload(resumable,fileOnly.id,'file-only.txt','Completed file-only network report.')).file;
const fileOnlySubmission=(await api(resumable,'homework',{action:'submit',assignment_id:fileOnly.id,answer:'',file_ids:[fileOnlyAttachment.id]})).record;
assert.equal(fileOnlySubmission.answer,'');assert.equal(fileOnlySubmission.lateness_seconds,0);
const scored=(await api(teacher,'homework',{action:'grade',assignment_id:fileOnly.id,submission_id:fileOnlySubmission.id,feedback:'File-only report reviewed.',score:85})).record;assert.equal(scored.score,85);
pass('no-deadline/future homework, late acceptance and exact duration, immutable deadline snapshot, optional-score grading, duplicate grading audit protection, learner Graded status');
const cors = await fetch(`${base}/api/activities/homework`,{method:'OPTIONS',headers:{Origin:'http://127.0.0.1:3009','Access-Control-Request-Headers':'authorization'}}); assert.equal(cors.status,204); assert.equal(cors.headers.get('access-control-allow-origin'),'http://127.0.0.1:3009');
const evil = await fetch(`${base}/api/activities/homework`,{method:'POST',headers:{Origin:'https://untrusted.invalid',Authorization:`Bearer ${teacher.token}`,'Content-Type':'application/json'},body:JSON.stringify({action:'publish',assignment_id:h.id})}); assert.equal(evil.status,403);
pass('local learner preview CORS and cross-origin write rejection');
fs.writeFileSync('.tmp/activity-api-test-fixture.json',JSON.stringify({run,classA:classA.id,classB:classB.id,quiz:quiz.id,homework:h.id,late:late.id}));
fs.writeFileSync('.tmp/activity-browser-accounts.json',JSON.stringify(learners.map(({email,password,id})=>({email,password,id}))));
console.log('PASS all 7 activity API/Storage integration groups. Synthetic QA history retained; owner account file unchanged.');
