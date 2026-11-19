-- Slice A3 review fix: learners cannot read a quiz total, objective points,
-- item results, essay scores or per-item correctness through direct table
-- queries while an instructor-release attempt is pending, evaluated or
-- finalized. Immediate-mode results and released results stay readable, and
-- saved answers stay readable while the attempt is in progress.
-- Also covers the review's minor items: no scores for unanswered essays,
-- evaluation needs both class and quiz ownership. Rollback-only.
begin;
select plan(31);

create temp table activity_clock(at timestamptz);
insert into activity_clock values ('2035-03-01 08:00:00+00');
grant select on activity_clock to authenticated, service_role;
create or replace function private.activity_server_now() returns timestamptz
language sql volatile security invoker set search_path = '' as $$ select at from pg_temp.activity_clock $$;

create temp table qv as select
  gen_random_uuid() teacher, gen_random_uuid() other_teacher,
  gen_random_uuid() l1, gen_random_uuid() l2, gen_random_uuid() l3, gen_random_uuid() l4, gen_random_uuid() l5, gen_random_uuid() l6,
  gen_random_uuid() class_a,
  (select id from public.coc_modules where coc_code = 'coc1') coc1,
  null::uuid quiz_e, null::uuid version_e, null::uuid e_mc, null::uuid e_essay, null::uuid asg_e,
  null::uuid quiz_r, null::uuid version_r, null::uuid r_tf, null::uuid asg_r,
  null::uuid quiz_i, null::uuid version_i, null::uuid i_tf, null::uuid i_id, null::uuid asg_i,
  null::uuid quiz_t, null::uuid version_t, null::uuid t_mc, null::uuid t_essay, null::uuid asg_t,
  null::uuid a1, null::uuid a2, null::uuid a3, null::uuid a4, null::uuid a5, null::uuid a6;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-visibility.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Quiz visibility fixture"}'::jsonb,now(),now()
from qv cross join lateral (values (teacher),(other_teacher),(l1),(l2),(l3),(l4),(l5),(l6)) ids(id);
update public.profiles set role = 'instructor' where user_id in (select teacher from qv union select other_teacher from qv);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Quiz visibility A','QVA-'||left(class_a::text,8),teacher,teacher from qv;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_a,id,teacher from qv cross join lateral (values (l1),(l2),(l3),(l4),(l5),(l6)) ids(id);
grant all on qv to authenticated, service_role;

select set_config('request.jwt.claim.sub', (select teacher::text from qv), true);
set local role authenticated;
-- E: essay quiz (instructor release forced). R: objective-only, instructor release.
-- I: objective-only, immediate results. T: timed essay quiz (essay left unanswered).
update qv set quiz_e = (public.create_instructor_quiz('Visibility essay quiz', 'Assembly', p_coc_module_id => coc1, p_focus => 'Explain safe assembly')).id;
update qv set version_e = (select id from public.quiz_versions where quiz_id = qv.quiz_e);
update qv set e_mc = (public.upsert_quiz_item(version_e, 'multiple_choice', 'Which tool prevents ESD damage?', '["Wrist strap","Pliers"]', '"Wrist strap"')).id;
update qv set e_essay = (public.upsert_quiz_item(version_e, 'scenario_essay', 'Explain how you would seat the processor.', '[]', '""',
  p_scenario => 'A workstation arrived unassembled on your bench with an anti-static mat.',
  p_rubric => '[{"id":"C1","criterion":"Safety","description":"ESD precautions","max_points":4}]')).id;
select public.review_quiz_item(id, 'approved') from public.quiz_items where quiz_version_id = (select version_e from qv);
select public.publish_and_assign_quiz(version_e, array[class_a]) from qv;
update qv set asg_e = (select id from public.quiz_assignments where quiz_version_id = qv.version_e);
update qv set quiz_r = (public.create_instructor_quiz('Visibility release quiz', 'Testing', p_coc_module_id => coc1,
  p_focus => 'Interpret test results', p_result_release_mode => 'instructor_release')).id;
