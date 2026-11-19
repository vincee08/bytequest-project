-- Slice A7: performance analytics (Objective 6). Rollback-only.
-- Fixtures are created inside this transaction with known expected values:
--   classes C1, C2 (instructor T1), C3 (instructor T2); instructor T3 owns no class.
--   L1 is enrolled in C1 and C2, L2 in C1, L3 in C2, L4 in C3.
-- Every function is called while impersonating the caller (RLS applies), the
-- JSON result is captured, and assertions run after `reset role`.
begin;
select plan(168);

create temporary table ax (
  admin_id uuid default gen_random_uuid(), t1 uuid default gen_random_uuid(),
  t2 uuid default gen_random_uuid(), t3 uuid default gen_random_uuid(),
  l1 uuid default gen_random_uuid(), l2 uuid default gen_random_uuid(),
  l3 uuid default gen_random_uuid(), l4 uuid default gen_random_uuid(),
  c1 uuid default gen_random_uuid(), c2 uuid default gen_random_uuid(), c3 uuid default gen_random_uuid(),
  source_id uuid, module_version_id uuid, activity_version_id uuid, rubric_id uuid,
  crit_a uuid default gen_random_uuid(), crit_b uuid default gen_random_uuid(),
  asg_c1 uuid default gen_random_uuid(), asg_c2 uuid default gen_random_uuid(),
  att_l1_a uuid default gen_random_uuid(), att_l1_b uuid default gen_random_uuid(),
  att_l2 uuid default gen_random_uuid(), att_l3 uuid default gen_random_uuid(),
  q1 uuid default gen_random_uuid(), q1v uuid default gen_random_uuid(),
  q1i1 uuid default gen_random_uuid(), q1i2 uuid default gen_random_uuid(),
  q2 uuid default gen_random_uuid(), q2v uuid default gen_random_uuid(), q2i1 uuid default gen_random_uuid(),
  qa1_c1 uuid default gen_random_uuid(), qa1_c2 uuid default gen_random_uuid(), qa2_c1 uuid default gen_random_uuid(),
  qt_l1 uuid default gen_random_uuid(), qt_l2 uuid default gen_random_uuid(),
  qt_l3 uuid default gen_random_uuid(), qt_l2_draft uuid default gen_random_uuid(),
  h1 uuid default gen_random_uuid(), h2 uuid default gen_random_uuid(),
  coc1_id uuid, act_l1 bigint, act_l3 bigint
);
insert into ax default values;
update ax set coc1_id = (select id from public.coc_modules where coc_code = 'coc1');
create temporary table ar (name text primary key, v jsonb);
grant select on ax to authenticated;
grant select, insert on ar to authenticated;

-- Identities (handle_new_user provisions the profiles).
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select u.id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',u.id||'@analytics-rollback.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',u.name),now(),now()
from ax cross join lateral (values
  (admin_id,'Analytics Admin'),(t1,'Analytics Teacher One'),(t2,'Analytics Teacher Two'),(t3,'Analytics Teacher Three'),
  (l1,'Ana Analytics'),(l2,'Ben Analytics'),(l3,'Cara Analytics'),(l4,'Dino Analytics')) u(id,name);
update public.profiles set role = 'admin' where user_id = (select admin_id from ax);
update public.profiles set role = 'instructor' where user_id in (select t1 from ax union all select t2 from ax union all select t3 from ax);
update public.profiles p set learner_id = s.sid from ax cross join lateral (values (l1,'A7-001'),(l2,'A7-002'),(l3,'A7-003'),(l4,'A7-004')) s(id,sid) where p.user_id = s.id;

insert into public.classes(id,title,class_code,instructor_id,created_by)
select c1,'Analytics A','A7-'||left(c1::text,8),t1,t1 from ax union all
select c2,'Analytics B','A7-'||left(c2::text,8),t1,t1 from ax union all
select c3,'Analytics C','A7-'||left(c3::text,8),t2,t2 from ax;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select c1,l1,t1 from ax union all select c2,l1,t1 from ax union all select c1,l2,t1 from ax union all
select c2,l3,t1 from ax union all select c3,l4,t2 from ax;

-- ===================================================================
-- Zero-data results: null averages, empty arrays, each learner once.
-- ===================================================================
select set_config('request.jwt.claim.sub',(select t1::text from ax),true);
set local role authenticated;
insert into ar values
  ('zero_overview', public.get_analytics_overview('{}'::jsonb)),
  ('zero_classes', public.get_class_performance('{}'::jsonb)),
  ('zero_learners', public.get_learner_performance('{}'::jsonb)),
  ('zero_quizzes', public.get_quiz_analytics(null, '{}'::jsonb)),
  ('zero_missions', public.get_mission_analytics('{}'::jsonb)),
  ('zero_criteria', public.get_criteria_analytics('{}'::jsonb));
select set_config('request.jwt.claim.sub',(select t3::text from ax),true);
insert into ar values
  ('empty_overview', public.get_analytics_overview('{}'::jsonb)),
  ('empty_classes', public.get_class_performance('{}'::jsonb));
reset role;

select is((select (v->'population'->>'enrolled')::int from ar where name='zero_overview'), 3,
  'L1 enrolled in two classes is counted once in the overview population');
select is((select v->'assessments'->>'avg_percent' from ar where name='zero_overview'), null, 'no released result gives a null assessment average');
select is((select v->'assessments'->>'competent_rate' from ar where name='zero_overview'), null, 'no released result gives a null competent rate');
select is((select v->'quizzes'->>'avg_percent' from ar where name='zero_overview'), null, 'no quiz result gives a null quiz average');
select is((select v->'quizzes'->>'completion_rate' from ar where name='zero_overview'), null, 'no eligible quiz gives a null completion rate');
select is((select v->'homework'->>'avg_percent' from ar where name='zero_overview'), null, 'no graded homework gives a null homework average');
select is((select v->'missions'->>'avg_duration_seconds' from ar where name='zero_overview'), null, 'no practice run gives a null duration');
select is((select (v->'missions'->>'runs')::int from ar where name='zero_overview'), 0, 'zero recorded runs');
select is((select v->'trend' from ar where name='zero_overview'), '[]'::jsonb, 'no activity gives an empty trend');
select is((select (v->'learning_progress'->>'avg_percent')::numeric from ar where name='zero_overview'), 0::numeric,
  'learners with required items but no completions average 0 % learning progress');
