-- Evaluation Center (Objective 4): technical attempts move through an explicit
-- instructor Evaluate step (evaluated -> under_review) before Finalize and
-- Release. Rollback-only; every fixture is removed by the final rollback.
begin;
select plan(47);

create temporary table ec as select
  gen_random_uuid() instructor, gen_random_uuid() other_instructor,
  gen_random_uuid() learner, gen_random_uuid() admin_user,
  gen_random_uuid() class_id, gen_random_uuid() other_class_id,
  null::uuid source_id, null::uuid module_version_id, null::uuid activity_version_id,
  null::uuid rubric_id, null::uuid c1, null::uuid c2, null::uuid assignment_id,
  gen_random_uuid() attempt_override, gen_random_uuid() attempt_confirm,
  gen_random_uuid() attempt_outcome, gen_random_uuid() attempt_submitted,
  gen_random_uuid() attempt_finalized, gen_random_uuid() attempt_array;
grant select on ec to authenticated, service_role;
create temporary table ec_results(label text primary key, payload jsonb);
grant select, insert on ec_results to service_role;
grant select on ec_results to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@evaluation-center.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',name),now(),now()
from ec cross join lateral (values (instructor,'EC Instructor'),(other_instructor,'EC Other Instructor'),
  (learner,'EC Learner'),(admin_user,'EC Admin')) t(id,name);
update public.profiles set role='instructor' where user_id in (select instructor from ec union all select other_instructor from ec);
update public.profiles set role='admin' where user_id=(select admin_user from ec);

with inserted as (
  insert into public.tesda_sources(qualification_code,title,edition,source_reference,status,validation_notes,created_by,approved_by,approved_at,activated_by,activated_at)
  select 'EC-'||left(gen_random_uuid()::text,8),'Evaluation Center rollback source','TEST_ONLY','Rollback fixture only',
    'active','TEST_ONLY_ROLLBACK_FIXTURE',admin_user,admin_user,now(),admin_user,now() from ec returning id)
update ec set source_id=inserted.id from inserted;
with inserted as (
  insert into public.module_versions(module_id,tesda_source_id,version_number,title,source_trace,status,created_by,published_by,published_at)
  select m.id,ec.source_id,coalesce((select max(version_number) from public.module_versions mv where mv.module_id=m.id),0)+1,
    'Evaluation Center rollback module',jsonb_build_object('status','TEST_ONLY'),'published',ec.admin_user,ec.admin_user,now()
  from ec cross join public.coc_modules m where m.coc_code='coc1' returning id)
update ec set module_version_id=inserted.id from inserted;
with inserted as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select m.id,ec.module_version_id,coalesce((select max(version_number) from public.activity_versions av where av.mission_id=m.id),0)+1,
    'Evaluation Center rollback assessment','assessment',jsonb_build_object('status','TEST_ONLY'),jsonb_build_object('status','TEST_ONLY'),
    'published',ec.admin_user,ec.admin_user,now()
  from ec cross join public.missions m where m.mission_code='coc1_m2' returning id)
update ec set activity_version_id=inserted.id from inserted;
with inserted as (
  insert into public.rubric_versions(activity_version_id,tesda_source_id,version_number,title,status,scoring_method,passing_rule,created_by,approved_by,approved_at)
  select activity_version_id,source_id,1,'Evaluation Center rollback rubric','approved','binary_sum',
    jsonb_build_object('status','APPROVED','method','all_required'),admin_user,admin_user,now() from ec returning id)
update ec set rubric_id=inserted.id from inserted;
with inserted as (
  insert into public.rubric_criteria(rubric_version_id,criterion_code,title,source_trace,evidence_rule,scoring_rule,max_value,order_index)
  select rubric_id,'EC-SAFETY','Isolate power and wear the ESD strap','TEST_ONLY_ROLLBACK',jsonb_build_object('operator','action_exists'),
    jsonb_build_object('status','APPROVED','method','binary','satisfied_value',1,'not_satisfied_value',0),1,1 from ec returning id)
update ec set c1=inserted.id from inserted;
with inserted as (
  insert into public.rubric_criteria(rubric_version_id,criterion_code,title,source_trace,evidence_rule,scoring_rule,max_value,order_index)
  select rubric_id,'EC-PROCEDURE','Install components in the approved order','TEST_ONLY_ROLLBACK',jsonb_build_object('operator','action_exists'),
    jsonb_build_object('status','APPROVED','method','binary','satisfied_value',1,'not_satisfied_value',0),1,2 from ec returning id)
