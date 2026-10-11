import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

// Local Docker only, rollback-only. Generate raw work-order fixtures with:
// cd ByteQuest-Mobile-App; dart run tool/export_practice_test_evidence.dart <temp.json>
const fixtures=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const literal=value=>`'${JSON.stringify(value).replaceAll("'","''")}'::jsonb`;
const rows=[];
for(const [mission,actions] of Object.entries(fixtures)) for(const a of actions) {
  const value={...a.value};
  delete value.equipment_snapshot; delete value.measured_result; delete value.measured_fact; delete value.measured_tool_result;
  rows.push(`((select learner from ctx),'${mission}-${a.clientActionId}','${mission}','${a.phaseId}','${a.actionType}',${a.target?`'${a.target}'`:'null'},${literal(value)},now())`);
}
const sql=String.raw`\set ON_ERROR_STOP on
begin;
create temp table ctx as select (select user_id from public.profiles where role='learner' and status='active' order by user_id limit 1) learner,
 (select user_id from public.profiles where role='learner' and status='active' order by user_id offset 1 limit 1) other;
grant select on ctx to authenticated;
select set_config('request.jwt.claim.sub',(select learner::text from ctx),true);
set local role authenticated;
do $$ begin
  if public.practice_coc_unlocked('coc2') then raise exception 'INITIAL_UNLOCK_BYPASS'; end if;
  begin insert into public.practice_coc_progress(learner_id,coc_code,quiz_attempt_id) values((select learner from ctx),'coc1',gen_random_uuid()); raise exception 'CLIENT_PROGRESS_WRITE_ALLOWED'; exception when insufficient_privilege then null; end;
  begin perform public.practice_verify_mission((select learner from ctx),'coc1_m1'); raise exception 'CLIENT_EVALUATION_ALLOWED'; exception when insufficient_privilege then null; end;
  begin perform questions from public.practice_quiz_attempts; raise exception 'CLIENT_ANSWER_KEY_ALLOWED'; exception when insufficient_privilege then null; end;
  begin insert into public.practice_mission_actions(learner_id,client_action_id,mission_id,phase_id,action_type,value,client_occurred_at) values((select learner from ctx),'locked-action','coc2_m1','coc2_m1_p1','object_inspected','{}',now()); raise exception 'LOCKED_EVIDENCE_ALLOWED'; exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.practice_mission_actions(learner_id,client_action_id,mission_id,phase_id,action_type,target,value,client_occurred_at)
 values((select learner from ctx),'forged','coc1_m1','coc1_m1_p1','phase_completed','coc1_m1_p5','{"simulation_valid":true,"equipment_snapshot":{"all_passed":true}}',now());
do $$ begin
 begin perform public.practice_verify_mission((select learner from ctx),'coc1_m1'); raise exception 'FORGED_COMPLETION_ACCEPTED'; exception when invalid_parameter_value then null; end;
end $$;
insert into public.practice_mission_actions(learner_id,client_action_id,mission_id,phase_id,action_type,target,value,client_occurred_at) values
${rows.join(',\n')};
savepoint placement_gate;
delete from public.practice_mission_actions
 where learner_id=(select learner from ctx) and mission_id='coc1_m1'
 and action_type='placement_attempted';
do $$ begin
 begin perform public.practice_verify_mission((select learner from ctx),'coc1_m1'); raise exception 'WORKSPACE_PLACEMENT_BYPASS'; exception when invalid_parameter_value then null; end;
end $$;
rollback to savepoint placement_gate;
do $$ declare learner uuid:=(select learner from ctx); coc text; mission text; a public.practice_quiz_attempts; b public.practice_quiz_attempts;
 questions jsonb:=(select jsonb_agg(jsonb_build_object('id','q'||n,'question','Test question '||n,'choices',jsonb_build_array('A','B','C','D'),'answer',0,'explanation','Verified bank fact','page',1)) from generate_series(1,5) n);
 answers jsonb:='{"q1":0,"q2":0,"q3":0,"q4":0,"q5":0}';
begin
 for n in 1..4 loop
  coc:='coc'||n;
  if n<4 then begin perform public.practice_verify_mission(learner,'coc'||(n+1)||'_m1'); raise exception 'COC_ORDER_BYPASS'; exception when insufficient_privilege then null; end; end if;
  begin perform public.practice_begin_quiz(learner,coc,gen_random_uuid(),questions); raise exception 'QUIZ_BEFORE_PRACTICE_ALLOWED'; exception when invalid_parameter_value then null; end;
  for m in 1..5 loop mission:=coc||'_m'||m; perform public.practice_verify_mission(learner,mission); end loop;
  a:=public.practice_begin_quiz(learner,coc,gen_random_uuid(),questions);
  b:=public.practice_begin_quiz(learner,coc,gen_random_uuid(),questions);
  if a.id<>b.id then raise exception 'QUIZ_RESUME_DUPLICATED'; end if;
  update public.practice_quiz_attempts set status='active' where id=a.id;
  begin perform public.practice_submit_quiz(learner,a.id,'{"q1":0}'); raise exception 'PARTIAL_SUBMIT_ALLOWED'; exception when invalid_parameter_value then null; end;
  if n=1 then
   a:=public.practice_submit_quiz(learner,a.id,'{"q1":1,"q2":1,"q3":1,"q4":1,"q5":1}');
   if a.passed or public.practice_coc_unlocked('coc2',learner) then raise exception 'FAILED_QUIZ_UNLOCK'; end if;
   a:=public.practice_begin_quiz(learner,coc,gen_random_uuid(),questions); update public.practice_quiz_attempts set status='active' where id=a.id;
  end if;
  a:=public.practice_submit_quiz(learner,a.id,answers);
  b:=public.practice_submit_quiz(learner,a.id,'{}');
  if a.score<>5 or not a.passed or b.id<>a.id or b.score<>a.score then raise exception 'GRADING_OR_IDEMPOTENCY_FAILED'; end if;
 end loop;
 if (select count(*) from public.practice_mission_completions where learner_id=learner)<>20 then raise exception 'MISSION_COVERAGE_FAILED'; end if;
 if (select count(*) from public.practice_coc_progress where learner_id=learner)<>4 then raise exception 'COC_COMPLETION_FAILED'; end if;
end $$;
select set_config('request.jwt.claim.sub',(select other::text from ctx),true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.practice_mission_completions where learner_id=(select learner from ctx)) then raise exception 'CROSS_LEARNER_COMPLETION_LEAK'; end if;
 if public.practice_coc_unlocked('coc2') then raise exception 'CROSS_LEARNER_UNLOCK'; end if;
end $$;
reset role;
rollback;
\echo PASS: 20 mission replays, four sequential COCs, quiz resume, failure, grading, idempotency, RLS and tampering
`;
const result=spawnSync('docker',['exec','-i','supabase_db_ByteQuest','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',maxBuffer:2_000_000});
console.log(result.stdout); if(result.stderr) console.error(result.stderr); process.exit(result.status??1);
