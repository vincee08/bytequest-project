-- Run only in isolated QA after quiz_publishing_and_single_attempt.
\set ON_ERROR_STOP on
\echo 1..1
begin;
create temporary table quiz_revision_context as select
  gen_random_uuid() instructor_id,gen_random_uuid() other_instructor,
  gen_random_uuid() learner_id,gen_random_uuid() outsider_id,
  gen_random_uuid() class_a,gen_random_uuid() class_b,gen_random_uuid() foreign_class,
  null::uuid quiz_id,null::uuid version_id,null::uuid item_id,
  null::uuid assignment_a,null::uuid assignment_b,null::uuid attempt_id;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-revision.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Quiz revision fixture"}'::jsonb,now(),now()
from quiz_revision_context cross join lateral (values(instructor_id),(other_instructor),(learner_id),(outsider_id)) ids(id);
update public.profiles set role='instructor',status='active' where user_id in (select instructor_id from quiz_revision_context union select other_instructor from quiz_revision_context);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Quiz QA A','QUIZ-A-'||left(class_a::text,8),instructor_id,instructor_id from quiz_revision_context union all
select class_b,'Quiz QA B','QUIZ-B-'||left(class_b::text,8),instructor_id,instructor_id from quiz_revision_context union all
select foreign_class,'Other instructor class','QUIZ-X-'||left(foreign_class::text,8),other_instructor,other_instructor from quiz_revision_context;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_a,learner_id,instructor_id from quiz_revision_context union all select class_b,learner_id,instructor_id from quiz_revision_context;
grant all on quiz_revision_context to authenticated;
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'ASSERT: %',message; end if; end $$;
create function pg_temp.denied(command text,expected text) returns void language plpgsql as $$
begin
  begin execute command; exception when others then
    if sqlerrm like '%'||expected||'%' then return; end if; raise;
  end;
  raise exception 'EXPECTED_DENIAL: %',expected;
end $$;
select set_config('request.jwt.claim.sub',(select instructor_id::text from quiz_revision_context),true);
set local role authenticated;
update quiz_revision_context set quiz_id=(public.create_instructor_quiz('Quiz revision QA','Network testing')).id;
update quiz_revision_context set version_id=(select id from public.quiz_versions where quiz_id=quiz_revision_context.quiz_id);
select pg_temp.denied(format('select public.publish_quiz_version(%L)',version_id),'APPROVED_QUIZ_ITEM_REQUIRED') from quiz_revision_context;
update quiz_revision_context set item_id=(public.upsert_quiz_item(version_id,'identification','Name the routing device.','[]','"Router"')).id;
select pg_temp.denied(format('select public.publish_quiz_version(%L)',version_id),'APPROVED_QUIZ_ITEM_REQUIRED') from quiz_revision_context;
select public.review_quiz_item(item_id,'approved') from quiz_revision_context;
-- A failure in any target rolls back publication and all assignments.
select pg_temp.denied(format('select public.publish_and_assign_quiz(%L,ARRAY[%L,%L]::uuid[])',version_id,class_a,foreign_class),'INSTRUCTOR_CLASS_SCOPE_REQUIRED') from quiz_revision_context;
select pg_temp.assert((select status='draft' from public.quiz_versions where id=version_id),'failed target must roll back publication') from quiz_revision_context;
select pg_temp.assert((select count(*)=0 from public.quiz_assignments where quiz_version_id=version_id),'failed target must roll back assignments') from quiz_revision_context;
select public.publish_and_assign_quiz(version_id,array[class_a,class_b]) from quiz_revision_context;
select public.publish_and_assign_quiz(version_id,array[class_a,class_b,class_b]) from quiz_revision_context;
select pg_temp.assert((select count(*)=2 from public.quiz_assignments where quiz_version_id=version_id),'publication retry must not duplicate assignments') from quiz_revision_context;
select pg_temp.assert((select bool_and(attempts_allowed=1) from public.quiz_assignments where quiz_version_id=version_id),'assignment limit must be one') from quiz_revision_context;
update quiz_revision_context set assignment_a=(select id from public.quiz_assignments where class_id=class_a and quiz_version_id=version_id),assignment_b=(select id from public.quiz_assignments where class_id=class_b and quiz_version_id=version_id);
select pg_temp.denied(format('select public.assign_published_quiz(%L,%L,p_attempts_allowed=>2)',class_a,version_id),'INVALID_ATTEMPT_LIMIT') from quiz_revision_context;
-- Learners cannot author, read answer keys, or enter an unenrolled class.
select set_config('request.jwt.claim.sub',(select outsider_id::text from quiz_revision_context),true);
select pg_temp.denied(format('select public.start_learner_quiz(%L,gen_random_uuid())',assignment_a),'QUIZ_NOT_AVAILABLE') from quiz_revision_context;
select pg_temp.denied(format('select public.publish_quiz_version(%L)',version_id),'INSTRUCTOR_REQUIRED') from quiz_revision_context;
select set_config('request.jwt.claim.sub',(select learner_id::text from quiz_revision_context),true);
select pg_temp.assert((select count(*)=0 from public.quiz_items),'learner must not read quiz answer keys');
update quiz_revision_context set attempt_id=(public.start_learner_quiz(assignment_a,gen_random_uuid())->>'attempt_id')::uuid;
select pg_temp.assert((public.start_learner_quiz(assignment_b,gen_random_uuid())->>'attempt_id')::uuid=attempt_id,'another class/device must resume same attempt') from quiz_revision_context;
select public.save_learner_quiz_answer(attempt_id,item_id,' router ') from quiz_revision_context;
select pg_temp.assert(public.start_learner_quiz(assignment_a,gen_random_uuid())->'questions'->0->>'saved_answer'='router','resume must retain saved answer') from quiz_revision_context;
-- Publish another version while an unfinished old-version attempt exists.
select set_config('request.jwt.claim.sub',(select instructor_id::text from quiz_revision_context),true);
do $$ declare v public.quiz_versions; i public.quiz_items; begin
  v:=public.create_quiz_version((select quiz_id from quiz_revision_context));
  i:=public.upsert_quiz_item(v.id,'true_false','A switch connects LAN devices.','[]','"true"');
  perform public.review_quiz_item(i.id,'approved');
  perform public.publish_and_assign_quiz(v.id,array[(select class_a from quiz_revision_context)]);
