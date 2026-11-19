-- Homework organised by COC/mission with objectives, criteria and a maximum
-- score, graded through Evaluate (grade) -> Finalize -> Release. Learners see a
-- grade only after release; pre-workflow graded rows are migrated as released.
-- Rollback-only.
begin;
select plan(57);

create temporary table hw as select
  gen_random_uuid() teacher, gen_random_uuid() other_teacher,
  gen_random_uuid() learner_a, gen_random_uuid() learner_b, gen_random_uuid() learner_c,
  gen_random_uuid() class_id, gen_random_uuid() other_class_id,
  (select id from public.coc_modules where coc_code='coc1') coc1,
  (select id from public.coc_modules where coc_code='coc2') coc2,
  (select id from public.curriculum_modules where coc_code='coc1' and code='LO1.1') lo11,
  (select id from public.curriculum_modules where coc_code='coc1' and code='LO1.4') lo14,
  null::uuid criteria_hw, null::uuid plain_hw, null::uuid mission_hw, null::uuid other_hw,
  null::uuid sub_a, null::uuid sub_b, null::uuid sub_c, null::uuid plain_a, null::uuid other_sub,
  null::uuid legacy_sub, null::uuid legacy_hw;
grant select on hw to authenticated;
grant select, update on hw to service_role;
create temporary table hw_results(label text primary key, payload jsonb);
grant select, insert on hw_results to service_role;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@homework-redefense.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',name),now(),now()
from hw cross join lateral (values (teacher,'HW Teacher'),(other_teacher,'HW Other Teacher'),(learner_a,'HW Learner A'),
  (learner_b,'HW Learner B'),(learner_c,'HW Learner C')) t(id,name);
update public.profiles set role='instructor' where user_id in (select teacher from hw union all select other_teacher from hw);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_id,'HW redefense class','HW-'||left(class_id::text,8),teacher,teacher from hw union all
select other_class_id,'HW other class','HW-'||left(other_class_id::text,8),other_teacher,other_teacher from hw;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_id,l,teacher from hw cross join lateral (values (learner_a),(learner_b),(learner_c)) t(l) union all
select other_class_id,learner_a,other_teacher from hw;

-- Contract.
select ok(not (select prosecdef from pg_proc where oid='public.manage_homework(uuid,text,jsonb)'::regprocedure)
  and has_function_privilege('service_role','public.manage_homework(uuid,text,jsonb)','execute')
  and not has_function_privilege('authenticated','public.manage_homework(uuid,text,jsonb)','execute'),
  'manage_homework stays a service-only SECURITY INVOKER function');
select is((select string_agg(column_name,',' order by column_name) from information_schema.columns
  where table_schema='public' and table_name='homework_assignments'
    and column_name in ('coc_module_id','module_id','mission_code','learning_objectives','criteria','max_score','submission_requirements')),
  'coc_module_id,criteria,learning_objectives,max_score,mission_code,module_id,submission_requirements',
  'assignments carry curriculum links, objectives, criteria, maximum score and requirements');
select is((select string_agg(column_name,',' order by column_name) from information_schema.columns
  where table_schema='public' and table_name='homework_submissions'
    and column_name in ('criterion_scores','finalized_by','finalized_at','released_by','released_at')),
  'criterion_scores,finalized_at,finalized_by,released_at,released_by','submissions carry criterion scores and finalize/release stamps');

-- Authoring with COC -> mission -> module, objectives and criteria.
set local role service_role;
update hw set criteria_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Assembly safety report',
  'instructions','Document the assembly safety checks.','deadline_at',null,'coc_module_id',coc1,'mission_code','coc1_m2','module_id',lo11,
  'learning_objectives',jsonb_build_array('  Apply ESD precautions  ','Follow the assembly order',''),
  'criteria',jsonb_build_array(jsonb_build_object('id','safety','criterion','Safety checks','description','Power and ESD','max_points',30),
    jsonb_build_object('id','order','criterion','Assembly order','max_points',20)),
  'submission_requirements','PDF report with photos'))->>'id')::uuid;
