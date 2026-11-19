-- Slice A6 (Objective 2): server-awarded points, levels and achievements.
-- Every award comes from a real source record, exactly once, and is written
-- only by trusted server roles. Rollback-only: all fixtures are discarded.
begin;
select plan(65);

create temporary table gam_ctx (
  teacher uuid not null default gen_random_uuid(),
  other_teacher uuid not null default gen_random_uuid(),
  learner_a uuid not null default gen_random_uuid(),
  learner_b uuid not null default gen_random_uuid(),
  learner_c uuid not null default gen_random_uuid(),
  learner_d uuid not null default gen_random_uuid(),
  class_a uuid not null default gen_random_uuid(),
  action_id bigint,
  topic_a uuid not null default gen_random_uuid(),
  topic_b uuid not null default gen_random_uuid(),
  topic_c uuid not null default gen_random_uuid(),
  practice_quiz_a uuid not null default gen_random_uuid(),
  practice_quiz_c uuid not null default gen_random_uuid(),
  quiz uuid not null default gen_random_uuid(),
  quiz_version uuid not null default gen_random_uuid(),
  quiz_assignment uuid not null default gen_random_uuid(),
  quiz_attempt_a uuid not null default gen_random_uuid(),
  quiz_attempt_b uuid not null default gen_random_uuid(),
  quiz_attempt_c uuid not null default gen_random_uuid(),
  homework_open uuid not null default gen_random_uuid(),
  homework_closed uuid not null default gen_random_uuid(),
  source_id uuid,
  module_version uuid,
  activity_version uuid,
  rubric_version uuid,
  assignment uuid,
  attempt_a uuid not null default gen_random_uuid(),
  attempt_c uuid not null default gen_random_uuid(),
  revision_a uuid,
  revision_c uuid
);
insert into gam_ctx default values;
grant select on gam_ctx to authenticated, service_role;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@gamification-rollback.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', name), now(), now()
from gam_ctx cross join lateral (values
  (teacher, 'Gamification Teacher'), (other_teacher, 'Other Teacher'),
  (learner_a, 'Ana Reyes'), (learner_b, 'Ben Santos'), (learner_c, 'Carla Mendoza'), (learner_d, 'Dan Lopez')) t(id, name);
update public.profiles set role = 'instructor'
where user_id in (select teacher from gam_ctx union all select other_teacher from gam_ctx);

insert into public.classes(id, title, class_code, instructor_id, created_by)
select class_a, 'Gamification rollback class', left(class_a::text, 12), teacher, teacher from gam_ctx;
insert into public.class_memberships(class_id, learner_id, enrolled_by)
select class_a, l, teacher from gam_ctx cross join lateral (values (learner_a), (learner_b), (learner_c)) m(l);

with inserted as (
  insert into public.practice_mission_actions (learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
  select learner_a, 'gamification-rollback', 'coc1_m1', 'inspect', 'object_inspected', 'case', '{}'::jsonb, now() from gam_ctx
  returning id)
update gam_ctx set action_id = (select id from inserted);

-- ---------------------------------------------------------------------------
-- Approved configuration
-- ---------------------------------------------------------------------------
select is(
  (select string_agg(format('%s=%s|%s|%s', event_type, points, label, active::text), ', ' order by sort_order)
   from public.gamification_point_rules),
  'practice_mission_verified=50|Practice mission verified|true, topic_completed=10|Topic completed|true, '
  || 'module_completed=100|Module completed|true, coc_completed=300|COC completed|true, '
  || 'quiz_submitted=20|Quiz submitted|true, homework_submitted_on_time=15|Homework submitted on time|true, '
  || 'assessment_released=40|Assessment result released|true',
  'point rules carry the approved values');
select is(
  (select string_agg(format('%s:%s:%s', level, min_points, title), ', ' order by level) from public.gamification_levels),
  '1:0:Trainee, 2:100:Apprentice, 3:300:Junior Technician, 4:600:Technician, 5:1000:Senior Technician, 6:1500:Lead Technician',
  'levels carry the approved thresholds');
select is(
  (select string_agg(achievement_code, ',' order by sort_order) from public.achievements where rule is not null),
  'first_mission,assembly_ready,five_missions,ten_missions,first_module,coc1_complete,coc2_complete,coc3_complete,coc4_complete,quiz_taker,on_time,first_release',
  'twelve real-event achievements are configured in display order');
select is((select rule from public.achievements where achievement_code = 'first_mission'),
  '{"type":"count","event_type":"practice_mission_verified","min":1}'::jsonb, 'first_mission counts one verified practice mission');
select is((select rule from public.achievements where achievement_code = 'assembly_ready'),
  '{"type":"source","event_type":"practice_mission_verified","source_id":"coc1_m2"}'::jsonb, 'assembly_ready requires COC1 M2');
select ok(not exists (select 1 from public.achievements a where a.rule is not null and (
    a.icon is null or nullif(btrim(a.description), '') is null
    or not exists (select 1 from public.gamification_point_rules r where r.event_type = a.rule->>'event_type'))),
  'every achievement has an icon, an earning description and a configured event type');

-- ---------------------------------------------------------------------------
-- Privileges, RLS and definer surface
-- ---------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'public.learner_point_events', 'INSERT, UPDATE, DELETE, TRUNCATE'),
  'clients cannot write point events');
