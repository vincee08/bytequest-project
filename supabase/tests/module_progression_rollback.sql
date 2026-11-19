-- Sequential module unlocking (re-defense slice A2.1). Rollback-only.
-- Covers the backend unlock rule used by the practice evidence gate, the
-- unlock/completion refresh triggers, the cutover backfill, bypass scope and
-- the COC practice quiz guard.
begin;
select plan(42);

-- Isolate the required items from lessons published in the target database
-- (rolled back with everything else): the fixtures below define the only
-- curriculum topics.
update public.curriculum_topics set archived_at = now() where archived_at is null;

-- ---------------------------------------------------------------------------
-- Fixture helpers (temporary, rolled back with the transaction)
-- ---------------------------------------------------------------------------
create function pg_temp.a2_learner(p_tag text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users(instance_id, id, aud, role, email, encrypted_password,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000'::uuid, v_id, 'authenticated', 'authenticated',
    'a2-' || p_tag || '-' || v_id || '@bytequest.invalid', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', 'A2 ' || p_tag), now(), now());
  return v_id;
end $$;

create function pg_temp.a2_action(p_learner uuid, p_mission text) returns bigint language sql as $$
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  values (p_learner, 'a2-' || gen_random_uuid(), p_mission, p_mission || '_p1',
    'object_inspected', 'fixture', '{}'::jsonb, clock_timestamp())
  returning id
$$;

create function pg_temp.a2_complete(p_learner uuid, p_mission text) returns void language sql as $$
  insert into public.practice_mission_completions(learner_id, mission_id, contract_version, evidence_through_id)
  select p_learner, c.mission_id, c.version, pg_temp.a2_action(p_learner, p_mission)
  from public.practice_mission_contracts c where c.mission_id = p_mission
$$;

create function pg_temp.a2_module(p_coc text, p_code text) returns uuid language sql stable as $$
  select id from public.curriculum_modules where coc_code = p_coc and code = p_code
$$;

-- Publishes a topic directly (the publication workflow has its own suite).
create function pg_temp.a2_topic(p_coc text, p_code text, p_title text) returns uuid language plpgsql as $$
declare v_topic uuid := gen_random_uuid();
begin
  insert into public.curriculum_topics(id, module_id, sequence_order)
  values (v_topic, pg_temp.a2_module(p_coc, p_code),
    1 + (select count(*) from public.curriculum_topics where module_id = pg_temp.a2_module(p_coc, p_code)));
  insert into public.curriculum_topic_revisions(topic_id, revision_number, title, body_markdown, status, published_at)
  values (v_topic, 1, p_title, 'Fixture lesson body.', 'published', now());
  return v_topic;
end $$;

create function pg_temp.a2_quiz_pass(p_learner uuid, p_coc text) returns void language plpgsql as $$
declare v_attempt uuid := gen_random_uuid();
begin
  insert into public.practice_quiz_attempts(id, learner_id, coc_code, status, questions, answers, score, passed, submitted_at)
  values (v_attempt, p_learner, p_coc, 'submitted',
    '[{"id":"q1","answer":0},{"id":"q2","answer":0},{"id":"q3","answer":0},{"id":"q4","answer":0},{"id":"q5","answer":0}]'::jsonb,
    '{"q1":0,"q2":0,"q3":0,"q4":0,"q5":0}'::jsonb, 5, true, now());
  insert into public.practice_coc_progress(learner_id, coc_code, quiz_attempt_id) values (p_learner, p_coc, v_attempt);
end $$;

create temporary table a2_ctx (key text primary key, id uuid);
grant select on a2_ctx to authenticated, service_role;
insert into a2_ctx values
  ('new', pg_temp.a2_learner('new')),
  ('legacy_completion', pg_temp.a2_learner('legacy-completion')),
  ('legacy_actions', pg_temp.a2_learner('legacy-actions')),
  ('sequence', pg_temp.a2_learner('sequence')),
  ('chain', pg_temp.a2_learner('chain')),
  ('coc3', pg_temp.a2_learner('coc3')),
  ('bypass', pg_temp.a2_learner('bypass')),
  ('service', pg_temp.a2_learner('service'));
create function pg_temp.a2(p_key text) returns uuid language sql stable as $$ select id from a2_ctx where key = p_key $$;

-- ---------------------------------------------------------------------------
-- Structure, privileges and authority
-- ---------------------------------------------------------------------------
select has_function('public', 'refresh_learner_unlocks', array['uuid'], 'refresh_learner_unlocks(uuid) exists');
select ok(not has_function_privilege('authenticated', 'public.refresh_learner_unlocks(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.refresh_learner_unlocks(uuid)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.refresh_learner_unlocks(uuid)', 'EXECUTE'),
  'only the trusted server can refresh unlocks');
select is((select prosecdef::text || provolatile::text from pg_proc
  where oid = 'public.practice_mission_unlocked(text,uuid)'::regprocedure), 'falses',
  'practice_mission_unlocked stays SECURITY INVOKER and STABLE');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef and p.proname in ('practice_mission_unlocked', 'refresh_learner_unlocks', 'learner_module_states',
    'learner_coc_bypass_active', 'practice_completion_accepted', 'refresh_learner_unlocks_trigger',
    'practice_quiz_requires_complete_modules', 'backfill_learner_module_unlocks')), 0,
  'the unlock slice adds no SECURITY DEFINER function');
