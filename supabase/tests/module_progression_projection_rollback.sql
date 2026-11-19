-- Learner curriculum projection get_learner_curriculum() (re-defense slice
-- A2.3). Rollback-only; evaluated with the learner's own RLS.
begin;
select plan(30);

-- Isolate the expected progress values from lessons published in the target
-- database (rolled back with everything else): the fixtures below define the
-- only curriculum topics.
update public.curriculum_topics set archived_at = now() where archived_at is null;

create function pg_temp.lp_learner(p_tag text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users(instance_id, id, aud, role, email, encrypted_password,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000'::uuid, v_id, 'authenticated', 'authenticated',
    'lp-' || p_tag || '-' || v_id || '@bytequest.invalid', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', 'LP ' || p_tag), now(), now());
  return v_id;
end $$;
create function pg_temp.lp_complete(p_learner uuid, p_mission text) returns void language sql as $$
  with a as (
    insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
      action_type, target, value, client_occurred_at)
    values (p_learner, 'lp-' || gen_random_uuid(), p_mission, p_mission || '_p1', 'object_inspected', 'fixture', '{}'::jsonb, clock_timestamp())
    returning id)
  insert into public.practice_mission_completions(learner_id, mission_id, contract_version, evidence_through_id)
  select p_learner, c.mission_id, c.version, a.id from public.practice_mission_contracts c, a where c.mission_id = p_mission
$$;
create function pg_temp.lp_topic(p_code text, p_title text, p_status text default 'published') returns uuid language plpgsql as $$
declare v_topic uuid := gen_random_uuid();
  v_module uuid := (select id from public.curriculum_modules where coc_code = 'coc1' and code = p_code);
begin
  insert into public.curriculum_topics(id, module_id, sequence_order)
  values (v_topic, v_module, 1 + (select count(*) from public.curriculum_topics where module_id = v_module));
  insert into public.curriculum_topic_revisions(topic_id, revision_number, title, summary, body_markdown, status)
  values (v_topic, 1, p_title, 'Summary of ' || p_title, 'Lesson body.', p_status::public.content_publication_status);
  return v_topic;
end $$;

create temporary table lp_ctx (key text primary key, id uuid);
grant select on lp_ctx to authenticated;
insert into lp_ctx values ('learner', pg_temp.lp_learner('one')), ('other', pg_temp.lp_learner('two'));
create function pg_temp.lp(p_key text) returns uuid language sql stable as $$ select id from lp_ctx where key = p_key $$;

-- Reads the projection as the learner (RLS) and returns one module/COC node.
create function pg_temp.lp_view(p_key text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.lp(p_key)::text, true);
  execute 'set local role authenticated';
  v := public.get_learner_curriculum();
  execute 'reset role';
  return v;
end $$;
create function pg_temp.lp_coc(p_view jsonb, p_coc text) returns jsonb language sql immutable as $$
  select c from jsonb_array_elements(p_view->'cocs') c where c->>'coc_code' = p_coc
$$;
create function pg_temp.lp_mod(p_view jsonb, p_coc text, p_code text) returns jsonb language sql immutable as $$
  select m from jsonb_array_elements(pg_temp.lp_coc(p_view, p_coc)->'modules') m where m->>'code' = p_code
$$;

select has_function('public', 'get_learner_curriculum', array[]::text[], 'get_learner_curriculum() exists');
select ok(has_function_privilege('authenticated', 'public.get_learner_curriculum()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_learner_curriculum()', 'EXECUTE')
  and not (select prosecdef from pg_proc where oid = 'public.get_learner_curriculum()'::regprocedure),
  'the projection is an invoker function for signed-in callers only');

select set_config('request.jwt.claim.sub', (select user_id::text from public.profiles where email = 'qa.instructor@bytequest.local'), true);
set local role authenticated;
select throws_ok($$select public.get_learner_curriculum()$$, '42501', 'ACTIVE_LEARNER_REQUIRED', 'only learners have a learner projection');
reset role;

-- ---------------------------------------------------------------------------
-- New learner
-- ---------------------------------------------------------------------------
create temporary table lp_view (key text primary key, v jsonb);
insert into lp_view values ('new', pg_temp.lp_view('learner'));
select is((select string_agg(c->>'coc_code', ',') from jsonb_array_elements((select v from lp_view where key = 'new')->'cocs') c),
  'coc1,coc2,coc3,coc4', 'four COCs in curriculum order');
select is((select string_agg(m->>'code', '>') from jsonb_array_elements(pg_temp.lp_coc((select v from lp_view where key = 'new'), 'coc3')->'modules') m),
  'LO3.2>LO3.1>LO3.3', 'COC3 modules follow the approved teaching order');
select ok((pg_temp.lp_coc((select v from lp_view where key = 'new'), 'coc1')->>'unlocked')::boolean
  and not (pg_temp.lp_coc((select v from lp_view where key = 'new'), 'coc2')->>'unlocked')::boolean,
  'COC1 is open and COC2 is locked');
select is(pg_temp.lp_coc((select v from lp_view where key = 'new'), 'coc2')->>'lock_reason',
  'Complete COC 1 and pass the COC 1 practice quiz to unlock.', 'a locked COC explains its prerequisite');
select is(pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.2')->>'lock_reason',
  'Complete Module 1 · LO1.1 Assemble computer hardware to unlock.', 'a locked module names the module to complete');
select ok((pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->>'unlocked')::boolean
  and pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->'lock_reason' = 'null'::jsonb,
  'the first module is open without a lock reason');
select ok((pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.3')->>'no_required_items')::boolean,
  'LO1.3 is labelled as having no required activities yet');
select is(pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->'progress',
  '{"done": 0, "total": 2, "percent": 0}'::jsonb, 'LO1.1 progress counts its two practice missions');
select is(pg_temp.lp_coc((select v from lp_view where key = 'new'), 'coc1')->'progress',
  '{"done": 0, "total": 6, "percent": 0}'::jsonb, 'COC1 progress counts five missions plus the practice quiz');
select is((select string_agg(m->>'mission_code', ',') from jsonb_array_elements(pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->'missions') m),
  'coc1_m1,coc1_m2', 'LO1.1 lists its linked missions in order');
select is(pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->'missions'->0->>'title',
  'Identify Computer Parts and Tools', 'mission titles come from the canonical catalog');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->'outcomes')),
  5, 'LO1.1 shows its five official performance criteria');
