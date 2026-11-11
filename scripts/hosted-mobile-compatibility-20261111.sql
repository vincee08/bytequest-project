-- OWNER APPROVAL REQUIRED. Prepared only; not authorized for production execution.
-- Target: ByteQuest rslmteqipxqfifwftugk, via its authenticated Management API only.
-- Reuses exactly two existing migration bodies, with only their outer BEGIN/COMMIT removed.
-- 20260908120000_harden_authoritative_action_idempotency.sql SHA256 1b8cfd6fc6b70ef1706a9152f86debff5baa67220f391bfbafedb54390863385
-- 20261109120000_coc1_m1_identification_contract.sql SHA256 95d60bdc4ecc09a728814c3a31156e170b8be7ebc1873e30ca580abaf81e9a3f
-- One top-level DO statement is atomic, including its new, honestly dated batch history entry.
-- All 49 existing migration entries remain unchanged. No db push or history repair.
-- Unfinished v2: retain old evidence; only learner-confirmed discard/restart creates a new v3 run.
do $hosted_mobile_approval$
declare
  v_idempotency text := $source_idempotency$-- Recover safely from an append response lost after commit. Client action IDs
-- are transport idempotency keys, not scoring inputs. This is a forward-only
-- upgrade and does not replay the fresh-database foundation migration.


do $$
begin
  if exists (
    select 1
    from public.attempt_actions aa
    where nullif(btrim(aa.value ->> 'client_action_id'), '') is not null
    group by aa.attempt_id, aa.value ->> 'client_action_id'
    having count(*) > 1
  ) then
    raise exception 'DUPLICATE_CLIENT_ACTION_IDS_REQUIRE_REVIEW'
      using errcode = '23505';
  end if;
end
$$;

create unique index if not exists attempt_actions_client_action_id_idx
  on public.attempt_actions (
    attempt_id,
    (value ->> 'client_action_id')
  )
  where nullif(btrim(value ->> 'client_action_id'), '') is not null;

create or replace function public.append_attempt_action(
  p_attempt_id uuid,
  p_sequence_number integer,
  p_action_type text,
  p_target text,
  p_value jsonb,
  p_client_occurred_at timestamptz
)
returns public.attempt_actions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt public.attempts;
  v_action public.attempt_actions;
  v_client_action_id text;
begin
  select a.* into v_attempt
  from public.attempts a
  where a.id = p_attempt_id
  for update;

  if not found then
    raise exception 'ATTEMPT_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.assert_attempt_write_access(v_attempt);

  if v_attempt.status <> 'in_progress'::public.attempt_status then
    raise exception 'ATTEMPT_NOT_IN_PROGRESS' using errcode = '22023';
  end if;

  if p_sequence_number <= 0 then
    raise exception 'INVALID_SEQUENCE_NUMBER' using errcode = '22023';
  end if;

  if p_client_occurred_at > now() + interval '5 minutes' then
    raise exception 'ACTION_TIME_IN_FUTURE' using errcode = '22023';
  end if;

  v_client_action_id := nullif(
    btrim(coalesce(p_value, '{}'::jsonb) ->> 'client_action_id'),
    ''
  );

  if v_client_action_id is not null then
    select aa.* into v_action
    from public.attempt_actions aa
    where aa.attempt_id = p_attempt_id
      and aa.value ->> 'client_action_id' = v_client_action_id;

    if found then
      if v_action.action_type = btrim(p_action_type)
         and v_action.target is not distinct from nullif(btrim(p_target), '')
         and v_action.value = coalesce(p_value, '{}'::jsonb)
         and v_action.client_occurred_at = p_client_occurred_at then
        return v_action;
      end if;
      raise exception 'ACTION_ID_CONFLICT' using errcode = '23505';
    end if;
  end if;

  select aa.* into v_action
  from public.attempt_actions aa
  where aa.attempt_id = p_attempt_id
    and aa.sequence_number = p_sequence_number;

  if found then
    if v_action.action_type = btrim(p_action_type)
       and v_action.target is not distinct from nullif(btrim(p_target), '')
       and v_action.value = coalesce(p_value, '{}'::jsonb)
       and v_action.client_occurred_at = p_client_occurred_at then
      return v_action;
    end if;
    raise exception 'ACTION_SEQUENCE_CONFLICT' using errcode = '23505';
  end if;

  insert into public.attempt_actions (
    attempt_id,
    sequence_number,
    action_type,
    target,
    value,
    client_occurred_at
  )
  values (
    p_attempt_id,
    p_sequence_number,
    btrim(p_action_type),
    nullif(btrim(p_target), ''),
    coalesce(p_value, '{}'::jsonb),
    p_client_occurred_at
  )
  returning * into v_action;

  return v_action;
