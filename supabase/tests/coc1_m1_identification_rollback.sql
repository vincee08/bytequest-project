-- Source-only rollback-safe regression for the versioned COC1 M1 practice
-- contract. Run only in a separately approved isolated database lifecycle.
\echo 1..1
begin;

-- Isolate the COC1 quiz gate from lessons published in the target database
-- (rolled back with everything else): this regression needs no curriculum
-- topic, so none is required.
update public.curriculum_topics set archived_at = now() where archived_at is null;

do $test$
declare
  v_user uuid := gen_random_uuid();
  v_email text := 'rollback-m1-' || v_user::text || '@bytequest.invalid';
  v_contract public.practice_mission_contracts%rowtype;
  v_actions jsonb;
  v_action jsonb;
  v_target text;
  v_group record;
  v_part record;
  v_run integer;
  v_seq integer;
  v_first_classification_id text;
  v_evidence_id bigint;
  v_quiz_id uuid := gen_random_uuid();
  v_questions jsonb := '[{"id":"q1","answer":0},{"id":"q2","answer":0},{"id":"q3","answer":0},{"id":"q4","answer":0},{"id":"q5","answer":0}]'::jsonb;
  v_answers jsonb := '{"q1":0,"q2":0,"q3":0,"q4":0,"q5":0}'::jsonb;
