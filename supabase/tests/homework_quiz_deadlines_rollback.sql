-- Controlled server clock exists ONLY inside this rollback transaction.
-- No client-controlled clock setting is read by production code.
\set ON_ERROR_STOP on
begin;
create temp table activity_clock(at timestamptz);
insert into activity_clock values('2035-01-01 07:59:00+00');
grant select on activity_clock to service_role;
create or replace function private.activity_server_now() returns timestamptz
language sql volatile security invoker set search_path='' as $$ select at from pg_temp.activity_clock $$;
create temp table activity_test as select
  gen_random_uuid() teacher,gen_random_uuid() foreign_teacher,
  gen_random_uuid() learner_a,gen_random_uuid() learner_b,gen_random_uuid() learner_c,
  gen_random_uuid() outsider,gen_random_uuid() class_a,gen_random_uuid() class_b,
  null::uuid quiz,null::uuid version,null::uuid item,null::uuid assignment_a,null::uuid assignment_b,
  null::uuid attempt_a,null::uuid attempt_b,null::uuid homework,null::uuid no_deadline,
  null::uuid submission_a,null::uuid submission_b;
grant all on activity_test to authenticated,service_role;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@activity-rollback.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Activity rollback fixture"}'::jsonb,now(),now()
from activity_test cross join lateral(values(teacher),(foreign_teacher),(learner_a),(learner_b),(learner_c),(outsider)) t(id);
update public.profiles set role='instructor' where user_id in(select teacher from activity_test union select foreign_teacher from activity_test);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Activity rollback A',left(class_a::text,12),teacher,teacher from activity_test union all
select class_b,'Activity rollback B',left(class_b::text,12),teacher,teacher from activity_test;
-- Legacy multi-class fixture: one learner in two active classes, as data created
-- before the one-active-class rule (20261123090000). Built with that rule's
-- trigger disabled inside this rolled-back transaction only.
alter table public.class_memberships disable trigger trg_class_memberships_one_active_class;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select cls,id,teacher from activity_test cross join lateral(values(class_a),(class_b)) c(cls) cross join lateral(values(learner_a),(learner_b),(learner_c)) l(id);
alter table public.class_memberships enable trigger trg_class_memberships_one_active_class;
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
create function pg_temp.denied(command text,expected text) returns void language plpgsql as $$ begin
  begin execute command; exception when others then if sqlerrm like '%'||expected||'%' then return; end if; raise; end;
  raise exception 'EXPECTED_DENIAL: %',expected;
end $$;

-- Instructor publication still requires review and persists separate quiz assignments.
select set_config('request.jwt.claim.sub',(select teacher::text from activity_test),true);
set local role authenticated;
update activity_test set quiz=(public.create_instructor_quiz('Deadline rollback quiz','Networking',p_coc_module_id=>(select id from public.coc_modules where coc_code='coc2'),p_focus=>'Identify network devices and their roles')).id;
update activity_test set version=(select id from public.quiz_versions where quiz_id=activity_test.quiz);
update activity_test set item=(public.upsert_quiz_item(version,'true_false','A router connects networks.','[]','"True"')).id;
select public.review_quiz_item(item,'approved') from activity_test;
select public.publish_and_assign_quiz(version,array[class_a,class_b],p_due_at=>'2035-01-01 08:00:00+00') from activity_test;
update activity_test set assignment_a=(select id from public.quiz_assignments where class_id=class_a and quiz_version_id=version),assignment_b=(select id from public.quiz_assignments where class_id=class_b and quiz_version_id=version);
select pg_temp.assert((select count(*)=0 from public.homework_assignments),'quiz publishing must not create homework');

