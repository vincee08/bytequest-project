-- Slice A3.1: curriculum-organised quiz authoring (COC -> module -> topic ->
-- learning outcome), quiz settings and scenario essay items with rubrics.
-- Rollback-only. Requires migrations 20261119130000 and 20261119130100.
begin;
select plan(48);

create temporary table qa3 as select
  gen_random_uuid() teacher, gen_random_uuid() other_teacher,
  gen_random_uuid() learner, gen_random_uuid() class_a, gen_random_uuid() class_b,
  (select id from public.coc_modules where coc_code = 'coc1') coc1,
  (select id from public.coc_modules where coc_code = 'coc2') coc2,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1') lo11,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.2') lo12,
  (select id from public.curriculum_modules where coc_code = 'coc2' and code = 'LO2.1') lo21,
  (select o.id from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
    where m.coc_code = 'coc1' and m.code = 'LO1.1' and o.code = '1.4') pc14,
  (select o.id from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
    where m.coc_code = 'coc1' and m.code = 'LO1.2' and o.code = '3.1') pc31,
  (select o.id from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
    where m.coc_code = 'coc2' and m.code = 'LO2.1' and o.code = '1.5') pc215,
  gen_random_uuid() topic_published, gen_random_uuid() topic_draft,
  null::uuid quiz, null::uuid version, null::uuid essay, null::uuid mcq,
  null::uuid whole_quiz, null::uuid plain_quiz, null::uuid plain_version,
  null::uuid legacy_quiz, null::uuid legacy_version, null::uuid legacy_item,
  null::uuid legacy_assignment_a, null::uuid legacy_assignment_b, null::uuid legacy_attempt;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-redefense.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Quiz redefense fixture"}'::jsonb,now(),now()
from qa3 cross join lateral (values (teacher),(other_teacher),(learner)) ids(id);
update public.profiles set role = 'instructor' where user_id in (select teacher from qa3 union select other_teacher from qa3);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Quiz redefense A','QRA-'||left(class_a::text,8),teacher,teacher from qa3 union all
select class_b,'Quiz redefense B','QRB-'||left(class_b::text,8),teacher,teacher from qa3;
-- Legacy multi-class fixture: one learner in two active classes, as data created
-- before the one-active-class rule (20261123090000). Built with that rule's
-- trigger disabled inside this rolled-back transaction only.
alter table public.class_memberships disable trigger trg_class_memberships_one_active_class;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_a,learner,teacher from qa3 union all select class_b,learner,teacher from qa3;
alter table public.class_memberships enable trigger trg_class_memberships_one_active_class;
insert into public.curriculum_topics(id,module_id,sequence_order)
select topic_published,lo11,1 from qa3 union all select topic_draft,lo11,2 from qa3;
insert into public.curriculum_topic_revisions(topic_id,revision_number,title,body_markdown,status)
select topic_published,1,'ESD-safe hardware assembly','Wear a wrist strap and ground yourself.','published'::public.content_publication_status from qa3 union all
select topic_draft,1,'Draft only topic','Not yet published.','draft'::public.content_publication_status from qa3;
grant all on qa3 to authenticated, service_role;

select ok('scenario_essay' = any(enum_range(null::public.quiz_item_type)::text[]), 'quiz_item_type includes scenario_essay');
select ok((select relrowsecurity from pg_class where oid = 'public.quiz_modules'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.quiz_learning_outcomes'::regclass),
  'quiz curriculum link tables keep RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.quiz_modules', 'INSERT')
  and not has_table_privilege('authenticated', 'public.quiz_learning_outcomes', 'INSERT'),
  'clients cannot write quiz curriculum links directly');

select set_config('request.jwt.claim.sub', (select teacher::text from qa3), true);
set local role authenticated;

