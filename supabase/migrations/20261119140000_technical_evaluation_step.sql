-- Objective 4 (Evaluate -> Finalize -> Release) for technical assessments.
--
-- The automated evaluator leaves an attempt in `evaluated`. An owning
-- instructor now records an explicit evaluation (optionally overriding
-- criteria or the outcome, with a reason), which moves the attempt to
-- `under_review`. Only then can `finalize_attempt` (reviewed SECURITY DEFINER,
-- spec Section 9) finalize it; `release_attempt` still requires `finalized`.
--
-- Additive: no attempt, revision, release or audit row is rewritten. Existing
-- `evaluated` attempts simply wait in the Evaluate queue; finalized and
-- released history is untouched. No new SECURITY DEFINER function.
begin;
set local lock_timeout = '5s';

-- Evidence of the Evaluate step (who, when, what changed and why). Learners
-- never read it: their visibility starts with the released final revision.
create table public.attempt_evaluation_records (
  attempt_id uuid primary key references public.attempts(id) on delete restrict,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default clock_timestamp(),
  outcome public.evaluation_outcome not null,
  criterion_overrides jsonb not null default '[]'::jsonb
    check (jsonb_typeof(criterion_overrides) = 'array'),
  adjustment_revision_id uuid references public.score_revisions(id) on delete restrict,
  note text check (note is null or length(note) <= 2000)
);
create index attempt_evaluation_records_recorder_idx
  on public.attempt_evaluation_records(recorded_by, recorded_at desc);
create index attempt_evaluation_records_revision_idx
  on public.attempt_evaluation_records(adjustment_revision_id);
create trigger attempt_evaluation_records_append_only
before update or delete on public.attempt_evaluation_records
for each row execute function private.prevent_append_only_mutation();

alter table public.attempt_evaluation_records enable row level security;
revoke all on public.attempt_evaluation_records from public, anon, authenticated;
grant select on public.attempt_evaluation_records to authenticated;
grant all on public.attempt_evaluation_records to service_role;
create policy attempt_evaluation_records_staff_read
on public.attempt_evaluation_records for select to authenticated using (
  public.is_admin() or (
    public.is_instructor() and exists (
      select 1
      from public.attempts a
      join public.classes c on c.id = a.class_id
      where a.id = attempt_evaluation_records.attempt_id
        and c.instructor_id = (select auth.uid())
    )
  )
);

