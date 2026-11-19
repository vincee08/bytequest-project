-- Re-defense slice A1.1: shared simulation replay, practice verification on
-- top of it, and server-computed practice run metrics.
--
-- * private.simulation_replay(definition, actions) is the pure, never-raising
--   replay of a mission contract. It reproduces every action kind of the
--   former practice_verify_mission loop (20261009090000) with identical
--   validity and terminal rules, and adds:
--     - placement_removed {item_id}: removes placed.<item>, applies the item's
--       optional removal_effects and counts a correction for the part;
--     - placement items may declare `requires` (operation condition format);
--     - re-placing a removed part is valid; moving a placed part or a
--       single-connection cable to another destination counts a correction;
--     - items/sources marked "required": false do not block their phase.
--   Existing contracts declare none of these keys, so their replay is
--   unchanged (verified by supabase/tests/simulation_replay_rollback.sql).
-- * public.practice_verify_mission keeps its signature, exceptions and
--   completion row, checks public.practice_mission_unlocked, and records a
--   verified practice_mission_runs row.
-- * public.practice_record_failed_verification records an incomplete run.
-- * public.practice_completion_version_accepted centralises which earlier
--   contract versions keep counting toward the COC practice quiz gate.
--
-- Everything here is SECURITY INVOKER and callable only by the trusted server.

begin;

