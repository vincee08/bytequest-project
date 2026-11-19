-- Slice A7: performance analytics (Objective 6). Rollback-only.
-- Fixtures are created inside this transaction with known expected values:
--   classes C1, C2 (instructor T1), C3 (instructor T2), C4 (T1, archived);
--   instructor T3 owns no class. L1 is enrolled in C1 and C2, L2 in C1, L3 in
--   C2, L4 in C3, L5 in C3 (enrolled after C3's homework and quiz deadlines).
-- Fixtures follow the real rules: practice completions use accepted contract
-- versions, a COC practice quiz is passed only after every COC module is
-- complete (slice A2 gate), homework follows submitted -> graded -> finalized
-- -> released (slice A4), instructor-release quizzes are scored from their
-- released finalization (slice A3), simulation criteria use the
-- simulation_condition operator and runs record step results (slice A1), and
-- A6 awards points from the same records.
-- Every function is called while impersonating the caller (RLS applies), the
-- JSON result is captured, and assertions run after `reset role`.
begin;
select plan(257);

-- Isolate the expected progress values from lessons published in the target
-- database (rolled back with everything else).
update public.curriculum_topics set archived_at = now() where archived_at is null;

create temporary table ax (
  admin_id uuid default gen_random_uuid(), t1 uuid default gen_random_uuid(),
  t2 uuid default gen_random_uuid(), t3 uuid default gen_random_uuid(),
  l1 uuid default gen_random_uuid(), l2 uuid default gen_random_uuid(),
  l3 uuid default gen_random_uuid(), l4 uuid default gen_random_uuid(), l5 uuid default gen_random_uuid(),
  c1 uuid default gen_random_uuid(), c2 uuid default gen_random_uuid(), c3 uuid default gen_random_uuid(),
  c4 uuid default gen_random_uuid(),
  source_id uuid, module_version_id uuid, activity_version_id uuid, rubric_id uuid,
  crit_a uuid default gen_random_uuid(), crit_b uuid default gen_random_uuid(),
  asg_c1 uuid default gen_random_uuid(), asg_c2 uuid default gen_random_uuid(),
  att_l1_a uuid default gen_random_uuid(), att_l1_b uuid default gen_random_uuid(),
  att_l2 uuid default gen_random_uuid(), att_l3 uuid default gen_random_uuid(), att_l3_b uuid default gen_random_uuid(),
  q1 uuid default gen_random_uuid(), q1v uuid default gen_random_uuid(),
  q1i1 uuid default gen_random_uuid(), q1i2 uuid default gen_random_uuid(),
  q2 uuid default gen_random_uuid(), q2v uuid default gen_random_uuid(), q2i1 uuid default gen_random_uuid(),
  q3 uuid default gen_random_uuid(), q3v uuid default gen_random_uuid(), q3i1 uuid default gen_random_uuid(),
  qa1_c1 uuid default gen_random_uuid(), qa1_c2 uuid default gen_random_uuid(), qa2_c1 uuid default gen_random_uuid(),
  qa3_c3 uuid default gen_random_uuid(),
  qt_l1 uuid default gen_random_uuid(), qt_l2 uuid default gen_random_uuid(),
  qt_l3 uuid default gen_random_uuid(), qt_l2_draft uuid default gen_random_uuid(),
  h1 uuid default gen_random_uuid(), h2 uuid default gen_random_uuid(), h3 uuid default gen_random_uuid(),
  h4 uuid default gen_random_uuid(), h5 uuid default gen_random_uuid(),
  gate_lesson uuid default gen_random_uuid(),
  q4 uuid default gen_random_uuid(), q4v uuid default gen_random_uuid(),
  q4i1 uuid default gen_random_uuid(), q4i2 uuid default gen_random_uuid(), qa4_c1 uuid default gen_random_uuid(),
  qt4_l1 uuid default gen_random_uuid(), qt4_l2 uuid default gen_random_uuid(),
  q5 uuid default gen_random_uuid(), q5v uuid default gen_random_uuid(),
  q5i1 uuid default gen_random_uuid(), q5i2 uuid default gen_random_uuid(), qa5_c1 uuid default gen_random_uuid(),
  qt5_l1 uuid default gen_random_uuid(),
  sim_av uuid, sim_rubric uuid, sim_crit uuid default gen_random_uuid(),
  sim_asg uuid default gen_random_uuid(), sim_att uuid default gen_random_uuid(),
  coc1_id uuid
);
insert into ax default values;
update ax set coc1_id = (select id from public.coc_modules where coc_code = 'coc1');
create temporary table ar (name text primary key, v jsonb);
grant select on ax to authenticated;
grant select, insert on ar to authenticated;

-- Fixture helpers: an evidence action, and a server-verified completion of the
-- mission's current (accepted) contract version.
create function pg_temp.a7_action(p_learner uuid, p_mission text) returns bigint language sql as $$
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, value, client_occurred_at)
  values (p_learner, 'a7-' || gen_random_uuid(), p_mission, p_mission || '_p1', 'object_inspected', '{}'::jsonb, now())
  returning id
$$;
create function pg_temp.a7_complete(p_learner uuid, p_mission text, p_at timestamptz) returns void language sql as $$
  insert into public.practice_mission_completions(learner_id, mission_id, contract_version, evidence_through_id, verified_at)
  select p_learner, c.mission_id, c.version, pg_temp.a7_action(p_learner, p_mission), p_at
  from public.practice_mission_contracts c where c.mission_id = p_mission
$$;

-- Identities (handle_new_user provisions the profiles).
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select u.id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',u.id||'@analytics-rollback.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',u.name),now(),now()
from ax cross join lateral (values
  (admin_id,'Analytics Admin'),(t1,'Analytics Teacher One'),(t2,'Analytics Teacher Two'),(t3,'Analytics Teacher Three'),
  (l1,'Ana Analytics'),(l2,'Ben Analytics'),(l3,'Cara Analytics'),(l4,'Dino Analytics'),(l5,'Eve Analytics')) u(id,name);
update public.profiles set role = 'admin' where user_id = (select admin_id from ax);
update public.profiles set role = 'instructor' where user_id in (select t1 from ax union all select t2 from ax union all select t3 from ax);
update public.profiles p set learner_id = s.sid from ax cross join lateral (values (l1,'A7-001'),(l2,'A7-002'),(l3,'A7-003'),(l4,'A7-004'),(l5,'A7-005')) s(id,sid) where p.user_id = s.id;

-- The admin overview covers every active class of the target database,
-- including classes that existed before this test (for example a seeded demo
-- class). Record that population before the fixture classes exist; the
-- fixtures must add exactly their own learners to it.
select set_config('request.jwt.claim.sub',(select admin_id::text from ax),true);
set local role authenticated;
insert into ar values ('admin_baseline', public.get_analytics_overview('{}'::jsonb));
reset role;

insert into public.classes(id,title,class_code,instructor_id,created_by)
select c1,'Analytics A','A7-'||left(c1::text,8),t1,t1 from ax union all
select c2,'Analytics B','A7-'||left(c2::text,8),t1,t1 from ax union all
select c3,'Analytics C','A7-'||left(c3::text,8),t2,t2 from ax;
insert into public.classes(id,title,class_code,instructor_id,created_by,status,archived_at,archived_by,archive_reason)
select c4,'Analytics Archived','A7-'||left(c4::text,8),t1,t1,'archived'::public.class_status,now()-interval '1 day',t1,'Term ended' from ax;
insert into public.class_memberships(class_id,learner_id,enrolled_by,enrolled_at)
select c1,l1,t1,now()-interval '60 days' from ax union all select c2,l1,t1,now()-interval '60 days' from ax union all
select c1,l2,t1,now()-interval '60 days' from ax union all select c2,l3,t1,now()-interval '60 days' from ax union all
select c3,l4,t2,now()-interval '60 days' from ax union all select c3,l5,t2,now()-interval '1 day' from ax union all
select c4,l1,t1,now()-interval '60 days' from ax;

