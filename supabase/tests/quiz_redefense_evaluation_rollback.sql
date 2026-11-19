-- Slice A3.3: scenario essay scoring by rubric, Evaluate -> Finalize -> Release
-- for quizzes in instructor-release mode, and the Evaluation Center queue item
-- contract. Rollback-only with a controlled server clock.
begin;
select plan(62);

create temp table activity_clock(at timestamptz);
insert into activity_clock values ('2035-02-01 08:00:00+00');
grant select on activity_clock to authenticated, service_role;
create or replace function private.activity_server_now() returns timestamptz
language sql volatile security invoker set search_path = '' as $$ select at from pg_temp.activity_clock $$;

create temp table qe as select
  gen_random_uuid() teacher, gen_random_uuid() other_teacher, gen_random_uuid() admin_user,
  gen_random_uuid() l1, gen_random_uuid() l2, gen_random_uuid() l3, gen_random_uuid() class_a, gen_random_uuid() class_x,
  (select id from public.coc_modules where coc_code = 'coc1') coc1,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1') lo11,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.4') lo14,
  null::uuid quiz_e, null::uuid version_e, null::uuid e_mc, null::uuid e_tf, null::uuid e_essay, null::uuid asg_e,
  null::uuid quiz_r, null::uuid version_r, null::uuid r_tf, null::uuid asg_r,
  null::uuid quiz_t, null::uuid version_t, null::uuid t_mc, null::uuid t_essay, null::uuid asg_t,
  null::uuid a1, null::uuid a2, null::uuid a3, null::jsonb result_pending, null::jsonb result_released;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-evaluation.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', name), now(), now()
from qe cross join lateral (values (teacher,'Eval Teacher'),(other_teacher,'Other Teacher'),(admin_user,'Eval Admin'),
  (l1,'Learner One'),(l2,'Learner Two'),(l3,'Learner Three')) ids(id, name);
update public.profiles set role = 'instructor' where user_id in (select teacher from qe union select other_teacher from qe);
update public.profiles set role = 'admin' where user_id = (select admin_user from qe);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Evaluation A','QEA-'||left(class_a::text,8),teacher,teacher from qe union all
select class_x,'Other class','QEX-'||left(class_x::text,8),other_teacher,other_teacher from qe;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_a,id,teacher from qe cross join lateral (values (l1),(l2),(l3)) ids(id);
grant all on qe to authenticated, service_role;

select set_config('request.jwt.claim.sub', (select teacher::text from qe), true);
set local role authenticated;
-- Quiz E: two objective items (2 + 1 points) and one essay (4 + 6 points).
update qe set quiz_e = (public.create_instructor_quiz('Assembly essay check', 'Assembly', p_coc_module_id => coc1,
  p_focus => 'Explain safe CPU installation', p_module_ids => array[lo11])).id;
update qe set version_e = (select id from public.quiz_versions where quiz_id = qe.quiz_e);
update qe set e_mc = (public.upsert_quiz_item(version_e, 'multiple_choice', 'Which tool prevents ESD damage?', '["Wrist strap","Pliers"]', '"Wrist strap"', p_points => 2)).id;
update qe set e_tf = (public.upsert_quiz_item(version_e, 'true_false', 'Thermal paste goes between CPU and cooler.', '[]', '"true"')).id;
update qe set e_essay = (public.upsert_quiz_item(version_e, 'scenario_essay', 'Explain how you would install the processor safely.', '[]',
  '"ESD strap, lever, triangle, POST"', p_scenario => 'A client left an unassembled workstation on your bench with an anti-static mat.',
  p_rubric => '[{"id":"C1","criterion":"Safety","description":"ESD precautions before handling","max_points":4},{"id":"C2","criterion":"Procedure","description":"Lever, alignment and seating","max_points":6}]')).id;
select public.review_quiz_item(id, 'approved') from public.quiz_items where quiz_version_id = (select version_e from qe);
select public.publish_and_assign_quiz(version_e, array[class_a], p_due_at => '2035-02-01 12:00:00+00') from qe;
update qe set asg_e = (select id from public.quiz_assignments where quiz_version_id = qe.version_e);
-- Quiz R: objective only, instructor release chosen by the instructor.
update qe set quiz_r = (public.create_instructor_quiz('Testing release check', 'Testing', p_coc_module_id => coc1,
  p_focus => 'Interpret test results', p_module_ids => array[lo14], p_result_release_mode => 'instructor_release')).id;