-- Required curriculum and settings.
select throws_ok(
  $$select public.create_instructor_quiz('Hardware assembly check','Assembly', p_focus => 'Assess safe assembly')$$,
  '22023', 'QUIZ_COC_REQUIRED', 'a new quiz requires a COC');
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L)', 'Hardware assembly check', 'Assembly', coc1),
  '22023', 'QUIZ_FOCUS_REQUIRED', 'a new quiz requires a stated focus') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_module_ids=>array[%L]::uuid[])',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly', lo21),
  '22023', 'QUIZ_MODULE_SCOPE_INVALID', 'scope modules must belong to the quiz COC') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_module_ids=>array[%L]::uuid[],p_outcome_ids=>array[%L]::uuid[])',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly', lo11, pc31),
  '22023', 'QUIZ_OUTCOME_SCOPE_INVALID', 'learning outcomes must belong to the selected modules') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_outcome_ids=>array[%L]::uuid[])',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly', pc215),
  '22023', 'QUIZ_OUTCOME_SCOPE_INVALID', 'whole-COC outcomes must belong to that COC') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_topic_id=>%L)',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly', topic_draft),
  '22023', 'QUIZ_TOPIC_SCOPE_INVALID', 'only published topics can be selected') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_module_ids=>array[%L]::uuid[],p_topic_id=>%L)',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly', lo12, topic_published),
  '22023', 'QUIZ_TOPIC_SCOPE_INVALID', 'the topic must belong to a selected module') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_time_limit_minutes=>241)',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly'),
  '22023', 'QUIZ_TIME_LIMIT_INVALID', 'time limits are 1 to 240 minutes') from qa3;
select throws_ok(format(
  'select public.create_instructor_quiz(%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_quiz_type=>%L)',
  'Hardware assembly check', 'Assembly', coc1, 'Assess safe assembly', 'final_exam'),
  '22023', 'QUIZ_TYPE_INVALID', 'quiz type is pre_assessment, formative or summative') from qa3;

update qa3 set quiz = (public.create_instructor_quiz(
  'Hardware assembly check', 'ESD-safe hardware assembly', 'Covers LO1.1 and LO1.2', coc1,
  'Answer every item.', 'Assess safe component installation and OS preparation', 'summative', 'intermediate',
  topic_published, array[lo11, lo12], array[pc14, pc31], 30, 'immediate')).id;
update qa3 set version = (select id from public.quiz_versions where quiz_id = qa3.quiz);
select is((select focus || '|' || quiz_type || '|' || difficulty || '|' || (topic_id = qa3.topic_published)::text
  from public.quizzes where id = qa3.quiz),
  'Assess safe component installation and OS preparation|summative|intermediate|true',
  'curriculum focus, type, difficulty and topic are stored on the quiz') from qa3;
select is((select count(*)::int from public.quiz_modules where quiz_id = qa3.quiz), 2, 'two scope modules are linked') from qa3;
select is((select count(*)::int from public.quiz_learning_outcomes where quiz_id = qa3.quiz), 2, 'two performance criteria are linked') from qa3;
select is((select time_limit_minutes || ':' || result_release_mode || ':' || instructions from public.quiz_versions where id = qa3.version),
  '30:immediate:Answer every item.', 'version 1 carries the time limit, release mode and instructions') from qa3;

update qa3 set whole_quiz = (public.create_instructor_quiz('Whole COC pre-assessment', 'COC1', p_coc_module_id => coc1,
  p_focus => 'Diagnose readiness across COC1', p_quiz_type => 'pre_assessment', p_outcome_ids => array[pc31])).id;
select is((select count(*)::int from public.quiz_modules where quiz_id = qa3.whole_quiz), 0,
  'whole-COC scope stores no module rows') from qa3;
select is((select quiz_type || ':' || difficulty from public.quizzes where id = qa3.whole_quiz), 'pre_assessment:foundation',
  'difficulty defaults to foundation') from qa3;

-- Scenario essays need a scenario and a rubric with positive points.
select throws_ok(format(
  'select public.upsert_quiz_item(%L,''scenario_essay'',%L,''[]'',''""'',p_scenario=>%L)',
  version, 'Explain how you would install the CPU.', 'A technician receives an unassembled workstation.'),
  '22023', 'QUIZ_ESSAY_RUBRIC_REQUIRED', 'an essay without a rubric is rejected') from qa3;
