-- Rollback-only regression for the simulation_condition evidence operator
-- (slice A1.2). Attempt evidence is replayed against the activity version's
-- evaluator_config.simulation_definition; a criterion is satisfied when its
-- phases are done, its conditions hold on the final state, and the invalid
-- actions plus corrections on its counted targets stay within max_incorrect.
begin;
select plan(27);

create temp table cond_ctx (
  admin uuid not null default gen_random_uuid(),
  instructor uuid not null default gen_random_uuid(),
  learner uuid not null default gen_random_uuid(),
  source uuid, module_version uuid, activity uuid, bare_activity uuid,
  class uuid, assignment uuid, bare_assignment uuid
) on commit drop;
insert into cond_ctx default values;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'authenticated', 'authenticated',
  'condition-' || id || '@bytequest.invalid', '', '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Simulation condition rollback fixture"}'::jsonb, now(), now()
from cond_ctx cross join lateral (values (admin), (instructor), (learner)) u(id);
update public.profiles set role = 'admin' where user_id = (select admin from cond_ctx);
update public.profiles set role = 'instructor' where user_id = (select instructor from cond_ctx);

with s as (
  insert into public.tesda_sources(qualification_code, title, edition, source_reference, status,
    validation_notes, created_by, approved_by, approved_at, activated_by, activated_at)
  select 'ROLLBACK-' || left(gen_random_uuid()::text, 8), 'Rollback-only simulation condition source',
    'TEST_ONLY', 'Rollback fixture; never a production TESDA source', 'active', 'TEST_ONLY_ROLLBACK_FIXTURE',
    admin, admin, now(), admin, now() from cond_ctx
  returning id)
update cond_ctx set source = s.id from s;

with m as (
  insert into public.module_versions(module_id, tesda_source_id, version_number, title, status,
    created_by, published_by, published_at)
  select c.id, x.source, coalesce((select max(version_number) from public.module_versions mv where mv.module_id = c.id), 0) + 1,
    'Rollback simulation module', 'published', x.admin, x.admin, now()
  from cond_ctx x cross join public.coc_modules c where c.coc_code = 'coc1'
  returning id)
update cond_ctx set module_version = m.id from m;

-- Compact bench contract: P1 places a CPU (lever must be open) and a memory
-- module; P2 connects the 24-pin cable; P3 is the review.
create temp table cond_definition(definition jsonb) on commit drop;
insert into cond_definition values ('{
  "id": "rollback_bench",
  "phases": [
    {"id": "t_p1", "primaryInteraction": "place", "presentation": {
      "items": [
        {"id": "cpu", "category": "cpu", "seating_orientation": "0",
         "requires": [{"path": "setting.lever", "value": "open"}]},
        {"id": "ram_1", "category": "dimm"}
      ],
      "destinations": [
        {"id": "socket", "socket_categories": ["cpu"]},
        {"id": "dimm_a1", "socket_categories": ["dimm"]},
        {"id": "dimm_a2", "socket_categories": ["dimm"]}
      ],
      "equipment": {"single_connection": true, "operations": [
        {"id": "open_lever", "effects": {"lever": "open"}, "requires": []},
        {"id": "close_lever", "effects": {"lever": "closed"}, "requires": [{"path": "setting.lever", "value": "open"}]}
      ]}}},
    {"id": "t_p2", "primaryInteraction": "connect", "presentation": {
      "sources": [{"id": "atx24", "interfaces": ["atx"]}],
      "destinations": [{"id": "board_atx", "interface": "atx"}],
      "equipment": {"single_connection": true}}},
    {"id": "t_p3", "primaryInteraction": "review", "presentation": {}}
  ]}');

with a as (
  insert into public.activity_versions(mission_id, module_version_id, version_number, title, delivery_mode,
    learner_payload, evaluator_config, status, created_by, published_by, published_at)
  select ms.id, x.module_version,
    coalesce((select max(version_number) from public.activity_versions av where av.mission_id = ms.id), 0) + n,
    'Rollback simulation assessment ' || n, 'assessment',
    '{"mission_id":"coc1_m2","definition_version":"rollback","mode":"assessment"}'::jsonb,
    case when n = 1 then jsonb_build_object('simulation_definition', (select definition from cond_definition))
      else '{"engine":"database_rule_v1"}'::jsonb end,
    'published', x.admin, x.admin, now()
  from cond_ctx x cross join public.missions ms cross join generate_series(1, 2) n
  where ms.mission_code = 'coc1_m2'
  returning id, version_number)