select ok(exists(select 1 from pg_policies where tablename = 'practice_mission_actions'
  and policyname = 'practice_actions_progression_gate' and permissive = 'RESTRICTIVE' and cmd = 'INSERT'
  and with_check like '%practice_mission_unlocked%' and with_check like '%131072%'),
  'the restrictive evidence gate calls practice_mission_unlocked and keeps the size limit');
select is((select count(*)::integer from pg_trigger where not tgisinternal
  and tgfoid = 'public.refresh_learner_unlocks_trigger()'::regprocedure
  and tgrelid in ('public.practice_mission_completions'::regclass, 'public.learner_topic_progress'::regclass,
    'public.practice_coc_progress'::regclass)), 3,
  'unlock refresh triggers exist on completions, topic progress and COC progress');
select ok(not has_table_privilege('authenticated', 'public.learner_module_unlocks', 'TRUNCATE')
  and not has_table_privilege('anon', 'public.learner_module_completions', 'TRUNCATE')
  and has_table_privilege('authenticated', 'public.learner_module_unlocks', 'SELECT'),
  'progression tables keep read-only client grants');
select ok(has_column_privilege('authenticated', 'public.practice_mission_contracts', 'version', 'SELECT')
  and not has_column_privilege('authenticated', 'public.practice_mission_contracts', 'definition', 'SELECT'),
  'learners may read contract versions but never contract definitions');

-- ---------------------------------------------------------------------------
-- A new learner: first module open, later modules locked server-side
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', pg_temp.a2('new')::text, true);
set local role authenticated;
select ok(public.practice_mission_unlocked('coc1_m1', pg_temp.a2('new')), 'LO1.1 mission is open for a new learner');
select ok(not public.practice_mission_unlocked('coc1_m3', pg_temp.a2('new')), 'LO1.2 mission is locked until LO1.1 is complete');
select ok(not public.practice_mission_unlocked('coc2_m1', pg_temp.a2('new')), 'COC2 stays locked for a new learner');
select lives_ok($$insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  values (pg_temp.a2('new'), 'a2-open-evidence', 'coc1_m1', 'coc1_m1_p1', 'object_inspected', 'case', '{}'::jsonb, now())$$,
  'evidence for an unlocked module is accepted');
select throws_ok($$insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  values (pg_temp.a2('new'), 'a2-locked-evidence', 'coc1_m3', 'coc1_m3_p1', 'object_inspected', 'media', '{}'::jsonb, now())$$,
  '42501', null, 'a direct REST-style insert into a locked module mission is denied');
select throws_ok($$select public.refresh_learner_unlocks(pg_temp.a2('new'))$$, '42501', null,
  'a learner cannot run the unlock refresh');
reset role;

-- ---------------------------------------------------------------------------
-- Cutover backfill keeps existing progress
-- ---------------------------------------------------------------------------
select pg_temp.a2_complete(pg_temp.a2('legacy_completion'), 'coc1_m4');
select pg_temp.a2_action(pg_temp.a2('legacy_actions'), 'coc1_m4');
select ok(not public.practice_mission_unlocked('coc1_m4', pg_temp.a2('legacy_completion')),
  'before the backfill a later-module completion alone does not unlock its module');