select is(pg_temp.lp_mod((select v from lp_view where key = 'new'), 'coc1', 'LO1.1')->'outcomes'->3->>'statement',
  'Computer hardware is assembled in accordance with established procedures and systems requirements',
  'performance criteria are verbatim');
select is(pg_temp.lp_coc((select v from lp_view where key = 'new'), 'coc1')->'quiz', '{"passed": false, "eligible": false}'::jsonb,
  'the COC quiz is not yet eligible');

-- ---------------------------------------------------------------------------
-- Topics, missions, runs and completion
-- ---------------------------------------------------------------------------
insert into lp_ctx values ('topic', pg_temp.lp_topic('LO1.1', 'ESD precautions'));
select pg_temp.lp_topic('LO1.1', 'Draft lesson', 'draft');
select pg_temp.lp_complete(pg_temp.lp('learner'), 'coc1_m1');
insert into public.practice_mission_runs(learner_id, mission_id, contract_version, run_number, duration_seconds, outcome)
values (pg_temp.lp('learner'), 'coc1_m1', 'fixture', 1, 410, 'incomplete'),
       (pg_temp.lp('learner'), 'coc1_m1', 'fixture', 2, 305, 'verified'),
       (pg_temp.lp('learner'), 'coc1_m1', 'fixture', 3, 280, 'verified');
insert into lp_view values ('progress', pg_temp.lp_view('learner'));
select is((select string_agg(t->>'title', ',') from jsonb_array_elements(pg_temp.lp_mod((select v from lp_view where key = 'progress'), 'coc1', 'LO1.1')->'topics') t),
  'ESD precautions', 'only published topics are listed');
