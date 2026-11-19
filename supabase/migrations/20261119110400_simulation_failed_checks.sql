-- Re-defense slice A1, fix round 1 (review findings I2 and C1; spec WS2 and owner
-- decision 7): physically possible mistakes that a power-on test exposes count
-- toward their step even when they are fixed afterwards.
--
-- * private.simulation_replay: every completed test with failing checks adds
--   one incorrect attempt per failing check to the target the check names in
--   "counts" (for COC1 M2: lever/CPU, latches/memory, screws, cooler/CPU_FAN,
--   power cables, data/front-panel). The replay returns failed_checks (per
--   target), phase_failed_checks and failed_check_count. Checks without
--   "counts" (every other contract) count nothing, so their replay and
--   verification are unchanged.
-- * Review finding C1 (assessment runs through the real controls): every move
--   of a sequencing list records the order in progress, so a learner who
--   reaches the right order step by step produced several wrong orders. Only
--   a confirmed order ({"confirmed": true}, sent by the Confirm order button)
--   is the learner's answer: an unconfirmed wrong order is no longer counted
--   as an incorrect attempt. Its effect on state and done is unchanged.
-- * private.evaluate_criterion_evidence (spec Section 9): simulation_condition
--   sums invalid actions, corrections and failed checks over the counted
--   targets; observed_evidence reports all three per target. Every other
--   operator is byte-for-byte the body of 20261119110100.
-- * private.practice_record_run: step_results also report the failed checks of
--   each test phase, the same counts the learner sees on the bench.
--
-- Bodies otherwise identical to 20261119110000 and 20261119110100. No new
-- function; SECURITY attributes, owners and grants are preserved.

begin;

create or replace function private.simulation_replay(p_definition jsonb, p_actions jsonb)
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
  failed_checks jsonb := '{}'::jsonb;
  phase_failed_checks jsonb := '{}'::jsonb;
  failed_check_count integer := 0;
  action_failed text[] := '{}';
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
    action_failed := '{}';
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
          -- Each failing check that names the step target it charges ("counts")
          -- adds one incorrect attempt to that target, every completed test.
          select coalesce(array_agg(c->>'counts'), '{}') into action_failed
            from jsonb_array_elements(coalesce(eq->'checks', '[]'::jsonb)) c
            where jsonb_typeof(c->'counts') = 'string'
              and not public.practice_conditions_met(c->'requires', state);
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
      action_failed := '{}';
    end;

    -- A reorder in progress is not an answer: only a confirmed wrong order
    -- counts as an incorrect attempt. Its state and done rules are unchanged.
    if not coalesce(valid, false)
       and not (kind = 'sequence_reordered' and coalesce(v->>'confirmed', 'false') <> 'true') then
      target_key := coalesce(target_key, 'phase:'||a_phase);
      invalid := invalid || jsonb_build_object(target_key, coalesce((invalid->>target_key)::integer, 0) + 1);
      phase_invalid := phase_invalid || jsonb_build_object(a_phase, coalesce((phase_invalid->>a_phase)::integer, 0) + 1);
      invalid_count := invalid_count + 1;
    elsif correction_key is not null then
      corrections := corrections || jsonb_build_object(correction_key, coalesce((corrections->>correction_key)::integer, 0) + 1);
      correction_count := correction_count + 1;
    end if;
    if coalesce(valid, false) and cardinality(action_failed) > 0 then
      foreach key in array action_failed loop
        failed_checks := failed_checks || jsonb_build_object(key, coalesce((failed_checks->>key)::integer, 0) + 1);
        failed_check_count := failed_check_count + 1;
      end loop;
      phase_failed_checks := phase_failed_checks || jsonb_build_object(a_phase,
        coalesce((phase_failed_checks->>a_phase)::integer, 0) + cardinality(action_failed));
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
    'failed_checks', failed_checks,
    'phase_failed_checks', phase_failed_checks,
    'failed_check_count', failed_check_count,
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
    'failed_checks', '{}'::jsonb,
    'phase_failed_checks', '{}'::jsonb,
    'failed_check_count', 0,
    'first_at', null,
    'last_at', null,
    'error', sqlstate);
end
$$;

