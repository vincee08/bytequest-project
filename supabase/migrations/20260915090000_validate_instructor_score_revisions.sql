-- Preserve instructor outcome authority while rejecting internally inconsistent
-- criterion values and aggregates before an append-only score revision is saved.
-- This is a SECURITY INVOKER trigger, not a new elevated RPC.
create or replace function private.validate_instructor_score_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_scoring_method text;
  v_expected_count integer;
  v_received_count integer;
  v_distinct_count integer;
  v_valid_count integer;
  v_rubric_max numeric;
  v_criterion_total numeric;
begin
  if new.revision_type not in (
    'instructor_adjustment'::public.score_revision_type,
    'instructor_final'::public.score_revision_type
  ) then
    return new;
  end if;

  if new.total_value is null or new.max_value is null or new.percentage is null
     or new.max_value <= 0 or new.total_value < 0 or new.total_value > new.max_value
     or new.percentage <> round((new.total_value / new.max_value) * 100, 4) then
    raise exception 'INCONSISTENT_SCORE_AGGREGATE' using errcode = '22023';
  end if;

  select rv.scoring_method into v_scoring_method
  from public.rubric_versions rv
  where rv.id = new.rubric_version_id;

  if v_scoring_method is null then
    raise exception 'FINAL_REVISION_RUBRIC_REQUIRED' using errcode = '22023';
  end if;
  if v_scoring_method <> 'binary_sum' then
    return new;
  end if;

  if jsonb_typeof(new.criterion_values) <> 'array' then
    raise exception 'FINAL_CRITERION_VALUES_REQUIRED' using errcode = '22023';
  end if;

  select count(*), coalesce(sum(rc.max_value), 0)
  into v_expected_count, v_rubric_max
  from public.rubric_criteria rc
  where rc.rubric_version_id = new.rubric_version_id;

  select count(*), count(distinct input.criterion_id),
         count(*) filter (where
           rc.id is not null
           and rc.max_value > 0
           and rc.scoring_rule->>'status' = 'APPROVED'
           and rc.scoring_rule->>'method' = 'binary'
           and input.observation in ('satisfied', 'not_satisfied', 'not_evaluated', 'requires_review')
           and input.score_value = case
             when input.observation = 'satisfied' then (rc.scoring_rule->>'satisfied_value')::numeric
             else (rc.scoring_rule->>'not_satisfied_value')::numeric
           end
         ),
         coalesce(sum(input.score_value), 0)
  into v_received_count, v_distinct_count, v_valid_count, v_criterion_total
  from jsonb_to_recordset(new.criterion_values) as input(
    criterion_id uuid,
    observation text,
    score_value numeric
  )
  left join public.rubric_criteria rc
    on rc.id = input.criterion_id
   and rc.rubric_version_id = new.rubric_version_id;

  if v_expected_count = 0 or v_received_count <> v_expected_count
     or v_distinct_count <> v_expected_count or v_valid_count <> v_expected_count
     or v_rubric_max <> new.max_value or v_criterion_total <> new.total_value then
    raise exception 'INCONSISTENT_CRITERION_SCORE' using errcode = '22023';
  end if;

  return new;
end
$$;

drop trigger if exists validate_instructor_score_revision on public.score_revisions;
create trigger validate_instructor_score_revision
before insert on public.score_revisions
for each row execute function private.validate_instructor_score_revision();

revoke all on function private.validate_instructor_score_revision() from public, anon, authenticated;