end
$$;

revoke all on function public.append_attempt_action(
  uuid, integer, text, text, jsonb, timestamptz
) from public, anon;
grant execute on function public.append_attempt_action(
  uuid, integer, text, text, jsonb, timestamptz
) to authenticated;

comment on function public.append_attempt_action(
  uuid, integer, text, text, jsonb, timestamptz
) is
  'Appends learner-owned evidence exactly once by attempt sequence and optional client_action_id. It accepts no score, outcome, reward, or competency decision.';$source_idempotency$;
  v_v3 text := $source_v3$-- COC1 M1 practice identification only. Historical v1/v2 migrations and
-- acknowledged learner actions remain unchanged; only the active contract moves
-- to v3. Official assessment, instructor release, and scoring are untouched.

do $guard$
declare current_contract public.practice_mission_contracts;
begin
  select * into strict current_contract from public.practice_mission_contracts
    where mission_id = 'coc1_m1' for update;
  if current_contract.version <> 'css-sag-20261011-v2'
     or current_contract.definition #>> '{phases,0,id}' <> 'coc1_m1_p1'
     or current_contract.definition #>> '{phases,1,id}' <> 'coc1_m1_p2'
     or coalesce(jsonb_array_length(current_contract.definition #> '{phases,0,presentation,equipment,placement,items}'),0) <> 4 then
    raise exception 'COC1_M1_V2_CONTRACT_REQUIRED' using errcode = '22023';
  end if;
end
$guard$;

-- Generated from the production typed Flutter definition. P1 requires seven
-- inspection taps and no placement; P2 records each role choice on tap using
-- the existing selection_confirmed evidence type. The readiness test still
-- verifies the role choices, safe work set, observations, and close-out.
insert into public.practice_mission_contracts(mission_id, version, definition) values
('coc1_m1', 'css-sag-20261109-v3', '{"id":"coc1_m1","cocId":"coc1","title":"Identify Computer Parts and Tools","scenario":"Inspect a de-energized desktop before servicing. The memory latch is open. Identify component roles, isolate abnormalities, and record a safe work plan.","environmentLabel":"Hardware inspection bench","practiceGuidance":"Inspect labels and visible conditions before recording any decision.","scene":{"id":"coc1_m1_scene","backgroundAsset":"assets/images/COC1.png","objects":[{"id":"motherboard","label":"Motherboard","x":0.08,"y":0.1,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["motherboard_port"],"initialState":"neutral","metadata":{"schematicRole":"primary","description":"Motherboard","replaceableAsset":"assets/simulation/schematics/motherboard.svg","imageAsset":"assets/COC1/Mission 1/motherboard.png"}},{"id":"cpu","label":"Processor","x":0.38,"y":0.1,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["cpu_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"Processor","replaceableAsset":"assets/simulation/schematics/cpu.svg","imageAsset":"assets/COC1/Mission 1/cpu.png"}},{"id":"ram","label":"Memory module","x":0.6799999999999999,"y":0.1,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["ram_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"Memory module","replaceableAsset":"assets/simulation/schematics/ram.svg","imageAsset":"assets/COC1/Mission 1/ram.png"}},{"id":"psu","label":"Power supply","x":0.08,"y":0.44000000000000006,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["psu_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"Power supply","replaceableAsset":"assets/simulation/schematics/psu.svg","imageAsset":"assets/COC1/Mission 1/psu.png"}},{"id":"cpu_socket","label":"CPU socket","x":0.38,"y":0.44000000000000006,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["cpu_socket_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"CPU socket","replaceableAsset":"assets/simulation/schematics/cpu_socket.svg","imageAsset":null}},{"id":"dimm_slot","label":"DIMM slot","x":0.6799999999999999,"y":0.44000000000000006,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["dimm_slot_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"DIMM slot","replaceableAsset":"assets/simulation/schematics/dimm_slot.svg","imageAsset":null}},{"id":"atx_power_port","label":"24-pin ATX power header","x":0.08,"y":0.78,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["atx_power_port_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"24-pin ATX power header","replaceableAsset":"assets/simulation/schematics/atx_power_port.svg","imageAsset":null}},{"id":"anti_static_strap","label":"Anti-static wrist strap","x":0.38,"y":0.78,"width":0.24,"height":0.22,"hotspotType":"inspect_and_select","connectionNodeIds":["anti_static_strap_port"],"initialState":"neutral","metadata":{"schematicRole":"supporting","description":"Anti-static wrist strap","replaceableAsset":"assets/simulation/schematics/anti_static_strap.svg","imageAsset":"assets/COC1/Mission 1/anti_static_wrist_strap.png"}}],"initialStatus":{"schematic":true,"replaceableAssets":true,"statusLabel":"Awaiting inspection","sceneKind":"workbench"}},"phases":[{"id":"coc1_m1_p1","title":"Inspect hardware","instruction":"Inspect each component and its visible condition.","primaryInteraction":"inspect","supportingInteractions":[],"availableObjectIds":["motherboard","cpu","ram","psu","cpu_socket","dimm_slot","atx_power_port","anti_static_strap"],"feedbackIds":["coc1_m1_constraint"],"presentation":{"component":"tap_inspect","objects":[{"id":"motherboard","label":"Motherboard","inspection":"ATX board. CPU socket, keyed DIMM slots, and 24-pin power header are visible. No swollen capacitors are visible.","description":"Motherboard","imageAsset":"assets/COC1/Mission 1/motherboard.png"},{"id":"cpu","label":"Processor","inspection":"Processor contacts are intact. The alignment mark must match the socket mark; do not force the package.","description":"Processor","imageAsset":"assets/COC1/Mission 1/cpu.png"},{"id":"ram","label":"Memory module","inspection":"DDR memory module. The notch is offset; one retaining latch is open. Isolate power before reseating.","description":"Memory module","imageAsset":"assets/COC1/Mission 1/ram.png"},{"id":"psu","label":"Power supply","inspection":"Power supply converts mains to regulated DC rails. Disconnect mains before touching internal connectors.","description":"Power supply","imageAsset":"assets/COC1/Mission 1/psu.png"},{"id":"cpu_socket","label":"CPU socket","inspection":"The keyed CPU socket is empty and its alignment marker is visible. No contacts appear bent.","description":"CPU socket","imageAsset":null},{"id":"dimm_slot","label":"DIMM slot","inspection":"The DIMM slot key and retaining latches are visible; one latch remains open.","description":"DIMM slot","imageAsset":null},{"id":"atx_power_port","label":"24-pin ATX power header","inspection":"The 24-pin ATX header is keyed and clear of debris. It must remain de-energized during inspection.","description":"24-pin ATX power header","imageAsset":null}],"equipment":{"single_connection":true,"completion":[{"path":"inspected.motherboard","value":true},{"path":"inspected.cpu","value":true},{"path":"inspected.ram","value":true},{"path":"inspected.psu","value":true},{"path":"inspected.cpu_socket","value":true},{"path":"inspected.dimm_slot","value":true},{"path":"inspected.atx_power_port","value":true}]},"mechanics":["inspect_hardware"]}},{"id":"coc1_m1_p2","title":"Select a safe set","instruction":"Record the components and safety equipment needed for the work.","primaryInteraction":"select","supportingInteractions":[],"availableObjectIds":["motherboard","cpu","ram","psu","cpu_socket","dimm_slot","atx_power_port","anti_static_strap"],"feedbackIds":["coc1_m1_constraint"],"presentation":{"component":"multi_select","options":[{"id":"esd_protection","label":"Wrist strap — ESD protection"},{"id":"open_memory_latch","label":"Memory latch requires attention"},{"id":"service_live","label":"Service while energized"}],"equipment":{"single_connection":true,"selection_groups":[{"id":"processing","label":"Classify: processing","single_choice_on_tap":true,"options":[{"id":"cpu","label":"Processor"},{"id":"ram","label":"Memory module"},{"id":"psu","label":"Power supply"}]},{"id":"memory","label":"Classify: volatile memory","single_choice_on_tap":true,"options":[{"id":"cpu","label":"Processor"},{"id":"ram","label":"Memory module"},{"id":"psu","label":"Power supply"}]},{"id":"power","label":"Classify: power conversion","single_choice_on_tap":true,"options":[{"id":"cpu","label":"Processor"},{"id":"ram","label":"Memory module"},{"id":"psu","label":"Power supply"}]}],"tools":[{"id":"anti_static_strap","label":"Anti-static wrist strap","compatible_categories":["esd_ground"]},{"id":"screwdriver","label":"Phillips screwdriver","compatible_categories":["fastener"]}],"targets":[{"id":"chassis_ground","label":"Bare chassis ground point","category":"esd_ground"},{"id":"case_fastener","label":"Case fastener","category":"fastener"}],"completion":[{"path":"selection.coc1_m1_p2","operator":"present"},{"path":"classification.processing","operator":"present"},{"path":"classification.memory","operator":"present"},{"path":"classification.power","operator":"present"},{"path":"tool.chassis_ground","value":"anti_static_strap"},{"path":"tool.case_fastener","value":"screwdriver"}]},"mechanics":["select_safe_set"]}},{"id":"coc1_m1_p3","title":"Record observations","instruction":"Describe the inspected condition without inferring an unobserved fault.","primaryInteraction":"observe","supportingInteractions":[],"availableObjectIds":["motherboard","cpu","ram","psu","cpu_socket","dimm_slot","atx_power_port","anti_static_strap"],"feedbackIds":["coc1_m1_constraint"],"presentation":{"component":"observation","equipment":{"single_connection":true},"mechanics":["record_observation"]}},{"id":"coc1_m1_p4","title":"Verify readiness","instruction":"Run the readiness check against the recorded inspection.","primaryInteraction":"testRun","supportingInteractions":[],"availableObjectIds":["motherboard","cpu","ram","psu","cpu_socket","dimm_slot","atx_power_port","anti_static_strap"],"feedbackIds":["coc1_m1_evidence"],"presentation":{"evidenceActionType":"hardware_readiness_test","target":"coc1_m1_test_4","equipment":{"single_connection":true,"checks":[{"id":"inspection","label":"Inspection record","requires":[{"path":"inspected.motherboard","value":true},{"path":"inspected.cpu","value":true},{"path":"inspected.ram","value":true},{"path":"inspected.psu","value":true},{"path":"inspected.cpu_socket","value":true},{"path":"inspected.dimm_slot","value":true},{"path":"inspected.atx_power_port","value":true}],"nominal":"Components, sockets, slots, and the ATX power header were inspected.","fault":"A component, socket, slot, or power-header inspection remains incomplete."},{"id":"classification","label":"Component roles","requires":[{"path":"classification.processing","operator":"set_equals","value":["cpu"]},{"path":"classification.memory","operator":"set_equals","value":["ram"]},{"path":"classification.power","operator":"set_equals","value":["psu"]}],"nominal":"Processing, volatile memory, and power-conversion components classified.","fault":"At least one component role conflicts with the inspected specification."},{"id":"safe_work","label":"Safe work plan","requires":[{"path":"selection.coc1_m1_p2","operator":"set_equals","value":["esd_protection","open_memory_latch"]}],"nominal":"ESD controls and the unseated memory latch are recorded.","fault":"The work plan omits an observed hazard or permits energized servicing."},{"id":"notes","label":"Observation record","requires":[{"path":"observation.coc1_m1_p3","operator":"present"}],"nominal":"Inspection notes attached.","fault":"No inspection notes recorded."},{"id":"close_out","label":"Safety and documentation","requires":[{"path":"setting.work_area_safe","value":true},{"path":"setting.service_report_ready","value":true}],"nominal":"Work-area safety, contingency where required, and service handover recorded.","fault":"Complete safety close-out and the service report before final verification."}],"completion":[{"path":"result.coc1_m1_test_4","value":true}],"operations":[{"id":"close_work_area","label":"Record 5S and 3Rs work-area close-out","effects":{"work_area_safe":true},"requires":[]},{"id":"prepare_service_report","label":"Prepare the technical work report for handover","effects":{"service_report_ready":true},"requires":[{"path":"setting.work_area_safe","value":true}]}]},"mechanics":["verify_readiness"]}},{"id":"coc1_m1_p5","title":"Review evidence","instruction":"Review the safe-set decision and readiness evidence.","primaryInteraction":"review","supportingInteractions":[],"availableObjectIds":["motherboard","cpu","ram","psu","cpu_socket","dimm_slot","atx_power_port","anti_static_strap"],"feedbackIds":["coc1_m1_review"],"presentation":{"equipment":{"single_connection":true},"mechanics":["review_evidence"]}}],"interactionFamilies":["inspect","select","observe","testRun"],"feedbackCatalog":{"coc1_m1_constraint":"Inspect the component label and safety condition before recording the set.","coc1_m1_evidence":"Readiness verification records the observed hardware state.","coc1_m1_review":"Review the inspection, safety selection, and observation evidence before submission."},"reviewMetadata":{"title":"Evidence review","returnLabel":"Return to mission","confirmLabel":"Confirm evidence"}}'::jsonb)
on conflict(mission_id) do update
  set version = excluded.version, definition = excluded.definition
  where public.practice_mission_contracts.version = 'css-sag-20261011-v2';

-- Existing verified v1/v2 COC1 M1 completions continue to count toward the
-- five-mission practice gate. No completion row or evidence row is rewritten.
create or replace function public.practice_begin_quiz(p_learner uuid,p_coc text,p_id uuid,p_questions jsonb)
returns public.practice_quiz_attempts language plpgsql security invoker set search_path='' as $$
declare attempt public.practice_quiz_attempts;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_learner::text||p_coc,0));
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active')
    or not public.practice_coc_unlocked(p_coc,p_learner) then raise exception 'PRACTICE_COC_LOCKED' using errcode='42501'; end if;
  if (select count(*) from public.practice_mission_completions c join public.practice_mission_contracts d using(mission_id)
      where c.learner_id=p_learner and left(c.mission_id,4)=p_coc and (c.contract_version=d.version or (c.mission_id='coc1_m1' and d.version='css-sag-20261109-v3' and c.contract_version in ('css-sag-20261009-v1','css-sag-20261011-v2'))))<>5 then
    raise exception 'PRACTICAL_COMPLETION_REQUIRED' using errcode='22023'; end if;
  select q.* into attempt from public.practice_coc_progress p
    join public.practice_quiz_attempts q on q.id=p.quiz_attempt_id
    where p.learner_id=p_learner and p.coc_code=p_coc;
  if found then return attempt; end if;
  select * into attempt from public.practice_quiz_attempts where learner_id=p_learner and coc_code=p_coc and status<>'submitted' for update;
  if found then
    if attempt.status='generating' and attempt.created_at<now()-interval '60 seconds' then
      update public.practice_quiz_attempts set status='active' where id=attempt.id returning * into attempt;
    end if;
    return attempt;
  end if;
  if (select count(*) from public.practice_quiz_attempts where learner_id=p_learner and created_at>now()-interval '24 hours')>=8 then
    raise exception 'PRACTICE_QUIZ_DAILY_LIMIT' using errcode='54000'; end if;
  insert into public.practice_quiz_attempts(id,learner_id,coc_code,questions) values(p_id,p_learner,p_coc,p_questions) returning * into attempt;
  return attempt;