end $$;
select set_config('request.jwt.claim.sub',(select learner_id::text from quiz_revision_context),true);
select pg_temp.assert((public.start_learner_quiz(assignment_a,gen_random_uuid())->>'attempt_id')::uuid=attempt_id,'retired version must remain resumable for original enrolled learner') from quiz_revision_context;
select pg_temp.assert((select count(*)=1 from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'attempt_id'=attempt_id::text),'republished list must expose canonical attempt') from quiz_revision_context;
select pg_temp.assert((public.submit_learner_quiz(attempt_id,gen_random_uuid())->>'correct_count')::int=1,'identification grading must remain case-insensitive') from quiz_revision_context;
select public.submit_learner_quiz(attempt_id,gen_random_uuid()) from quiz_revision_context;
select pg_temp.assert((select count(*)=1 from public.quiz_results where quiz_attempt_id=attempt_id),'duplicate submission must not duplicate grade') from quiz_revision_context;
select pg_temp.denied(format('select public.start_learner_quiz(%L,gen_random_uuid())',(select id from public.quiz_assignments where quiz_version_id<>(select version_id from quiz_revision_context) limit 1)),'QUIZ_ATTEMPT_ALREADY_SUBMITTED');
select pg_temp.denied(format('select public.save_learner_quiz_answer(%L,%L,''Switch'')',attempt_id,item_id),'QUIZ_ATTEMPT_ALREADY_SUBMITTED') from quiz_revision_context;
select set_config('request.jwt.claim.sub',(select outsider_id::text from quiz_revision_context),true);
select pg_temp.denied(format('select public.get_learner_quiz_result(%L)',attempt_id),'QUIZ_RESULT_NOT_AVAILABLE') from quiz_revision_context;
reset role;
-- The table-level guard rejects bypass attempts even with new assignment/start keys.
select pg_temp.denied(format('insert into public.quiz_attempts(learner_id,class_id,quiz_assignment_id,quiz_version_id,client_start_key) values(%L,%L,%L,%L,gen_random_uuid())',learner_id,class_a,assignment_a,version_id),'quiz_attempt_claims_pkey') from quiz_revision_context;
select pg_temp.assert((select count(*)=1 from public.audit_events where action='quiz_version.published' and target_id=version_id),'publication audit must be exactly once') from quiz_revision_context;
select pg_temp.assert((select reason is null from public.audit_events where action='quiz_version.published' and target_id=version_id),'no fabricated publication reason') from quiz_revision_context;
rollback;
\echo ok 1 - atomic reason-free publication, RBAC, quiz-wide single attempt, saved-answer resume, retired-version resume, grading and audit