begin
  select * into strict v_contract from public.practice_mission_contracts
    where mission_id = 'coc1_m1';
  if v_contract.version <> 'css-sag-20261109-v3'
     or v_contract.definition #> '{phases,0,presentation,equipment,placement}' is not null
     or jsonb_array_length(v_contract.definition #> '{phases,0,presentation,equipment,completion}') <> 7
     or (select count(*) from jsonb_array_elements(v_contract.definition #> '{phases,1,presentation,equipment,selection_groups}') g
         where g->>'single_choice_on_tap' = 'true') <> 3 then
    raise exception 'COC1_M1_IDENTIFICATION_CONTRACT_INVALID';
  end if;
  if (select count(*) from public.practice_mission_contracts where version = 'css-sag-20261109-v3') <> 1 then
    raise exception 'UNRELATED_CONTRACT_VERSION_CHANGED';
  end if;
  if has_function_privilege('authenticated',
      'public.practice_verify_mission(uuid,text)','EXECUTE')
     or has_function_privilege('authenticated',
      'public.practice_begin_quiz(uuid,text,uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated',
      'public.practice_submit_quiz(uuid,uuid,jsonb)','EXECUTE') then
    raise exception 'PRACTICE_VERIFICATION_EXPOSED_TO_CLIENT';
  end if;

  -- Auth signup creates the active learner profile. The entire fixture rolls back.
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values ('00000000-0000-0000-0000-000000000000'::uuid,v_user,
    'authenticated','authenticated',v_email,'',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Rollback COC1 learner"}'::jsonb,now(),now());
  if not exists(select 1 from public.profiles where user_id=v_user and role='learner' and status='active') then
    raise exception 'ROLLBACK_LEARNER_PROFILE_MISSING';
  end if;

  -- First timeline contains one incorrect processing identification. No
  -- placement action is needed in either timeline.
  for v_run in 1..2 loop
    if v_run = 2 then
      insert into public.practice_mission_actions(learner_id,client_action_id,
        mission_id,phase_id,action_type,target,value,client_occurred_at)
      values(v_user,'rollback-m1-discard','coc1_m1','coc1_m1_p1',
        'practice_progress_discarded',null,'{"reason":"test_retry"}'::jsonb,clock_timestamp());
    end if;
    v_actions := '[]'::jsonb;
    for v_target in select unnest(array['motherboard','cpu','ram','psu',
      'cpu_socket','dimm_slot','atx_power_port']) loop
      v_actions := v_actions || jsonb_build_array(jsonb_build_object(
        'phase','coc1_m1_p1','type','object_inspected','target',v_target,
        'value',jsonb_build_object('input_method','tap')));
    end loop;
    for v_group in select * from (values
      ('processing',case when v_run=1 then 'ram' else 'cpu' end),
      ('memory','ram'),('power','psu')) g(group_id,component_id) loop
      v_actions := v_actions || jsonb_build_array(jsonb_build_object(
        'phase','coc1_m1_p2','type','selection_confirmed',
        'target','coc1_m1_p2_'||v_group.group_id,
        'value',jsonb_build_object('selection_group',v_group.group_id,
          'selected_ids',jsonb_build_array(v_group.component_id),'input_method','tap')));
    end loop;
    if v_run=2 then
      -- A second, distinct tap with the same answer is harmless before retest.
      v_actions := v_actions || jsonb_build_array(jsonb_build_object(
        'phase','coc1_m1_p2','type','selection_confirmed',
        'target','coc1_m1_p2_processing',
        'value','{"selection_group":"processing","selected_ids":["cpu"],"input_method":"tap"}'::jsonb));
    end if;
    v_actions := v_actions || '[
      {"phase":"coc1_m1_p2","type":"selection_confirmed","target":"coc1_m1_p2","value":{"selected_ids":["esd_protection","open_memory_latch"]}},
      {"phase":"coc1_m1_p2","type":"tool_attempted","target":"chassis_ground","value":{"tool_id":"anti_static_strap"}},
      {"phase":"coc1_m1_p2","type":"tool_attempted","target":"case_fastener","value":{"tool_id":"screwdriver"}},
      {"phase":"coc1_m1_p3","type":"observation_recorded","target":"coc1_m1_p3","value":{"observation":"Power isolated; memory latch open."}},
      {"phase":"coc1_m1_p4","type":"equipment_operation","target":"close_work_area","value":{}},
      {"phase":"coc1_m1_p4","type":"equipment_operation","target":"prepare_service_report","value":{}},
      {"phase":"coc1_m1_p4","type":"test_started","target":"coc1_m1_test_4","value":{}},
      {"phase":"coc1_m1_p4","type":"test_completed","target":"coc1_m1_test_4","value":{}}
    ]'::jsonb;
    v_seq := 0;
    for v_action in select value from jsonb_array_elements(v_actions) loop
      if v_run=1 and v_action->>'type'='test_completed' then
        v_action := jsonb_set(v_action,'{value}',
          '{"simulation_valid":true,"measured_result":{"operating":true}}'::jsonb);
      end if;
      v_seq := v_seq + 1;
      insert into public.practice_mission_actions(learner_id,client_action_id,
        mission_id,phase_id,action_type,target,value,client_occurred_at)
      values(v_user,format('rollback-m1-%s-%s',v_run,v_seq),'coc1_m1',
        v_action->>'phase',v_action->>'type',v_action->>'target',
        v_action->'value',clock_timestamp());
      if v_run=2 and v_action->>'type'='selection_confirmed'
         and v_action->'value'->>'selection_group'='processing'
         and v_first_classification_id is null then
        v_first_classification_id := format('rollback-m1-%s-%s',v_run,v_seq);
      end if;
    end loop;
    if v_run=1 then
      begin
        perform public.practice_verify_mission(v_user,'coc1_m1');
        raise exception 'INCORRECT_IDENTIFICATION_VERIFIED';
      exception when sqlstate '22023' then
        if sqlerrm <> 'PRACTICE_WORK_INCOMPLETE:coc1_m1_p4' then raise; end if;
      end;
      if exists(select 1 from public.practice_mission_completions
          where learner_id=v_user and mission_id='coc1_m1') then
        raise exception 'INCORRECT_IDENTIFICATION_AWARDED_COMPLETION';
      end if;
    else
      -- Client retry with an acknowledged ID must not append another action.
      insert into public.practice_mission_actions(learner_id,client_action_id,
        mission_id,phase_id,action_type,target,value,client_occurred_at)
      select learner_id,client_action_id,mission_id,phase_id,action_type,target,
        value,client_occurred_at from public.practice_mission_actions
      where learner_id=v_user and client_action_id=v_first_classification_id
      on conflict(learner_id,client_action_id) do nothing;
      if (select count(*) from public.practice_mission_actions
          where learner_id=v_user and client_action_id=v_first_classification_id) <> 1 then
        raise exception 'IDENTIFICATION_RETRY_DUPLICATED_EVIDENCE';
      end if;
      perform public.practice_verify_mission(v_user,'coc1_m1');
      select evidence_through_id into strict v_evidence_id
        from public.practice_mission_completions
        where learner_id=v_user and mission_id='coc1_m1'
          and contract_version='css-sag-20261109-v3';
    end if;
  end loop;

  -- Previously acknowledged v2 placement records remain append-only and do
  -- not invalidate the identification timeline under v3.
  for v_part in select * from (values
    ('motherboard','motherboard_position'),('cpu','cpu_position'),
    ('ram','ram_position'),('psu','psu_position')) p(item_id,slot_id) loop
    insert into public.practice_mission_actions(learner_id,client_action_id,
      mission_id,phase_id,action_type,target,value,client_occurred_at)
    values(v_user,'rollback-legacy-'||v_part.item_id,'coc1_m1','coc1_m1_p1',
      'placement_attempted',v_part.slot_id,
      jsonb_build_object('item_id',v_part.item_id,'destination_id',v_part.slot_id),
      clock_timestamp());
  end loop;
  perform public.practice_verify_mission(v_user,'coc1_m1');

  -- Historical verified v1/v2 rows count toward the five-mission quiz gate.
  -- Test-only rows for the other four missions are rolled back.
  insert into public.practice_mission_completions(learner_id,mission_id,
    contract_version,evidence_through_id)
  select v_user,'coc1_m'||n,'css-sag-20261011-v2',v_evidence_id
    from generate_series(2,5) n;
  update public.practice_mission_completions
    set contract_version='css-sag-20261009-v1'
    where learner_id=v_user and mission_id='coc1_m1';
  perform public.practice_begin_quiz(v_user,'coc1',v_quiz_id,v_questions);
  update public.practice_mission_completions
    set contract_version='css-sag-20261011-v2'
    where learner_id=v_user and mission_id='coc1_m1';
  perform public.practice_begin_quiz(v_user,'coc1',v_quiz_id,v_questions);
  update public.practice_mission_completions
    set contract_version='unsupported-version'
    where learner_id=v_user and mission_id='coc1_m1';
  begin
    perform public.practice_begin_quiz(v_user,'coc1',v_quiz_id,v_questions);
    raise exception 'UNSUPPORTED_COMPLETION_UNLOCKED_QUIZ';
  exception when sqlstate '22023' then
    if sqlerrm <> 'PRACTICAL_COMPLETION_REQUIRED' then raise; end if;
  end;
  update public.practice_quiz_attempts set status='active' where id=v_quiz_id;
  begin
    perform public.practice_submit_quiz(v_user,v_quiz_id,v_answers);
    raise exception 'UNSUPPORTED_COMPLETION_AWARDED_COC';
  exception when raise_exception then
    if sqlerrm <> 'PRACTICAL_COMPLETION_REQUIRED' then raise; end if;
  end;
  if exists(select 1 from public.practice_coc_progress where learner_id=v_user and coc_code='coc1') then
    raise exception 'UNSUPPORTED_COMPLETION_CREATED_PROGRESS';
  end if;
  update public.practice_mission_completions
    set contract_version='css-sag-20261011-v2'
    where learner_id=v_user and mission_id='coc1_m1';
  perform public.practice_submit_quiz(v_user,v_quiz_id,v_answers);
  if not exists(select 1 from public.practice_coc_progress
      where learner_id=v_user and coc_code='coc1') then
    raise exception 'HISTORICAL_COMPLETION_DID_NOT_UNLOCK_COC';
  end if;
end
$test$;

rollback;
\echo ok 1 - COC1 M1 identification and historical practice versions
