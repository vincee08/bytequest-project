-- Slice A3.2: server-enforced time limits and automatic submission of saved
-- answers at the effective expiry (earliest of start + time limit and the
-- class deadline in force). Rollback-only; the controlled server clock exists
-- only inside this transaction.
begin;
select plan(46);

create temp table activity_clock(at timestamptz);
insert into activity_clock values ('2035-01-01 08:00:00+00');
grant select on activity_clock to authenticated, service_role;
create or replace function private.activity_server_now() returns timestamptz
language sql volatile security invoker set search_path = '' as $$ select at from pg_temp.activity_clock $$;

create temp table qt as select
  gen_random_uuid() teacher, gen_random_uuid() other_teacher,
  gen_random_uuid() l1, gen_random_uuid() l2, gen_random_uuid() l3, gen_random_uuid() l4, gen_random_uuid() l5,
  gen_random_uuid() class_a,
  (select id from public.coc_modules where coc_code = 'coc2') coc2,
  null::uuid quiz_t, null::uuid version_t, null::uuid t_mc, null::uuid t_tf, null::uuid t_id, null::uuid asg_t,
  null::uuid quiz_d, null::uuid version_d, null::uuid d_tf, null::uuid asg_d,
  null::uuid quiz_c, null::uuid version_c, null::uuid c_tf, null::uuid asg_c,
  null::uuid quiz_p, null::uuid version_p, null::uuid p_tf, null::uuid asg_p,
  null::uuid t1, null::uuid t2, null::uuid d3, null::uuid c1, null::uuid p4;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-timing.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Quiz timing fixture"}'::jsonb,now(),now()
from qt cross join lateral (values (teacher),(other_teacher),(l1),(l2),(l3),(l4),(l5)) ids(id);
update public.profiles set role = 'instructor' where user_id in (select teacher from qt union select other_teacher from qt);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Quiz timing A','QTA-'||left(class_a::text,8),teacher,teacher from qt;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_a,id,teacher from qt cross join lateral (values (l1),(l2),(l3),(l4),(l5)) ids(id);
grant all on qt to authenticated, service_role;

-- Instructor authoring: a 10-minute timed quiz and three deadline-only quizzes.
select set_config('request.jwt.claim.sub', (select teacher::text from qt), true);
set local role authenticated;
update qt set quiz_t = (public.create_instructor_quiz('Timed network check', 'Network devices', p_coc_module_id => coc2,
  p_focus => 'Identify network devices under time pressure', p_time_limit_minutes => 10)).id;
update qt set version_t = (select id from public.quiz_versions where quiz_id = qt.quiz_t);
update qt set t_mc = (public.upsert_quiz_item(version_t, 'multiple_choice', 'Which device forwards packets between networks?', '["Router","Keyboard"]', '"Router"')).id;
update qt set t_tf = (public.upsert_quiz_item(version_t, 'true_false', 'A hub filters traffic by MAC address.', '[]', '"false"')).id;
update qt set t_id = (public.upsert_quiz_item(version_t, 'identification', 'Name the device that connects hosts in one LAN.', '[]', '"Switch"')).id;
select public.review_quiz_item(id, 'approved') from public.quiz_items where quiz_version_id = (select version_t from qt);
select public.publish_and_assign_quiz(version_t, array[class_a], p_due_at => '2035-01-01 09:00:00+00') from qt;
update qt set asg_t = (select id from public.quiz_assignments where quiz_version_id = qt.version_t);
update qt set quiz_d = (public.create_instructor_quiz('Deadline network check', 'Network media', p_coc_module_id => coc2,
  p_focus => 'Recognise network media')).id;
