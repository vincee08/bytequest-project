-- Evaluation Center queue (Objective 4): one RLS-scoped read of the Evaluate,
-- Finalize, Release and Released stages across technical attempts, homework
-- and (when slice A3's function exists) quizzes. Rollback-only.
begin;
select plan(45);
-- Learner calls identify as the 1.2.0 app (client version guard, 20261120100000).
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);

create temporary table q as select
  gen_random_uuid() t1, gen_random_uuid() t2, gen_random_uuid() l1, gen_random_uuid() l2, gen_random_uuid() admin_user,
  gen_random_uuid() c1, gen_random_uuid() c2,
  null::uuid source_id, null::uuid module_version_id, null::uuid activity_version_id, null::uuid rubric_id,
  null::uuid assignment_c1, null::uuid assignment_c2,
  null::uuid hw_c1, null::uuid hw_c1_coc2, null::uuid hw_c2,
  (select id from public.coc_modules where coc_code='coc1') coc1,
  (select id from public.coc_modules where coc_code='coc2') coc2,
  (select id from public.curriculum_modules where coc_code='coc1' and code='LO1.1') lo11,
  (select id from public.curriculum_modules where coc_code='coc2' and code='LO2.1') lo21;
grant select on q to authenticated, service_role;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@evaluation-queue.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,jsonb_build_object('full_name',name),now(),now()
from q cross join lateral (values (t1,'Queue Teacher One'),(t2,'Queue Teacher Two'),(l1,'Queue Learner One'),
  (l2,'Queue Learner Two'),(admin_user,'Queue Admin')) t(id,name);
update public.profiles set role='instructor' where user_id in (select t1 from q union all select t2 from q);
update public.profiles set role='admin' where user_id=(select admin_user from q);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select c1,'Queue class one','QC-'||left(c1::text,8),t1,t1 from q union all
select c2,'Queue class two','QC-'||left(c2::text,8),t2,t2 from q;
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select c1,l,t1 from q cross join lateral (values (l1),(l2)) t(l) union all select c2,l1,t2 from q;

-- Technical fixtures (COC1 M2 assessment) in every stage.
with inserted as (
  insert into public.tesda_sources(qualification_code,title,edition,source_reference,status,validation_notes,created_by,approved_by,approved_at,activated_by,activated_at)
  select 'QQ-'||left(gen_random_uuid()::text,8),'Queue rollback source','TEST_ONLY','Rollback fixture only','active','TEST_ONLY_ROLLBACK_FIXTURE',
    admin_user,admin_user,now(),admin_user,now() from q returning id)
update q set source_id=inserted.id from inserted;
with inserted as (
  insert into public.module_versions(module_id,tesda_source_id,version_number,title,source_trace,status,created_by,published_by,published_at)
  select q.coc1,q.source_id,coalesce((select max(version_number) from public.module_versions mv where mv.module_id=q.coc1),0)+1,
    'Queue rollback module',jsonb_build_object('status','TEST_ONLY'),'published',q.admin_user,q.admin_user,now() from q returning id)
update q set module_version_id=inserted.id from inserted;
with inserted as (
  insert into public.activity_versions(mission_id,module_version_id,version_number,title,delivery_mode,learner_payload,evaluator_config,status,created_by,published_by,published_at)
  select m.id,q.module_version_id,coalesce((select max(version_number) from public.activity_versions av where av.mission_id=m.id),0)+1,
    'Queue rollback assessment','assessment','{}'::jsonb,'{}'::jsonb,'published',q.admin_user,q.admin_user,now()
  from q cross join public.missions m where m.mission_code='coc1_m2' returning id)
update q set activity_version_id=inserted.id from inserted;
with inserted as (
  insert into public.rubric_versions(activity_version_id,tesda_source_id,version_number,title,status,scoring_method,passing_rule,created_by,approved_by,approved_at)
  select activity_version_id,source_id,1,'Queue rollback rubric','approved','binary_sum',jsonb_build_object('status','APPROVED','method','all_required'),
    admin_user,admin_user,now() from q returning id)
update q set rubric_id=inserted.id from inserted;
with inserted as (
  insert into public.assignments(class_id,activity_version_id,rubric_version_id,assignment_type,title,assigned_by)
  select c1,activity_version_id,rubric_id,'assessment','Install internal components (assessment)',t1 from q returning id)