update hw set plain_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Legacy style homework',
  'instructions','Write a network report.','deadline_at',null))->>'id')::uuid;
update hw set mission_hw=(public.manage_homework(teacher,'create',jsonb_build_object('class_id',class_id,'title','Mission linked homework',
  'instructions','Reflect on the mission.','mission_code','coc1_m5'))->>'id')::uuid;
reset role;
select is((select max_score from public.homework_assignments where id=(select criteria_hw from hw)),50::numeric,
  'the maximum score equals the criteria total');
select is((select array_to_string(learning_objectives,'|') from public.homework_assignments where id=(select criteria_hw from hw)),
  'Apply ESD precautions|Follow the assembly order','objectives are trimmed and blank entries dropped');
select is((select jsonb_array_length(criteria) from public.homework_assignments where id=(select criteria_hw from hw)),2,'criteria are stored');
select ok((select coc_module_id=(select coc1 from hw) and module_id=(select lo11 from hw) and mission_code='coc1_m2'
  and submission_requirements='PDF report with photos' from public.homework_assignments where id=(select criteria_hw from hw)),
  'COC, mission, module and submission requirements are stored');
select ok((select max_score=100 and criteria='[]'::jsonb and learning_objectives='{}' and coc_module_id is null and module_id is null
  and mission_code is null from public.homework_assignments where id=(select plain_hw from hw)),
  'an unlinked assignment keeps the previous payload and defaults (max score 100)');
select ok((select module_id=(select lo14 from hw) and coc_module_id=(select coc1 from hw) from public.homework_assignments
  where id=(select mission_hw from hw)),'module and COC are derived from the mission curriculum link when omitted');

set local role service_role;
select throws_ok(format('select public.manage_homework(%L,''create'',%L)',(select teacher from hw),jsonb_build_object('class_id',(select class_id from hw),
  'title','Mismatched max','instructions','Report.','max_score',80,'criteria',jsonb_build_array(jsonb_build_object('criterion','Only','max_points',40)))),
  '22023','HOMEWORK_MAX_SCORE_MUST_EQUAL_CRITERIA_TOTAL','an explicit maximum score must equal the criteria total');
select throws_ok(format('select public.manage_homework(%L,''create'',%L)',(select teacher from hw),jsonb_build_object('class_id',(select class_id from hw),
  'title','Wrong COC','instructions','Report.','coc_module_id',(select coc2 from hw),'mission_code','coc1_m2','module_id',(select lo11 from hw))),
  '22023','HOMEWORK_CURRICULUM_MISMATCH','the mission and module must belong to the selected COC');
select throws_ok(format('select public.manage_homework(%L,''create'',%L)',(select teacher from hw),jsonb_build_object('class_id',(select class_id from hw),
  'title','Bad criteria','instructions','Report.','criteria',jsonb_build_array(jsonb_build_object('criterion','Zero points','max_points',0)))),
  '22023','HOMEWORK_CRITERIA_INVALID','each criterion needs a name and positive points');
select throws_ok(format('select public.manage_homework(%L,''create'',%L)',(select teacher from hw),jsonb_build_object('class_id',(select class_id from hw),
  'title','Duplicate criteria','instructions','Report.','criteria',jsonb_build_array(jsonb_build_object('id','x','criterion','One','max_points',5),
    jsonb_build_object('id','x','criterion','Two','max_points',5)))),
  '22023','HOMEWORK_CRITERIA_INVALID','criterion identifiers are unique');
select throws_ok(format('select public.manage_homework(%L,''create'',%L)',(select teacher from hw),jsonb_build_object('class_id',(select class_id from hw),
  'title','Unknown mission','instructions','Report.','mission_code','coc9_m9')),
  '22023','HOMEWORK_CURRICULUM_MISMATCH','an unknown mission is rejected');
