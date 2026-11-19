-- Rollback-only: sequencing steps in a simulation assessment are answered
-- only by a confirmed order (re-defense slice A1, fix round 2, re-review N1).
--
-- The COC1 M3 package (boot-sequence step coc1_m3_p2) is published as the
-- publish script builds it, and one learner submits several attempts that
-- differ only in how the boot order is answered:
--   * a valid order that is never confirmed does not satisfy the step;
--   * two confirmed wrong orders, then the confirmed right one: satisfied
--     (2 of 2 allowed); three confirmed wrong orders: not satisfied;
--   * orders in progress before the confirmed answer are not counted;
--   * confirming the same wrong order again is not a new attempt;
--   * an assessment ignores a practice_progress_discarded marker (fix round 3,
--     N1): earlier wrong orders still count.
-- A class practice assignment of the same package keeps the practice rules:
-- a marker restarts its evaluation, and a valid order completes the step
-- without Confirm (fix round 3, N2).
-- The other phases follow the exported happy path without its single
-- prerequisite retry, so only the boot-order step changes between attempts.
--
-- The GENERATED blocks come from scripts/publish-simulation-assessments.mjs
-- (buildSimulationPackage for coc1_m3) and
-- dart run tool/export_practice_contracts.dart --replay-fixtures <file>.
begin;
select plan(13);

create temp table seq_ctx (
  admin uuid not null default gen_random_uuid(),
  instructor uuid not null default gen_random_uuid(),
  learner uuid not null default gen_random_uuid(),
  source uuid, module_version uuid, activity uuid, rubric uuid, class uuid, assignment uuid,
  practice_assignment uuid
) on commit drop;
insert into seq_ctx default values;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'authenticated', 'authenticated',
  'simulation-sequence-' || id || '@bytequest.invalid', '', '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Simulation sequence rollback fixture"}'::jsonb, now(), now()
from seq_ctx cross join lateral (values (admin), (instructor), (learner)) u(id);
update public.profiles set role = 'admin' where user_id = (select admin from seq_ctx);
update public.profiles set role = 'instructor' where user_id = (select instructor from seq_ctx);

-- BEGIN GENERATED CRITERIA (buildSimulationPackage, coc1_m3)
create temp table seq_criteria(criteria jsonb) on commit drop;
insert into seq_criteria values ('[{"criterion_code":"COC1_M3_S1","title":"Inspect and configure setup","description":"Place the equipment in the workspace, then complete the inspection and work-order checks. The boot console reports a blank GPT disk and UEFI media. Configure firmware and select the installation target.","source_trace":"LO1.2 Install operating system and drivers for peripherals/devices · PC 1.5, 2.1, 3.1 · TR Computer Systems Servicing NC II (Amended December 2013); ByteQuest supplementary simulation assessment, not an official TESDA certification.","evidence_rule":{"operator":"simulation_condition","phase_ids":["coc1_m3_p1"],"conditions":[{"path":"placed.system_unit","operator":"present"},{"path":"placed.boot_usb","operator":"present"}],"counted_targets":["phase:coc1_m3_p1","item:system_unit","item:boot_usb"],"max_incorrect":2},"scoring_rule":{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0,"classification":"TECHNICAL_BINARY_ENCODING","note":"1/0 encodes SATISFIED/NOT SATISFIED only; it is not a TESDA percentage or criterion weight."},"max_value":1,"order_index":1,"is_required":true},{"criterion_code":"COC1_M3_S2","title":"Install the operating system","description":"Sequence the installation operations before applying them.","source_trace":"LO1.2 Install operating system and drivers for peripherals/devices · PC 1.5, 2.1, 3.1 · TR Computer Systems Servicing NC II (Amended December 2013); ByteQuest supplementary simulation assessment, not an official TESDA certification.","evidence_rule":{"operator":"simulation_condition","phase_ids":["coc1_m3_p2"],"conditions":[{"path":"operation.install_os","value":true}],"counted_targets":["phase:coc1_m3_p2","operation:install_os","operation:prepare_boot_media"],"max_incorrect":2},"scoring_rule":{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0,"classification":"TECHNICAL_BINARY_ENCODING","note":"1/0 encodes SATISFIED/NOT SATISFIED only; it is not a TESDA percentage or criterion weight."},"max_value":1,"order_index":2,"is_required":true},{"criterion_code":"COC1_M3_S3","title":"Configure drivers and restart","description":"Select the adapter driver, apply configuration, and restart the installed system.","source_trace":"LO1.2 Install operating system and drivers for peripherals/devices · PC 1.5, 2.1, 3.1 · TR Computer Systems Servicing NC II (Amended December 2013); ByteQuest supplementary simulation assessment, not an official TESDA certification.","evidence_rule":{"operator":"simulation_condition","phase_ids":["coc1_m3_p3"],"conditions":[{"path":"operation.restart_workstation","value":true}],"counted_targets":["phase:coc1_m3_p3","operation:restart_workstation","operation:install_licensed_apps","operation:apply_vendor_updates"],"max_incorrect":2},"scoring_rule":{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0,"classification":"TECHNICAL_BINARY_ENCODING","note":"1/0 encodes SATISFIED/NOT SATISFIED only; it is not a TESDA percentage or criterion weight."},"max_value":1,"order_index":3,"is_required":true},{"criterion_code":"COC1_M3_S4","title":"Verify and interpret startup","description":"Run startup verification and interpret the boot and device statuses. Return to setup if a failure is reported.","source_trace":"LO1.2 Install operating system and drivers for peripherals/devices · PC 1.5, 2.1, 3.1 · TR Computer Systems Servicing NC II (Amended December 2013); ByteQuest supplementary simulation assessment, not an official TESDA certification.","evidence_rule":{"operator":"simulation_condition","phase_ids":["coc1_m3_p4"],"conditions":[{"path":"result.coc1_m3_test_4","value":true}],"counted_targets":["phase:coc1_m3_p4","operation:close_work_area","operation:prepare_service_report"],"max_incorrect":2},"scoring_rule":{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0,"classification":"TECHNICAL_BINARY_ENCODING","note":"1/0 encodes SATISFIED/NOT SATISFIED only; it is not a TESDA percentage or criterion weight."},"max_value":1,"order_index":4,"is_required":true}]'::jsonb);
-- END GENERATED CRITERIA