update cond_ctx set activity = (select id from a order by version_number limit 1),
  bare_activity = (select id from a order by version_number desc limit 1);

with c as (
  insert into public.classes(title, instructor_id, created_by)
  select 'Rollback simulation class', instructor, instructor from cond_ctx returning id)
update cond_ctx set class = c.id from c;
with s as (
  insert into public.assignments(class_id, activity_version_id, title, assigned_by)
  select class, v, 'Rollback simulation assignment ' || n, instructor
  from cond_ctx cross join lateral (values (activity, 1), (bare_activity, 2)) t(v, n)
  returning id, activity_version_id)
update cond_ctx set assignment = (select id from s where activity_version_id = cond_ctx.activity),
  bare_assignment = (select id from s where activity_version_id = cond_ctx.bare_activity);

-- One attempt per scenario; actions carry phase_id in value as the app sends.
create temp table cond_attempt(name text primary key, attempt uuid not null) on commit drop;
create function pg_temp.attempt_with(p_name text, p_actions jsonb, p_bare boolean default false)
returns uuid language plpgsql as $$
declare v_attempt uuid; ctx cond_ctx;
begin
  select * into ctx from cond_ctx;
  insert into public.attempts(learner_id, class_id, assignment_id, activity_version_id, client_start_key)
  values (ctx.learner, ctx.class, case when p_bare then ctx.bare_assignment else ctx.assignment end,
    case when p_bare then ctx.bare_activity else ctx.activity end, gen_random_uuid())
  returning id into v_attempt;
  insert into public.attempt_actions(attempt_id, sequence_number, action_type, target, value, client_occurred_at)
  values (v_attempt, 1, 'attempt_started', null, '{"assignment_type":"assessment"}'::jsonb, now());
  insert into public.attempt_actions(attempt_id, sequence_number, action_type, target, value, client_occurred_at)
  select v_attempt, n + 1, x->>'type', x->>'target',
    coalesce(x->'value', '{}'::jsonb) || jsonb_build_object('phase_id', x->>'phase', 'mission_id', 'coc1_m2',
      'client_action_id', p_name || '-' || n),
    now() + n * interval '1 second'
  from jsonb_array_elements(p_actions) with ordinality t(x, n);
  insert into cond_attempt values (p_name, v_attempt);
  return v_attempt;
end $$;

create temp table cond_steps(name text primary key, actions jsonb) on commit drop;
insert into cond_steps values
('open', '[{"phase":"t_p1","type":"equipment_operation","target":"open_lever"}]'),
('cpu', '[{"phase":"t_p1","type":"component_drop_attempted","target":"socket","value":{"runtime_action_type":"placement_attempted","item_id":"cpu","destination_id":"socket","orientation":"0"}}]'),
('cpu_rotated', '[{"phase":"t_p1","type":"component_drop_attempted","target":"socket","value":{"runtime_action_type":"placement_attempted","item_id":"cpu","destination_id":"socket","orientation":"90"}}]'),
('close', '[{"phase":"t_p1","type":"equipment_operation","target":"close_lever"}]'),
('ram_a1', '[{"phase":"t_p1","type":"component_drop_attempted","target":"dimm_a1","value":{"runtime_action_type":"placement_attempted","item_id":"ram_1","destination_id":"dimm_a1"}}]'),
('ram_a2', '[{"phase":"t_p1","type":"component_drop_attempted","target":"dimm_a2","value":{"runtime_action_type":"placement_attempted","item_id":"ram_1","destination_id":"dimm_a2"}}]'),
('ram_out', '[{"phase":"t_p1","type":"placement_removed","target":"ram_1","value":{"item_id":"ram_1"}}]'),
('atx', '[{"phase":"t_p2","type":"connection_created","target":"board_atx","value":{"source_id":"atx24","destination_id":"board_atx"}}]');