update ec set c2=inserted.id from inserted;

insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_id,'EC rollback class','EC-'||left(class_id::text,8),instructor,instructor from ec union all
select other_class_id,'EC other class','EC-'||left(other_class_id::text,8),other_instructor,other_instructor from ec;
insert into public.class_memberships(class_id,learner_id,enrolled_by) select class_id,learner,instructor from ec;
with inserted as (
  insert into public.assignments(class_id,activity_version_id,rubric_version_id,assignment_type,title,assigned_by)
  select class_id,activity_version_id,rubric_id,'assessment','EC rollback assessment',instructor from ec returning id)
update ec set assignment_id=inserted.id from inserted;

-- Attempts start in the states the automated evaluator leaves them in.
insert into public.attempts(id,learner_id,class_id,assignment_id,activity_version_id,rubric_version_id,tesda_source_id,status,
  client_start_key,submission_key,submitted_at,evaluated_at,finalized_at)
select a.id,ec.learner,ec.class_id,ec.assignment_id,ec.activity_version_id,ec.rubric_id,ec.source_id,a.status::public.attempt_status,
  gen_random_uuid(),gen_random_uuid(),now(),case when a.status<>'submitted' then now() end,case when a.status='finalized' then now() end
from ec cross join lateral (values (ec.attempt_override,'evaluated'),(ec.attempt_confirm,'evaluated'),(ec.attempt_outcome,'evaluated'),
  (ec.attempt_array,'evaluated'),(ec.attempt_submitted,'submitted'),(ec.attempt_finalized,'finalized')) a(id,status);
insert into public.score_revisions(attempt_id,revision_number,revision_type,tesda_source_id,rubric_version_id,evaluation_run_id,
  total_value,max_value,percentage,outcome,criterion_values)
select a.id,1,'automated_provisional',ec.source_id,ec.rubric_id,gen_random_uuid(),2,2,100,'competent',
  jsonb_build_array(jsonb_build_object('criterion_id',ec.c1,'observation','satisfied','score_value',1,'observed_evidence','{}'::jsonb),
                    jsonb_build_object('criterion_id',ec.c2,'observation','satisfied','score_value',1,'observed_evidence','{}'::jsonb))
from ec cross join lateral (values (ec.attempt_override),(ec.attempt_confirm),(ec.attempt_outcome),(ec.attempt_array),(ec.attempt_finalized)) a(id);
insert into public.score_revisions(attempt_id,revision_number,revision_type,supersedes_revision_id,actor_id,actor_role,tesda_source_id,
  rubric_version_id,evaluation_run_id,total_value,max_value,percentage,outcome,criterion_values)
select sr.attempt_id,2,'instructor_final',sr.id,ec.instructor,'instructor',sr.tesda_source_id,sr.rubric_version_id,sr.evaluation_run_id,
  2,2,100,'competent',sr.criterion_values
from ec join public.score_revisions sr on sr.attempt_id=ec.attempt_finalized;

-- Contract of the new step and the modified definer.
select ok(to_regprocedure('public.record_attempt_evaluation(uuid,uuid,jsonb,text,text)') is not null,
  'record_attempt_evaluation(p_actor, p_attempt_id, p_criterion_overrides, p_reason, p_note) exists');
select ok(not (select prosecdef from pg_proc where oid='public.record_attempt_evaluation(uuid,uuid,jsonb,text,text)'::regprocedure),
  'record_attempt_evaluation is SECURITY INVOKER');
select ok(has_function_privilege('service_role','public.record_attempt_evaluation(uuid,uuid,jsonb,text,text)','execute')
  and not has_function_privilege('authenticated','public.record_attempt_evaluation(uuid,uuid,jsonb,text,text)','execute')
  and not has_function_privilege('anon','public.record_attempt_evaluation(uuid,uuid,jsonb,text,text)','execute'),
  'record_attempt_evaluation is service-only');
