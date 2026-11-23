-- Structured homework submission rules: a written answer and/or a minimum
-- number of files, optionally images only. The server refuses a submission
-- that misses a required part and an answer file the assignment does not
-- accept. Existing assignments keep "answer or file". Rollback-only.
begin;
select plan(38);

create temporary table req as select
  gen_random_uuid() teacher, gen_random_uuid() learner_a, gen_random_uuid() learner_b,
  gen_random_uuid() learner_c, gen_random_uuid() learner_d, gen_random_uuid() class_id,
  null::uuid both_hw, null::uuid file_hw, null::uuid answer_hw, null::uuid legacy_hw, null::uuid any_file_hw;
grant select, update on req to service_role;
grant select on req to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@homework-requirements.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',name),now(),now()
from req cross join lateral (values (teacher,'REQ Teacher'),(learner_a,'REQ Learner A'),(learner_b,'REQ Learner B'),
  (learner_c,'REQ Learner C'),(learner_d,'REQ Learner D')) t(id,name);
update public.profiles set role='instructor' where user_id=(select teacher from req);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_id,'REQ class','REQ-'||left(class_id::text,8),teacher,teacher from req;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_id,l,teacher from req cross join lateral (values (learner_a),(learner_b),(learner_c),(learner_d)) t(l);

create function pg_temp.attach(p_learner uuid, p_hw uuid, p_mime text, p_name text) returns jsonb language sql as $$
  select public.manage_homework(p_learner,'attach',jsonb_build_object('assignment_id',p_hw,'file_id',gen_random_uuid(),
    'kind','answer','filename',p_name,'object_path','homework/'||gen_random_uuid()||'/'||p_name,'mime_type',p_mime,'size_bytes',1024))
$$;
grant execute on function pg_temp.attach(uuid,uuid,text,text) to service_role;

-- Schema contract.
select is((select string_agg(column_name||'='||column_default,',' order by column_name) from information_schema.columns
  where table_schema='public' and table_name='homework_assignments'
    and column_name in ('submission_format','required_file_count','accepted_file_types')),
  'accepted_file_types=''any''::text,required_file_count=0,submission_format=''answer_or_file''::text',
  'assignments carry submission rules that default to the previous behaviour');
select ok(not (select prosecdef from pg_proc where oid='public.manage_homework(uuid,text,jsonb)'::regprocedure)
  and has_function_privilege('service_role','public.manage_homework(uuid,text,jsonb)','execute')
  and not has_function_privilege('authenticated','public.manage_homework(uuid,text,jsonb)','execute'),
  'manage_homework stays a service-only SECURITY INVOKER function');
select throws_ok($$insert into public.homework_assignments(class_id,instructor_id,title,instructions,submission_format,required_file_count)
  select class_id,teacher,'Bad rows','x','file',0 from req$$,'23514',null,'a file-only assignment needs at least one file (constraint)');
select throws_ok($$insert into public.homework_assignments(class_id,instructor_id,title,instructions,submission_format,accepted_file_types)
  select class_id,teacher,'Bad rows','x','answer','image' from req$$,'23514',null,'a written-answer-only assignment has no file type (constraint)');

-- Authoring.
set local role service_role;
update req set both_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Cable photo report',
  'instructions','Describe the termination and attach one photo.','deadline_at',null,
  'submission_format','answer_and_file','required_file_count',1,'accepted_file_types','image'))->>'id')::uuid;
update req set file_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Upload the report file',
  'instructions','Send your report as a file.','deadline_at',null,'submission_format','file'))->>'id')::uuid;
update req set answer_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Short reflection',
  'instructions','Write a reflection.','deadline_at',null,'submission_format','answer','accepted_file_types','image'))->>'id')::uuid;
update req set legacy_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Older client homework',
  'instructions','Answer or attach.','deadline_at',null))->>'id')::uuid;
update req set any_file_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Two documents',
  'instructions','Attach two files.','deadline_at',null,'submission_format','file','required_file_count',2))->>'id')::uuid;
reset role;

select ok((select submission_format='answer_and_file' and required_file_count=1 and accepted_file_types='image'
  from public.homework_assignments where id=(select both_hw from req)), 'answer-and-image rules are stored');
select ok((select submission_format='file' and required_file_count=1 and accepted_file_types='any'
  from public.homework_assignments where id=(select file_hw from req)), 'a file-only assignment without a count requires one file');
select ok((select submission_format='answer' and required_file_count=0 and accepted_file_types='any'
  from public.homework_assignments where id=(select answer_hw from req)), 'a written-answer-only assignment takes no file type');
select ok((select submission_format='answer_or_file' and required_file_count=0 and accepted_file_types='any'
  from public.homework_assignments where id=(select legacy_hw from req)), 'an older client payload keeps answer-or-file');

