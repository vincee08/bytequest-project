// Additive owner UAT fixtures. Never submit/reset the owner's existing work.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921');
const options={auth:{persistSession:false,autoRefreshToken:false}};
const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,options);
const accounts=JSON.parse(fs.readFileSync('.tmp/quiz-preview-accounts.json','utf8')).accounts;
const owner=JSON.parse(fs.readFileSync('.tmp/activity-owner-setup.json','utf8'));
async function ok(p){const r=await p;assert(!r.error,r.error?.message);return r.data;}
const signed=await ok(client.auth.signInWithPassword({email:accounts.instructor.email,password:accounts.instructor.password}));
const classroom=await ok(client.from('classes').select('*').eq('class_code','OWNER-ACTIVITIES-QA').eq('instructor_id',signed.user.id).single());
assert.equal(classroom.status,'active');
async function api(body){const r=await fetch('http://127.0.0.1:3008/api/activities/homework',{method:'POST',headers:{Authorization:`Bearer ${signed.session.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(body)});const result=await r.json();assert.equal(r.status,200,result.error);return result.record;}
let quiz=await ok(client.from('quizzes').select('id').eq('title','Owner — Notification Quiz').eq('instructor_id',signed.user.id).maybeSingle());
if(!quiz){
 quiz=await ok(client.rpc('create_instructor_quiz',{p_title:'Owner — Notification Quiz',p_topic:'Network review',p_instructions:'Open this quiz through the notification bell. Start only when ready to use your one attempt.'}));
 const v=await ok(client.from('quiz_versions').select('id').eq('quiz_id',quiz.id).single());
 const item=await ok(client.rpc('upsert_quiz_item',{p_quiz_version_id:v.id,p_item_type:'true_false',p_prompt:'A router connects different IP networks.',p_options:[],p_correct_answer:'True',p_order_index:1}));
 await ok(client.rpc('review_quiz_item',{p_item_id:item.id,p_decision:'approved'}));
 await ok(client.rpc('publish_and_assign_quiz',{p_quiz_version_id:v.id,p_class_ids:[classroom.id],p_due_at:new Date(Date.now()+7*86400000).toISOString()}));
}
let homework=await ok(client.from('homework_assignments').select('id').eq('class_id',classroom.id).eq('title','Owner — Notification Homework').maybeSingle());
if(!homework){
 homework=await api({action:'create',class_id:classroom.id,title:'Owner — Notification Homework',instructions:'Inspect your network outside ByteQuest. Return here to submit a written answer, a TXT/PDF/image file, or both. After grading, check the notification bell again.',deadline_at:new Date(Date.now()+7*86400000).toISOString()});
 await api({action:'publish',assignment_id:homework.id});
}
let technical=await ok(client.from('assignments').select('id').eq('class_id',classroom.id).eq('title','Owner — Technical Notification QA').maybeSingle());
if(!technical){
 const source=await ok(client.from('tesda_sources').select('id').eq('qualification_code','BQ-NOTIFICATION-QA-ONLY').single());
 const module=await ok(client.from('module_versions').select('id').eq('tesda_source_id',source.id).single());
 const version=await ok(client.from('activity_versions').select('id').eq('module_version_id',module.id).single());
 technical=await ok(client.rpc('assign_activity',{p_class_id:classroom.id,p_activity_version_id:version.id,p_rubric_version_id:null,p_assignment_type:'practice',p_title:'Owner — Technical Notification QA',p_instructions:'Synthetic QA practice assignment for testing the notification and task review link. It is not an official COC assessment.'}));
}
fs.writeFileSync('.tmp/notification-owner-setup.json',JSON.stringify({classId:classroom.id,quizId:quiz.id,homeworkId:homework.id,technicalId:technical.id}));
console.log(`PASS additive owner notification fixtures ready in class ${classroom.id}; existing attempts, submissions and read states preserved. Existing logins: .tmp/activity-owner-logins.txt`);
