-- Rollback-only regression for the COC1 M2 assembly-bench practice contract
-- css-assembly-20261119-v3 (slice A1.4): server-side realism rules, the POST
-- symptoms of physically possible mistakes, corrections, POST faults charged
-- to their steps, the v2-to-v3 version boundary, and the quiz gate
-- that keeps earlier verified versions.
begin;
select plan(28);

create temp table m2_ctx (learner uuid not null default gen_random_uuid()) on commit drop;
insert into m2_ctx default values;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, learner, 'authenticated', 'authenticated',
  'assembly-' || learner || '@bytequest.invalid', '', '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Assembly bench rollback learner"}'::jsonb, now(), now()
from m2_ctx;

create temp table m2_contract on commit drop as
  select definition from public.practice_mission_contracts where mission_id = 'coc1_m2';

-- Named bench actions: (phase, runtime type, target, value).
create temp table m2_step(name text primary key, phase text, kind text, target text, value jsonb) on commit drop;
insert into m2_step values
('inspect_case', 'coc1_m2_p1', 'object_inspected', 'system_case', '{}'),
('inspect_board', 'coc1_m2_p1', 'object_inspected', 'motherboard', '{}'),
('inspect_cpu', 'coc1_m2_p1', 'object_inspected', 'cpu', '{}'),
('inspect_cooler', 'coc1_m2_p1', 'object_inspected', 'cooler', '{}'),
('inspect_ram', 'coc1_m2_p1', 'object_inspected', 'ram', '{}'),
('inspect_psu', 'coc1_m2_p1', 'object_inspected', 'psu', '{}'),
('inspect_storage', 'coc1_m2_p1', 'object_inspected', 'storage', '{}'),
('wear_strap', 'coc1_m2_p1', 'equipment_operation', 'wear_wrist_strap', '{}'),
('ground_strap', 'coc1_m2_p1', 'equipment_operation', 'ground_wrist_strap', '{}'),
('open_lever', 'coc1_m2_p2', 'equipment_operation', 'open_cpu_lever', '{}'),
('cpu_rotated', 'coc1_m2_p2', 'placement_attempted', 'cpu_socket', '{"item_id":"cpu","destination_id":"cpu_socket","orientation":"90"}'),
('cpu', 'coc1_m2_p2', 'placement_attempted', 'cpu_socket', '{"item_id":"cpu","destination_id":"cpu_socket","orientation":"0"}'),
('close_lever', 'coc1_m2_p2', 'equipment_operation', 'close_cpu_lever', '{}'),
('compound', 'coc1_m2_p2', 'equipment_operation', 'apply_thermal_compound', '{}'),
('cooler', 'coc1_m2_p2', 'placement_attempted', 'cooler_mount', '{"item_id":"cooler","destination_id":"cooler_mount"}'),
('fan_cpu', 'coc1_m2_p2', 'connection_created', 'cpu_fan_header', '{"source_id":"cooler_fan","destination_id":"cpu_fan_header"}'),
('open_latches', 'coc1_m2_p2', 'equipment_operation', 'open_dimm_latches', '{}'),
('ram1_a2', 'coc1_m2_p2', 'placement_attempted', 'dimm_a2', '{"item_id":"ram_1","destination_id":"dimm_a2","orientation":"0"}'),
('ram2_b2', 'coc1_m2_p2', 'placement_attempted', 'dimm_b2', '{"item_id":"ram_2","destination_id":"dimm_b2","orientation":"0"}'),
('ram1_a1', 'coc1_m2_p2', 'placement_attempted', 'dimm_a1', '{"item_id":"ram_1","destination_id":"dimm_a1","orientation":"0"}'),
('ram2_b1', 'coc1_m2_p2', 'placement_attempted', 'dimm_b1', '{"item_id":"ram_2","destination_id":"dimm_b1","orientation":"0"}'),
('lock_latches', 'coc1_m2_p2', 'equipment_operation', 'close_dimm_latches', '{}'),
('psu', 'coc1_m2_p3', 'placement_attempted', 'psu_bay', '{"item_id":"psu","destination_id":"psu_bay","orientation":"0"}'),
('screwdriver', 'coc1_m2_p3', 'equipment_operation', 'pick_screwdriver', '{}'),
('fasten_psu', 'coc1_m2_p3', 'equipment_operation', 'fasten_psu', '{}'),
('shield', 'coc1_m2_p3', 'placement_attempted', 'io_cutout', '{"item_id":"io_shield","destination_id":"io_cutout"}'),
('board', 'coc1_m2_p3', 'placement_attempted', 'board_standoffs', '{"item_id":"motherboard","destination_id":"board_standoffs"}'),
('board_out', 'coc1_m2_p3', 'placement_removed', 'motherboard', '{"item_id":"motherboard"}'),
('fasten_board', 'coc1_m2_p3', 'equipment_operation', 'fasten_motherboard', '{}'),
('drive', 'coc1_m2_p3', 'placement_attempted', 'drive_bay', '{"item_id":"storage","destination_id":"drive_bay"}'),
('fasten_drive', 'coc1_m2_p3', 'equipment_operation', 'fasten_drive', '{}'),
('atx24', 'coc1_m2_p4', 'connection_created', 'board_atx24', '{"source_id":"atx_24pin","destination_id":"board_atx24"}'),
('atx24_in_eps', 'coc1_m2_p4', 'connection_created', 'board_eps8', '{"source_id":"atx_24pin","destination_id":"board_eps8"}'),
('eps8', 'coc1_m2_p4', 'connection_created', 'board_eps8', '{"source_id":"eps_8pin","destination_id":"board_eps8"}'),
('sata_power', 'coc1_m2_p4', 'connection_created', 'drive_power', '{"source_id":"sata_power","destination_id":"drive_power"}'),
('sata_data', 'coc1_m2_p4', 'connection_created', 'drive_data', '{"source_id":"sata_data","destination_id":"drive_data"}'),
('front_panel', 'coc1_m2_p4', 'connection_created', 'board_front_panel', '{"source_id":"front_panel","destination_id":"board_front_panel"}'),
('eps8_fix', 'coc1_m2_p5', 'connection_created', 'board_eps8', '{"source_id":"eps_8pin","destination_id":"board_eps8"}'),
('ram1_out', 'coc1_m2_p5', 'placement_removed', 'ram_1', '{"item_id":"ram_1"}'),
('ram2_out', 'coc1_m2_p5', 'placement_removed', 'ram_2', '{"item_id":"ram_2"}'),
('fix_open_latches', 'coc1_m2_p5', 'equipment_operation', 'open_dimm_latches', '{}'),
('fix_ram1_a2', 'coc1_m2_p5', 'placement_attempted', 'dimm_a2', '{"item_id":"ram_1","destination_id":"dimm_a2","orientation":"0"}'),
('fix_ram2_b2', 'coc1_m2_p5', 'placement_attempted', 'dimm_b2', '{"item_id":"ram_2","destination_id":"dimm_b2","orientation":"0"}'),
('fix_lock_latches', 'coc1_m2_p5', 'equipment_operation', 'close_dimm_latches', '{}'),
('post_start', 'coc1_m2_p5', 'test_started', 'coc1_m2_post', '{}'),
('post_done', 'coc1_m2_p5', 'test_completed', 'coc1_m2_post', '{}'),
('interpret', 'coc1_m2_p5', 'result_interpreted', 'coc1_m2_p5', '{"interpretation":"POST passed: CPU, dual-channel memory and the boot drive are detected."}');