update q set assignment_c1=inserted.id from inserted;
with inserted as (
  insert into public.assignments(class_id,activity_version_id,rubric_version_id,assignment_type,title,assigned_by)
  select c2,activity_version_id,rubric_id,'assessment','Other class assessment',t2 from q returning id)
update q set assignment_c2=inserted.id from inserted;
insert into public.attempts(learner_id,class_id,assignment_id,activity_version_id,rubric_version_id,tesda_source_id,status,
  client_start_key,submission_key,submitted_at,evaluated_at)
select a.learner,a.class_id,a.assignment_id,q.activity_version_id,q.rubric_id,q.source_id,a.status::public.attempt_status,
  gen_random_uuid(),gen_random_uuid(),a.submitted_at,a.submitted_at
from q cross join lateral (values
  (q.l1,q.c1,q.assignment_c1,'evaluated',timestamptz '2026-11-18 01:00+00'),
  (q.l2,q.c1,q.assignment_c1,'evaluated',timestamptz '2026-11-18 03:00+00'),
  (q.l1,q.c1,q.assignment_c1,'under_review',timestamptz '2026-11-17 01:00+00'),
  (q.l2,q.c1,q.assignment_c1,'finalized',timestamptz '2026-11-16 01:00+00'),
  (q.l1,q.c1,q.assignment_c1,'released',timestamptz '2026-11-15 01:00+00'),
  (q.l1,q.c2,q.assignment_c2,'evaluated',timestamptz '2026-11-18 02:00+00')) a(learner,class_id,assignment_id,status,submitted_at);
insert into public.score_revisions(attempt_id,revision_number,revision_type,tesda_source_id,rubric_version_id,evaluation_run_id,total_value,max_value,percentage,outcome,criterion_values)
select a.id,1,'automated_provisional',a.tesda_source_id,a.rubric_version_id,gen_random_uuid(),1,2,50,'not_yet_competent','[]'::jsonb
from public.attempts a join q on a.rubric_version_id=q.rubric_id;

-- Homework fixtures in every stage (two COC links and one unlinked class).
insert into public.homework_assignments(class_id,instructor_id,title,instructions,status,published_at,coc_module_id,module_id,mission_code)
select c1,t1,'Assembly report','Report.','published',now(),coc1,lo11,'coc1_m2' from q;
update q set hw_c1=(select id from public.homework_assignments where title='Assembly report' and class_id=q.c1);
insert into public.homework_assignments(class_id,instructor_id,title,instructions,status,published_at,coc_module_id,module_id)
select c1,t1,'Cabling report','Report.','published',now(),coc2,lo21 from q;
update q set hw_c1_coc2=(select id from public.homework_assignments where title='Cabling report' and class_id=q.c1);
insert into public.homework_assignments(class_id,instructor_id,title,instructions,status,published_at)
select c2,t2,'Other class report','Report.','published',now() from q;
update q set hw_c2=(select id from public.homework_assignments where class_id=q.c2);
insert into public.homework_submissions(assignment_id,learner_id,answer,submitted_at,deadline_revision,status,score,feedback,graded_at,graded_by,finalized_at,finalized_by,released_at,released_by)
select s.hw,s.learner,'Answer',s.submitted_at,1,s.status,s.score,null,
  case when s.status<>'submitted' then s.submitted_at end, case when s.status<>'submitted' then q.t1 end,
  case when s.status in ('finalized','released') then s.submitted_at end, case when s.status in ('finalized','released') then q.t1 end,
  case when s.status='released' then s.submitted_at end, case when s.status='released' then q.t1 end
from q cross join lateral (values
  (q.hw_c1,q.l1,'submitted',null::numeric,timestamptz '2026-11-18 00:30+00'),
  (q.hw_c1_coc2,q.l2,'submitted',null,timestamptz '2026-11-18 04:00+00'),
  (q.hw_c1,q.l2,'graded',80,timestamptz '2026-11-17 00:30+00'),
  (q.hw_c1_coc2,q.l1,'finalized',70,timestamptz '2026-11-16 00:30+00')) s(hw,learner,status,score,submitted_at);