select ok(private.backfill_learner_module_unlocks() >= 0, 'backfill runs');
select ok(public.practice_mission_unlocked('coc1_m4', pg_temp.a2('legacy_completion'))
  and public.practice_mission_unlocked('coc1_m3', pg_temp.a2('legacy_completion')),
  'backfill_keeps_existing_progress: a learner with a COC1 M4 completion keeps LO1.2 unlocked');
select is((select reason from public.learner_module_unlocks
  where learner_id = pg_temp.a2('legacy_completion') and module_id = pg_temp.a2_module('coc1', 'LO1.2')), 'migration',
  'the backfilled unlock is labelled migration');
select ok(exists(select 1 from public.learner_module_unlocks where learner_id = pg_temp.a2('legacy_completion')
  and module_id = pg_temp.a2_module('coc1', 'LO1.1')), 'every earlier module of the COC is backfilled as unlocked');
select ok(not exists(select 1 from public.learner_module_completions where learner_id = pg_temp.a2('legacy_completion')
  and module_id = pg_temp.a2_module('coc1', 'LO1.2')), 'an unfinished module receives no completion record');

select set_config('request.jwt.claim.sub', pg_temp.a2('legacy_actions')::text, true);
set local role authenticated;
select lives_ok($$insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  values (pg_temp.a2('legacy_actions'), 'a2-legacy-m4', 'coc1_m4', 'coc1_m4_p1', 'object_inspected', 'monitor', '{}'::jsonb, now()),
         (pg_temp.a2('legacy_actions'), 'a2-legacy-m3', 'coc1_m3', 'coc1_m3_p1', 'object_inspected', 'media', '{}'::jsonb, now())$$,
  'legacy_unlocked_mission_accepts_evidence: in-progress legacy work can continue after cutover');
reset role;

-- ---------------------------------------------------------------------------
-- Completing LO1.1 (missions + published topics) unlocks LO1.2 permanently
-- ---------------------------------------------------------------------------
insert into a2_ctx values ('topic_11', pg_temp.a2_topic('coc1', 'LO1.1', 'ESD and work-area safety'));
select pg_temp.a2_complete(pg_temp.a2('sequence'), 'coc1_m1');
select pg_temp.a2_complete(pg_temp.a2('sequence'), 'coc1_m2');
select ok(not public.practice_mission_unlocked('coc1_m3', pg_temp.a2('sequence')),
  'a published LO1.1 topic must also be completed before LO1.2 unlocks');
insert into public.learner_topic_progress(learner_id, topic_id, revision_id)
select pg_temp.a2('sequence'), pg_temp.a2('topic_11'), r.id
from public.curriculum_topic_revisions r where r.topic_id = pg_temp.a2('topic_11');
select ok(public.practice_mission_unlocked('coc1_m3', pg_temp.a2('sequence')),
  'completing LO1.1 missions and topics unlocks LO1.2');
select ok(exists(select 1 from public.learner_module_completions where learner_id = pg_temp.a2('sequence')
  and module_id = pg_temp.a2_module('coc1', 'LO1.1')), 'LO1.1 completion is recorded durably');
select is((select reason from public.learner_module_unlocks where learner_id = pg_temp.a2('sequence')
  and module_id = pg_temp.a2_module('coc1', 'LO1.2')), 'sequence', 'the LO1.2 unlock is recorded as a sequence unlock');
select pg_temp.a2_topic('coc1', 'LO1.1', 'Motherboard form factors');
select ok(public.practice_mission_unlocked('coc1_m3', pg_temp.a2('sequence'))
  and exists(select 1 from public.learner_module_completions where learner_id = pg_temp.a2('sequence')
    and module_id = pg_temp.a2_module('coc1', 'LO1.1')),
  'publishing a new LO1.1 topic afterwards does not re-lock LO1.2 or revoke the completion');
select ok(not exists(select 1 from public.learner_module_completions where learner_id = pg_temp.a2('sequence')
  and module_id = pg_temp.a2_module('coc1', 'LO1.3')), 'a module with no required items is not completed before it unlocks');