create function pg_temp.m2_actions(variadic p_names text[])
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('phase_id', s.phase, 'action_type', s.kind,
      'target', s.target, 'value', s.value || jsonb_build_object('runtime_action_type', s.kind)) order by u.n), '[]'::jsonb)
  from unnest(p_names) with ordinality u(name, n) join m2_step s on s.name = u.name
$$;
create function pg_temp.m2_replay(p_actions jsonb)
returns jsonb language sql stable as $$
  select private.simulation_replay((select definition from m2_contract), p_actions)
$$;
create function pg_temp.post_reading(p_actions jsonb, p_check text)
returns boolean language sql stable as $$
  select public.practice_conditions_met(c->'requires', pg_temp.m2_replay(p_actions)->'state')
  from m2_contract, jsonb_array_elements(definition #> '{phases,4,presentation,equipment,checks}') c
  where c->>'id' = p_check
$$;

create temp table m2_run(name text primary key, actions jsonb) on commit drop;
insert into m2_run values
('prepare', pg_temp.m2_actions('inspect_case','inspect_board','inspect_cpu','inspect_cooler','inspect_ram',
  'inspect_psu','inspect_storage','wear_strap','ground_strap')),
('board_wrong_pair', pg_temp.m2_actions('open_lever','cpu','close_lever','compound','cooler','fan_cpu',
  'open_latches','ram1_a1','ram2_b1','lock_latches')),
('case', pg_temp.m2_actions('psu','screwdriver','fasten_psu','shield','board','fasten_board','drive','fasten_drive')),
('cables_no_eps', pg_temp.m2_actions('atx24','sata_power','sata_data','front_panel'));
insert into m2_run values
('mistakes', (select actions from m2_run where name='prepare') || (select actions from m2_run where name='board_wrong_pair')
  || (select actions from m2_run where name='case') || (select actions from m2_run where name='cables_no_eps')
  || pg_temp.m2_actions('post_start', 'post_done')),
('corrected', (select actions from m2_run where name='prepare') || (select actions from m2_run where name='board_wrong_pair')
  || (select actions from m2_run where name='case') || (select actions from m2_run where name='cables_no_eps')
  || pg_temp.m2_actions('post_start', 'post_done', 'eps8_fix', 'ram1_out', 'ram2_out', 'fix_open_latches',
     'fix_ram1_a2', 'fix_ram2_b2', 'fix_lock_latches', 'post_start', 'post_done', 'interpret'));

-- Contract identity and catalog.
select is((select version from public.practice_mission_contracts where mission_id = 'coc1_m2'),
  'css-assembly-20261119-v3', 'COC1 M2 publishes the assembly-bench contract');
select is((select jsonb_agg(p->>'primaryInteraction' order by n) from m2_contract,
    jsonb_array_elements(definition->'phases') with ordinality t(p, n)),
  '["inspect","place","place","connect","testRun","review"]'::jsonb, 'six bench phases with four interaction families');
select is((select title from public.missions where mission_code = 'coc1_m2'),
  'Install Internal Components', 'the catalog title is unchanged');
select is((select count(*)::integer from public.practice_mission_contracts where version = 'css-assembly-20261119-v3'),
  1, 'no other contract changed version');

-- Physically impossible actions are refused and counted against the part.
select is(pg_temp.m2_replay(pg_temp.m2_actions('cpu'))->'invalid', '{"item:cpu": 1}'::jsonb,
  'a processor cannot be seated under a closed load plate');
select is(pg_temp.m2_replay(pg_temp.m2_actions('open_lever', 'cpu_rotated', 'cpu'))->'invalid', '{"item:cpu": 1}'::jsonb,
  'a processor in the wrong orientation is refused');
select is(pg_temp.m2_replay(pg_temp.m2_actions('board', 'shield'))->'invalid', '{"item:io_shield": 1}'::jsonb,
  'the I/O shield cannot be fitted behind an installed motherboard');
select is(pg_temp.m2_replay(pg_temp.m2_actions('board', 'board_out', 'shield', 'board'))->'corrections',
  '{"item:motherboard": 1}'::jsonb, 'removing the motherboard to fit the shield is one correction');
select is(pg_temp.m2_replay(pg_temp.m2_actions('atx24_in_eps'))->'invalid', '{"connection:atx_24pin": 1}'::jsonb,
  'the 24-pin connector does not fit the 8-pin CPU header');
select is(pg_temp.m2_replay(pg_temp.m2_actions('board', 'screwdriver', 'fasten_board', 'board_out'))->'state'->'setting.board_fastened',
  'false'::jsonb, 'removing a fastened motherboard releases its screws');

-- Physically possible mistakes are accepted and surface at POST.
select ok((pg_temp.m2_replay((select actions from m2_run where name = 'mistakes'))->'done' ?& array['coc1_m2_p2', 'coc1_m2_p4']),
  'the wrong DIMM pair and a missing EPS cable do not block their phases');
select is((pg_temp.m2_replay((select actions from m2_run where name = 'mistakes'))->>'invalid_count')::integer, 0,
  'physically possible mistakes are not invalid actions');
select ok(not pg_temp.post_reading((select actions from m2_run where name = 'mistakes'), 'memory_channels'),
  'POST reports the memory channel fault');
select ok(not pg_temp.post_reading((select actions from m2_run where name = 'mistakes'), 'cpu_power'),
  'POST reports the missing CPU power');
select ok(pg_temp.post_reading((select actions from m2_run where name = 'mistakes'), 'boot_device'),
  'POST finds the boot drive when both SATA cables are connected');
select is((pg_temp.m2_replay((select actions from m2_run where name = 'mistakes'))->'state'->'result.coc1_m2_post'->>'operating'),
  'false', 'the first POST fails');

do $$
declare learner uuid := (select learner from m2_ctx); outcome text;
begin
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
  select learner, 'm2-mistakes-' || n, 'coc1_m2', x->>'phase_id', x->>'action_type', x->>'target', x->'value', now() - interval '40 minutes' + n * interval '20 seconds'
  from jsonb_array_elements((select actions from m2_run where name = 'mistakes')) with ordinality t(x, n);
  begin
    perform public.practice_verify_mission(learner, 'coc1_m2');
    outcome := 'verified';
  exception when sqlstate '22023' then
    outcome := sqlerrm;
  end;
  create temp table m2_outcome on commit drop as select outcome;
end $$;
select is((select outcome from m2_outcome), 'PRACTICE_WORK_INCOMPLETE:coc1_m2_p5',
  'the work is not verified while POST reports faults');

do $$
declare learner uuid := (select learner from m2_ctx);
begin
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
  values (learner, 'm2-discard', 'coc1_m2', 'coc1_m2_p1', 'practice_progress_discarded', null, '{}', now() - interval '20 minutes');
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
  select learner, 'm2-corrected-' || n, 'coc1_m2', x->>'phase_id', x->>'action_type', x->>'target', x->'value', now() - interval '19 minutes' + n * interval '10 seconds'
  from jsonb_array_elements((select actions from m2_run where name = 'corrected')) with ordinality t(x, n);
  perform public.practice_verify_mission(learner, 'coc1_m2');
end $$;
select is((select contract_version from public.practice_mission_completions
    where learner_id = (select learner from m2_ctx) and mission_id = 'coc1_m2'),
  'css-assembly-20261119-v3', 'correcting the assembly and retesting verifies the mission');
select is((select jsonb_build_object('outcome', outcome, 'invalid', invalid_count, 'corrections', correction_count)
    from public.practice_mission_runs where learner_id = (select learner from m2_ctx) and mission_id = 'coc1_m2'
    order by run_number desc limit 1),
  '{"outcome": "verified", "invalid": 0, "corrections": 0}'::jsonb,
  'reseating the memory the failed POST flagged is a repair, not a correction');

-- Fix rounds 1 and 2 (I2): the faults the first POST exposed still count
-- after they are fixed: once per step and run, charged to the step its
-- checks name; the reseats that fix the memory pair are the repair.
select is((select jsonb_build_object('failed', r->'failed_checks', 'repairs', r->'repair_corrections')
    from (select pg_temp.m2_replay((select actions from m2_run where name = 'corrected')) r) x),
  '{"failed": {"step:memory": 1, "step:power_cables": 1}, "repairs": {"item:ram_1": 1, "item:ram_2": 1}}'::jsonb,
  'the failed POST charges the memory and power-cable steps once and the reseats are repairs');
select is((select step_results->'coc1_m2_p5'->'failed_checks'
    from public.practice_mission_runs where learner_id = (select learner from m2_ctx) and mission_id = 'coc1_m2'
    order by run_number desc limit 1),
  '2'::jsonb, 'the practice run reports the POST faults as learning feedback');
select is((select jsonb_agg(c->>'counts' order by n) from m2_contract,
    jsonb_array_elements(definition #> '{phases,4,presentation,equipment,checks}') with ordinality t(c, n)),
  '["step:psu","step:board","step:drive","step:data_cables","step:power_cables","step:cpu","step:cooling","step:cooling","step:memory","step:memory","step:power_cables","step:data_cables"]'::jsonb,
  'every POST check charges its assessment step');

-- Fix round 1 (I3): practice saved for the v2 layout does not leak into v3.
-- The app writes a practice_progress_discarded marker when it starts the new
-- version; the earlier actions stay on the server but are not replayed.
create temp table m2_legacy_ctx (with_marker uuid not null default gen_random_uuid(),
  without_marker uuid not null default gen_random_uuid()) on commit drop;
insert into m2_legacy_ctx default values;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'authenticated', 'authenticated',
  'assembly-legacy-' || id || '@bytequest.invalid', '', '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Assembly bench legacy rollback learner"}'::jsonb, now(), now()
from m2_legacy_ctx cross join lateral (values (with_marker), (without_marker)) u(id);
do $$
declare learner uuid;
begin
  for learner in select with_marker from m2_legacy_ctx union all select without_marker from m2_legacy_ctx loop
    -- Three actions recorded by the v2 layout (card workspace, sequence panel).
    insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
    values
      (learner, 'v2-1', 'coc1_m2', 'coc1_m2_p2', 'component_drop_attempted', 'motherboard_area',
        '{"runtime_action_type":"placement_attempted","item_id":"motherboard","destination_id":"motherboard_area","compatible":true}', now() - interval '3 days'),
      (learner, 'v2-2', 'coc1_m2', 'coc1_m2_p2', 'component_drop_attempted', 'cpu_socket',
        '{"runtime_action_type":"placement_attempted","item_id":"cpu","destination_id":"cpu_socket","orientation":"aligned","compatible":true}', now() - interval '3 days'),
      (learner, 'v2-3', 'coc1_m2', 'coc1_m2_p3', 'connection_created', 'board_power',
        '{"runtime_action_type":"connection_created","source_id":"atx","destination_id":"board_power"}', now() - interval '3 days');
    if learner = (select with_marker from m2_legacy_ctx) then
      insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
      values (learner, 'v3-start', 'coc1_m2', 'coc1_m2_p1', 'practice_progress_discarded', null,
        '{"reason":"definition_updated","definition_version":"css-assembly-20261119-v3"}', now() - interval '30 minutes');
    end if;
    insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
    select learner, 'v3-' || n, 'coc1_m2', x->>'phase_id', x->>'action_type', x->>'target',
      x->'value' || '{"definition_version":"css-assembly-20261119-v3"}', now() - interval '20 minutes' + n * interval '10 seconds'
    from jsonb_array_elements((select actions from m2_run where name = 'corrected')) with ordinality t(x, n);
    perform public.practice_verify_mission(learner, 'coc1_m2');
  end loop;
end $$;
select is((select jsonb_build_object('outcome', outcome, 'invalid', invalid_count, 'actions', action_count)
    from public.practice_mission_runs where learner_id = (select with_marker from m2_legacy_ctx) and mission_id = 'coc1_m2'),
  jsonb_build_object('outcome', 'verified', 'invalid', 0,
    'actions', jsonb_array_length((select actions from m2_run where name = 'corrected'))),
  'after the version marker the v3 run replays only v3 actions');
select ok((select invalid_count >= 3 from public.practice_mission_runs
    where learner_id = (select without_marker from m2_legacy_ctx) and mission_id = 'coc1_m2'),
  'without the marker the v2 actions would be counted against the new layout');
select is((select count(*)::integer from public.practice_mission_actions
    where learner_id = (select with_marker from m2_legacy_ctx) and client_action_id like 'v2-%'),
  3, 'the v2 evidence is kept for audit');

-- Earlier verified COC1 M2 versions keep counting toward the COC1 quiz gate.
do $$
declare learner uuid := (select learner from m2_ctx); evidence bigint;
begin
  select max(id) into evidence from public.practice_mission_actions where learner_id = learner;
  insert into public.practice_mission_completions(learner_id, mission_id, contract_version, evidence_through_id)
  select learner, 'coc1_m' || n, case n when 1 then 'css-sag-20261109-v3' else 'css-sag-20261011-v2' end, evidence
  from generate_series(1, 5) n where n <> 2;
  update public.practice_mission_completions set contract_version = 'css-sag-20261011-v2'
    where learner_id = learner and mission_id = 'coc1_m2';
end $$;
select lives_ok(format('select public.practice_begin_quiz(%L::uuid, %L, gen_random_uuid(), %L::jsonb)',
    (select learner from m2_ctx), 'coc1',
    (select jsonb_agg(jsonb_build_object('id', 'q' || i, 'answer', 0)) from generate_series(1, 5) i)),
  'a verified css-sag-20261011-v2 COC1 M2 completion still opens the COC1 quiz');
update public.practice_mission_completions set contract_version = 'css-sag-20261009-v1'
  where learner_id = (select learner from m2_ctx) and mission_id = 'coc1_m2';
select ok((select count(*) = 5 from public.practice_mission_completions c
    where c.learner_id = (select learner from m2_ctx) and left(c.mission_id, 4) = 'coc1'
      and public.practice_completion_accepted(c.mission_id, c.contract_version)),
  'a verified css-sag-20261009-v1 COC1 M2 completion still counts');
update public.practice_mission_completions set contract_version = 'unsupported-version'
  where learner_id = (select learner from m2_ctx) and mission_id = 'coc1_m2';
select ok((select count(*) = 4 from public.practice_mission_completions c
    where c.learner_id = (select learner from m2_ctx) and left(c.mission_id, 4) = 'coc1'
      and public.practice_completion_accepted(c.mission_id, c.contract_version)),
  'an unknown COC1 M2 version does not count');

select * from finish();
rollback;
