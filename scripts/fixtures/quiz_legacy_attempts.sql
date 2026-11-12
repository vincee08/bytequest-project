create temp table legacy_quiz_context as select gen_random_uuid() quiz_id,gen_random_uuid() version_id,gen_random_uuid() class_a,gen_random_uuid() class_b,gen_random_uuid() assignment_a,gen_random_uuid() assignment_b,
  gen_random_uuid() completed_a,gen_random_uuid() completed_b,gen_random_uuid() unfinished,
  (select id from qa_staff where role='instructor' limit 1) instructor_id,
  (select user_id from public.profiles where role='learner' limit 1) learner_id;
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Legacy QA A','LQA-'||class_a,instructor_id,instructor_id from legacy_quiz_context union all select class_b,'Legacy QA B','LQB-'||class_b,instructor_id,instructor_id from legacy_quiz_context;
insert into public.class_memberships(class_id,learner_id,enrolled_by) select class_a,learner_id,instructor_id from legacy_quiz_context union all select class_b,learner_id,instructor_id from legacy_quiz_context;
insert into public.quizzes(id,instructor_id,title,topic,created_by) select quiz_id,instructor_id,'Legacy quiz','Legacy topic',instructor_id from legacy_quiz_context;
insert into public.quiz_versions(id,quiz_id,version_number,status,published_by,published_at,created_by) select version_id,quiz_id,1,'published',instructor_id,now(),instructor_id from legacy_quiz_context;
insert into public.quiz_assignments(id,class_id,quiz_version_id,assigned_by) select assignment_a,class_a,version_id,instructor_id from legacy_quiz_context union all select assignment_b,class_b,version_id,instructor_id from legacy_quiz_context;
insert into public.quiz_attempts(id,learner_id,class_id,quiz_assignment_id,quiz_version_id,client_start_key,status,submission_key,submitted_at,completed_at,started_at)
select completed_a,learner_id,class_a,assignment_a,version_id,gen_random_uuid(),'completed'::public.quiz_attempt_status,gen_random_uuid(),now()-interval '3 days',now()-interval '3 days',now()-interval '4 days' from legacy_quiz_context union all
select completed_b,learner_id,class_b,assignment_b,version_id,gen_random_uuid(),'completed'::public.quiz_attempt_status,gen_random_uuid(),now()-interval '1 day',now()-interval '1 day',now()-interval '2 days' from legacy_quiz_context union all
select unfinished,learner_id,class_a,assignment_a,version_id,gen_random_uuid(),'in_progress'::public.quiz_attempt_status,null,null,null,now()-interval '6 days' from legacy_quiz_context;
insert into public.quiz_results(quiz_attempt_id,correct_count,question_count,item_results) select completed_a,1,1,'[]'::jsonb from legacy_quiz_context union all select completed_b,0,1,'[]'::jsonb from legacy_quiz_context;
create temp table legacy_hashes as select
(select md5(string_agg(row_to_json(a)::text,'|' order by id)) from public.quiz_attempts a) attempts,
(select md5(string_agg(row_to_json(a)::text,'|' order by id)) from public.quiz_results a) results,
(select md5(string_agg(row_to_json(a)::text,'|' order by id)) from public.quiz_assignments a) assignments;