-- A previous-version edit payload (no curriculum keys) keeps the stored criteria.
select lives_ok(format('select public.manage_homework(%L,''edit'',%L)',(select teacher from hw),jsonb_build_object('assignment_id',(select criteria_hw from hw),
  'title','Assembly safety report v2','instructions','Document the assembly safety checks.','deadline_at',null)),
  'an edit from an older client keeps working');
reset role;
select ok((select title='Assembly safety report v2' and max_score=50 and jsonb_array_length(criteria)=2 from public.homework_assignments
  where id=(select criteria_hw from hw)),'an edit without curriculum fields leaves them unchanged');
select throws_ok(format('update public.homework_assignments set max_score=60 where id=%L',(select criteria_hw from hw)),
  '22023','HOMEWORK_MAX_SCORE_MUST_EQUAL_CRITERIA_TOTAL','the database rejects a criteria/maximum mismatch from any writer');

-- Publish, submit, and the other class.
set local role service_role;
select public.manage_homework(teacher,'publish',jsonb_build_object('assignment_id',h)) from hw cross join lateral (values (criteria_hw),(plain_hw)) t(h);
update hw set other_hw=(public.manage_homework(other_teacher,'create',jsonb_build_object('class_id',other_class_id,'title','Other class homework',
  'instructions','Other report.'))->>'id')::uuid;
select public.manage_homework(other_teacher,'publish',jsonb_build_object('assignment_id',other_hw)) from hw;
update hw set sub_a=(public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',criteria_hw,'answer','Safety report A','file_ids','[]'::jsonb))->>'id')::uuid;
update hw set sub_b=(public.manage_homework(learner_b,'submit',jsonb_build_object('assignment_id',criteria_hw,'answer','Safety report B','file_ids','[]'::jsonb))->>'id')::uuid;
update hw set sub_c=(public.manage_homework(learner_c,'submit',jsonb_build_object('assignment_id',criteria_hw,'answer','Safety report C','file_ids','[]'::jsonb))->>'id')::uuid;
update hw set plain_a=(public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',plain_hw,'answer','Plain report','file_ids','[]'::jsonb))->>'id')::uuid;
update hw set other_sub=(public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',other_hw,'answer','Other report','file_ids','[]'::jsonb))->>'id')::uuid;

-- Grading (Evaluate): bounded by the assignment maximum and criteria.
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select teacher from hw),jsonb_build_object('assignment_id',(select plain_hw from hw),
  'submission_id',(select plain_a from hw),'score',120,'feedback','Too high')),
  '22023','HOMEWORK_SCORE_EXCEEDS_MAX','a score above the assignment maximum is denied');
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select teacher from hw),jsonb_build_object('assignment_id',(select criteria_hw from hw),
  'submission_id',(select sub_a from hw),'criterion_scores',jsonb_build_object('safety',31,'order',10))),
  '22023','HOMEWORK_CRITERION_SCORES_INVALID','a criterion score above its points is denied');
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select teacher from hw),jsonb_build_object('assignment_id',(select criteria_hw from hw),
  'submission_id',(select sub_a from hw),'criterion_scores',jsonb_build_object('safety',20))),
  '22023','HOMEWORK_CRITERION_SCORES_INVALID','every criterion must be scored');
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select teacher from hw),jsonb_build_object('assignment_id',(select criteria_hw from hw),
  'submission_id',(select sub_a from hw),'score',40)),
  '22023','HOMEWORK_CRITERION_SCORES_REQUIRED','criteria-based homework is scored per criterion');
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select teacher from hw),jsonb_build_object('assignment_id',(select criteria_hw from hw),
  'submission_id',(select sub_a from hw),'score',45,'criterion_scores',jsonb_build_object('safety',25,'order',10))),
  '22023','HOMEWORK_SCORE_MUST_EQUAL_CRITERIA_TOTAL','a total that differs from the criterion scores is denied');
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select other_teacher from hw),jsonb_build_object('assignment_id',(select criteria_hw from hw),
  'submission_id',(select sub_a from hw),'score',null,'feedback','Not mine')),
  '42501','HOMEWORK_SCOPE_DENIED','another instructor cannot grade this class homework');