-- Service-only SECURITY INVOKER: the authenticated /api/evaluations route
-- calls it with the service client after identifying the caller; the actor's
-- role and class ownership are re-checked here from profiles/classes.
--
-- p_criterion_overrides: {} | null (confirm unchanged)
--   | {"criteria":[{"criterion_id":uuid,"observation":"satisfied"|"not_satisfied"}],
--      "outcome":"competent"|"not_yet_competent"}
--   | a bare criteria array.
-- Criterion overrides are rescored with the approved binary rubric rule; the
-- aggregate and criterion consistency checks of validate_instructor_score_revision
-- (the same rules finalize_attempt relies on) still apply to the new revision.
create function public.record_attempt_evaluation(
  p_actor uuid,
  p_attempt_id uuid,
  p_criterion_overrides jsonb,
  p_reason text,
  p_note text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_role public.user_role;
  v_attempt public.attempts;
  v_provisional public.score_revisions;
  v_current public.score_revisions;
  v_adjustment public.score_revisions;
  v_result public.score_revisions;
  v_record public.attempt_evaluation_records;
  v_rubric public.rubric_versions;
  v_overrides jsonb;
  v_criteria jsonb;
  v_outcome_text text;
  v_outcome public.evaluation_outcome;
  v_values jsonb;
  v_total numeric;
  v_max numeric;
  v_percentage numeric;
  v_changed boolean;
  v_reason text := nullif(btrim(p_reason), '');
  v_note text := nullif(btrim(p_note), '');
begin
  select p.role into v_role
  from public.profiles p
  where p.user_id = p_actor and p.status = 'active'::public.account_status;
  if v_role is distinct from 'instructor'::public.user_role then
    raise exception 'INSTRUCTOR_REQUIRED' using errcode = '42501';
  end if;

  select a.* into v_attempt from public.attempts a where a.id = p_attempt_id for update;
  if not found or not exists (
    select 1 from public.classes c
    where c.id = v_attempt.class_id
      and c.instructor_id = p_actor
      and c.status = 'active'::public.class_status
  ) then
    raise exception 'CLASS_SCOPE_DENIED' using errcode = '42501';
  end if;

  if v_reason is not null and length(v_reason) > 1000 then
    raise exception 'ADJUSTMENT_REASON_TOO_LONG' using errcode = '22023';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'EVALUATION_NOTE_TOO_LONG' using errcode = '22023';
  end if;

  v_overrides := coalesce(p_criterion_overrides, '{}'::jsonb);
  if jsonb_typeof(v_overrides) = 'array' then
    v_overrides := jsonb_build_object('criteria', v_overrides);
  end if;
  if jsonb_typeof(v_overrides) <> 'object'
     or exists (select 1 from jsonb_object_keys(v_overrides) k where k not in ('criteria', 'outcome')) then
    raise exception 'INVALID_CRITERION_OVERRIDE' using errcode = '22023';
  end if;
  v_criteria := coalesce(v_overrides->'criteria', '[]'::jsonb);
  if jsonb_typeof(v_criteria) <> 'array'
     or jsonb_array_length(v_criteria) > 200
     or exists (
       select 1 from jsonb_array_elements(v_criteria) e
       where jsonb_typeof(e) <> 'object'
          or coalesce(e->>'observation', '') not in ('satisfied', 'not_satisfied')
          or coalesce(e->>'criterion_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     )
     or (select count(*) <> count(distinct lower(e->>'criterion_id')) from jsonb_array_elements(v_criteria) e) then
    raise exception 'INVALID_CRITERION_OVERRIDE' using errcode = '22023';
  end if;
  v_outcome_text := v_overrides->>'outcome';
  if v_outcome_text is not null and v_outcome_text not in ('competent', 'not_yet_competent')
     or (v_overrides ? 'outcome' and jsonb_typeof(v_overrides->'outcome') not in ('string', 'null')) then
    raise exception 'INVALID_EVALUATION_OUTCOME' using errcode = '22023';
  end if;

  if v_attempt.status not in ('evaluated'::public.attempt_status, 'under_review'::public.attempt_status) then
    raise exception 'EVALUATED_ATTEMPT_REQUIRED' using errcode = '55000';
  end if;

  -- The Evaluate step always starts from the trusted automated result.
  select sr.* into v_provisional
  from public.score_revisions sr
  where sr.attempt_id = v_attempt.id
    and sr.revision_type = 'automated_provisional'::public.score_revision_type
  order by sr.revision_number desc
  limit 1;
  select sr.* into v_current
  from public.score_revisions sr
  where sr.attempt_id = v_attempt.id
  order by sr.revision_number desc
  limit 1;
  if v_provisional.id is null
     or (v_attempt.status = 'evaluated'::public.attempt_status and v_current.id <> v_provisional.id) then
    raise exception 'PROVISIONAL_REVISION_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(v_provisional.criterion_values) <> 'array' then
    raise exception 'CRITERION_VALUES_MUST_BE_ARRAY' using errcode = '22023';
  end if;

  v_values := v_provisional.criterion_values;
  v_total := v_provisional.total_value;
  v_max := v_provisional.max_value;
  v_percentage := v_provisional.percentage;
  if jsonb_array_length(v_criteria) > 0 then
    select rv.* into v_rubric from public.rubric_versions rv where rv.id = v_provisional.rubric_version_id;
    if v_rubric.scoring_method is distinct from 'binary_sum' then
      raise exception 'CRITERION_OVERRIDE_UNSUPPORTED' using errcode = '22023';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_criteria) e
      where not exists (
          select 1 from jsonb_array_elements(v_provisional.criterion_values) cv
          where lower(cv->>'criterion_id') = lower(e->>'criterion_id'))
        or not exists (
          select 1 from public.rubric_criteria rc
          where rc.id = (e->>'criterion_id')::uuid
            and rc.rubric_version_id = v_rubric.id
            and rc.max_value > 0
            and rc.scoring_rule->>'status' = 'APPROVED'
            and rc.scoring_rule->>'method' = 'binary'
            and jsonb_typeof(rc.scoring_rule->'satisfied_value') = 'number'
            and jsonb_typeof(rc.scoring_rule->'not_satisfied_value') = 'number')
    ) then
      raise exception 'INVALID_CRITERION_OVERRIDE' using errcode = '22023';
    end if;

    select jsonb_agg(
      case when o.observation is null then x.cv
        else x.cv || jsonb_build_object(
          'observation', o.observation,
          'score_value', case when o.observation = 'satisfied'
            then (rc.scoring_rule->>'satisfied_value')::numeric
            else (rc.scoring_rule->>'not_satisfied_value')::numeric end)
      end order by x.ord)
    into v_values
    from jsonb_array_elements(v_provisional.criterion_values) with ordinality as x(cv, ord)
    left join (
      select lower(e->>'criterion_id') as criterion_id, e->>'observation' as observation
      from jsonb_array_elements(v_criteria) e
    ) o on o.criterion_id = lower(x.cv->>'criterion_id')
    left join public.rubric_criteria rc
      on rc.id::text = lower(x.cv->>'criterion_id') and rc.rubric_version_id = v_rubric.id;

    select coalesce(sum((cv->>'score_value')::numeric), 0) into v_total
    from jsonb_array_elements(v_values) cv;
    select coalesce(sum(rc.max_value), 0) into v_max
    from public.rubric_criteria rc where rc.rubric_version_id = v_rubric.id;
    if v_max <= 0 then
      raise exception 'INVALID_MAX_VALUE' using errcode = '22023';
    end if;
    v_percentage := round((v_total / v_max) * 100, 4);
  end if;
  v_outcome := coalesce(v_outcome_text::public.evaluation_outcome, v_provisional.outcome);

  v_changed :=
    v_values is distinct from v_provisional.criterion_values
    or v_total is distinct from v_provisional.total_value
    or v_max is distinct from v_provisional.max_value
    or v_percentage is distinct from v_provisional.percentage
    or v_outcome is distinct from v_provisional.outcome;

  if v_attempt.status = 'under_review'::public.attempt_status then
    -- Idempotent replay of the same decision; anything else is corrected at
    -- finalization (which keeps its own reasoned-adjustment rule).
    if v_current.criterion_values = v_values
       and v_current.total_value is not distinct from v_total
       and v_current.max_value is not distinct from v_max
       and v_current.percentage is not distinct from v_percentage
       and v_current.outcome = v_outcome then
      select r.* into v_record from public.attempt_evaluation_records r where r.attempt_id = v_attempt.id;
      return jsonb_build_object(
        'attempt_id', v_attempt.id,
        'status', v_attempt.status,
        'changed', v_record.adjustment_revision_id is not null,
        'replayed', true,
        'recorded_at', v_record.recorded_at,
        'revision', to_jsonb(v_current));
    end if;
    raise exception 'EVALUATION_ALREADY_RECORDED' using errcode = '55000';
  end if;

  if v_changed and v_reason is null then
    raise exception 'ADJUSTMENT_REASON_REQUIRED' using errcode = '22023';
  end if;

  v_result := v_provisional;
  if v_changed then
    insert into public.score_revisions (
      attempt_id, revision_number, revision_type, supersedes_revision_id,
      actor_id, actor_role, tesda_source_id, rubric_version_id, evaluation_run_id,
      total_value, max_value, percentage, outcome, criterion_values, reason, remarks
    )
    values (
      v_attempt.id, v_provisional.revision_number + 1,
      'instructor_adjustment'::public.score_revision_type, v_provisional.id,
      p_actor, 'instructor'::public.user_role, v_provisional.tesda_source_id,
      v_provisional.rubric_version_id, v_provisional.evaluation_run_id,
      v_total, v_max, v_percentage, v_outcome, v_values, v_reason, v_note
    )
    returning * into v_adjustment;

    insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value, reason, metadata)
    values (p_actor, 'instructor'::public.user_role, 'score.adjusted', 'attempt', v_attempt.id,
      to_jsonb(v_provisional), to_jsonb(v_adjustment), v_reason, jsonb_build_object('stage', 'evaluate'));
    v_result := v_adjustment;
  end if;

  update public.attempts set status = 'under_review'::public.attempt_status where id = v_attempt.id;

  insert into public.attempt_evaluation_records(attempt_id, recorded_by, outcome, criterion_overrides, adjustment_revision_id, note)
  values (v_attempt.id, p_actor, v_outcome, v_criteria, v_adjustment.id, v_note)
  returning * into v_record;

  insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value, reason, metadata)
  values (p_actor, 'instructor'::public.user_role, 'attempt.evaluation_recorded', 'attempt', v_attempt.id,
    jsonb_build_object('status', 'evaluated', 'score_revision_id', v_provisional.id),
    jsonb_build_object('status', 'under_review', 'score_revision_id', v_result.id, 'outcome', v_outcome, 'changed', v_changed),
    v_reason,
    jsonb_build_object('class_id', v_attempt.class_id, 'learner_id', v_attempt.learner_id,
      'adjustment_revision_id', v_adjustment.id, 'note', v_note));

  return jsonb_build_object(
    'attempt_id', v_attempt.id,
    'status', 'under_review',
    'changed', v_changed,
    'replayed', false,
    'recorded_at', v_record.recorded_at,
    'revision', to_jsonb(v_result));
