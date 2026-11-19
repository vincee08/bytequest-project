-- Client version guard (final fix wave, cross-layer client version marker):
-- an app client must identify as at least the minimum supported app version
-- (x-bytequest-app-version) to start a simulation-assessment attempt or an
-- essay quiz. Header absent as authenticated, 1.1.9 or an unparsable value is
-- refused with APP_UPDATE_REQUIRED before anything is recorded; 1.2.0 and
-- 1.10.0 are allowed; service and SQL contexts are not app clients.
-- Form-based packages and objective-only quizzes are unchanged. Rollback-only.
begin;
select plan(33);
-- The suite's own minimum (rolled back), whatever the database is configured with.
insert into public.app_release_config(key, value) values ('min_supported_app_version', '1.2.0')
on conflict (key) do update set value = excluded.value;

create temporary table vg as select
  gen_random_uuid() admin_user, gen_random_uuid() teacher, gen_random_uuid() learner, gen_random_uuid() learner2,
  gen_random_uuid() class_id,
  null::uuid source_id, null::uuid module_version_id, null::uuid sim_activity, null::uuid sim_activity_b, null::uuid form_activity,
  null::uuid sim_rubric, null::uuid sim_rubric_b, null::uuid form_rubric,
  null::uuid sim_a, null::uuid sim_b, null::uuid sim_practice, null::uuid form_a,
  null::uuid essay_quiz, null::uuid essay_version, null::uuid essay_assignment,
  null::uuid objective_quiz, null::uuid objective_version, null::uuid objective_assignment,
  null::uuid essay_attempt,
  (select id from public.coc_modules where coc_code = 'coc1') coc1,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1') lo11;
grant select, update on vg to authenticated, service_role;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@client-version.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',name),now(),now()
from vg cross join lateral (values (admin_user,'Version Admin'),(teacher,'Version Teacher'),(learner,'Version Learner'),
  (learner2,'Version Learner Two')) t(id,name);
update public.profiles set role = 'admin' where user_id = (select admin_user from vg);
update public.profiles set role = 'instructor' where user_id = (select teacher from vg);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_id,'Client version class','CV-'||left(class_id::text,8),teacher,teacher from vg;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_id,l,teacher from vg cross join lateral (values (learner),(learner2)) t(l);

-- A published simulation package (as scripts/publish-simulation-assessments.mjs
-- writes it) and a published form-based package, each with an approved rubric.
with inserted as (
  insert into public.tesda_sources(qualification_code,title,edition,source_reference,status,validation_notes,created_by,approved_by,approved_at,activated_by,activated_at)
  select 'CV-'||left(gen_random_uuid()::text,8),'Client version rollback source','TEST_ONLY','Rollback fixture only','active','TEST_ONLY_ROLLBACK_FIXTURE',
    admin_user,admin_user,now(),admin_user,now() from vg returning id)
update vg set source_id = inserted.id from inserted;
with inserted as (
  insert into public.module_versions(module_id,tesda_source_id,version_number,title,source_trace,status,created_by,published_by,published_at)
  select vg.coc1,vg.source_id,coalesce((select max(version_number) from public.module_versions mv where mv.module_id=vg.coc1),0)+1,
    'Client version rollback module',jsonb_build_object('status','TEST_ONLY'),'published',vg.admin_user,vg.admin_user,now() from vg returning id)
update vg set module_version_id = inserted.id from inserted;
with inserted as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select m.id,vg.module_version_id,coalesce((select max(version_number) from public.activity_versions av where av.mission_id=m.id),0)+1,
    'Client version simulation assessment','assessment',
    jsonb_build_object('mission_id','coc1_m2','definition_version',c.version,'mode','assessment'),
    jsonb_build_object('engine','simulation_replay_v1','simulation_definition',c.definition,'contract_version',c.version),
    'published',vg.admin_user,vg.admin_user,now()
  from vg cross join public.missions m join public.practice_mission_contracts c on c.mission_id = m.mission_code
  where m.mission_code='coc1_m2' returning id)
update vg set sim_activity = inserted.id from inserted;
with inserted as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select m.id,vg.module_version_id,coalesce((select max(version_number) from public.activity_versions av where av.mission_id=m.id),0)+1,
    'Client version second simulation assessment','assessment',
    jsonb_build_object('mission_id','coc1_m3','definition_version',c.version,'mode','assessment'),
    jsonb_build_object('engine','simulation_replay_v1','simulation_definition',c.definition,'contract_version',c.version),
    'published',vg.admin_user,vg.admin_user,now()
  from vg cross join public.missions m join public.practice_mission_contracts c on c.mission_id = m.mission_code
  where m.mission_code='coc1_m3' returning id)
