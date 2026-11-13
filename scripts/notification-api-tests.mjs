// Run after activity-tests. Reuses its NEW synthetic fixtures, never owner work.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921');
const url=process.env.NEXT_PUBLIC_SUPABASE_URL, key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const options={auth:{persistSession:false,autoRefreshToken:false}};
const service=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,options);
const accounts=JSON.parse(fs.readFileSync('.tmp/quiz-preview-accounts.json','utf8')).accounts;
const fixture=JSON.parse(fs.readFileSync('.tmp/activity-api-test-fixture.json','utf8'));
const learners=JSON.parse(fs.readFileSync('.tmp/activity-browser-accounts.json','utf8'));
async function ok(p){const r=await p;assert(!r.error,r.error?.message);return r.data;}
async function login(a){const c=createClient(url,key,options);await ok(c.auth.signInWithPassword({email:a.email,password:a.password}));return c;}
const [teacher,learner,other,outsider]=await Promise.all([login(accounts.instructor),login(learners[2]),login(learners[1]),login(accounts.outside ?? accounts.outsider)]);
const rows=await ok(learner.from('notifications').select('*'));
for(const event of ['quiz.assigned','homework.publish','homework.graded','quiz.reopened','homework.deadline']) assert(rows.some(n=>n.metadata.event_type===event),`missing ${event}`);
assert(rows.every(n=>n.user_id===learners[2].id));
const graded=rows.find(n=>n.metadata.event_type==='homework.graded'&&n.metadata.activity_id===fixture.late);assert(graded);
assert(!(await ok(other.from('notifications').select('*'))).some(n=>n.event_key===graded.event_key));
assert(!(await ok(outsider.from('notifications').select('*'))).some(n=>n.metadata.class_id===fixture.classA));
console.log('PASS quiz/homework/grading/reopen/deadline event delivery, exact recipient and unrelated-class RLS');
const assignment=(await ok(teacher.from('quiz_assignments').select('*').eq('class_id',fixture.classA))).find(a=>rows.some(n=>n.metadata.activity_id===a.id));assert(assignment);
const summary=(await ok(learner.rpc('get_available_learner_quizzes'))).find(q=>q.eligible_assignments.some(a=>a.assignment_id===assignment.id));
assert(summary?.eligible_assignments.some(a=>a.class_id===fixture.classB),'canonical quiz must carry both eligible class references');
const initial=(await ok(service.from('notifications').select('id').eq('event_key',`quiz.assigned:${assignment.id}`))).length;
await Promise.all(Array.from({length:8},()=>ok(teacher.rpc('assign_published_quiz',{p_class_id:fixture.classA,p_quiz_version_id:assignment.quiz_version_id}))));
assert.equal((await ok(service.from('notifications').select('id').eq('event_key',`quiz.assigned:${assignment.id}`))).length,initial);
assert((await learner.from('notifications').insert({user_id:learners[2].id,title:'Spoof',message:'Not permitted'})).error);
assert((await learner.from('notifications').update({metadata:{activity_id:fixture.homework}}).eq('id',graded.id)).error);
console.log('PASS concurrent assignment retries do not duplicate delivery; notification content cannot be forged');
await ok(learner.from('notifications').update({is_read:true,read_at:'1900-01-01'}).eq('id',graded.id));
let persisted=await ok(learner.from('notifications').select('*').eq('id',graded.id).single());assert(persisted.is_read&&Date.parse(persisted.read_at)>Date.parse('2026-01-01'));
const stamp=persisted.read_at;await ok(learner.from('notifications').update({is_read:true}).eq('id',graded.id));
const relogged=await login(learners[2]);persisted=await ok(relogged.from('notifications').select('*').eq('id',graded.id).single());assert.equal(persisted.read_at,stamp);
const otherUnread=(await ok(other.from('notifications').select('id').eq('is_read',false))).length;
await ok(relogged.from('notifications').update({is_read:true}).eq('is_read',false));
assert.equal((await ok(relogged.from('notifications').select('id').eq('is_read',false))).length,0);
assert.equal((await ok(other.from('notifications').select('id').eq('is_read',false))).length,otherUnread);
console.log('PASS authoritative read timestamp, relogin persistence and own-only mark-all');
// Dedicated synthetic practice content. It never changes an official source,
// mission definition, rubric, released result or existing published version.
let source=await ok(service.from('tesda_sources').select('id,created_by').eq('qualification_code','BQ-NOTIFICATION-QA-ONLY').maybeSingle());
if(!source) {
  const actor=await ok(service.auth.admin.createUser({email:`notification-admin.${fixture.run}@bytequest.invalid`,password:`${randomBytes(24).toString('base64url')}Aa1!`,email_confirm:true,user_metadata:{full_name:'Synthetic notification QA admin'}}));
  await ok(service.from('profiles').update({role:'admin'}).eq('user_id',actor.user.id));
  const at=new Date().toISOString();
  source=await ok(service.from('tesda_sources').insert({qualification_code:'BQ-NOTIFICATION-QA-ONLY',title:'Synthetic local notification QA source',source_reference:'QA ONLY: no official competency/scoring authority',status:'active',created_by:actor.user.id,approved_by:actor.user.id,approved_at:at,activated_by:actor.user.id,activated_at:at,validation_notes:'SYNTHETIC_QA_ONLY'}).select().single());
  const mission=await ok(service.from('missions').select('id,coc_id').order('mission_code').limit(1).single());
  const mv=await ok(service.from('module_versions').select('version_number').eq('module_id',mission.coc_id).order('version_number',{ascending:false}).limit(1));
  const module=await ok(service.from('module_versions').insert({module_id:mission.coc_id,tesda_source_id:source.id,version_number:(mv[0]?.version_number??0)+1,title:'Synthetic notification QA module',status:'published',created_by:actor.user.id,published_by:actor.user.id,published_at:at,source_trace:{status:'SYNTHETIC_QA_ONLY'}}).select().single());
  const av=await ok(service.from('activity_versions').select('version_number').eq('mission_id',mission.id).order('version_number',{ascending:false}).limit(1));
  await ok(service.from('activity_versions').insert({mission_id:mission.id,module_version_id:module.id,version_number:(av[0]?.version_number??0)+1,title:'Synthetic notification practice task',delivery_mode:'practice',learner_payload:{status:'SYNTHETIC_QA_ONLY'},evaluator_config:{status:'PENDING_TESDA_VALIDATION'},status:'published',created_by:actor.user.id,published_by:actor.user.id,published_at:at}));
}
const module=await ok(service.from('module_versions').select('id').eq('tesda_source_id',source.id).single());
const version=await ok(service.from('activity_versions').select('id').eq('module_version_id',module.id).single());
const technical=await ok(teacher.rpc('assign_activity',{p_class_id:fixture.classA,p_activity_version_id:version.id,p_rubric_version_id:null,p_assignment_type:'practice',p_title:`Technical task ${fixture.run}`}));
const technicalNotices=await ok(service.from('notifications').select('*').eq('event_key',`assignment.created:${technical.id}`));
assert.equal(technicalNotices.length,3);assert(technicalNotices.every(n=>n.metadata.activity_type==='technical'&&n.metadata.activity_id===technical.id));
assert((await outsider.rpc('assign_activity',{p_class_id:fixture.classA,p_activity_version_id:version.id,p_rubric_version_id:null,p_assignment_type:'practice',p_title:'Unauthorized'})).error);
console.log('PASS real supported technical assignment notifications, with no unauthorized assignment');
fs.writeFileSync('.tmp/notification-test-fixture.json',JSON.stringify({...fixture,technical:technical.id,quizAssignment:assignment.id}));
