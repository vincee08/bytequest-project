-- Panel revision (2026-11-23): quiz workflow fixes (20261123130100).
-- A quiz question cannot ask for an image or file (answers are typed text),
-- direct assignment refuses past deadlines, and the normal typed-answer
-- attempt still works end to end. Rollback-only.
begin;
select plan(24);

create temporary table qw as select
  gen_random_uuid() teacher, gen_random_uuid() learner, gen_random_uuid() class_a,
  (select id from public.coc_modules where coc_code = 'coc1') coc1,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1') lo11,
  null::uuid quiz, null::uuid version, null::uuid bad_item, null::uuid essay, null::uuid mcq,
  null::uuid legacy_quiz, null::uuid legacy_version, null::uuid legacy_item,
  null::uuid assignment, null::uuid attempt;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-workflow.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Quiz workflow fixture"}'::jsonb,now(),now()
from qw cross join lateral (values (teacher),(learner)) ids(id);
update public.profiles set role = 'instructor' where user_id = (select teacher from qw);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_a,'Quiz workflow A','QWA-'||left(class_a::text,8),teacher,teacher from qw;
insert into public.class_memberships(class_id,learner_id,enrolled_by) select class_a,learner,teacher from qw;
grant all on qw to authenticated, service_role;

-- 1. Detection: the same phrases the dashboard test uses.
select ok(private.quiz_text_requests_upload(t), 'flags: ' || t) from (values
  ('Explain your answer and attach one image of your crimped cable.'),
  ('Required: written answer and one image file.'),
  ('Upload a screenshot of your IP configuration.'),
  ('Take a clear photo of the wiring and submit it.'),
  ('Please upload your file.'),
  ('One image file is required for this item.')) v(t);
select ok(not private.quiz_text_requests_upload(t), 'allows: ' || t) from (values
  ('Why should a technician take a photo of the cable layout before disassembly?'),
  ('Which protocol is used to upload a file to a server?'),
  ('Which of these is an image file format?'),
  ('Attach the CPU fan cable to the CPU_FAN header.'),
  ('A user cannot open an attached image file in Outlook. Diagnose the cause.'),
  ('Provide the IP address and subnet mask you would assign.')) v(t);

select set_config('request.jwt.claim.sub', (select teacher::text from qw), true);
set local role authenticated;

update qw set quiz = (public.create_instructor_quiz('Cable termination check', 'RJ45', p_coc_module_id => coc1,
  p_focus => 'Assess cable termination', p_module_ids => array[lo11], p_time_limit_minutes => 30)).id;
update qw set version = (select id from public.quiz_versions where quiz_id = qw.quiz);

-- 2. An essay asking for an image is saved as a draft but cannot be approved.
update qw set bad_item = (public.upsert_quiz_item(version, 'scenario_essay',
  'Explain the T568B order you used and attach one image of your crimped cable.',
  '[]', '""', null,
  p_rubric => '[{"criterion":"Order","description":"Lists T568B colours","max_points":5}]',
  p_scenario => 'A client needs a new patch cable for a workstation in the lab.')).id;
select throws_ok(format('select public.review_quiz_item(%L, ''approved'')', bad_item), '22023', 'QUIZ_UPLOAD_RESPONSE_UNSUPPORTED',
  'an essay that asks for an image cannot be approved') from qw;
select lives_ok(format('select public.remove_quiz_item(%L, %L)', bad_item, 'Quizzes cannot collect images'), 'the instructor can remove the refused item') from qw;

-- 3. Typed questions approve, publish and assign as before.
update qw set essay = (public.upsert_quiz_item(version, 'scenario_essay',
  'Explain, step by step, how you would terminate the cable and verify it with a tester.',
  '[]', '""', null,
  p_rubric => '[{"criterion":"Procedure","description":"Strip, order, trim, insert, crimp","max_points":4},{"criterion":"Testing","description":"Uses a tester and reads the wire map","max_points":2}]',
  p_scenario => 'A client needs a new patch cable for a workstation in the lab.')).id;