end $$;
create or replace function public.practice_submit_quiz(p_learner uuid,p_attempt uuid,p_answers jsonb)
returns public.practice_quiz_attempts language plpgsql security invoker set search_path='' as $$
declare attempt public.practice_quiz_attempts; total integer;
begin
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active') then
    raise exception 'ACTIVE_LEARNER_REQUIRED' using errcode='42501';
  end if;
  select * into strict attempt from public.practice_quiz_attempts where id=p_attempt and learner_id=p_learner for update;
  if attempt.status='submitted' then return attempt; end if;
  if attempt.status<>'active' or not public.practice_coc_unlocked(attempt.coc_code,p_learner) then raise exception 'QUIZ_NOT_ACTIVE'; end if;
  if jsonb_typeof(p_answers)<>'object' or (select count(*) from jsonb_each(p_answers))<>5
    or exists(select 1 from jsonb_array_elements(attempt.questions) q where p_answers->(q->>'id') is null
      or jsonb_typeof(p_answers->(q->>'id'))<>'number' or p_answers->>(q->>'id') !~ '^[0-3]$') then
    raise exception 'ANSWER_ALL_QUESTIONS' using errcode='22023'; end if;
  select count(*) into total from jsonb_array_elements(attempt.questions) q where p_answers->(q->>'id')=q->'answer';
  update public.practice_quiz_attempts set answers=p_answers, score=total, passed=total*100>=5*passing_percent,
    status='submitted',submitted_at=now() where id=p_attempt returning * into attempt;
  if attempt.passed then
    if (select count(*) from public.practice_mission_completions c join public.practice_mission_contracts d using(mission_id)
      where c.learner_id=p_learner and left(c.mission_id,4)=attempt.coc_code and (c.contract_version=d.version or (c.mission_id='coc1_m1' and d.version='css-sag-20261109-v3' and c.contract_version in ('css-sag-20261009-v1','css-sag-20261011-v2'))))<>5 then raise exception 'PRACTICAL_COMPLETION_REQUIRED'; end if;
    insert into public.practice_coc_progress(learner_id,coc_code,quiz_attempt_id) values(p_learner,attempt.coc_code,p_attempt) on conflict do nothing;
  end if;
  return attempt;