create or replace function private.practice_record_run(p_learner uuid, p_mission text, p_contract public.practice_mission_contracts,
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
      'invalid', coalesce((p_replay->'phase_invalid'->>(phase->>'id'))::integer, 0),
      'failed_checks', coalesce((p_replay->'phase_failed_checks'->>(phase->>'id'))::integer, 0)));
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

create or replace function private.evaluate_criterion_evidence(
  p_attempt_id uuid,
  p_rule jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_operator text := p_rule->>'operator';
  v_count integer;
  v_actions jsonb;
  v_observed jsonb;
  v_expected_set jsonb;
  v_observed_set jsonb;
  v_definition jsonb;
  v_replay jsonb;
  v_phases_done jsonb;
  v_conditions_met boolean;
  v_incorrect jsonb;
begin
  if not private.valid_evidence_rule(p_rule) then
    raise exception 'UNSUPPORTED_EVIDENCE_RULE' using errcode = '22023';
  end if;

  if v_operator = 'simulation_condition' then
    select av.evaluator_config->'simulation_definition'
    into v_definition
    from public.attempts at
    join public.assignments asg on asg.id = at.assignment_id
    join public.activity_versions av on av.id = asg.activity_version_id
    where at.id = p_attempt_id
      and av.id = at.activity_version_id;

    if v_definition is null or jsonb_typeof(v_definition) <> 'object' then
      return jsonb_build_object(
        'observation', 'not_satisfied',
        'observed_evidence', jsonb_build_object(
          'reason', 'SIMULATION_DEFINITION_MISSING',
          'phases_required', p_rule->'phase_ids'
        )
      );
    end if;

    -- Ordered attempt evidence; the app stores the phase in value.phase_id
    -- and the rendered action in value.runtime_action_type.
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'action_type', aa.action_type,
                 'target', aa.target,
                 'phase_id', aa.value->>'phase_id',
                 'value', aa.value,
                 'occurred_at', aa.client_occurred_at
               ) order by aa.sequence_number
             ),
             '[]'::jsonb
           )
    into v_actions
    from public.attempt_actions aa
    where aa.attempt_id = p_attempt_id;

    v_replay := private.simulation_replay(v_definition, v_actions);

    select coalesce(jsonb_agg(to_jsonb(x.phase_id) order by x.n), '[]'::jsonb)
    into v_phases_done
    from jsonb_array_elements_text(p_rule->'phase_ids') with ordinality as x(phase_id, n)
    where coalesce(v_replay->'done'->>x.phase_id, 'false') = 'true';

    v_conditions_met := coalesce(
      public.practice_conditions_met(coalesce(p_rule->'conditions', '[]'::jsonb), v_replay->'state'),
      false
    );

    select coalesce(
             jsonb_object_agg(
               t.target,
               jsonb_build_object(
                 'invalid', coalesce((v_replay->'invalid'->>t.target)::integer, 0),
                 'corrections', coalesce((v_replay->'corrections'->>t.target)::integer, 0),
                 'failed_checks', coalesce((v_replay->'failed_checks'->>t.target)::integer, 0)
               )
             ),
             '{}'::jsonb
           ),
           coalesce(sum(
             coalesce((v_replay->'invalid'->>t.target)::integer, 0)
             + coalesce((v_replay->'corrections'->>t.target)::integer, 0)
             + coalesce((v_replay->'failed_checks'->>t.target)::integer, 0)
           ), 0)::integer
    into v_incorrect, v_count
    from (
      select distinct item.value as target
      from jsonb_array_elements_text(coalesce(p_rule->'counted_targets', '[]'::jsonb)) item
    ) t;

    return jsonb_build_object(
      'observation', case
        when v_replay->>'error' is null
          and jsonb_array_length(v_phases_done) = jsonb_array_length(p_rule->'phase_ids')
          and v_conditions_met
          and v_count <= (p_rule->>'max_incorrect')::integer
          then 'satisfied'
        else 'not_satisfied'
      end,
      'observed_evidence', jsonb_build_object(
        'phases_required', p_rule->'phase_ids',
        'phases_done', v_phases_done,
        'conditions_met', v_conditions_met,
        'incorrect_by_target', v_incorrect,
        'incorrect_total', v_count,
        'max_incorrect', (p_rule->>'max_incorrect')::integer,
        'action_count', coalesce((v_replay->>'action_count')::integer, 0)
      )
    );
  end if;

  if v_operator = 'action_exists' then
    select count(*)::integer,
           coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'sequence_number', aa.sequence_number,
                 'action_type', aa.action_type,
                 'target', aa.target,
                 'value', aa.value,
                 'client_occurred_at', aa.client_occurred_at
               ) order by aa.sequence_number
             ),
             '[]'::jsonb
           )
    into v_count, v_actions
    from public.attempt_actions aa
    where aa.attempt_id = p_attempt_id
      and aa.action_type = (p_rule->>'action_type')
      and (not (p_rule ? 'target') or aa.target = (p_rule->>'target'))
      and (not (p_rule ? 'value_contains') or aa.value @> (p_rule->'value_contains'));

    return jsonb_build_object(
      'observation', case
        when v_count >= (p_rule->>'minimum_count')::integer then 'satisfied'
        else 'not_satisfied'
      end,
      'observed_evidence', jsonb_build_object(
        'matching_count', v_count,
        'required_count', (p_rule->>'minimum_count')::integer,
        'matching_actions', v_actions
      )
    );
  end if;

  if v_operator = 'exact_target_sequence' then
    select coalesce(jsonb_agg(to_jsonb(aa.target) order by aa.sequence_number), '[]'::jsonb)
    into v_observed
    from public.attempt_actions aa
    where aa.attempt_id = p_attempt_id
      and aa.action_type = (p_rule->>'action_type');

    return jsonb_build_object(
      'observation', case
        when v_observed = (p_rule->'expected_targets') then 'satisfied'
        else 'not_satisfied'
      end,
      'observed_evidence', jsonb_build_object(
        'observed_targets', v_observed,
        'expected_targets', p_rule->'expected_targets'
      )
    );
  end if;

  select aa.value->(p_rule->>'value_key')
  into v_observed
  from public.attempt_actions aa
  where aa.attempt_id = p_attempt_id
    and aa.action_type = (p_rule->>'action_type')
  order by aa.sequence_number desc
  limit 1;

  v_count := case when found then 1 else 0 end;

  if v_operator = 'final_action_value_set_equals' then
    select coalesce(jsonb_agg(to_jsonb(item.value) order by item.value), '[]'::jsonb)
    into v_expected_set
    from (
      select distinct jsonb_array_elements_text(p_rule->'expected') as value
    ) item;

    if v_count = 1 and jsonb_typeof(v_observed) = 'array' then
      select coalesce(jsonb_agg(to_jsonb(item.value) order by item.value), '[]'::jsonb)
      into v_observed_set
      from (
        select distinct jsonb_array_elements_text(v_observed) as value
      ) item;
    else
      v_observed_set := '[]'::jsonb;
    end if;

    return jsonb_build_object(
      'observation', case
        when v_count = 1 and v_observed_set = v_expected_set then 'satisfied'
        else 'not_satisfied'
      end,
      'observed_evidence', jsonb_build_object(
        'observed_values', coalesce(v_observed, 'null'::jsonb),
        'expected_values', p_rule->'expected',
        'normalized_observed_values', v_observed_set,
        'normalized_expected_values', v_expected_set,
        'value_key', p_rule->>'value_key'
      )
    );
  end if;

  return jsonb_build_object(
    'observation', case
      when v_count = 1 and v_observed is not distinct from (p_rule->'expected') then 'satisfied'
      else 'not_satisfied'
    end,
    'observed_evidence', jsonb_build_object(
      'observed_value', v_observed,
      'expected_value', p_rule->'expected',
      'value_key', p_rule->>'value_key'
    )
  );
end
$$;

revoke all on function private.simulation_replay(jsonb, jsonb),
  private.practice_record_run(uuid, text, public.practice_mission_contracts, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function private.simulation_replay(jsonb, jsonb),
  private.practice_record_run(uuid, text, public.practice_mission_contracts, jsonb, text, text)
  to service_role;
revoke all on function private.evaluate_criterion_evidence(uuid, jsonb) from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