select pg_temp.a2_complete(pg_temp.a2('sequence'), 'coc1_m3');
select pg_temp.a2_complete(pg_temp.a2('sequence'), 'coc1_m4');
select ok(public.practice_mission_unlocked('coc1_m5', pg_temp.a2('sequence'))
  and exists(select 1 from public.learner_module_completions where learner_id = pg_temp.a2('sequence')
    and module_id = pg_temp.a2_module('coc1', 'LO1.3')),
  'LO1.3 has no required items, completes on unlock and does not block LO1.4');

-- The COC practice quiz requires every module of the COC to be complete.
insert into a2_ctx values ('topic_14', pg_temp.a2_topic('coc1', 'LO1.4', 'Stress testing and documentation'));
select pg_temp.a2_complete(pg_temp.a2('sequence'), 'coc1_m5');
select throws_ok($$select public.practice_begin_quiz(pg_temp.a2('sequence'), 'coc1', gen_random_uuid(),
  '[{"id":"q1","answer":0},{"id":"q2","answer":0},{"id":"q3","answer":0},{"id":"q4","answer":0},{"id":"q5","answer":0}]'::jsonb)$$,
  '22023', 'PRACTICAL_COMPLETION_REQUIRED', 'the COC quiz cannot start while a module topic is incomplete');
insert into public.learner_topic_progress(learner_id, topic_id) values (pg_temp.a2('sequence'), pg_temp.a2('topic_14'));
select lives_ok($$select public.practice_begin_quiz(pg_temp.a2('sequence'), 'coc1', gen_random_uuid(),
  '[{"id":"q1","answer":0},{"id":"q2","answer":0},{"id":"q3","answer":0},{"id":"q4","answer":0},{"id":"q5","answer":0}]'::jsonb)$$,
  'the COC quiz starts once every module is complete');
select is((select count(*)::integer from public.learner_module_completions where learner_id = pg_temp.a2('sequence')
  and module_id in (select id from public.curriculum_modules where coc_code = 'coc1')), 4,
  'all four COC1 modules are recorded complete');

-- ---------------------------------------------------------------------------
-- COC chain, legacy COC progress and the COC3 teaching order
-- ---------------------------------------------------------------------------
alter table public.practice_quiz_attempts disable trigger trg_practice_quiz_requires_complete_modules;
select pg_temp.a2_quiz_pass(pg_temp.a2('chain'), 'coc1');
select pg_temp.a2_quiz_pass(pg_temp.a2('coc3'), 'coc1');
select pg_temp.a2_quiz_pass(pg_temp.a2('coc3'), 'coc2');
alter table public.practice_quiz_attempts enable trigger trg_practice_quiz_requires_complete_modules;
select ok(public.practice_mission_unlocked('coc2_m1', pg_temp.a2('chain'))
  and not public.practice_mission_unlocked('coc2_m4', pg_temp.a2('chain'))
  and not public.practice_mission_unlocked('coc3_m1', pg_temp.a2('chain')),
  'an existing practice_coc_progress row keeps the next COC open at its first module only');
select ok(exists(select 1 from public.learner_module_unlocks where learner_id = pg_temp.a2('chain')
  and module_id = pg_temp.a2_module('coc2', 'LO2.1')), 'the first module of the next COC is recorded as unlocked');
select ok(public.practice_mission_unlocked('coc3_m1', pg_temp.a2('coc3'))
  and not public.practice_mission_unlocked('coc3_m3', pg_temp.a2('coc3'))
  and not public.practice_mission_unlocked('coc3_m5', pg_temp.a2('coc3')),
  'COC3 opens at LO3.2; LO3.1 and LO3.3 stay locked');
select pg_temp.a2_complete(pg_temp.a2('coc3'), 'coc3_m1');
select pg_temp.a2_complete(pg_temp.a2('coc3'), 'coc3_m2');
select pg_temp.a2_complete(pg_temp.a2('coc3'), 'coc3_m4');
select ok(public.practice_mission_unlocked('coc3_m3', pg_temp.a2('coc3'))
  and not public.practice_mission_unlocked('coc3_m5', pg_temp.a2('coc3')),
  'completing LO3.2 unlocks LO3.1 but not LO3.3');