update qe set version_r = (select id from public.quiz_versions where quiz_id = qe.quiz_r);
update qe set r_tf = (public.upsert_quiz_item(version_r, 'true_false', 'A stress test checks reliability.', '[]', '"true"')).id;
select public.review_quiz_item(r_tf, 'approved') from qe;
select public.publish_and_assign_quiz(version_r, array[class_a], p_due_at => '2035-02-01 12:00:00+00') from qe;
update qe set asg_r = (select id from public.quiz_assignments where quiz_version_id = qe.version_r);
-- Quiz T: timed essay quiz; the essay is left unanswered.
update qe set quiz_t = (public.create_instructor_quiz('Timed essay check', 'Assembly', p_coc_module_id => coc1,
  p_focus => 'Explain RAM installation', p_time_limit_minutes => 5)).id;
update qe set version_t = (select id from public.quiz_versions where quiz_id = qe.quiz_t);
update qe set t_mc = (public.upsert_quiz_item(version_t, 'multiple_choice', 'Which slot holds memory modules?', '["DIMM","PCIe"]', '"DIMM"')).id;
update qe set t_essay = (public.upsert_quiz_item(version_t, 'scenario_essay', 'Explain how you seat a memory module.', '[]', '""',
  p_scenario => 'The motherboard is on the anti-static mat and the latches are closed.',
  p_rubric => '[{"criterion":"Latches","description":"Opens latches first","max_points":5}]')).id;
select public.review_quiz_item(id, 'approved') from public.quiz_items where quiz_version_id = (select version_t from qe);
select public.publish_and_assign_quiz(version_t, array[class_a], p_due_at => '2035-02-01 12:00:00+00') from qe;
update qe set asg_t = (select id from public.quiz_assignments where quiz_version_id = qe.version_t);
reset role;

select is((select result_release_mode from public.quiz_versions where id = qe.version_e), 'instructor_release', 'essay quiz uses instructor release') from qe;
select ok(not has_function_privilege('authenticated', 'public.manage_quiz_evaluation(uuid,text,jsonb)', 'EXECUTE'),
  'evaluation actions are service-only');
select ok(not has_table_privilege('authenticated', 'public.quiz_essay_scores', 'INSERT')
  and not has_table_privilege('authenticated', 'public.quiz_result_finalizations', 'UPDATE'),
  'clients cannot write scores or finalizations');

-- Learner One answers everything, including a long essay, and submits.
select set_config('request.jwt.claim.sub', (select l1::text from qe), true);
set local role authenticated;
update qe set a1 = (public.start_learner_quiz(asg_e, gen_random_uuid())->>'attempt_id')::uuid;
select is((select jsonb_array_length(q->'rubric') || ':' || (q->'rubric'->0 ? 'description')::text || ':' || (q->>'scenario' is not null)::text
  from jsonb_array_elements(public.start_learner_quiz(asg_e, gen_random_uuid())->'questions') q where q->>'type' = 'scenario_essay'),
  '2:false:true', 'essay questions show the scenario and criterion names but not the scoring descriptors') from qe;
select public.save_learner_quiz_answer(a1, e_mc, 'Wrist strap') from qe;
select public.save_learner_quiz_answer(a1, e_tf, 'True') from qe;
select lives_ok(format('select public.save_learner_quiz_answer(%L,%L,%L)', a1, e_essay, repeat('Ground yourself, open the lever, align the triangle. ', 60)),
  'essay answers longer than the objective limit are saved') from qe;
select throws_ok(format('select public.save_learner_quiz_answer(%L,%L,%L)', a1, e_mc, repeat('x', 2001)),
  '22023', 'QUIZ_ANSWER_REQUIRED', 'objective answers keep their length limit') from qe;
select is(public.submit_learner_quiz(a1, gen_random_uuid()) ? 'correct_count', false, 'submission shows no total before release') from qe;
update qe set result_pending = public.get_learner_quiz_result(a1);
select is(result_pending->>'result_status', 'awaiting_evaluation', 'the learner sees Awaiting instructor evaluation') from qe;
select ok(not (result_pending ? 'correct_count') and not (result_pending ? 'objective_points')
  and not exists (select 1 from jsonb_array_elements(result_pending->'item_results') r where r ? 'is_correct'),
  'no score or correctness is shown before release') from qe;
select is((select payload->>'status' from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'quiz_id' = qe.quiz_e::text),
  'awaiting_evaluation', 'the list shows awaiting evaluation') from qe;