select is(pg_temp.lp_mod((select v from lp_view where key = 'progress'), 'coc1', 'LO1.1')->'topics'->0->>'revision_id',
  (select id::text from public.curriculum_topic_revisions where topic_id = pg_temp.lp('topic')), 'a topic carries its published revision id');
select is(pg_temp.lp_mod((select v from lp_view where key = 'progress'), 'coc1', 'LO1.1')->'progress',
  '{"done": 1, "total": 3, "percent": 33}'::jsonb, 'module progress = completed required items / required items');
select is(pg_temp.lp_mod((select v from lp_view where key = 'progress'), 'coc1', 'LO1.1')->'missions'->0,
  '{"title": "Identify Computer Parts and Tools", "verified": true, "runs": 3, "best_seconds": 280, "mission_code": "coc1_m1", "mission_number": 1, "unlocked": true}'::jsonb,
  'mission tiles carry verified state, run count and best verified time');
select is(pg_temp.lp_mod((select v from lp_view where key = 'progress'), 'coc1', 'LO1.1')->'missions'->1->>'runs', '0',
  'a mission without runs reports zero runs');
insert into lp_view values ('other', pg_temp.lp_view('other'));
select is(pg_temp.lp_mod((select v from lp_view where key = 'other'), 'coc1', 'LO1.1')->'progress'->>'done', '0',
  'another learner never sees this learner''s progress');

select pg_temp.lp_complete(pg_temp.lp('learner'), 'coc1_m2');
insert into public.learner_topic_progress(learner_id, topic_id) values (pg_temp.lp('learner'), pg_temp.lp('topic'));
insert into lp_view values ('done', pg_temp.lp_view('learner'));
select ok((pg_temp.lp_mod((select v from lp_view where key = 'done'), 'coc1', 'LO1.1')->>'completed')::boolean
  and (pg_temp.lp_mod((select v from lp_view where key = 'done'), 'coc1', 'LO1.1')->'topics'->0->>'completed')::boolean,
  'LO1.1 and its topic are complete');
select ok((pg_temp.lp_mod((select v from lp_view where key = 'done'), 'coc1', 'LO1.2')->>'unlocked')::boolean,
  'LO1.2 is unlocked in the projection');
select is(pg_temp.lp_coc((select v from lp_view where key = 'done'), 'coc1')->'progress',
  '{"done": 3, "total": 7, "percent": 42}'::jsonb, 'COC1 progress = topics + missions + quiz');

select pg_temp.lp_topic('LO1.1', 'Motherboard form factors');
insert into lp_view values ('new_content', pg_temp.lp_view('learner'));
select ok((pg_temp.lp_mod((select v from lp_view where key = 'new_content'), 'coc1', 'LO1.1')->>'completed')::boolean
  and (pg_temp.lp_mod((select v from lp_view where key = 'new_content'), 'coc1', 'LO1.1')->>'new_content')::boolean
  and (pg_temp.lp_mod((select v from lp_view where key = 'new_content'), 'coc1', 'LO1.2')->>'unlocked')::boolean,
  'a completed module that gains a topic shows new content without re-locking the next module');
select ok(not (pg_temp.lp_mod((select v from lp_view where key = 'done'), 'coc1', 'LO1.1')->>'new_content')::boolean,
  'new content is not flagged when every required item is complete');

-- Every COC1 module complete makes the practice quiz eligible.
select pg_temp.lp_complete(pg_temp.lp('learner'), 'coc1_m3');
select pg_temp.lp_complete(pg_temp.lp('learner'), 'coc1_m4');
select pg_temp.lp_complete(pg_temp.lp('learner'), 'coc1_m5');
insert into lp_view values ('quiz', pg_temp.lp_view('learner'));
select is(pg_temp.lp_coc((select v from lp_view where key = 'quiz'), 'coc1')->'quiz', '{"passed": false, "eligible": true}'::jsonb,
  'the COC quiz is eligible once every module is complete');
select ok(not (pg_temp.lp_coc((select v from lp_view where key = 'quiz'), 'coc1')->>'completed')::boolean,
  'the COC is not complete until its practice quiz is passed');

select * from finish();
rollback;