end
$$;

revoke all on function public.record_attempt_evaluation(uuid, uuid, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.record_attempt_evaluation(uuid, uuid, jsonb, text, text) to service_role;

-- Reviewed definer change (spec Section 9): finalization now requires the
-- recorded instructor evaluation (`under_review`). The latest revision may be
-- the automated result (confirmed unchanged) or the instructor adjustment;
-- every other rule (ownership, reasoned final adjustments, append-only
-- revisions, aggregate validation, audit) is unchanged.
create or replace function public.finalize_attempt(
  p_attempt_id uuid,
  p_total_value numeric,
  p_max_value numeric,
  p_percentage numeric,
  p_outcome public.evaluation_outcome,
  p_criterion_values jsonb,
  p_reason text default null,
  p_remarks text default null
)
returns public.score_revisions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt public.attempts;
  v_latest public.score_revisions;
  v_adjustment public.score_revisions;
  v_final public.score_revisions;
  v_next integer;
  v_changed boolean;
  v_values jsonb;
begin
  select a.* into v_attempt
  from public.attempts a
  where a.id = p_attempt_id
  for update;

  if not found or not public.instructor_owns_class(v_attempt.class_id) then
    raise exception 'CLASS_SCOPE_DENIED' using errcode = '42501';
  end if;

  if v_attempt.status <> 'under_review'::public.attempt_status then
    raise exception 'UNDER_REVIEW_ATTEMPT_REQUIRED' using errcode = '22023';
  end if;

  if p_outcome = 'pending_tesda_validation'::public.evaluation_outcome then
    raise exception 'FINAL_OUTCOME_REQUIRES_APPROVED_TESDA_RULE' using errcode = '22023';
  end if;

  if p_total_value is not null and p_total_value < 0 then
    raise exception 'INVALID_TOTAL_VALUE' using errcode = '22023';
  end if;

  if p_max_value is not null and p_max_value <= 0 then
    raise exception 'INVALID_MAX_VALUE' using errcode = '22023';
  end if;

  if p_percentage is not null and (p_percentage < 0 or p_percentage > 100) then
    raise exception 'INVALID_PERCENTAGE' using errcode = '22023';
  end if;

  select sr.* into v_latest
  from public.score_revisions sr
  where sr.attempt_id = p_attempt_id
  order by sr.revision_number desc
  limit 1;

  if not found or v_latest.revision_type not in (
    'automated_provisional'::public.score_revision_type,
    'instructor_adjustment'::public.score_revision_type
  ) then
    raise exception 'PROVISIONAL_REVISION_REQUIRED' using errcode = '22023';
  end if;

  v_values := coalesce(p_criterion_values, v_latest.criterion_values);
  if jsonb_typeof(v_values) <> 'array' then
    raise exception 'CRITERION_VALUES_MUST_BE_ARRAY' using errcode = '22023';
  end if;

  v_changed :=
    p_total_value is distinct from v_latest.total_value
    or p_max_value is distinct from v_latest.max_value
    or p_percentage is distinct from v_latest.percentage
    or p_outcome is distinct from v_latest.outcome
    or v_values is distinct from v_latest.criterion_values;

  if v_changed and nullif(btrim(p_reason), '') is null then
    raise exception 'ADJUSTMENT_REASON_REQUIRED' using errcode = '22023';
  end if;

  v_next := v_latest.revision_number + 1;

  if v_changed then
    insert into public.score_revisions (
      attempt_id,
      revision_number,
      revision_type,
      supersedes_revision_id,
      actor_id,
      actor_role,
      tesda_source_id,
      rubric_version_id,
      evaluation_run_id,
      total_value,
      max_value,
      percentage,
      outcome,
      criterion_values,
      reason,
      remarks
    )
    values (
      v_attempt.id,
      v_next,
      'instructor_adjustment'::public.score_revision_type,
      v_latest.id,
      (select auth.uid()),
      'instructor'::public.user_role,
      v_latest.tesda_source_id,
      v_latest.rubric_version_id,
      v_latest.evaluation_run_id,
      p_total_value,
      p_max_value,
      p_percentage,
      p_outcome,
      v_values,
      btrim(p_reason),
      nullif(btrim(p_remarks), '')
    )
    returning * into v_adjustment;

    perform private.write_audit_event(
      'score.adjusted',
      'attempt',
      v_attempt.id,
      to_jsonb(v_latest),
      to_jsonb(v_adjustment),
      p_reason
    );

    v_latest := v_adjustment;
    v_next := v_next + 1;
  end if;

  insert into public.score_revisions (
    attempt_id,
    revision_number,
    revision_type,
    supersedes_revision_id,
    actor_id,
    actor_role,
    tesda_source_id,
    rubric_version_id,
    evaluation_run_id,
    total_value,
    max_value,
    percentage,
    outcome,
    criterion_values,
    reason,
    remarks
  )
  values (
    v_attempt.id,
    v_next,
    'instructor_final'::public.score_revision_type,
    v_latest.id,
    (select auth.uid()),
    'instructor'::public.user_role,
    v_latest.tesda_source_id,
    v_latest.rubric_version_id,
    v_latest.evaluation_run_id,
    p_total_value,
    p_max_value,
    p_percentage,
    p_outcome,
    v_values,
    nullif(btrim(p_reason), ''),
    nullif(btrim(p_remarks), '')
  )
  returning * into v_final;

  update public.attempts
  set status = 'finalized'::public.attempt_status,
      finalized_at = now()
  where id = v_attempt.id;

  perform private.write_audit_event(
    'score.finalized',
    'attempt',
    v_attempt.id,
    to_jsonb(v_latest),
    to_jsonb(v_final),
    p_reason
  );

  return v_final;
end
$$;

revoke all on function public.finalize_attempt(uuid, numeric, numeric, numeric, public.evaluation_outcome, jsonb, text, text) from public, anon;
grant execute on function public.finalize_attempt(uuid, numeric, numeric, numeric, public.evaluation_outcome, jsonb, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