set local role service_role;
select throws_ok(format($$select public.manage_homework(%L,'create',jsonb_build_object('class_id',%L,'title','Bad rules','instructions','x',
  'submission_format','file','required_file_count',0))$$,teacher,class_id),'22023','HOMEWORK_SUBMISSION_RULES_INVALID',
  'file-only with zero files is refused') from req;
select throws_ok(format($$select public.manage_homework(%L,'create',jsonb_build_object('class_id',%L,'title','Bad rules','instructions','x',
  'submission_format','answer','required_file_count',2))$$,teacher,class_id),'22023','HOMEWORK_SUBMISSION_RULES_INVALID',
  'a written-answer-only assignment cannot require files') from req;
select throws_ok(format($$select public.manage_homework(%L,'create',jsonb_build_object('class_id',%L,'title','Bad rules','instructions','x',
  'submission_format','video'))$$,teacher,class_id),'22023','HOMEWORK_SUBMISSION_RULES_INVALID','an unknown format is refused') from req;
select throws_ok(format($$select public.manage_homework(%L,'create',jsonb_build_object('class_id',%L,'title','Bad rules','instructions','x',
  'submission_format','file','required_file_count',6))$$,teacher,class_id),'22023','HOMEWORK_SUBMISSION_RULES_INVALID',
  'more than five required files is refused') from req;
select throws_ok(format($$select public.manage_homework(%L,'create',jsonb_build_object('class_id',%L,'title','Bad rules','instructions','x',
  'submission_format','file','required_file_count',1.5))$$,teacher,class_id),'22023','HOMEWORK_SUBMISSION_RULES_INVALID',
  'a fractional file count is refused') from req;
select throws_ok(format($$select public.manage_homework(%L,'create',jsonb_build_object('class_id',%L,'title','Bad rules','instructions','x',
  'submission_format','file','accepted_file_types','video'))$$,teacher,class_id),'22023','HOMEWORK_SUBMISSION_RULES_INVALID',
  'an unknown file type is refused') from req;
-- An edit that omits the rules keeps them.
select public.manage_homework(teacher,'edit',jsonb_build_object('assignment_id',both_hw,'title','Cable photo report (edited)',
  'instructions','Describe the termination and attach one photo.','deadline_at',null)) from req;
-- A format change without a count picks the smallest consistent count.
select public.manage_homework(teacher,'edit',jsonb_build_object('assignment_id',legacy_hw,'title','Older client homework',
  'instructions','Answer or attach.','deadline_at',null,'submission_format','answer_and_file')) from req;
select public.manage_homework(teacher,'edit',jsonb_build_object('assignment_id',legacy_hw,'title','Older client homework',
  'instructions','Answer or attach.','deadline_at',null,'submission_format','answer_or_file')) from req;
select public.manage_homework((select teacher from req),'publish',jsonb_build_object('assignment_id',id)) from public.homework_assignments
  where id in (select both_hw from req union all select file_hw from req union all select answer_hw from req
    union all select legacy_hw from req union all select any_file_hw from req);
reset role;
select ok((select title='Cable photo report (edited)' and submission_format='answer_and_file' and required_file_count=1 and accepted_file_types='image'
  from public.homework_assignments where id=(select both_hw from req)), 'an edit that omits the rules keeps them');
select ok((select submission_format='answer_or_file' and required_file_count=0 from public.homework_assignments where id=(select legacy_hw from req)),
  'switching back to answer-or-file clears the file count');
select ok(exists(select 1 from public.audit_events where target_id=(select legacy_hw from req) and action='homework.edit'
  and old_value->>'submission_format'='answer_or_file' and new_value->>'submission_format'='answer_and_file'),
  'the audit trail records the rule change');

-- Written answer and one image.
set local role service_role;
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','Termination done','file_ids','[]'::jsonb))$$,
  learner_a,both_hw),'22023','HOMEWORK_FILES_REQUIRED','an answer without the required image is refused') from req;
select throws_ok(format($$select pg_temp.attach(%L,%L,'application/pdf','report.pdf')$$,learner_a,both_hw),'22023','HOMEWORK_IMAGE_FILES_REQUIRED',
  'a PDF cannot be attached where images are required') from req;
create temporary table att as select (pg_temp.attach(learner_a,both_hw,'image/jpeg','crimp.jpg')->>'id')::uuid id from req;
grant select on att to service_role;
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','  ','file_ids',jsonb_build_array(%L)))$$,
  learner_a,both_hw,(select id from att)),'22023','HOMEWORK_ANSWER_REQUIRED','an image without the written answer is refused') from req;
select ok((public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',both_hw,'answer','Termination done',
  'file_ids',jsonb_build_array((select id from att))))->>'status')='submitted','an answer with the image is accepted') from req;