update qt set version_d = (select id from public.quiz_versions where quiz_id = qt.quiz_d);
update qt set d_tf = (public.upsert_quiz_item(version_d, 'true_false', 'Fiber optic cable carries light signals.', '[]', '"true"')).id;
select public.review_quiz_item(d_tf, 'approved') from qt;
select public.publish_and_assign_quiz(version_d, array[class_a], p_due_at => '2035-01-01 08:30:00+00') from qt;
update qt set asg_d = (select id from public.quiz_assignments where quiz_version_id = qt.version_d);
update qt set quiz_c = (public.create_instructor_quiz('Close-now network check', 'Network tools', p_coc_module_id => coc2,
  p_focus => 'Select network testing tools')).id;
update qt set version_c = (select id from public.quiz_versions where quiz_id = qt.quiz_c);
update qt set c_tf = (public.upsert_quiz_item(version_c, 'true_false', 'A LAN tester checks cable continuity.', '[]', '"true"')).id;
select public.review_quiz_item(c_tf, 'approved') from qt;
select public.publish_and_assign_quiz(version_c, array[class_a], p_due_at => '2035-01-01 12:00:00+00') from qt;
update qt set asg_c = (select id from public.quiz_assignments where quiz_version_id = qt.version_c);
update qt set quiz_p = (public.create_instructor_quiz('Pre-release network check', 'Network history', p_coc_module_id => coc2,
  p_focus => 'Recall network history')).id;
update qt set version_p = (select id from public.quiz_versions where quiz_id = qt.quiz_p);
update qt set p_tf = (public.upsert_quiz_item(version_p, 'true_false', 'Ethernet is a LAN technology.', '[]', '"true"')).id;
select public.review_quiz_item(p_tf, 'approved') from qt;
select public.publish_quiz_version(version_p) from qt;
reset role;

-- An attempt that expired before this release (deadline before the cutover).
insert into public.quiz_assignments(class_id, quiz_version_id, assigned_by, due_at, attempts_allowed)
select class_a, version_p, teacher, '2026-01-01 00:00:00+00', 1 from qt;
update qt set asg_p = (select id from public.quiz_assignments where quiz_version_id = qt.version_p);
insert into public.quiz_attempts(learner_id, class_id, quiz_assignment_id, quiz_version_id, client_start_key, started_at)
select l4, class_a, asg_p, version_p, gen_random_uuid(), '2025-12-31 10:00:00+00' from qt;
update qt set p4 = (select id from public.quiz_attempts where quiz_assignment_id = qt.asg_p);
insert into public.quiz_answers(quiz_attempt_id, quiz_item_id, quiz_version_id, answer)
select p4, p_tf, version_p, '"true"' from qt;

select ok(not has_function_privilege('authenticated', 'private.auto_submit_expired_quiz_attempts(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.auto_submit_expired_quiz_attempts(uuid)', 'EXECUTE'),
  'clients cannot run automatic submission directly');
select ok(not has_function_privilege('authenticated', 'public.process_expired_quiz_attempts(uuid,uuid)', 'EXECUTE'),
  'the instructor processing entry point is service-only');

-- Timed quiz: two learners start at 08:00 (expiry 08:10).
select set_config('request.jwt.claim.sub', (select l1::text from qt), true);
set local role authenticated;
update qt set t1 = (public.start_learner_quiz(asg_t, gen_random_uuid())->>'attempt_id')::uuid;
select is((public.start_learner_quiz(asg_t, gen_random_uuid())->>'time_limit_minutes')::int, 10, 'start returns the time limit') from qt;
select is((public.start_learner_quiz(asg_t, gen_random_uuid())->>'expires_at')::timestamptz, '2035-01-01 08:10:00+00'::timestamptz,
  'start returns the server effective expiry') from qt;
select is((select payload->>'status' from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'quiz_id' = qt.quiz_t::text),
  'in_progress', 'the list shows the attempt in progress') from qt;