update vg set sim_activity_b = inserted.id from inserted;
with inserted as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select m.id,vg.module_version_id,coalesce((select max(version_number) from public.activity_versions av where av.mission_id=m.id),0)+1,
    'Client version form-based assessment','assessment',
    '{"assessment_package_id":"client-version-form","simulation_template":"authoritative_mission_v1"}'::jsonb,'{}'::jsonb,
    'published',vg.admin_user,vg.admin_user,now()
  from vg cross join public.missions m where m.mission_code='coc1_m2' returning id)
update vg set form_activity = inserted.id from inserted;
with inserted as (
  insert into public.rubric_versions(activity_version_id,tesda_source_id,version_number,title,status,scoring_method,passing_rule,created_by,approved_by,approved_at)
  select a,vg.source_id,1,t,'approved','binary_sum',jsonb_build_object('status','APPROVED','method','all_required'),vg.admin_user,vg.admin_user,now()
  from vg cross join lateral (values (vg.sim_activity,'Client version simulation rubric'),
    (vg.sim_activity_b,'Client version second simulation rubric'),(vg.form_activity,'Client version form rubric')) x(a,t)
  returning id, activity_version_id)
update vg set sim_rubric = (select id from inserted where activity_version_id = vg.sim_activity),
  sim_rubric_b = (select id from inserted where activity_version_id = vg.sim_activity_b),
  form_rubric = (select id from inserted where activity_version_id = vg.form_activity);
with inserted as (
  insert into public.assignments(class_id,activity_version_id,rubric_version_id,assignment_type,title,assigned_by)
  select vg.class_id,a,r,t::public.assignment_type,n,vg.teacher
  from vg cross join lateral (values
    (vg.sim_activity,vg.sim_rubric,'assessment','Simulation A'),
    (vg.sim_activity_b,vg.sim_rubric_b,'assessment','Simulation B'),
    (vg.sim_activity,vg.sim_rubric,'practice','Simulation class practice'),
    (vg.form_activity,vg.form_rubric,'assessment','Form-based A')) x(a,r,t,n)
  returning id, title)
update vg set sim_a = (select id from inserted where title='Simulation A'),
  sim_b = (select id from inserted where title='Simulation B'),
  sim_practice = (select id from inserted where title='Simulation class practice'),
  form_a = (select id from inserted where title='Form-based A');

-- Contract.
select ok((select not prosecdef and provolatile = 's' from pg_proc where oid = 'private.client_app_version_ok()'::regprocedure),
  'private.client_app_version_ok() is SECURITY INVOKER and stable');
select ok(exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.attempts'::regclass and t.tgname = 'trg_attempts_require_supported_app'
      and t.tgtype & 2 = 2 and t.tgtype & 4 = 4 and t.tgtype & 1 = 1 and not p.prosecdef),
  'a SECURITY INVOKER BEFORE INSERT row trigger guards public.attempts');
select ok((select prosecdef from pg_proc where oid = 'public.start_learner_quiz(uuid,uuid)'::regprocedure)
  and not has_function_privilege('authenticated', 'private.client_app_version_ok()', 'execute')
  and not has_function_privilege('anon', 'private.client_app_version_ok()', 'execute'),
  'start_learner_quiz stays SECURITY DEFINER; clients cannot call the private helper');
select is(private.app_version_parts('1.2.0+3'), array[1,2,0], 'build metadata is ignored when parsing a version');
select ok(private.app_version_parts('v1.2.0') is null and private.app_version_parts('1.2.3.4.5') is null
  and private.app_version_parts('') is null, 'values that are not dotted version numbers are unparsable');

-- Request contexts.
select is(private.client_app_version_ok(), true, 'no request context (postgres, migrations, SQL) is not an app client');
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.headers', '{"accept":"application/json"}', true);
select is(private.client_app_version_ok(), true, 'a service-role request without the header is not an app client');
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(private.client_app_version_ok(), false, 'a request whose JWT role claim is authenticated must send the header');
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);
select is(private.client_app_version_ok(), true, 'an authenticated request that identifies as 1.2.0 passes');
select set_config('request.jwt.claim.role', '', true);
select set_config('request.headers', '{"x-bytequest-app-version":"1.1.9"}', true);
select is(private.client_app_version_ok(), false, 'a lower header is refused whatever the role');
select set_config('request.headers', '', true);

