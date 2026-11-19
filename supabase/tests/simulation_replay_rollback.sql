-- Rollback-only regression for the shared simulation replay (slice A1.1).
--
-- 1. Parity: for every published practice contract, the server replay
--    reproduces the pre-refactor verifier (20261009090000, embedded below as
--    pg_temp.legacy_replay) on the Flutter happy path, and
--    practice_verify_mission returns the same outcome for a truncated and a
--    complete run.
-- 2. Extensions: invalid/correction counting, placement `requires`,
--    `placement_removed` with `removal_effects`, re-placement, optional
--    (`required: false`) items and sources, and a replay that never raises.
-- 3. Runs: verified and failed verifications are summarised in
--    practice_mission_runs; locked missions keep PRACTICE_COC_LOCKED.
--
-- The rows between the GENERATED markers come from
--   cd ByteQuest-Mobile-App
--   dart run tool/export_practice_contracts.dart --replay-fixtures <file>
begin;
select plan(104);

-- ---------------------------------------------------------------------------
-- Reference: the verifier loop exactly as published in 20261009090000
-- (lines 128-264), returning the replayed phase completion and state.
-- ---------------------------------------------------------------------------
create function pg_temp.legacy_replay(p_definition jsonb, p_actions jsonb)
returns jsonb language plpgsql as $$
declare contract_definition jsonb := p_definition; a record;
  phase jsonb; p jsonb; eq jsonb; panel jsonb; item jsonb; destination jsonb;
  field jsonb; v jsonb; state jsonb := '{"revision":0}'::jsonb; done jsonb := '{}'::jsonb;
  family text; kind text; key text; actual jsonb; valid boolean; terminal boolean;
  revision integer := 0;
begin
  for a in select x->>'phase_id' as phase_id, x->>'action_type' as action_type,
      x->>'target' as target, x->'value' as value
    from jsonb_array_elements(p_actions) with ordinality t(x, n) order by n loop
    select value into phase from jsonb_array_elements(contract_definition->'phases') where value->>'id'=a.phase_id;
    if phase is null then continue; end if;
    p := phase->'presentation'; eq := p->'equipment'; v := a.value;
    family := phase->>'primaryInteraction'; kind := coalesce(v->>'runtime_action_type',a.action_type);
    valid := true; terminal := false;
    case kind
    when 'object_inspected' then
      valid := exists(select 1 from jsonb_array_elements(contract_definition->'scene'->'objects') where value->>'id'=a.target);
      if valid then state := state || jsonb_build_object('inspected.'||a.target,true); end if;
      if family='inspect' then terminal := not exists(select 1 from jsonb_array_elements(p->'objects') o
        where coalesce(state->>('inspected.'||(o->>'id')),'false') <> 'true'); end if;
    when 'placement_attempted' then
      panel := coalesce(eq->'placement',p);
      select value into item from jsonb_array_elements(panel->'items') where value->>'id'=v->>'item_id';
      select value into destination from jsonb_array_elements(panel->'destinations') where value->>'id'=v->>'destination_id';
      valid := item is not null and destination is not null
        and coalesce(destination->'socket_categories',destination->'accepted_categories') @> jsonb_build_array(item->'category')
        and (item->>'seating_orientation' is null or item->>'seating_orientation'=v->>'orientation')
        and not exists(select 1 from jsonb_array_elements_text(coalesce(item->'requires_placements','[]')) x
          where state->('placed.'||x) is null)
        and not exists(select 1 from jsonb_each(state) s where s.key like 'placed.%'
          and s.key <> 'placed.'||(v->>'item_id') and s.value=v->'destination_id');
      if valid then state := state || jsonb_build_object('placed.'||(v->>'item_id'),v->'destination_id'); end if;
      if family='place' then terminal := not exists(select 1 from jsonb_array_elements(panel->'items') o
        where state->('placed.'||(o->>'id')) is null); end if;
    when 'connection_created' then
      panel := coalesce(eq->'connection',p);
      select value into item from jsonb_array_elements(panel->'sources') where value->>'id'=v->>'source_id';
      select value into destination from jsonb_array_elements(panel->'destinations') where value->>'id'=v->>'destination_id';
      valid := item is not null and destination is not null and item->>'id'<>destination->>'id'
        and (coalesce(item->'interfaces','[]')='[]' or item->'interfaces' @> jsonb_build_array(destination->'interface'));
      if valid then
        if eq->>'single_connection'='true' then
          select coalesce(jsonb_object_agg(s.key,s.value),'{}') into state from jsonb_each(state) s
            where left(s.key,length('link.'||(v->>'source_id')||'>')) <> 'link.'||(v->>'source_id')||'>';
        end if;
        state := state || jsonb_build_object('link.'||(v->>'source_id')||'>'||(v->>'destination_id'),true);
      end if;
      if family='connect' then terminal := not exists(select 1 from jsonb_array_elements(panel->'sources') o
        where not exists(select 1 from jsonb_each(state) s where s.key like 'link.'||(o->>'id')||'>%' and s.value='true')); end if;
    when 'configuration_applied' then
      panel := coalesce(eq->'configuration',p);
      for field in select value from jsonb_array_elements(panel->'fields') loop
        actual := v->'values'->(field->>'id'); key := actual #>> '{}';
        if actual is null or actual='null' or btrim(key)='' then valid := false;
        elsif field->>'type'='toggle' and jsonb_typeof(actual)<>'boolean' then valid := false;
        elsif field->>'type'='dropdown' and not exists(select 1 from jsonb_array_elements(field->'options') where value->'id'=actual) then valid := false;
        elsif field->>'format'='ipv4' and not (key ~ '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$'
          and not exists(select 1 from unnest(string_to_array(key,'.')) octet where octet::integer>255)) then valid:=false;
        elsif field->>'format'='port' and not (key ~ '^[0-9]{1,5}$' and key::integer between 1 and 65535) then valid:=false;
        end if;
        if actual is not null then state := state || jsonb_build_object('config.'||(field->>'id'),actual); end if;
      end loop;
      if state ? 'setting.restarted' then state := state || '{"setting.restarted":false}'; end if;
      if v->'values' ? 'service_control' then state:= state || jsonb_build_object('setting.service_running',v->'values'->>'service_control'<>'stop'); end if;
      terminal := family='configure' and valid;
    when 'sequence_reordered' then
      valid := jsonb_typeof(v->'order')='array' and
        jsonb_array_length(v->'order')=jsonb_array_length(p->'items')
        and not exists(select 1 from jsonb_array_elements(p->'items') o where not v->'order' @> jsonb_build_array(o->'id'))
        and not exists(select 1 from jsonb_array_elements(eq->'precedence') edge
          where (select ordinality from jsonb_array_elements_text(v->'order') with ordinality where value=edge->>'before')
            >= (select ordinality from jsonb_array_elements_text(v->'order') with ordinality where value=edge->>'after'));
      state := state || jsonb_build_object('sequence.'||a.phase_id,coalesce(valid,false),'order.'||a.phase_id,v->'order');
      terminal := family='sequence' and valid;
    when 'tool_attempted' then
      select value into item from jsonb_array_elements(coalesce(eq->'tools',p->'tools')) where value->>'id'=v->>'tool_id';
      select value into destination from jsonb_array_elements(coalesce(eq->'targets',p->'targets')) where value->>'id'=a.target;
      valid := item is not null and destination is not null and
        (coalesce(item->'compatible_categories','[]')='[]' or item->'compatible_categories' @> jsonb_build_array(destination->'category'));
      if valid then state:=state || jsonb_build_object('tool.'||a.target,v->'tool_id'); end if;
      terminal := family='tool' and valid;
    when 'selection_confirmed' then
      if v->>'selection_group' is not null then
        select value into panel from jsonb_array_elements(eq->'selection_groups') where value->>'id'=v->>'selection_group';
        key:='classification.'||(v->>'selection_group');
      else panel:=p; key:='selection.'||a.phase_id; end if;
      valid := panel is not null and jsonb_typeof(v->'selected_ids')='array' and jsonb_array_length(v->'selected_ids')>0
        and not exists(select 1 from jsonb_array_elements(v->'selected_ids') id where not exists(
          select 1 from jsonb_array_elements(coalesce(panel->'options',to_jsonb(array(select jsonb_build_object('id',x) from jsonb_array_elements_text(phase->'availableObjectIds') x)))) o where o->'id'=id));
      if valid then state:=state||jsonb_build_object(key,v->'selected_ids'); end if;
      terminal:=family='select' and valid and v->>'selection_group' is null;
    when 'scenario_decision' then
      select value into item from jsonb_array_elements(p->'choices') where value->>'id'=a.target;
      valid:=item is not null;
      if valid then
        state:=state||jsonb_build_object('decision.'||a.phase_id,a.target);
        for key,actual in select * from jsonb_each(coalesce(item->'equipment_effects','{}')) loop state:=state||jsonb_build_object('setting.'||key,actual); end loop;
      end if;
      terminal:=family='decide' and valid;
    when 'diagnostic_action' then
      select value into item from jsonb_array_elements(p->'diagnostic_actions') where value->>'id'=a.target;
      valid:=item is not null and public.practice_conditions_met(item->'requires',state);
      if valid then state:=state||jsonb_build_object('fact.'||(item->>'reveals_fact_id'),true); end if;
      terminal:=family='troubleshoot' and not exists(select 1 from jsonb_array_elements_text(p->'required_fact_ids') f where state->('fact.'||f)<>'true' or state->('fact.'||f) is null);
    when 'equipment_operation' then
      select value into item from jsonb_array_elements(eq->'operations') where value->>'id'=a.target;
      valid:=item is not null and public.practice_conditions_met(item->'requires',state);
      if valid then
        for key,actual in select * from jsonb_each(coalesce(item->'effects','{}')) loop state:=state||jsonb_build_object('setting.'||key,actual); end loop;
        state:=state||jsonb_build_object('operation.'||a.target,true);
      end if;
    when 'test_started' then
      valid:=a.target=coalesce(p->>'target',a.phase_id);
      if valid then state:=state||jsonb_build_object('test_started.'||a.target,true); end if;
    when 'test_completed' then
      valid:=a.target=coalesce(p->>'target',a.phase_id) and state->>('test_started.'||a.target)='true';
      if valid then
        terminal:=jsonb_array_length(eq->'checks')>0 and not exists(select 1 from jsonb_array_elements(eq->'checks') c where not public.practice_conditions_met(c->'requires',state));
        state:=state||jsonb_build_object('result.'||a.target,jsonb_build_object('operating',terminal,'revision',revision));
        if p->>'test_reveals_fact_id' is not null then state:=state||jsonb_build_object('fact.'||(p->>'test_reveals_fact_id'),true); end if;
        terminal:=family='testRun' and (coalesce(p->>'requires_interpretation','false')='false');
      end if;
    when 'observation_recorded' then
      valid:=length(btrim(v->>'observation'))>0 and a.target=a.phase_id;
      if valid then state:=state||jsonb_build_object('observation.'||a.phase_id,v->'observation'); end if;
      terminal:=family='observe' and valid;
    when 'result_interpreted' then
      valid:=length(btrim(v->>'interpretation'))>0 and a.target=a.phase_id;
      if valid then state:=state||jsonb_build_object('interpretation.'||a.phase_id,v->'interpretation'); end if;
      terminal:=valid and (family='interpret' or family='testRun' and state ? ('result.'||coalesce(p->>'target',a.phase_id)));
    else continue;
    end case;
    if (coalesce(valid,false) or kind='configuration_applied') and kind in ('connection_created','configuration_applied','placement_attempted','sequence_reordered','scenario_decision','selection_confirmed','equipment_operation','tool_attempted') then
      revision:=revision+1; state:=state||jsonb_build_object('revision',revision);
    end if;
    if not coalesce(valid,false) and
       (kind='configuration_applied' and family='configure' or kind='sequence_reordered' and family='sequence') then
      done:=done-a.phase_id;
    elsif coalesce(valid,false) and terminal then
      done:=done||jsonb_build_object(a.phase_id,true);
    end if;
  end loop;
  return jsonb_build_object('done', done, 'state', state);