update qv set version_r = (select id from public.quiz_versions where quiz_id = qv.quiz_r);
update qv set r_tf = (public.upsert_quiz_item(version_r, 'true_false', 'A stress test checks reliability.', '[]', '"true"')).id;
select public.review_quiz_item(r_tf, 'approved') from qv;
select public.publish_and_assign_quiz(version_r, array[class_a]) from qv;
update qv set asg_r = (select id from public.quiz_assignments where quiz_version_id = qv.version_r);
update qv set quiz_i = (public.create_instructor_quiz('Visibility immediate quiz', 'Tools', p_coc_module_id => coc1, p_focus => 'Name assembly tools')).id;
update qv set version_i = (select id from public.quiz_versions where quiz_id = qv.quiz_i);
update qv set i_tf = (public.upsert_quiz_item(version_i, 'true_false', 'A screwdriver set is an assembly tool.', '[]', '"true"')).id;
update qv set i_id = (public.upsert_quiz_item(version_i, 'identification', 'Name the strap that prevents ESD.', '[]', '"Wrist strap"')).id;
select public.review_quiz_item(id, 'approved') from public.quiz_items where quiz_version_id = (select version_i from qv);
select public.publish_and_assign_quiz(version_i, array[class_a]) from qv;
update qv set asg_i = (select id from public.quiz_assignments where quiz_version_id = qv.version_i);
update qv set quiz_t = (public.create_instructor_quiz('Visibility timed essay quiz', 'Memory', p_coc_module_id => coc1,
  p_focus => 'Explain memory installation', p_time_limit_minutes => 5)).id;
update qv set version_t = (select id from public.quiz_versions where quiz_id = qv.quiz_t);
update qv set t_mc = (public.upsert_quiz_item(version_t, 'multiple_choice', 'Which slot holds memory modules?', '["DIMM","PCIe"]', '"DIMM"')).id;
update qv set t_essay = (public.upsert_quiz_item(version_t, 'scenario_essay', 'Explain how you seat a memory module.', '[]', '""',
  p_scenario => 'The motherboard is on the anti-static mat and the latches are closed.',
  p_rubric => '[{"id":"C1","criterion":"Latches","description":"Opens latches first","max_points":5}]')).id;
select public.review_quiz_item(id, 'approved') from public.quiz_items where quiz_version_id = (select version_t from qv);
select public.publish_and_assign_quiz(version_t, array[class_a]) from qv;
update qv set asg_t = (select id from public.quiz_assignments where quiz_version_id = qv.version_t);