select ok(not has_table_privilege('authenticated', 'public.user_achievements', 'INSERT, UPDATE, DELETE, TRUNCATE'),
  'clients cannot write earned achievements');
select ok(not has_table_privilege('authenticated', 'public.learner_achievements', 'INSERT, UPDATE, DELETE, TRUNCATE'),
  'the learner_achievements view is read-only');
select ok(not has_table_privilege('authenticated', 'public.gamification_point_rules', 'INSERT, UPDATE, DELETE, TRUNCATE')
  and not has_table_privilege('authenticated', 'public.gamification_levels', 'INSERT, UPDATE, DELETE, TRUNCATE'),
  'clients cannot change rules or levels');
select ok(not has_table_privilege('anon', 'public.learner_point_events', 'SELECT')
  and not has_table_privilege('anon', 'public.gamification_point_rules', 'SELECT')
  and not has_table_privilege('anon', 'public.learner_achievements', 'SELECT'),
  'anonymous users read no gamification data');
select ok((select bool_and(relrowsecurity) from pg_class where oid in (
    'public.gamification_point_rules'::regclass, 'public.learner_point_events'::regclass, 'public.gamification_levels'::regclass)),
  'RLS is enabled on the new gamification tables');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.proname like '%gamification%' and p.prosecdef
    and p.proname <> 'prevent_gamification_event_mutation'), 0,
  'gamification adds no SECURITY DEFINER function');
select ok(not has_function_privilege('authenticated', 'private.gamification_award(uuid,text,text,timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.gamification_backfill()', 'EXECUTE'),
  'clients cannot call the award or backfill functions');

-- ---------------------------------------------------------------------------
-- Verified practice missions (service-role verifier writes)
-- ---------------------------------------------------------------------------
set local role service_role;
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_a, 'coc1_m1', 'rollback', action_id, '2026-01-01 08:00:00+00' from gam_ctx;
-- Re-verification uses the verifier's upsert; it must never re-award.
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_a, 'coc1_m1', 'rollback-2', action_id, '2026-01-01 09:00:00+00' from gam_ctx
on conflict (learner_id, mission_id) do update
  set contract_version = excluded.contract_version, verified_at = excluded.verified_at;
select is(private.gamification_award((select learner_a from gam_ctx), 'practice_mission_verified', 'coc1_m1', now()), false,
  'repeating an already awarded event is a no-op');
reset role;

select is((select count(*)::integer from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a
  where e.event_type = 'practice_mission_verified'), 1,
  'a verified practice mission awards once and re-verification does not re-award');
select is((select format('%s|%s|%s', e.points, e.awarded_at, e.detail) from public.learner_point_events e join gam_ctx c
  on e.learner_id = c.learner_a where e.source_id = 'coc1_m1'),
  format('50|%s|%s', '2026-01-01 08:00:00+00'::timestamptz, (select title from public.missions where mission_code = 'coc1_m1')),
  'the award carries 50 points, the first verification time and the mission title');
select ok(exists (select 1 from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_a
  where la.code = 'first_mission'), 'the first verified mission earns first_mission');

set local role service_role;
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_a, 'coc1_m' || n, 'rollback', action_id, '2026-01-01 08:00:00+00'::timestamptz + make_interval(days => n - 1)
from gam_ctx cross join generate_series(2, 4) n;
reset role;
select ok(exists (select 1 from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_a
  where la.code = 'assembly_ready'), 'verifying COC1 M2 earns assembly_ready');