select throws_ok(format(
  'select public.upsert_quiz_item(%L,''scenario_essay'',%L,''[]'',''""'',p_scenario=>%L,p_rubric=>''[]'')',
  version, 'Explain how you would install the CPU.', 'A technician receives an unassembled workstation.'),
  '22023', 'QUIZ_ESSAY_RUBRIC_REQUIRED', 'an essay needs at least one rubric criterion') from qa3;
select throws_ok(format(
  'select public.upsert_quiz_item(%L,''scenario_essay'',%L,''[]'',''""'',p_scenario=>%L,p_rubric=>%L)',
  version, 'Explain how you would install the CPU.', 'A technician receives an unassembled workstation.',
  '[{"id":"C1","criterion":"Safety","description":"ESD precautions","max_points":0}]'),
  '22023', 'QUIZ_ESSAY_RUBRIC_REQUIRED', 'rubric criteria need positive points') from qa3;
select throws_ok(format(
  'select public.upsert_quiz_item(%L,''scenario_essay'',%L,''[]'',''""'',p_scenario=>%L,p_rubric=>%L)',
  version, 'Explain how you would install the CPU.', 'A technician receives an unassembled workstation.',
  '[{"id":"C1","criterion":"Safety","description":"ESD precautions","max_points":-2}]'),
  '22023', 'QUIZ_ESSAY_RUBRIC_REQUIRED', 'negative rubric points are rejected') from qa3;
select throws_ok(format(
  'select public.upsert_quiz_item(%L,''scenario_essay'',%L,''[]'',''""'',p_rubric=>%L)',
  version, 'Explain how you would install the CPU.',
  '[{"id":"C1","criterion":"Safety","description":"ESD precautions","max_points":4}]'),
  '22023', 'QUIZ_ESSAY_SCENARIO_REQUIRED', 'an essay needs scenario text') from qa3;
update qa3 set essay = (public.upsert_quiz_item(version, 'scenario_essay', 'Describe, step by step, how you would install the processor and verify the build.',
  '[]', '"Mentions ESD strap, socket lever, triangle alignment and POST check."', 'Instructor scoring guide only.',
  p_rubric => '[{"id":"C1","criterion":"Safety","description":"Uses ESD precautions before touching parts","max_points":4},{"criterion":"Procedure","description":"Correct CPU orientation and seating","max_points":6}]',
  p_scenario => 'A client brought an unassembled workstation and an anti-static mat. The motherboard is already on the mat.',
  p_min_words => 60, p_max_words => 250)).id;
select is((select points from public.quiz_items where id = qa3.essay), 10::numeric, 'essay points equal the sum of rubric points') from qa3;
select is((select jsonb_array_length(rubric) || ':' || (rubric->1->>'id') || ':' || min_words || '-' || max_words from public.quiz_items where id = qa3.essay),
  '2:C2:60-250', 'rubric is normalised with generated criterion ids and word guidance') from qa3;
update qa3 set mcq = (public.upsert_quiz_item(version, 'multiple_choice', 'Which tool prevents electrostatic discharge?',
  '["Anti-static wrist strap","Crimping tool"]', '"Anti-static wrist strap"')).id;
select is((select points from public.quiz_items where id = qa3.mcq), 1::numeric, 'objective items default to one point') from qa3;
select throws_ok(format(
  'select public.upsert_quiz_item(%L,''multiple_choice'',%L,%L,%L,p_rubric=>%L)',
  version, 'Which tool prevents electrostatic discharge?', '["Anti-static wrist strap","Crimping tool"]', '"Anti-static wrist strap"',
  '[{"id":"C1","criterion":"Safety","description":"","max_points":4}]'),
  '22023', 'INVALID_QUIZ_ITEM', 'objective items cannot carry an essay rubric') from qa3;

-- Settings updates and module scope on edit.
select throws_ok(format(
  'select public.update_instructor_quiz(%L,%L,%L,p_coc_module_id=>%L,p_focus=>%L,p_module_ids=>array[%L]::uuid[])',
  quiz, 'Hardware assembly check', 'Assembly', coc2, 'Assess safe assembly', lo11),
  '22023', 'QUIZ_MODULE_SCOPE_INVALID', 'an edit cannot keep modules of another COC') from qa3;
