import fs from 'node:fs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921','Dedicated isolated QA required.');
const fixture=JSON.parse(fs.readFileSync('.tmp/quiz-preview-accounts.json','utf8'));
const options={auth:{persistSession:false,autoRefreshToken:false}};
const service=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,options);
const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,options);
async function ok(promise){const result=await promise;assert(!result.error,result.error?.message);return result.data;}
const signed=await ok(client.auth.signInWithPassword({email:fixture.accounts.instructor.email,password:fixture.accounts.instructor.password}));
const token=signed.session.access_token;
async function api(path,body){const response=await fetch(`http://127.0.0.1:3008/api/activities/${path}`,{method:'POST',headers:{Authorization:`Bearer ${token}`,...(body instanceof FormData?{}:{'Content-Type':'application/json'})},body:body instanceof FormData?body:JSON.stringify(body)});const result=await response.json();assert.equal(response.status,200,result.error);return result;}
let classroom=await ok(client.from('classes').select('*').eq('class_code','OWNER-ACTIVITIES-QA').eq('instructor_id',signed.user.id).maybeSingle());
if(!classroom) classroom=await ok(client.rpc('create_class',{p_title:'Owner Quiz & Homework QA',p_class_code:'OWNER-ACTIVITIES-QA'}));
assert.equal(classroom.status,'active','Do not reset an archived owner class.');
for(const name of ['learner','resumeLearner']){
 const account=fixture.accounts[name];
 const enrolled=await ok(client.from('class_memberships').select('id').eq('class_id',classroom.id).eq('learner_id',account.id).eq('status','active').maybeSingle());
 if(!enrolled)await ok(client.rpc('enroll_learner',{p_class_id:classroom.id,p_learner_id:account.id}));
}
const quizIds={};
for(const [key,title,kind] of [['open','Owner — One Attempt Quiz','open'],['expired','Owner — Reopen & Resume Quiz','expired'],['completed','Owner — Submitted Result Stays Locked','completed']]){
 let quiz=await ok(client.from('quizzes').select('id').eq('title',title).eq('instructor_id',signed.user.id).maybeSingle());
 if(!quiz){
  quiz=await ok(client.rpc('create_instructor_quiz',{p_title:title,p_topic:'Network review',p_instructions:'Answer the networking question and submit once.'}));
  const version=await ok(client.from('quiz_versions').select('id').eq('quiz_id',quiz.id).single());
  const item=await ok(client.rpc('upsert_quiz_item',{p_quiz_version_id:version.id,p_item_type:'true_false',p_prompt:'A router connects different IP networks.',p_options:[],p_correct_answer:'True',p_order_index:1}));
  await ok(client.rpc('review_quiz_item',{p_item_id:item.id,p_decision:'approved'}));
  await ok(client.rpc('publish_and_assign_quiz',{p_quiz_version_id:version.id,p_class_ids:[classroom.id]}));
  const assignment=await ok(client.from('quiz_assignments').select('id').eq('class_id',classroom.id).eq('quiz_version_id',version.id).single());
  if(kind!=='open'){
   const learner=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,options);
   const account=fixture.accounts[kind==='expired'?'resumeLearner':'learner'];
   await ok(learner.auth.signInWithPassword({email:account.email,password:account.password}));
   const attempt=await ok(learner.rpc('start_learner_quiz',{p_assignment_id:assignment.id,p_client_start_key:randomUUID()}));
   await ok(learner.rpc('save_learner_quiz_answer',{p_attempt_id:attempt.attempt_id,p_item_id:item.id,p_answer:'True'}));
   if(kind==='completed')await ok(learner.rpc('submit_learner_quiz',{p_attempt_id:attempt.attempt_id,p_submission_key:randomUUID()}));
   // Deliberately expired synthetic QA fixtures; no owner work is changed.
   await ok(service.from('quiz_assignments').update({due_at:new Date(Date.now()-60000).toISOString()}).eq('id',assignment.id));
  }
 }
 quizIds[key]=quiz.id;
}
const homeworkIds={};
for(const [key,title,deadline] of [
 ['future','Owner — Network Inspection Homework',new Date(Date.now()+86400000).toISOString()],
 ['late','Owner — Late Homework Allowed',new Date(Date.now()-(2*86400+3*3600)*1000).toISOString()],
 ['noDeadline','Owner — No Deadline Homework',null],
]){
 let h=await ok(service.from('homework_assignments').select('*').eq('class_id',classroom.id).eq('title',title).maybeSingle());
 if(!h){
  h=(await api('homework',{action:'create',class_id:classroom.id,title,instructions:'Complete this homework outside ByteQuest. Inspect a sample network, list the devices and connections, and describe one connectivity check. Return to enter a written report, upload a completed PDF/image/TXT file, or both. Your Instructor will review it. Late submissions are accepted.',deadline_at:deadline})).record;
  const content='ByteQuest QA homework instructions\n1. Inspect a sample network.\n2. Record devices and connections.\n3. Describe a connectivity check.\n4. Submit a report for Instructor review.\n';
  fs.writeFileSync('.tmp/homework-network-instructions.txt',content);
  const form=new FormData();form.set('file',new Blob([content],{type:'text/plain'}),'homework-network-instructions.txt');
  await api(`files?assignment=${h.id}`,form);
  await api('homework',{action:'publish',assignment_id:h.id});
 }
 homeworkIds[key]=h.id;
}
const metadata={classId:classroom.id,quizIds,homeworkIds,instructorUrl:`http://localhost:3008/classes/${classroom.id}?tab=assignments`,learnerUrl:'http://127.0.0.1:3009',quizUrl:'http://localhost:3008/quizzes'};
fs.writeFileSync('.tmp/activity-owner-setup.json',JSON.stringify(metadata,null,2));
fs.writeFileSync('.tmp/activity-owner-logins.txt',['Isolated QA only: http://localhost:3008 and http://127.0.0.1:3009','Backend: http://127.0.0.1:58921','',...['instructor','learner','resumeLearner'].flatMap(name=>[name,`Email: ${fixture.accounts[name].email}`,`Password: ${fixture.accounts[name].password}`,''])].join('\n'));
console.log(`PASS owner QA prepared without resetting existing state. Class: ${metadata.instructorUrl}`);
console.log('PASS 3 distinct quizzes, 3 homework assignments, private instruction files; existing accounts preserved. Private logins: .tmp/activity-owner-logins.txt');