select ok(not exists (select 1 from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_a
  where la.code = 'five_missions'), 'four verified missions do not earn five_missions');

set local role service_role;
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_a, 'coc1_m5', 'rollback', action_id, '2026-01-05 08:00:00+00' from gam_ctx;
reset role;
select is((select la.earned_at from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_a
  where la.code = 'five_missions'), '2026-01-05 08:00:00+00'::timestamptz,
  'five_missions is earned at the time of the fifth verification');
select ok(not exists (select 1 from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_a
  where la.code = 'ten_missions'), 'ten_missions stays locked');

-- ---------------------------------------------------------------------------
-- Topics, modules and COCs (service-role progression writes)
-- ---------------------------------------------------------------------------
insert into public.curriculum_topics (id, module_id, sequence_order)
select t, (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1'), 900 + n
from gam_ctx cross join lateral (values (topic_a, 1), (topic_b, 2), (topic_c, 3)) v(t, n);
insert into public.curriculum_topic_revisions (topic_id, revision_number, title, body_markdown, status)
select topic_a, 1, 'Rollback ESD precautions', 'Wear the wrist strap.', 'published' from gam_ctx;

set local role service_role;
insert into public.learner_topic_progress (learner_id, topic_id, completed_at)
select learner_a, topic_a, '2026-02-01 08:00:00+00' from gam_ctx;
insert into public.learner_topic_progress (learner_id, topic_id) select learner_a, topic_a from gam_ctx on conflict do nothing;
insert into public.learner_module_completions (learner_id, module_id, completed_at)
select learner_a, (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1'), '2026-02-02 08:00:00+00' from gam_ctx;
reset role;
insert into public.practice_quiz_attempts (id, learner_id, coc_code, status, questions, answers, score, passed, submitted_at)
select practice_quiz_a, learner_a, 'coc1', 'submitted', '[1,2,3,4,5]'::jsonb, '{}'::jsonb, 5, true, now() from gam_ctx;
set local role service_role;
insert into public.practice_coc_progress (learner_id, coc_code, quiz_attempt_id, completed_at)
select learner_a, 'coc1', practice_quiz_a, '2026-02-03 08:00:00+00' from gam_ctx;
insert into public.practice_coc_progress (learner_id, coc_code, quiz_attempt_id)
select learner_a, 'coc1', practice_quiz_a from gam_ctx on conflict do nothing;
reset role;

select is((select string_agg(format('%s:%s', e.event_type, e.points), ',' order by e.event_type)
  from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a
  where e.event_type in ('topic_completed', 'module_completed', 'coc_completed')),
  'coc_completed:300,module_completed:100,topic_completed:10',
  'topic, module and COC completions each award their configured points once');
select is((select detail from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a
  where e.event_type = 'topic_completed'), 'Rollback ESD precautions', 'topic points record the published topic title');
select is((select detail from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a
  where e.event_type = 'module_completed'), 'LO1.1 Assemble computer hardware', 'module points record the official module');
select is((select string_agg(la.code, ',' order by la.code) from public.learner_achievements la join gam_ctx c
  on la.learner_id = c.learner_a where la.code in ('first_module', 'coc1_complete', 'coc2_complete')),
  'coc1_complete,first_module', 'module and COC milestones earn only their own achievements');

-- ---------------------------------------------------------------------------
-- Quizzes (definer RPC writes run as the function owner)
-- ---------------------------------------------------------------------------
insert into public.quizzes (id, instructor_id, title, topic, created_by)
select quiz, teacher, 'Rollback networking quiz', 'Networking', teacher from gam_ctx;
insert into public.quiz_versions (id, quiz_id, version_number, status, created_by, published_by, published_at)
select quiz_version, quiz, 1, 'published', teacher, teacher, now() from gam_ctx;
insert into public.quiz_assignments (id, class_id, quiz_version_id, assigned_by)
select quiz_assignment, class_a, quiz_version, teacher from gam_ctx;
insert into public.quiz_attempts (id, learner_id, class_id, quiz_assignment_id, quiz_version_id, client_start_key)
select quiz_attempt_a, learner_a, class_a, quiz_assignment, quiz_version, gen_random_uuid() from gam_ctx;
select is((select count(*)::integer from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a
  where e.event_type = 'quiz_submitted'), 0, 'an in-progress quiz attempt earns nothing');
update public.quiz_attempts set status = 'submitted', submission_key = gen_random_uuid(), submitted_at = '2026-02-04 08:00:00+00'
where id = (select quiz_attempt_a from gam_ctx);
update public.quiz_attempts set status = 'completed', completed_at = '2026-02-04 08:01:00+00'
where id = (select quiz_attempt_a from gam_ctx);
select is((select format('%s|%s|%s|%s', count(*), max(e.points), max(e.awarded_at), max(e.detail))
  from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a and e.source_id = c.quiz_attempt_a::text
  where e.event_type = 'quiz_submitted'),
  format('1|20|%s|Rollback networking quiz', '2026-02-04 08:00:00+00'::timestamptz),
  'a submitted quiz awards 20 points once even after it is completed');

-- ---------------------------------------------------------------------------
-- Homework (service-role writes; only zero lateness earns points)
-- ---------------------------------------------------------------------------
insert into public.homework_assignments (id, class_id, instructor_id, title, instructions, status, deadline_at, published_at)
select homework_open, class_a, teacher, 'Rollback cabling report', 'Describe the cable test.', 'published', '2035-01-01 00:00:00+00'::timestamptz, now() from gam_ctx
union all
select homework_closed, class_a, teacher, 'Rollback topology report', 'Describe the topology.', 'published', '2026-01-01 00:00:00+00'::timestamptz, now() from gam_ctx;
set local role service_role;
insert into public.homework_submissions (assignment_id, learner_id, answer, submitted_at, effective_deadline_at, deadline_revision)
select homework_open, learner_a, 'On time.', '2026-02-05 08:00:00+00'::timestamptz, '2035-01-01 00:00:00+00'::timestamptz, 1 from gam_ctx
union all
select homework_closed, learner_a, 'Late.', '2026-02-05 08:00:00+00'::timestamptz, '2026-01-01 00:00:00+00'::timestamptz, 1 from gam_ctx;
reset role;
select is((select format('%s|%s', count(*), max(e.detail)) from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a
  where e.event_type = 'homework_submitted_on_time'), '1|Rollback cabling report',
  'only the on-time homework submission earns points');

-- ---------------------------------------------------------------------------
-- Released assessments (definer release writes run as the function owner)
-- ---------------------------------------------------------------------------
with inserted as (
  insert into public.tesda_sources (qualification_code, title, edition, source_reference, status, validation_notes,
    created_by, approved_by, approved_at, activated_by, activated_at)
  select 'ROLLBACK-GAM-' || left(gen_random_uuid()::text, 8), 'Rollback-only gamification source', 'TEST_ONLY',
    'Rollback fixture; never a production TESDA source', 'active', 'TEST_ONLY_ROLLBACK_FIXTURE',
    teacher, teacher, now(), teacher, now() from gam_ctx
  returning id)
update gam_ctx set source_id = (select id from inserted);
with inserted as (
  insert into public.module_versions (module_id, tesda_source_id, version_number, title, source_trace, status, created_by, published_by, published_at)
  select m.id, c.source_id, coalesce((select max(version_number) from public.module_versions mv where mv.module_id = m.id), 0) + 1,
    'Rollback gamification module', '{"status":"TEST_ONLY"}'::jsonb, 'published', c.teacher, c.teacher, now()
  from gam_ctx c cross join public.coc_modules m where m.coc_code = 'coc1'
  returning id)
update gam_ctx set module_version = (select id from inserted);
with inserted as (
  insert into public.activity_versions (mission_id, module_version_id, version_number, title, delivery_mode, learner_payload,
    evaluator_config, status, created_by, published_by, published_at)
  select m.id, c.module_version, coalesce((select max(version_number) from public.activity_versions av where av.mission_id = m.id), 0) + 1,
    'Rollback assembly assessment', 'assessment', '{"status":"TEST_ONLY"}'::jsonb, '{"status":"TEST_ONLY"}'::jsonb,
    'published', c.teacher, c.teacher, now()
  from gam_ctx c cross join public.missions m where m.mission_code = 'coc1_m2'
  returning id)
update gam_ctx set activity_version = (select id from inserted);
with inserted as (
  insert into public.rubric_versions (activity_version_id, tesda_source_id, version_number, title, status, scoring_method,
    passing_rule, created_by, approved_by, approved_at)
  select activity_version, source_id, 1, 'Rollback rubric', 'approved', 'binary_sum',
    '{"status":"APPROVED","method":"all_required"}'::jsonb, teacher, teacher, now() from gam_ctx
  returning id)
update gam_ctx set rubric_version = (select id from inserted);
with inserted as (
  insert into public.assignments (class_id, activity_version_id, rubric_version_id, assignment_type, title, assigned_by)
  select class_a, activity_version, rubric_version, 'assessment', 'Rollback assembly assessment', teacher from gam_ctx
  returning id)
update gam_ctx set assignment = (select id from inserted);
insert into public.attempts (id, learner_id, class_id, assignment_id, activity_version_id, rubric_version_id, tesda_source_id,
  status, client_start_key, submission_key, submitted_at)
select a, l, class_a, assignment, activity_version, rubric_version, source_id, 'finalized', gen_random_uuid(), gen_random_uuid(), now()
from gam_ctx cross join lateral (values (attempt_a, learner_a), (attempt_c, learner_c)) v(a, l);
with inserted as (
  insert into public.score_revisions (attempt_id, revision_number, revision_type, tesda_source_id, rubric_version_id, outcome)
  select attempt_a, 1, 'automated_provisional', source_id, rubric_version, 'competent' from gam_ctx
  returning id)
update gam_ctx set revision_a = (select id from inserted);
insert into public.result_releases (attempt_id, score_revision_id, release_number, released_by, released_at)
select attempt_a, revision_a, 1, teacher, '2026-02-06 08:00:00+00' from gam_ctx;
update public.result_releases set is_current = false, revoked_by = (select teacher from gam_ctx), revoked_at = now(),
  revocation_reason = 'Rollback re-release check'
where attempt_id = (select attempt_a from gam_ctx);
insert into public.result_releases (attempt_id, score_revision_id, release_number, released_by)
select attempt_a, revision_a, 2, teacher from gam_ctx;
select is((select format('%s|%s|%s', count(*), max(e.points), max(e.detail)) from public.learner_point_events e
  join gam_ctx c on e.learner_id = c.learner_a and e.source_id = c.attempt_a::text
  where e.event_type = 'assessment_released'), '1|40|Rollback assembly assessment',
  'a released assessment awards 40 points once and a re-release does not re-award');
select ok(exists (select 1 from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_a
  where la.code = 'first_release'), 'the first released assessment earns first_release');

-- ---------------------------------------------------------------------------
-- Totals and levels
-- ---------------------------------------------------------------------------
select is((select sum(e.points)::integer from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_a), 735,
  'the learner total is the sum of eleven real awards');
select is(public.gamification_level_for_points(735),
  '{"level":4,"title":"Technician","min_points":600,"next_level":5,"next_min_points":1000,"progress_percent":33}'::jsonb,
  '735 points is level 4 Technician, a third of the way to level 5');
select is(public.gamification_level_for_points(0)->>'title', 'Trainee', 'zero points is Trainee');
select is(public.gamification_level_for_points(99),
  '{"level":1,"title":"Trainee","min_points":0,"next_level":2,"next_min_points":100,"progress_percent":99}'::jsonb,
  '99 points stays at level 1');
select is(public.gamification_level_for_points(100)->>'title', 'Apprentice', 'exactly 100 points reaches Apprentice');
select is(public.gamification_level_for_points(1500),
  '{"level":6,"title":"Lead Technician","min_points":1500,"next_level":null,"next_min_points":null,"progress_percent":100}'::jsonb,
  'the top level has no next level');
select is(public.gamification_level_for_points(-5)->>'level', '1', 'negative input is treated as zero points');

-- ---------------------------------------------------------------------------
-- Integrity: append-only history and rule-enforced point values
-- ---------------------------------------------------------------------------
select throws_ok($$update public.learner_point_events set points = 1$$, '55000', null, 'point events are append-only');
select throws_ok($$delete from public.learner_point_events$$, '55000', null, 'point events cannot be deleted');
select throws_ok($$delete from public.user_achievements$$, '55000', null, 'earned achievements are append-only');
set local role service_role;
insert into public.learner_point_events (learner_id, event_type, source_id, points)
select learner_b, 'topic_completed', 'direct-service-insert', 999 from gam_ctx;
reset role;
select is((select points from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_b
  where e.source_id = 'direct-service-insert'), 10, 'stored points always equal the configured rule value');

-- ---------------------------------------------------------------------------
-- Client access: learners read only their own records and cannot self-award
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', (select learner_a::text from gam_ctx), true);
set local role authenticated;
select throws_ok(format($$insert into public.learner_point_events (learner_id, event_type, source_id, points) values (%L, 'topic_completed', 'self-award', 10)$$,
  (select learner_a from gam_ctx)), '42501', null, 'a learner cannot award points to themselves');
select throws_ok(format($$insert into public.user_achievements (user_id, achievement_id) select %L, id from public.achievements where achievement_code = 'ten_missions'$$,
  (select learner_a from gam_ctx)), '42501', null, 'a learner cannot grant themselves an achievement');
select throws_ok($$update public.gamification_point_rules set points = 1000$$, '42501', null, 'a learner cannot change point rules');
select is((select count(*)::integer from public.learner_point_events), 11, 'a learner reads exactly their own eleven point events');
select is((select string_agg(code, ',' order by code) from public.learner_achievements),
  'assembly_ready,coc1_complete,first_mission,first_module,first_release,five_missions',
  'a learner reads exactly their own earned achievements');
select is((select count(*)::integer from public.gamification_point_rules) + (select count(*)::integer from public.gamification_levels), 13,
  'learners can read the point rules and levels');
select set_config('request.jwt.claim.sub', (select learner_b::text from gam_ctx), true);
select is((select count(*)::integer from public.learner_point_events where learner_id <> auth.uid()), 0,
  'a classmate cannot read another learner''s point events');
select set_config('request.jwt.claim.sub', (select teacher::text from gam_ctx), true);
select is((select count(*)::integer from public.learner_point_events where learner_id = (select learner_a from gam_ctx)), 11,
  'the class instructor reads learner points for analytics');
select set_config('request.jwt.claim.sub', (select other_teacher::text from gam_ctx), true);
select is((select count(*)::integer from public.learner_point_events), 0, 'an unrelated instructor reads no learner points');
reset role;

-- ---------------------------------------------------------------------------
-- Backfill: records that existed before installation are awarded once with
-- their original timestamps; re-running awards nothing new.
-- ---------------------------------------------------------------------------
alter table public.practice_mission_completions disable trigger trg_practice_mission_completions_award_points;
alter table public.learner_topic_progress disable trigger trg_learner_topic_progress_award_points;
alter table public.learner_module_completions disable trigger trg_learner_module_completions_award_points;
alter table public.practice_coc_progress disable trigger trg_practice_coc_progress_award_points;
alter table public.quiz_attempts disable trigger trg_quiz_attempts_award_points;
alter table public.homework_submissions disable trigger trg_homework_submissions_award_points;
alter table public.result_releases disable trigger trg_result_releases_award_points;

insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_c, 'coc1_m' || n, 'legacy', action_id, '2026-03-01 08:00:00+00'::timestamptz + make_interval(days => n - 1)
from gam_ctx cross join generate_series(1, 3) n;
insert into public.learner_topic_progress (learner_id, topic_id, completed_at) select learner_c, topic_b, '2026-03-05 08:00:00+00' from gam_ctx;
insert into public.learner_module_completions (learner_id, module_id, completed_at)
select learner_c, (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.2'), '2026-03-06 08:00:00+00' from gam_ctx;
insert into public.practice_quiz_attempts (id, learner_id, coc_code, status, questions, answers, score, passed, submitted_at)
select practice_quiz_c, learner_c, 'coc1', 'submitted', '[1,2,3,4,5]'::jsonb, '{}'::jsonb, 5, true, now() from gam_ctx;
insert into public.practice_coc_progress (learner_id, coc_code, quiz_attempt_id, completed_at)
select learner_c, 'coc1', practice_quiz_c, '2026-03-07 08:00:00+00' from gam_ctx;
insert into public.quiz_attempts (id, learner_id, class_id, quiz_assignment_id, quiz_version_id, client_start_key, status,
  submission_key, submitted_at)
select quiz_attempt_c, learner_c, class_a, quiz_assignment, quiz_version, gen_random_uuid(), 'submitted', gen_random_uuid(),
  '2026-03-08 08:00:00+00' from gam_ctx;
insert into public.homework_submissions (assignment_id, learner_id, answer, submitted_at, effective_deadline_at, deadline_revision)
select homework_open, learner_c, 'On time.', '2026-03-09 08:00:00+00'::timestamptz, '2035-01-01 00:00:00+00'::timestamptz, 1 from gam_ctx
union all
select homework_closed, learner_c, 'Late.', '2026-03-09 08:00:00+00'::timestamptz, '2026-01-01 00:00:00+00'::timestamptz, 1 from gam_ctx;
with inserted as (
  insert into public.score_revisions (attempt_id, revision_number, revision_type, tesda_source_id, rubric_version_id, outcome)
  select attempt_c, 1, 'automated_provisional', source_id, rubric_version, 'not_yet_competent' from gam_ctx
  returning id)
update gam_ctx set revision_c = (select id from inserted);
insert into public.result_releases (attempt_id, score_revision_id, release_number, released_by, released_at)
select attempt_c, revision_c, 1, teacher, '2026-03-10 08:00:00+00' from gam_ctx;

select is((select count(*)::integer from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_c), 0,
  'records created before installation have no points yet');
select private.gamification_backfill();
select is(
  (select jsonb_object_agg(event_type, n) from (select e.event_type, count(*)::integer n from public.learner_point_events e
    join gam_ctx c on e.learner_id = c.learner_c group by e.event_type) s),
  (select jsonb_build_object(
    'practice_mission_verified', (select count(*) from public.practice_mission_completions where learner_id = c.learner_c),
    'topic_completed', (select count(*) from public.learner_topic_progress where learner_id = c.learner_c),
    'module_completed', (select count(*) from public.learner_module_completions where learner_id = c.learner_c),
    'coc_completed', (select count(*) from public.practice_coc_progress where learner_id = c.learner_c),
    'quiz_submitted', (select count(*) from public.quiz_attempts where learner_id = c.learner_c and status::text in ('submitted', 'completed')),
    'homework_submitted_on_time', (select count(*) from public.homework_submissions where learner_id = c.learner_c and lateness_seconds = 0),
    'assessment_released', (select count(distinct rr.attempt_id) from public.result_releases rr join public.attempts a on a.id = rr.attempt_id
      where a.learner_id = c.learner_c)) from gam_ctx c),
  'backfill awards exactly one event per qualifying source record');
select is((select sum(e.points)::integer from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_c), 635,
  'backfilled total equals the configured points of the source records');
select is((select e.awarded_at from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_c
  where e.source_id = 'coc1_m1'), '2026-03-01 08:00:00+00'::timestamptz, 'backfill keeps the original verification time');
select is((select string_agg(format('%s@%s', la.code, to_char(la.earned_at at time zone 'UTC', 'MM-DD')), ',' order by la.code)
  from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_c),
  'assembly_ready@03-02,coc1_complete@03-07,first_mission@03-01,first_module@03-06,first_release@03-10',
  'backfilled achievements keep the time each rule became true');
select private.gamification_backfill();
select is((select count(*)::integer from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_c), 9,
  'running the backfill again awards nothing new');

alter table public.practice_mission_completions enable trigger trg_practice_mission_completions_award_points;
alter table public.learner_topic_progress enable trigger trg_learner_topic_progress_award_points;
alter table public.learner_module_completions enable trigger trg_learner_module_completions_award_points;
alter table public.practice_coc_progress enable trigger trg_practice_coc_progress_award_points;
alter table public.quiz_attempts enable trigger trg_quiz_attempts_award_points;
alter table public.homework_submissions enable trigger trg_homework_submissions_award_points;
alter table public.result_releases enable trigger trg_result_releases_award_points;

-- ---------------------------------------------------------------------------
-- Inactive rules award nothing
-- ---------------------------------------------------------------------------
update public.gamification_point_rules set active = false where event_type = 'quiz_submitted';
insert into public.quiz_attempts (id, learner_id, class_id, quiz_assignment_id, quiz_version_id, client_start_key)
select quiz_attempt_b, learner_b, class_a, quiz_assignment, quiz_version, gen_random_uuid() from gam_ctx;
update public.quiz_attempts set status = 'submitted', submission_key = gen_random_uuid(), submitted_at = now()
where id = (select quiz_attempt_b from gam_ctx);
set local role service_role;
insert into public.learner_topic_progress (learner_id, topic_id) select learner_b, topic_c from gam_ctx;
update public.gamification_point_rules set active = false where event_type = 'topic_completed';
insert into public.learner_topic_progress (learner_id, topic_id) select learner_b, topic_b from gam_ctx;
reset role;
select is((select string_agg(format('%s:%s', e.event_type, (e.source_id = c.topic_c::text)::text), ',' order by e.event_type, e.source_id)
  from public.learner_point_events e join gam_ctx c on e.learner_id = c.learner_b
  where e.source_id <> 'direct-service-insert'),
  'topic_completed:true', 'an inactive rule awards nothing while active rules keep awarding');

-- ---------------------------------------------------------------------------
-- Fail open: a gamification fault never blocks the learning record that fired
-- it. A failed award rolls back as a unit (no partial point row) and the
-- backfill repairs it later, still exactly once.
-- ---------------------------------------------------------------------------
-- Achievement evaluation fails: the record and its points commit, the
-- achievement waits for repair.
alter table public.user_achievements add constraint gamification_test_block_achievements check (false) not valid;
set local role service_role;
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_d, 'coc2_m2', 'fail-open', action_id, '2026-05-01 08:00:00+00' from gam_ctx;
reset role;
select is((select format('%s|%s|%s',
    (select count(*) from public.practice_mission_completions where learner_id = c.learner_d and mission_id = 'coc2_m2'),
    (select count(*) from public.learner_point_events where learner_id = c.learner_d and source_id = 'coc2_m2'),
    (select count(*) from public.user_achievements where user_id = c.learner_d)) from gam_ctx c),
  '1|1|0', 'when achievements cannot be evaluated the mission and its points commit and the achievement waits');
alter table public.user_achievements drop constraint gamification_test_block_achievements;
select is((private.gamification_backfill()->>'achievements')::integer, 1, 'the backfill re-evaluates the deferred achievement');
select is((select la.earned_at from public.learner_achievements la join gam_ctx c on la.learner_id = c.learner_d
  where la.code = 'first_mission'), '2026-05-01 08:00:00+00'::timestamptz,
  'the repaired achievement keeps the time its rule became true');

-- The award itself fails (a constraint, then missing table access): the record
-- commits and no point row is left behind.
alter table public.learner_point_events add constraint gamification_test_block_points check (source_id <> 'coc2_m1');
set local role service_role;
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_d, 'coc2_m1', 'fail-open', action_id, '2026-05-02 08:00:00+00' from gam_ctx;
reset role;
select is((select format('%s|%s',
    (select count(*) from public.practice_mission_completions where learner_id = c.learner_d and mission_id = 'coc2_m1'),
    (select count(*) from public.learner_point_events where learner_id = c.learner_d and source_id = 'coc2_m1')) from gam_ctx c),
  '1|0', 'a failed award never blocks the verified mission and leaves no partial point row');
revoke select on public.gamification_point_rules from service_role;
set local role service_role;
insert into public.learner_module_completions (learner_id, module_id, completed_at)
select learner_d, (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.3'), '2026-05-03 08:00:00+00'
from gam_ctx;
reset role;
grant select on public.gamification_point_rules to service_role;
select is((select format('%s|%s',
    (select count(*) from public.learner_module_completions where learner_id = c.learner_d),
    (select count(*) from public.learner_point_events where learner_id = c.learner_d and event_type = 'module_completed')) from gam_ctx c),
  '1|0', 'a writer without access to the rules still records the module completion');

-- The backfill is fail open per record and repairs every missed award once.
select is(private.gamification_backfill()->>'skipped', '1',
  'the backfill skips a still-failing record with a warning instead of aborting');
alter table public.learner_point_events drop constraint gamification_test_block_points;
select private.gamification_backfill();
select private.gamification_backfill();
select is((select format('%s|%s|%s',
    (select string_agg(e.source_id, ',' order by e.awarded_at) from public.learner_point_events e
      where e.learner_id = c.learner_d and e.event_type = 'practice_mission_verified'),
    (select count(*) from public.learner_point_events e where e.learner_id = c.learner_d),
    (select string_agg(la.code, ',' order by la.code) from public.learner_achievements la where la.learner_id = c.learner_d))
  from gam_ctx c),
  'coc2_m2,coc2_m1|3|first_mission,first_module', 'repaired awards and achievements are recorded exactly once');

select * from finish();
rollback;