create function pg_temp.steps(variadic p_names text[])
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(x order by n, m), '[]'::jsonb)
  from unnest(p_names) with ordinality u(name, n)
  join cond_steps s on s.name = u.name
  cross join lateral jsonb_array_elements(s.actions) with ordinality e(x, m)
$$;

select pg_temp.attempt_with('perfect', pg_temp.steps('open', 'cpu', 'close', 'ram_a2', 'atx'));
select pg_temp.attempt_with('cpu_one_error', pg_temp.steps('open', 'cpu_rotated', 'cpu', 'close', 'ram_a2', 'atx'));
select pg_temp.attempt_with('cpu_two_errors', pg_temp.steps('open', 'cpu_rotated', 'cpu_rotated', 'cpu', 'close', 'ram_a2', 'atx'));
select pg_temp.attempt_with('ram_two_corrections', pg_temp.steps('open', 'cpu', 'close',
  'ram_a1', 'ram_out', 'ram_a1', 'ram_out', 'ram_a2', 'atx'));
select pg_temp.attempt_with('ram_three_corrections', pg_temp.steps('open', 'cpu', 'close',
  'ram_a1', 'ram_out', 'ram_a1', 'ram_out', 'ram_a1', 'ram_out', 'ram_a2', 'atx'));
select pg_temp.attempt_with('no_power_phase', pg_temp.steps('open', 'cpu', 'close', 'ram_a2'));
select pg_temp.attempt_with('lever_open', pg_temp.steps('open', 'cpu', 'ram_a2', 'atx'));
select pg_temp.attempt_with('no_definition', pg_temp.steps('open', 'cpu', 'close', 'ram_a2', 'atx'), true);

create temp table cond_rule(name text primary key, rule jsonb) on commit drop;
insert into cond_rule values
('cpu_safety', '{"operator":"simulation_condition","phase_ids":["t_p1"],
  "conditions":[{"path":"placed.cpu","value":"socket"},{"path":"setting.lever","value":"closed"}],
  "counted_targets":["item:cpu","operation:open_lever","operation:close_lever"],"max_incorrect":0}'),
('cpu_standard', '{"operator":"simulation_condition","phase_ids":["t_p1"],
  "conditions":[{"path":"placed.cpu","value":"socket"},{"path":"setting.lever","value":"closed"}],
  "counted_targets":["item:cpu"],"max_incorrect":2}'),
('ram', '{"operator":"simulation_condition","phase_ids":["t_p1"],
  "conditions":[{"path":"placed.ram_1","operator":"one_of","value":["dimm_a2"]}],
  "counted_targets":["item:ram_1"],"max_incorrect":2}'),
('power', '{"operator":"simulation_condition","phase_ids":["t_p2"],
  "conditions":[{"path":"link.atx24>board_atx","value":true}],
  "counted_targets":["connection:atx24"],"max_incorrect":2}');

create function pg_temp.observe(p_attempt text, p_rule text)
returns jsonb language sql as $$
  select private.evaluate_criterion_evidence(
    (select attempt from cond_attempt where name = p_attempt),
    (select rule from cond_rule where name = p_rule))
$$;

-- Validation of the new rule shape; existing operators keep their validity.
select ok(private.valid_evidence_rule(rule), name || ' is a valid simulation_condition rule')
from cond_rule order by name;
select ok(not private.valid_evidence_rule(r), 'malformed simulation rule rejected: ' || label)
from (values
  ('{"operator":"simulation_condition","phase_ids":[],"conditions":[],"counted_targets":[],"max_incorrect":0}'::jsonb, 'no phases'),
  ('{"operator":"simulation_condition","phase_ids":["t_p1"],"conditions":[],"counted_targets":[],"max_incorrect":-1}'::jsonb, 'negative threshold'),
  ('{"operator":"simulation_condition","phase_ids":["t_p1"],"conditions":[{"path":"placed.cpu","operator":"regex","value":".*"}],"counted_targets":[],"max_incorrect":0}'::jsonb, 'unknown condition operator'),
  ('{"operator":"simulation_condition","phase_ids":["t_p1"],"conditions":"placed.cpu","counted_targets":[],"max_incorrect":0}'::jsonb, 'conditions not a list'),
  ('{"operator":"simulation_condition","phase_ids":["t_p1"],"conditions":[],"counted_targets":[1],"max_incorrect":0}'::jsonb, 'non-text counted target')
) t(r, label);
select ok(private.valid_evidence_rule('{"operator":"action_exists","action_type":"placement_attempted","minimum_count":1}')
  and private.valid_evidence_rule('{"operator":"exact_target_sequence","action_type":"x","expected_targets":["a"]}')
  and private.valid_evidence_rule('{"operator":"final_action_value_set_equals","action_type":"x","value_key":"k","expected":["a"]}')
  and not private.valid_evidence_rule('{"operator":"unknown_operator"}'),
  'existing evidence operators keep their validation');