select is((select count(*)::int from public.quiz_essay_scores), 0, 'learners cannot read unreleased essay scores');
reset role;

select is((select evaluation_status from public.quiz_attempts where id = qe.a1), 'pending', 'an answered essay leaves the attempt pending') from qe;
select is((select string_agg(coalesce(is_correct::text, 'null'), ',' order by quiz_item_id = qe.e_essay, quiz_item_id = qe.e_tf)
  from public.quiz_answers where quiz_attempt_id = qe.a1), 'true,true,null', 'objective items are graded at submission; the essay is not') from qe;
select is((select objective_points || '/' || max_points from public.quiz_results where quiz_attempt_id = qe.a1), '3/13',
  'objective points and maximum points are recorded') from qe;

-- Evaluation Center queue: evaluate stage.
select set_config('request.jwt.claim.sub', (select teacher::text from qe), true);
set local role authenticated;
select is((select jsonb_agg(k order by k) from jsonb_object_keys(public.quiz_evaluation_queue_items('evaluate', '{}')->0) k),
  '["class", "id", "kind", "learner", "link", "max_score", "score", "status", "submitted_at", "title"]'::jsonb,
  'queue items have the exact Evaluation Center shape');
select is((select item->>'kind' || '|' || (item->>'id') || '|' || (item->>'status') || '|' || coalesce(item->>'score', 'null') || '|' || (item->>'max_score')
  || '|' || (item->'learner'->>'name') || '|' || (item->'class'->>'title') || '|' || (item->>'title')
  from jsonb_array_elements(public.quiz_evaluation_queue_items('evaluate', '{}')) item where item->>'id' = qe.a1::text),
  'quiz|' || a1 || '|pending|null|13|Learner One|Evaluation A|Assembly essay check', 'evaluate lists the pending essay attempt') from qe;
select is((select item->>'link' from jsonb_array_elements(public.quiz_evaluation_queue_items('evaluate', '{}')) item where item->>'id' = qe.a1::text),
  '/quizzes/' || quiz_e || '?tab=results&attempt=' || a1, 'the item links to the quiz results tab') from qe;
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate', jsonb_build_object('class_id', class_x))), 0, 'class filter') from qe;
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate', jsonb_build_object('learner_id', l2))), 0, 'learner filter') from qe;
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate', '{"coc_code":"coc2"}')), 0, 'COC filter');
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate', jsonb_build_object('module_id', lo11, 'coc_code', 'coc1'))), 1, 'module filter') from qe;
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate', jsonb_build_object('module_id', lo14))), 0, 'module filter excludes other modules') from qe;
select throws_ok($$select public.quiz_evaluation_queue_items('grading', '{}')$$, '22023', 'INVALID_EVALUATION_STAGE', 'unknown stages are rejected');
select set_config('request.jwt.claim.sub', (select other_teacher::text from qe), true);
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate', '{}')), 0, 'other instructors see none of these items');
select set_config('request.jwt.claim.sub', (select admin_user::text from qe), true);
select is((select count(*)::int from jsonb_array_elements(public.quiz_evaluation_queue_items('evaluate', '{}')) item where item->>'id' = qe.a1::text), 1,
  'admins can read the queue') from qe;
select set_config('request.jwt.claim.sub', (select l1::text from qe), true);
select throws_ok($$select public.quiz_evaluation_queue_items('evaluate', '{}')$$, '42501', 'STAFF_REQUIRED', 'learners cannot read the queue');
reset role;

-- Scoring rules (service-only, owning instructor).
set local role service_role;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''score_essay'',%L)', other_teacher,
  jsonb_build_object('attempt_id', a1, 'item_id', e_essay, 'criterion_scores', jsonb_build_object('C1', 3, 'C2', 5))),
  '42501', 'QUIZ_EVALUATION_SCOPE_DENIED', 'only the owning instructor scores essays') from qe;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''score_essay'',%L)', teacher,
  jsonb_build_object('attempt_id', a1, 'item_id', e_essay, 'criterion_scores', jsonb_build_object('C1', 5, 'C2', 5))),
  '22023', 'QUIZ_ESSAY_SCORE_INVALID', 'a criterion score cannot exceed its maximum') from qe;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''score_essay'',%L)', teacher,
  jsonb_build_object('attempt_id', a1, 'item_id', e_essay, 'criterion_scores', jsonb_build_object('C1', -1, 'C2', 5))),
  '22023', 'QUIZ_ESSAY_SCORE_INVALID', 'a criterion score cannot be negative') from qe;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''score_essay'',%L)', teacher,
  jsonb_build_object('attempt_id', a1, 'item_id', e_essay, 'criterion_scores', jsonb_build_object('C1', 3))),
  '22023', 'QUIZ_ESSAY_SCORE_INVALID', 'every rubric criterion must be scored') from qe;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''finalize'',%L)', teacher, jsonb_build_object('attempt_id', a1)),
  '55000', 'QUIZ_ESSAYS_NOT_SCORED', 'finalize requires every essay to be scored') from qe;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''release'',%L)', teacher, jsonb_build_object('attempt_ids', jsonb_build_array(a1))),
  '55000', 'QUIZ_RESULT_NOT_FINALIZED', 'release requires finalization') from qe;