select ok((select prosecdef from pg_proc where oid='public.finalize_attempt(uuid,numeric,numeric,numeric,public.evaluation_outcome,jsonb,text,text)'::regprocedure),
  'finalize_attempt keeps its reviewed SECURITY DEFINER boundary');
select ok((select relrowsecurity from pg_class where oid='public.attempt_evaluation_records'::regclass)
  and not has_table_privilege('authenticated','public.attempt_evaluation_records','INSERT'),
  'evaluation records keep RLS and are server-written only');

-- No stage can be skipped by the owning instructor.
select set_config('request.jwt.claim.sub',(select instructor::text from ec),true);
set local role authenticated;
select throws_ok(format('select public.finalize_attempt(%L,2,2,100,''competent'',null,null,null)',(select attempt_override from ec)),
  '22023','UNDER_REVIEW_ATTEMPT_REQUIRED','cannot finalize an automatically evaluated attempt before the instructor evaluation');
select throws_ok(format('select public.release_attempt(%L,null)',(select attempt_override from ec)),
  '22023','FINALIZED_ATTEMPT_REQUIRED','cannot release an attempt that has not been finalized');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{}'',null,null)',(select instructor from ec),(select attempt_override from ec)),
  '42501',null,'browser clients cannot call the service-only evaluation step directly');
reset role;

-- Server-side role, ownership, state and input validation.
set local role service_role;
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{}'',null,null)',(select other_instructor from ec),(select attempt_override from ec)),
  '42501','CLASS_SCOPE_DENIED','another instructor cannot evaluate this class attempt');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{}'',null,null)',(select learner from ec),(select attempt_override from ec)),
  '42501','INSTRUCTOR_REQUIRED','a learner cannot record an evaluation');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{}'',null,null)',(select admin_user from ec),(select attempt_override from ec)),
  '42501','INSTRUCTOR_REQUIRED','admin access is read-only for routine evaluation');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,%L,null,null)',(select instructor from ec),(select attempt_override from ec),
  jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('criterion_id',(select c2 from ec),'observation','not_satisfied')))),
  '22023','ADJUSTMENT_REASON_REQUIRED','a criterion override without a reason is denied');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,%L,''Reviewed'',null)',(select instructor from ec),(select attempt_override from ec),
  jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('criterion_id',gen_random_uuid(),'observation','not_satisfied')))),
  '22023','INVALID_CRITERION_OVERRIDE','an override must reference a criterion of the attempt rubric');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,%L,''Reviewed'',null)',(select instructor from ec),(select attempt_override from ec),
  jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('criterion_id',(select c2 from ec),'observation','requires_review')))),
  '22023','INVALID_CRITERION_OVERRIDE','an override can only mark a criterion satisfied or not satisfied');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,%L,''Reviewed'',null)',(select instructor from ec),(select attempt_override from ec),
  jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('criterion_id',(select c2 from ec),'observation','satisfied'),
    jsonb_build_object('criterion_id',(select c2 from ec),'observation','not_satisfied')))),
  '22023','INVALID_CRITERION_OVERRIDE','a criterion cannot be overridden twice in one evaluation');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''"bad"'',''Reviewed'',null)',(select instructor from ec),(select attempt_override from ec)),
  '22023','INVALID_CRITERION_OVERRIDE','malformed override payloads are rejected');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{"outcome":"pending_tesda_validation"}'',''Reviewed'',null)',(select instructor from ec),(select attempt_override from ec)),
  '22023','INVALID_EVALUATION_OUTCOME','the reviewed outcome must be competent or not yet competent');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{}'',null,null)',(select instructor from ec),(select attempt_submitted from ec)),
  '55000','EVALUATED_ATTEMPT_REQUIRED','an attempt still awaiting automatic evaluation cannot be instructor-evaluated');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{}'',null,null)',(select instructor from ec),(select attempt_finalized from ec)),
  '55000','EVALUATED_ATTEMPT_REQUIRED','finalized history cannot be re-evaluated');

-- Override with a reason: evaluated -> under_review with an instructor_adjustment.
insert into ec_results select 'override',public.record_attempt_evaluation(instructor,attempt_override,
  jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('criterion_id',c2,'observation','not_satisfied')),'outcome','not_yet_competent'),
  '  Procedure order evidence was misread  ','Reviewed against the recorded sequence.') from ec;