select set_config('request.jwt.claim.sub', (select l2::text from qt), true);
update qt set t2 = (public.start_learner_quiz(asg_t, gen_random_uuid())->>'attempt_id')::uuid;
reset role;
update activity_clock set at = '2035-01-01 08:05:00+00';
select is(private.quiz_attempt_effective_expiry(t1), '2035-01-01 08:10:00+00'::timestamptz, 'effective expiry is start + time limit') from qt;
select set_config('request.jwt.claim.sub', (select l1::text from qt), true);
set local role authenticated;
select public.save_learner_quiz_answer(t1, t_mc, 'Router') from qt;
select public.save_learner_quiz_answer(t1, t_tf, 'True') from qt;
select set_config('request.jwt.claim.sub', (select l2::text from qt), true);
select public.save_learner_quiz_answer(t2, t_mc, 'Router') from qt;
select public.save_learner_quiz_answer(t2, t_tf, 'False') from qt;
select public.save_learner_quiz_answer(t2, t_id, 'switch') from qt;
reset role;

-- 08:12: the time limit has passed while both were answering.
update activity_clock set at = '2035-01-01 08:12:00+00';
select set_config('request.jwt.claim.sub', (select l2::text from qt), true);
set local role authenticated;
select throws_ok(format('select public.save_learner_quiz_answer(%L,%L,%L)', t2, t_id, 'Router'),
  '42501', 'QUIZ_NOT_AVAILABLE', 'a save after expiry is refused') from qt;
select is(public.submit_learner_quiz(t2, gen_random_uuid())->>'submission_kind', 'auto_time_limit',
  'a submit after expiry returns the automatic submission') from qt;
reset role;
select is((select status::text || '|' || submission_kind || '|' || submitted_at::text from public.quiz_attempts where id = qt.t1),
  'completed|auto_time_limit|2035-01-01 08:10:00+00', 'expiry_while_answering_auto_submits_saved_answers: submitted at the expiry time') from qt;
select is((select correct_count || '/' || question_count from public.quiz_results where quiz_attempt_id = qt.t1), '1/3',
  'saved answers are graded; the unanswered item scores zero') from qt;
select is((select count(*)::int from jsonb_array_elements((select item_results from public.quiz_results where quiz_attempt_id = qt.t1)) r
  where r->>'answered' = 'false' and r->>'learner_answer' is null and r->>'is_correct' = 'false'), 1,
  'the unanswered item is recorded as not answered, nothing invented') from qt;
select is((select correct_count from public.quiz_results where quiz_attempt_id = qt.t2), 3, 'the second learner keeps every saved answer') from qt;
select is((select submitted_at from public.quiz_attempts where id = qt.t2), '2035-01-01 08:10:00+00'::timestamptz,
  'the submit after expiry is recorded at the expiry, not at the request time') from qt;