insert into public.homework_submissions(assignment_id,learner_id,answer,submitted_at,deadline_revision,status)
select hw_c2,l1,'Answer','2026-11-18 05:00+00',1,'submitted' from q;

-- Contract.
select ok(to_regprocedure('public.get_evaluation_queue(text,jsonb)') is not null
  and not (select prosecdef from pg_proc where oid='public.get_evaluation_queue(text,jsonb)'::regprocedure),
  'get_evaluation_queue(p_stage, p_filters) is SECURITY INVOKER');
select ok(has_function_privilege('authenticated','public.get_evaluation_queue(text,jsonb)','execute')
  and not has_function_privilege('anon','public.get_evaluation_queue(text,jsonb)','execute'),
  'signed-in staff can read the queue; anonymous callers cannot');

-- Instructor one: own classes only, every stage counted per kind.
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
select is(public.get_evaluation_queue('evaluate','{}')->'counts','{"evaluate":4,"finalize":2,"release":2,"released":1}'::jsonb,
  'counts cover technical evaluated/under_review/finalized/released and homework submitted/graded/finalized/released');
select is((select jsonb_agg(i->>'kind' order by ord) from jsonb_array_elements(public.get_evaluation_queue('evaluate','{}')->'items') with ordinality x(i,ord)),
  '["homework","technical","technical","homework"]'::jsonb,'evaluate items are the oldest submissions first across kinds');
select is((select string_agg(i->>'status',',' order by ord) from jsonb_array_elements(public.get_evaluation_queue('finalize','{}')->'items') with ordinality x(i,ord)),
  'graded,under_review','finalize holds saved homework grades and recorded technical evaluations, oldest first');
select is((select string_agg(i->>'status',',' order by ord) from jsonb_array_elements(public.get_evaluation_queue('release','{}')->'items') with ordinality x(i,ord)),
  'finalized,finalized','release holds finalized items');
select is((select string_agg(i->>'kind'||':'||(i->>'status'),',') from jsonb_array_elements(public.get_evaluation_queue('released','{}')->'items') i),
  'technical:released','released holds released results');
select is((select count(*)::integer from jsonb_array_elements(public.get_evaluation_queue('evaluate','{}')->'items') i
  where i->'class'->>'id'=(select c2::text from q)),0,'another instructor''s class never appears');
select ok((select i ?& array['kind','id','title','learner','class','submitted_at','status','score','max_score','link']
    and i->'learner' ?& array['id','name'] and i->'class' ?& array['id','title']
  from jsonb_array_elements(public.get_evaluation_queue('evaluate','{"kind":"technical"}')->'items') i limit 1),
  'items carry the documented shape');
select is((select i->>'link' from jsonb_array_elements(public.get_evaluation_queue('finalize','{"kind":"technical"}')->'items') i),
  '/attempts/'||(select a.id::text from public.attempts a where a.status='under_review' and a.class_id=(select c1 from q)),
  'technical items link to the attempt review');
select is((select i->>'link' from jsonb_array_elements(public.get_evaluation_queue('finalize','{"kind":"homework"}')->'items') i),
  (select '/classes/'||h.class_id||'/assignments/'||h.id||'?submission='||s.id from public.homework_submissions s
   join public.homework_assignments h on h.id=s.assignment_id where s.status='graded' and h.class_id=(select c1 from q)),
  'homework items link to the submission in its assignment');
select ok((select (i->>'score')::numeric=80 and (i->>'max_score')::numeric=100 and i->'learner'->>'name'='Queue Learner Two'
  and i->'class'->>'title'='Queue class one' and i->>'title'='Assembly report'
  from jsonb_array_elements(public.get_evaluation_queue('finalize','{"kind":"homework"}')->'items') i),
  'homework items carry the draft score, maximum, learner and class');
select ok((select (i->>'score')::numeric=1 and (i->>'max_score')::numeric=2 and i->>'title'='Install internal components (assessment)'
  from jsonb_array_elements(public.get_evaluation_queue('finalize','{"kind":"technical"}')->'items') i),
  'technical items carry the latest revision score and the assignment title');

-- Filters.
select is(public.get_evaluation_queue('evaluate','{"kind":"homework"}')->'counts','{"evaluate":2,"finalize":1,"release":1,"released":0}'::jsonb,
  'the kind filter limits every stage count');