update qw set mcq = (public.upsert_quiz_item(version, 'multiple_choice', 'Which tool attaches the RJ45 plug to the cable?',
  '["Crimping tool","Punch-down tool"]', '"Crimping tool"')).id;
select lives_ok(format('select public.review_quiz_item(%L, ''approved'')', essay), 'a typed essay is approved') from qw;
select lives_ok(format('select public.review_quiz_item(%L, ''approved'')', mcq), 'a multiple-choice item is approved') from qw;
select lives_ok(format('select public.publish_quiz_version(%L)', version), 'the typed-answer version publishes') from qw;

-- 4. Direct assignment refuses a deadline that has already passed.
select throws_ok(format('select public.assign_published_quiz(%L,%L,p_due_at=>now() - interval ''1 hour'')', class_a, version),
  '22023', 'FUTURE_DEADLINE_REQUIRED', 'a past deadline is refused on direct assignment') from qw;
update qw set assignment = (public.assign_published_quiz(class_a, version, p_due_at => now() + interval '2 days',
  p_instructions => 'Type every answer; no files are needed.')).id;
select ok((select assignment is not null from qw), 'a future deadline is accepted');

-- 5. A version approved before this guard existed cannot be published.
update qw set legacy_quiz = (public.create_instructor_quiz('Legacy draft quiz', 'Photos', p_coc_module_id => coc1,
  p_focus => 'Legacy wording check', p_module_ids => array[lo11])).id;
update qw set legacy_version = (select id from public.quiz_versions where quiz_id = qw.legacy_quiz);
update qw set legacy_item = (public.upsert_quiz_item(legacy_version, 'identification',
  'Name the standard you used. Upload a screenshot of your tester result.', '[]', '"T568B"')).id;
reset role;
alter table public.quiz_items disable trigger trg_quiz_items_reject_upload_request;
update public.quiz_items set review_status = 'approved', reviewed_by = (select teacher from qw), reviewed_at = now()
where id = (select legacy_item from qw);
alter table public.quiz_items enable trigger trg_quiz_items_reject_upload_request;
select set_config('request.jwt.claim.sub', (select teacher::text from qw), true);
set local role authenticated;
select throws_ok(format('select public.publish_quiz_version(%L)', legacy_version), '22023', 'QUIZ_UPLOAD_RESPONSE_UNSUPPORTED',
  'publishing re-checks items approved before the guard') from qw;
reset role;
select is((select status::text from public.quiz_versions where id = (select legacy_version from qw)), 'draft',
  'the refused legacy version stays a draft');

-- 6. The learner's typed attempt still works end to end.
select set_config('request.jwt.claim.sub', (select learner::text from qw), true);
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);
set local role authenticated;
update qw set attempt = (public.start_learner_quiz(assignment, gen_random_uuid())->>'attempt_id')::uuid;
select is((public.start_learner_quiz(assignment, gen_random_uuid())->'quiz'->>'instructions'),
  'Type every answer; no files are needed.', 'the learner receives the class instructions') from qw;
select throws_ok(format('select public.submit_learner_quiz(%L, gen_random_uuid())', attempt), '22023',
  'ANSWER_EVERY_QUESTION_BEFORE_SUBMISSION', 'an incomplete attempt cannot be submitted') from qw;
select public.save_learner_quiz_answer(attempt, mcq, 'Crimping tool') from qw;
select public.save_learner_quiz_answer(attempt, essay,
  'Strip the jacket, order the wires to T568B, trim, insert, crimp, then test the wire map.') from qw;
select is((public.submit_learner_quiz(attempt, gen_random_uuid())->>'evaluation_status'), 'pending',
  'a complete typed attempt submits and waits for essay scoring') from qw;
reset role;

select * from finish();
rollback;