end $$;
revoke all on function public.practice_begin_quiz(uuid,text,uuid,jsonb),
  public.practice_submit_quiz(uuid,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.practice_begin_quiz(uuid,text,uuid,jsonb),
  public.practice_submit_quiz(uuid,uuid,jsonb) to service_role;
notify pgrst, 'reload schema';$source_v3$;
  v_expected_history jsonb := $expected_history$[{"name":"add_admin_and_instructor_roles","recorded_statements_md5":"19cd8afd18e66f3b1830c7c04c6f2bce","version":"20260728153636"},{"name":"rbac_role_helper_functions","recorded_statements_md5":"f93c943a37a86a80e2b12c2df317e256","version":"20260728153711"},{"name":"create_administrator_and_instructor_accounts","recorded_statements_md5":"913855fdb44a957f632a48b92ec77e1b","version":"20260728153837"},{"name":"lock_down_rbac_function_execute_grants","recorded_statements_md5":"cc3e3eb5f260d3bb5ffaa077d963373e","version":"20260728155035"},{"name":"add_deactivated_account_status","recorded_statements_md5":"e2338425c741f60ed5d71820b4c5f1d0","version":"20260807153938"},{"name":"foundation_identity_and_audit","recorded_statements_md5":"4f9e131be7d048b3d1f1112184da7b27","version":"20260807153940"},{"name":"classes_and_memberships","recorded_statements_md5":"7da5a7855619b4cf471ebc6c0b640c71","version":"20260807153942"},{"name":"tesda_and_content_versioning","recorded_statements_md5":"e1e72ffe7771ea9f55dbb26423d268f0","version":"20260807154024"},{"name":"assignments_attempts_and_evidence","recorded_statements_md5":"6efa94946a6740bcb8957267f34c5144","version":"20260807154026"},{"name":"gamification_resources_and_settings","recorded_statements_md5":"712246e29aafc1ffddf8fba529f39f23","version":"20260807154027"},{"name":"authoritative_workflow_rpcs","recorded_statements_md5":"50fd5d0106912fe6f086d3e15845e64f","version":"20260807154029"},{"name":"evaluation_finalization_and_release","recorded_statements_md5":"b8bacc64403b7768cebab67c93ddd7b1","version":"20260807154031"},{"name":"admin_governance_rpcs","recorded_statements_md5":"c82910f7eecc2f54428beb58915cf116","version":"20260807154033"},{"name":"class_and_content_management_rpcs","recorded_statements_md5":"80a91ba0449d3f4533b540f115d49fcc","version":"20260807155016"},{"name":"authoritative_rls","recorded_statements_md5":"8beba009006e4a6d4be8357c60190901","version":"20260807163912"},{"name":"indexes_and_legacy_quarantine","recorded_statements_md5":"f8b7af8d7991b2641b130ebc6487efdd","version":"20260807163924"},{"name":"fix_rls_policy_recursion","recorded_statements_md5":"e0b2a2175f9912ef8040875486d53ab3","version":"20260807164102"},{"name":"retire_merged_staff_role","recorded_statements_md5":"afecd29afc83af5649edc3c377eb9cfc","version":"20260808031053"},{"name":"quarantine_legacy_rating_policy","recorded_statements_md5":"389b2889aad552e06e4d716b91822cc9","version":"20260808031619"},{"name":"close_lifecycle_review_gaps","recorded_statements_md5":"fa1a2a362cdd282717f3f0eb0c513f97","version":"20260808035904"},{"name":"fix_evaluator_json_operator_precedence","recorded_statements_md5":"0bbaacf58a2eb72c28f215c6dc68f724","version":"20260808035946"},{"name":"learning_resource_storage_workflow","recorded_statements_md5":"b8f0b1e669cfe17380475f36849a9350","version":"20260810034611"},{"name":"instructor_learner_account_deactivation","recorded_statements_md5":"12fb815ef93ff01535e12b325a357472","version":"20260810034617"},{"name":"audit_retention_safe_auth_deletion","recorded_statements_md5":"c6df0c2e1e52f44738e3e6e7647bddea","version":"20260810035600"},{"name":"admin_account_removal_readiness","recorded_statements_md5":"a9cf095a685e7bbae18b36e40474234c","version":"20260810035957"},{"name":"security_definer_grant_hardening","recorded_statements_md5":"1576975d28567df2bc9a4f6aebc4502b","version":"20260810040236"},{"name":"coc2_assessment_and_assignment_policy_support","recorded_statements_md5":"1af7a9eeeb631bd6339563936feb044b","version":"20260810053319"},{"name":"grant_activity_versions_select","recorded_statements_md5":"d8573319938d955e77c1af120c2fe11d","version":"20260810054905"},{"name":"fix_extended_evaluator_json_precedence","recorded_statements_md5":"b3153dd77b5d6a23c7eacce081450c87","version":"20260810061248"},{"name":"instructor_quiz_authoring_and_ai_drafts","recorded_statements_md5":"79ba1fa7b66251ad2fd936b606f6232f","version":"20260810083108"},{"name":"quiz_private_function_grant_hardening","recorded_statements_md5":"89f28cf5a98cc8435076160ada1a392b","version":"20260810090447"},{"name":"openrouter_quiz_provider","recorded_statements_md5":"e77d644ded74bb4e6dca58c5ae6f9ce0","version":"20260810093917"},{"name":"scoped_analytics_and_reporting","recorded_statements_md5":"af1c9e1f7b7227984026dc1754c53cac","version":"20260811044757"},{"name":"learner_quiz_lifecycle","recorded_statements_md5":"fd45195b10314256761d7e28d277e55c","version":"20260812120000"},{"name":"learner_learning_path_projection","recorded_statements_md5":"1470d18d6caae0e798135c5e9932451b","version":"20260812130000"},{"name":"learner_settings_update_grant","recorded_statements_md5":"2115996e5feb96398cdf8c6909dcc4ef","version":"20260812132000"},{"name":"learner_settings_table_update_grant","recorded_statements_md5":"5b5bc28da55b99c86a1003c08d3f4acf","version":"20260812133000"},{"name":"scoped_realtime_publications","recorded_statements_md5":"e51369d98de11fd336a5cb5c108e5f34","version":"20260814120000"},{"name":"realtime_safe_quiz_scope_policies","recorded_statements_md5":"fac4c4f657c867e8893e5e0d6aafbd82","version":"20260814123000"},{"name":"teacherdesk_mvp_schema","recorded_statements_md5":"e6b18f96b7cb63d7e36a383caf479ef8","version":"20260825143532"},{"name":"teacherdesk_rls_and_rpcs","recorded_statements_md5":"91e6287ce3b715dc4b58d8ecd659dab6","version":"20260825143627"},{"name":"teacherdesk_onboarding_rpcs","recorded_statements_md5":"cf508795ac91d3d05fd17547715099aa","version":"20260825143700"},{"name":"validate_instructor_score_revisions","recorded_statements_md5":"50580a091d178e46385ecfe177fe8ac3","version":"20260929103316"},{"name":"role_scoped_support_concerns","recorded_statements_md5":"76e94f1bf3340452ebd4c971eb6ccb56","version":"20260929103333"},{"name":"practice_mission_evidence","recorded_statements_md5":"bf35980d8c4ef27f440bf14c677cb8a9","version":"20261011035806"},{"name":"coc_practice_progression","recorded_statements_md5":"a10d6df0cce9d756a1dc8a223e68276a","version":"20261011035837"},{"name":"css_practice_contracts","recorded_statements_md5":"1d84b404bbffc0ebccc5c9253f2dc5fb","version":"20261011035915"},{"name":"harden_practice_evidence_grants","recorded_statements_md5":"bcfdc85c572ce996846816fd600562cf","version":"20261011040956"},{"name":"css_drag_workspace_contracts","recorded_statements_md5":"00ccf46909419f1a9c506dcea3f08544","version":"20261011044331"}]$expected_history$::jsonb;
  v_current_history jsonb;
  v_relation record;
  v_fingerprint jsonb;
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
  v_other_contracts text;
begin
  perform set_config('lock_timeout','5s',true);
  perform set_config('statement_timeout','120s',true);
  if not pg_try_advisory_xact_lock(846216112026::bigint) then raise exception 'HOSTED_MOBILE_SYNC_ALREADY_RUNNING'; end if;
  select jsonb_agg(jsonb_build_object('version',to_jsonb(m)->>'version','name',to_jsonb(m)->>'name','recorded_statements_md5',md5((to_jsonb(m)->'statements')::text)) order by to_jsonb(m)->>'version') from supabase_migrations.schema_migrations m into v_current_history;
  if v_current_history is distinct from v_expected_history then raise exception 'HOSTED_HISTORY_CHANGED_REVIEW_REQUIRED'; end if;
  if md5(pg_get_functiondef('public.append_attempt_action(uuid,integer,text,text,jsonb,timestamp with time zone)'::regprocedure))<>'2e2f3668ce27332d029e4385210fde4c'
     or (select pg_get_userbyid(proowner)<>'postgres' or coalesce(proacl,acldefault('f',proowner))::text<>'{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' from pg_proc where oid='public.append_attempt_action(uuid,integer,text,text,jsonb,timestamp with time zone)'::regprocedure)
  then raise exception 'HOSTED_FUNCTION_CHANGED:append_attempt_action(uuid,integer,text,text,jsonb,timestamp with time zone)'; end if;
  if md5(pg_get_functiondef('public.practice_begin_quiz(uuid,text,uuid,jsonb)'::regprocedure))<>'58a7aebe47464a222d5b13769c860ca5'
     or (select pg_get_userbyid(proowner)<>'postgres' or coalesce(proacl,acldefault('f',proowner))::text<>'{postgres=X/postgres,service_role=X/postgres}' from pg_proc where oid='public.practice_begin_quiz(uuid,text,uuid,jsonb)'::regprocedure)
  then raise exception 'HOSTED_FUNCTION_CHANGED:practice_begin_quiz(uuid,text,uuid,jsonb)'; end if;
  if md5(pg_get_functiondef('public.practice_submit_quiz(uuid,uuid,jsonb)'::regprocedure))<>'b158dd07e0da6ad2198f109c2231c4f8'
     or (select pg_get_userbyid(proowner)<>'postgres' or coalesce(proacl,acldefault('f',proowner))::text<>'{postgres=X/postgres,service_role=X/postgres}' from pg_proc where oid='public.practice_submit_quiz(uuid,uuid,jsonb)'::regprocedure)
  then raise exception 'HOSTED_FUNCTION_CHANGED:practice_submit_quiz(uuid,uuid,jsonb)'; end if;
  select md5(string_agg(mission_id||version||definition::text,'|' order by mission_id)) from public.practice_mission_contracts where mission_id<>'coc1_m1' into v_other_contracts;
  for v_relation in
    select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname not in ('pg_catalog','information_schema') and n.nspname not like 'pg_toast%'
      and n.nspname not like 'pg_temp%' and c.relkind in ('r','p') and not c.relispartition
      and (n.nspname,c.relname) not in (('public','practice_mission_contracts'),('supabase_migrations','schema_migrations'))
    order by n.nspname,c.relname
  loop
    execute format('select jsonb_build_object(''rows'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by md5(to_jsonb(t)::text)),''''))) from %I.%I t',v_relation.nspname,v_relation.relname) into v_fingerprint;
    v_before:=v_before||jsonb_build_object(v_relation.nspname||'.'||v_relation.relname,v_fingerprint);
  end loop;
  execute v_idempotency;
  execute v_v3;
  for v_relation in
    select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname not in ('pg_catalog','information_schema') and n.nspname not like 'pg_toast%'
      and n.nspname not like 'pg_temp%' and c.relkind in ('r','p') and not c.relispartition
      and (n.nspname,c.relname) not in (('public','practice_mission_contracts'),('supabase_migrations','schema_migrations'))
    order by n.nspname,c.relname
  loop
    execute format('select jsonb_build_object(''rows'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by md5(to_jsonb(t)::text)),''''))) from %I.%I t',v_relation.nspname,v_relation.relname) into v_fingerprint;
    v_after:=v_after||jsonb_build_object(v_relation.nspname||'.'||v_relation.relname,v_fingerprint);
  end loop;
  if v_after is distinct from v_before then raise exception 'PROTECTED_DATA_CHANGED_ROLLBACK_REQUIRED'; end if;
  if (select md5(string_agg(mission_id||version||definition::text,'|' order by mission_id)) from public.practice_mission_contracts where mission_id<>'coc1_m1') is distinct from v_other_contracts then raise exception 'OTHER_19_CONTRACTS_CHANGED'; end if;
  if (select version from public.practice_mission_contracts where mission_id='coc1_m1')<>'css-sag-20261109-v3'
     or to_regclass('public.attempt_actions_client_action_id_idx') is null
     or has_function_privilege('authenticated','public.practice_begin_quiz(uuid,text,uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.practice_submit_quiz(uuid,uuid,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','public.practice_begin_quiz(uuid,text,uuid,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','public.practice_submit_quiz(uuid,uuid,jsonb)','EXECUTE')
  then raise exception 'HOSTED_POSTCONDITIONS_FAILED'; end if;
  insert into supabase_migrations.schema_migrations(version,name,statements)
    values ('20261111160000','hosted_mobile_v3_and_action_idempotency',array[v_idempotency,v_v3]);
end
$hosted_mobile_approval$;