select is((select jsonb_array_length(v->'learners') from ar where name='zero_learners'), 3, 'learner list counts each learner once');
select is((select v->'quizzes' from ar where name='zero_quizzes'), '[]'::jsonb, 'no quiz gives an empty quiz list');
select is((select v->'missions' from ar where name='zero_missions'), '[]'::jsonb, 'no practice activity gives an empty mission list');
select is((select v->'assessments' from ar where name='zero_missions'), '[]'::jsonb, 'no assessment attempt gives an empty assessment list');
select is((select v->'criteria' from ar where name='zero_criteria'), '[]'::jsonb, 'no released criterion gives an empty criteria list');
select is((select v->'strongest' from ar where name='zero_criteria'), '[]'::jsonb, 'no strongest criterion without data');
select is((select (v->'population'->>'enrolled')::int from ar where name='empty_overview'), 0, 'an instructor without classes has an empty population');
select is((select v->'classes' from ar where name='empty_overview'), '[]'::jsonb, 'an instructor without classes has no class rows');
select is((select v->'learning_progress'->>'avg_percent' from ar where name='empty_overview'), null, 'empty population gives a null progress average');
select is((select v->'summary'->>'avg_score' from ar where name='empty_classes'), null, 'empty class summary averages are null');
select is((select v->'classes' from ar where name='empty_classes'), '[]'::jsonb, 'empty class performance list');
select ok((select (v->'classes'->0->>'avg_score') is null and (v->'classes'->0->>'enrolled')::int = 2 from ar where name='zero_classes'),
  'a class with members but no scored work has a null average score');