select lives_ok(format(
  'select public.update_instructor_quiz(%L,%L,%L,%L,%L,p_focus=>%L,p_quiz_type=>%L,p_difficulty=>%L,p_module_ids=>array[%L]::uuid[],p_outcome_ids=>array[%L]::uuid[],p_time_limit_minutes=>45,p_result_release_mode=>%L,p_instructions=>%L)',
  quiz, 'Hardware assembly check', 'ESD-safe hardware assembly', 'Covers LO1.1', coc1, 'Assess safe component installation',
  'formative', 'advanced', lo11, pc14, 'immediate', 'Read the scenario first.'), 'a valid curriculum edit succeeds') from qa3;
select is((select string_agg(m.code, ',') from public.quiz_modules qm join public.curriculum_modules m on m.id = qm.module_id where qm.quiz_id = qa3.quiz),
  'LO1.1', 'the edit replaces the scope modules') from qa3;
select is((select time_limit_minutes || ':' || instructions from public.quiz_versions where id = qa3.version), '45:Read the scenario first.',
  'the edit updates the draft version settings') from qa3;

-- Reordering keeps rubric data intact.
select lives_ok(format('select public.reorder_quiz_items(%L, array[%L,%L]::uuid[])', version, mcq, essay), 'reorder works with essays') from qa3;
select is((select points || ':' || jsonb_array_length(rubric) || ':' || order_index from public.quiz_items where id = qa3.essay), '10:2:2',
  'reorder keeps the essay rubric and points') from qa3;

-- Publication forces instructor release for essays.
select public.review_quiz_item(essay, 'approved') from qa3;
select public.review_quiz_item(mcq, 'approved') from qa3;
select lives_ok(format('select public.publish_quiz_version(%L)', version), 'a reviewed essay version publishes') from qa3;
select is((select status || ':' || result_release_mode from public.quiz_versions where id = qa3.version), 'published:instructor_release',
  'publishing a version with an essay forces instructor release') from qa3;
select throws_ok(format(
  'select public.update_instructor_quiz(%L,%L,%L,%L,%L,p_focus=>%L,p_quiz_type=>%L,p_difficulty=>%L,p_module_ids=>array[%L]::uuid[],p_outcome_ids=>array[%L]::uuid[],p_time_limit_minutes=>20,p_result_release_mode=>%L,p_instructions=>%L)',
  quiz, 'Hardware assembly check', 'ESD-safe hardware assembly', 'Covers LO1.1', coc1, 'Assess safe component installation',
  'formative', 'advanced', lo11, pc14, 'instructor_release', 'Read the scenario first.'),
  '22023', 'CREATE_DRAFT_TO_CHANGE_SETTINGS', 'published settings change only through a new draft') from qa3;
select lives_ok(format('select public.create_quiz_version(%L)', quiz), 'a new draft version can be created') from qa3;
select is((select time_limit_minutes || ':' || result_release_mode from public.quiz_versions where quiz_id = qa3.quiz and status = 'draft'),
  '45:instructor_release', 'a new draft inherits the previous version settings') from qa3;

update qa3 set plain_quiz = (public.create_instructor_quiz('Network media check', 'Cables', p_coc_module_id => coc2,
  p_focus => 'Identify network media', p_module_ids => array[lo21])).id;
update qa3 set plain_version = (select id from public.quiz_versions where quiz_id = qa3.plain_quiz);
select public.review_quiz_item((public.upsert_quiz_item(plain_version, 'true_false', 'UTP cable uses twisted pairs.', '[]', '"true"')).id, 'approved') from qa3;
select public.publish_quiz_version(plain_version) from qa3;
select is((select result_release_mode from public.quiz_versions where id = qa3.plain_version), 'immediate',
  'objective-only versions keep immediate results') from qa3;
reset role;