select is((select answer #>> '{}' from public.quiz_answers where quiz_attempt_id = qt.t2 and quiz_item_id = qt.t_id), 'switch',
  'the refused save did not change the saved answer') from qt;
select is(private.auto_submit_expired_quiz_attempts(asg_t), 0, 'auto-submission is idempotent') from qt;
select is((select count(*)::int from public.quiz_results where quiz_attempt_id in (qt.t1, qt.t2)), 2, 'exactly one result per attempt') from qt;
select is((select count(*)::int from public.audit_events where action = 'quiz_attempt.auto_submitted' and target_id in (qt.t1, qt.t2)), 2,
  'exactly one automatic-submission audit event per attempt') from qt;
select set_config('request.jwt.claim.sub', (select l1::text from qt), true);
set local role authenticated;
select is(public.get_learner_quiz_result(t1)->>'submission_kind', 'auto_time_limit', 'the result explains the automatic submission') from qt;
select is((select payload->>'status' || '|' || (payload->>'submission_kind') from jsonb_array_elements(public.get_available_learner_quizzes()) payload
  where payload->>'quiz_id' = qt.quiz_t::text), 'completed|auto_time_limit', 'the list shows the auto-submitted state') from qt;
select throws_ok(format('select public.start_learner_quiz(%L,gen_random_uuid())', asg_t), '55000', 'QUIZ_ATTEMPT_ALREADY_SUBMITTED',
  'an auto-submitted attempt cannot be resumed') from qt;
reset role;

-- Deadline-only quiz: an extension before expiry extends the attempt.
update activity_clock set at = '2035-01-01 08:20:00+00';
select set_config('request.jwt.claim.sub', (select l3::text from qt), true);
set local role authenticated;
update qt set d3 = (public.start_learner_quiz(asg_d, gen_random_uuid())->>'attempt_id')::uuid;
select is((public.start_learner_quiz(asg_d, gen_random_uuid())->>'expires_at')::timestamptz, '2035-01-01 08:30:00+00'::timestamptz,
  'a deadline-only attempt expires at the class deadline') from qt;
reset role;
update activity_clock set at = '2035-01-01 08:25:00+00';
set local role service_role;
select public.set_quiz_assignment_deadline(teacher, asg_d, '2035-01-01 09:00:00+00', false) from qt;
reset role;
update activity_clock set at = '2035-01-01 08:40:00+00';
select set_config('request.jwt.claim.sub', (select l3::text from qt), true);
set local role authenticated;
select lives_ok(format('select public.save_learner_quiz_answer(%L,%L,%L)', d3, d_tf, 'True'),
  'extension_before_expiry_extends_attempt: saving after the old deadline works') from qt;
select is((select (payload->>'expires_at')::timestamptz from jsonb_array_elements(public.get_available_learner_quizzes()) payload
  where payload->>'quiz_id' = qt.quiz_d::text), '2035-01-01 09:00:00+00'::timestamptz, 'the list shows the extended expiry') from qt;
reset role;

-- 09:05: the extended deadline passed; nobody opened the quiz. Reopening finalises first.
update activity_clock set at = '2035-01-01 09:05:00+00';
select is((select status::text from public.quiz_attempts where id = qt.d3), 'in_progress', 'nothing has processed the expired attempt yet') from qt;
set local role service_role;
select public.set_quiz_assignment_deadline(teacher, asg_d, '2035-01-01 10:00:00+00', true) from qt;
reset role;
select is((select status::text || '|' || submission_kind || '|' || submitted_at::text from public.quiz_attempts where id = qt.d3),
  'completed|auto_deadline|2035-01-01 09:00:00+00', 'reopen_after_expiry_finalizes_first: the attempt is final at the old deadline') from qt;
select is((select correct_count from public.quiz_results where quiz_attempt_id = qt.d3), 1, 'the saved answer was graded') from qt;
select set_config('request.jwt.claim.sub', (select l3::text from qt), true);
set local role authenticated;
select throws_ok(format('select public.start_learner_quiz(%L,gen_random_uuid())', asg_d), '55000', 'QUIZ_ATTEMPT_ALREADY_SUBMITTED',
  'reopening does not revive an auto-submitted attempt') from qt;
select set_config('request.jwt.claim.sub', (select l5::text from qt), true);
select ok(public.start_learner_quiz(asg_d, gen_random_uuid())->>'attempt_id' is not null, 'reopening lets a learner who never started take the quiz') from qt;
reset role;

-- Pre-release attempt: expired before this migration; left exactly as it is.
select is(private.auto_submit_expired_quiz_attempts(asg_p), 0, 'pre_release_expired_attempt_untouched: no automatic submission') from qt;
select is((select status::text from public.quiz_attempts where id = qt.p4), 'in_progress', 'the pre-release attempt stays in progress') from qt;
select is((select count(*)::int from public.quiz_results where quiz_attempt_id = qt.p4), 0, 'no retroactive grading') from qt;
select set_config('request.jwt.claim.sub', (select l4::text from qt), true);
set local role authenticated;
select is((select payload->>'status' from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'quiz_id' = qt.quiz_p::text),
  'closed', 'the pre-release attempt shows as closed') from qt;
select throws_ok(format('select public.save_learner_quiz_answer(%L,%L,%L)', p4, p_tf, 'False'), '42501', 'QUIZ_NOT_AVAILABLE',
  'saving into the expired pre-release attempt is refused') from qt;
reset role;
set local role service_role;
select public.set_quiz_assignment_deadline(teacher, asg_p, '2035-01-02 08:00:00+00', true) from qt;
reset role;
select set_config('request.jwt.claim.sub', (select l4::text from qt), true);
set local role authenticated;
select is((public.start_learner_quiz(asg_p, gen_random_uuid())->>'attempt_id')::uuid, p4,
  'after a reopen the pre-release attempt resumes as before') from qt;
reset role;

-- Close now: in-progress attempts are submitted at the close time.
update activity_clock set at = '2035-01-01 09:10:00+00';
select set_config('request.jwt.claim.sub', (select l1::text from qt), true);
set local role authenticated;
update qt set c1 = (public.start_learner_quiz(asg_c, gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(c1, c_tf, 'True') from qt;
reset role;
update activity_clock set at = '2035-01-01 09:20:00+00';
set local role service_role;
select throws_ok(format('select public.set_quiz_assignment_deadline(%L,%L,null,false,true)', other_teacher, asg_c), '42501',
  'INSTRUCTOR_CLASS_SCOPE_REQUIRED', 'only the owning instructor can close a quiz') from qt;
select is((public.set_quiz_assignment_deadline(teacher, asg_c, null, false, true)).due_at, '2035-01-01 09:20:00+00'::timestamptz,
  'close now sets the class deadline to the server time') from qt;
select throws_ok(format('select public.set_quiz_assignment_deadline(%L,%L,null,false,true)', teacher, asg_c), '22023',
  'QUIZ_ALREADY_CLOSED', 'a closed quiz cannot be closed again') from qt;
reset role;
select is((select status::text || '|' || submission_kind || '|' || submitted_at::text from public.quiz_attempts where id = qt.c1),
  'completed|auto_deadline|2035-01-01 09:20:00+00', 'close now auto-submits the attempt in progress') from qt;
select is((select count(*)::int from public.audit_events where action = 'quiz.deadline_changed' and target_id = qt.asg_c
  and (metadata->>'closed_now')::boolean), 1, 'close now is audited as a deadline change') from qt;
select set_config('request.jwt.claim.sub', (select l2::text from qt), true);
set local role authenticated;
select throws_ok(format('select public.start_learner_quiz(%L,gen_random_uuid())', asg_c), '42501', 'QUIZ_NOT_AVAILABLE',
  'nobody can start a closed quiz') from qt;
reset role;

-- Instructor results read path.
set local role service_role;
select throws_ok(format('select public.process_expired_quiz_attempts(%L,%L)', other_teacher, quiz_t), '42501', 'QUIZ_SCOPE_DENIED',
  'another instructor cannot process this quiz') from qt;
select is(public.process_expired_quiz_attempts(teacher, quiz_t), 0, 'processing an already-final quiz changes nothing') from qt;
reset role;

-- Effective expiry follows the deadline in force; a later deadline cannot shorten a submitted attempt.
select is((select count(*)::int from public.quiz_attempts a where a.id in (qt.t1, qt.t2, qt.d3, qt.c1) and a.status = 'completed'), 4,
  'every expired attempt is final') from qt;
select is((select count(*)::int from public.quiz_attempts where learner_id = qt.l5 and quiz_assignment_id = qt.asg_d and status = 'in_progress'), 1,
  'the never-started learner has a fresh attempt after the reopen') from qt;
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relname = 'quiz_auto_submission_config' and not c.relrowsecurity),
  'the cutover configuration keeps RLS enabled');
select is((select count(*)::int from private.quiz_auto_submission_config), 1, 'one cutover timestamp is recorded');

select * from finish();
rollback;