-- BEGIN GENERATED HAPPY PATH (coc1_m3)
create temp table replay_fixture(mission_id text, ordinal integer, phase_id text, action_type text,
  target text, value jsonb) on commit drop;
insert into replay_fixture(mission_id, ordinal, phase_id, action_type, target, value) values
('coc1_m3', 1, 'coc1_m3_p1', 'placement_attempted', 'system_unit_position', '{"item_id":"system_unit","destination_id":"system_unit_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m3', 2, 'coc1_m3_p1', 'placement_attempted', 'boot_usb_position', '{"item_id":"boot_usb","destination_id":"boot_usb_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m3', 3, 'coc1_m3_p1', 'configuration_applied', 'coc1_m3_p1', '{"values":{"boot_mode":"uefi","storage_mode":"ahci","install_target":"system_disk"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc1_m3', 4, 'coc1_m3_p2', 'sequence_reordered', 'coc1_m3_p2', '{"order":["boot_media","select_disk","copy_files","configure_device"],"confirmed":true,"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc1_m3', 5, 'coc1_m3_p2', 'equipment_operation', 'install_os', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 6, 'coc1_m3_p2', 'equipment_operation', 'prepare_boot_media', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 7, 'coc1_m3_p2', 'equipment_operation', 'install_os', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 8, 'coc1_m3_p2', 'equipment_operation', 'prepare_boot_media', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 9, 'coc1_m3_p3', 'configuration_applied', 'coc1_m3_p3', '{"values":{"network_driver":"ethernet"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc1_m3', 10, 'coc1_m3_p3', 'equipment_operation', 'restart_workstation', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 11, 'coc1_m3_p3', 'equipment_operation', 'install_licensed_apps', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 12, 'coc1_m3_p3', 'equipment_operation', 'apply_vendor_updates', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 13, 'coc1_m3_p3', 'equipment_operation', 'restart_workstation', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 14, 'coc1_m3_p3', 'equipment_operation', 'install_licensed_apps', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 15, 'coc1_m3_p3', 'equipment_operation', 'apply_vendor_updates', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 16, 'coc1_m3_p4', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 17, 'coc1_m3_p4', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m3', 18, 'coc1_m3_p4', 'test_started', 'coc1_m3_test_4', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc1_m3', 19, 'coc1_m3_p4', 'test_completed', 'coc1_m3_test_4', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc1_m3', 20, 'coc1_m3_p4', 'result_interpreted', 'coc1_m3_p4', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb);
-- END GENERATED HAPPY PATH

with s as (
  insert into public.tesda_sources(qualification_code, title, edition, source_reference, status,
    validation_notes, created_by, approved_by, approved_at, activated_by, activated_at)
  select 'ROLLBACK-' || left(gen_random_uuid()::text, 8), 'Rollback-only simulation sequence source',
    'TEST_ONLY', 'Rollback fixture; never a production TESDA source', 'active', 'TEST_ONLY_ROLLBACK_FIXTURE',
    admin, admin, now(), admin, now() from seq_ctx
  returning id)
update seq_ctx set source = s.id from s;
with m as (
  insert into public.module_versions(module_id, tesda_source_id, version_number, title, source_trace,
    content_metadata, status, created_by)
  select c.id, x.source, coalesce((select max(version_number) from public.module_versions mv where mv.module_id = c.id), 0) + 1,
    'Rollback simulation sequence module',
    jsonb_build_object('source_classification', 'TEST_ONLY', 'note', 'Rollback fixture'),
    jsonb_build_object('assessment_engine', 'simulation_replay_v1'), 'draft', x.admin
  from seq_ctx x cross join public.coc_modules c where c.coc_code = 'coc1'
  returning id)
update seq_ctx set module_version = m.id from m;
with a as (
  insert into public.activity_versions(mission_id, module_version_id, version_number, title, delivery_mode,
    learner_payload, evaluator_config, status, created_by)
  select ms.id, x.module_version,
    coalesce((select max(version_number) from public.activity_versions av where av.mission_id = ms.id), 0) + 1,
    'Install and Configure a Workstation OS — simulation assessment', 'assessment',
    jsonb_build_object('mission_id', 'coc1_m3', 'definition_version', c.version, 'mode', 'assessment'),
    jsonb_build_object('engine', 'simulation_replay_v1', 'simulation_definition', c.definition,
      'contract_version', c.version),
    'draft', x.admin
  from seq_ctx x
  cross join public.missions ms
  join public.practice_mission_contracts c on c.mission_id = ms.mission_code
  where ms.mission_code = 'coc1_m3'
  returning id)
update seq_ctx set activity = a.id from a;
with r as (
  insert into public.rubric_versions(activity_version_id, tesda_source_id, version_number, title, status, created_by)
  select activity, source, 1, 'COC1_M3 simulation step rubric', 'draft', admin from seq_ctx
  returning id)
update seq_ctx set rubric = r.id from r;
insert into public.rubric_criteria(rubric_version_id, criterion_code, title, description, source_trace,
  evidence_rule, scoring_rule, max_value, order_index, is_required)
select x.rubric, c->>'criterion_code', c->>'title', c->>'description', c->>'source_trace',
  c->'evidence_rule', c->'scoring_rule', (c->>'max_value')::numeric, (c->>'order_index')::integer,
  (c->>'is_required')::boolean
from seq_ctx x, seq_criteria s, jsonb_array_elements(s.criteria) c;

create temp table seq_failure(error text) on commit drop;
grant select on seq_ctx to authenticated;
grant insert on seq_failure to authenticated;
select set_config('request.jwt.claim.sub', (select admin::text from seq_ctx), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $$
begin
  perform public.publish_module_version((select module_version from seq_ctx), 'Rollback publication');
  perform public.publish_activity_version((select activity from seq_ctx), 'Rollback publication');
  perform public.approve_rubric_version((select rubric from seq_ctx), 'binary_sum',
    jsonb_build_object('status', 'APPROVED', 'method', 'all_required',
      'classification', 'PROJECT_APPROVED_OPERATIONAL_RULE', 'official_numeric_threshold', null),
    'Rollback approval of the generated simulation step rubric');
exception when others then
  insert into seq_failure values (sqlerrm);
end $$;
reset role;
select is((select coalesce(string_agg(error, '; '), 'none') from seq_failure), 'none',
  'the COC1 M3 package publishes and its rubric passes governed approval');

with c as (
  insert into public.classes(title, instructor_id, created_by)
  select 'Rollback simulation sequence class', instructor, instructor from seq_ctx returning id)
update seq_ctx set class = c.id from c;
insert into public.class_memberships(class_id, learner_id, enrolled_by)
select class, learner, instructor from seq_ctx;
with s as (
  insert into public.assignments(class_id, activity_version_id, rubric_version_id, assignment_type, title, assigned_by)
  select class, activity, rubric, 'assessment', 'COC1 M3 simulation assessment', instructor from seq_ctx
  returning id)
update seq_ctx set assignment = s.id from s;
with s as (
  insert into public.assignments(class_id, activity_version_id, rubric_version_id, assignment_type, title, assigned_by)
  select class, activity, rubric, 'practice', 'COC1 M3 class practice', instructor from seq_ctx
  returning id)
update seq_ctx set practice_assignment = s.id from s;

-- The boot-order answers. R is the right order; W1-W3 violate it.
create function pg_temp.seq_order(p_order text[], p_confirmed boolean)
returns jsonb language sql immutable as $$
  select jsonb_build_object('phase_id', 'coc1_m3_p2', 'action_type', 'sequence_reordered', 'target', 'coc1_m3_p2',
    'value', jsonb_build_object('order', to_jsonb(p_order), 'runtime_action_type', 'sequence_reordered')
      || case when p_confirmed then '{"confirmed": true}'::jsonb else '{}'::jsonb end)
$$;
create function pg_temp.right_order(p_confirmed boolean) returns jsonb language sql immutable as $$
  select pg_temp.seq_order(array['boot_media','select_disk','copy_files','configure_device'], p_confirmed) $$;
create function pg_temp.wrong_order(p_n integer) returns jsonb language sql immutable as $$
  select pg_temp.seq_order(case p_n
    when 1 then array['select_disk','boot_media','copy_files','configure_device']
    when 2 then array['boot_media','copy_files','select_disk','configure_device']
    else array['configure_device','copy_files','select_disk','boot_media'] end, true) $$;
-- The happy path around the boot-order answer, without its prerequisite
-- retry (ordinal 5 installs before the boot media is ready).
create function pg_temp.happy(p_from integer, p_to integer) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('phase_id', phase_id, 'action_type', action_type,
      'target', target, 'value', value) order by ordinal), '[]'::jsonb)
  from replay_fixture where ordinal between p_from and p_to and ordinal not in (4, 5, 8)