select throws_ok(format(
  'update public.quiz_versions set time_limit_minutes = 5 where id = %L', version),
  '55000', 'PUBLISHED_QUIZ_SETTINGS_ARE_IMMUTABLE', 'published version settings are immutable') from qa3;
select throws_ok(format(
  'insert into public.quiz_items(quiz_version_id,item_code,item_type,prompt,options,correct_answer,order_index,created_by,scenario,rubric,points) values (%L,''BYPASS-1'',''scenario_essay'',''Bypass essay prompt'',''[]'',''""'',99,%L,''Scenario text here.'',''[]'',1)',
  (select id from public.quiz_versions where quiz_id = qa3.quiz and status = 'draft'), teacher),
  '23514', null, 'the table rejects an essay without rubric criteria') from qa3;

-- Other instructors and learners cannot read curriculum links.
select set_config('request.jwt.claim.sub', (select other_teacher::text from qa3), true);
set local role authenticated;
select is((select count(*)::int from public.quiz_modules where quiz_id = (select quiz from qa3)), 0, 'another instructor sees no links');
select set_config('request.jwt.claim.sub', (select learner::text from qa3), true);
select is((select count(*)::int from public.quiz_learning_outcomes), 0, 'learners cannot read quiz curriculum links');
reset role;

-- Existing (unmapped) quizzes stay valid: legacy edit, publication and one-attempt claims.
insert into public.quizzes(instructor_id, title, topic, created_by) select teacher, 'Legacy networking quiz', 'Networks', teacher from qa3;
update qa3 set legacy_quiz = (select id from public.quizzes where title = 'Legacy networking quiz' and instructor_id = qa3.teacher);
insert into public.quiz_versions(quiz_id, version_number, created_by) select legacy_quiz, 1, teacher from qa3;
update qa3 set legacy_version = (select id from public.quiz_versions where quiz_id = qa3.legacy_quiz);
select set_config('request.jwt.claim.sub', (select teacher::text from qa3), true);
set local role authenticated;
select lives_ok(format('select public.update_instructor_quiz(%L,%L,%L,%L)', legacy_quiz, 'Legacy networking quiz', 'Networks', 'Still valid'),
  'a legacy metadata edit still works without curriculum fields') from qa3;
update qa3 set legacy_item = (public.upsert_quiz_item(legacy_version, 'identification', 'Name the routing device.', '[]', '"Router"')).id;
select public.review_quiz_item(legacy_item, 'approved') from qa3;
select public.publish_and_assign_quiz(legacy_version, array[class_a, class_b]) from qa3;
update qa3 set legacy_assignment_a = (select id from public.quiz_assignments where class_id = qa3.class_a and quiz_version_id = qa3.legacy_version),
  legacy_assignment_b = (select id from public.quiz_assignments where class_id = qa3.class_b and quiz_version_id = qa3.legacy_version);
select is((select result_release_mode from public.quiz_versions where id = qa3.legacy_version), 'immediate', 'a legacy quiz publishes with immediate results') from qa3;
select set_config('request.jwt.claim.sub', (select learner::text from qa3), true);
update qa3 set legacy_attempt = (public.start_learner_quiz(legacy_assignment_a, gen_random_uuid())->>'attempt_id')::uuid;
select is((public.start_learner_quiz(legacy_assignment_b, gen_random_uuid())->>'attempt_id')::uuid, legacy_attempt,
  'one attempt per learner is shared across classes') from qa3;
select public.save_learner_quiz_answer(legacy_attempt, legacy_item, ' router ') from qa3;
select is((public.submit_learner_quiz(legacy_attempt, gen_random_uuid())->>'correct_count')::int, 1,
  'legacy identification grading is unchanged') from qa3;
reset role;
select throws_ok(format(
  'insert into public.quiz_attempts(learner_id,class_id,quiz_assignment_id,quiz_version_id,client_start_key) values(%L,%L,%L,%L,gen_random_uuid())',
  learner, class_a, legacy_assignment_a, legacy_version),
  '23505', null, 'the quiz-wide attempt claim still rejects a second attempt') from qa3;

select * from finish();
rollback;