end $$;

create function pg_temp.legacy_outcome(p_definition jsonb, p_actions jsonb)
returns text language plpgsql as $$
declare replayed jsonb := pg_temp.legacy_replay(p_definition, p_actions); phase jsonb;
begin
  for phase in select value from jsonb_array_elements(p_definition->'phases') loop
    if phase->>'primaryInteraction'='review' then continue; end if;
    if coalesce(replayed->'done'->>(phase->>'id'),'false')<>'true'
      or not public.practice_conditions_met(phase->'presentation'->'equipment'->'completion', replayed->'state') then
      return 'PRACTICE_WORK_INCOMPLETE:'||(phase->>'id');
    end if;
  end loop;
  if jsonb_array_length(p_actions) = 0 then return 'PRACTICE_EVIDENCE_REQUIRED'; end if;
  return 'verified';
end $$;

-- ---------------------------------------------------------------------------
-- Happy-path evidence exported from the Flutter work-order driver.
-- ---------------------------------------------------------------------------
create temp table replay_fixture (
  mission_id text not null, ordinal integer not null, phase_id text not null,
  action_type text not null, target text, value jsonb not null,
  primary key (mission_id, ordinal)
) on commit drop;

-- BEGIN GENERATED REPLAY FIXTURES
-- Generated by tool/export_practice_contracts.dart --replay-fixtures.
insert into replay_fixture(mission_id, ordinal, phase_id, action_type, target, value) values
('coc1_m1', 1, 'coc1_m1_p1', 'object_inspected', 'motherboard', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 2, 'coc1_m1_p1', 'object_inspected', 'cpu', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 3, 'coc1_m1_p1', 'object_inspected', 'ram', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 4, 'coc1_m1_p1', 'object_inspected', 'psu', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 5, 'coc1_m1_p1', 'object_inspected', 'cpu_socket', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 6, 'coc1_m1_p1', 'object_inspected', 'dimm_slot', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 7, 'coc1_m1_p1', 'object_inspected', 'atx_power_port', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m1', 8, 'coc1_m1_p2', 'tool_attempted', 'chassis_ground', '{"tool_id":"anti_static_strap","runtime_action_type":"tool_attempted"}'::jsonb),
('coc1_m1', 9, 'coc1_m1_p2', 'tool_attempted', 'case_fastener', '{"tool_id":"screwdriver","runtime_action_type":"tool_attempted"}'::jsonb),
('coc1_m1', 10, 'coc1_m1_p2', 'selection_confirmed', 'coc1_m1_p2_processing', '{"selection_group":"processing","selected_ids":["cpu"],"runtime_action_type":"selection_confirmed"}'::jsonb),
('coc1_m1', 11, 'coc1_m1_p2', 'selection_confirmed', 'coc1_m1_p2_memory', '{"selection_group":"memory","selected_ids":["ram"],"runtime_action_type":"selection_confirmed"}'::jsonb),
('coc1_m1', 12, 'coc1_m1_p2', 'selection_confirmed', 'coc1_m1_p2_power', '{"selection_group":"power","selected_ids":["psu"],"runtime_action_type":"selection_confirmed"}'::jsonb),
('coc1_m1', 13, 'coc1_m1_p2', 'selection_confirmed', 'coc1_m1_p2', '{"selected_ids":["esd_protection","open_memory_latch"],"runtime_action_type":"selection_confirmed"}'::jsonb),
('coc1_m1', 14, 'coc1_m1_p3', 'observation_recorded', 'coc1_m1_p3', '{"observation":"Inspected indicators and documented the observed operating condition.","runtime_action_type":"observation_recorded"}'::jsonb),
('coc1_m1', 15, 'coc1_m1_p4', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m1', 16, 'coc1_m1_p4', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m1', 17, 'coc1_m1_p4', 'test_started', 'coc1_m1_test_4', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc1_m1', 18, 'coc1_m1_p4', 'test_completed', 'coc1_m1_test_4', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc1_m2', 1, 'coc1_m2_p1', 'object_inspected', 'system_case', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 2, 'coc1_m2_p1', 'object_inspected', 'motherboard', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 3, 'coc1_m2_p1', 'object_inspected', 'cpu', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 4, 'coc1_m2_p1', 'object_inspected', 'cooler', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 5, 'coc1_m2_p1', 'object_inspected', 'ram', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 6, 'coc1_m2_p1', 'object_inspected', 'psu', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 7, 'coc1_m2_p1', 'object_inspected', 'storage', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m2', 8, 'coc1_m2_p1', 'equipment_operation', 'wear_wrist_strap', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 9, 'coc1_m2_p1', 'equipment_operation', 'ground_wrist_strap', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 10, 'coc1_m2_p2', 'equipment_operation', 'open_cpu_lever', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 11, 'coc1_m2_p2', 'placement_attempted', 'cpu_socket', '{"item_id":"cpu","destination_id":"cpu_socket","orientation":"0","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 12, 'coc1_m2_p2', 'equipment_operation', 'close_cpu_lever', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 13, 'coc1_m2_p2', 'equipment_operation', 'apply_thermal_compound', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 14, 'coc1_m2_p2', 'placement_attempted', 'cooler_mount', '{"item_id":"cooler","destination_id":"cooler_mount","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 15, 'coc1_m2_p2', 'connection_created', 'cpu_fan_header', '{"source_id":"cooler_fan","destination_id":"cpu_fan_header","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m2', 16, 'coc1_m2_p2', 'equipment_operation', 'open_dimm_latches', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 17, 'coc1_m2_p2', 'placement_attempted', 'dimm_a2', '{"item_id":"ram_1","destination_id":"dimm_a2","orientation":"0","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 18, 'coc1_m2_p2', 'placement_attempted', 'dimm_b2', '{"item_id":"ram_2","destination_id":"dimm_b2","orientation":"0","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 19, 'coc1_m2_p2', 'equipment_operation', 'close_dimm_latches', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 20, 'coc1_m2_p3', 'placement_attempted', 'psu_bay', '{"item_id":"psu","destination_id":"psu_bay","orientation":"0","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 21, 'coc1_m2_p3', 'equipment_operation', 'pick_screwdriver', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 22, 'coc1_m2_p3', 'equipment_operation', 'fasten_psu', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 23, 'coc1_m2_p3', 'placement_attempted', 'io_cutout', '{"item_id":"io_shield","destination_id":"io_cutout","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 24, 'coc1_m2_p3', 'placement_attempted', 'board_standoffs', '{"item_id":"motherboard","destination_id":"board_standoffs","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 25, 'coc1_m2_p3', 'equipment_operation', 'fasten_motherboard', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 26, 'coc1_m2_p3', 'placement_attempted', 'drive_bay', '{"item_id":"storage","destination_id":"drive_bay","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m2', 27, 'coc1_m2_p3', 'equipment_operation', 'fasten_drive', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m2', 28, 'coc1_m2_p4', 'connection_created', 'board_atx24', '{"source_id":"atx_24pin","destination_id":"board_atx24","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m2', 29, 'coc1_m2_p4', 'connection_created', 'board_eps8', '{"source_id":"eps_8pin","destination_id":"board_eps8","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m2', 30, 'coc1_m2_p4', 'connection_created', 'drive_power', '{"source_id":"sata_power","destination_id":"drive_power","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m2', 31, 'coc1_m2_p4', 'connection_created', 'drive_data', '{"source_id":"sata_data","destination_id":"drive_data","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m2', 32, 'coc1_m2_p4', 'connection_created', 'board_front_panel', '{"source_id":"front_panel","destination_id":"board_front_panel","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m2', 33, 'coc1_m2_p5', 'test_started', 'coc1_m2_post', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc1_m2', 34, 'coc1_m2_p5', 'test_completed', 'coc1_m2_post', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc1_m2', 35, 'coc1_m2_p5', 'result_interpreted', 'coc1_m2_p5', '{"interpretation":"POST passed: CPU, dual-channel memory, CPU fan and boot drive detected; the system is ready for OS installation.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc1_m3', 1, 'coc1_m3_p1', 'placement_attempted', 'system_unit_position', '{"item_id":"system_unit","destination_id":"system_unit_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m3', 2, 'coc1_m3_p1', 'placement_attempted', 'boot_usb_position', '{"item_id":"boot_usb","destination_id":"boot_usb_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m3', 3, 'coc1_m3_p1', 'configuration_applied', 'coc1_m3_p1', '{"values":{"boot_mode":"uefi","storage_mode":"ahci","install_target":"system_disk"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc1_m3', 4, 'coc1_m3_p2', 'sequence_reordered', 'coc1_m3_p2', '{"order":["boot_media","select_disk","copy_files","configure_device"],"runtime_action_type":"sequence_reordered"}'::jsonb),
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
('coc1_m3', 20, 'coc1_m3_p4', 'result_interpreted', 'coc1_m3_p4', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc1_m4', 1, 'coc1_m4_p1', 'placement_attempted', 'monitor_position', '{"item_id":"monitor","destination_id":"monitor_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m4', 2, 'coc1_m4_p1', 'placement_attempted', 'keyboard_position', '{"item_id":"keyboard","destination_id":"keyboard_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m4', 3, 'coc1_m4_p1', 'placement_attempted', 'mouse_position', '{"item_id":"mouse","destination_id":"mouse_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m4', 4, 'coc1_m4_p1', 'object_inspected', 'system_unit', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m4', 5, 'coc1_m4_p1', 'object_inspected', 'monitor', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m4', 6, 'coc1_m4_p1', 'object_inspected', 'keyboard', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m4', 7, 'coc1_m4_p1', 'object_inspected', 'mouse', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m4', 8, 'coc1_m4_p1', 'object_inspected', 'network_adapter', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc1_m4', 9, 'coc1_m4_p2', 'tool_attempted', 'monitor', '{"tool_id":"interface_inspection_light","runtime_action_type":"tool_attempted"}'::jsonb),
('coc1_m4', 10, 'coc1_m4_p2', 'tool_attempted', 'network_adapter', '{"tool_id":"interface_inspection_light","runtime_action_type":"tool_attempted"}'::jsonb),
('coc1_m4', 11, 'coc1_m4_p3', 'configuration_applied', 'coc1_m4_p3', '{"values":{"display_resolution":"1920x1080","address_mode":"automatic"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc1_m4', 12, 'coc1_m4_p3', 'connection_created', 'hdmi_port', '{"source_id":"monitor","destination_id":"hdmi_port","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m4', 13, 'coc1_m4_p3', 'connection_created', 'usb_port', '{"source_id":"keyboard","destination_id":"usb_port","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m4', 14, 'coc1_m4_p3', 'connection_created', 'usb_port', '{"source_id":"mouse","destination_id":"usb_port","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m4', 15, 'coc1_m4_p3', 'connection_created', 'ethernet_port', '{"source_id":"network_adapter","destination_id":"ethernet_port","runtime_action_type":"connection_created"}'::jsonb),
('coc1_m4', 16, 'coc1_m4_p4', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m4', 17, 'coc1_m4_p4', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m4', 18, 'coc1_m4_p4', 'test_started', 'peripheral_device_test', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc1_m4', 19, 'coc1_m4_p4', 'test_completed', 'peripheral_device_test', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc1_m4', 20, 'coc1_m4_p4', 'result_interpreted', 'coc1_m4_p4', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc1_m5', 1, 'coc1_m5_p1', 'placement_attempted', 'system_unit_position', '{"item_id":"system_unit","destination_id":"system_unit_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m5', 2, 'coc1_m5_p1', 'placement_attempted', 'storage_position', '{"item_id":"storage","destination_id":"storage_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc1_m5', 3, 'coc1_m5_p1', 'diagnostic_action', 'inspect_startup_indicators', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc1_m5', 4, 'coc1_m5_p2', 'tool_attempted', 'storage', '{"tool_id":"firmware_inventory","runtime_action_type":"tool_attempted"}'::jsonb),
('coc1_m5', 5, 'coc1_m5_p2', 'diagnostic_action', 'open_storage_inventory', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc1_m5', 6, 'coc1_m5_p3', 'diagnostic_action', 'inspect_device_status', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc1_m5', 7, 'coc1_m5_p3', 'diagnostic_action', 'run_subsystem_probe', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc1_m5', 8, 'coc1_m5_p3', 'diagnostic_action', 'inspect_connection_log', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc1_m5', 9, 'coc1_m5_p4', 'scenario_decision', 'replace_storage_cable', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc1_m5', 10, 'coc1_m5_p5', 'equipment_operation', 'run_monitored_stress_test', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m5', 11, 'coc1_m5_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m5', 12, 'coc1_m5_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc1_m5', 13, 'coc1_m5_p5', 'test_started', 'retest_integration', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc1_m5', 14, 'coc1_m5_p5', 'test_completed', 'retest_integration', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m1', 1, 'coc2_m1_p1', 'placement_attempted', 'copper_cable_position', '{"item_id":"copper_cable","destination_id":"copper_cable_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m1', 2, 'coc2_m1_p1', 'placement_attempted', 'rj45_connector_position', '{"item_id":"rj45_connector","destination_id":"rj45_connector_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m1', 3, 'coc2_m1_p1', 'placement_attempted', 'lan_cable_tester_position', '{"item_id":"lan_cable_tester","destination_id":"lan_cable_tester_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m1', 4, 'coc2_m1_p1', 'tool_attempted', 'copper_cable', '{"tool_id":"wire_stripper","runtime_action_type":"tool_attempted"}'::jsonb),
('coc2_m1', 5, 'coc2_m1_p1', 'tool_attempted', 'rj45_connector', '{"tool_id":"crimping_tool","runtime_action_type":"tool_attempted"}'::jsonb),
('coc2_m1', 6, 'coc2_m1_p2', 'tool_attempted', 'copper_cable', '{"tool_id":"crimping_tool","runtime_action_type":"tool_attempted"}'::jsonb),
('coc2_m1', 7, 'coc2_m1_p2', 'tool_attempted', 'lan_cable_tester', '{"tool_id":"lan_cable_tester","runtime_action_type":"tool_attempted"}'::jsonb),
('coc2_m1', 8, 'coc2_m1_p3', 'configuration_applied', 'coc2_m1_p3', '{"values":{"cable_route":"protected_design_route","raceway_material":"pvc"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m1', 9, 'coc2_m1_p3', 'sequence_reordered', 'coc2_m1_p3', '{"order":["measure","strip","arrange","terminate","inspect"],"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc2_m1', 10, 'coc2_m1_p4', 'connection_created', 'lan_cable_tester', '{"source_id":"copper_cable","destination_id":"lan_cable_tester","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m1', 11, 'coc2_m1_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m1', 12, 'coc2_m1_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m1', 13, 'coc2_m1_p5', 'test_started', 'coc2_m1_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m1', 14, 'coc2_m1_p5', 'test_completed', 'coc2_m1_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m1', 15, 'coc2_m1_p5', 'result_interpreted', 'coc2_m1_p5', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc2_m2', 1, 'coc2_m2_p1', 'placement_attempted', 'copper_cable_position', '{"item_id":"copper_cable","destination_id":"copper_cable_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m2', 2, 'coc2_m2_p1', 'placement_attempted', 'switch_position', '{"item_id":"switch","destination_id":"switch_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m2', 3, 'coc2_m2_p1', 'placement_attempted', 'router_position', '{"item_id":"router","destination_id":"router_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m2', 4, 'coc2_m2_p1', 'configuration_applied', 'coc2_m2_p1', '{"values":{"ppe_prepared":true,"termination_tool":"crimping_tool"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m2', 5, 'coc2_m2_p2', 'sequence_reordered', 'coc2_m2_p2', '{"order":["white_orange","orange","white_green","blue","white_blue","green","white_brown","brown"],"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc2_m2', 6, 'coc2_m2_p3', 'connection_created', 'switch', '{"source_id":"workstation","destination_id":"switch","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m2', 7, 'coc2_m2_p3', 'connection_created', 'router', '{"source_id":"switch","destination_id":"router","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m2', 8, 'coc2_m2_p4', 'configuration_applied', 'coc2_m2_p4', '{"values":{"workstation_interface":"ethernet_auto","physical_link_inspected":true},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m2', 9, 'coc2_m2_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m2', 10, 'coc2_m2_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m2', 11, 'coc2_m2_p5', 'test_started', 'coc2_m2_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m2', 12, 'coc2_m2_p5', 'test_completed', 'coc2_m2_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m2', 13, 'coc2_m2_p5', 'result_interpreted', 'coc2_m2_p5', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc2_m3', 1, 'coc2_m3_p1', 'placement_attempted', 'router_position', '{"item_id":"router","destination_id":"router_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m3', 2, 'coc2_m3_p1', 'placement_attempted', 'switch_position', '{"item_id":"switch","destination_id":"switch_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m3', 3, 'coc2_m3_p1', 'placement_attempted', 'workstation_a_position', '{"item_id":"workstation_a","destination_id":"workstation_a_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m3', 4, 'coc2_m3_p1', 'placement_attempted', 'workstation_b_position', '{"item_id":"workstation_b","destination_id":"workstation_b_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m3', 5, 'coc2_m3_p1', 'placement_attempted', 'server_position', '{"item_id":"server","destination_id":"server_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m3', 6, 'coc2_m3_p1', 'selection_confirmed', 'coc2_m3_p1', '{"selected_ids":["router","switch","workstation_a","workstation_b","server"],"runtime_action_type":"selection_confirmed"}'::jsonb),
('coc2_m3', 7, 'coc2_m3_p2', 'connection_created', 'switch', '{"source_id":"router","destination_id":"switch","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m3', 8, 'coc2_m3_p2', 'connection_created', 'server', '{"source_id":"switch","destination_id":"server","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m3', 9, 'coc2_m3_p2', 'connection_created', 'switch', '{"source_id":"workstation_a","destination_id":"switch","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m3', 10, 'coc2_m3_p2', 'connection_created', 'switch', '{"source_id":"workstation_b","destination_id":"switch","runtime_action_type":"connection_created"}'::jsonb),
('coc2_m3', 11, 'coc2_m3_p3', 'test_started', 'coc2_m3_test_3', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m3', 12, 'coc2_m3_p3', 'test_completed', 'coc2_m3_test_3', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m3', 13, 'coc2_m3_p4', 'scenario_decision', 'replace_link_segment', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc2_m3', 14, 'coc2_m3_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m3', 15, 'coc2_m3_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m3', 16, 'coc2_m3_p5', 'test_started', 'coc2_m3_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m3', 17, 'coc2_m3_p5', 'test_completed', 'coc2_m3_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m4', 1, 'coc2_m4_p1', 'placement_attempted', 'router_position', '{"item_id":"router","destination_id":"router_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m4', 2, 'coc2_m4_p1', 'placement_attempted', 'switch_position', '{"item_id":"switch","destination_id":"switch_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m4', 3, 'coc2_m4_p1', 'placement_attempted', 'repeater_position', '{"item_id":"repeater","destination_id":"repeater_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m4', 4, 'coc2_m4_p1', 'configuration_applied', 'coc2_m4_p1', '{"values":{"device_context":"managed_switch"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m4', 5, 'coc2_m4_p2', 'configuration_applied', 'coc2_m4_p2', '{"values":{"interface_address":"192.168.10.2","subnet_mask":"255.255.255.0","default_gateway":"192.168.10.1","wireless_ssid":"BQ-LAB","wireless_security":"wpa2_aes","wan_mode":"dhcp","firewall_policy":"deny_unsolicited","repeater_mode":"bridge"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m4', 6, 'coc2_m4_p3', 'test_started', 'coc2_m4_test_3', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m4', 7, 'coc2_m4_p3', 'test_completed', 'coc2_m4_test_3', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m4', 8, 'coc2_m4_p4', 'result_interpreted', 'coc2_m4_p4', '{"interpretation":"The measured outputs isolate the service path; correction and retest are recorded.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc2_m4', 9, 'coc2_m4_p5', 'configuration_applied', 'coc2_m4_p5', '{"values":{"interface_address":"192.168.10.2","subnet_mask":"255.255.255.0","default_gateway":"192.168.10.1","wireless_ssid":"BQ-LAB","wireless_security":"wpa2_aes","wan_mode":"dhcp","firewall_policy":"deny_unsolicited","repeater_mode":"bridge"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m4', 10, 'coc2_m4_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m4', 11, 'coc2_m4_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m4', 12, 'coc2_m4_p5', 'test_started', 'coc2_m4_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m4', 13, 'coc2_m4_p5', 'test_completed', 'coc2_m4_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m4', 14, 'coc2_m4_p5', 'result_interpreted', 'coc2_m4_p5', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc2_m5', 1, 'coc2_m5_p1', 'placement_attempted', 'workstation_position', '{"item_id":"workstation","destination_id":"workstation_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m5', 2, 'coc2_m5_p1', 'placement_attempted', 'switch_position', '{"item_id":"switch","destination_id":"switch_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc2_m5', 3, 'coc2_m5_p1', 'diagnostic_action', 'inspect_visible_topology', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc2_m5', 4, 'coc2_m5_p1', 'diagnostic_action', 'inspect_recorded_address', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc2_m5', 5, 'coc2_m5_p2', 'test_started', 'coc2_m5_test_2', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m5', 6, 'coc2_m5_p2', 'test_completed', 'coc2_m5_test_2', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc2_m5', 7, 'coc2_m5_p3', 'diagnostic_action', 'inspect_link_state', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc2_m5', 8, 'coc2_m5_p3', 'diagnostic_action', 'inspect_interface_config', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc2_m5', 9, 'coc2_m5_p3', 'diagnostic_action', 'run_route_probe', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc2_m5', 10, 'coc2_m5_p4', 'configuration_applied', 'coc2_m5_p4', '{"values":{"interface_address":"192.168.10.24","subnet_mask":"255.255.255.0","default_gateway":"192.168.10.1"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc2_m5', 11, 'coc2_m5_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m5', 12, 'coc2_m5_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc2_m5', 13, 'coc2_m5_p5', 'test_started', 'retest_network_path', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc2_m5', 14, 'coc2_m5_p5', 'test_completed', 'retest_network_path', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc3_m1', 1, 'coc3_m1_p1', 'placement_attempted', 'server_node_position', '{"item_id":"server_node","destination_id":"server_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m1', 2, 'coc3_m1_p1', 'placement_attempted', 'client_node_position', '{"item_id":"client_node","destination_id":"client_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m1', 3, 'coc3_m1_p1', 'placement_attempted', 'server_switch_position', '{"item_id":"server_switch","destination_id":"server_switch_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m1', 4, 'coc3_m1_p1', 'connection_created', 'server_switch', '{"source_id":"server_node","destination_id":"server_switch","runtime_action_type":"connection_created"}'::jsonb),
('coc3_m1', 5, 'coc3_m1_p1', 'connection_created', 'server_switch', '{"source_id":"client_node","destination_id":"server_switch","runtime_action_type":"connection_created"}'::jsonb),
('coc3_m1', 6, 'coc3_m1_p1', 'object_inspected', 'server_chassis', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m1', 7, 'coc3_m1_p1', 'object_inspected', 'network_drop', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m1', 8, 'coc3_m1_p1', 'object_inspected', 'power_conditioner', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m1', 9, 'coc3_m1_p1', 'object_inspected', 'installation_media', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m1', 10, 'coc3_m1_p1', 'object_inspected', 'setup_document', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m1', 11, 'coc3_m1_p2', 'scenario_decision', 'record_server_requirements', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc3_m1', 12, 'coc3_m1_p3', 'scenario_decision', 'file_service', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc3_m1', 13, 'coc3_m1_p4', 'sequence_reordered', 'coc3_m1_p4', '{"order":["power","network","capacity","media"],"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc3_m1', 14, 'coc3_m1_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m1', 15, 'coc3_m1_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m1', 16, 'coc3_m1_p5', 'test_started', 'coc3_m1_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc3_m1', 17, 'coc3_m1_p5', 'test_completed', 'coc3_m1_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc3_m2', 1, 'coc3_m2_p1', 'placement_attempted', 'server_node_position', '{"item_id":"server_node","destination_id":"server_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m2', 2, 'coc3_m2_p1', 'placement_attempted', 'client_node_position', '{"item_id":"client_node","destination_id":"client_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m2', 3, 'coc3_m2_p1', 'configuration_applied', 'coc3_m2_p1', '{"values":{"server_role":"file_service","host_name":"BQ-FS01","management_address":"192.168.30.10"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc3_m2', 4, 'coc3_m2_p2', 'sequence_reordered', 'coc3_m2_p2', '{"order":["validate","partition","install","role"],"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc3_m2', 5, 'coc3_m2_p3', 'scenario_decision', 'restart_after_configuration', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc3_m2', 6, 'coc3_m2_p4', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m2', 7, 'coc3_m2_p4', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m2', 8, 'coc3_m2_p4', 'test_started', 'coc3_m2_test_4', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc3_m2', 9, 'coc3_m2_p4', 'test_completed', 'coc3_m2_test_4', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc3_m3', 1, 'coc3_m3_p1', 'placement_attempted', 'server_node_position', '{"item_id":"server_node","destination_id":"server_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m3', 2, 'coc3_m3_p1', 'placement_attempted', 'client_node_position', '{"item_id":"client_node","destination_id":"client_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m3', 3, 'coc3_m3_p1', 'configuration_applied', 'coc3_m3_p1', '{"values":{"account_name":"technician","group_assignment":"support","resource_permission":"modify"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc3_m3', 4, 'coc3_m3_p2', 'test_started', 'coc3_m3_test_2', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc3_m3', 5, 'coc3_m3_p2', 'test_completed', 'coc3_m3_test_2', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc3_m3', 6, 'coc3_m3_p3', 'diagnostic_action', 'inspect_group_membership', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m3', 7, 'coc3_m3_p3', 'diagnostic_action', 'inspect_effective_permission', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m3', 8, 'coc3_m3_p3', 'diagnostic_action', 'inspect_resource_scope', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m3', 9, 'coc3_m3_p4', 'configuration_applied', 'coc3_m3_p4', '{"values":{"account_name":"technician","group_assignment":"support","resource_permission":"modify"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc3_m3', 10, 'coc3_m3_p4', 'equipment_operation', 'create_user_folder', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m3', 11, 'coc3_m3_p4', 'equipment_operation', 'create_user_folder', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m3', 12, 'coc3_m3_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m3', 13, 'coc3_m3_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m3', 14, 'coc3_m3_p5', 'test_started', 'retest_client_access', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc3_m3', 15, 'coc3_m3_p5', 'test_completed', 'retest_client_access', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc3_m4', 1, 'coc3_m4_p1', 'placement_attempted', 'server_node_position', '{"item_id":"server_node","destination_id":"server_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m4', 2, 'coc3_m4_p1', 'placement_attempted', 'client_node_position', '{"item_id":"client_node","destination_id":"client_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m4', 3, 'coc3_m4_p1', 'placement_attempted', 'network_printer_position', '{"item_id":"network_printer","destination_id":"network_printer_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m4', 4, 'coc3_m4_p1', 'object_inspected', 'server', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m4', 5, 'coc3_m4_p1', 'object_inspected', 'service_console', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m4', 6, 'coc3_m4_p1', 'object_inspected', 'status_monitor', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m4', 7, 'coc3_m4_p1', 'object_inspected', 'client', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc3_m4', 8, 'coc3_m4_p2', 'configuration_applied', 'coc3_m4_p2', '{"values":{"service_name":"file","listen_port":"445","startup_mode":"automatic"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc3_m4', 9, 'coc3_m4_p2', 'equipment_operation', 'install_service_modules', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m4', 10, 'coc3_m4_p2', 'equipment_operation', 'configure_printer_share', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m4', 11, 'coc3_m4_p2', 'equipment_operation', 'install_service_modules', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m4', 12, 'coc3_m4_p2', 'equipment_operation', 'configure_printer_share', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m4', 13, 'coc3_m4_p3', 'configuration_applied', 'coc3_m4_p3', '{"values":{"service_control":"start","status_inspected":true},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc3_m4', 14, 'coc3_m4_p4', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m4', 15, 'coc3_m4_p4', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m4', 16, 'coc3_m4_p4', 'test_started', 'coc3_m4_test_4', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc3_m4', 17, 'coc3_m4_p4', 'test_completed', 'coc3_m4_test_4', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc3_m4', 18, 'coc3_m4_p5', 'result_interpreted', 'coc3_m4_p5', '{"interpretation":"The measured outputs isolate the service path; correction and retest are recorded.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc3_m5', 1, 'coc3_m5_p1', 'placement_attempted', 'server_node_position', '{"item_id":"server_node","destination_id":"server_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m5', 2, 'coc3_m5_p1', 'placement_attempted', 'client_node_position', '{"item_id":"client_node","destination_id":"client_node_position","runtime_action_type":"placement_attempted"}'::jsonb),
('coc3_m5', 3, 'coc3_m5_p1', 'diagnostic_action', 'inspect_client_message', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 4, 'coc3_m5_p1', 'diagnostic_action', 'inspect_server_console', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 5, 'coc3_m5_p2', 'diagnostic_action', 'inspect_listener_state', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 6, 'coc3_m5_p2', 'diagnostic_action', 'inspect_permission_summary', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 7, 'coc3_m5_p3', 'diagnostic_action', 'probe_client_network', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 8, 'coc3_m5_p3', 'diagnostic_action', 'inspect_service_status', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 9, 'coc3_m5_p3', 'diagnostic_action', 'inspect_access_scope', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc3_m5', 10, 'coc3_m5_p4', 'scenario_decision', 'restore_support_membership', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc3_m5', 11, 'coc3_m5_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m5', 12, 'coc3_m5_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc3_m5', 13, 'coc3_m5_p5', 'test_started', 'retest_service_access', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc3_m5', 14, 'coc3_m5_p5', 'test_completed', 'retest_service_access', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc4_m1', 1, 'coc4_m1_p1', 'object_inspected', 'workstation', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m1', 2, 'coc4_m1_p1', 'object_inspected', 'display', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m1', 3, 'coc4_m1_p1', 'object_inspected', 'network_adapter', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m1', 4, 'coc4_m1_p1', 'object_inspected', 'event_console', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m1', 5, 'coc4_m1_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m1', 6, 'coc4_m1_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m1', 7, 'coc4_m1_p2', 'observation_recorded', 'coc4_m1_p2', '{"observation":"Inspected indicators and documented the observed operating condition.","runtime_action_type":"observation_recorded"}'::jsonb),
('coc4_m1', 8, 'coc4_m1_p3', 'scenario_decision', 'prioritize_network_path', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc4_m1', 9, 'coc4_m1_p4', 'scenario_decision', 'preliminary_network_path', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc4_m1', 10, 'coc4_m1_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m1', 11, 'coc4_m1_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m1', 12, 'coc4_m1_p5', 'test_started', 'coc4_m1_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc4_m1', 13, 'coc4_m1_p5', 'test_completed', 'coc4_m1_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc4_m2', 1, 'coc4_m2_p1', 'diagnostic_action', 'inspect_component_seating', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m2', 2, 'coc4_m2_p1', 'diagnostic_action', 'inspect_event_indicator', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m2', 3, 'coc4_m2_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m2', 4, 'coc4_m2_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m2', 5, 'coc4_m2_p2', 'diagnostic_action', 'run_memory_probe', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m2', 6, 'coc4_m2_p2', 'diagnostic_action', 'inspect_storage_health', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m2', 7, 'coc4_m2_p2', 'diagnostic_action', 'measure_power_state', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m2', 8, 'coc4_m2_p3', 'result_interpreted', 'coc4_m2_p3', '{"interpretation":"The measured outputs isolate the service path; correction and retest are recorded.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc4_m2', 9, 'coc4_m2_p4', 'scenario_decision', 'replace_storage', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc4_m2', 10, 'coc4_m2_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m2', 11, 'coc4_m2_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m2', 12, 'coc4_m2_p5', 'test_started', 'retest_component', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc4_m2', 13, 'coc4_m2_p5', 'test_completed', 'retest_component', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc4_m3', 1, 'coc4_m3_p1', 'object_inspected', 'workstation', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m3', 2, 'coc4_m3_p1', 'object_inspected', 'application_log', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m3', 3, 'coc4_m3_p1', 'object_inspected', 'service_monitor', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m3', 4, 'coc4_m3_p1', 'object_inspected', 'network_interface', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m3', 5, 'coc4_m3_p1', 'object_inspected', 'route_monitor', '{"runtime_action_type":"object_inspected"}'::jsonb),
('coc4_m3', 6, 'coc4_m3_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m3', 7, 'coc4_m3_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m3', 8, 'coc4_m3_p2', 'diagnostic_action', 'inspect_application_log', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m3', 9, 'coc4_m3_p2', 'diagnostic_action', 'inspect_adapter_status', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m3', 10, 'coc4_m3_p2', 'diagnostic_action', 'inspect_service_status', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m3', 11, 'coc4_m3_p3', 'result_interpreted', 'coc4_m3_p3', '{"interpretation":"The measured outputs isolate the service path; correction and retest are recorded.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc4_m3', 12, 'coc4_m3_p4', 'test_started', 'coc4_m3_test_4', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc4_m3', 13, 'coc4_m3_p4', 'test_completed', 'coc4_m3_test_4', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc4_m3', 14, 'coc4_m3_p4', 'result_interpreted', 'coc4_m3_p4', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc4_m3', 15, 'coc4_m3_p5', 'result_interpreted', 'coc4_m3_p5', '{"interpretation":"The measured outputs isolate the service path; correction and retest are recorded.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc4_m4', 1, 'coc4_m4_p1', 'tool_attempted', 'retaining_screw', '{"tool_id":"esd_driver","runtime_action_type":"tool_attempted"}'::jsonb),
('coc4_m4', 2, 'coc4_m4_p1', 'sequence_reordered', 'coc4_m4_p1', '{"order":["isolate","remove","inspect"],"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc4_m4', 3, 'coc4_m4_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m4', 4, 'coc4_m4_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m4', 5, 'coc4_m4_p2', 'placement_attempted', 'workstation', '{"item_id":"replacement_component","destination_id":"workstation","orientation":"aligned","runtime_action_type":"placement_attempted"}'::jsonb),
('coc4_m4', 6, 'coc4_m4_p3', 'configuration_applied', 'coc4_m4_p3', '{"values":{"device_mode":"automatic","device_identifier":"BQ-ETH01","driver_state":"installed"},"runtime_action_type":"configuration_applied"}'::jsonb),
('coc4_m4', 7, 'coc4_m4_p4', 'sequence_reordered', 'coc4_m4_p4', '{"order":["seat","fasten","configure","restore"],"runtime_action_type":"sequence_reordered"}'::jsonb),
('coc4_m4', 8, 'coc4_m4_p5', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m4', 9, 'coc4_m4_p5', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m4', 10, 'coc4_m4_p5', 'test_started', 'coc4_m4_test_5', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc4_m4', 11, 'coc4_m4_p5', 'test_completed', 'coc4_m4_test_5', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc4_m5', 1, 'coc4_m5_p1', 'diagnostic_action', 'diagnose_printer_driver', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m5', 2, 'coc4_m5_p1', 'diagnostic_action', 'diagnose_usb_port', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m5', 3, 'coc4_m5_p1', 'diagnostic_action', 'diagnose_audio_driver', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m5', 4, 'coc4_m5_p1', 'diagnostic_action', 'diagnose_video_cable', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m5', 5, 'coc4_m5_p1', 'diagnostic_action', 'diagnose_windows_update', '{"runtime_action_type":"diagnostic_action"}'::jsonb),
('coc4_m5', 6, 'coc4_m5_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 7, 'coc4_m5_p1', 'equipment_operation', 'protect_service_data', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 8, 'coc4_m5_p2', 'tool_attempted', 'driver_inventory', '{"tool_id":"device_manager","runtime_action_type":"tool_attempted"}'::jsonb),
('coc4_m5', 9, 'coc4_m5_p2', 'tool_attempted', 'usb_interface', '{"tool_id":"port_tester","runtime_action_type":"tool_attempted"}'::jsonb),
('coc4_m5', 10, 'coc4_m5_p2', 'tool_attempted', 'video_link', '{"tool_id":"cable_tester","runtime_action_type":"tool_attempted"}'::jsonb),
('coc4_m5', 11, 'coc4_m5_p2', 'scenario_decision', 'service_verified_faults', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc4_m5', 12, 'coc4_m5_p3', 'scenario_decision', 'open_service_console', '{"runtime_action_type":"scenario_decision"}'::jsonb),
('coc4_m5', 13, 'coc4_m5_p3', 'equipment_operation', 'usb_port', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 14, 'coc4_m5_p3', 'equipment_operation', 'printer_driver', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 15, 'coc4_m5_p3', 'equipment_operation', 'audio_driver', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 16, 'coc4_m5_p3', 'equipment_operation', 'video_cable', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 17, 'coc4_m5_p3', 'equipment_operation', 'windows_update', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 18, 'coc4_m5_p3', 'equipment_operation', 'usb_port', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 19, 'coc4_m5_p3', 'equipment_operation', 'printer_driver', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 20, 'coc4_m5_p3', 'equipment_operation', 'audio_driver', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 21, 'coc4_m5_p3', 'equipment_operation', 'video_cable', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 22, 'coc4_m5_p3', 'equipment_operation', 'windows_update', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 23, 'coc4_m5_p4', 'equipment_operation', 'close_work_area', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 24, 'coc4_m5_p4', 'equipment_operation', 'prepare_service_report', '{"runtime_action_type":"equipment_operation"}'::jsonb),
('coc4_m5', 25, 'coc4_m5_p4', 'test_started', 'run_maintenance_check', '{"test_status":"running","runtime_action_type":"test_started"}'::jsonb),
('coc4_m5', 26, 'coc4_m5_p4', 'test_completed', 'run_maintenance_check', '{"test_status":"completed","runtime_action_type":"test_completed"}'::jsonb),
('coc4_m5', 27, 'coc4_m5_p4', 'result_interpreted', 'coc4_m5_p4', '{"interpretation":"Recorded output supports the next service action; verify each measured subsystem.","runtime_action_type":"result_interpreted"}'::jsonb),
('coc4_m5', 28, 'coc4_m5_p5', 'observation_recorded', 'coc4_m5_p5', '{"observation":"Inspected indicators and documented the observed operating condition.","runtime_action_type":"observation_recorded"}'::jsonb);
-- END GENERATED REPLAY FIXTURES

create function pg_temp.fixture_actions(p_mission text, p_phase text default null)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('action_type', f.action_type,
      'target', f.target, 'phase_id', f.phase_id, 'value', f.value) order by f.ordinal), '[]'::jsonb)
  from replay_fixture f
  where f.mission_id = p_mission and (p_phase is null or f.phase_id = p_phase)
$$;

-- ---------------------------------------------------------------------------
-- Learners (the Auth trigger creates active learner profiles); every row is
-- rolled back. The parity learner has COC1-COC3 practice progress and every
-- module unlocked so each mission is open under COC- or module-level rules.
-- ---------------------------------------------------------------------------
create temp table replay_ctx (learner uuid, locked_learner uuid, metrics_learner uuid) on commit drop;
insert into replay_ctx values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid());
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'authenticated', 'authenticated',
  'replay-' || id || '@bytequest.invalid', '', '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Simulation replay rollback learner"}'::jsonb, now(), now()
from replay_ctx cross join lateral (values (learner), (locked_learner), (metrics_learner)) u(id);

do $$
declare learner uuid; n integer; quiz uuid;
begin
  for learner in select r.learner from replay_ctx r union all select r.metrics_learner from replay_ctx r loop
    for n in 1..3 loop
      quiz := gen_random_uuid();
      insert into public.practice_quiz_attempts(id, learner_id, coc_code, status, questions, answers, score, passed, submitted_at)
      values (quiz, learner, 'coc' || n, 'submitted',
        (select jsonb_agg(jsonb_build_object('id', 'q' || i, 'answer', 0)) from generate_series(1, 5) i),
        '{}'::jsonb, 5, true, now());
      insert into public.practice_coc_progress(learner_id, coc_code, quiz_attempt_id) values (learner, 'coc' || n, quiz);
    end loop;
    insert into public.learner_module_unlocks(learner_id, module_id, reason)
    select learner, m.id, 'bypass' from public.curriculum_modules m on conflict do nothing;
  end loop;
end $$;

create function pg_temp.insert_actions(p_learner uuid, p_mission text, p_actions jsonb, p_tag text,
  p_start timestamptz default now() - interval '1 hour', p_step interval default interval '1 second')
returns void language sql as $$
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  select p_learner, p_tag || '-' || p_mission || '-' || n, p_mission, x->>'phase_id', x->>'action_type',
    x->>'target', x->'value', p_start + (n - 1) * p_step
  from jsonb_array_elements(p_actions) with ordinality t(x, n)
$$;

create function pg_temp.discard(p_learner uuid, p_mission text, p_tag text)
returns void language sql as $$
  insert into public.practice_mission_actions(learner_id, client_action_id, mission_id, phase_id,
    action_type, target, value, client_occurred_at)
  values (p_learner, p_tag || '-discard-' || p_mission, p_mission, p_mission || '_p1',
    'practice_progress_discarded', null, '{"reason":"rollback_test"}'::jsonb, now() - interval '30 minutes')
$$;

create function pg_temp.verify_outcome(p_learner uuid, p_mission text)
returns text language plpgsql as $$
begin
  perform public.practice_verify_mission(p_learner, p_mission);
  return 'verified';
exception when others then
  return sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Parity with the legacy verifier on every published contract (20 + 1).
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.practice_mission_contracts c
    where exists (select 1 from replay_fixture f where f.mission_id = c.mission_id)),
  20, 'every published practice contract has an exported happy path');

select is(
  (select r - 'invalid' - 'corrections' - 'phase_invalid' - 'action_count' - 'invalid_count'
      - 'correction_count' - 'first_at' - 'last_at'
   from private.simulation_replay(c.definition, pg_temp.fixture_actions(c.mission_id)) r),
  pg_temp.legacy_replay(c.definition, pg_temp.fixture_actions(c.mission_id)),
  c.mission_id || ' replay reproduces the legacy done set and state')
from public.practice_mission_contracts c
order by c.mission_id;

create temp table verify_parity(mission_id text, scenario text, legacy text, actual text) on commit drop;
do $$
declare c record; learner uuid := (select r.learner from replay_ctx r);
  first_phase text; truncated jsonb; complete jsonb;
begin
  for c in select mission_id, definition from public.practice_mission_contracts order by mission_id loop
    first_phase := c.definition #>> '{phases,0,id}';
    truncated := pg_temp.fixture_actions(c.mission_id, first_phase);
    complete := pg_temp.fixture_actions(c.mission_id);
    perform pg_temp.insert_actions(learner, c.mission_id, truncated, 'truncated');
    insert into verify_parity values (c.mission_id, 'truncated',
      pg_temp.legacy_outcome(c.definition, truncated), pg_temp.verify_outcome(learner, c.mission_id));
    perform pg_temp.discard(learner, c.mission_id, 'parity');
    perform pg_temp.insert_actions(learner, c.mission_id, complete, 'complete', now() - interval '20 minutes');
    insert into verify_parity values (c.mission_id, 'complete',
      pg_temp.legacy_outcome(c.definition, complete), pg_temp.verify_outcome(learner, c.mission_id));
  end loop;
end $$;

select is(actual, legacy, mission_id || ' ' || scenario || ' run: practice_verify_mission matches the legacy outcome')
from verify_parity order by mission_id, scenario;

select is((select count(*)::integer from verify_parity where scenario = 'complete' and actual = 'verified'),
  20, 'every complete happy path verifies');
select is((select count(*)::integer from verify_parity where scenario = 'truncated' and actual like 'PRACTICE_WORK_INCOMPLETE:%'),
  20, 'every truncated run is rejected as incomplete');
select is((select count(*)::integer from public.practice_mission_completions c
    join public.practice_mission_contracts d using (mission_id)
    where c.learner_id = (select learner from replay_ctx) and c.contract_version = d.version),
  20, 'verified runs record completions for the current contract versions');

-- ---------------------------------------------------------------------------
-- 2. Extended replay semantics on a compact bench contract.
-- ---------------------------------------------------------------------------
create temp table bench(definition jsonb) on commit drop;
insert into bench values ('{
  "phases": [
    {"id": "t_p1", "primaryInteraction": "place", "presentation": {
      "items": [
        {"id": "cpu", "category": "cpu", "seating_orientation": "0",
         "requires": [{"path": "setting.lever", "value": "open"}]},
        {"id": "ram_1", "category": "dimm", "removal_effects": {"ram_locked": false}},
        {"id": "shield", "category": "shield", "required": false}
      ],
      "destinations": [
        {"id": "socket", "socket_categories": ["cpu"]},
        {"id": "dimm_a1", "socket_categories": ["dimm"]},
        {"id": "dimm_a2", "socket_categories": ["dimm"]},
        {"id": "cutout", "socket_categories": ["shield"]}
      ],
      "equipment": {"single_connection": true,
        "operations": [
          {"id": "open_lever", "effects": {"lever": "open"}, "requires": []},
          {"id": "lock_ram", "effects": {"ram_locked": true},
           "requires": [{"path": "placed.ram_1", "operator": "present"}]}
        ],
        "connection": {
          "sources": [{"id": "fan", "interfaces": ["fan"]}],
          "destinations": [{"id": "cpu_fan", "interface": "fan"},
            {"id": "sys_fan", "interface": "fan"}, {"id": "atx", "interface": "atx"}]}}}},
    {"id": "t_p2", "primaryInteraction": "connect", "presentation": {
      "sources": [{"id": "atx24", "interfaces": ["atx"]}, {"id": "eps8", "interfaces": ["eps"], "required": false}],
      "destinations": [{"id": "board_atx", "interface": "atx"}, {"id": "board_eps", "interface": "eps"}],
      "equipment": {"single_connection": true}}},
    {"id": "t_p3", "primaryInteraction": "review", "presentation": {}}
  ]}');

create function pg_temp.bench_replay(p_actions jsonb)
returns jsonb language sql stable as $$
  select private.simulation_replay((select definition from bench), p_actions)
$$;

create temp table bench_result(name text primary key, result jsonb) on commit drop;
insert into bench_result values
('wrong_category', pg_temp.bench_replay('[
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"dimm_a1","value":{"item_id":"cpu","destination_id":"dimm_a1","orientation":"0"},"occurred_at":"2026-11-19T01:00:00Z"}]')),
('requires_unmet', pg_temp.bench_replay('[
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"socket","value":{"item_id":"cpu","destination_id":"socket","orientation":"0"}},
  {"action_type":"equipment_operation","phase_id":"t_p1","target":"open_lever","value":{}},
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"socket","value":{"item_id":"cpu","destination_id":"socket","orientation":"90"}},
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"socket","value":{"item_id":"cpu","destination_id":"socket","orientation":"0"}}]')),
('reseat', pg_temp.bench_replay('[
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"dimm_a1","value":{"item_id":"ram_1","destination_id":"dimm_a1"},"occurred_at":"2026-11-19T01:00:00Z"},
  {"action_type":"equipment_operation","phase_id":"t_p1","target":"lock_ram","value":{},"occurred_at":"2026-11-19T01:00:30Z"},
  {"action_type":"placement_removed","phase_id":"t_p1","target":"ram_1","value":{"item_id":"ram_1"},"occurred_at":"2026-11-19T01:01:00Z"},
  {"action_type":"placement_removed","phase_id":"t_p1","target":"ram_1","value":{"item_id":"ram_1"},"occurred_at":"2026-11-19T01:01:10Z"},
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"dimm_a2","value":{"item_id":"ram_1","destination_id":"dimm_a2"},"occurred_at":"2026-11-19T01:02:00Z"}]')),
('optional_parts', pg_temp.bench_replay('[
  {"action_type":"equipment_operation","phase_id":"t_p1","target":"open_lever","value":{}},
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"socket","value":{"item_id":"cpu","destination_id":"socket","orientation":"0"}},
  {"action_type":"placement_attempted","phase_id":"t_p1","target":"dimm_a2","value":{"item_id":"ram_1","destination_id":"dimm_a2"}},
  {"action_type":"connection_created","phase_id":"t_p2","target":"board_atx","value":{"source_id":"atx24","destination_id":"board_atx"}}]')),
('connections', pg_temp.bench_replay('[
  {"action_type":"connection_created","phase_id":"t_p1","target":"sys_fan","value":{"source_id":"fan","destination_id":"sys_fan"}},
  {"action_type":"connection_created","phase_id":"t_p1","target":"cpu_fan","value":{"source_id":"fan","destination_id":"cpu_fan"}},
  {"action_type":"connection_created","phase_id":"t_p1","target":"atx","value":{"source_id":"fan","destination_id":"atx"}},
  {"action_type":"connection_created","phase_id":"t_p2","target":"board_eps","value":{"source_id":"atx24","destination_id":"board_eps"}}]')),
('runtime_type_precedence', pg_temp.bench_replay('[
  {"action_type":"component_drop_attempted","phase_id":"t_p1","target":"dimm_a1","value":{"runtime_action_type":"placement_attempted","item_id":"ram_1","destination_id":"dimm_a1"}},
  {"action_type":"phase_completed","phase_id":"t_p1","target":"t_p2","value":{}},
  {"action_type":"placement_attempted","phase_id":"unknown_phase","target":"dimm_a2","value":{"item_id":"ram_1","destination_id":"dimm_a2"}}]'));

select is((select result->'invalid' from bench_result where name = 'wrong_category'),
  '{"item:cpu": 1}'::jsonb, 'a part in an incompatible slot is counted against that part');
select is((select result->'phase_invalid' from bench_result where name = 'wrong_category'),
  '{"t_p1": 1}'::jsonb, 'invalid actions are also counted per phase');
select ok((select not (result->'state' ? 'placed.cpu') from bench_result where name = 'wrong_category'),
  'an invalid placement does not change the bench state');
select is((select result->'invalid' from bench_result where name = 'requires_unmet'),
  '{"item:cpu": 2}'::jsonb, 'unmet item requires and a wrong orientation are both invalid');
select is((select result->'state'->>'placed.cpu' from bench_result where name = 'requires_unmet'),
  'socket', 'the part seats once its requires and orientation are met');
select is((select result->'corrections' from bench_result where name = 'reseat'),
  '{"item:ram_1": 1}'::jsonb, 'a valid removal counts one correction for the part');
select is((select result->'invalid' from bench_result where name = 'reseat'),
  '{"item:ram_1": 1}'::jsonb, 'removing a part that is not installed is invalid');
select is((select result->'state'->>'placed.ram_1' from bench_result where name = 'reseat'),
  'dimm_a2', 're-placing a removed part is valid');
select is((select result->'state'->'setting.ram_locked' from bench_result where name = 'reseat'),
  'false'::jsonb, 'removal_effects reset the dependent equipment setting');
select is((select (result->>'revision')::integer from (select result->'state' result from bench_result where name = 'reseat') s),
  4, 'placement, operation, removal and re-placement each advance the state revision');
select ok((select (result->'done'->>'t_p1')::boolean and (result->'done'->>'t_p2')::boolean
    from bench_result where name = 'optional_parts'),
  'items and sources marked required:false do not block their phase');
select is((select result->'corrections' from bench_result where name = 'connections'),
  '{"connection:fan": 1}'::jsonb, 'moving a single-connection cable to another header is a correction');
select is((select result->'invalid' from bench_result where name = 'connections'),
  '{"connection:fan": 1, "connection:atx24": 1}'::jsonb, 'a connector that does not fit is counted against its cable');
select ok((select result->'state' ? 'link.fan>cpu_fan' and not (result->'state' ? 'link.fan>sys_fan')
    from bench_result where name = 'connections'),
  'the replaced fan link is removed from the state');
select is((select result->'state'->>'placed.ram_1' from bench_result where name = 'runtime_type_precedence'),
  'dimm_a1', 'runtime_action_type takes precedence over the transport action type');
select is((select (result->>'action_count')::integer from bench_result where name = 'runtime_type_precedence'),
  1, 'navigation actions and unknown phases are not counted as bench actions');
select is((select jsonb_build_object('actions', result->'action_count', 'invalid', result->'invalid_count',
    'corrections', result->'correction_count',
    'first', (result->>'first_at')::timestamptz = '2026-11-19T01:00:00Z'::timestamptz,
    'last', (result->>'last_at')::timestamptz = '2026-11-19T01:02:00Z'::timestamptz)
    from bench_result where name = 'reseat'),
  '{"actions": 5, "invalid": 1, "corrections": 1, "first": true, "last": true}'::jsonb,
  'replay metrics summarise the run');

select lives_ok($$ select private.simulation_replay('{"phases":"broken"}'::jsonb, '"not an array"'::jsonb) $$,
  'replay never raises on malformed definitions or actions');
select is(private.simulation_replay(null, null)->'done', '{}'::jsonb,
  'replay of nothing completes nothing');
select is((private.simulation_replay(
    (select definition from public.practice_mission_contracts where mission_id = 'coc1_m3'),
    '[{"action_type":"sequence_reordered","phase_id":"coc1_m3_p2","target":"coc1_m3_p2","value":{"order":"boot_media"}},
      {"action_type":"configuration_applied","phase_id":"coc1_m3_p1","target":"coc1_m3_p1","value":{"values":"broken"}},
      {"action_type":"placement_attempted","phase_id":"coc1_m3_p1","target":"x","value":{"item_id":["not","text"],"destination_id":{"a":1}}}]'::jsonb
  )->>'invalid_count')::integer, 3, 'malformed learner values are invalid actions, not errors');

-- ---------------------------------------------------------------------------
-- 3. Verification guards and practice run metrics.
-- ---------------------------------------------------------------------------
select throws_ok(
  format('select public.practice_verify_mission(%L::uuid, %L)', (select locked_learner from replay_ctx), 'coc2_m1'),
  '42501', 'PRACTICE_COC_LOCKED', 'a mission whose COC is locked keeps raising PRACTICE_COC_LOCKED');
select throws_ok(
  format('select public.practice_verify_mission(%L::uuid, %L)', (select locked_learner from replay_ctx), 'coc1_m1'),
  '22023', 'PRACTICE_WORK_INCOMPLETE:coc1_m1_p1', 'a learner without evidence keeps the incomplete error');

do $$
declare learner uuid := (select metrics_learner from replay_ctx);
begin
  -- Run 1: one incompatible placement, a removal of an absent part, then the full work order.
  perform pg_temp.insert_actions(learner, 'coc1_m3',
    '[{"action_type":"placement_attempted","phase_id":"coc1_m3_p1","target":"boot_usb_position","value":{"item_id":"boot_usb","destination_id":"system_unit_position"}},
      {"action_type":"placement_removed","phase_id":"coc1_m3_p1","target":"boot_usb","value":{"item_id":"boot_usb"}}]'::jsonb
      || pg_temp.fixture_actions('coc1_m3'),
    'metrics-1', now() - interval '50 minutes', interval '10 seconds');
  perform public.practice_verify_mission(learner, 'coc1_m3');
  -- Repeating the verification of the same evidence does not add a run.
  perform public.practice_verify_mission(learner, 'coc1_m3');
end $$;

select is((select count(*)::integer from public.practice_mission_runs
    where learner_id = (select metrics_learner from replay_ctx) and mission_id = 'coc1_m3'),
  1, 'repeating a verification of the same evidence records one run');
-- The exported work order retries one operation whose prerequisite is set
-- later in the same phase; the two prepended mistakes add to that baseline.
create temp table coc1_m3_baseline on commit drop as
  select private.simulation_replay(definition, pg_temp.fixture_actions('coc1_m3')) as replay
  from public.practice_mission_contracts where mission_id = 'coc1_m3';

select is((select jsonb_build_object('run', run_number, 'outcome', outcome, 'version', contract_version,
    'invalid', invalid_count, 'corrections', correction_count, 'failure', failure_code)
    from public.practice_mission_runs where learner_id = (select metrics_learner from replay_ctx) and mission_id = 'coc1_m3'),
  jsonb_build_object('run', 1, 'outcome', 'verified', 'version', 'css-sag-20261011-v2',
    'invalid', 2 + (select (replay->>'invalid_count')::integer from coc1_m3_baseline),
    'corrections', 0, 'failure', null),
  'the verified run records its number, outcome, contract version and invalid actions');
select is((select duration_seconds from public.practice_mission_runs
    where learner_id = (select metrics_learner from replay_ctx) and mission_id = 'coc1_m3'),
  ((select count(*)::integer from replay_fixture where mission_id = 'coc1_m3') + 1) * 10,
  'duration_seconds is the time from the first to the last action of the run');
select is((select action_count from public.practice_mission_runs
    where learner_id = (select metrics_learner from replay_ctx) and mission_id = 'coc1_m3'),
  (select count(*)::integer + 2 from replay_fixture where mission_id = 'coc1_m3'
     and coalesce(value->>'runtime_action_type', action_type) not in ('phase_completed', 'review_returned')),
  'action_count counts every replayed bench action of the run');
select is((select step_results from public.practice_mission_runs
    where learner_id = (select metrics_learner from replay_ctx) and mission_id = 'coc1_m3'),
  (select jsonb_object_agg(phase_id, jsonb_build_object('done', true,
      'invalid', coalesce((replay->'phase_invalid'->>phase_id)::integer, 0) + case when phase_id = 'coc1_m3_p1' then 2 else 0 end))
    from coc1_m3_baseline, unnest(array['coc1_m3_p1', 'coc1_m3_p2', 'coc1_m3_p3', 'coc1_m3_p4']) phase_id),
  'step_results reports each work phase as done with its invalid actions');
select is((select (replay->>'invalid_count')::integer from coc1_m3_baseline), 1,
  'the exported coc1_m3 work order contains exactly one prerequisite retry');

do $$
declare learner uuid := (select metrics_learner from replay_ctx); failure text;
begin
  perform pg_temp.discard(learner, 'coc1_m3', 'metrics-2');
  perform pg_temp.insert_actions(learner, 'coc1_m3', pg_temp.fixture_actions('coc1_m3', 'coc1_m3_p1'),
    'metrics-2', now() - interval '10 minutes', interval '5 seconds');
  begin
    perform public.practice_verify_mission(learner, 'coc1_m3');
    raise exception 'INCOMPLETE_RUN_VERIFIED';
  exception when sqlstate '22023' then
    failure := sqlerrm;
  end;
  perform public.practice_record_failed_verification(learner, 'coc1_m3', failure);
  perform public.practice_record_failed_verification(learner, 'coc1_m3', failure);
end $$;

select is((select jsonb_build_object('run', run_number, 'outcome', outcome, 'failure', failure_code,
    'actions', action_count, 'p1', step_results->'coc1_m3_p1', 'p2', step_results->'coc1_m3_p2')
    from public.practice_mission_runs where learner_id = (select metrics_learner from replay_ctx)
      and mission_id = 'coc1_m3' and run_number = 2),
  jsonb_build_object('run', 2, 'outcome', 'incomplete', 'failure', 'PRACTICE_WORK_INCOMPLETE:coc1_m3_p2',
    'actions', (select count(*)::integer from replay_fixture where mission_id = 'coc1_m3' and phase_id = 'coc1_m3_p1'),
    'p1', '{"done": true, "invalid": 0}'::jsonb, 'p2', '{"done": false, "invalid": 0}'::jsonb),
  'a failed verification is recorded as an incomplete run of the current evidence window');
select is((select count(*)::integer from public.practice_mission_runs
    where learner_id = (select metrics_learner from replay_ctx) and mission_id = 'coc1_m3'),
  2, 'recording the same failure twice keeps one incomplete run');
select throws_ok(
  format('select public.practice_record_failed_verification(%L::uuid, %L, %L)',
    (select metrics_learner from replay_ctx), 'coc1_m3', 'not a code; drop table'),
  '22023', 'PRACTICE_FAILURE_CODE_INVALID', 'failure codes are validated');
select throws_ok(
  format('select public.practice_record_failed_verification(%L::uuid, %L, %L)',
    gen_random_uuid(), 'coc1_m3', 'PRACTICE_WORK_INCOMPLETE:coc1_m3_p1'),
  '42501', 'ACTIVE_LEARNER_REQUIRED', 'only active learners have practice runs');
select lives_ok(
  format('select public.practice_record_failed_verification(%L::uuid, %L, %L)',
    (select locked_learner from replay_ctx), 'coc1_m1', 'PRACTICE_WORK_INCOMPLETE:coc1_m1_p1'),
  'a failure with no evidence in the current window is accepted');
select is((select count(*)::integer from public.practice_mission_runs where learner_id = (select locked_learner from replay_ctx)),
  0, 'a failure with no evidence records no run');

-- ---------------------------------------------------------------------------
-- 4. Privileges: replay and run recording stay server-only and invoker.
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated', 'private.simulation_replay(jsonb,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.simulation_replay(jsonb,jsonb)', 'EXECUTE'),
  'learners and anonymous callers cannot execute the replay');
select ok(has_function_privilege('service_role', 'private.simulation_replay(jsonb,jsonb)', 'EXECUTE'),
  'the trusted server can execute the replay');
select ok(not has_function_privilege('authenticated', 'public.practice_record_failed_verification(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.practice_record_failed_verification(uuid,text,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.practice_record_failed_verification(uuid,text,text)', 'EXECUTE'),
  'only the trusted server records failed verifications');
select ok(not has_function_privilege('authenticated', 'public.practice_verify_mission(uuid,text)', 'EXECUTE'),
  'practice verification remains server-only');
select is((select count(*)::integer from pg_proc where oid in (
    'private.simulation_replay(jsonb,jsonb)'::regprocedure,
    'public.practice_verify_mission(uuid,text)'::regprocedure,
    'public.practice_record_failed_verification(uuid,text,text)'::regprocedure,
    'public.practice_completion_version_accepted(text,text,text)'::regprocedure) and prosecdef),
  0, 'the replay refactor introduces no SECURITY DEFINER function');
select ok((select pg_get_function_identity_arguments(oid) = 'p_learner uuid, p_mission text'
      and prorettype = 'void'::regtype
    from pg_proc where oid = 'public.practice_verify_mission(uuid,text)'::regprocedure),
  'practice_verify_mission keeps its signature');

select * from finish();
rollback;