$$;
create function pg_temp.run(p_answer jsonb) returns jsonb language sql stable as $$
  select pg_temp.happy(1, 3) || p_answer || pg_temp.happy(6, 100)
$$;

create function pg_temp.marker() returns jsonb language sql immutable as $$
  select jsonb_build_object('phase_id', 'coc1_m3_p1', 'action_type', 'practice_progress_discarded', 'target', null,
    'value', '{"reason": "definition_updated"}'::jsonb) $$;

create temp table seq_run(name text primary key, actions jsonb, attempt uuid,
  practice boolean not null default false) on commit drop;
insert into seq_run(name, actions) values
('confirmed_right', pg_temp.run(jsonb_build_array(pg_temp.right_order(true)))),
('unconfirmed_right', pg_temp.run(jsonb_build_array(
    pg_temp.seq_order(array['select_disk','boot_media','copy_files','configure_device'], false),
    pg_temp.right_order(false)))),
('two_wrong_then_right', pg_temp.run(jsonb_build_array(pg_temp.wrong_order(1), pg_temp.wrong_order(2),
    pg_temp.right_order(true)))),
('three_wrong_then_right', pg_temp.run(jsonb_build_array(pg_temp.wrong_order(1), pg_temp.wrong_order(2),
    pg_temp.wrong_order(3), pg_temp.right_order(true)))),