create function private.simulation_replay(p_definition jsonb, p_actions jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  a jsonb;
  a_phase text;
  a_type text;
  a_target text;
  a_at timestamptz;
  phases jsonb;
  phase jsonb;
  p jsonb;
  eq jsonb;
  panel jsonb;
  item jsonb;
  destination jsonb;
  field jsonb;
  v jsonb;
  state jsonb := '{"revision":0}'::jsonb;
  done jsonb := '{}'::jsonb;
  family text;
  kind text;
  key text;
  actual jsonb;
  valid boolean;
  terminal boolean;
  revision integer := 0;
  saved_state jsonb;
  saved_revision integer;
  saved_done jsonb;
  target_key text;
  correction_key text;
  link_prefix text;
  invalid jsonb := '{}'::jsonb;
  corrections jsonb := '{}'::jsonb;
  phase_invalid jsonb := '{}'::jsonb;
  action_count integer := 0;
  invalid_count integer := 0;
  correction_count integer := 0;
  first_at timestamptz;
  last_at timestamptz;
begin
  phases := case when jsonb_typeof(p_definition->'phases') = 'array'
    then p_definition->'phases' else '[]'::jsonb end;

  for a in select x from jsonb_array_elements(
      case when jsonb_typeof(p_actions) = 'array' then p_actions else '[]'::jsonb end) x loop
    if jsonb_typeof(a) <> 'object' then continue; end if;
    begin
      a_at := (a->>'occurred_at')::timestamptz;
    exception when others then
      a_at := null;
    end;
    if a_at is not null then
      first_at := least(coalesce(first_at, a_at), a_at);
      last_at := greatest(coalesce(last_at, a_at), a_at);
    end if;

    a_phase := a->>'phase_id';
    a_type := a->>'action_type';
    a_target := a->>'target';
    v := case when jsonb_typeof(a->'value') = 'object' then a->'value' else '{}'::jsonb end;
    phase := null;
    select x into phase from jsonb_array_elements(phases) x where x->>'id' = a_phase;
    if phase is null then continue; end if;
    p := phase->'presentation';
    eq := p->'equipment';
    family := phase->>'primaryInteraction';
    kind := coalesce(v->>'runtime_action_type', a_type);
    if kind is null or kind not in ('object_inspected', 'placement_attempted', 'placement_removed',
        'connection_created', 'configuration_applied', 'sequence_reordered', 'tool_attempted',
        'selection_confirmed', 'scenario_decision', 'diagnostic_action', 'equipment_operation',
        'test_started', 'test_completed', 'observation_recorded', 'result_interpreted') then
      continue;
    end if;

    action_count := action_count + 1;
    valid := true;
    terminal := false;
    target_key := null;
    correction_key := null;
    saved_state := state;
    saved_revision := revision;
    saved_done := done;
    item := null;
    destination := null;
    panel := null;

    begin
      -- Client compatibility flags, snapshots, measured results and
      -- phase_completed are never trusted.
      case kind
      when 'object_inspected' then
        valid := exists(select 1 from jsonb_array_elements(p_definition->'scene'->'objects') o where o->>'id' = a_target);
        if valid then state := state || jsonb_build_object('inspected.'||a_target, true); end if;
        if family = 'inspect' then terminal := not exists(select 1 from jsonb_array_elements(p->'objects') o
          where coalesce(state->>('inspected.'||(o->>'id')), 'false') <> 'true'); end if;
      when 'placement_attempted' then
        panel := coalesce(eq->'placement', p);
        select x into item from jsonb_array_elements(panel->'items') x where x->>'id' = v->>'item_id';
        select x into destination from jsonb_array_elements(panel->'destinations') x where x->>'id' = v->>'destination_id';
        if v->>'item_id' is not null then target_key := 'item:'||(v->>'item_id'); end if;
        valid := item is not null and destination is not null
          and coalesce(destination->'socket_categories', destination->'accepted_categories') @> jsonb_build_array(item->'category')
          and (item->>'seating_orientation' is null or item->>'seating_orientation' = v->>'orientation')
          and not exists(select 1 from jsonb_array_elements_text(coalesce(item->'requires_placements', '[]')) x
            where state->('placed.'||x) is null)
          and public.practice_conditions_met(item->'requires', state)
          and not exists(select 1 from jsonb_each(state) s where s.key like 'placed.%'
            and s.key <> 'placed.'||(v->>'item_id') and s.value = v->'destination_id');
        if valid then
          if state->('placed.'||(v->>'item_id')) is not null
             and state->('placed.'||(v->>'item_id')) <> v->'destination_id' then
            correction_key := target_key;
          end if;
          state := state || jsonb_build_object('placed.'||(v->>'item_id'), v->'destination_id');
        end if;
        if family = 'place' then terminal := not exists(select 1 from jsonb_array_elements(panel->'items') o
          where coalesce(o->>'required', 'true') <> 'false' and state->('placed.'||(o->>'id')) is null); end if;
      when 'placement_removed' then
        panel := coalesce(eq->'placement', p);
        select x into item from jsonb_array_elements(panel->'items') x where x->>'id' = v->>'item_id';
        if v->>'item_id' is not null then target_key := 'item:'||(v->>'item_id'); end if;
        valid := item is not null and state ? ('placed.'||(v->>'item_id'));
        if valid then
          state := state - ('placed.'||(v->>'item_id'));
          for key, actual in select e.key, e.value from jsonb_each(
              case when jsonb_typeof(item->'removal_effects') = 'object' then item->'removal_effects' else '{}'::jsonb end) e loop
            state := state || jsonb_build_object('setting.'||key, actual);
          end loop;
          correction_key := target_key;
        end if;
      when 'connection_created' then
        panel := coalesce(eq->'connection', p);
        select x into item from jsonb_array_elements(panel->'sources') x where x->>'id' = v->>'source_id';
        select x into destination from jsonb_array_elements(panel->'destinations') x where x->>'id' = v->>'destination_id';
        if v->>'source_id' is not null then target_key := 'connection:'||(v->>'source_id'); end if;
        valid := item is not null and destination is not null and item->>'id' <> destination->>'id'
          and (coalesce(item->'interfaces', '[]') = '[]' or item->'interfaces' @> jsonb_build_array(destination->'interface'));
        if valid then
          link_prefix := 'link.'||(v->>'source_id')||'>';
          if eq->>'single_connection' = 'true' then
            if exists(select 1 from jsonb_each(state) s where left(s.key, length(link_prefix)) = link_prefix
                and s.key <> link_prefix||(v->>'destination_id')) then
              correction_key := target_key;
            end if;
            select coalesce(jsonb_object_agg(s.key, s.value), '{}') into state from jsonb_each(state) s
              where left(s.key, length(link_prefix)) <> link_prefix;
          end if;
          state := state || jsonb_build_object(link_prefix||(v->>'destination_id'), true);
        end if;
        if family = 'connect' then terminal := not exists(select 1 from jsonb_array_elements(panel->'sources') o
          where coalesce(o->>'required', 'true') <> 'false'
            and not exists(select 1 from jsonb_each(state) s where s.key like 'link.'||(o->>'id')||'>%' and s.value = 'true')); end if;
      when 'configuration_applied' then
        panel := coalesce(eq->'configuration', p);
        for field in select x from jsonb_array_elements(panel->'fields') x loop
          actual := v->'values'->(field->>'id');
          key := actual #>> '{}';
          if actual is null or actual = 'null' or btrim(key) = '' then valid := false;
          elsif field->>'type' = 'toggle' and jsonb_typeof(actual) <> 'boolean' then valid := false;
          elsif field->>'type' = 'dropdown' and not exists(select 1 from jsonb_array_elements(field->'options') o where o->'id' = actual) then valid := false;
          elsif field->>'format' = 'ipv4' and not (key ~ '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$'
            and not exists(select 1 from unnest(string_to_array(key, '.')) octet where octet::integer > 255)) then valid := false;
          elsif field->>'format' = 'port' and not (key ~ '^[0-9]{1,5}$' and key::integer between 1 and 65535) then valid := false;
          end if;
          if actual is not null then state := state || jsonb_build_object('config.'||(field->>'id'), actual); end if;
        end loop;
        if state ? 'setting.restarted' then state := state || '{"setting.restarted":false}'; end if;
        if v->'values' ? 'service_control' then
          state := state || jsonb_build_object('setting.service_running', v->'values'->>'service_control' <> 'stop');
        end if;
        terminal := family = 'configure' and valid;
      when 'sequence_reordered' then
        valid := jsonb_typeof(v->'order') = 'array' and
          jsonb_array_length(v->'order') = jsonb_array_length(p->'items')
          and not exists(select 1 from jsonb_array_elements(p->'items') o where not v->'order' @> jsonb_build_array(o->'id'))
          and not exists(select 1 from jsonb_array_elements(eq->'precedence') edge
            where (select ordinality from jsonb_array_elements_text(v->'order') with ordinality t(value, ordinality) where t.value = edge->>'before')
              >= (select ordinality from jsonb_array_elements_text(v->'order') with ordinality t(value, ordinality) where t.value = edge->>'after'));
        state := state || jsonb_build_object('sequence.'||a_phase, coalesce(valid, false), 'order.'||a_phase, v->'order');
        terminal := family = 'sequence' and valid;
      when 'tool_attempted' then
        select x into item from jsonb_array_elements(coalesce(eq->'tools', p->'tools')) x where x->>'id' = v->>'tool_id';
        select x into destination from jsonb_array_elements(coalesce(eq->'targets', p->'targets')) x where x->>'id' = a_target;
        if a_target is not null then target_key := 'tool:'||a_target; end if;
        valid := item is not null and destination is not null and
          (coalesce(item->'compatible_categories', '[]') = '[]' or item->'compatible_categories' @> jsonb_build_array(destination->'category'));
        if valid then state := state || jsonb_build_object('tool.'||a_target, v->'tool_id'); end if;
        terminal := family = 'tool' and valid;
      when 'selection_confirmed' then
        if v->>'selection_group' is not null then
          select x into panel from jsonb_array_elements(eq->'selection_groups') x where x->>'id' = v->>'selection_group';
          key := 'classification.'||(v->>'selection_group');
        else
          panel := p;
          key := 'selection.'||a_phase;
        end if;
        valid := panel is not null and jsonb_typeof(v->'selected_ids') = 'array' and jsonb_array_length(v->'selected_ids') > 0
          and not exists(select 1 from jsonb_array_elements(v->'selected_ids') id where not exists(
            select 1 from jsonb_array_elements(coalesce(panel->'options', to_jsonb(array(
              select jsonb_build_object('id', x) from jsonb_array_elements_text(phase->'availableObjectIds') x)))) o
            where o->'id' = id));
        if valid then state := state || jsonb_build_object(key, v->'selected_ids'); end if;
        terminal := family = 'select' and valid and v->>'selection_group' is null;
      when 'scenario_decision' then
        select x into item from jsonb_array_elements(p->'choices') x where x->>'id' = a_target;
        valid := item is not null;
        if valid then
          state := state || jsonb_build_object('decision.'||a_phase, a_target);
          for key, actual in select e.key, e.value from jsonb_each(coalesce(item->'equipment_effects', '{}')) e loop
            state := state || jsonb_build_object('setting.'||key, actual);
          end loop;
        end if;
        terminal := family = 'decide' and valid;
      when 'diagnostic_action' then
        select x into item from jsonb_array_elements(p->'diagnostic_actions') x where x->>'id' = a_target;
        valid := item is not null and public.practice_conditions_met(item->'requires', state);
        if valid then state := state || jsonb_build_object('fact.'||(item->>'reveals_fact_id'), true); end if;
        terminal := family = 'troubleshoot' and not exists(select 1 from jsonb_array_elements_text(p->'required_fact_ids') f
          where state->('fact.'||f) <> 'true' or state->('fact.'||f) is null);
      when 'equipment_operation' then
        select x into item from jsonb_array_elements(eq->'operations') x where x->>'id' = a_target;
        if a_target is not null then target_key := 'operation:'||a_target; end if;
        valid := item is not null and public.practice_conditions_met(item->'requires', state);
        if valid then
          for key, actual in select e.key, e.value from jsonb_each(coalesce(item->'effects', '{}')) e loop
            state := state || jsonb_build_object('setting.'||key, actual);
          end loop;
          state := state || jsonb_build_object('operation.'||a_target, true);
        end if;
      when 'test_started' then
        valid := a_target = coalesce(p->>'target', a_phase);
        if valid then state := state || jsonb_build_object('test_started.'||a_target, true); end if;
      when 'test_completed' then
        valid := a_target = coalesce(p->>'target', a_phase) and state->>('test_started.'||a_target) = 'true';
        if valid then
          terminal := jsonb_array_length(eq->'checks') > 0 and not exists(select 1 from jsonb_array_elements(eq->'checks') c
            where not public.practice_conditions_met(c->'requires', state));
          state := state || jsonb_build_object('result.'||a_target, jsonb_build_object('operating', terminal, 'revision', revision));
          if p->>'test_reveals_fact_id' is not null then
            state := state || jsonb_build_object('fact.'||(p->>'test_reveals_fact_id'), true);
          end if;
          terminal := family = 'testRun' and (coalesce(p->>'requires_interpretation', 'false') = 'false');
        end if;
      when 'observation_recorded' then
        valid := length(btrim(v->>'observation')) > 0 and a_target = a_phase;
        if valid then state := state || jsonb_build_object('observation.'||a_phase, v->'observation'); end if;
        terminal := family = 'observe' and valid;
      when 'result_interpreted' then
        valid := length(btrim(v->>'interpretation')) > 0 and a_target = a_phase;
        if valid then state := state || jsonb_build_object('interpretation.'||a_phase, v->'interpretation'); end if;
        terminal := valid and (family = 'interpret' or family = 'testRun' and state ? ('result.'||coalesce(p->>'target', a_phase)));
      end case;

      if (coalesce(valid, false) or kind = 'configuration_applied') and kind in ('connection_created', 'configuration_applied',
          'placement_attempted', 'placement_removed', 'sequence_reordered', 'scenario_decision', 'selection_confirmed',
          'equipment_operation', 'tool_attempted') then
        revision := revision + 1;
        state := state || jsonb_build_object('revision', revision);
      end if;
      if not coalesce(valid, false) and
         (kind = 'configuration_applied' and family = 'configure' or kind = 'sequence_reordered' and family = 'sequence') then
        done := done - a_phase;
      elsif coalesce(valid, false) and terminal then
        done := done || jsonb_build_object(a_phase, true);
      end if;
    exception when others then
      -- A malformed learner value is an invalid action, never a replay error.
      state := saved_state;
      revision := saved_revision;
      done := saved_done;
      valid := false;
      correction_key := null;
    end;

    if not coalesce(valid, false) then
      target_key := coalesce(target_key, 'phase:'||a_phase);
      invalid := invalid || jsonb_build_object(target_key, coalesce((invalid->>target_key)::integer, 0) + 1);
      phase_invalid := phase_invalid || jsonb_build_object(a_phase, coalesce((phase_invalid->>a_phase)::integer, 0) + 1);
      invalid_count := invalid_count + 1;
    elsif correction_key is not null then
      corrections := corrections || jsonb_build_object(correction_key, coalesce((corrections->>correction_key)::integer, 0) + 1);
      correction_count := correction_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'done', done,
    'state', state,
    'invalid', invalid,
    'corrections', corrections,
    'phase_invalid', phase_invalid,
    'action_count', action_count,
    'invalid_count', invalid_count,
    'correction_count', correction_count,
    'first_at', first_at,
    'last_at', last_at);