select is(public.get_evaluation_queue('evaluate',jsonb_build_object('learner_id',(select l2 from q)))->'counts',
  '{"evaluate":2,"finalize":1,"release":1,"released":0}'::jsonb,'the learner filter limits the queue to one learner');
select is(public.get_evaluation_queue('evaluate','{"coc_code":"coc2"}')->'counts','{"evaluate":1,"finalize":0,"release":1,"released":0}'::jsonb,
  'the COC filter uses the mission and homework curriculum links');
select is(public.get_evaluation_queue('evaluate',jsonb_build_object('module_id',(select lo11 from q)))->'counts',
  '{"evaluate":3,"finalize":2,"release":1,"released":1}'::jsonb,'the module filter uses mission and homework module links');
select is(public.get_evaluation_queue('evaluate',jsonb_build_object('class_id',(select c2 from q)))->'counts',
  '{"evaluate":0,"finalize":0,"release":0,"released":0}'::jsonb,'filtering by another instructor''s class returns nothing');
select ok((select jsonb_array_length(r->'items')=1 and (r->>'total')::integer=4 and (r->>'limit')::integer=1 and (r->>'offset')::integer=1
  and r->'items'->0->>'kind'='technical' from (select public.get_evaluation_queue('evaluate','{"limit":1,"offset":1}') r) s),
  'limit and offset page the stage while counts stay complete');
select is((public.get_evaluation_queue('evaluate','{}')->>'quiz_available')::boolean,
  to_regprocedure('public.quiz_evaluation_queue_items(text,jsonb)') is not null,
  'quiz availability reflects whether the quiz evaluation function is installed');

-- Validation.
select throws_ok($$select public.get_evaluation_queue('archive','{}')$$,'22023','EVALUATION_STAGE_INVALID','unknown stages are rejected');
select throws_ok($$select public.get_evaluation_queue('evaluate','{"class_id":"not-a-uuid"}')$$,'22023','EVALUATION_FILTERS_INVALID','malformed filters are rejected');
select throws_ok($$select public.get_evaluation_queue('evaluate','{"limit":101}')$$,'22023','EVALUATION_FILTERS_INVALID','pages hold at most 100 items');
select throws_ok($$select public.get_evaluation_queue('evaluate','{"kind":"essay"}')$$,'22023','EVALUATION_FILTERS_INVALID','unknown kinds are rejected');
reset role;

-- Instructor two and admin scopes; learners have no queue.
select set_config('request.jwt.claim.sub',(select t2::text from q),true);
set local role authenticated;
select is(public.get_evaluation_queue('evaluate','{}')->'counts','{"evaluate":2,"finalize":0,"release":0,"released":0}'::jsonb,
  'the second instructor sees only their own class');
select set_config('request.jwt.claim.sub',(select admin_user::text from q),true);
select is(public.get_evaluation_queue('evaluate','{}')->'counts'->'evaluate',
  ((select count(*) from public.attempts a join public.classes c on c.id=a.class_id where a.status='evaluated' and c.status='active')
   + (select count(*) from public.homework_submissions s join public.homework_assignments h on h.id=s.assignment_id
      join public.classes c on c.id=h.class_id where s.status='submitted' and c.status='active')
   -- Quiz attempts awaiting essay scores in active classes: like technical
   -- and homework items, the quiz action stages skip archived classes
   -- (20261120100100). This test's own quiz attempt is created below, so
   -- these are only attempts that already exist in the target database.
   + (select count(*) from public.quiz_attempts qa join public.quiz_versions qv on qv.id=qa.quiz_version_id
      join public.quizzes qu on qu.id=qv.quiz_id join public.classes c on c.id=qa.class_id
      where qa.evaluation_status='pending' and c.status='active'))::text::jsonb,
  'admins read every active class');
select set_config('request.jwt.claim.sub',(select l1::text from q),true);
select throws_ok($$select public.get_evaluation_queue('evaluate','{}')$$,'42501','STAFF_REQUIRED','learners cannot read the evaluation queue');
reset role;