select is(public.manage_quiz_evaluation(teacher, 'score_essay', jsonb_build_object('attempt_id', a1, 'item_id', e_essay,
  'criterion_scores', jsonb_build_object('C1', 3, 'C2', 5), 'feedback', 'Good ESD steps.'))->>'evaluation_status', 'evaluated',
  'scoring every essay moves the attempt to evaluated') from qe;
select is((public.manage_quiz_evaluation(teacher, 'score_essay', jsonb_build_object('attempt_id', a1, 'item_id', e_essay,
  'criterion_scores', jsonb_build_object('C1', 4, 'C2', 5), 'feedback', 'Complete ESD and orientation steps.'))->>'total')::numeric, 9::numeric,
  'a re-score records a new total') from qe;
reset role;
select is((select count(*)::int from public.quiz_essay_scores where attempt_id = qe.a1), 2, 'essay score history is append-only') from qe;
select throws_ok(format('update public.quiz_essay_scores set total = 0 where attempt_id = %L', a1), '55000', null,
  'essay scores cannot be edited') from qe;
select throws_ok(format('delete from public.quiz_essay_scores where attempt_id = %L', a1), '55000', null,
  'essay scores cannot be deleted') from qe;
select set_config('request.jwt.claim.sub', (select teacher::text from qe), true);
set local role authenticated;
select is((select (item->>'score')::numeric from jsonb_array_elements(public.quiz_evaluation_queue_items('finalize', '{}')) item where item->>'id' = qe.a1::text),
  12::numeric, 'the finalize stage shows objective plus latest essay points') from qe;
select is((select count(*)::int from public.quiz_essay_scores where attempt_id = qe.a1), 2, 'the owning instructor reads the score history') from qe;
select set_config('request.jwt.claim.sub', (select l1::text from qe), true);
select is(public.get_learner_quiz_result(a1)->>'result_status', 'awaiting_evaluation', 'an evaluated result stays hidden from the learner') from qe;
reset role;

set local role service_role;
select is((select (r->>'total_points')::numeric || '/' || (r->>'max_points')::numeric || '/' || (r->>'percent')::numeric
  from (select public.manage_quiz_evaluation(teacher, 'finalize', jsonb_build_object('attempt_id', a1)) r) s), '12/13/92.31',
  'finalize records objective plus essay points') from qe;
select is(public.manage_quiz_evaluation(teacher, 'finalize', jsonb_build_object('attempt_id', a1))->>'already', 'true', 'finalize is idempotent') from qe;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''score_essay'',%L)', teacher,
  jsonb_build_object('attempt_id', a1, 'item_id', e_essay, 'criterion_scores', jsonb_build_object('C1', 1, 'C2', 1))),
  '55000', 'QUIZ_EVALUATION_STATE_INVALID', 'a finalized result cannot be re-scored') from qe;
reset role;
select is((select evaluation_status from public.quiz_attempts where id = qe.a1), 'finalized', 'the attempt is finalized') from qe;
select throws_ok(format('update public.quiz_result_finalizations set total_points = 13 where attempt_id = %L', a1), '55000', null,
  'finalized totals are immutable') from qe;
select set_config('request.jwt.claim.sub', (select l1::text from qe), true);
set local role authenticated;
select is(public.get_learner_quiz_result(a1)->>'result_status', 'awaiting_evaluation', 'a finalized result stays hidden until release') from qe;
select is((select count(*)::int from public.quiz_result_finalizations), 0, 'learners cannot read unreleased finalizations');
reset role;
set local role service_role;
select is(jsonb_array_length(public.manage_quiz_evaluation(teacher, 'release', jsonb_build_object('attempt_ids', jsonb_build_array(a1)))->'released'), 1,
  'release publishes the result') from qe;