-- ===================================================================
-- Access control and filter validation.
-- ===================================================================
select set_config('request.jwt.claim.sub',(select t1::text from ax),true);
set local role authenticated;
select throws_ok(format('select public.get_analytics_overview(%L::jsonb)', jsonb_build_object('class_id',(select c3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'an instructor cannot read another instructor''s class');
select throws_ok(format('select public.get_class_performance(%L::jsonb)', jsonb_build_object('class_id',(select c3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'class performance enforces class ownership');
select throws_ok(format('select public.get_learner_profile_analytics(%L::uuid, ''{}''::jsonb)', (select l4 from ax)),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'an instructor cannot open a learner outside their classes');
select throws_ok(format('select public.get_learner_performance(%L::jsonb)', jsonb_build_object('learner_id',(select l4 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'learner filter outside the caller scope is denied');
select throws_ok($$select public.get_analytics_overview('{"klass":"x"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'unknown filter keys are rejected');
select throws_ok($$select public.get_analytics_overview('{"class_id":"not-a-uuid"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'malformed uuids are rejected');
select throws_ok($$select public.get_analytics_overview('{"from":"2026-02-01T00:00:00Z","to":"2026-01-01T00:00:00Z"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'from after to is rejected');
select throws_ok($$select public.get_analytics_overview('{"from":"2025-01-01T00:00:00Z","to":"2026-06-01T00:00:00Z"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'periods longer than 366 days are rejected');
select throws_ok($$select public.get_analytics_overview('{"from":"yesterday-ish"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'malformed dates are rejected');
select throws_ok($$select public.get_analytics_overview('{"coc_code":"coc9"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'unknown COC codes are rejected');
select throws_ok($$select public.get_analytics_overview('{"mission_code":"coc1_m9"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'unknown mission codes are rejected');
select throws_ok($$select public.get_my_performance()$$, '42501', 'ANALYTICS_LEARNER_REQUIRED', 'staff cannot call the learner performance view');
select set_config('request.jwt.claim.sub',(select l1::text from ax),true);
select throws_ok($$select public.get_analytics_overview('{}'::jsonb)$$, '42501', 'ANALYTICS_ACCESS_DENIED', 'learners cannot read staff analytics');
reset role;
select ok((select bool_and(not p.prosecdef and p.provolatile = 's') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('get_analytics_overview','get_class_performance','get_learner_performance',
    'get_learner_profile_analytics','get_quiz_analytics','get_mission_analytics','get_criteria_analytics','get_my_performance',
    'get_analytics_filter_options')), 'every analytics function is stable SECURITY INVOKER');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('get_analytics_overview','get_class_performance','get_learner_performance',
    'get_learner_profile_analytics','get_quiz_analytics','get_mission_analytics','get_criteria_analytics','get_my_performance',
    'get_analytics_filter_options')), 9, 'all nine analytics functions exist');
select ok(not has_function_privilege('anon', 'public.get_analytics_overview(jsonb)', 'execute'), 'anon cannot execute analytics');
select ok(has_function_privilege('authenticated', 'public.get_my_performance()', 'execute'), 'authenticated may call the learner view');
select ok((select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname like 'analytics%' and p.prosecdef), 'no analytics helper is SECURITY DEFINER');
select ok((select count(*) = 3 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'
  and tablename in ('practice_mission_runs','learner_topic_progress','learner_module_completions')),
  'run, topic and module progress tables are published for realtime refresh');

-- ===================================================================
-- Technical assessment fixtures (mission coc1_m2, two criteria).
-- ===================================================================
with s as (
  insert into public.tesda_sources(qualification_code,title,edition,source_reference,status,validation_notes,created_by,approved_by,approved_at,activated_by,activated_at)
  select 'A7-'||left(gen_random_uuid()::text,8),'Analytics rollback source','TEST_ONLY','Rollback fixture','active','TEST_ONLY',admin_id,admin_id,now(),admin_id,now() from ax
  returning id)
update ax set source_id = s.id from s;
with mv as (
  insert into public.module_versions(module_id,tesda_source_id,version_number,title,source_trace,status,created_by,published_by,published_at)
  select coc1_id, source_id, coalesce((select max(version_number) from public.module_versions where module_id = ax.coc1_id),0)+1,
    'Analytics module version','{"status":"TEST_ONLY"}','published',admin_id,admin_id,now() from ax
  returning id)
update ax set module_version_id = mv.id from mv;
with av as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select (select id from public.missions where mission_code = 'coc1_m2'), module_version_id,
    coalesce((select max(version_number) from public.activity_versions where mission_id = (select id from public.missions where mission_code='coc1_m2')),0)+1,
    'Analytics assessment','assessment','{}','{"secret":"evaluator"}','published',admin_id,admin_id,now() from ax
  returning id)
update ax set activity_version_id = av.id from av;
with rv as (
  insert into public.rubric_versions(activity_version_id,tesda_source_id,version_number,title,status,scoring_method,passing_rule,created_by,approved_by,approved_at)
  select activity_version_id,source_id,1,'Analytics rubric','approved','TEST_ONLY_POINTS','{"status":"APPROVED","method":"threshold","threshold":75}',admin_id,admin_id,now() from ax
  returning id)
update ax set rubric_id = rv.id from rv;
insert into public.rubric_criteria(id,rubric_version_id,criterion_code,title,source_trace,evidence_rule,scoring_rule,max_value,order_index)
select crit_a,rubric_id,'A7-CRIT-A','Analytics criterion A','TEST_ONLY','{"operator":"action_exists","expected":"secret-a"}'::jsonb,'{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0}'::jsonb,1,1 from ax union all
select crit_b,rubric_id,'A7-CRIT-B','Analytics criterion B','TEST_ONLY','{"operator":"action_exists","expected":"secret-b"}'::jsonb,'{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0}'::jsonb,1,2 from ax;
insert into public.assignments(id,class_id,activity_version_id,rubric_version_id,assignment_type,title,assigned_by)
select asg_c1,c1,activity_version_id,rubric_id,'assessment'::public.assignment_type,'Analytics assessment A',t1 from ax union all
select asg_c2,c2,activity_version_id,rubric_id,'assessment'::public.assignment_type,'Analytics assessment B',t1 from ax;
insert into public.attempts(id,learner_id,class_id,assignment_id,activity_version_id,rubric_version_id,tesda_source_id,status,client_start_key,submission_key,started_at,submitted_at,evaluated_at,finalized_at,released_at)
select att_l1_a,l1,c1,asg_c1,activity_version_id,rubric_id,source_id,'released'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '5 days',now()-interval '5 days',now()-interval '5 days',now()-interval '5 days',now()-interval '5 days' from ax union all
select att_l1_b,l1,c1,asg_c1,activity_version_id,rubric_id,source_id,'released'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '3 days',now()-interval '3 days',now()-interval '3 days',now()-interval '3 days',now()-interval '3 days' from ax union all
select att_l2,l2,c1,asg_c1,activity_version_id,rubric_id,source_id,'evaluated'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '20 days',now()-interval '20 days',now()-interval '20 days',null,null from ax union all
select att_l3,l3,c2,asg_c2,activity_version_id,rubric_id,source_id,'released'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '4 days',now()-interval '4 days',now()-interval '4 days',now()-interval '4 days',now()-interval '4 days' from ax;
insert into public.score_revisions(attempt_id,revision_number,revision_type,actor_id,actor_role,tesda_source_id,rubric_version_id,total_value,max_value,percentage,outcome,criterion_values)
select att_l1_a,1,'instructor_final'::public.score_revision_type,t1,'instructor'::public.user_role,source_id,rubric_id,1,2,50,'not_yet_competent'::public.evaluation_outcome,
  jsonb_build_array(jsonb_build_object('criterion_id',crit_a,'observation','satisfied','score_value',1),jsonb_build_object('criterion_id',crit_b,'observation','not_satisfied','score_value',0)) from ax union all
select att_l1_b,1,'instructor_final'::public.score_revision_type,t1,'instructor'::public.user_role,source_id,rubric_id,2,2,100,'competent'::public.evaluation_outcome,
  jsonb_build_array(jsonb_build_object('criterion_id',crit_a,'observation','satisfied','score_value',1),jsonb_build_object('criterion_id',crit_b,'observation','satisfied','score_value',1)) from ax union all
select att_l3,1,'instructor_final'::public.score_revision_type,t1,'instructor'::public.user_role,source_id,rubric_id,1,2,50,'not_yet_competent'::public.evaluation_outcome,
  jsonb_build_array(jsonb_build_object('criterion_id',crit_a,'observation','satisfied','score_value',1),jsonb_build_object('criterion_id',crit_b,'observation','not_satisfied','score_value',0)) from ax union all
select att_l2,1,'automated_provisional'::public.score_revision_type,null,null,source_id,rubric_id,0,2,0,'not_yet_competent'::public.evaluation_outcome,
  jsonb_build_array(jsonb_build_object('criterion_id',crit_a,'observation','not_satisfied','score_value',0),jsonb_build_object('criterion_id',crit_b,'observation','not_satisfied','score_value',0)) from ax;
insert into public.result_releases(attempt_id,score_revision_id,release_number,released_by,released_at,is_current)
select a.id,(select sr.id from public.score_revisions sr where sr.attempt_id = a.id),1,(select t1 from ax),a.released_at,true
from public.attempts a where a.id in (select att_l1_a from ax union all select att_l1_b from ax union all select att_l3 from ax);
insert into public.criterion_results(attempt_id,rubric_criterion_id,evaluation_run_id,expected_rule,observed_evidence,observation,score_value)
select att_l1_b,crit_a,gen_random_uuid(),'{}'::jsonb,'{}'::jsonb,'satisfied'::public.criterion_observation,1 from ax union all
select att_l1_b,crit_b,gen_random_uuid(),'{}'::jsonb,'{}'::jsonb,'satisfied'::public.criterion_observation,1 from ax union all
select att_l3,crit_a,gen_random_uuid(),'{}'::jsonb,'{}'::jsonb,'satisfied'::public.criterion_observation,1 from ax union all
select att_l3,crit_b,gen_random_uuid(),'{}'::jsonb,'{}'::jsonb,'not_satisfied'::public.criterion_observation,0 from ax union all
select att_l2,crit_a,gen_random_uuid(),'{}'::jsonb,'{}'::jsonb,'not_satisfied'::public.criterion_observation,0 from ax;

-- ===================================================================
-- Quiz fixtures: Q1 published (assigned to C1 and C2), Q2 never published.
-- ===================================================================
insert into public.quizzes(id,instructor_id,coc_module_id,title,topic,created_by)
select q1,t1,coc1_id,'Analytics Quiz One','Hardware',t1 from ax union all
select q2,t1,coc1_id,'Analytics Draft Quiz','Hardware',t1 from ax;
insert into public.quiz_versions(id,quiz_id,version_number,status,created_by,published_by,published_at)
select q1v,q1,1,'published'::public.content_version_status,t1,t1,now()-interval '25 days' from ax union all
select q2v,q2,1,'draft'::public.content_version_status,t1,null::uuid,null::timestamptz from ax;
insert into public.quiz_items(id,quiz_version_id,item_code,item_type,prompt,options,correct_answer,review_status,reviewed_by,reviewed_at,order_index,created_by)
select q1i1,q1v,'A7-ITEM-1','true_false'::public.quiz_item_type,'Analytics item one prompt','[]'::jsonb,'"True"'::jsonb,'approved'::public.quiz_item_review_status,t1,now(),1,t1 from ax union all
select q1i2,q1v,'A7-ITEM-2','true_false'::public.quiz_item_type,'Analytics item two prompt','[]'::jsonb,'"True"'::jsonb,'approved'::public.quiz_item_review_status,t1,now(),2,t1 from ax union all
select q2i1,q2v,'A7-ITEM-D','true_false'::public.quiz_item_type,'Draft item prompt','[]'::jsonb,'"True"'::jsonb,'approved'::public.quiz_item_review_status,t1,now(),1,t1 from ax;
insert into public.quiz_assignments(id,class_id,quiz_version_id,assigned_by,created_at)
select qa1_c1,c1,q1v,t1,now()-interval '25 days' from ax union all
select qa1_c2,c2,q1v,t1,now()-interval '25 days' from ax union all
select qa2_c1,c1,q2v,t1,now()-interval '25 days' from ax;
insert into public.quiz_attempts(id,learner_id,class_id,quiz_assignment_id,quiz_version_id,status,client_start_key,submission_key,started_at,submitted_at,completed_at)
select qt_l1,l1,c1,qa1_c1,q1v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '2 days',now()-interval '2 days',now()-interval '2 days' from ax union all
select qt_l2,l2,c1,qa1_c1,q1v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '20 days',now()-interval '20 days',now()-interval '20 days' from ax union all
select qt_l3,l3,c2,qa1_c2,q1v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '2 days',now()-interval '2 days',now()-interval '2 days' from ax union all
select qt_l2_draft,l2,c1,qa2_c1,q2v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '20 days',now()-interval '20 days',now()-interval '20 days' from ax;
insert into public.quiz_answers(quiz_attempt_id,quiz_item_id,quiz_version_id,answer,is_correct)
select qt_l1,q1i1,q1v,'"True"'::jsonb,true from ax union all select qt_l1,q1i2,q1v,'"True"'::jsonb,true from ax union all
select qt_l2,q1i1,q1v,'"True"'::jsonb,true from ax union all select qt_l2,q1i2,q1v,'"False"'::jsonb,false from ax union all
select qt_l3,q1i1,q1v,'"False"'::jsonb,false from ax union all select qt_l3,q1i2,q1v,'"False"'::jsonb,false from ax union all
select qt_l2_draft,q2i1,q2v,'"True"'::jsonb,true from ax;
insert into public.quiz_results(quiz_attempt_id,correct_count,question_count,item_results,evaluated_at)
select qt_l1,2,2,'[]'::jsonb,now()-interval '2 days' from ax union all
select qt_l2,1,2,'[]'::jsonb,now()-interval '20 days' from ax union all
select qt_l3,0,2,'[]'::jsonb,now()-interval '2 days' from ax union all
select qt_l2_draft,1,1,'[]'::jsonb,now()-interval '20 days' from ax;

-- ===================================================================
-- Homework fixtures: H1 in C1 (L1 on time, graded 80; L2 missing),
-- H2 in C2 (L3 late, graded 60; L1 missing).
-- ===================================================================
insert into public.homework_assignments(id,class_id,instructor_id,title,instructions,status,deadline_at,published_at)
select h1,c1,t1,'Analytics Homework One','Write the report.','published',now()-interval '2 days',now()-interval '10 days' from ax union all
select h2,c2,t1,'Analytics Homework Two','Write the report.','published',now()-interval '5 days',now()-interval '10 days' from ax;
insert into public.homework_submissions(assignment_id,learner_id,answer,submitted_at,effective_deadline_at,deadline_revision,status,score,graded_at,graded_by)
select h1,l1,'Report',now()-interval '3 days',now()-interval '2 days',1,'graded',80,now()-interval '1 day',t1 from ax union all
select h2,l3,'Report',now()-interval '3 days',now()-interval '5 days',1,'graded',60,now()-interval '1 day',t1 from ax;

-- ===================================================================
-- Practice fixtures: server-verified completions and recorded runs.
-- ===================================================================
with a as (
  insert into public.practice_mission_actions(learner_id,client_action_id,mission_id,phase_id,action_type,value,client_occurred_at)
  select l1,'a7-l1','coc1_m1','phase','inspect','{}',now()-interval '7 days' from ax returning id)
update ax set act_l1 = a.id from a;
with a as (
  insert into public.practice_mission_actions(learner_id,client_action_id,mission_id,phase_id,action_type,value,client_occurred_at)
  select l3,'a7-l3','coc1_m1','phase','inspect','{}',now()-interval '7 days' from ax returning id)
update ax set act_l3 = a.id from a;
insert into public.practice_mission_completions(learner_id,mission_id,contract_version,evidence_through_id,verified_at)
select l1,'coc1_m1','1',act_l1,now()-interval '6 days' from ax union all
select l1,'coc1_m2','1',act_l1,now()-interval '5 days' from ax union all
select l1,'coc1_m3','1',act_l1,now()-interval '4 days' from ax union all
select l3,'coc1_m1','1',act_l3,now()-interval '6 days' from ax union all
select l3,'coc1_m5','1',act_l3,now()-interval '5 days' from ax;
insert into public.practice_mission_runs(learner_id,mission_id,contract_version,run_number,started_at,ended_at,duration_seconds,action_count,invalid_count,correction_count,outcome,created_at)
select l1,'coc1_m1','1',1,now()-interval '7 days',now()-interval '7 days',90,8,3,1,'incomplete',now()-interval '7 days' from ax union all
select l1,'coc1_m1','1',2,now()-interval '6 days',now()-interval '6 days',120,6,0,0,'verified',now()-interval '6 days' from ax union all
select l1,'coc1_m2','1',1,now()-interval '5 days',now()-interval '5 days',200,9,0,0,'verified',now()-interval '5 days' from ax union all
select l1,'coc1_m3','1',1,now()-interval '4 days',now()-interval '4 days',300,12,0,0,'verified',now()-interval '4 days' from ax union all
select l3,'coc1_m4','1',1,now()-interval '3 days',now()-interval '3 days',60,5,2,0,'incomplete',now()-interval '3 days' from ax union all
select l3,'coc1_m4','1',2,now()-interval '2 days',now()-interval '2 days',70,5,2,0,'incomplete',now()-interval '2 days' from ax union all
select l3,'coc1_m4','1',3,now()-interval '1 day',now()-interval '1 day',80,5,2,0,'incomplete',now()-interval '1 day' from ax;
-- A COC1 practice quiz pass for L4 (T2's learner) exercises the new practice_coc_progress policy.
with pq as (
  insert into public.practice_quiz_attempts(learner_id,coc_code,status,questions,answers,score,passed,submitted_at)
  select l4,'coc1','submitted','[1,2,3,4,5]','{}',5,true,now()-interval '1 day' from ax returning id, learner_id)
insert into public.practice_coc_progress(learner_id,coc_code,completed_at,quiz_attempt_id) select learner_id,'coc1',now()-interval '1 day',id from pq;

-- ===================================================================
-- RLS: instructors read practice records of learners they teach only.
-- ===================================================================
select set_config('request.jwt.claim.sub',(select t1::text from ax),true);
set local role authenticated;
insert into ar values ('t1_completions', to_jsonb((select count(*) from public.practice_mission_completions where learner_id in (select l1 from ax union all select l3 from ax))));
insert into ar values ('t1_coc_progress', to_jsonb((select count(*) from public.practice_coc_progress where learner_id = (select l4 from ax))));
select set_config('request.jwt.claim.sub',(select t2::text from ax),true);
insert into ar values ('t2_completions', to_jsonb((select count(*) from public.practice_mission_completions where learner_id in (select l1 from ax union all select l3 from ax))));
insert into ar values ('t2_coc_progress', to_jsonb((select count(*) from public.practice_coc_progress where learner_id = (select l4 from ax))));
select set_config('request.jwt.claim.sub',(select l1::text from ax),true);
insert into ar values ('l1_completions', to_jsonb((select count(*) from public.practice_mission_completions)));
insert into ar values ('l1_criteria', to_jsonb((select count(*) from public.rubric_criteria where rubric_version_id = (select rubric_id from ax))));
select set_config('request.jwt.claim.sub',(select l2::text from ax),true);
insert into ar values ('l2_criteria', to_jsonb((select count(*) from public.rubric_criteria where rubric_version_id = (select rubric_id from ax))));
select set_config('request.jwt.claim.sub',(select admin_id::text from ax),true);
insert into ar values ('admin_completions', to_jsonb((select count(*) from public.practice_mission_completions where learner_id in (select l1 from ax union all select l3 from ax))));
reset role;
select is((select v::int from ar where name='t1_completions'), 5, 'instructor reads practice completions of learners in owned classes');
select is((select v::int from ar where name='t2_completions'), 0, 'instructor cannot read practice completions outside owned classes');
select is((select v::int from ar where name='t2_coc_progress'), 1, 'instructor reads COC progress of an owned learner');
select is((select v::int from ar where name='t1_coc_progress'), 0, 'instructor cannot read COC progress outside owned classes');
select is((select v::int from ar where name='admin_completions'), 5, 'admin reads all practice completions');
select is((select v::int from ar where name='l1_completions'), 3, 'learners still read only their own completions');
select is((select v::int from ar where name='l1_criteria'), 2, 'learner reads criterion labels of their own released result');
select is((select v::int from ar where name='l2_criteria'), 0, 'criterion labels stay hidden for unreleased results');
select ok(not has_table_privilege('authenticated', 'public.practice_quiz_attempts', 'SELECT'), 'practice quiz attempts (answer keys) stay unreadable by clients');

-- ===================================================================
-- Populated analytics (default period: last 30 days).
-- ===================================================================
select set_config('request.jwt.claim.sub',(select t1::text from ax),true);
set local role authenticated;
insert into ar values
  ('overview', public.get_analytics_overview('{}'::jsonb)),
  ('overview_c2', public.get_analytics_overview(jsonb_build_object('class_id',(select c2 from ax)))),
  ('overview_quiz', public.get_analytics_overview(jsonb_build_object('quiz_id',(select q1 from ax)))),
  ('overview_coc2', public.get_analytics_overview('{"coc_code":"COC2"}'::jsonb)),
  ('classes', public.get_class_performance('{}'::jsonb)),
  ('learners', public.get_learner_performance('{}'::jsonb)),
  ('learner_l2_only', public.get_learner_performance(jsonb_build_object('learner_id',(select l2 from ax)))),
  ('quiz_list', public.get_quiz_analytics(null,'{}'::jsonb)),
  ('quiz_q1', public.get_quiz_analytics((select q1 from ax),'{}'::jsonb)),
  ('quiz_q2', public.get_quiz_analytics((select q2 from ax),'{}'::jsonb)),
  ('missions', public.get_mission_analytics('{}'::jsonb)),
  ('missions_m1', public.get_mission_analytics('{"mission_code":"coc1_m1"}'::jsonb)),
  ('criteria', public.get_criteria_analytics('{}'::jsonb)),
  ('profile_l1', public.get_learner_profile_analytics((select l1 from ax),'{}'::jsonb)),
  ('options', public.get_analytics_filter_options());
select set_config('request.jwt.claim.sub',(select t2::text from ax),true);
insert into ar values ('overview_t2', public.get_analytics_overview('{}'::jsonb));
select set_config('request.jwt.claim.sub',(select admin_id::text from ax),true);
insert into ar values ('overview_admin', public.get_analytics_overview('{}'::jsonb));
select set_config('request.jwt.claim.sub',(select l1::text from ax),true);
insert into ar values ('me_l1', public.get_my_performance());
select set_config('request.jwt.claim.sub',(select l2::text from ax),true);
insert into ar values ('me_l2', public.get_my_performance());
reset role;

-- Overview: population and accuracy.
select is((select (v->'population'->>'enrolled')::int from ar where name='overview'), 3, 'population counts L1 once across C1 and C2');
select is((select (v->'population'->>'active_in_period')::int from ar where name='overview'), 3, 'three learners have activity in the period');
select is((select (v->'population'->>'completed')::int from ar where name='overview'), 0, 'nobody completed every required item');
select is((select (v->'population'->>'enrolled')::int from ar where name='overview_admin'), 4, 'admin overview covers every active class');
select is((select (v->'population'->>'enrolled')::int from ar where name='overview_t2'), 1, 'another instructor sees only their own learner');
select is((select v->'assessments'->>'avg_percent' from ar where name='overview_t2'), null, 'another instructor sees no foreign assessment results');
select is((select (v->'assessments'->>'submitted')::int from ar where name='overview'), 4, 'four assessment attempts were submitted');
select is((select (v->'assessments'->>'released')::int from ar where name='overview'), 3, 'three results are released');
select is((select (v->'assessments'->>'pending_release')::int from ar where name='overview'), 1, 'the unreleased evaluated attempt is counted as pending');
select is((select (v->'assessments'->>'avg_percent')::numeric from ar where name='overview'), 66.7, 'pending results are excluded from the assessment average');
select is((select (v->'assessments'->>'competent_rate')::numeric from ar where name='overview'), 33.3, 'competent rate uses released results only');
select is((select (v->'quizzes'->>'submitted')::int from ar where name='overview'), 3, 'only published quiz submissions are counted');
select is((select (v->'quizzes'->>'avg_percent')::numeric from ar where name='overview'), 50.0, 'the unpublished quiz result is excluded from the quiz average');
select is((select (v->'quizzes'->>'eligible')::int from ar where name='overview'), 3, 'quiz eligibility counts each learner once per quiz');
select is((select (v->'quizzes'->>'completion_rate')::numeric from ar where name='overview'), 100.0, 'every eligible learner completed the published quiz');
select is((select (v->'homework'->>'submitted')::int from ar where name='overview'), 2, 'two homework submissions');
select is((select (v->'homework'->>'missing')::int from ar where name='overview'), 2, 'two past-deadline homework items are missing');
select is((select (v->'homework'->>'late')::int from ar where name='overview'), 1, 'one late homework submission');
select is((select (v->'homework'->>'avg_percent')::numeric from ar where name='overview'), 70.0, 'missing homework is not scored as zero');
select is((select (v->'missions'->>'runs')::int from ar where name='overview'), 7, 'mission attempts equal the recorded practice runs');
select is((select (v->'missions'->>'successful_runs')::int from ar where name='overview'), 3, 'three verified runs');
select is((select (v->'missions'->>'failed_runs')::int from ar where name='overview'), 4, 'four incomplete runs');
select is((select (v->'missions'->>'verified')::int from ar where name='overview'), 5, 'five server-verified completions in the period');
select is((select (v->'missions'->>'completion_rate')::numeric from ar where name='overview'), 8.3, 'mission completion rate = verified pairs / (learners x missions)');
select is((select (v->'missions'->>'avg_duration_seconds')::numeric from ar where name='overview'), 206.7, 'average completion time uses verified runs');
select is((select (v->'learning_progress'->>'avg_percent')::numeric from ar where name='overview'), 6.9, 'learning progress averages each learner once');
select ok((select jsonb_array_length(v->'trend') > 0 from ar where name='overview'), 'activity produces a daily trend');
select is((select sum((d->>'practice_runs')::int)::int from ar, jsonb_array_elements(v->'trend') d where name='overview'), 7, 'trend practice runs add up to recorded runs');
select ok((select (v->'homework'->>'applicable')::boolean and (v->'assessments'->>'applicable')::boolean from ar where name='overview'), 'every source applies without curriculum filters');

-- Class filter never mixes unrelated classes.
select is((select (v->'population'->>'enrolled')::int from ar where name='overview_c2'), 2, 'class filter restricts the population');
select is((select (v->'quizzes'->>'avg_percent')::numeric from ar where name='overview_c2'), 0.0, 'C2 quiz average excludes C1 attempts');
select is((select (v->'quizzes'->>'completion_rate')::numeric from ar where name='overview_c2'), 100.0, 'a learner''s single quiz attempt completes the quiz in every class');
select is((select (v->'assessments'->>'released')::int from ar where name='overview_c2'), 1, 'C2 sees only its own released result');
select is((select (v->'homework'->>'avg_percent')::numeric from ar where name='overview_c2'), 60.0, 'C2 homework average excludes C1 homework');
-- Curriculum filters: sources that cannot be positioned on the filter are excluded, not mixed.
select is((select (v->'quizzes'->>'submitted')::int from ar where name='overview_quiz'), 3, 'quiz filter keeps the quiz');
select ok((select not (v->'homework'->>'applicable')::boolean and v->'homework'->>'avg_percent' is null from ar where name='overview_quiz'), 'quiz filter marks homework as not applicable');
select ok((select not (v->'assessments'->>'applicable')::boolean and v->'assessments'->>'avg_percent' is null from ar where name='overview_quiz'), 'quiz filter marks assessments as not applicable');
select is((select (v->'missions'->>'runs')::int from ar where name='overview_coc2'), 0, 'COC filter excludes practice from other COCs');
select is((select v->'quizzes'->>'avg_percent' from ar where name='overview_coc2'), null, 'COC filter excludes quizzes from other COCs');
select is((select v->'filters'->>'coc_code' from ar where name='overview_coc2'), 'coc2', 'COC codes are normalized');

-- Class performance and comparison.
select is((select jsonb_array_length(v->'classes') from ar where name='classes'), 2, 'two owned classes are compared');
select is((select (c->>'quiz_avg')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 75.0, 'C1 quiz average');
select is((select (c->>'avg_score')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 66.3, 'C1 average score averages each learner once');
select is((select c->'highest'->>'name' from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 'Ana Analytics', 'C1 highest learner');
select is((select (c->'lowest'->>'score')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 50.0, 'C1 lowest learner score');
select is((select (c->>'assessment_competent_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 50.0, 'C1 competent rate');
select is((select (c->>'mission_completion_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 7.5, 'C1 mission completion rate');
select is((select (c->>'assignment_completion_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 50.0, 'C1 homework completion rate');
select is((select (c->>'progress_avg')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 6.3, 'C1 learning progress average');
select is((select (c->>'avg_score')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics B'), 36.7, 'C2 average score ignores L1 who has no scored C2 work');
select is((select (c->>'quiz_avg')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics B'), 0.0, 'C2 quiz average');
select is((select (v->'summary'->>'enrolled')::int from ar where name='classes'), 3, 'summary counts distinct learners');
select is((select (v->'summary'->>'avg_score')::numeric from ar where name='classes'), 56.4, 'summary average score averages each learner once');
select is((select (v->'summary'->>'quiz_avg')::numeric from ar where name='classes'), 50.0, 'summary quiz average across selected classes');

-- Learner status rules.
select is((select l->>'status' from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 'on_track', 'L1 is on track');
select is((select l->>'status' from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ben Analytics'), 'falling_behind', 'L2 is falling behind');
select ok((select l->'reasons' @> '[{"code":"inactive"}]' and l->'reasons' @> '[{"code":"below_class_median"}]'
  from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ben Analytics'), 'L2 reasons: 14 days inactive and below half of the class median');
select is((select l->>'status' from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Cara Analytics'), 'struggling', 'L3 is struggling');
select ok((select l->'reasons' @> '[{"code":"quiz_average_low"},{"code":"not_yet_competent"},{"code":"repeated_incomplete_runs"}]'
  from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Cara Analytics'), 'L3 reasons: quiz below 75 %, a not-yet-competent result, 3+ incomplete runs');
select is((select jsonb_array_length(l->'classes') from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 2, 'L1 lists both classes');
select is((select (l->'assessment'->>'released')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 2, 'L1 has two released results');
select is((select (l->>'practice_runs')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 4, 'L1 recorded runs');
select is((select (l->'assignments'->>'missing')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 1, 'L1 has one missing homework');
select is((select (v->'counts'->>'falling_behind')::int from ar where name='learners'), 1, 'status counts');
select is((select (v->'thresholds'->>'quiz_average_below')::numeric from ar where name='learners'), 75::numeric, 'documented quiz threshold');
select is((select jsonb_array_length(v->'learners') from ar where name='learner_l2_only'), 1, 'learner filter returns one learner');
select is((select v->'learners'->0->>'status' from ar where name='learner_l2_only'), 'falling_behind', 'class median ignores the learner filter');

-- Quiz analytics.
select is((select jsonb_array_length(v->'quizzes') from ar where name='quiz_list'), 1, 'only published quizzes are listed');
select is((select v->'quizzes'->0->>'title' from ar where name='quiz_list'), 'Analytics Quiz One', 'the published quiz is listed');
select is((select (v->>'participants')::int from ar where name='quiz_q1'), 3, 'three participants');
select is((select (v->>'eligible')::int from ar where name='quiz_q1'), 3, 'three eligible learners');
select is((select (v->>'average')::numeric from ar where name='quiz_q1'), 50.0, 'quiz average');
select is((select (v->>'highest')::numeric from ar where name='quiz_q1'), 100.0, 'quiz highest');
select is((select (v->>'lowest')::numeric from ar where name='quiz_q1'), 0.0, 'quiz lowest');
select is((select sum((b->>'count')::int)::int from ar, jsonb_array_elements(v->'distribution') b where name='quiz_q1'), 3, 'distribution buckets sum to participants');
select is((select jsonb_array_length(v->'distribution') from ar where name='quiz_q1'), 10, 'ten distribution buckets');
select is((select (b->>'count')::int from ar, jsonb_array_elements(v->'distribution') b where name='quiz_q1' and b->>'bucket'='90-100'), 1, 'a perfect score lands in 90-100');
select is((select (b->>'count')::int from ar, jsonb_array_elements(v->'distribution') b where name='quiz_q1' and b->>'bucket'='50-59'), 1, 'a 50 % score lands in 50-59');
select is((select (q->>'correct_rate')::numeric from ar, jsonb_array_elements(v->'per_question') q where name='quiz_q1' and q->>'code'='A7-ITEM-1'), 66.7, 'item one correctness');
select is((select (q->>'correct_rate')::numeric from ar, jsonb_array_elements(v->'per_question') q where name='quiz_q1' and q->>'code'='A7-ITEM-2'), 33.3, 'item two correctness');
select is((select jsonb_array_length(v->'results') from ar where name='quiz_q1'), 3, 'one result per learner');
select is((select v->'quiz'->>'status' from ar where name='quiz_q2'), 'draft', 'the unpublished quiz reports its draft status');
select is((select (v->>'participants')::int from ar where name='quiz_q2'), 0, 'the unpublished quiz has no counted participants');
select is((select v->'distribution' from ar where name='quiz_q2'), '[]'::jsonb, 'the unpublished quiz has no distribution');

-- Mission analytics.
select is((select sum((m->>'runs')::int)::int from ar, jsonb_array_elements(v->'missions') m where name='missions'), 7, 'mission rows add up to recorded runs');
select is((select (m->>'learners_attempted')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 2, 'coc1_m1 learners attempted');
select is((select (m->>'learners_verified')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 2, 'coc1_m1 learners verified');
select is((select (m->>'completion_rate')::numeric from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 66.7, 'coc1_m1 completion rate');
select is((select (m->>'avg_runs_per_learner')::numeric from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 2.0, 'coc1_m1 runs per learner with runs');
select is((select (m->>'avg_invalid_actions')::numeric from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 1.5, 'coc1_m1 invalid actions per run');
select is((select (m->>'learners_verified')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), 0, 'incomplete runs never count as completion');
select is((select (m->>'failed_runs')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), 3, 'coc1_m4 failed runs');
select is((select m->>'avg_duration_seconds' from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), null, 'no verified run gives a null completion time');
select is((select m->'module'->>'code' from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), 'LO1.2', 'missions carry their curriculum module');
select ok((select a->>'mission_code' = 'coc1_m2' and (a->>'attempts')::int = 4 and (a->>'released')::int = 3 and (a->>'competent')::int = 1
  and (a->>'not_yet_competent')::int = 2 and (a->>'pending')::int = 1 from ar, jsonb_array_elements(v->'assessments') a where name='missions'),
  'assessment attempts by mission come from recorded attempts');
select is((select jsonb_array_length(v->'missions') from ar where name='missions_m1'), 1, 'mission filter narrows to one mission');

-- Criterion analysis.
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-CRIT-A'), 100.0, 'criterion A percent');
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-CRIT-B'), 50.0, 'criterion B percent (latest released result per learner)');
select is((select (c->>'evaluated_learners')::int from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-CRIT-B'), 2, 'each learner counted once per criterion');
select is((select v->'strongest'->0->>'code' from ar where name='criteria'), 'A7-CRIT-A', 'strongest criterion');
select is((select v->'weakest'->0->>'code' from ar where name='criteria'), 'A7-CRIT-B', 'weakest criterion');

-- Learner profile (instructor view).
select is((select v->'learner'->>'student_id' from ar where name='profile_l1'), 'A7-001', 'profile header');
select is((select (v->'progress'->>'overall_percent')::numeric from ar where name='profile_l1'), 12.5, 'profile overall progress');
select is((select jsonb_array_length(v->'assessments') from ar where name='profile_l1'), 2, 'profile assessment results');
select ok((select jsonb_array_length(v->'timeline') >= 8 from ar where name='profile_l1'), 'profile activity timeline');
select is((select (v->'status'->>'status') from ar where name='profile_l1'), 'on_track', 'profile status');
select ok((select jsonb_array_length(v->'classes') = 2 and jsonb_array_length(v->'quizzes') = 1 from ar where name='options'), 'filter options list owned classes and published quizzes');

-- Learner-facing performance (released results only).
select is((select (v->'progress'->>'overall_percent')::numeric from ar where name='me_l1'), 12.5, 'learner overall progress');
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'progress'->'cocs') c where name='me_l1' and c->>'coc_code'='coc1'), 50.0, 'learner COC1 progress');
select ok((select (c->>'modules_completed')::int = 1 and (c->>'modules_total')::int = 3 from ar, jsonb_array_elements(v->'progress'->'cocs') c where name='me_l1' and c->>'coc_code'='coc1'), 'learner module completion counts');
select is((select count(*)::int from ar, jsonb_array_elements(v->'competency') c where name='me_l1' and c->>'outcome'='satisfied' and c->>'criterion' like 'Analytics criterion%'), 2, 'competency per released criterion with its label');
select is((select v->'scores'->'quizzes'->0->>'title' from ar where name='me_l1'), 'Analytics Quiz One', 'learner quiz score with title');
select is((select (v->'scores'->'homework'->0->>'score')::numeric from ar where name='me_l1'), 80::numeric, 'released homework score');
select is((select jsonb_array_length(v->'assessments') from ar where name='me_l1'), 2, 'released assessment results');
select is((select (v->'practice'->>'runs')::int from ar where name='me_l1'), 4, 'learner practice runs');
select is((select (b->>'best_seconds')::int from ar, jsonb_array_elements(v->'practice'->'best_times') b where name='me_l1' and b->>'mission_code'='coc1_m1'), 120, 'best verified time');
select is((select v->'assessments' from ar where name='me_l2'), '[]'::jsonb, 'unreleased results are not shown to the learner');
select is((select v->'competency' from ar where name='me_l2'), '[]'::jsonb, 'no competency entries without a released result');

select * from finish();
rollback;
