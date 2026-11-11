import fs from 'node:fs';
import { randomUUID } from 'node:crypto';

// Isolated local QA only. Flutter exports the same work-order actions used by
// its interaction tests: dart run tool/export_practice_test_evidence.dart <file>
const api = process.env.BQ_QA_SUPABASE_URL;
const practice = process.env.BQ_QA_PRACTICE_URL;
const anon = process.env.BQ_QA_ANON_KEY;
const service = process.env.BQ_QA_SERVICE_KEY;
const fixtures = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const [label, value] of Object.entries({api, practice})) {
  const url = new URL(value);
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(url.hostname)) {
    throw new Error(`${label} must point to the isolated local QA stack`);
  }
}
if (!anon || !service || Object.keys(fixtures).length !== 20) {
  throw new Error('QA credentials and exactly 20 mission fixtures are required');
}

let checks = 0;
function check(label, condition, detail) {
  if (!condition) throw new Error(`${label}: ${JSON.stringify(detail).slice(0, 400)}`);
  checks++;
  console.log(`PASS ${label}`);
}
async function call(base, path, {method='GET', token=anon, key=anon, body, headers={}}={}) {
  const response = await fetch(new URL(path, base), {
    method,
    headers: {apikey:key, Authorization:`Bearer ${token}`,
      ...(body === undefined ? {} : {'Content-Type':'application/json'}), ...headers},
    body:body === undefined ? undefined : JSON.stringify(body),
  });
  const raw = await response.text();
  let data;
  try { data = JSON.parse(raw); } catch { data = raw; }
  return {status:response.status, data};
}
const rest = (path, options) => call(api, `/rest/v1/${path}`, options);
const route = (token, body) => call(practice, '', {method:'POST',token,body});
async function signup(label) {
  const result = await call(api, '/auth/v1/signup', {
    method:'POST', body:{email:`qa-${label}-${randomUUID()}@bytequest.invalid`,
      password:`QA-${randomUUID()}-9a!`, data:{full_name:`Synthetic QA ${label}`}},
  });
  check(`signup_${label}`, result.status === 200 && !!result.data?.access_token && !!result.data?.user?.id,
    {status:result.status, error:result.data?.msg ?? result.data?.error});
  return {id:result.data.user.id, token:result.data.access_token};
}
async function submitEvidence(user, mission) {
  const rows = fixtures[mission].map((action, index) => {
    const value = {...action.value};
    delete value.equipment_snapshot;
    delete value.measured_result;
    delete value.measured_fact;
    delete value.measured_tool_result;
    return {learner_id:user.id, mission_id:mission,
      client_action_id:`qa-${mission}-${index}-${randomUUID()}`,
      phase_id:action.phaseId, action_type:action.actionType,
      target:action.target, value, client_occurred_at:new Date().toISOString()};
  });
  const result = await rest('practice_mission_actions?on_conflict=learner_id,client_action_id', {
    method:'POST',token:user.token,body:rows,
    headers:{Prefer:'resolution=ignore-duplicates,return=minimal'},
  });
  check(`${mission}_evidence`, result.status >= 200 && result.status < 300,
    {status:result.status, error:result.data});
}
async function submitInvalidAction(user, mission) {
  const first = fixtures[mission][0];
  const value = {...first.value};
  if (first.actionType === 'placement_attempted') {
    value.item_id = 'qa_incompatible_part';
    value.destination_id = 'qa_incompatible_socket';
  }
  const result = await rest('practice_mission_actions?on_conflict=learner_id,client_action_id', {
    method:'POST',token:user.token,
    body:{learner_id:user.id, mission_id:mission,
      client_action_id:`qa-invalid-${mission}-${randomUUID()}`,
      phase_id:first.phaseId, action_type:first.actionType,
      target:'qa_incompatible_target', value, client_occurred_at:new Date().toISOString()},
    headers:{Prefer:'resolution=ignore-duplicates,return=minimal'},
  });
  check(`${mission}_invalid_action_recorded`, result.status >= 200 && result.status < 300,
    {status:result.status, error:result.data});
}
async function completeQuiz(user, coc) {
  const id = randomUUID();
  const questions = Array.from({length:5}, (_, index) => ({id:`q${index+1}`,
    question:`Synthetic QA question ${index+1}`,choices:['A','B','C','D'],
    answer:0,explanation:'Synthetic QA fact',page:1}));
  const begun = await rest('rpc/practice_begin_quiz', {method:'POST',token:service,key:service,
    body:{p_learner:user.id,p_coc:coc,p_id:id,p_questions:questions}});
  check(`${coc}_quiz_begin`, begun.status === 200 && begun.data?.id === id, begun);
  const active = await rest(`practice_quiz_attempts?id=eq.${id}`, {method:'PATCH',token:service,key:service,
    body:{status:'active'}});
  check(`${coc}_quiz_active`, active.status >= 200 && active.status < 300, active);
  const answers = Object.fromEntries(questions.map(q => [q.id,0]));
  const submitted = await route(user.token,{action:'submit',id,answers});
  check(`${coc}_quiz_submit`, submitted.status === 200 && submitted.data?.passed === true, submitted);
}

const learner = await signup('learner');
const other = await signup('other');
const unauthorized = await route('invalid-token',{action:'verify',mission:'coc1_m1'});
check('route_rejects_invalid_token', unauthorized.status === 401, unauthorized);
for (let cocNumber=1;cocNumber<=4;cocNumber++) {
  const coc = `coc${cocNumber}`;
  for (let missionNumber=1;missionNumber<=5;missionNumber++) {
    const mission = `${coc}_m${missionNumber}`;
    const incomplete = await route(learner.token,{action:'verify',mission});
    check(`${mission}_incomplete_rejected`, incomplete.status === 422, incomplete);
    await submitInvalidAction(learner,mission);
    const invalid = await route(learner.token,{action:'verify',mission});
    check(`${mission}_invalid_action_rejected`, invalid.status === 422, invalid);
    await submitEvidence(learner,mission);
    const verified = await route(learner.token,{action:'verify',mission});
    check(`${mission}_verified`, verified.status === 200 && verified.data?.verified === true, verified);
    const repeated = await route(learner.token,{action:'verify',mission});
    check(`${mission}_idempotent`, repeated.status === 200 && repeated.data?.verified === true, repeated);
  }
  await completeQuiz(learner,coc);
}
const completions = await rest(`practice_mission_completions?select=mission_id&learner_id=eq.${learner.id}`, {
  token:service,key:service});
check('twenty_persisted_completions', completions.status === 200 && completions.data?.length === 20,
  completions);
const path = await rest('rpc/get_practice_learning_path', {method:'POST',token:learner.token,body:{}});
check('learn_page_progress', path.status === 200 && path.data?.length === 4 &&
  path.data.every(coc => coc.completed === true && coc.completed_missions?.length === 5), path);
const otherRead = await rest('practice_mission_completions?select=mission_id', {token:other.token});
check('cross_learner_isolation', otherRead.status === 200 && otherRead.data?.length === 0, otherRead);
console.log(`PASS all_20_mission_api_workflows checks=${checks}`);