exception when others then
  return jsonb_build_object(
    'done', '{}'::jsonb,
    'state', '{"revision":0}'::jsonb,
    'invalid', '{}'::jsonb,
    'corrections', '{}'::jsonb,
    'phase_invalid', '{}'::jsonb,
    'action_count', 0,
    'invalid_count', 0,
    'correction_count', 0,
    'first_at', null,
    'last_at', null,
    'error', sqlstate);
end
$$;

comment on function private.simulation_replay(jsonb, jsonb) is
  'Pure replay of a mission contract over ordered actions {action_type,target,phase_id,value,occurred_at}. Never raises. Returns done, state, invalid/correction counts per target and phase, and run timestamps.';

-- The current practice run of a learner: every action after the latest
-- practice_progress_discarded marker. Action times are client times bounded by
-- the server receipt time (never later, and at most one day earlier).
create function private.practice_run_replay(p_learner uuid, p_mission text, p_definition jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  first_id bigint;
  last_id bigint;
  actions jsonb;
begin
  select coalesce(max(id), 0) into first_id from public.practice_mission_actions
    where learner_id = p_learner and mission_id = p_mission and action_type = 'practice_progress_discarded';
  select coalesce(jsonb_agg(jsonb_build_object(
      'action_type', a.action_type, 'target', a.target, 'phase_id', a.phase_id, 'value', a.value,
      'occurred_at', greatest(least(a.client_occurred_at, a.created_at), a.created_at - interval '1 day'))
      order by a.id), '[]'::jsonb), max(a.id)
    into actions, last_id
    from public.practice_mission_actions a
    where a.learner_id = p_learner and a.mission_id = p_mission and a.id > first_id;
  return private.simulation_replay(p_definition, actions)
    || jsonb_build_object('evidence_through_id', last_id);
end
$$;

-- Appends one practice run summary unless the latest run of this learner and
-- mission already summarises the same evidence window with the same outcome.
create function private.practice_record_run(p_learner uuid, p_mission text, p_contract public.practice_mission_contracts,
  p_replay jsonb, p_outcome text, p_failure text)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  phase jsonb;
  steps jsonb := '{}'::jsonb;
  started timestamptz := (p_replay->>'first_at')::timestamptz;
  ended timestamptz := (p_replay->>'last_at')::timestamptz;
  previous public.practice_mission_runs;
  next_number integer;
begin
  for phase in select x from jsonb_array_elements(p_contract.definition->'phases') x loop
    if phase->>'primaryInteraction' = 'review' then continue; end if;
    steps := steps || jsonb_build_object(phase->>'id', jsonb_build_object(
      'done', coalesce(p_replay->'done'->>(phase->>'id'), 'false') = 'true',
      'invalid', coalesce((p_replay->'phase_invalid'->>(phase->>'id'))::integer, 0)));
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('practice-run:'||p_learner::text||':'||p_mission, 0));
  select * into previous from public.practice_mission_runs
    where learner_id = p_learner and mission_id = p_mission
    order by run_number desc, created_at desc limit 1;
  if found and previous.outcome = p_outcome
     and previous.contract_version = p_contract.version
     and previous.started_at is not distinct from started
     and previous.ended_at is not distinct from ended
     and previous.action_count = coalesce((p_replay->>'action_count')::integer, 0)
     and previous.invalid_count = coalesce((p_replay->>'invalid_count')::integer, 0)
     and previous.correction_count = coalesce((p_replay->>'correction_count')::integer, 0)
     and previous.failure_code is not distinct from p_failure then
    return;
  end if;
  select count(*)::integer + 1 into next_number from public.practice_mission_runs
    where learner_id = p_learner and mission_id = p_mission;
  insert into public.practice_mission_runs(learner_id, mission_id, contract_version, run_number,
    started_at, ended_at, duration_seconds, action_count, invalid_count, correction_count,
    outcome, step_results, failure_code)
  values (p_learner, p_mission, p_contract.version, next_number, started, ended,
    case when started is null or ended is null then null
      else greatest(0, floor(extract(epoch from ended - started)))::integer end,
    coalesce((p_replay->>'action_count')::integer, 0),
    coalesce((p_replay->>'invalid_count')::integer, 0),
    coalesce((p_replay->>'correction_count')::integer, 0),
    p_outcome, steps, p_failure);