-- L1: essay quiz -> pending.  L3: essay quiz -> finalized, released later.
-- L2: instructor-release objective quiz -> evaluated.  L4: immediate quiz -> not_required.
-- L5: immediate quiz still in progress.  L6: timed essay quiz auto-submitted with the essay unanswered.
select set_config('request.jwt.claim.sub', (select l1::text from qv), true);
update qv set a1 = (public.start_learner_quiz(asg_e, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a1, e_mc, 'Wrist strap') from qv;
select public.save_learner_quiz_answer(a1, e_essay, 'I wear a wrist strap and open the socket lever.') from qv;
select public.submit_learner_quiz(a1, gen_random_uuid()) from qv;
select set_config('request.jwt.claim.sub', (select l3::text from qv), true);
update qv set a3 = (public.start_learner_quiz(asg_e, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a3, e_mc, 'Wrist strap') from qv;
select public.save_learner_quiz_answer(a3, e_essay, 'Ground yourself, lift the lever, align the triangle.') from qv;
select public.submit_learner_quiz(a3, gen_random_uuid()) from qv;
select set_config('request.jwt.claim.sub', (select l2::text from qv), true);
update qv set a2 = (public.start_learner_quiz(asg_r, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a2, r_tf, 'True') from qv;
select public.submit_learner_quiz(a2, gen_random_uuid()) from qv;
select set_config('request.jwt.claim.sub', (select l4::text from qv), true);
update qv set a4 = (public.start_learner_quiz(asg_i, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a4, i_tf, 'True') from qv;
select public.save_learner_quiz_answer(a4, i_id, 'wrist strap') from qv;
select public.submit_learner_quiz(a4, gen_random_uuid()) from qv;
select set_config('request.jwt.claim.sub', (select l5::text from qv), true);
update qv set a5 = (public.start_learner_quiz(asg_i, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a5, i_tf, 'False') from qv;
select set_config('request.jwt.claim.sub', (select l6::text from qv), true);
update qv set a6 = (public.start_learner_quiz(asg_t, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(a6, t_mc, 'DIMM') from qv;
reset role;
update activity_clock set at = '2035-03-01 08:06:00+00';
set local role service_role;
select public.process_expired_quiz_attempts(teacher, quiz_t) from qv;
select public.manage_quiz_evaluation(teacher, 'score_essay', jsonb_build_object('attempt_id', a3, 'item_id', e_essay,
  'criterion_scores', jsonb_build_object('C1', 3), 'feedback', 'Clear grounding steps.')) from qv;
select public.manage_quiz_evaluation(teacher, 'finalize', jsonb_build_object('attempt_id', a3)) from qv;
reset role;

select is((select string_agg(evaluation_status, ',' order by learner_id = qv.l1 desc, learner_id = qv.l2 desc, learner_id = qv.l3 desc, learner_id = qv.l4 desc, learner_id = qv.l6 desc)
  from public.quiz_attempts where id in (qv.a1, qv.a2, qv.a3, qv.a4, qv.a6)),
  'pending,evaluated,finalized,not_required,evaluated', 'fixture states: pending, evaluated, finalized, immediate, auto-submitted') from qv;
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id in (qv.a1, qv.a3) and is_correct is not null), 2,
  'objective answers are graded at submission (server copy)') from qv;

-- Pending (essay to score).
select set_config('request.jwt.claim.sub', (select l1::text from qv), true);
set local role authenticated;
select is((select count(*)::int from public.quiz_results where quiz_attempt_id = (select a1 from qv)), 0,
  'a pending attempt exposes no result row (no total, points or item results)');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a1 from qv)), 0,
  'a pending attempt exposes no graded answer rows (no per-item correctness)');
select is((select count(*)::int from public.quiz_essay_scores), 0, 'a pending attempt exposes no essay scores');
select is((select count(*)::int from public.quiz_result_finalizations), 0, 'a pending attempt exposes no finalization');
select ok(not (public.get_learner_quiz_result((select a1 from qv)) ? 'correct_count'), 'the result RPC still hides the total');
select is((select count(*)::int from public.quiz_attempts where id = (select a1 from qv)), 1, 'the learner still sees their own attempt state');

-- Evaluated (instructor release without essays).
select set_config('request.jwt.claim.sub', (select l2::text from qv), true);
select is((select count(*)::int from public.quiz_results where quiz_attempt_id = (select a2 from qv)), 0,
  'an evaluated attempt exposes no result row');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a2 from qv)), 0,
  'an evaluated attempt exposes no graded answers');

-- Finalized but not released.
select set_config('request.jwt.claim.sub', (select l3::text from qv), true);
select is((select count(*)::int from public.quiz_results where quiz_attempt_id = (select a3 from qv)), 0,
  'a finalized attempt exposes no result row before release');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a3 from qv)), 0,
  'a finalized attempt exposes no graded answers before release');
select is((select count(*)::int from public.quiz_essay_scores), 0, 'a finalized attempt exposes no essay score before release');
select is((select count(*)::int from public.quiz_result_finalizations), 0, 'a finalized attempt exposes no total before release');

-- Auto-submitted, evaluated (essay unanswered).
select set_config('request.jwt.claim.sub', (select l6::text from qv), true);
select is((select count(*)::int from public.quiz_results where quiz_attempt_id = (select a6 from qv)), 0,
  'an auto-submitted instructor-release attempt exposes no result row');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a6 from qv)), 0,
  'an auto-submitted instructor-release attempt exposes no graded answers');