insert into hw_results select 'grade-a',public.manage_homework(teacher,'grade',jsonb_build_object('submission_id',sub_a,
  'criterion_scores',jsonb_build_object('safety',25,'order',15),'feedback','Clear safety checks.')) from hw;
insert into hw_results select 'grade-b',public.manage_homework(teacher,'grade',jsonb_build_object('assignment_id',criteria_hw,'submission_id',sub_b,
  'criterion_scores',jsonb_build_object('safety',10,'order',10),'feedback','Review the ESD steps.')) from hw;
select public.manage_homework(teacher,'grade',jsonb_build_object('assignment_id',criteria_hw,'submission_id',sub_b,
  'criterion_scores',jsonb_build_object('safety',12,'order',10),'feedback','Review the ESD steps again.')) from hw;
-- A learner's idempotent submit retry must never carry an unreleased grade.
insert into hw_results select 'replay-graded',public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',criteria_hw,
  'answer','Retry after grading','file_ids','[]'::jsonb)) from hw;
reset role;
select is((select payload->>'id' from hw_results where label='replay-graded'),(select sub_a::text from hw),
  'a submit retry returns the existing submission');
select ok((select payload->'score'='null'::jsonb and payload->'feedback'='null'::jsonb and payload->'criterion_scores'='null'::jsonb
    and payload->'graded_by'='null'::jsonb and payload->'graded_at'='null'::jsonb and payload->>'answer'='Safety report A'
  from hw_results where label='replay-graded'),
  'a submit retry after grading returns no score, feedback, criterion scores or grader');
select ok((select status='graded' and score=40 and criterion_scores=jsonb_build_object('safety',25,'order',15) and graded_by=(select teacher from hw)
  from public.homework_submissions where id=(select sub_a from hw)),'the total is computed from the criterion scores');
select ok((select score=22 and feedback='Review the ESD steps again.' from public.homework_submissions where id=(select sub_b from hw)),
  'a draft grade stays editable while graded');
select is((select count(*)::integer from public.audit_events where target_id=(select sub_b from hw) and action in ('homework.graded','homework.grade_updated')),2,
  'the first grade and the edit are both audited');
select throws_ok(format('update public.homework_submissions set score=51 where id=%L',(select sub_c from hw)),
  '22023','HOMEWORK_SCORE_EXCEEDS_MAX','the database rejects a score above the assignment maximum from any writer');
select is((select count(*)::integer from public.notifications where event_key in ('homework.graded:'||(select sub_a from hw),'homework.released:'||(select sub_a from hw))),0,
  'saving a draft grade notifies nobody');

-- Learners never read an unreleased grade.
select set_config('request.jwt.claim.sub',(select learner_a::text from hw),true);
set local role authenticated;
select is((select count(*)::integer from public.homework_submissions where id=(select sub_a from hw)),0,
  'a learner cannot read an unreleased graded submission directly');
select is((select count(*)::integer from public.homework_submissions where id=(select plain_a from hw) and status='submitted' and score is null),1,
  'a learner still sees their own ungraded submission');
reset role;

-- Finalize: graded -> finalized, per-item results, ownership enforced.
set local role service_role;
insert into hw_results select 'finalize',public.manage_homework(teacher,'finalize',jsonb_build_object('submission_ids',jsonb_build_array(sub_a,sub_c,other_sub))) from hw;
reset role;
select is((select (payload->>'succeeded')::integer||'/'||(payload->>'failed')::integer from hw_results where label='finalize'),'1/2',
  'bulk finalize reports per-item success and failure');