-- Simulation-assessment attempts, as the learner (request role authenticated).
select set_config('request.jwt.claim.sub', (select learner::text from vg), true);
set local role authenticated;
select throws_ok(format('select public.start_attempt(%L, gen_random_uuid())', (select sim_a from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this assessment.',
  'header absent as authenticated: a simulation-assessment attempt is refused');
select set_config('request.headers', '{"x-bytequest-app-version":"1.1.9"}', true);
select throws_ok(format('select public.start_attempt(%L, gen_random_uuid())', (select sim_a from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this assessment.',
  'header 1.1.9: a simulation-assessment attempt is refused');
select set_config('request.headers', '{"x-bytequest-app-version":"latest"}', true);
select throws_ok(format('select public.start_attempt(%L, gen_random_uuid())', (select sim_a from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this assessment.',
  'an unparsable header is refused');
select set_config('request.headers', '{}', true);
select throws_ok(format('select public.start_attempt(%L, gen_random_uuid())', (select sim_practice from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this assessment.',
  'a class practice attempt on a simulation package is refused for an unidentified app too');
reset role;
select is((select count(*)::integer from public.attempts where learner_id = (select learner from vg)), 0,
  'a refused start records no attempt');
select is((select count(*)::integer from public.audit_events where action = 'attempt.started'
    and actor_id = (select learner from vg)), 0,
  'a refused start writes no attempt.started audit event');

select set_config('request.jwt.claim.sub', (select learner::text from vg), true);
set local role authenticated;
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);
select is((public.start_attempt((select sim_a from vg), gen_random_uuid())).status::text, 'in_progress',
  'header 1.2.0: the simulation-assessment attempt starts');
select set_config('request.headers', '{"x-bytequest-app-version":"1.10.0"}', true);
select is((public.start_attempt((select sim_b from vg), gen_random_uuid())).status::text, 'in_progress',
  'header 1.10.0 passes (versions compare numerically, not as text)');
select set_config('request.headers', '', true);
select is((public.start_attempt((select form_a from vg), gen_random_uuid())).status::text, 'in_progress',
  'a form-based package still starts without the header (1.1.0 keeps working)');
reset role;
select is((select count(*)::integer from public.attempts where learner_id = (select learner from vg) and assignment_id = (select sim_a from vg)), 1,
  'after updating, the learner''s first attempt is the one recorded: the refusals used none');

-- Service and SQL contexts insert simulation attempts without the header.
select lives_ok(format($$insert into public.attempts(learner_id,class_id,assignment_id,activity_version_id,rubric_version_id,tesda_source_id,client_start_key)
    values (%L,%L,%L,%L,%L,%L,gen_random_uuid())$$,
    (select learner2 from vg), (select class_id from vg), (select sim_a from vg), (select sim_activity from vg),
    (select sim_rubric from vg), (select source_id from vg)),
  'a SQL (postgres) insert of a simulation attempt passes');
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.headers', '{"accept":"application/json"}', true);
select lives_ok(format($$insert into public.attempts(learner_id,class_id,assignment_id,activity_version_id,rubric_version_id,tesda_source_id,client_start_key)
    values (%L,%L,%L,%L,%L,%L,gen_random_uuid())$$,
    (select learner2 from vg), (select class_id from vg), (select sim_b from vg), (select sim_activity_b from vg),
    (select sim_rubric_b from vg), (select source_id from vg)),
  'a service-role insert of a simulation attempt passes');
reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.headers', '', true);

-- Quizzes: an essay quiz needs an identified app; an objective quiz does not.
select set_config('request.jwt.claim.sub', (select teacher::text from vg), true);
set local role authenticated;
update vg set essay_quiz = (public.create_instructor_quiz(
  'Client version essay quiz', 'Assembly', p_coc_module_id => (select coc1 from vg), p_focus => 'Explain safe CPU installation',
  p_module_ids => array[(select lo11 from vg)])).id;
update vg set essay_version = (select id from public.quiz_versions where quiz_id = vg.essay_quiz);
select public.upsert_quiz_item((select essay_version from vg), 'true_false', 'Thermal paste goes between the CPU and the cooler.', '[]', '"true"');
select public.upsert_quiz_item((select essay_version from vg), 'scenario_essay', 'Explain how you would install the processor safely.', '[]', '""',
  p_scenario => 'A client left an unassembled workstation on your bench with an anti-static mat.',
  p_rubric => '[{"id":"C1","criterion":"Safety","description":"ESD precautions before handling","max_points":4},{"id":"C2","criterion":"Procedure","description":"Lever, alignment and seating","max_points":6}]');
update vg set objective_quiz = (public.create_instructor_quiz(
  'Client version objective quiz', 'Assembly', p_coc_module_id => (select coc1 from vg), p_focus => 'Recall the assembly order',
  p_module_ids => array[(select lo11 from vg)])).id;
update vg set objective_version = (select id from public.quiz_versions where quiz_id = vg.objective_quiz);
select public.upsert_quiz_item((select objective_version from vg), 'true_false', 'The CPU is installed before the cooler.', '[]', '"true"');
select public.review_quiz_item(id, 'approved') from public.quiz_items
  where quiz_version_id in ((select essay_version from vg), (select objective_version from vg));
select public.publish_and_assign_quiz((select essay_version from vg), array[(select class_id from vg)]);
select public.publish_and_assign_quiz((select objective_version from vg), array[(select class_id from vg)]);
update vg set essay_assignment = (select id from public.quiz_assignments where quiz_version_id = vg.essay_version),
  objective_assignment = (select id from public.quiz_assignments where quiz_version_id = vg.objective_version);

select set_config('request.jwt.claim.sub', (select learner::text from vg), true);
select throws_ok(format('select public.start_learner_quiz(%L, gen_random_uuid())', (select essay_assignment from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this quiz.',
  'header absent as authenticated: an essay quiz is refused');
select set_config('request.headers', '{"x-bytequest-app-version":"1.1.9"}', true);
select throws_ok(format('select public.start_learner_quiz(%L, gen_random_uuid())', (select essay_assignment from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this quiz.',
  'header 1.1.9: an essay quiz is refused');
reset role;
select is((select count(*)::integer from public.quiz_attempts where learner_id = (select learner from vg)), 0,
  'a refused essay quiz admits no attempt');
select is((select count(*)::integer from private.quiz_attempt_claims where learner_id = (select learner from vg)), 0,
  'a refused essay quiz uses up no quiz claim');
select is((select count(*)::integer from public.audit_events where action = 'quiz_attempt.started'
    and actor_id = (select learner from vg)), 0,
  'a refused essay quiz writes no quiz_attempt.started audit event');

select set_config('request.jwt.claim.sub', (select learner::text from vg), true);
set local role authenticated;
select set_config('request.headers', '', true);
select is(jsonb_array_length(public.start_learner_quiz((select objective_assignment from vg), gen_random_uuid())->'questions'), 1,
  'an objective-only quiz still starts without the header (1.1.0 keeps working)');
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);
update vg set essay_attempt = (public.start_learner_quiz(essay_assignment, gen_random_uuid())->>'attempt_id')::uuid;
select ok((select essay_attempt from vg) is not null, 'header 1.2.0: the essay quiz starts');
select set_config('request.headers', '', true);
select throws_ok(format('select public.start_learner_quiz(%L, gen_random_uuid())', (select essay_assignment from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this quiz.',
  'an unidentified app cannot resume the essay attempt either');
select set_config('request.headers', '{"x-bytequest-app-version":"1.10.0"}', true);
select is((public.start_learner_quiz((select essay_assignment from vg), gen_random_uuid())->>'attempt_id')::uuid,
  (select essay_attempt from vg), 'header 1.10.0 resumes the same essay attempt');
reset role;

-- The configured minimum drives the check and the message.
update public.app_release_config set value = '1.3.0' where key = 'min_supported_app_version';
select set_config('request.jwt.claim.sub', (select learner2::text from vg), true);
set local role authenticated;
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);
select throws_ok(format('select public.start_learner_quiz(%L, gen_random_uuid())', (select essay_assignment from vg)),
  'P0001', 'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.3.0 or later to take this quiz.',
  'a raised minimum refuses 1.2.0 and names the configured version');
reset role;
delete from public.app_release_config where key = 'min_supported_app_version';
select is(private.min_supported_app_version(), '1.2.0', 'a missing minimum falls back to 1.2.0');
select set_config('request.headers', '', true);

select * from finish();
rollback;
