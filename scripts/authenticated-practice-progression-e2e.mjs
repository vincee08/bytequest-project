import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// Local-only HTTP integration; keeps immutable evidence and retires QA identities.
// Generate fixtures with tool/export_practice_test_evidence.dart first.
const root=fileURLToPath(new URL('../',import.meta.url));
const dashboard=fileURLToPath(new URL('../ByteQuest-Web-Dashboard/',import.meta.url));
const require=createRequire(new URL('../ByteQuest-Web-Dashboard/package.json',import.meta.url));
const {createClient}=require('@supabase/supabase-js');
const cli='npm.cmd exec --offline --yes --package=supabase@2.117.0 -- supabase status --output json';
const config=JSON.parse(execFileSync('cmd.exe',['/d','/c',cli],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe']}));
assert.equal(new URL(config.API_URL).hostname,'127.0.0.1','Only disposable local Supabase is permitted');
const fixtures=JSON.parse(readFileSync(process.argv[2],'utf8'));
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const users=[];
const checks=[];
const run=`practice-e2e-${randomUUID()}`;
const endpoint='http://127.0.0.1:3006/api/learner/practice';
const server=spawn(process.execPath,[require.resolve('next/dist/bin/next'),'dev','--hostname','127.0.0.1','--port','3006'],{
  cwd:dashboard,windowsHide:true,stdio:'ignore',env:{...process.env,
    NEXT_PUBLIC_SUPABASE_URL:config.API_URL,NEXT_PUBLIC_SUPABASE_ANON_KEY:config.ANON_KEY,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:config.ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:config.SERVICE_ROLE_KEY,
    OPENROUTER_API_KEY:'',PRACTICE_OPENROUTER_MODEL:'openrouter/free',NEXT_TELEMETRY_DISABLED:'1'}
});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function request(token,body,attempt) {
  const response=await fetch(attempt?`${endpoint}?attempt=${attempt}`:endpoint,{
    method:attempt?'GET':'POST',headers:{...(token?{Authorization:`Bearer ${token}`}:{}) ,'Content-Type':'application/json'},
    ...(attempt?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(60_000)
  });
  return {status:response.status,json:await response.json()};
}
async function account(name) {
  const email=`${run}-${name}@bytequest-e2e.invalid`;
  const password=randomBytes(24).toString('base64url');
  const created=await service.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name:`Practice QA ${name}`,bytequest_test_account:true,bytequest_test_run:run}});
  assert.ifError(created.error); users.push(created.data.user.id);
  const profile=await service.from('profiles').update({role:'learner',status:'active'}).eq('user_id',created.data.user.id);
  assert.ifError(profile.error);
  const client=createClient(config.API_URL,config.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const signed=await client.auth.signInWithPassword({email,password}); assert.ifError(signed.error);
  return {id:created.data.user.id,client,token:signed.data.session.access_token};
}
function hidden(view) {
  for(const q of view.questions) { assert.equal('answer' in q,false); assert.equal('explanation' in q,false); }
  assert.equal('score' in view,false); assert.equal('passed' in view,false);
}
async function key(id) {
  const result=await service.from('practice_quiz_attempts').select('questions').eq('id',id).single(); assert.ifError(result.error);
  return Object.fromEntries(result.data.questions.map(q=>[q.id,q.answer]));
}
try {
  let ready=false;
  for(let n=0;n<40;n++) { try {const response=await request(null,{action:'begin',coc:'coc1'}); if(response.status===401){ready=true;break;}}catch{} await delay(500); }
  assert.ok(ready,'Local practice endpoint did not start');
  checks.push('anonymous requests denied');
  const a=await account('a'); const b=await account('b');
  assert.equal((await request(a.token,{action:'begin',coc:'coc1'})).status,403);
  assert.equal((await request(a.token,{action:'verify',mission:'coc2_m1'})).status,403);
  assert.equal((await request(a.token,{action:'verify',mission:'coc1_m1'})).status,422);
  const forged=await a.client.from('practice_mission_actions').insert({learner_id:a.id,client_action_id:randomUUID(),mission_id:'coc2_m1',phase_id:'coc2_m1_p1',action_type:'phase_completed',value:{simulation_valid:true},client_occurred_at:new Date().toISOString()});
  assert.ok(forged.error); checks.push('locked evidence and premature quiz denied');
  for(let n=1;n<=5;n++) {
    const mission=`coc1_m${n}`;
    const actions=fixtures[mission].map(ae=>{
      const value={...ae.value};
      for(const field of ['equipment_snapshot','measured_result','measured_fact','measured_tool_result']) delete value[field];
      return {learner_id:a.id,client_action_id:`${mission}-${ae.clientActionId}`,mission_id:mission,phase_id:ae.phaseId,action_type:ae.actionType,target:ae.target,value,client_occurred_at:new Date().toISOString()};
    });
    const inserted=await a.client.from('practice_mission_actions').insert(actions); assert.ifError(inserted.error);
    const verified=await request(a.token,{action:'verify',mission}); assert.equal(verified.status,200,`${mission}: ${JSON.stringify(verified.json)}`);
  }
  checks.push('five real work orders verified through authenticated API');
  let quiz=await request(a.token,{action:'begin',coc:'coc1'}); assert.equal(quiz.status,200); hidden(quiz.json);
  assert.equal(quiz.json.source,'bank'); assert.equal(quiz.json.questions.length,5);
  const partial={[quiz.json.questions[0].id]:1};
  const saved=await request(a.token,{action:'save',id:quiz.json.id,answers:partial}); assert.equal(saved.status,200); hidden(saved.json);
  const resumed=await request(a.token,{action:'begin',coc:'coc1'}); assert.equal(resumed.json.id,quiz.json.id); assert.deepEqual(resumed.json.answers,partial);
  assert.equal((await request(b.token,null,quiz.json.id)).status,404);
  assert.equal((await request(b.token,{action:'save',id:quiz.json.id,answers:partial})).status,403);
  assert.equal((await request(b.token,{action:'submit',id:quiz.json.id,answers:partial})).status,422);
  assert.equal((await request(a.token,{action:'submit',id:quiz.json.id,answers:partial})).status,422);
  checks.push('answer privacy, restart resume, ownership and partial-submit checks');
  const wrong=Object.fromEntries(Object.entries(await key(quiz.json.id)).map(([id,answer])=>[id,(answer+1)%4]));
  const failed=await request(a.token,{action:'submit',id:quiz.json.id,answers:wrong});
  assert.equal(failed.status,200); assert.equal(failed.json.passed,false); assert.equal(failed.json.score,0);
  assert.ok(failed.json.questions.every(q=>Number.isInteger(q.answer)&&q.explanation));
  let path=await a.client.rpc('get_practice_learning_path'); assert.ifError(path.error); assert.equal(path.data[1].unlocked,false);
  checks.push('failed quiz displays explanations and preserves lock');
  quiz=await request(a.token,{action:'begin',coc:'coc1'}); assert.notEqual(quiz.json.id,failed.json.id); hidden(quiz.json);
  const correct=await key(quiz.json.id); const one=Object.keys(correct)[0]; correct[one]=(correct[one]+1)%4;
  const passed=await request(a.token,{action:'submit',id:quiz.json.id,answers:correct});
  assert.equal(passed.status,200); assert.equal(passed.json.score,4); assert.equal(passed.json.passed,true);
  const repeated=await request(a.token,{action:'submit',id:quiz.json.id,answers:{}}); assert.equal(repeated.json.score,4);
  const completed=await request(a.token,{action:'begin',coc:'coc1'}); assert.equal(completed.json.id,quiz.json.id); assert.equal(completed.json.status,'submitted');
  path=await a.client.rpc('get_practice_learning_path'); assert.ifError(path.error);
  assert.equal(path.data[1].unlocked,true); assert.equal(path.data[2].unlocked,false);
  const other=await b.client.rpc('get_practice_learning_path'); assert.ifError(other.error); assert.equal(other.data[1].unlocked,false);
  checks.push('80% server grading unlocks only next COC; retries are idempotent');
  await service.from('profiles').update({role:'instructor'}).eq('user_id',b.id);
  assert.equal((await request(b.token,{action:'begin',coc:'coc1'})).status,401);
  const malformed=await fetch(endpoint,{method:'POST',headers:{Authorization:`Bearer ${a.token}`,'Content-Type':'application/json'},body:'{'});
  assert.equal(malformed.status,400);
  checks.push('role checks and malformed requests handled');
  console.log(JSON.stringify({status:'PASS',scope:'local-only',checks},null,2));
} finally {
  for(const id of users) {
    const banned=await service.auth.admin.updateUserById(id,{ban_duration:'876000h'}); assert.ifError(banned.error);
    const retired=await service.from('profiles').update({status:'deactivated',deactivated_at:new Date().toISOString(),deactivation_reason:'Local practice progression QA finished; evidence retained'}).eq('user_id',id);
    assert.ifError(retired.error);
  }
  server.kill();
}
