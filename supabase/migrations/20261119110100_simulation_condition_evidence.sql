-- Re-defense slice A1.2: the simulation_condition evidence operator.
--
-- Simulation-based assessments evaluate each rubric criterion by replaying the
-- attempt's ordered evidence against the contract snapshot stored in the
-- activity version (evaluator_config.simulation_definition):
--   {"operator":"simulation_condition","phase_ids":[...],"conditions":[...],
--    "counted_targets":["item:cpu",...],"max_incorrect":2}
-- The criterion is satisfied when every listed phase is done, every condition
-- holds on the final state, and the invalid actions plus corrections on the
-- counted targets do not exceed max_incorrect (owner decision 7: two, zero for
-- safety-critical steps).
--
-- Both functions are listed in spec Section 9. Their bodies are the latest
-- published ones (valid_evidence_rule: 20260810110000; evaluate_criterion_
-- evidence: 20260810112000) with the new branch added; every existing operator
-- is unchanged. Owners, SECURITY attributes and grants are preserved.

begin;

create or replace function private.valid_evidence_rule(p_rule jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_operator text := p_rule->>'operator';
  v_minimum integer;
begin
  if jsonb_typeof(p_rule) <> 'object' then
    return false;
  end if;

  if v_operator = 'action_exists' then
    if nullif(btrim(p_rule->>'action_type'), '') is null
       or jsonb_typeof(p_rule->'minimum_count') <> 'number'
       or (p_rule ? 'value_contains' and jsonb_typeof(p_rule->'value_contains') <> 'object') then
      return false;
    end if;
    begin
      v_minimum := (p_rule->>'minimum_count')::integer;
    exception when others then
      return false;
    end;
    return v_minimum > 0;
  end if;

  if v_operator = 'exact_target_sequence' then
    return nullif(btrim(p_rule->>'action_type'), '') is not null
      and jsonb_typeof(p_rule->'expected_targets') = 'array'
      and jsonb_array_length(p_rule->'expected_targets') > 0
      and not exists (
        select 1
        from jsonb_array_elements(p_rule->'expected_targets') item
        where jsonb_typeof(item) <> 'string'
      );
  end if;

  if v_operator = 'final_action_value_equals' then
    return nullif(btrim(p_rule->>'action_type'), '') is not null
      and nullif(btrim(p_rule->>'value_key'), '') is not null
      and p_rule ? 'expected';
  end if;

  if v_operator = 'final_action_value_set_equals' then
    return nullif(btrim(p_rule->>'action_type'), '') is not null
      and nullif(btrim(p_rule->>'value_key'), '') is not null
      and jsonb_typeof(p_rule->'expected') = 'array'
      and jsonb_array_length(p_rule->'expected') > 0
      and not exists (
        select 1
        from jsonb_array_elements(p_rule->'expected') item
        where jsonb_typeof(item) <> 'string'
      );
  end if;

  if v_operator = 'simulation_condition' then
    if jsonb_typeof(p_rule->'phase_ids') is distinct from 'array'
       or jsonb_typeof(coalesce(p_rule->'conditions', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_rule->'counted_targets', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(p_rule->'max_incorrect') is distinct from 'number'
       or (p_rule->>'max_incorrect') !~ '^[0-9]{1,3}$' then
      return false;
    end if;
    if jsonb_array_length(p_rule->'phase_ids') = 0
       or exists (
         select 1
         from jsonb_array_elements(p_rule->'phase_ids') item
         where jsonb_typeof(item) <> 'string' or btrim(item #>> '{}') = ''
       )
       or exists (
         select 1
         from jsonb_array_elements(coalesce(p_rule->'conditions', '[]'::jsonb)) item
         where jsonb_typeof(item) <> 'object'
           or nullif(btrim(item->>'path'), '') is null
           or coalesce(item->>'operator', 'equals') not in
             ('equals', 'present', 'contains', 'set_equals', 'one_of', 'not_equals', 'minimum')
       )
       or exists (
         select 1
         from jsonb_array_elements(coalesce(p_rule->'counted_targets', '[]'::jsonb)) item
         where jsonb_typeof(item) <> 'string' or btrim(item #>> '{}') = ''
       ) then
      return false;
    end if;
    return true;
  end if;

  return false;
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
                 'corrections', coalesce((v_replay->'corrections'->>t.target)::integer, 0)
               )
             ),
             '{}'::jsonb
           ),
           coalesce(sum(
             coalesce((v_replay->'invalid'->>t.target)::integer, 0)
             + coalesce((v_replay->'corrections'->>t.target)::integer, 0)
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

revoke all on function private.valid_evidence_rule(jsonb) from public, anon, authenticated;
revoke all on function private.evaluate_criterion_evidence(uuid, jsonb) from public, anon, authenticated;

commit;