-- Quiz essays through slice A3's real functions: an instructor-release quiz
-- with a scenario essay moves Evaluate -> Finalize -> Release -> Released.
create temporary table qz(quiz uuid, version uuid, objective uuid, essay uuid, assignment uuid, attempt uuid);
insert into qz default values;
grant all on qz to authenticated, service_role;
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
update qz set quiz=(public.create_instructor_quiz('Queue essay quiz','Assembly',p_coc_module_id=>(select coc1 from q),
  p_focus=>'Explain safe CPU installation',p_module_ids=>array[(select lo11 from q)])).id;
update qz set version=(select id from public.quiz_versions where quiz_id=qz.quiz);
update qz set objective=(public.upsert_quiz_item(version,'true_false','Thermal paste goes between the CPU and the cooler.','[]','"true"')).id;
update qz set essay=(public.upsert_quiz_item(version,'scenario_essay','Explain how you would install the processor safely.','[]','""',
  p_scenario=>'A client left an unassembled workstation on your bench with an anti-static mat.',
  p_rubric=>'[{"id":"C1","criterion":"Safety","description":"ESD precautions before handling","max_points":4},{"id":"C2","criterion":"Procedure","description":"Lever, alignment and seating","max_points":6}]')).id;
select public.review_quiz_item(id,'approved') from public.quiz_items where quiz_version_id=(select version from qz);
select public.publish_and_assign_quiz(version,array[(select c1 from q)]) from qz;
update qz set assignment=(select id from public.quiz_assignments where quiz_version_id=qz.version);
select set_config('request.jwt.claim.sub',(select l1::text from q),true);
update qz set attempt=(public.start_learner_quiz(assignment,gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(attempt,objective,'True') from qz;
select public.save_learner_quiz_answer(attempt,essay,'Ground yourself on the mat, lift the lever, align the triangle and lower the CPU.') from qz;
select public.submit_learner_quiz(attempt,gen_random_uuid()) from qz;

select set_config('request.jwt.claim.sub',(select t1::text from q),true);
select ok((public.get_evaluation_queue('evaluate','{}')->>'quiz_available')::boolean,'the queue reads quiz essays through slice A3''s function');
select is(public.get_evaluation_queue('evaluate','{}')->'counts','{"evaluate":5,"finalize":2,"release":2,"released":1}'::jsonb,
  'a submitted essay attempt is counted in Evaluate');
select is((select i from jsonb_array_elements(public.get_evaluation_queue('evaluate','{"kind":"quiz"}')->'items') i),
  public.quiz_evaluation_queue_items('evaluate','{}')->0,'quiz items pass through exactly as slice A3 builds them');
select is((select jsonb_agg(k order by k) from jsonb_object_keys(public.get_evaluation_queue('evaluate','{"kind":"quiz"}')->'items'->0) k),
  '["class", "id", "kind", "learner", "link", "max_score", "score", "status", "submitted_at", "title"]'::jsonb,
  'quiz items keep the documented Evaluation Center shape');
select is((select i->>'kind'||'|'||(i->>'title')||'|'||(i->>'status')||'|'||coalesce(i->>'score','null')||'|'||(i->>'max_score')||'|'||(i->'learner'->>'name')
    ||'|'||(i->'class'->>'title')||'|'||(i->>'link')
  from jsonb_array_elements(public.get_evaluation_queue('evaluate','{"kind":"quiz"}')->'items') i),
  'quiz|Queue essay quiz|pending|null|11|Queue Learner One|Queue class one|/quizzes/'||(select quiz from qz)||'?tab=results&attempt='||(select attempt from qz),
  'Evaluate lists the attempt awaiting essay scores, linked to the quiz results');
select is((select jsonb_agg(i->>'kind' order by ord) from jsonb_array_elements(public.get_evaluation_queue('evaluate','{}')->'items') with ordinality x(i,ord)),
  '["homework","technical","technical","homework","quiz"]'::jsonb,'quiz items are ordered with the others by submission time');
select is(public.get_evaluation_queue('evaluate','{"kind":"technical"}')->'counts'->'evaluate','2'::jsonb,'the kind filter excludes quiz items');
select is(public.get_evaluation_queue('evaluate','{"coc_code":"coc2"}')->'counts'->'evaluate','1'::jsonb,'the COC filter applies to quiz items');
select is(public.get_evaluation_queue('evaluate',jsonb_build_object('learner_id',(select l2 from q)))->'counts'->'evaluate','2'::jsonb,
  'the learner filter applies to quiz items');
select set_config('request.jwt.claim.sub',(select t2::text from q),true);
select is(public.get_evaluation_queue('evaluate','{"kind":"quiz"}')->'counts'->'evaluate','0'::jsonb,'another instructor sees none of the quiz items');
reset role;

-- Essay scoring stays on the quiz results page (A3); then Finalize per attempt and Release.
set local role service_role;
select public.manage_quiz_evaluation(t1,'score_essay',jsonb_build_object('attempt_id',(select attempt from qz),'item_id',(select essay from qz),
  'criterion_scores',jsonb_build_object('C1',3,'C2',5),'feedback','Good ESD steps.')) from q;
reset role;
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
select is((select i->>'status'||'|'||(i->>'score')||'/'||(i->>'max_score') from jsonb_array_elements(public.get_evaluation_queue('finalize','{"kind":"quiz"}')->'items') i),
  'evaluated|9/11','scored essays move the attempt to Finalize with objective plus essay points');
reset role;
set local role service_role;
select public.manage_quiz_evaluation(t1,'finalize',jsonb_build_object('attempt_id',(select attempt from qz))) from q;
reset role;
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
select is((select i->>'status'||'|'||(i->>'score')||'/'||(i->>'max_score') from jsonb_array_elements(public.get_evaluation_queue('release','{"kind":"quiz"}')->'items') i),
  'finalized|9/11','a finalized quiz result waits in Release with its final total');
reset role;
set local role service_role;
select public.manage_quiz_evaluation(t1,'release',jsonb_build_object('attempt_ids',jsonb_build_array((select attempt from qz)))) from q;
reset role;
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
select is((select i->>'status'||'|'||(i->>'id') from jsonb_array_elements(public.get_evaluation_queue('released','{"kind":"quiz"}')->'items') i),
  'released|'||(select attempt from qz),'a released quiz result appears in Released');
select is(public.get_evaluation_queue('evaluate','{}')->'counts','{"evaluate":4,"finalize":2,"release":2,"released":2}'::jsonb,
  'after release the quiz attempt is counted only in Released');

-- Archived classes (demo review m4, final review SQL-B M4): every kind leaves
-- the action stages while its class is archived and keeps its released
-- results; reactivating the class brings the work back.
select set_config('request.jwt.claim.sub',(select l2::text from q),true);
update qz set attempt=(public.start_learner_quiz(assignment,gen_random_uuid())->>'attempt_id')::uuid;
select public.save_learner_quiz_answer(attempt,objective,'True') from qz;
select public.save_learner_quiz_answer(attempt,essay,'Wear the strap, open the lever, match the triangle and close the lever.') from qz;
select public.submit_learner_quiz(attempt,gen_random_uuid()) from qz;
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
select is(public.get_evaluation_queue('evaluate','{"kind":"quiz"}')->'counts','{"evaluate":1,"finalize":0,"release":0,"released":1}'::jsonb,
  'a second essay attempt waits in Evaluate while its class is active');
reset role;
update public.classes set status='archived', archived_at=now(), archived_by=(select t1 from q), archive_reason='Rollback archive'
where id=(select c1 from q);
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
select is(public.get_evaluation_queue('evaluate','{}')->'counts','{"evaluate":0,"finalize":0,"release":0,"released":2}'::jsonb,
  'an archived class leaves every action stage for technical, homework and quiz items; its released results stay');
select is(jsonb_array_length(public.quiz_evaluation_queue_items('evaluate','{}'))::text
    ||'/'||jsonb_array_length(public.quiz_evaluation_queue_items('released','{}'))::text,
  '0/1','the quiz queue skips archived classes in Evaluate and still lists their released results');
reset role;
update public.classes set status='active', archived_at=null, archived_by=null, archive_reason=null where id=(select c1 from q);
select set_config('request.jwt.claim.sub',(select t1::text from q),true);
set local role authenticated;
select is(public.get_evaluation_queue('evaluate','{"kind":"quiz"}')->'counts'->'evaluate','1'::jsonb,
  'reactivating the class brings its quiz attempt back to Evaluate');
reset role;

select * from finish();
rollback;