select is((select string_agg(coalesce(r->>'error','ok'),',' order by ord) from hw_results, jsonb_array_elements(payload->'results') with ordinality x(r,ord)
  where label='finalize'),'ok,HOMEWORK_GRADE_REQUIRED,HOMEWORK_SCOPE_DENIED','ungraded and foreign submissions are refused individually');
select ok((select status='finalized' and finalized_by=(select teacher from hw) and finalized_at is not null and released_at is null
  from public.homework_submissions where id=(select sub_a from hw)),'the graded submission is finalized');
set local role service_role;
select throws_ok(format('select public.manage_homework(%L,''grade'',%L)',(select teacher from hw),jsonb_build_object('submission_id',(select sub_a from hw),
  'criterion_scores',jsonb_build_object('safety',30,'order',20))),
  '55000','HOMEWORK_GRADE_LOCKED','a finalized grade can no longer be edited');
insert into hw_results select 'release-early',public.manage_homework(teacher,'release',jsonb_build_object('submission_ids',jsonb_build_array(sub_b))) from hw;
insert into hw_results select 'replay-finalized',public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',criteria_hw,
  'answer','Retry after finalization','file_ids','[]'::jsonb)) from hw;
select throws_ok(format('select public.manage_homework(%L,''release'',%L)',(select learner_a from hw),jsonb_build_object('submission_ids',jsonb_build_array((select sub_a from hw)))),
  '42501','INSTRUCTOR_CLASS_SCOPE_REQUIRED','a learner cannot release grades');
select throws_ok(format('select public.manage_homework(%L,''release'',%L)',(select teacher from hw),
  jsonb_build_object('submission_ids',(select jsonb_agg(gen_random_uuid()) from generate_series(1,51)))),
  '22023','HOMEWORK_SUBMISSION_IDS_INVALID','bulk actions accept at most fifty submissions');
select throws_ok(format('select public.manage_homework(%L,''release'',%L)',(select teacher from hw),
  jsonb_build_object('submission_ids',jsonb_build_array((select sub_a from hw),(select sub_a from hw)))),
  '22023','HOMEWORK_SUBMISSION_IDS_INVALID','bulk actions reject duplicate submissions');
reset role;
select is((select payload->'results'->0->>'error' from hw_results where label='release-early'),'HOMEWORK_FINALIZE_REQUIRED',
  'a graded submission cannot be released before finalization');
select ok((select payload->>'status'='finalized' and payload->'score'='null'::jsonb and payload->'feedback'='null'::jsonb
    and payload->'criterion_scores'='null'::jsonb and payload->'finalized_by'='null'::jsonb
  from hw_results where label='replay-finalized'),'a submit retry after finalization still returns no grade');

-- Release: finalized -> released, notification on release, bulk idempotent.
set local role service_role;
select public.manage_homework(teacher,'finalize',jsonb_build_object('submission_ids',jsonb_build_array(sub_b))) from hw;
insert into hw_results select 'release',public.manage_homework(teacher,'release',jsonb_build_object('submission_ids',jsonb_build_array(sub_a,sub_b))) from hw;
insert into hw_results select 'release-again',public.manage_homework(teacher,'release',jsonb_build_object('submission_ids',jsonb_build_array(sub_a,sub_b))) from hw;
insert into hw_results select 'replay-released',public.manage_homework(learner_a,'submit',jsonb_build_object('assignment_id',criteria_hw,
  'answer','Retry after release','file_ids','[]'::jsonb)) from hw;
reset role;
select ok((select (payload->>'score')::numeric=40 and payload->>'feedback'='Clear safety checks.' and payload->>'status'='released'
  from hw_results where label='replay-released'),'once released, a submit retry carries the released result');
select is((select (payload->>'succeeded')::integer from hw_results where label='release'),2,'finalized submissions are released in bulk');
select ok((select bool_and(status='released' and released_by=(select teacher from hw) and released_at is not null)
  from public.homework_submissions where id in ((select sub_a from hw),(select sub_b from hw))),'released submissions record who released them and when');