select is((select payload->>'status' from ec_results where label='override'),'under_review','the evaluation step returns the under_review state');
select is((select (payload->>'changed')::boolean from ec_results where label='override'),true,'the evaluation reports that the result changed');
reset role;
select is((select status::text from public.attempts where id=(select attempt_override from ec)),'under_review','the attempt moves to under_review');
select is((select count(*)::integer from public.score_revisions sr join ec on sr.attempt_id=ec.attempt_override
  where sr.revision_number=2 and sr.revision_type='instructor_adjustment' and sr.actor_id=ec.instructor and sr.actor_role='instructor'
    and sr.total_value=1 and sr.max_value=2 and sr.percentage=50 and sr.outcome='not_yet_competent'
    and sr.reason='Procedure order evidence was misread' and sr.remarks='Reviewed against the recorded sequence.'
    and sr.supersedes_revision_id=(select id from public.score_revisions where attempt_id=ec.attempt_override and revision_number=1)),1,
  'the override appends one recalculated, reasoned instructor_adjustment revision');
select is((select string_agg((v->>'observation')||':'||(v->>'score_value'),',' order by ord) from public.score_revisions sr join ec on sr.attempt_id=ec.attempt_override,
  jsonb_array_elements(sr.criterion_values) with ordinality x(v,ord) where sr.revision_number=2),'satisfied:1,not_satisfied:0',
  'only the overridden criterion changes, scored by the approved rubric rule');
select is((select count(*)::integer from public.audit_events ae join ec on ae.target_id=ec.attempt_override
  where ae.action='attempt.evaluation_recorded' and ae.actor_id=ec.instructor and ae.actor_role='instructor' and ae.reason='Procedure order evidence was misread'),1,
  'the evaluation step is audited with its actor and reason');
select is((select count(*)::integer from public.audit_events ae join ec on ae.target_id=ec.attempt_override
  where ae.action='score.adjusted' and ae.actor_id=ec.instructor),1,'the score adjustment is audited');
select is((select count(*)::integer from public.attempt_evaluation_records r join ec on r.attempt_id=ec.attempt_override
  where r.recorded_by=ec.instructor and r.note='Reviewed against the recorded sequence.' and r.outcome='not_yet_competent'
    and r.adjustment_revision_id=(select id from public.score_revisions where attempt_id=ec.attempt_override and revision_number=2)),1,
  'one evaluation record keeps the recorder, note and adjustment');

-- Retries and late changes.
set local role service_role;
insert into ec_results select 'override-retry',public.record_attempt_evaluation(instructor,attempt_override,
  jsonb_build_object('criteria',jsonb_build_array(jsonb_build_object('criterion_id',c2,'observation','not_satisfied')),'outcome','not_yet_competent'),
  'Procedure order evidence was misread',null) from ec;
select is((select (payload->>'replayed')::boolean from ec_results where label='override-retry'),true,'an identical retry is acknowledged as a replay');
select throws_ok(format('select public.record_attempt_evaluation(%L,%L,''{"outcome":"competent"}'',''Changed my mind'',null)',(select instructor from ec),(select attempt_override from ec)),
  '55000','EVALUATION_ALREADY_RECORDED','a recorded evaluation is corrected at finalization, not silently replaced');
reset role;
select is((select count(*)::integer from public.score_revisions where attempt_id=(select attempt_override from ec)),2,'the retry appends no revision');
select is((select count(*)::integer from public.audit_events where target_id=(select attempt_override from ec) and action='attempt.evaluation_recorded'),1,
  'the retry writes no second evaluation audit row');

-- Learners never see the instructor's working evaluation before release.
select set_config('request.jwt.claim.sub',(select learner::text from ec),true);
set local role authenticated;
select is((select count(*)::integer from public.attempt_evaluation_records),0,'learners cannot read instructor evaluation records');
select is((select count(*)::integer from public.score_revisions where attempt_id=(select attempt_override from ec)),0,
  'learners cannot read unreleased score revisions');
reset role;

-- Finalize and release only in order.
select set_config('request.jwt.claim.sub',(select instructor::text from ec),true);
set local role authenticated;
select is((select count(*)::integer from public.attempt_evaluation_records where attempt_id=(select attempt_override from ec)),1,
  'the owning instructor can read the evaluation record');