-- Immediate mode keeps today's behaviour.
select set_config('request.jwt.claim.sub', (select l4::text from qv), true);
select is((select correct_count || '/' || question_count from public.quiz_results where quiz_attempt_id = (select a4 from qv)), '2/2',
  'an immediate-mode result stays readable directly');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a4 from qv) and is_correct), 2,
  'immediate-mode per-item correctness stays readable directly');

-- In progress: own saved answers stay readable and resumable.
select set_config('request.jwt.claim.sub', (select l5::text from qv), true);
select is((select answer #>> '{}' || ':' || coalesce(is_correct::text, 'ungraded') from public.quiz_answers where quiz_attempt_id = (select a5 from qv)),
  'False:ungraded', 'an in-progress learner reads their saved answer (never graded yet)');
select is((select q->>'saved_answer' from jsonb_array_elements(public.start_learner_quiz((select asg_i from qv), gen_random_uuid())->'questions') q
  where q->>'id' = (select i_tf::text from qv)), 'False', 'resume still restores the saved answer');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a4 from qv)), 0,
  'learners never read another learner''s answers');
reset role;

-- Staff reads are unchanged.
select set_config('request.jwt.claim.sub', (select teacher::text from qv), true);
set local role authenticated;
select is((select count(*)::int from public.quiz_results where quiz_attempt_id in (select a1 from qv union all select a2 from qv union all select a3 from qv union all select a4 from qv union all select a6 from qv)), 5,
  'the owning instructor still reads every result');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a1 from qv) and is_correct is not null), 1,
  'the owning instructor still reads per-item correctness');
reset role;

-- Release: the learner now sees the total, correctness and essay feedback.
set local role service_role;
select public.manage_quiz_evaluation(teacher, 'release', jsonb_build_object('attempt_ids', jsonb_build_array(a3))) from qv;
reset role;
select set_config('request.jwt.claim.sub', (select l3::text from qv), true);
set local role authenticated;
select is((select (objective_points)::int || '/' || (max_points)::int from public.quiz_results where quiz_attempt_id = (select a3 from qv)), '1/5',
  'after release the result row is readable');
select is((select count(*)::int from public.quiz_answers where quiz_attempt_id = (select a3 from qv) and is_correct is not null), 1,
  'after release per-item correctness is readable');
select is((select feedback from public.quiz_essay_scores where attempt_id = (select a3 from qv)), 'Clear grounding steps.',
  'after release the essay feedback is readable');
select is((select total_points::int from public.quiz_result_finalizations where attempt_id = (select a3 from qv)), 4,
  'after release the final total is readable');
reset role;

-- Review minor items: unanswered essays are not scored; evaluation needs both class and quiz ownership.
set local role service_role;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''score_essay'',%L)', teacher,
  jsonb_build_object('attempt_id', a6, 'item_id', t_essay, 'criterion_scores', jsonb_build_object('C1', 2))),
  '22023', 'QUIZ_ESSAY_NOT_ANSWERED', 'an unanswered essay cannot be given points') from qv;
reset role;
update public.classes set instructor_id = (select other_teacher from qv) where id = (select class_a from qv);
set local role service_role;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''finalize'',%L)', other_teacher,
  jsonb_build_object('attempt_id', a6)),
  '42501', 'QUIZ_EVALUATION_SCOPE_DENIED', 'a new class instructor cannot evaluate another instructor''s quiz') from qv;
select throws_ok(format('select public.manage_quiz_evaluation(%L,''finalize'',%L)', teacher,
  jsonb_build_object('attempt_id', a6)),
  '42501', 'QUIZ_EVALUATION_SCOPE_DENIED', 'the quiz owner cannot evaluate learners of a class they no longer teach') from qv;
reset role;
select is((select evaluation_status from public.quiz_attempts where id = (select a6 from qv)), 'evaluated', 'denied actions change nothing');

select * from finish();
rollback;