-- Evaluation.
select is(pg_temp.observe('perfect', name)->>'observation', 'satisfied', 'perfect run satisfies ' || name)
from cond_rule order by name;
select is(pg_temp.observe('cpu_one_error', 'cpu_safety')->>'observation', 'not_satisfied',
  'a safety-critical step fails after one invalid attempt');
select is(pg_temp.observe('cpu_two_errors', 'cpu_standard')->>'observation', 'satisfied',
  'two invalid attempts stay within a threshold of two');
select is(pg_temp.observe('ram_two_corrections', 'ram')->>'observation', 'satisfied',
  'two corrections stay within the threshold');
select is(pg_temp.observe('ram_three_corrections', 'ram')->>'observation', 'not_satisfied',
  'three corrections exceed the threshold');
select is(pg_temp.observe('ram_three_corrections', 'ram')->'observed_evidence'->'incorrect_by_target',
  '{"item:ram_1": {"invalid": 0, "corrections": 3}}'::jsonb, 'observed evidence reports counts per counted target');
select is(pg_temp.observe('no_power_phase', 'power')->>'observation', 'not_satisfied',
  'an unfinished phase is not satisfied');
select is(pg_temp.observe('no_power_phase', 'power')->'observed_evidence'->'phases_done',
  '[]'::jsonb, 'observed evidence lists the required phases that are done');
select is(pg_temp.observe('lever_open', 'cpu_standard')->>'observation', 'not_satisfied',
  'a condition that fails on the final state is not satisfied');
select is(pg_temp.observe('no_definition', 'cpu_standard')->'observed_evidence'->>'reason',
  'SIMULATION_DEFINITION_MISSING', 'an activity without a simulation definition is not satisfied');
select is((pg_temp.observe('cpu_two_errors', 'cpu_safety')->'observed_evidence'->>'incorrect_total')::integer,
  2, 'observed evidence totals the counted incorrect actions');

-- Learners cannot evaluate or replay evidence themselves.
select ok(not has_function_privilege('authenticated', 'private.evaluate_criterion_evidence(uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.evaluate_criterion_evidence(uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.valid_evidence_rule(jsonb)', 'EXECUTE'),
  'learners cannot execute the evaluator');
create temp table cond_denial(name text primary key, code text) on commit drop;
grant insert on cond_denial to authenticated;
select set_config('request.jwt.claim.sub', (select learner::text from cond_ctx), true);
set local role authenticated;
do $$
begin
  begin
    perform private.evaluate_criterion_evidence(gen_random_uuid(), '{"operator":"simulation_condition"}'::jsonb);
    insert into cond_denial values ('evaluator', 'allowed');
  exception when others then
    insert into cond_denial values ('evaluator', sqlstate);
  end;
  begin
    perform private.simulation_replay('{}'::jsonb, '[]'::jsonb);
    insert into cond_denial values ('replay', 'allowed');
  exception when others then
    insert into cond_denial values ('replay', sqlstate);
  end;
end $$;
reset role;
select is((select code from cond_denial where name = 'evaluator'), '42501',
  'a learner session is refused by the evaluator');
select is((select code from cond_denial where name = 'replay'), '42501',
  'a learner session is refused by the replay');

select * from finish();
rollback;