select throws_ok(format('select public.release_attempt(%L,null)',(select attempt_override from ec)),
  '22023','FINALIZED_ATTEMPT_REQUIRED','release still requires finalization after the evaluation step');
select lives_ok(format('select public.finalize_attempt(%L,1,2,50,''not_yet_competent'',null,null,''Confirmed'')',(select attempt_override from ec)),
  'finalizing the recorded evaluation without further changes needs no reason');
select is((select count(*)::integer from public.score_revisions sr join ec on sr.attempt_id=ec.attempt_override
  where sr.revision_number=3 and sr.revision_type='instructor_final' and sr.total_value=1 and sr.outcome='not_yet_competent'
    and sr.supersedes_revision_id=(select id from public.score_revisions where attempt_id=ec.attempt_override and revision_number=2)),1,
  'the final revision supersedes the instructor adjustment');
select lives_ok(format('select public.release_attempt(%L,''Released after evaluation'')',(select attempt_override from ec)),'release follows finalization');
select is((select status::text from public.attempts where id=(select attempt_override from ec)),'released','the attempt is released');
reset role;

-- Confirming the automated result unchanged, then a reasoned final adjustment.
set local role service_role;
insert into ec_results select 'confirm',public.record_attempt_evaluation(instructor,attempt_confirm,'{}'::jsonb,null,'Evidence matches the rubric.') from ec;
reset role;
select ok((select (payload->>'changed')::boolean = false from ec_results where label='confirm')
  and (select count(*) from public.score_revisions where attempt_id=(select attempt_confirm from ec))=1
  and (select adjustment_revision_id is null from public.attempt_evaluation_records where attempt_id=(select attempt_confirm from ec)),
  'confirming the automated evaluation records the step without an adjustment revision');
select set_config('request.jwt.claim.sub',(select instructor::text from ec),true);
set local role authenticated;
select throws_ok(format('select public.finalize_attempt(%L,2,2,100,''not_yet_competent'',null,null,null)',(select attempt_confirm from ec)),
  '22023','ADJUSTMENT_REASON_REQUIRED','a final adjustment still requires a reason');
select lives_ok(format('select public.finalize_attempt(%L,2,2,100,''not_yet_competent'',null,''Observed unsafe handling'',null)',(select attempt_confirm from ec)),
  'a reasoned final adjustment is accepted from under_review');
reset role;
select is((select string_agg(revision_type::text,'>' order by revision_number) from public.score_revisions where attempt_id=(select attempt_confirm from ec)),
  'automated_provisional>instructor_adjustment>instructor_final','the final adjustment keeps the append-only history');

-- Outcome-only review and the bare-array override form.
set local role service_role;
insert into ec_results select 'outcome',public.record_attempt_evaluation(instructor,attempt_outcome,'{"outcome":"not_yet_competent"}'::jsonb,
  'Safety observation contradicts the automated outcome',null) from ec;
insert into ec_results select 'array',public.record_attempt_evaluation(instructor,attempt_array,
  jsonb_build_array(jsonb_build_object('criterion_id',c1,'observation','not_satisfied')),'ESD strap was not worn',null) from ec;
reset role;
select is((select count(*)::integer from public.score_revisions sr join ec on sr.attempt_id=ec.attempt_outcome
  where sr.revision_type='instructor_adjustment' and sr.total_value=2 and sr.max_value=2 and sr.percentage=100 and sr.outcome='not_yet_competent'),1,
  'an outcome-only review keeps the criterion totals');
select is((select sr.total_value::text||'/'||sr.max_value::text||':'||sr.outcome::text from public.score_revisions sr
  where sr.attempt_id=(select attempt_array from ec) and sr.revision_type='instructor_adjustment'),'1.0000/2.0000:competent',
  'a bare override array is accepted and keeps the current outcome unless one is chosen');

-- Existing finalized and released history is untouched.
select is((select status::text||':'||(select count(*) from public.score_revisions where attempt_id=a.id)::text from public.attempts a
  where a.id=(select attempt_finalized from ec)),'finalized:2','existing finalized attempts keep their state and revisions');
select is((select count(*)::integer from public.attempt_evaluation_records where attempt_id=(select attempt_finalized from ec)),0,
  'no evaluation record is invented for historical attempts');

select * from finish();
rollback;