select is((select string_agg(r->>'changed',',' order by ord) from hw_results, jsonb_array_elements(payload->'results') with ordinality x(r,ord)
  where label='release-again'),'false,false','repeating a bulk release is an idempotent no-op');
select is((select count(*)::integer from public.audit_events where action='homework.released' and target_id in ((select sub_a from hw),(select sub_b from hw))),2,
  'each release is audited exactly once');
select is((select count(*)::integer from public.notifications n where n.event_key='homework.released:'||(select sub_a from hw)
  and n.user_id=(select learner_a from hw) and n.metadata->>'activity_type'='homework'),1,'release notifies the learner exactly once');
select is((select count(*)::integer from public.notifications n where n.event_key like 'homework.released:%'
  and n.user_id not in ((select learner_a from hw),(select learner_b from hw))),0,'no other learner is notified of a release');

select set_config('request.jwt.claim.sub',(select learner_a::text from hw),true);
set local role authenticated;
select ok((select score=40 and feedback='Clear safety checks.' and criterion_scores=jsonb_build_object('safety',25,'order',15)
  from public.homework_submissions where id=(select sub_a from hw)),'after release the learner reads the score, feedback and criterion scores');
reset role;

-- Lifecycle integrity.
select throws_ok(format('update public.homework_submissions set status=''released'' where id=%L',(select sub_c from hw)),
  '23514',null,'a submission cannot jump to released without the finalize and release stamps');

-- Backfill: grades recorded before the workflow were already visible, so they are released unchanged.
update hw set legacy_hw=(select id from public.homework_assignments where id=plain_hw);
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-4000-8000-0000000a4002'::uuid,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',
  'legacy-learner@homework-redefense.invalid','','{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"HW Legacy Learner"}'::jsonb,now(),now();
insert into public.class_memberships(class_id,learner_id,enrolled_by) select class_id,'00000000-0000-4000-8000-0000000a4002'::uuid,teacher from hw;
insert into public.homework_submissions(id,assignment_id,learner_id,answer,submitted_at,effective_deadline_at,deadline_revision,status,feedback,score,graded_at,graded_by)
select '00000000-0000-4000-8000-0000000a4001'::uuid,plain_hw,'00000000-0000-4000-8000-0000000a4002'::uuid,'Graded before the workflow',
  '2026-11-13 08:00+00',null,1,'graded','Legacy feedback kept verbatim.',88,'2026-11-13 09:30+00',teacher from hw;
update hw set legacy_sub='00000000-0000-4000-8000-0000000a4001';
set local role service_role;
insert into hw_results select 'new-graded',public.manage_homework(teacher,'grade',jsonb_build_object('submission_id',plain_a,'score',70,'feedback','Post-cutover draft')) from hw;
reset role;
select is(private.release_pre_workflow_homework_grades(),1,'the backfill releases exactly the pre-workflow graded submission');
select ok((select status='released' and score=88 and feedback='Legacy feedback kept verbatim.'
  and finalized_at=graded_at and released_at=graded_at and finalized_by=graded_by and released_by=graded_by
  from public.homework_submissions where id=(select legacy_sub from hw)),
  'a backfilled grade is released with identical score, feedback and timestamps');
select is((select status from public.homework_submissions where id=(select plain_a from hw)),'graded',
  'a grade saved under the new workflow is never auto-released');
select is((select count(*)::integer from public.audit_events where action='homework.release_backfill' and target_id=(select legacy_sub from hw)),1,
  'the backfill is audited per submission');
select is((select count(*)::integer from public.notifications where event_key like '%'||(select legacy_sub from hw)::text),0,
  'the backfill sends no new notification');
select is(private.release_pre_workflow_homework_grades(),0,'running the backfill again changes nothing');
select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),0,'every public table keeps RLS enabled');
select * from finish();
rollback;