-- T2's published quiz (assigned to C3, due 3 days ago) and homework (deadline
-- 2 days ago); nobody submitted. L5 joined C3 after both deadlines.
insert into public.quizzes(id,instructor_id,coc_module_id,title,topic,created_by)
select q3,t2,coc1_id,'Analytics Foreign Quiz','Hardware',t2 from ax;
insert into public.quiz_versions(id,quiz_id,version_number,status,created_by,published_by,published_at)
select q3v,q3,1,'published',t2,t2,now()-interval '10 days' from ax;
insert into public.quiz_items(id,quiz_version_id,item_code,item_type,prompt,options,correct_answer,review_status,reviewed_by,reviewed_at,order_index,created_by)
select q3i1,q3v,'A7-ITEM-F','true_false','Foreign item prompt','[]','"True"','approved',t2,now(),1,t2 from ax;
insert into public.quiz_assignments(id,class_id,quiz_version_id,assigned_by,created_at,due_at)
select qa3_c3,c3,q3v,t2,now()-interval '10 days',now()-interval '3 days' from ax;
insert into public.homework_assignments(id,class_id,instructor_id,title,instructions,status,deadline_at,published_at)
select h5,c3,t2,'Analytics Homework Five','Write the report.','published',now()-interval '2 days',now()-interval '10 days' from ax;

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
select is((select v->'homework'->>'avg_percent' from ar where name='zero_overview'), null, 'no released homework gives a null homework average');
select is((select v->'missions'->>'avg_duration_seconds' from ar where name='zero_overview'), null, 'no practice run gives a null duration');
select is((select (v->'missions'->>'runs')::int from ar where name='zero_overview'), 0, 'zero recorded runs');
select is((select v->'trend' from ar where name='zero_overview'), '[]'::jsonb, 'no activity gives an empty trend');
select is((select v->'evaluation'->'total' from ar where name='zero_overview'),
  '{"evaluate":0,"finalize":0,"release":0,"released":0}'::jsonb, 'no submitted work gives empty evaluation stages');
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
select throws_ok(format('select public.get_quiz_analytics(null, %L::jsonb)', jsonb_build_object('class_id',(select c3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'quiz analytics enforce class ownership');
select throws_ok(format('select public.get_mission_analytics(%L::jsonb)', jsonb_build_object('class_id',(select c3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'mission analytics enforce class ownership');
select throws_ok(format('select public.get_criteria_analytics(%L::jsonb)', jsonb_build_object('class_id',(select c3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'criteria analytics enforce class ownership');
select throws_ok(format('select public.get_quiz_analytics(%L::uuid, ''{}''::jsonb)', (select q3 from ax)),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'an instructor cannot open another instructor''s quiz');
select throws_ok(format('select public.get_quiz_analytics(null, %L::jsonb)', jsonb_build_object('quiz_id',(select q3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'a foreign quiz filter is denied on quiz analytics');
select throws_ok(format('select public.get_mission_analytics(%L::jsonb)', jsonb_build_object('quiz_id',(select q3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'a foreign quiz filter is denied on mission analytics');
select throws_ok(format('select public.get_criteria_analytics(%L::jsonb)', jsonb_build_object('quiz_id',(select q3 from ax))),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'a foreign quiz filter is denied on criteria analytics');
select throws_ok($$select public.get_mission_analytics('{"mission_code":"coc1_m9"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'mission analytics reject unknown mission codes');
select throws_ok($$select public.get_criteria_analytics('{"mission_code":"coc5_m1"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'criteria analytics reject unknown mission codes');
select throws_ok($$select public.get_quiz_analytics(null, '{"mission_code":"coc1_m9"}'::jsonb)$$, '22023', 'ANALYTICS_FILTER_INVALID', 'quiz analytics reject unknown mission codes');
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
insert into ar values ('archived_class', public.get_analytics_overview(jsonb_build_object('class_id',(select c4 from ax))));
select set_config('request.jwt.claim.sub',(select admin_id::text from ax),true);
insert into ar values ('admin_c3', public.get_analytics_overview(jsonb_build_object('class_id',(select c3 from ax)))),
  ('admin_c3_quizzes', public.get_quiz_analytics(null, jsonb_build_object('class_id',(select c3 from ax)))),
  ('admin_c3_missions', public.get_mission_analytics(jsonb_build_object('class_id',(select c3 from ax)))),
  ('admin_c3_criteria', public.get_criteria_analytics(jsonb_build_object('class_id',(select c3 from ax))));
select throws_ok(format('select public.get_analytics_overview(%L::jsonb)', jsonb_build_object('class_id', gen_random_uuid())),
  '42501', 'ANALYTICS_SCOPE_DENIED', 'admins get a scope error for a class that does not exist');
select set_config('request.jwt.claim.sub',(select l1::text from ax),true);
select throws_ok($$select public.get_analytics_overview('{}'::jsonb)$$, '42501', 'ANALYTICS_ACCESS_DENIED', 'learners cannot read staff analytics');
reset role;
select ok((select (v->'population'->>'enrolled')::int = 0 and v->'classes' = '[]'::jsonb from ar where name='archived_class'),
  'an own archived class is out of analytics scope (empty, not an error)');
select is((select (v->'population'->>'enrolled')::int from ar where name='admin_c3'), 2, 'admins may analyse any instructor''s class');
select ok((select bool_and(v->'filters'->>'class_id' = (select c3::text from ax)) from ar
  where name in ('admin_c3_quizzes','admin_c3_missions','admin_c3_criteria')) and (select count(*) = 3 from ar
  where name in ('admin_c3_quizzes','admin_c3_missions','admin_c3_criteria')),
  'admins may scope quiz, mission and criteria analytics to any instructor''s class');
select ok((select v->'quizzes' @> jsonb_build_array(jsonb_build_object('id', (select q3 from ax))) from ar where name='admin_c3_quizzes'),
  'admin quiz analytics list the quiz that the other instructor cannot open');
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
select ok(has_function_privilege('authenticated', 'private.analytics_homework_facts(jsonb)', 'execute')
  and not has_function_privilege('anon', 'private.analytics_learner_metrics(jsonb)', 'execute'), 'recreated helpers keep their grants');
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
select att_l3,l3,c2,asg_c2,activity_version_id,rubric_id,source_id,'released'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '4 days',now()-interval '4 days',now()-interval '4 days',now()-interval '4 days',now()-interval '4 days' from ax union all
select att_l3_b,l3,c2,asg_c2,activity_version_id,rubric_id,source_id,'under_review'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '1 day',now()-interval '1 day',now()-interval '1 day',null,null from ax;
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
-- A3 quizzes, submitted 45 days ago (outside the default 30-day period, so
-- every expected value above is unchanged; asserted with a 60-day period).
-- Q4: instructor_release, one objective item (1 point) and one scenario essay
-- (rubric E1 Diagnosis 4 + E2 Safety 4 points), mapped to module LO1.1.
--   L1: released, finalized 1 + 7 = 8 of 9 points (88.9 %). Current essay
--       score: the latest evaluated_at, then the highest sequence (two rows
--       share a timestamp; a later-inserted row carries an older time).
--   L2: evaluated, not released: pending evaluation, never averaged.
-- Q5: immediate, weighted items (1 and 3 points). L1 answered only the
--   3-point item correctly: 3 of 4 points = 75 % (1 of 2 answers would be 50 %).
-- ===================================================================
insert into public.quizzes(id,instructor_id,coc_module_id,title,topic,created_by)
select q4,t1,coc1_id,'Analytics Essay Quiz','Diagnosis',t1 from ax union all
select q5,t1,coc1_id,'Analytics Weighted Quiz','Hardware',t1 from ax;
insert into public.quiz_modules(quiz_id,module_id)
select q4,(select m.id from public.curriculum_modules m where m.coc_code = 'coc1' and m.code = 'LO1.1') from ax;
insert into public.quiz_versions(id,quiz_id,version_number,status,created_by,published_by,published_at,result_release_mode)
select q4v,q4,1,'published'::public.content_version_status,t1,t1,now()-interval '50 days','instructor_release' from ax union all
select q5v,q5,1,'published'::public.content_version_status,t1,t1,now()-interval '50 days','immediate' from ax;
insert into public.quiz_items(id,quiz_version_id,item_code,item_type,prompt,options,correct_answer,review_status,reviewed_by,reviewed_at,order_index,created_by,points,scenario,rubric)
select q4i1,q4v,'A7-ESSAY-OBJ','true_false'::public.quiz_item_type,'Analytics objective prompt','[]'::jsonb,'"True"'::jsonb,
  'approved'::public.quiz_item_review_status,t1,now(),1,t1,1::numeric,null::text,null::jsonb from ax union all
select q4i2,q4v,'A7-ESSAY','scenario_essay'::public.quiz_item_type,'Explain your diagnosis','[]'::jsonb,'"Reseat the memory"'::jsonb,
  'approved'::public.quiz_item_review_status,t1,now(),2,t1,8::numeric,'A workstation does not power on after a memory upgrade.',
  '[{"id":"E1","criterion":"Diagnosis","description":"","max_points":4},{"id":"E2","criterion":"Safety","description":"","max_points":4}]'::jsonb from ax union all
select q5i1,q5v,'A7-WEIGHT-1','true_false'::public.quiz_item_type,'Weighted item one prompt','[]'::jsonb,'"True"'::jsonb,
  'approved'::public.quiz_item_review_status,t1,now(),1,t1,1::numeric,null::text,null::jsonb from ax union all
select q5i2,q5v,'A7-WEIGHT-3','true_false'::public.quiz_item_type,'Weighted item three prompt','[]'::jsonb,'"True"'::jsonb,
  'approved'::public.quiz_item_review_status,t1,now(),2,t1,3::numeric,null::text,null::jsonb from ax;
insert into public.quiz_assignments(id,class_id,quiz_version_id,assigned_by,created_at,due_at)
select qa4_c1,c1,q4v,t1,now()-interval '50 days',now()-interval '40 days' from ax union all
select qa5_c1,c1,q5v,t1,now()-interval '50 days',now()-interval '40 days' from ax;
insert into public.quiz_attempts(id,learner_id,class_id,quiz_assignment_id,quiz_version_id,status,client_start_key,submission_key,started_at,submitted_at,completed_at,evaluation_status)
select qt4_l1,l1,c1,qa4_c1,q4v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '45 days',now()-interval '45 days',now()-interval '45 days','released' from ax union all
select qt4_l2,l2,c1,qa4_c1,q4v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '45 days',now()-interval '45 days',now()-interval '45 days','evaluated' from ax union all
select qt5_l1,l1,c1,qa5_c1,q5v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '45 days',now()-interval '45 days',now()-interval '45 days','not_required' from ax;
insert into public.quiz_answers(quiz_attempt_id,quiz_item_id,quiz_version_id,answer,is_correct)
select qt4_l1,q4i1,q4v,'"True"'::jsonb,true from ax union all
select qt4_l1,q4i2,q4v,'"The memory is not seated; power off and reseat it."'::jsonb,null::boolean from ax union all
select qt4_l2,q4i1,q4v,'"False"'::jsonb,false from ax union all
select qt4_l2,q4i2,q4v,'"Replace the power supply."'::jsonb,null::boolean from ax union all
select qt5_l1,q5i1,q5v,'"False"'::jsonb,false from ax union all
select qt5_l1,q5i2,q5v,'"True"'::jsonb,true from ax;
insert into public.quiz_results(quiz_attempt_id,correct_count,question_count,item_results,evaluated_at,objective_points,max_points)
select qt4_l1,1,2,'[]'::jsonb,now()-interval '45 days',1,9 from ax union all
select qt4_l2,0,2,'[]'::jsonb,now()-interval '45 days',0,9 from ax union all
select qt5_l1,1,2,'[]'::jsonb,now()-interval '45 days',3,4 from ax;
insert into public.quiz_essay_scores(attempt_id,item_id,criterion_scores,total,evaluated_by,evaluated_at)
select qt4_l1,q4i2,'{"E1":1,"E2":1}'::jsonb,2,t1,now()-interval '44 days' from ax;
insert into public.quiz_essay_scores(attempt_id,item_id,criterion_scores,total,evaluated_by,evaluated_at)
select qt4_l1,q4i2,'{"E1":2,"E2":2}'::jsonb,4,t1,now()-interval '43 days' from ax;
insert into public.quiz_essay_scores(attempt_id,item_id,criterion_scores,total,evaluated_by,evaluated_at)
select qt4_l1,q4i2,'{"E1":4,"E2":3}'::jsonb,7,t1,now()-interval '43 days' from ax;
insert into public.quiz_essay_scores(attempt_id,item_id,criterion_scores,total,evaluated_by,evaluated_at)
select qt4_l1,q4i2,'{"E1":0,"E2":0}'::jsonb,0,t1,now()-interval '44 days 12 hours' from ax;
insert into public.quiz_essay_scores(attempt_id,item_id,criterion_scores,total,evaluated_by,evaluated_at)
select qt4_l2,q4i2,'{"E1":1,"E2":0}'::jsonb,1,t1,now()-interval '44 days' from ax;
insert into public.quiz_result_finalizations(attempt_id,objective_points,essay_points,total_points,max_points,percent,finalized_by,finalized_at,released_by,released_at)
select qt4_l1,1,7,8,9,88.9,t1,now()-interval '42 days',t1,now()-interval '41 days' from ax;

-- ===================================================================
-- A1 simulation assessment: L3 (C2), released 45 days ago; one
-- simulation_condition criterion on phase coc1_m2_p2, not satisfied.
-- ===================================================================
with av as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select (select id from public.missions where mission_code = 'coc1_m2'), module_version_id,
    (select max(version_number) from public.activity_versions where mission_id = (select id from public.missions where mission_code = 'coc1_m2')) + 1,
    'Analytics simulation assessment','assessment','{"mission_id":"coc1_m2","mode":"assessment"}','{"engine":"simulation_replay_v1"}',
    'published',admin_id,admin_id,now()-interval '50 days' from ax
  returning id)
update ax set sim_av = av.id from av;
with rv as (
  insert into public.rubric_versions(activity_version_id,tesda_source_id,version_number,title,status,scoring_method,passing_rule,created_by,approved_by,approved_at)
  select sim_av,source_id,1,'Analytics simulation rubric','approved','TEST_ONLY_POINTS','{"status":"APPROVED","method":"threshold","threshold":75}',admin_id,admin_id,now() from ax
  returning id)
update ax set sim_rubric = rv.id from rv;
insert into public.rubric_criteria(id,rubric_version_id,criterion_code,title,source_trace,evidence_rule,scoring_rule,max_value,order_index)
select sim_crit,sim_rubric,'A7-SIM-C3','CPU seated in the correct orientation with the lever closed','TEST_ONLY',
  '{"operator":"simulation_condition","phase_ids":["coc1_m2_p2"],"conditions":[{"path":"placed.cpu","value":"cpu_socket"}],"counted_targets":["item:cpu"],"max_incorrect":0}'::jsonb,
  '{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0}'::jsonb,1,1 from ax;
insert into public.assignments(id,class_id,activity_version_id,rubric_version_id,assignment_type,title,assigned_by)
select sim_asg,c2,sim_av,sim_rubric,'assessment'::public.assignment_type,'Analytics simulation assessment',t1 from ax;
insert into public.attempts(id,learner_id,class_id,assignment_id,activity_version_id,rubric_version_id,tesda_source_id,status,client_start_key,submission_key,started_at,submitted_at,evaluated_at,finalized_at,released_at)
select sim_att,l3,c2,sim_asg,sim_av,sim_rubric,source_id,'released'::public.attempt_status,gen_random_uuid(),gen_random_uuid(),
  now()-interval '45 days',now()-interval '45 days',now()-interval '45 days',now()-interval '45 days',now()-interval '45 days' from ax;
insert into public.score_revisions(attempt_id,revision_number,revision_type,actor_id,actor_role,tesda_source_id,rubric_version_id,total_value,max_value,percentage,outcome,criterion_values)
select sim_att,1,'instructor_final'::public.score_revision_type,t1,'instructor'::public.user_role,source_id,sim_rubric,0,1,0,'not_yet_competent'::public.evaluation_outcome,
  jsonb_build_array(jsonb_build_object('criterion_id',sim_crit,'observation','not_satisfied','score_value',0)) from ax;
insert into public.result_releases(attempt_id,score_revision_id,release_number,released_by,released_at,is_current)
select sim_att,(select sr.id from public.score_revisions sr where sr.attempt_id = ax.sim_att),1,t1,now()-interval '45 days',true from ax;

-- ===================================================================
-- Homework (A4 lifecycle). H1 (C1, COC1 / coc1_m2, max 50, two criteria):
-- L1 released 40/50, L2 missing. H2 (C2): L3 released 60 late, L1 missing.
-- H3 (C1, due in 3 days, max 20): L1 graded 18 (pending). H4 (C2, due in 3
-- days): L3 finalized 70 (pending), L1 submitted (awaiting grading).
-- ===================================================================
insert into public.homework_assignments(id,class_id,instructor_id,title,instructions,status,deadline_at,published_at,max_score,criteria,coc_module_id,mission_code)
select h1,c1,t1,'Analytics Homework One','Write the report.','published',now()-interval '2 days',now()-interval '10 days',50,
  '[{"id":"A7-HW-C1","criterion":"Report structure","max_points":30},{"id":"A7-HW-C2","criterion":"Diagram accuracy","max_points":20}]'::jsonb,
  coc1_id,'coc1_m2' from ax;
insert into public.homework_assignments(id,class_id,instructor_id,title,instructions,status,deadline_at,published_at,max_score)
select h2,c2,t1,'Analytics Homework Two','Write the report.','published',now()-interval '5 days',now()-interval '10 days',100 from ax union all
select h3,c1,t1,'Analytics Homework Three','Write the checklist.','published',now()+interval '3 days',now()-interval '4 days',20 from ax union all
select h4,c2,t1,'Analytics Homework Four','Write the checklist.','published',now()+interval '3 days',now()-interval '4 days',100 from ax;
insert into public.homework_submissions(assignment_id,learner_id,answer,submitted_at,effective_deadline_at,deadline_revision,status,score,criterion_scores,graded_at,graded_by,finalized_at,finalized_by,released_at,released_by)
select h1,l1,'Report',now()-interval '3 days',now()-interval '2 days',1,'released',40,'{"A7-HW-C1":25,"A7-HW-C2":15}'::jsonb,
  now()-interval '2 days',t1,now()-interval '1 day',t1,now()-interval '1 day',t1 from ax union all
select h2,l3,'Report',now()-interval '3 days',now()-interval '5 days',1,'released',60,null::jsonb,
  now()-interval '2 days',t1,now()-interval '1 day',t1,now()-interval '1 day',t1 from ax union all
select h3,l1,'Checklist',now()-interval '1 day',now()+interval '3 days',1,'graded',18,null::jsonb,
  now()-interval '12 hours',t1,null,null,null,null from ax union all
select h4,l3,'Checklist',now()-interval '2 days',now()+interval '3 days',1,'finalized',70,null::jsonb,
  now()-interval '1 day',t1,now()-interval '12 hours',t1,null,null from ax union all
select h4,l1,'Checklist',now()-interval '1 day',now()+interval '3 days',1,'submitted',null,null::jsonb,
  null,null,null,null,null,null from ax;

-- ===================================================================
-- Practice: server-verified completions (accepted contract versions) and
-- recorded runs. L1 verified coc1_m3 40 days ago (outside the period).
-- ===================================================================
select pg_temp.a7_complete(l1,'coc1_m1',now()-interval '6 days') from ax;
select pg_temp.a7_complete(l1,'coc1_m2',now()-interval '5 days') from ax;
select pg_temp.a7_complete(l1,'coc1_m3',now()-interval '40 days') from ax;
select pg_temp.a7_complete(l3,'coc1_m1',now()-interval '6 days') from ax;
select pg_temp.a7_complete(l3,'coc1_m5',now()-interval '5 days') from ax;
-- L3's coc1_m4 runs record step results (A1): step 2 is reached late or
-- fixed (2, 1 and 1 incorrect attempts), steps 3 and 4 are never completed.
insert into public.practice_mission_runs(learner_id,mission_id,contract_version,run_number,started_at,ended_at,duration_seconds,action_count,invalid_count,correction_count,outcome,created_at,step_results)
select l1,'coc1_m1','v',1,now()-interval '7 days',now()-interval '7 days',90,8,3,1,'incomplete',now()-interval '7 days','{}'::jsonb from ax union all
select l1,'coc1_m1','v',2,now()-interval '6 days',now()-interval '6 days',120,6,0,0,'verified',now()-interval '6 days','{}'::jsonb from ax union all
select l1,'coc1_m2','v',1,now()-interval '5 days',now()-interval '5 days',200,9,0,0,'verified',now()-interval '5 days','{}'::jsonb from ax union all
select l1,'coc1_m3','v',1,now()-interval '40 days',now()-interval '40 days',300,12,0,0,'verified',now()-interval '40 days','{}'::jsonb from ax union all
select l3,'coc1_m4','v',1,now()-interval '3 days',now()-interval '3 days',60,5,2,0,'incomplete',now()-interval '3 days',
  '{"coc1_m4_p1":{"done":true,"invalid":0,"failed_checks":0},"coc1_m4_p2":{"done":false,"invalid":2,"failed_checks":0},"coc1_m4_p3":{"done":false,"invalid":0,"failed_checks":0},"coc1_m4_p4":{"done":false,"invalid":0,"failed_checks":0}}'::jsonb from ax union all
select l3,'coc1_m4','v',2,now()-interval '2 days',now()-interval '2 days',70,5,2,0,'incomplete',now()-interval '2 days',
  '{"coc1_m4_p1":{"done":true,"invalid":0,"failed_checks":0},"coc1_m4_p2":{"done":true,"invalid":1,"failed_checks":0},"coc1_m4_p3":{"done":false,"invalid":0,"failed_checks":0},"coc1_m4_p4":{"done":false,"invalid":0,"failed_checks":0}}'::jsonb from ax union all
select l3,'coc1_m4','v',3,now()-interval '1 day',now()-interval '1 day',80,5,2,0,'incomplete',now()-interval '1 day',
  '{"coc1_m4_p1":{"done":true,"invalid":0,"failed_checks":0},"coc1_m4_p2":{"done":true,"invalid":0,"failed_checks":1},"coc1_m4_p3":{"done":false,"invalid":1,"failed_checks":0},"coc1_m4_p4":{"done":false,"invalid":0,"failed_checks":0}}'::jsonb from ax union all
select l4,'coc1_m2','v',1,now()-interval '2 days',now()-interval '2 days',100,7,0,0,'verified',now()-interval '2 days','{}'::jsonb from ax;
-- L4 (T2's learner) completes every COC1 module, then passes the COC1 practice
-- quiz: the A2 gate (every module of the COC complete) is satisfied, not bypassed.
-- A lesson published in LO1.4 beforehand keeps that module, and so the gate,
-- open after all five missions are verified until L4 completes the lesson
-- too. It is archived again after the quiz so the progress totals asserted
-- below stay lesson-free (module completion is kept once recorded, slice A2).
insert into public.curriculum_topics(id, module_id, sequence_order)
select ax.gate_lesson, m.id, 1 + (select count(*) from public.curriculum_topics t where t.module_id = m.id)
from ax, public.curriculum_modules m where m.coc_code = 'coc1' and m.code = 'LO1.4';
insert into public.curriculum_topic_revisions(topic_id, revision_number, title, body_markdown, status, published_at)
select gate_lesson, 1, 'Analytics gate lesson', 'Fixture lesson body.', 'published', now()-interval '21 days' from ax;
select pg_temp.a7_complete(l4, m.mission_code, now()-interval '20 days')
from ax cross join (values ('coc1_m1'),('coc1_m2'),('coc1_m3'),('coc1_m4'),('coc1_m5')) m(mission_code);
select throws_ok(format($q$insert into public.practice_quiz_attempts(learner_id,coc_code,status,questions,answers,score,passed,submitted_at)
  values (%L,'coc1','submitted',
    '[{"id":"q1","answer":0},{"id":"q2","answer":0},{"id":"q3","answer":0},{"id":"q4","answer":0},{"id":"q5","answer":0}]'::jsonb,
    '{"q1":0,"q2":0,"q3":0,"q4":0,"q5":0}'::jsonb,5,true,now())$q$, (select l4 from ax)),
  '22023', 'PRACTICAL_COMPLETION_REQUIRED', 'fixture: the A2 gate refuses the practice quiz while a published COC1 lesson is incomplete');
insert into public.learner_topic_progress(learner_id, topic_id, revision_id, completed_at)
select ax.l4, t.id, (select r.id from public.curriculum_topic_revisions r where r.topic_id = t.id and r.status = 'published'
  order by r.revision_number desc limit 1), now()-interval '20 days'
from ax, public.curriculum_topics t join public.curriculum_modules m on m.id = t.module_id
where m.coc_code = 'coc1' and t.archived_at is null
  and exists (select 1 from public.curriculum_topic_revisions r where r.topic_id = t.id and r.status = 'published');
select ok((select bool_and(s.completed) from ax, public.learner_module_states(ax.l4, 'coc1') s),
  'fixture: every COC1 module of L4 is complete before the practice quiz');
with pq as (
  insert into public.practice_quiz_attempts(learner_id,coc_code,status,questions,answers,score,passed,submitted_at)
  select l4,'coc1','submitted',
    '[{"id":"q1","answer":0},{"id":"q2","answer":0},{"id":"q3","answer":0},{"id":"q4","answer":0},{"id":"q5","answer":0}]'::jsonb,
    '{"q1":0,"q2":0,"q3":0,"q4":0,"q5":0}'::jsonb,5,true,now()-interval '1 day' from ax returning id, learner_id)
insert into public.practice_coc_progress(learner_id,coc_code,completed_at,quiz_attempt_id) select learner_id,'coc1',now()-interval '1 day',id from pq;
update public.curriculum_topics set archived_at = now() where id = (select gate_lesson from ax);
-- A6 awards points from the fixture records through its own triggers; one
-- explicit award 45 days ago lies outside the default period.
insert into public.learner_point_events(learner_id,event_type,source_id,points,detail,awarded_at)
select l2,'topic_completed','a7-old-topic',10,'Rollback fixture',now()-interval '45 days' from ax;

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
  ('overview_coc1', public.get_analytics_overview('{"coc_code":"coc1"}'::jsonb)),
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
  ('options', public.get_analytics_filter_options()),
  ('overview_q4_60', public.get_analytics_overview(jsonb_build_object('quiz_id',(select q4 from ax),'from',now()-interval '60 days'))),
  ('overview_lo11_60', public.get_analytics_overview(jsonb_build_object('module_id',
    (select m.id from public.curriculum_modules m where m.coc_code = 'coc1' and m.code = 'LO1.1'),'from',now()-interval '60 days'))),
  ('overview_m4', public.get_analytics_overview('{"mission_code":"coc1_m4"}'::jsonb)),
  ('quiz_q4_60', public.get_quiz_analytics((select q4 from ax),jsonb_build_object('from',now()-interval '60 days'))),
  ('quiz_q5_60', public.get_quiz_analytics((select q5 from ax),jsonb_build_object('from',now()-interval '60 days'))),
  ('learners_60', public.get_learner_performance(jsonb_build_object('from',now()-interval '60 days'))),
  ('criteria_60', public.get_criteria_analytics(jsonb_build_object('from',now()-interval '60 days'))),
  ('profile_l3_60', public.get_learner_profile_analytics((select l3 from ax),jsonb_build_object('from',now()-interval '60 days')));
select set_config('request.jwt.claim.sub',(select t2::text from ax),true);
insert into ar values
  ('overview_t2', public.get_analytics_overview('{}'::jsonb)),
  ('missions_t2', public.get_mission_analytics('{}'::jsonb));
select set_config('request.jwt.claim.sub',(select admin_id::text from ax),true);
insert into ar values
  ('overview_admin', public.get_analytics_overview('{}'::jsonb)),
  ('quiz_q1_admin', public.get_quiz_analytics((select q1 from ax),'{}'::jsonb));
select set_config('request.jwt.claim.sub',(select l1::text from ax),true);
insert into ar values ('me_l1', public.get_my_performance());
select set_config('request.jwt.claim.sub',(select l2::text from ax),true);
insert into ar values ('me_l2', public.get_my_performance());
reset role;

-- Overview: population and accuracy.
select is((select (v->'population'->>'enrolled')::int from ar where name='overview'), 3, 'population counts L1 once across C1 and C2');
select is((select (v->'population'->>'active_in_period')::int from ar where name='overview'), 3, 'three learners have activity in the period');
select is((select (v->'population'->>'completed')::int from ar where name='overview'), 0, 'nobody completed every required item');
select is((select (v->'population'->>'enrolled')::int from ar where name='overview_admin'),
  (select (v->'population'->>'enrolled')::int from ar where name='admin_baseline') + 5, 'admin overview covers every active class');
select is((select (v->>'participants')::int from ar where name='quiz_q1_admin'), 3, 'admins can analyse any quiz');
select is((select (v->'population'->>'enrolled')::int from ar where name='overview_t2'), 2, 'another instructor sees only their own learners');
select is((select v->'assessments'->>'avg_percent' from ar where name='overview_t2'), null, 'another instructor sees no foreign assessment results');
select is((select (v->'assessments'->>'submitted')::int from ar where name='overview'), 5, 'five assessment attempts were submitted');
select is((select (v->'assessments'->>'released')::int from ar where name='overview'), 3, 'three results are released');
select is((select (v->'assessments'->>'pending_release')::int from ar where name='overview'), 2, 'evaluated and under-review attempts count as pending');
select is((select (v->'assessments'->>'avg_percent')::numeric from ar where name='overview'), 66.7, 'pending results are excluded from the assessment average');
select is((select (v->'assessments'->>'competent_rate')::numeric from ar where name='overview'), 33.3, 'competent rate uses released results only');
select is((select v->'evaluation'->'technical' from ar where name='overview'),
  '{"evaluate":1,"finalize":1,"release":0,"released":3}'::jsonb, 'technical attempts by Evaluate / Finalize / Release stage (under_review = Finalize)');
select is((select v->'evaluation'->'homework' from ar where name='overview'),
  '{"evaluate":1,"finalize":1,"release":1,"released":2}'::jsonb, 'homework by Evaluate / Finalize / Release stage');
select is((select v->'evaluation'->'total' from ar where name='overview'),
  '{"evaluate":2,"finalize":2,"release":1,"released":5}'::jsonb, 'evaluation stage totals');
select is((select (v->'quizzes'->>'submitted')::int from ar where name='overview'), 3, 'only published quiz submissions are counted');
select is((select (v->'quizzes'->>'avg_percent')::numeric from ar where name='overview'), 50.0, 'the unpublished quiz result is excluded from the quiz average');
select is((select (v->'quizzes'->>'eligible')::int from ar where name='overview'), 3, 'quiz eligibility counts each learner once per quiz');
select is((select (v->'quizzes'->>'completion_rate')::numeric from ar where name='overview'), 100.0, 'every eligible learner completed the published quiz');
select is((select (v->'homework'->>'submitted')::int from ar where name='overview'), 5, 'five homework submissions in the period');
select is((select (v->'homework'->>'released')::int from ar where name='overview'), 2, 'two homework grades are released');
select is((select (v->'homework'->>'pending_evaluation')::int from ar where name='overview'), 3, 'submitted, graded and finalized homework is pending evaluation');
select is((select (v->'homework'->>'missing')::int from ar where name='overview'), 2, 'two past-deadline homework items are missing');
select is((select (v->'homework'->>'late')::int from ar where name='overview'), 1, 'one late homework submission');
select is((select (v->'homework'->>'avg_percent')::numeric from ar where name='overview'), 70.0,
  'homework average uses released grades as a share of max_score; graded and finalized grades are excluded');
select is((select (v->'homework'->>'completion_rate')::numeric from ar where name='overview'), 62.5, 'homework completion = submitted / eligible pairs');
select is((select (v->'missions'->>'runs')::int from ar where name='overview'), 6, 'mission attempts equal the recorded practice runs in the period');
select is((select (v->'missions'->>'successful_runs')::int from ar where name='overview'), 2, 'two verified runs');
select is((select (v->'missions'->>'failed_runs')::int from ar where name='overview'), 4, 'four incomplete runs');
select is((select (v->'missions'->>'verified')::int from ar where name='overview'), 4, 'four server-verified completions in the period');
select is((select (v->'missions'->>'completion_rate')::numeric from ar where name='overview'), 8.3, 'mission completion to date = verified pairs / (learners x missions)');
select is((select (v->'missions'->>'avg_duration_seconds')::numeric from ar where name='overview'), 160.0, 'average completion time uses verified runs in the period');
select is((select (v->'learning_progress'->>'avg_percent')::numeric from ar where name='overview'), 6.9, 'learning progress averages each learner once');
select ok((select jsonb_array_length(v->'trend') > 0 from ar where name='overview'), 'activity produces a daily trend');
select is((select sum((d->>'practice_runs')::int)::int from ar, jsonb_array_elements(v->'trend') d where name='overview'), 6, 'trend practice runs add up to recorded runs');
select ok((select (v->'homework'->>'applicable')::boolean and (v->'assessments'->>'applicable')::boolean from ar where name='overview'), 'every source applies without curriculum filters');

-- Enrolment-aware eligibility (T2: L5 joined C3 after the deadlines).
select is((select (v->'homework'->>'missing')::int from ar where name='overview_t2'), 1, 'a learner enrolled after the deadline is not counted as missing homework');
select is((select (v->'homework'->>'eligible')::int from ar where name='overview_t2'), 1, 'a learner enrolled after the deadline is not eligible for that homework');
select is((select (v->'quizzes'->>'eligible')::int from ar where name='overview_t2'), 1, 'a learner enrolled after the quiz closed is not eligible');
select is((select (v->'quizzes'->>'completion_rate')::numeric from ar where name='overview_t2'), 0.0, 'the eligible learner has not completed the quiz');

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
select is((select (v->'homework'->>'submitted')::int from ar where name='overview_coc1'), 1, 'COC filter keeps only homework linked to that COC');
select is((select (v->'homework'->>'avg_percent')::numeric from ar where name='overview_coc1'), 80.0, 'COC1 homework average (released 40 / 50)');
select is((select (v->'homework'->>'missing')::int from ar where name='overview_coc1'), 1, 'COC1 missing homework');
select is((select (v->'missions'->>'runs')::int from ar where name='overview_coc2'), 0, 'COC filter excludes practice from other COCs');
select is((select v->'quizzes'->>'avg_percent' from ar where name='overview_coc2'), null, 'COC filter excludes quizzes from other COCs');
select is((select (v->'homework'->>'submitted')::int from ar where name='overview_coc2'), 0, 'unlinked homework is excluded under a COC filter');
select is((select v->'filters'->>'coc_code' from ar where name='overview_coc2'), 'coc2', 'COC codes are normalized');

-- Class performance and comparison.
select is((select jsonb_array_length(v->'classes') from ar where name='classes'), 2, 'two active owned classes are compared (the archived class is excluded)');
select is((select (c->>'quiz_avg')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 75.0, 'C1 quiz average');
select is((select (c->>'avg_score')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 66.3, 'C1 average score averages each learner once (unreleased grades excluded)');
select is((select c->'highest'->>'name' from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 'Ana Analytics', 'C1 highest learner');
select is((select (c->'lowest'->>'score')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 50.0, 'C1 lowest learner score');
select is((select (c->>'assessment_competent_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 50.0, 'C1 competent rate');
select is((select (c->>'mission_completion_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 7.5, 'C1 mission completion rate');
select is((select (c->>'assignment_completion_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 50.0, 'C1 homework completion rate');
select is((select (c->>'assignment_completion_rate')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics B'), 75.0, 'C2 homework completion rate');
select is((select (c->>'progress_avg')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics A'), 6.3, 'C1 learning progress average');
select is((select (c->>'avg_score')::numeric from ar, jsonb_array_elements(v->'classes') c where name='classes' and c->>'title'='Analytics B'), 36.7, 'C2 average score ignores L1 who has no released C2 grade');
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
select is((select jsonb_array_length(l->'classes') from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 2, 'L1 lists both active classes');
select is((select (l->'assessment'->>'released')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 2, 'L1 has two released results');
select is((select (l->'assessment'->>'pending')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Cara Analytics'), 1, 'L3 under-review attempt is pending');
select is((select (l->>'practice_runs')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 3, 'L1 recorded runs in the period');
select is((select (l->'assignments'->>'missing')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 1, 'L1 has one missing homework');
select is((select (l->'assignments'->>'pending_evaluation')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'), 2, 'L1 has two homework items pending evaluation');
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

-- Mission analytics: in-period columns and explicitly labelled to-date columns.
select is((select sum((m->>'runs')::int)::int from ar, jsonb_array_elements(v->'missions') m where name='missions'), 6, 'mission rows add up to recorded runs in the period');
select is((select jsonb_array_length(v->'missions') from ar where name='missions'), 5, 'missions with period activity or a completion to date are listed');
select is((select (m->>'learners_attempted')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 2, 'coc1_m1 learners attempted in the period');
select is((select (m->>'learners_verified')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 2, 'coc1_m1 learners verified in the period');
select is((select (m->>'completion_rate_to_date')::numeric from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 66.7, 'coc1_m1 completion to date');
select is((select (m->>'avg_runs_per_learner')::numeric from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 2.0, 'coc1_m1 runs per learner with runs');
select is((select (m->>'avg_invalid_actions')::numeric from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'), 1.5, 'coc1_m1 invalid actions per run');
select ok((select (m->>'learners_attempted')::int = 0 and (m->>'learners_verified')::int = 0 and (m->>'runs')::int = 0
    and (m->>'learners_verified_to_date')::int = 1 and (m->>'completion_rate_to_date')::numeric = 33.3
  from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m3'),
  'coc1_m3 verified 40 days ago: zero in-period counts, one learner verified to date');
select is((select (m->>'learners_verified_to_date')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), 0, 'incomplete runs never count as completion');
select is((select (m->>'failed_runs')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), 3, 'coc1_m4 failed runs');
select is((select m->>'avg_duration_seconds' from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), null, 'no verified run gives a null completion time');
select is((select m->'module'->>'code' from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'), 'LO1.2', 'missions carry their curriculum module');
select is((select (m->>'runs')::int from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m2'), 1, 'another instructor''s learner runs are never mixed in');
select is((select (m->>'runs')::int from ar, jsonb_array_elements(v->'missions') m where name='missions_t2' and m->>'mission_code'='coc1_m2'), 1, 'the other instructor sees their own learner''s run');
select ok((select a->>'mission_code' = 'coc1_m2' and (a->>'attempts')::int = 5 and (a->>'released')::int = 3 and (a->>'competent')::int = 1
  and (a->>'not_yet_competent')::int = 2 and (a->>'pending')::int = 2 from ar, jsonb_array_elements(v->'assessments') a where name='missions'),
  'assessment attempts by mission come from recorded attempts');
select is((select jsonb_array_length(v->'missions') from ar where name='missions_m1'), 1, 'mission filter narrows to one mission');

-- Criterion analysis (assessment and homework criteria).
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-CRIT-A'), 100.0, 'criterion A percent');
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-CRIT-B'), 50.0, 'criterion B percent (latest released result per learner)');
select is((select (c->>'evaluated_learners')::int from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-CRIT-B'), 2, 'each learner counted once per criterion');
select ok((select c->>'source' = 'homework' and (c->>'percent')::numeric = 83.3 and c->>'activity_title' = 'Analytics Homework One'
  from ar, jsonb_array_elements(v->'criteria') c where name='criteria' and c->>'code'='A7-HW-C1'), 'released homework criterion scores are analysed (25 / 30)');
select is((select jsonb_array_length(v->'criteria') from ar where name='criteria'), 4, 'graded and finalized homework criteria are not analysed before release');
select is((select v->'strongest'->0->>'code' from ar where name='criteria'), 'A7-CRIT-A', 'strongest criterion');
select is((select v->'weakest'->0->>'code' from ar where name='criteria'), 'A7-CRIT-B', 'weakest criterion');

-- Learner profile (instructor view).
select is((select v->'learner'->>'student_id' from ar where name='profile_l1'), 'A7-001', 'profile header');
select is((select (v->'progress'->>'overall_percent')::numeric from ar where name='profile_l1'), 12.5, 'profile overall progress');
select is((select jsonb_array_length(v->'assessments') from ar where name='profile_l1'), 2, 'profile assessment results');
select is((select jsonb_array_length(v->'timeline') from ar where name='profile_l1'), 14, 'profile timeline lists every recorded event in the period');
select is((select v->'evaluation' from ar where name='profile_l1'),
  '{"evaluate":1,"finalize":1,"release":0,"released":3}'::jsonb, 'profile evaluation stages for the learner');
select ok((select a->>'status' = 'released' and (a->>'percent')::numeric = 80.0 and (a->>'max_score')::numeric = 50
  from ar, jsonb_array_elements(v->'assignments') a where name='profile_l1' and a->>'title'='Analytics Homework One'), 'profile shows the released homework percentage of max_score');
select is((select a->>'status' from ar, jsonb_array_elements(v->'assignments') a where name='profile_l1' and a->>'title'='Analytics Homework Three'), 'graded', 'profile shows the homework lifecycle status');
select is((select a->>'status' from ar, jsonb_array_elements(v->'assignments') a where name='profile_l1' and a->>'title'='Analytics Homework Two'), 'missing', 'profile shows missing homework');
select is((select (v->'status'->'assignments'->>'pending_evaluation')::int from ar where name='profile_l1'), 2, 'profile pending homework');
select is((select (v->'status'->>'status') from ar where name='profile_l1'), 'on_track', 'profile status');
select ok((select jsonb_array_length(v->'classes') = 2 and jsonb_array_length(v->'quizzes') = 3 from ar where name='options'), 'filter options list active owned classes and own published quizzes');

-- Learner-facing performance (released results only; A2 progress methodology).
select is((select (v->'progress'->>'overall_percent')::numeric from ar where name='me_l1'), 12.5, 'learner overall progress');
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'progress'->'cocs') c where name='me_l1' and c->>'coc_code'='coc1'), 50.0, 'learner COC1 progress');
select ok((select (c->>'modules_completed')::int = 1 and (c->>'modules_total')::int = 4 from ar, jsonb_array_elements(v->'progress'->'cocs') c where name='me_l1' and c->>'coc_code'='coc1'),
  'learner module counts follow learner_module_states (1 of 4 COC1 modules)');
select is((select count(*)::int from ar, jsonb_array_elements(v->'competency') c where name='me_l1' and c->>'outcome'='satisfied' and c->>'criterion' like 'Analytics criterion%'), 2, 'competency per released criterion with its label');
select is((select jsonb_array_length(v->'scores'->'quizzes') from ar where name='me_l1'), 3, 'learner quiz scores: the immediate quizzes and the released essay quiz');
select ok((select (q->>'percent')::numeric = 88.9 and (q->>'score')::numeric = 8 and (q->>'max_score')::numeric = 9 and (q->>'released')::boolean
  from ar, jsonb_array_elements(v->'scores'->'quizzes') q where name='me_l1' and q->>'attempt_id' = (select qt4_l1::text from ax)),
  'a released essay quiz shows its finalized points and percent to the learner');
select is((select (q->>'percent')::numeric from ar, jsonb_array_elements(v->'scores'->'quizzes') q
  where name='me_l1' and q->>'attempt_id' = (select qt5_l1::text from ax)), 75.0, 'an immediate quiz is scored by points (3 of 4)');
select ok((select q->>'score' is null and q->>'max_score' is null and (q->>'correct_count')::int = 2 and (q->>'percent')::numeric = 100.0
  from ar, jsonb_array_elements(v->'scores'->'quizzes') q where name='me_l1' and q->>'attempt_id' = (select qt_l1::text from ax)),
  'a result recorded before points reports answers only, never answers as points');
select ok((select bool_and(not (q ? 'title')) from ar, jsonb_array_elements(v->'scores'->'quizzes') q where name='me_l1'),
  'no per-quiz title lookup in the learner view (review Minor 4)');
select ok(to_regprocedure('private.analytics_learner_quiz_title(uuid)') is null, 'the quiz-title wrapper is removed (review Minor 4)');
select ok((select jsonb_array_length(v->'scores'->'quizzes') = 2
    and not exists (select 1 from jsonb_array_elements(v->'scores'->'quizzes') q where q->>'attempt_id' = (select qt4_l2::text from ax))
  from ar where name='me_l2'), 'an evaluated, unreleased essay quiz is not shown to the learner');
select ok((select (h->>'score')::numeric = 40 and (h->>'max_score')::numeric = 50 and (h->>'percent')::numeric = 80.0 and (h->>'released')::boolean
  from ar, jsonb_array_elements(v->'scores'->'homework') h where name='me_l1' and h->>'title'='Analytics Homework One'), 'released homework score and max_score');
select is((select jsonb_array_length(v->'scores'->'homework') from ar where name='me_l1'), 2, 'graded and finalized homework stay hidden from the learner until release');
select is((select (v->'summary'->>'homework_avg')::numeric from ar where name='me_l1'), 80.0, 'learner homework average uses released grades only');
select ok((select (v->'summary'->>'criteria_achieved')::int = 2 and (v->'summary'->>'criteria_total')::int = 2
  and (v->'summary'->>'assessments_competent')::int = 1 and (v->'summary'->>'quiz_avg')::numeric = 88.0 from ar where name='me_l1'),
  'learner summary (quiz average of the visible results: 100, 88.9 and 75)');
select is((select jsonb_array_length(v->'assessments') from ar where name='me_l1'), 2, 'released assessment results');
select is((select (v->'practice'->>'runs')::int from ar where name='me_l1'), 4, 'learner practice runs');
select is((select (v->'practice'->>'missions_verified')::int from ar where name='me_l1'), 3, 'learner verified missions (accepted versions)');
select is((select (b->>'best_seconds')::int from ar, jsonb_array_elements(v->'practice'->'best_times') b where name='me_l1' and b->>'mission_code'='coc1_m1'), 120, 'best verified time');
select is((select v->'assessments' from ar where name='me_l2'), '[]'::jsonb, 'unreleased results are not shown to the learner');
select is((select v->'competency' from ar where name='me_l2'), '[]'::jsonb, 'no competency entries without a released result');

-- A3 quizzes: instructor-release results count once released, from the
-- finalization; pending, evaluated and finalized attempts are pending.
select ok((select (v->'quizzes'->>'submitted')::int = 2 and (v->'quizzes'->>'scored')::int = 1 and (v->'quizzes'->>'pending')::int = 1
  from ar where name='overview_q4_60'), 'essay quiz: two submissions, one released result, one pending evaluation');
select is((select (v->'quizzes'->>'avg_percent')::numeric from ar where name='overview_q4_60'), 88.9, 'the quiz average uses the released finalization only');
select is((select v->'evaluation'->'quiz' from ar where name='overview_q4_60'),
  '{"evaluate":0,"finalize":1,"release":0,"released":1}'::jsonb, 'quiz attempts by Evaluate / Finalize / Release stage');
select ok((select (v->>'participants')::int = 2 and (v->>'pending')::int = 1 and (v->>'average')::numeric = 88.9
    and (v->>'highest')::numeric = 88.9 and (v->>'lowest')::numeric = 88.9 and v->'quiz'->>'release_mode' = 'instructor_release'
  from ar where name='quiz_q4_60'), 'essay quiz analytics: average, highest and lowest from released results only');
select ok((select sum((b->>'count')::int) = 1 and sum((b->>'count')::int) filter (where b->>'bucket' = '80-89') = 1
  from ar, jsonb_array_elements(v->'distribution') b where name='quiz_q4_60'), 'the distribution holds only the released result');
select ok((select (r->>'score')::numeric = 8 and (r->>'max_score')::numeric = 9 and (r->>'percent')::numeric = 88.9 and r->>'status' = 'scored'
  from ar, jsonb_array_elements(v->'results') r where name='quiz_q4_60' and r->>'name' = 'Ana Analytics'), 'released result: finalized points of the maximum');
select ok((select r->>'status' = 'pending' and r->>'percent' is null and r->>'score' is null and r->>'stage' = 'finalize'
  from ar, jsonb_array_elements(v->'results') r where name='quiz_q4_60' and r->>'name' = 'Ben Analytics'), 'evaluated attempt: pending, no score');
select ok((select (q->>'avg_points')::numeric = 7 and (q->>'avg_percent')::numeric = 87.5 and q->>'correct' is null and (q->>'points')::numeric = 8
  from ar, jsonb_array_elements(v->'per_question') q where name='quiz_q4_60' and q->>'code' = 'A7-ESSAY'),
  'essay item: current score (latest evaluated_at, then highest sequence), not an older or later-inserted row');
select is((select (q->>'correct_rate')::numeric from ar, jsonb_array_elements(v->'per_question') q where name='quiz_q4_60' and q->>'code' = 'A7-ESSAY-OBJ'),
  100.0, 'objective items count released attempts only');
select ok((select (v->>'average')::numeric = 75.0 and (v->'results'->0->>'score')::numeric = 3 and (v->'results'->0->>'max_score')::numeric = 4
  from ar where name='quiz_q5_60'), 'an immediate quiz keeps quiz_results, scored by points (3 of 4), not answers (1 of 2)');
select ok((select (v->'quizzes'->>'applicable')::boolean and (v->'quizzes'->>'submitted')::int = 2 from ar where name='overview_lo11_60'),
  'a module filter keeps quizzes mapped to that module (quiz_modules) and drops whole-COC quizzes');
select ok((select not (v->'quizzes'->>'applicable')::boolean and v->'quizzes'->>'avg_percent' is null from ar where name='overview_m4'),
  'quizzes are not positioned at missions');
select is((select (l->>'quiz_avg')::numeric from ar, jsonb_array_elements(v->'learners') l where name='learners_60' and l->>'name' = 'Ana Analytics'),
  88.0, 'learner quiz average over released and immediate results (100, 88.9, 75)');
select is((select (l->>'quiz_avg')::numeric from ar, jsonb_array_elements(v->'learners') l where name='learners_60' and l->>'name' = 'Ben Analytics'),
  50.0, 'a pending essay attempt is excluded from the learner quiz average');
select ok((select c->>'source' = 'essay' and (c->>'avg')::numeric = 4 and (c->>'percent')::numeric = 100.0 and (c->>'evaluated_learners')::int = 1
    and c->>'activity_title' = 'Analytics Essay Quiz · A7-ESSAY'
  from ar, jsonb_array_elements(v->'criteria') c where name='criteria_60' and c->>'code' = 'E1'), 'essay rubric criterion E1 from the current essay score');
select is((select (c->>'percent')::numeric from ar, jsonb_array_elements(v->'criteria') c where name='criteria_60' and c->>'code' = 'E2'),
  75.0, 'essay rubric criterion E2 (3 of 4), released attempts only');

-- A1 simulation: simulation_condition criteria with their step titles, and
-- practice step results.
select ok((select c->>'source' = 'simulation' and c->>'title' = 'CPU seated in the correct orientation with the lever closed'
    and c->'steps' = '[{"id":"coc1_m2_p2","step":2,"title":"Prepare the motherboard"}]'::jsonb
    and (c->>'percent')::numeric = 0.0 and (c->>'not_satisfied')::int = 1
  from ar, jsonb_array_elements(v->'criteria') c where name='criteria_60' and c->>'code' = 'A7-SIM-C3'),
  'simulation criteria appear as simulation steps with their step title');
select ok((select (a->>'simulation')::boolean and a->'criteria'->0->'steps'->0->>'title' = 'Prepare the motherboard'
  from ar, jsonb_array_elements(v->'assessments') a where name='profile_l3_60' and a->>'assignment_title' = 'Analytics simulation assessment'),
  'the learner profile marks the simulation assessment and names each criterion''s step');
select ok(has_column_privilege('authenticated', 'public.practice_mission_contracts', 'step_titles', 'SELECT')
  and not has_column_privilege('authenticated', 'public.practice_mission_contracts', 'definition', 'SELECT'),
  'step titles are readable; contract definitions (answer keys) are not');
select is((select jsonb_array_length(m->'steps') from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m4'),
  4, 'coc1_m4 lists its four recorded steps');
select ok((select s->>'title' = 'Choose a tool' and (s->>'runs')::int = 3 and (s->>'missed')::int = 3 and (s->>'not_completed')::int = 1
    and (s->>'avg_incorrect')::numeric = 1.33
  from ar, jsonb_array_elements(v->'missions') m, jsonb_array_elements(m->'steps') s
  where name='missions' and m->>'mission_code'='coc1_m4' and s->>'phase_id' = 'coc1_m4_p2'),
  'step 2: missed in all three runs, 1.33 incorrect attempts per run (2 invalid, 1 invalid, 1 failed check)');
select ok((select (s->>'missed')::int = 0 and (s->>'avg_incorrect')::numeric = 0
  from ar, jsonb_array_elements(v->'missions') m, jsonb_array_elements(m->'steps') s
  where name='missions' and m->>'mission_code'='coc1_m4' and s->>'phase_id' = 'coc1_m4_p1'), 'a clean step is never missed');
select is((select jsonb_agg(x.value->>'title' order by x.o) from ar, jsonb_array_elements(v->'missions') m,
    jsonb_array_elements(m->'most_missed') with ordinality x(value, o)
  where name='missions' and m->>'mission_code'='coc1_m4'),
  '["Choose a tool","Connect devices","Run and interpret device test"]'::jsonb, 'most-missed steps: by runs missed, then incorrect attempts');
select is((select m->'steps' from ar, jsonb_array_elements(v->'missions') m where name='missions' and m->>'mission_code'='coc1_m1'),
  '[]'::jsonb, 'runs without step results add no steps');
select is((select jsonb_agg(x.value->>'phase_id' order by x.o) from ar, jsonb_array_elements(v->'missions') m, jsonb_array_elements(m->'recent_runs') r,
    jsonb_array_elements(r->'missed_steps') with ordinality x(value, o)
  where name='profile_l3_60' and m->>'mission_code'='coc1_m4' and (r->>'run_number')::int = 3),
  '["coc1_m4_p2","coc1_m4_p3","coc1_m4_p4"]'::jsonb, 'the profile lists the steps each recent run missed');

-- A6 engagement: points and level from A6, separate from scores.
select is((select (l->'engagement'->>'points')::int from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'),
  (select coalesce(sum(e.points), 0)::int from public.learner_point_events e where e.learner_id = (select l1 from ax) and e.awarded_at <= now()),
  'learner list points = the learner''s A6 point events to the period end');
select ok((select (l->'engagement'->>'points')::int > 0 from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'),
  'the fixture''s own records award points to L1');
select is((select l->'engagement'->>'level_title' from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ana Analytics'),
  (select public.gamification_level_for_points((select coalesce(sum(e.points), 0)::int from public.learner_point_events e
    where e.learner_id = (select l1 from ax))) ->> 'title'), 'level from public.gamification_level_for_points');
select is((select (l->'engagement'->>'points')::int - (l->'engagement'->>'points_in_period')::int
  from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ben Analytics'),
  (select coalesce(sum(e.points), 0)::int from public.learner_point_events e
    where e.learner_id = (select l2 from ax) and e.awarded_at < now() - interval '30 days'),
  'points in the period exclude awards before the period (the 45-day-old award)');
select ok((select (v->'engagement'->>'points')::int = (select (l->'engagement'->>'points')::int from ar a2, jsonb_array_elements(a2.v->'learners') l
      where a2.name='learners' and l->>'name'='Ana Analytics')
    and (v->'engagement'->>'achievements')::int = (select count(*)::int from public.learner_achievements la where la.learner_id = (select l1 from ax))
    and jsonb_array_length(v->'engagement'->'recent_events') between 1 and 5
    and (select bool_and(x->>'label' is not null) from jsonb_array_elements(v->'engagement'->'recent_events') x)
  from ar where name='profile_l1'), 'the profile shows the same points, the achievements and labelled recent awards');
select ok((select l->'engagement' ?& array['points','points_in_period','level','level_title'] and not (l ? 'points')
    and (l->>'performance_score')::numeric = (select (l2->>'performance_score')::numeric from ar a2, jsonb_array_elements(a2.v->'learners') l2
      where a2.name='learner_l2_only' and l2->>'name'='Ben Analytics')
  from ar, jsonb_array_elements(v->'learners') l where name='learners' and l->>'name'='Ben Analytics'),
  'engagement is reported apart from the performance score');

select * from finish();
rollback;