('moves_then_right', pg_temp.run(jsonb_build_array(
    pg_temp.seq_order(array['select_disk','boot_media','copy_files','configure_device'], false),
    pg_temp.seq_order(array['boot_media','copy_files','select_disk','configure_device'], false),
    pg_temp.right_order(true)))),
('same_wrong_confirmed_repeatedly', pg_temp.run(jsonb_build_array(pg_temp.wrong_order(1), pg_temp.wrong_order(1),
    pg_temp.wrong_order(1), pg_temp.right_order(true)))),
('assessment_marker', jsonb_build_array(pg_temp.wrong_order(1), pg_temp.wrong_order(2), pg_temp.wrong_order(3),
    pg_temp.marker()) || pg_temp.run(jsonb_build_array(pg_temp.right_order(true))));
insert into seq_run(name, actions, practice) values
('practice_marker', jsonb_build_array(pg_temp.wrong_order(1), pg_temp.wrong_order(2), pg_temp.wrong_order(3),
    pg_temp.marker()) || pg_temp.run(jsonb_build_array(pg_temp.right_order(true))), true),
('practice_unconfirmed', pg_temp.run(jsonb_build_array(pg_temp.right_order(false))), true);
grant select, update on seq_run to authenticated;

select set_config('request.jwt.claim.sub', (select learner::text from seq_ctx), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $$
declare r record; v_attempt uuid; a jsonb; n integer;
begin
  for r in select name, actions, practice from seq_run order by name loop
    select id into v_attempt from public.start_attempt(
      case when r.practice then (select practice_assignment from seq_ctx) else (select assignment from seq_ctx) end,
      gen_random_uuid());
    n := 0;
    for a in select x from jsonb_array_elements(r.actions) x loop
      n := n + 1;
      perform public.append_attempt_action(v_attempt, n, a->>'action_type', a->>'target',
        (a->'value') || jsonb_build_object('phase_id', a->>'phase_id', 'mission_id', 'coc1_m3',
          'client_action_id', r.name || '-' || n),
        clock_timestamp());
    end loop;
    perform public.submit_attempt(v_attempt, gen_random_uuid(), 600);
    -- Class practice is not evaluated on submit; the learner may request it.
    if r.practice then
      perform public.evaluate_submitted_attempt(v_attempt);
    end if;
    update seq_run set attempt = v_attempt where name = r.name;
  end loop;
end $$;
reset role;

create function pg_temp.not_satisfied(p_run text)
returns text[] language sql stable as $$
  select coalesce(array_agg(rc.criterion_code order by rc.order_index), '{}')
  from public.criterion_results cr
  join public.rubric_criteria rc on rc.id = cr.rubric_criterion_id
  where cr.attempt_id = (select attempt from seq_run where name = p_run)
    and cr.observation <> 'satisfied'
$$;
create function pg_temp.step_incorrect(p_run text)
returns integer language sql stable as $$
  select (cr.observed_evidence->>'incorrect_total')::integer
  from public.criterion_results cr join public.rubric_criteria rc on rc.id = cr.rubric_criterion_id
  where cr.attempt_id = (select attempt from seq_run where name = p_run) and rc.criterion_code = 'COC1_M3_S2'
$$;

select is(pg_temp.not_satisfied('confirmed_right'), '{}'::text[],
  'a confirmed right boot order satisfies every step');
select is(pg_temp.not_satisfied('unconfirmed_right'), array['COC1_M3_S2'],
  'reordering without confirming, then advancing, does not satisfy the step');
select is(pg_temp.not_satisfied('two_wrong_then_right'), '{}'::text[],
  'two confirmed wrong orders, then the right one, stay within the threshold');
select is(pg_temp.step_incorrect('two_wrong_then_right'), 2,
  'each confirmed wrong order is one incorrect attempt');
select is(pg_temp.not_satisfied('three_wrong_then_right'), array['COC1_M3_S2'],
  'three confirmed wrong orders exceed the threshold');
select is(jsonb_build_object('failed', pg_temp.not_satisfied('moves_then_right'), 'incorrect', pg_temp.step_incorrect('moves_then_right')),
  jsonb_build_object('failed', '{}'::text[], 'incorrect', 0),
  'orders in progress before the confirmed answer are not incorrect attempts');
select is(jsonb_build_object('failed', pg_temp.not_satisfied('same_wrong_confirmed_repeatedly'),
    'incorrect', pg_temp.step_incorrect('same_wrong_confirmed_repeatedly')),
  jsonb_build_object('failed', '{}'::text[], 'incorrect', 1),
  'confirming the same wrong order again is not a new incorrect attempt');
select is(pg_temp.not_satisfied('assessment_marker'), array['COC1_M3_S2'],
  'an assessment ignores a discard marker: the three earlier wrong orders still count');
select is(pg_temp.step_incorrect('assessment_marker'), 3,
  'every recorded assessment action is evaluated');
select is(pg_temp.not_satisfied('practice_marker'), '{}'::text[],
  'a class practice attempt is evaluated from its latest discard marker');
select is(pg_temp.not_satisfied('practice_unconfirmed'), '{}'::text[],
  'class practice completes the step on a valid order without Confirm');
select is((select count(*)::integer from public.attempts where id in (select attempt from seq_run) and status = 'evaluated'),
  9, 'every attempt is evaluated');

select * from finish();
rollback;