reset role;
select is((select count(*)::int from public.homework_files where submission_id=(select id from public.homework_submissions
  where assignment_id=(select both_hw from req) and learner_id=(select learner_a from req))),1,'the image is linked to the submission');
-- A stray non-image row that bypassed attach still cannot be submitted.
insert into public.homework_files(id,assignment_id,owner_id,kind,filename,object_path,mime_type,size_bytes)
select gen_random_uuid(),both_hw,learner_b,'answer','notes.pdf','homework/'||gen_random_uuid()||'/notes.pdf','application/pdf',2048 from req;
set local role service_role;
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','Notes','file_ids',
  (select jsonb_agg(id) from public.homework_files where owner_id=%L and assignment_id=%L)))$$,learner_b,both_hw,learner_b,both_hw),
  '22023','HOMEWORK_IMAGE_FILES_REQUIRED','a non-image file is refused at submit where images are required') from req;

-- File only.
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','','file_ids','[]'::jsonb))$$,
  learner_a,file_hw),'22023','HOMEWORK_FILES_REQUIRED','a file-only task needs its file') from req;
create temporary table att_file as select (pg_temp.attach(learner_a,file_hw,'application/pdf','report.pdf')->>'id')::uuid id from req;
grant select on att_file to service_role;
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','My report text','file_ids',jsonb_build_array(%L)))$$,
  learner_a,file_hw,(select id from att_file)),'22023','HOMEWORK_ANSWER_NOT_ACCEPTED','a file-only task refuses a written answer') from req;
select ok((public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',file_hw,'answer','',
  'file_ids',jsonb_build_array((select id from att_file))))->>'answer')='','a file-only task accepts the file alone') from req;
-- Two required files of any supported type.
create temporary table att_two as select (pg_temp.attach(learner_c,any_file_hw,'application/pdf','one.pdf')->>'id')::uuid id from req;
grant select on att_two to service_role;
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','','file_ids',jsonb_build_array(%L)))$$,
  learner_c,any_file_hw,(select id from att_two)),'22023','HOMEWORK_FILES_REQUIRED','one file is not enough when two are required') from req;
insert into att_two select (pg_temp.attach(learner_c,any_file_hw,'image/png','two.png')->>'id')::uuid from req;
select ok((public.manage_homework(learner_c,'submit',jsonb_build_object('assignment_id',any_file_hw,'answer','',
  'file_ids',(select jsonb_agg(id) from att_two)))->>'status')='submitted','two files of any supported type are accepted') from req;

-- Written answer only.
select throws_ok(format($$select pg_temp.attach(%L,%L,'image/png','photo.png')$$,learner_a,answer_hw),'22023','HOMEWORK_FILES_NOT_ACCEPTED',
  'a written-answer-only task refuses files') from req;
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','','file_ids','[]'::jsonb))$$,
  learner_a,answer_hw),'22023','HOMEWORK_ANSWER_REQUIRED','a written-answer-only task needs the answer') from req;
select ok((public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',answer_hw,'answer','My reflection','file_ids','[]'::jsonb))->>'status')='submitted',
  'a written answer is accepted') from req;

-- Existing behaviour: answer or file.
select throws_ok(format($$select public.manage_homework(%L,'submit',jsonb_build_object('assignment_id',%L,'answer','','file_ids','[]'::jsonb))$$,
  learner_d,legacy_hw),'22023','ANSWER_OR_FILE_REQUIRED','answer-or-file still needs one of them') from req;
select ok((public.manage_homework(learner_d,'submit',jsonb_build_object('assignment_id',legacy_hw,'answer','Plain answer','file_ids','[]'::jsonb))->>'status')='submitted',
  'answer-or-file accepts a written answer alone') from req;
select ok((pg_temp.attach(learner_b,legacy_hw,'application/pdf','legacy.pdf')->>'mime_type')='application/pdf',
  'answer-or-file accepts any supported file type') from req;

-- Retries stay idempotent and redacted.
select ok((public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',both_hw,'answer','','file_ids','[]'::jsonb))->>'answer')='Termination done',
  'a retry after submitting returns the stored submission without re-checking the rules') from req;
select ok((public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',both_hw,'answer','','file_ids','[]'::jsonb))->'score') = 'null'::jsonb,
  'the retry stays the learner view') from req;
reset role;

-- Learners read the rules through RLS (the activities API selects *).
set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',(select learner_a from req),'role','authenticated')::text, true);
select ok(exists(select 1 from public.homework_assignments where id=(select both_hw from req)
  and submission_format='answer_and_file' and required_file_count=1 and accepted_file_types='image'),
  'an enrolled learner can read the submission rules');
reset role;

select is((select count(*)::int from public.homework_assignments where submission_format='answer_or_file' and created_at < now() - interval '1 second'
  and (required_file_count<>0 or accepted_file_types<>'any')),0,'existing assignments keep answer-or-file with no file rules');

select * from finish();
rollback;