select pg_temp.a2_complete(pg_temp.a2('coc3'), 'coc3_m3');
select ok(public.practice_mission_unlocked('coc3_m5', pg_temp.a2('coc3')), 'completing LO3.1 unlocks LO3.3');

-- ---------------------------------------------------------------------------
-- Instructor COC bypass unlocks every module of that COC only
-- ---------------------------------------------------------------------------
create temporary table a2_bypass (id uuid, instructor_id uuid);
with staff as (
  select (select user_id from public.profiles where email = 'qa.instructor@bytequest.local') instructor,
         (select user_id from public.profiles where email = 'qa.admin@bytequest.local') admin
), source as (
  insert into public.tesda_sources(qualification_code, title, source_reference, status, created_by, approved_by, approved_at)
  select 'A2-CSS-NCII', 'A2 rollback TESDA source', 'Rollback-only fixture source', 'approved', admin, admin, now() from staff
  returning id
), version as (
  insert into public.module_versions(module_id, tesda_source_id, version_number, title, status, created_by, published_by, published_at)
  select (select id from public.coc_modules where coc_code = 'coc2'), source.id, 9201, 'A2 COC2 bypass fixture', 'published',
    staff.admin, staff.admin, now() from source, staff
  returning id
), classroom as (
  insert into public.classes(title, instructor_id, created_by)
  select 'A2 bypass class', instructor, instructor from staff returning id
), membership as (
  insert into public.class_memberships(class_id, learner_id, enrolled_by)
  select classroom.id, pg_temp.a2('bypass'), staff.instructor from classroom, staff returning class_id
), bypass as (
  insert into public.coc_bypasses(learner_id, class_id, module_version_id, instructor_id, reason)
  select pg_temp.a2('bypass'), membership.class_id, version.id, staff.instructor, 'Rollback bypass fixture'
  from membership, version, staff
  returning id, instructor_id
)
insert into a2_bypass select id, instructor_id from bypass;
select set_config('request.jwt.claim.sub', pg_temp.a2('bypass')::text, true);
set local role authenticated;
select ok(public.practice_mission_unlocked('coc2_m1', pg_temp.a2('bypass'))
  and public.practice_mission_unlocked('coc2_m4', pg_temp.a2('bypass'))
  and public.practice_mission_unlocked('coc2_m5', pg_temp.a2('bypass')),
  'an active COC2 bypass unlocks every COC2 module for practice (learner context)');
select ok(not public.practice_mission_unlocked('coc3_m1', pg_temp.a2('bypass')), 'the bypass does not reach other COCs');
select lives_ok($$insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  values (pg_temp.a2('bypass'), 'a2-bypass-m4', 'coc2_m4', 'coc2_m4_p1', 'object_inspected', 'switch', '{}'::jsonb, now())$$,
  'bypassed learners can record evidence in a later module of the bypassed COC');
reset role;
update public.coc_bypasses set revoked_at = now(), revoked_by = (select instructor_id from a2_bypass),
  revocation_reason = 'Rollback revocation' where id = (select id from a2_bypass);
select ok(not public.practice_mission_unlocked('coc2_m4', pg_temp.a2('bypass')), 'revoking the bypass ends bypass-only access');

-- ---------------------------------------------------------------------------
-- Service-role writes run the refresh with sufficient privileges
-- ---------------------------------------------------------------------------
set local role service_role;
select pg_temp.a2_complete(pg_temp.a2('service'), 'coc1_m1');
select pg_temp.a2_complete(pg_temp.a2('service'), 'coc1_m2');
-- The two LO1.1 topics published above are required for every learner.
insert into public.learner_topic_progress(learner_id, topic_id)
select pg_temp.a2('service'), t.id from public.curriculum_topics t
where t.module_id = pg_temp.a2_module('coc1', 'LO1.1') and t.archived_at is null;
select ok(exists(select 1 from public.learner_module_unlocks where learner_id = pg_temp.a2('service')
    and module_id = pg_temp.a2_module('coc1', 'LO1.2') and reason = 'sequence'),
  'a service-role verification write records the next module unlock through the trigger');
reset role;
select is((select count(*)::integer from public.learner_module_unlocks u
  where u.learner_id = pg_temp.a2('service')), 2, 'the refresh records only LO1.1 and LO1.2 for that learner');

select * from finish();
rollback;