select is(jsonb_array_length(public.manage_quiz_evaluation(teacher, 'release', jsonb_build_object('attempt_ids', jsonb_build_array(a1)))->'already_released'), 1,
  'release is idempotent') from qe;
reset role;

select set_config('request.jwt.claim.sub', (select l1::text from qe), true);
set local role authenticated;
update qe set result_released = public.get_learner_quiz_result(a1);
select is(result_released->>'result_status' || '|' || (result_released->>'total_points') || '/' || (result_released->>'max_points'),
  'released|12/13', 'the released result shows the final total') from qe;
select is((select r->>'feedback' || '|' || (r->>'points_awarded') || '|' || jsonb_array_length(r->'rubric') || '|' || (r->'rubric'->0->>'points') || '|' || (r->'rubric'->0->>'description')
  from jsonb_array_elements(result_released->'item_results') r where r->>'type' = 'scenario_essay'),
  'Complete ESD and orientation steps.|9|2|4|ESD precautions before handling', 'released rubric feedback shows criterion points and descriptors') from qe;
select is((select count(*)::int from public.quiz_essay_scores), 2, 'the learner can read released essay scores') from qe;
select is((select payload->>'status' from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'quiz_id' = qe.quiz_e::text),
  'released', 'the list shows the released result') from qe;
reset role;
select is((select string_agg(action || '=' || n, ',' order by action) from (
  select action, count(*) n from public.audit_events where target_id = qe.a1 and action like 'quiz_%.%' and action <> 'quiz_attempt.started'
  group by action) s), 'quiz_attempt.completed=1,quiz_essay.scored=2,quiz_result.finalized=1,quiz_result.released=1',
  'every evaluation action is audited exactly once') from qe;

-- Instructor release without essays goes straight to evaluated.
select set_config('request.jwt.claim.sub', (select l2::text from qe), true);
set local role authenticated;
update qe set a2 = (public.start_learner_quiz(asg_r, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a2, r_tf, 'True') from qe;
select is(public.submit_learner_quiz(a2, gen_random_uuid())->>'evaluation_status', 'evaluated', 'instructor release without essays is evaluated at submission') from qe;
reset role;
set local role service_role;
select is((public.manage_quiz_evaluation(teacher, 'finalize', jsonb_build_object('attempt_ids', jsonb_build_array(a2)))->'results'->0->>'total_points')::numeric,
  1::numeric, 'bulk finalize records the objective score') from qe;
reset role;

-- Timed essay quiz: the essay is unanswered when time runs out; it scores zero.
select set_config('request.jwt.claim.sub', (select l3::text from qe), true);
set local role authenticated;
update qe set a3 = (public.start_learner_quiz(asg_t, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a3, t_mc, 'DIMM') from qe;
reset role;
update activity_clock set at = '2035-02-01 08:06:00+00';
select set_config('request.jwt.claim.sub', (select l3::text from qe), true);
set local role authenticated;
select is(public.get_learner_quiz_result(a3)->>'submission_kind' || '|' || (public.get_learner_quiz_result(a3)->>'result_status'),
  'auto_time_limit|awaiting_evaluation', 'an auto-submitted essay quiz awaits instructor release') from qe;
reset role;
select is((select evaluation_status from public.quiz_attempts where id = qe.a3), 'evaluated',
  'an unanswered essay needs no scoring and counts zero') from qe;
set local role service_role;
select is((public.manage_quiz_evaluation(teacher, 'finalize', jsonb_build_object('attempt_id', a3))->>'total_points')::numeric, 1::numeric,
  'the unanswered essay adds zero points') from qe;
reset role;
select set_config('request.jwt.claim.sub', (select teacher::text from qe), true);
set local role authenticated;
select is((select count(*)::int from jsonb_array_elements(public.quiz_evaluation_queue_items('release', '{}')) item
  where item->>'id' in (qe.a2::text, qe.a3::text)), 2, 'finalized attempts wait in the release stage') from qe;
select is((select count(*)::int from jsonb_array_elements(public.quiz_evaluation_queue_items('released', '{}')) item where item->>'id' = qe.a1::text), 1,
  'released attempts appear in the released stage') from qe;
reset role;
select ok((select relrowsecurity from pg_class where oid = 'public.quiz_essay_scores'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.quiz_result_finalizations'::regclass), 'evaluation tables keep RLS enabled');

select * from finish();
rollback;
