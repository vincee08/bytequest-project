-- Learner status reflects missed deadlines (20261123130000): realistic
-- instructor/learner scenarios. Every fixture is rolled back.
begin;
select plan(23);

create temporary table dx (
  teacher uuid default gen_random_uuid(), class_id uuid default gen_random_uuid(),
  olive uuid default gen_random_uuid(), hugo uuid default gen_random_uuid(), quinn uuid default gen_random_uuid(),
  lara uuid default gen_random_uuid(), ian uuid default gen_random_uuid(),
  h_past uuid default gen_random_uuid(), h_ext uuid default gen_random_uuid(),
  q_past uuid default gen_random_uuid(), q_past_v uuid default gen_random_uuid(), qa_past uuid default gen_random_uuid(),
  q_reopen uuid default gen_random_uuid(), q_reopen_v uuid default gen_random_uuid(), qa_reopen uuid default gen_random_uuid(),
  q_gone uuid default gen_random_uuid(), q_gone_v uuid default gen_random_uuid(), qa_gone uuid default gen_random_uuid(),
  coc1 uuid
);
insert into dx default values;
update dx set coc1 = (select id from public.coc_modules where coc_code = 'coc1');
create temporary table dr (name text primary key, v jsonb);
grant select on dx to authenticated;
grant select, insert on dr to authenticated;

-- Identities: handle_new_user provisions active learner profiles.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select u.id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',u.id||'@analytics-deadline.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',u.name),now(),now()
from dx cross join lateral (values
  (teacher,'Deadline Teacher'),(olive,'Olive OnTime'),(hugo,'Hugo MissedHomework'),(quinn,'Quinn MissedQuiz'),
  (lara,'Lara LateJoiner'),(ian,'Ian InProgress')) u(id,name);
update public.profiles set role = 'instructor' where user_id = (select teacher from dx);

insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_id,'Deadline Class','DL-'||left(class_id::text,8),teacher,teacher from dx;
-- Everyone joined 10 days ago (so nobody is inactive), except Lara who joined
-- yesterday, after every deadline below.
insert into public.class_memberships(class_id,learner_id,enrolled_by,enrolled_at)
select class_id,olive,teacher,now()-interval '10 days' from dx union all
select class_id,hugo,teacher,now()-interval '10 days' from dx union all
select class_id,quinn,teacher,now()-interval '10 days' from dx union all
select class_id,ian,teacher,now()-interval '10 days' from dx union all
select class_id,lara,teacher,now()-interval '1 day' from dx;

-- Homework: one deadline three days ago; one extended to two days from now.
insert into public.homework_assignments(id,class_id,instructor_id,title,instructions,status,deadline_at,published_at,revision)
select h_past,class_id,teacher,'Cable test report','Submit the report.','published',now()-interval '3 days',now()-interval '9 days',1 from dx union all
select h_ext,class_id,teacher,'Extended wiring plan','Submit the plan.','published',now()+interval '2 days',now()-interval '9 days',2 from dx;
insert into public.homework_submissions(assignment_id,learner_id,answer,submitted_at,effective_deadline_at,deadline_revision)
select h_past,olive,'Report',now()-interval '4 days',now()-interval '3 days',1 from dx union all
select h_past,quinn,'Report',now()-interval '4 days',now()-interval '3 days',1 from dx union all
select h_past,ian,'Report',now()-interval '4 days',now()-interval '3 days',1 from dx;

-- Quizzes: due three days ago; reopened until two days from now; withdrawn
-- (closed before its deadline).
insert into public.quizzes(id,instructor_id,coc_module_id,title,topic,created_by)
select q_past,teacher,coc1,'Safety quiz','Safety',teacher from dx union all
select q_reopen,teacher,coc1,'Reopened tools quiz','Tools',teacher from dx union all
select q_gone,teacher,coc1,'Withdrawn quiz','Tools',teacher from dx;
insert into public.quiz_versions(id,quiz_id,version_number,status,created_by,published_by,published_at)
select q_past_v,q_past,1,'published'::public.content_version_status,teacher,teacher,now()-interval '9 days' from dx union all
select q_reopen_v,q_reopen,1,'published'::public.content_version_status,teacher,teacher,now()-interval '9 days' from dx union all
select q_gone_v,q_gone,1,'published'::public.content_version_status,teacher,teacher,now()-interval '9 days' from dx;
insert into public.quiz_assignments(id,class_id,quiz_version_id,assigned_by,created_at,due_at)
select qa_past,class_id,q_past_v,teacher,now()-interval '9 days',now()-interval '3 days' from dx union all
select qa_reopen,class_id,q_reopen_v,teacher,now()-interval '9 days',now()+interval '2 days' from dx;
insert into public.quiz_assignments(id,class_id,quiz_version_id,assigned_by,created_at,due_at,status,closed_at,close_reason)
select qa_gone,class_id,q_gone_v,teacher,now()-interval '9 days',now()-interval '2 days','closed'::public.assignment_status,now()-interval '6 days','Withdrawn by the instructor' from dx;
insert into public.quiz_attempts(id,learner_id,class_id,quiz_assignment_id,quiz_version_id,status,client_start_key,submission_key,started_at,submitted_at,completed_at)
select gen_random_uuid(),olive,class_id,qa_past,q_past_v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '4 days',now()-interval '4 days',now()-interval '4 days' from dx union all
select gen_random_uuid(),hugo,class_id,qa_past,q_past_v,'completed'::public.quiz_attempt_status,gen_random_uuid(),gen_random_uuid(),now()-interval '4 days',now()-interval '4 days',now()-interval '4 days' from dx;
-- Ian started before the deadline; the server submits it when its time runs out.
insert into public.quiz_attempts(id,learner_id,class_id,quiz_assignment_id,quiz_version_id,status,client_start_key,started_at)
select gen_random_uuid(),ian,class_id,qa_past,q_past_v,'in_progress'::public.quiz_attempt_status,gen_random_uuid(),now()-interval '4 days' from dx;