select set_config('request.jwt.claim.sub',(select learner_a::text from activity_test),true);
update activity_test set attempt_a=(public.start_learner_quiz(assignment_a,gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(attempt_a,item,'True') from activity_test;
select public.submit_learner_quiz(attempt_a,gen_random_uuid()) from activity_test;
select pg_temp.assert((select started_at='2035-01-01 07:59:00+00' and submitted_at='2035-01-01 07:59:00+00' from public.quiz_attempts where id=attempt_a),'quiz admission timestamps must use the checked server time after locks') from activity_test;
select pg_temp.assert((select answered_at='2035-01-01 07:59:00+00' from public.quiz_answers where quiz_attempt_id=attempt_a),'saved answer timestamp must use its server admission time') from activity_test;
select set_config('request.jwt.claim.sub',(select learner_b::text from activity_test),true);
update activity_test set attempt_b=(public.start_learner_quiz(assignment_a,gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(attempt_b,item,'True') from activity_test;
select pg_temp.denied('select private.activity_server_now()','permission denied');
select pg_temp.denied(format('select public.manage_homework(%L,''create'',''{}'')',teacher),'permission denied') from activity_test;
reset role;
update activity_clock set at='2035-01-01 08:00:00+00';
select set_config('request.jwt.claim.sub',(select learner_c::text from activity_test),true);
set local role authenticated;
select pg_temp.denied(format('select public.start_learner_quiz(%L,gen_random_uuid())',assignment_a),'QUIZ_NOT_AVAILABLE') from activity_test;
select set_config('request.jwt.claim.sub',(select learner_b::text from activity_test),true);
select pg_temp.denied(format('select public.save_learner_quiz_answer(%L,%L,''False'')',attempt_b,item),'QUIZ_NOT_AVAILABLE') from activity_test;
-- Re-defense A3 (approved design WS4): expired unfinished attempts are now
-- submitted automatically at the deadline with their saved answers.
select pg_temp.assert(public.submit_learner_quiz(attempt_b,gen_random_uuid())->>'submission_kind'='auto_deadline','a submit after the deadline returns the automatic submission of the saved answers') from activity_test;
select pg_temp.assert((select answer #>> '{}'='True' from public.quiz_answers where quiz_attempt_id=attempt_b),'deadline must preserve saved answers') from activity_test;
select pg_temp.assert((select status='completed' and submission_kind='auto_deadline' and submitted_at='2035-01-01 08:00:00+00' from public.quiz_attempts where id=attempt_b),'an expired unfinished attempt is auto-submitted at the deadline, not at the request time') from activity_test;
select pg_temp.assert((select count(*)=1 and min(correct_count)=1 from public.quiz_results where quiz_attempt_id=attempt_b),'the saved answer is graded exactly once; nothing is invented') from activity_test;
select pg_temp.assert((select payload->>'closed_reason'='deadline_passed' and payload->>'is_available'='false' from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'quiz_id'=quiz::text),'closed quiz must stay discoverable') from activity_test;
select set_config('request.jwt.claim.sub',(select learner_a::text from activity_test),true);
select pg_temp.assert(public.get_learner_quiz_result(attempt_a)->>'correct_count'='1','completed result remains available after deadline') from activity_test;
reset role;

set local role service_role;
select pg_temp.denied(format('select public.set_quiz_assignment_deadline(%L,%L,%L,true)',foreign_teacher,assignment_a,'2035-01-02 08:00:00+00'),'INSTRUCTOR_CLASS_SCOPE_REQUIRED') from activity_test;
select pg_temp.denied(format('select public.set_quiz_assignment_deadline(%L,%L,%L,true)',teacher,assignment_a,'2035-01-01 08:00:00+00'),'FUTURE_DEADLINE_REQUIRED') from activity_test;
select public.set_quiz_assignment_deadline(teacher,assignment_a,'2035-01-02 08:00:00+00',true) from activity_test;
select pg_temp.assert((select due_at='2035-01-01 08:00:00+00' from public.quiz_assignments where id=assignment_b),'reopening one class must not change another') from activity_test;
reset role;
select set_config('request.jwt.claim.sub',(select learner_b::text from activity_test),true);
set local role authenticated;
-- Re-defense A3: reopening after the deadline does not revive an attempt that
-- was auto-submitted under the old deadline (it stays the learner's one attempt).
select pg_temp.denied(format('select public.start_learner_quiz(%L,gen_random_uuid())',assignment_a),'QUIZ_ATTEMPT_ALREADY_SUBMITTED') from activity_test;
select set_config('request.jwt.claim.sub',(select learner_a::text from activity_test),true);
select pg_temp.denied(format('select public.start_learner_quiz(%L,gen_random_uuid())',assignment_a),'QUIZ_ATTEMPT_ALREADY_SUBMITTED') from activity_test;
select set_config('request.jwt.claim.sub',(select learner_c::text from activity_test),true);
select pg_temp.assert(public.start_learner_quiz(assignment_a,gen_random_uuid())->>'attempt_id' is not null,'reopen permits first attempt for never-started learner') from activity_test;
select set_config('request.jwt.claim.sub',(select outsider::text from activity_test),true);
select pg_temp.denied(format('select public.start_learner_quiz(%L,gen_random_uuid())',assignment_a),'QUIZ_NOT_AVAILABLE') from activity_test;
reset role;
select pg_temp.assert((select count(*)=1 from public.audit_events where action='quiz.reopened' and target_id=assignment_a and actor_id=teacher and old_value->>'deadline' is not null and new_value->>'deadline' is not null),'reopen audit must preserve actor, quiz, class, old/new deadline and time') from activity_test;

-- Server-only homework writes and client RLS reads share the same identities.
set local role service_role;
update activity_test set homework=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_a,'title','Boundary homework','instructions','Write a network report.','deadline_at','2035-01-01 08:00:00+00'))->>'id')::uuid;
reset role;
select set_config('request.jwt.claim.sub',(select learner_a::text from activity_test),true);
set local role authenticated;
select pg_temp.assert((select count(*)=0 from public.homework_assignments where id=homework),'draft homework must stay private') from activity_test;
select pg_temp.denied(format('update public.homework_assignments set status=''published'' where id=%L',homework),'permission denied') from activity_test;
reset role;
set local role service_role;
select public.manage_homework(teacher,'publish',jsonb_build_object('assignment_id',homework)) from activity_test;
update activity_test set submission_a=(public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',homework,'answer','At the exact deadline.','file_ids','[]'::jsonb))->>'id')::uuid;
select pg_temp.assert((select lateness_seconds=0 and submitted_at=effective_deadline_at from public.homework_submissions where id=submission_a),'homework at exact deadline must be on time') from activity_test;
reset role;
update activity_clock set at='2035-01-03 14:15:00+00';
set local role service_role;
update activity_test set submission_b=(public.manage_homework(learner_b,'submit',jsonb_build_object('assignment_id',homework,'answer','Late report.','file_ids','[]'::jsonb))->>'id')::uuid;
select pg_temp.assert((select lateness_seconds=195300 from public.homework_submissions where id=submission_b),'late duration must equal exactly 2 days 6 hours 15 minutes') from activity_test;
select public.manage_homework(teacher,'deadline',jsonb_build_object('assignment_id',homework,'deadline_at','2035-01-10 08:00:00+00')) from activity_test;
select pg_temp.assert((select lateness_seconds=195300 and effective_deadline_at='2035-01-01 08:00:00+00' from public.homework_submissions where id=submission_b),'later deadline edit must not rewrite historical lateness') from activity_test;
select pg_temp.assert(public.manage_homework(learner_b,'submit',jsonb_build_object('assignment_id',homework,'answer','Duplicate changed answer','file_ids','[]'::jsonb))->>'id'=submission_b::text,'retry must return existing immutable submission') from activity_test;
select pg_temp.assert((select answer='Late report.' from public.homework_submissions where id=submission_b),'retry must not change original answer') from activity_test;
select public.manage_homework(teacher,'grade',jsonb_build_object('assignment_id',homework,'submission_id',submission_b,'feedback','Reviewed; no numeric score required.')) from activity_test;
select public.manage_homework(teacher,'grade',jsonb_build_object('assignment_id',homework,'submission_id',submission_b,'feedback','Duplicate grade.')) from activity_test;
select pg_temp.assert((select status='graded' and score is null and graded_by=teacher and graded_at='2035-01-03 14:15:00+00' from public.homework_submissions where id=submission_b),'late homework must be gradeable without a score') from activity_test;
update activity_test set no_deadline=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_a,'title','No deadline homework','instructions','Submit a report.'))->>'id')::uuid;
select public.manage_homework(teacher,'publish',jsonb_build_object('assignment_id',no_deadline)) from activity_test;
select public.manage_homework(learner_c,'submit',jsonb_build_object('assignment_id',no_deadline,'answer','No deadline report.','file_ids','[]'::jsonb)) from activity_test;
select pg_temp.assert((select lateness_seconds=0 and effective_deadline_at is null from public.homework_submissions where assignment_id=no_deadline),'homework without deadline is never late') from activity_test;
select pg_temp.denied(format('select public.manage_homework(%L,''submit'',jsonb_build_object(''assignment_id'',%L,''answer'',''Forbidden''))',outsider,homework),'HOMEWORK_SCOPE_DENIED') from activity_test;
-- Objective 4: a grade becomes visible only after Finalize -> Release.
select public.manage_homework(teacher,'finalize',jsonb_build_object('submission_ids',jsonb_build_array(submission_b))) from activity_test;
select public.manage_homework(teacher,'release',jsonb_build_object('submission_ids',jsonb_build_array(submission_b))) from activity_test;
reset role;
select set_config('request.jwt.claim.sub',(select learner_b::text from activity_test),true);
set local role authenticated;
select pg_temp.assert((select status='released' from public.homework_submissions where id=submission_b),'learner must see the released grade after instructor review') from activity_test;
select pg_temp.assert((select count(*)=0 from public.homework_submissions where id=submission_a),'learner must not read another submission') from activity_test;
select pg_temp.denied(format('update public.homework_submissions set status=''graded'' where id=%L',submission_b),'permission denied') from activity_test;
reset role;
select pg_temp.assert((select count(*)=1 from public.audit_events where action='homework.graded' and target_id=submission_b),'duplicate grading must not create duplicate audit decision') from activity_test;
select pg_temp.assert(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),'RLS must remain enabled on every public base table');
rollback;