end
$$;

create or replace function public.practice_verify_mission(p_learner uuid, p_mission text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  contract public.practice_mission_contracts;
  replayed jsonb;
  phase jsonb;
  last_id bigint;
begin
  if not exists(select 1 from public.profiles where user_id = p_learner and role = 'learner' and status = 'active')
    or not public.practice_mission_unlocked(p_mission, p_learner) then
    raise exception 'PRACTICE_COC_LOCKED' using errcode = '42501';
  end if;
  select * into strict contract from public.practice_mission_contracts where mission_id = p_mission;
  replayed := private.practice_run_replay(p_learner, p_mission, contract.definition);
  for phase in select x from jsonb_array_elements(contract.definition->'phases') x loop
    if phase->>'primaryInteraction' = 'review' then continue; end if;
    if coalesce(replayed->'done'->>(phase->>'id'), 'false') <> 'true'
      or not public.practice_conditions_met(phase->'presentation'->'equipment'->'completion', replayed->'state') then
      raise exception 'PRACTICE_WORK_INCOMPLETE:%', phase->>'id' using errcode = '22023';
    end if;
  end loop;
  last_id := (replayed->>'evidence_through_id')::bigint;
  if last_id is null then raise exception 'PRACTICE_EVIDENCE_REQUIRED'; end if;
  insert into public.practice_mission_completions(learner_id, mission_id, contract_version, evidence_through_id)
    values (p_learner, p_mission, contract.version, last_id)
    on conflict (learner_id, mission_id) do update set contract_version = excluded.contract_version,
      evidence_through_id = excluded.evidence_through_id, verified_at = now();
  perform private.practice_record_run(p_learner, p_mission, contract, replayed, 'verified', null);
end
$$;

create function public.practice_record_failed_verification(p_learner uuid, p_mission text, p_failure text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  contract public.practice_mission_contracts;
  replayed jsonb;
begin
  if p_failure is null or p_failure !~ '^[A-Za-z0-9_.:-]{1,120}$' then
    raise exception 'PRACTICE_FAILURE_CODE_INVALID' using errcode = '22023';
  end if;
  if not exists(select 1 from public.profiles where user_id = p_learner and role = 'learner' and status = 'active') then
    raise exception 'ACTIVE_LEARNER_REQUIRED' using errcode = '42501';
  end if;
  select * into contract from public.practice_mission_contracts where mission_id = p_mission;
  if not found then
    raise exception 'PRACTICE_MISSION_UNKNOWN' using errcode = '22023';
  end if;
  replayed := private.practice_run_replay(p_learner, p_mission, contract.definition);
  if replayed->>'evidence_through_id' is null then
    return;
  end if;
  perform private.practice_record_run(p_learner, p_mission, contract, replayed, 'incomplete', p_failure);
end
$$;

-- Which verified completion versions count for the COC practice quiz gate.
-- Pure: callers pass the mission's current contract version.
create function public.practice_completion_version_accepted(p_mission text, p_completion_version text, p_current_version text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(p_completion_version = p_current_version
    or (p_mission = 'coc1_m1' and p_current_version = 'css-sag-20261109-v3'
        and p_completion_version in ('css-sag-20261009-v1', 'css-sag-20261011-v2'))
    or (p_mission = 'coc1_m2' and p_current_version = 'css-assembly-20261119-v3'
        and p_completion_version in ('css-sag-20261009-v1', 'css-sag-20261011-v2')), false)
$$;

create or replace function public.practice_begin_quiz(p_learner uuid,p_coc text,p_id uuid,p_questions jsonb)
returns public.practice_quiz_attempts language plpgsql security invoker set search_path='' as $$
declare attempt public.practice_quiz_attempts;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_learner::text||p_coc,0));
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active')
    or not public.practice_coc_unlocked(p_coc,p_learner) then raise exception 'PRACTICE_COC_LOCKED' using errcode='42501'; end if;
  if (select count(*) from public.practice_mission_completions c join public.practice_mission_contracts d using(mission_id)
      where c.learner_id=p_learner and left(c.mission_id,4)=p_coc
        and public.practice_completion_version_accepted(c.mission_id, c.contract_version, d.version))<>5 then
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
      where c.learner_id=p_learner and left(c.mission_id,4)=attempt.coc_code
        and public.practice_completion_version_accepted(c.mission_id, c.contract_version, d.version))<>5 then
      raise exception 'PRACTICAL_COMPLETION_REQUIRED'; end if;
    insert into public.practice_coc_progress(learner_id,coc_code,quiz_attempt_id) values(p_learner,attempt.coc_code,p_attempt) on conflict do nothing;
  end if;
  return attempt;
end $$;

revoke all on function private.simulation_replay(jsonb, jsonb),
  private.practice_run_replay(uuid, text, jsonb),
  private.practice_record_run(uuid, text, public.practice_mission_contracts, jsonb, text, text),
  public.practice_verify_mission(uuid, text),
  public.practice_record_failed_verification(uuid, text, text),
  public.practice_begin_quiz(uuid, text, uuid, jsonb),
  public.practice_submit_quiz(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function private.simulation_replay(jsonb, jsonb),
  private.practice_run_replay(uuid, text, jsonb),
  private.practice_record_run(uuid, text, public.practice_mission_contracts, jsonb, text, text),
  public.practice_verify_mission(uuid, text),
  public.practice_record_failed_verification(uuid, text, text),
  public.practice_begin_quiz(uuid, text, uuid, jsonb),
  public.practice_submit_quiz(uuid, uuid, jsonb)
  to service_role;
revoke all on function public.practice_completion_version_accepted(text, text, text) from public, anon;
grant execute on function public.practice_completion_version_accepted(text, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