select set_config('request.jwt.claim.sub',(select teacher::text from dx),true);
set local role authenticated;
insert into dr values
  ('learners', public.get_learner_performance((select jsonb_build_object('class_id', class_id) from dx))),
  ('after_deadlines', public.get_learner_performance((select jsonb_build_object('class_id', class_id,
    'from', to_char((now()-interval '1 day') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')) from dx))),
  ('profile_hugo', public.get_learner_profile_analytics((select hugo from dx), (select jsonb_build_object('class_id', class_id) from dx)));
reset role;

create function pg_temp.learner(p_name text) returns jsonb language sql as $$
  select l from dr, jsonb_array_elements(dr.v->'learners') l where dr.name = 'learners' and l->>'name' = p_name
$$;

select is((select pg_temp.learner('Olive OnTime')->>'status'), 'on_track', 'on-time homework and quiz: on track');
select is((select jsonb_array_length(pg_temp.learner('Olive OnTime')->'reasons')), 0, 'on-time learner has no reasons');

select is((select pg_temp.learner('Hugo MissedHomework')->>'status'), 'falling_behind', 'missed homework deadline: falling behind');
select ok((select pg_temp.learner('Hugo MissedHomework')->'reasons' @>
  '[{"code":"missed_deadlines","kind":"falling_behind","threshold":1,"missed_count":1,"homework_missed":1,"quizzes_missed":0}]'),
  'missed homework reason carries the counts');
select ok((select pg_temp.learner('Hugo MissedHomework')->'reasons' @> '[{"items":[{"kind":"homework","title":"Cable test report"}]}]'),
  'missed homework reason names the homework');
select ok((select not pg_temp.learner('Hugo MissedHomework')->'reasons' @> '[{"items":[{"title":"Extended wiring plan"}]}]'),
  'an extended homework deadline is not missed');
select ok((select not pg_temp.learner('Hugo MissedHomework')->'reasons' @> '[{"code":"inactive"}]'),
  'the missed deadline, not inactivity, explains the status');

select is((select pg_temp.learner('Quinn MissedQuiz')->>'status'), 'falling_behind', 'missed quiz deadline: falling behind');
select ok((select pg_temp.learner('Quinn MissedQuiz')->'reasons' @>
  '[{"code":"missed_deadlines","missed_count":1,"homework_missed":0,"quizzes_missed":1,"items":[{"kind":"quiz","title":"Safety quiz"}]}]'),
  'missed quiz reason names the quiz');
select ok((select not pg_temp.learner('Quinn MissedQuiz')->'reasons' @> '[{"items":[{"title":"Reopened tools quiz"}]}]'),
  'a reopened quiz is not missed');
select ok((select not pg_temp.learner('Quinn MissedQuiz')->'reasons' @> '[{"items":[{"title":"Withdrawn quiz"}]}]'),
  'a quiz closed before its deadline is not missed');

select is((select pg_temp.learner('Lara LateJoiner')->>'status'), 'on_track', 'deadlines before enrolment are not missed');
select is((select pg_temp.learner('Ian InProgress')->>'status'), 'on_track', 'an attempt started before the deadline is not missed');

select is((select (v->'counts'->>'falling_behind')::int from dr where name='learners'), 2, 'two learners are falling behind');
select is((select (v->'counts'->>'on_track')::int from dr where name='learners'), 3, 'three learners are on track');
select is((select (v->'counts'->>'struggling')::int from dr where name='learners'), 0, 'deadlines never mark struggling');
select is((select (v->'thresholds'->>'missed_deadlines_at_least')::int from dr where name='learners'), 1, 'threshold is one missed deadline');
select is((select (pg_temp.learner('Hugo MissedHomework')->'assignments'->>'missing')::int), 1, 'missing homework count matches the reason');

select is((select l->>'status' from dr, jsonb_array_elements(v->'learners') l where name='after_deadlines' and l->>'name'='Hugo MissedHomework'),
  'on_track', 'a period after the deadline does not count it');
select is((select l->>'status' from dr, jsonb_array_elements(v->'learners') l where name='after_deadlines' and l->>'name'='Quinn MissedQuiz'),
  'on_track', 'a period after the quiz deadline does not count it');

select is((select v->'status'->>'status' from dr where name='profile_hugo'), 'falling_behind', 'learner profile uses the same rule');
select ok((select v->'status'->'reasons' @> '[{"code":"missed_deadlines","homework_missed":1}]' from dr where name='profile_hugo'),
  'learner profile lists the missed deadline');

-- Learners never read staff analytics.
select set_config('request.jwt.claim.sub',(select hugo::text from dx),true);
set local role authenticated;
select throws_ok('select public.get_learner_performance(''{}''::jsonb)', '42501', null, 'learners cannot read learner status analytics');
reset role;

select * from finish();
rollback;
