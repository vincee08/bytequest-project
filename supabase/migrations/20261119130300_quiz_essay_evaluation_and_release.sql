-- Re-defense WS4/WS5 (slice A3.3): instructor scoring of scenario essays
-- against their rubric and the Evaluate -> Finalize -> Release workflow for
-- quizzes in instructor-release mode, plus the quiz items consumed by the
-- Evaluation Center (slice A4).
--
-- Essay scores are append-only (the latest row per attempt and item is the
-- current one); finalized totals are immutable and release is recorded once.
-- Learners see no total until release. No SECURITY DEFINER function is added:
-- manage_quiz_evaluation is a service-only invoker behind an authenticated
-- server route, and quiz_evaluation_queue_items is an RLS-scoped invoker.
begin;
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table public.quiz_essay_scores (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.quiz_attempts(id) on delete restrict,
  item_id uuid not null references public.quiz_items(id) on delete restrict,
  criterion_scores jsonb not null check (jsonb_typeof(criterion_scores) = 'object'),
  total numeric not null check (total >= 0),
  feedback text check (feedback is null or length(feedback) <= 5000),
  evaluated_by uuid not null references auth.users(id) on delete restrict,
  evaluated_at timestamptz not null default clock_timestamp()
);
create index quiz_essay_scores_attempt_item_idx on public.quiz_essay_scores(attempt_id, item_id, evaluated_at desc, id desc);
create trigger quiz_essay_scores_append_only
  before update or delete on public.quiz_essay_scores
  for each row execute function private.prevent_append_only_mutation();
comment on table public.quiz_essay_scores is
  'Instructor rubric scores for scenario essay answers. Append-only: the latest row per attempt and item is current; earlier rows are history.';

create table public.quiz_result_finalizations (
  attempt_id uuid primary key references public.quiz_attempts(id) on delete restrict,
  objective_points numeric not null check (objective_points >= 0),
  essay_points numeric not null check (essay_points >= 0),
  total_points numeric not null check (total_points >= 0),
  max_points numeric not null check (max_points > 0),
  percent numeric not null check (percent between 0 and 100),
  finalized_by uuid not null references auth.users(id) on delete restrict,
  finalized_at timestamptz not null default clock_timestamp(),
  released_by uuid references auth.users(id) on delete restrict,
  released_at timestamptz,
  constraint quiz_result_finalizations_total_check check (total_points = objective_points + essay_points and total_points <= max_points),
  constraint quiz_result_finalizations_release_check check ((released_by is null) = (released_at is null))
);
comment on table public.quiz_result_finalizations is
  'Final quiz totals recorded by the owning instructor (Finalize) and the time they were released to the learner (Release).';

create function private.protect_quiz_result_finalization()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'FINALIZED_QUIZ_RESULT_IS_IMMUTABLE' using errcode = '55000';
  end if;
  if (new.attempt_id, new.objective_points, new.essay_points, new.total_points, new.max_points, new.percent,
      new.finalized_by, new.finalized_at)
     is distinct from
     (old.attempt_id, old.objective_points, old.essay_points, old.total_points, old.max_points, old.percent,
      old.finalized_by, old.finalized_at) then
    raise exception 'FINALIZED_QUIZ_RESULT_IS_IMMUTABLE' using errcode = '55000';
  end if;
  if old.released_at is not null
     and (new.released_at is distinct from old.released_at or new.released_by is distinct from old.released_by) then
    raise exception 'RELEASED_QUIZ_RESULT_IS_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end
$$;
revoke all on function private.protect_quiz_result_finalization() from public, anon, authenticated;
create trigger quiz_result_finalizations_protect
  before update or delete on public.quiz_result_finalizations
  for each row execute function private.protect_quiz_result_finalization();

alter table public.quiz_essay_scores enable row level security;
alter table public.quiz_result_finalizations enable row level security;
-- Owning instructor and admin always; the learner only after release.
create policy quiz_essay_scores_select_scoped on public.quiz_essay_scores for select to authenticated
using (exists (
  select 1 from public.quiz_attempts qa
  where qa.id = quiz_essay_scores.attempt_id
    and (public.is_admin()
      or exists (select 1 from public.classes c where c.id = qa.class_id and c.instructor_id = (select auth.uid()))
      or (qa.learner_id = (select auth.uid()) and qa.evaluation_status = 'released'))
));
create policy quiz_result_finalizations_select_scoped on public.quiz_result_finalizations for select to authenticated
using (exists (
  select 1 from public.quiz_attempts qa
  where qa.id = quiz_result_finalizations.attempt_id
    and (public.is_admin()
      or exists (select 1 from public.classes c where c.id = qa.class_id and c.instructor_id = (select auth.uid()))
      or (qa.learner_id = (select auth.uid()) and qa.evaluation_status = 'released'))
));
revoke all on public.quiz_essay_scores, public.quiz_result_finalizations from public, anon, authenticated;
grant select on public.quiz_essay_scores, public.quiz_result_finalizations to authenticated;
grant all on public.quiz_essay_scores, public.quiz_result_finalizations to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.quiz_essay_scores, public.quiz_result_finalizations;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Points helpers
-- ---------------------------------------------------------------------------
-- Objective points from graded answers, essay points from the latest rubric
-- scores (unanswered essays count zero), and how many answered essays are scored.
create function private.quiz_attempt_points(p_attempt_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with items as (
    select qi.id, qi.item_type, qi.points, ans.id answer_id, ans.is_correct
    from public.quiz_attempts a
    join public.quiz_items qi on qi.quiz_version_id = a.quiz_version_id
      and qi.review_status = 'approved'::public.quiz_item_review_status and qi.removed_at is null
    left join public.quiz_answers ans on ans.quiz_attempt_id = a.id and ans.quiz_item_id = qi.id
    where a.id = p_attempt_id
  ), latest as (
    select distinct on (s.item_id) s.item_id, s.total
    from public.quiz_essay_scores s
    where s.attempt_id = p_attempt_id
    order by s.item_id, s.evaluated_at desc, s.id desc
  )
  select jsonb_build_object(
    'objective_points', coalesce(sum(i.points) filter (where i.item_type <> 'scenario_essay'::public.quiz_item_type and i.is_correct), 0),
    'essay_points', coalesce(sum(l.total) filter (where i.item_type = 'scenario_essay'::public.quiz_item_type), 0),
    'max_points', coalesce(sum(i.points), 0),
    'essays_required', count(*) filter (where i.item_type = 'scenario_essay'::public.quiz_item_type and i.answer_id is not null),
    'essays_scored', count(*) filter (where i.item_type = 'scenario_essay'::public.quiz_item_type and i.answer_id is not null and l.item_id is not null))
  from items i
  left join latest l on l.item_id = i.id
$$;

create function private.lock_owned_quiz_attempt(p_actor uuid, p_attempt_id uuid)
returns public.quiz_attempts
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_attempt public.quiz_attempts;
begin
  select a.* into v_attempt
  from public.quiz_attempts a
  join public.classes c on c.id = a.class_id
  where a.id = p_attempt_id and c.instructor_id = p_actor
  for update of a;
  if not found then raise exception 'QUIZ_EVALUATION_SCOPE_DENIED' using errcode = '42501'; end if;
  return v_attempt;
end
$$;

create function private.quiz_finalization_json(p_finalization public.quiz_result_finalizations, p_status text, p_already boolean)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'attempt_id', p_finalization.attempt_id,
    'evaluation_status', p_status,
    'objective_points', p_finalization.objective_points,
    'essay_points', p_finalization.essay_points,
    'total_points', p_finalization.total_points,
    'max_points', p_finalization.max_points,
    'percent', p_finalization.percent,
    'finalized_at', p_finalization.finalized_at,
    'released_at', p_finalization.released_at,
    'already', p_already)
$$;

revoke all on function private.quiz_attempt_points(uuid) from public, anon, authenticated;
revoke all on function private.lock_owned_quiz_attempt(uuid, uuid) from public, anon, authenticated;
revoke all on function private.quiz_finalization_json(public.quiz_result_finalizations, text, boolean) from public, anon, authenticated;
grant execute on function private.quiz_attempt_points(uuid) to service_role;
grant execute on function private.lock_owned_quiz_attempt(uuid, uuid) to service_role;
grant execute on function private.quiz_finalization_json(public.quiz_result_finalizations, text, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Evaluate -> Finalize -> Release (service-only invoker)
-- ---------------------------------------------------------------------------
create function public.manage_quiz_evaluation(p_actor uuid, p_action text, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_now timestamptz := private.activity_server_now();
  v_attempt public.quiz_attempts;
  v_item public.quiz_items;
  v_scores jsonb;
  v_criterion jsonb;
  v_value jsonb;
  v_total numeric := 0;
  v_feedback text;
  v_row public.quiz_essay_scores;
  v_points jsonb;
  v_status text;
  v_fin public.quiz_result_finalizations;
  v_ids uuid[];
  v_id uuid;
  v_results jsonb := '[]'::jsonb;
  v_released jsonb := '[]'::jsonb;
  v_already jsonb := '[]'::jsonb;
  v_objective numeric;
  v_essay numeric;
  v_max numeric;
begin
  -- Results are evaluated, finalized and released only by the owning instructor.
  if not exists (
    select 1 from public.profiles p
    where p.user_id = p_actor and p.role = 'instructor'::public.user_role and p.status = 'active'::public.account_status
  ) then
    raise exception 'INSTRUCTOR_REQUIRED' using errcode = '42501';
  end if;

  if p_action = 'score_essay' then
    v_attempt := private.lock_owned_quiz_attempt(p_actor, (v_payload->>'attempt_id')::uuid);
    if v_attempt.status <> 'completed'::public.quiz_attempt_status or v_attempt.evaluation_status not in ('pending', 'evaluated') then
      raise exception 'QUIZ_EVALUATION_STATE_INVALID' using errcode = '55000';
    end if;
    select qi.* into v_item from public.quiz_items qi
    where qi.id = (v_payload->>'item_id')::uuid
      and qi.quiz_version_id = v_attempt.quiz_version_id
      and qi.item_type = 'scenario_essay'::public.quiz_item_type
      and qi.review_status = 'approved'::public.quiz_item_review_status
      and qi.removed_at is null;
    if not found then raise exception 'QUIZ_ESSAY_ITEM_NOT_FOUND' using errcode = 'P0002'; end if;
    v_scores := v_payload->'criterion_scores';
    if v_scores is null or jsonb_typeof(v_scores) <> 'object' then
      raise exception 'QUIZ_ESSAY_SCORE_INVALID' using errcode = '22023';
    end if;
    if (select count(*) from jsonb_object_keys(v_scores)) <> jsonb_array_length(v_item.rubric) then
      raise exception 'QUIZ_ESSAY_SCORE_INVALID' using errcode = '22023';
    end if;
    for v_criterion in select value from jsonb_array_elements(v_item.rubric) loop
      v_value := v_scores->(v_criterion->>'id');
      if v_value is null or jsonb_typeof(v_value) <> 'number' then
        raise exception 'QUIZ_ESSAY_SCORE_INVALID' using errcode = '22023';
      end if;
      if (v_value #>> '{}')::numeric < 0 or (v_value #>> '{}')::numeric > (v_criterion->>'max_points')::numeric then
        raise exception 'QUIZ_ESSAY_SCORE_INVALID' using errcode = '22023';
      end if;
      v_total := v_total + (v_value #>> '{}')::numeric;
    end loop;
    v_feedback := nullif(btrim(v_payload->>'feedback'), '');
    if length(coalesce(v_feedback, '')) > 5000 then
      raise exception 'QUIZ_ESSAY_FEEDBACK_TOO_LONG' using errcode = '22023';
    end if;
    insert into public.quiz_essay_scores (attempt_id, item_id, criterion_scores, total, feedback, evaluated_by, evaluated_at)
    values (v_attempt.id, v_item.id, v_scores, v_total, v_feedback, p_actor, v_now)
    returning * into v_row;
    v_points := private.quiz_attempt_points(v_attempt.id);
    v_status := v_attempt.evaluation_status;
    if v_status = 'pending' and (v_points->>'essays_scored')::integer >= (v_points->>'essays_required')::integer then
      update public.quiz_attempts set evaluation_status = 'evaluated' where id = v_attempt.id;
      v_status := 'evaluated';
    end if;
    insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, new_value, metadata, created_at)
    values (p_actor, 'instructor', 'quiz_essay.scored', 'quiz_attempt', v_attempt.id,
      jsonb_build_object('item_id', v_item.id, 'score_id', v_row.id, 'criterion_scores', v_scores, 'total', v_total,
        'max_points', v_item.points),
      jsonb_build_object('evaluation_status', v_status, 'feedback_supplied', v_feedback is not null), v_now);
    return jsonb_build_object(
      'attempt_id', v_attempt.id, 'item_id', v_item.id, 'score_id', v_row.id, 'total', v_total,
      'max_points', v_item.points, 'evaluation_status', v_status,
      'essays_scored', (v_points->>'essays_scored')::integer, 'essays_required', (v_points->>'essays_required')::integer);

  elsif p_action = 'finalize' then
    if v_payload ? 'attempt_ids' then
      if jsonb_typeof(v_payload->'attempt_ids') <> 'array' then
        raise exception 'QUIZ_EVALUATION_SELECTION_INVALID' using errcode = '22023';
      end if;
      select array_agg(distinct x::uuid order by x::uuid) into v_ids from jsonb_array_elements_text(v_payload->'attempt_ids') x;
    else
      v_ids := array[(v_payload->>'attempt_id')::uuid];
    end if;
    if v_ids is null or array_position(v_ids, null) is not null or cardinality(v_ids) not between 1 and 100 then
      raise exception 'QUIZ_EVALUATION_SELECTION_INVALID' using errcode = '22023';
    end if;
    foreach v_id in array v_ids loop
      v_attempt := private.lock_owned_quiz_attempt(p_actor, v_id);
      if v_attempt.evaluation_status in ('finalized', 'released') then
        select f.* into v_fin from public.quiz_result_finalizations f where f.attempt_id = v_id;
        v_results := v_results || jsonb_build_array(private.quiz_finalization_json(v_fin, v_attempt.evaluation_status, true));
        continue;
      end if;
      if v_attempt.evaluation_status = 'not_required' then
        raise exception 'QUIZ_EVALUATION_NOT_REQUIRED' using errcode = '22023';
      end if;
      if v_attempt.evaluation_status = 'pending' then
        raise exception 'QUIZ_ESSAYS_NOT_SCORED' using errcode = '55000';
      end if;
      v_points := private.quiz_attempt_points(v_id);
      v_objective := (v_points->>'objective_points')::numeric;
      v_essay := (v_points->>'essay_points')::numeric;
      v_max := (v_points->>'max_points')::numeric;
      insert into public.quiz_result_finalizations (
        attempt_id, objective_points, essay_points, total_points, max_points, percent, finalized_by, finalized_at
      ) values (
        v_id, v_objective, v_essay, v_objective + v_essay, v_max,
        round((v_objective + v_essay) / v_max * 100, 2), p_actor, v_now
      ) returning * into v_fin;
      update public.quiz_attempts set evaluation_status = 'finalized' where id = v_id;
      insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, created_at)
      values (p_actor, 'instructor', 'quiz_result.finalized', 'quiz_attempt', v_id,
        jsonb_build_object('evaluation_status', v_attempt.evaluation_status),
        private.quiz_finalization_json(v_fin, 'finalized', false), v_now);
      v_results := v_results || jsonb_build_array(private.quiz_finalization_json(v_fin, 'finalized', false));
    end loop;
    if v_payload ? 'attempt_ids' then return jsonb_build_object('results', v_results); end if;
    return v_results->0;

  elsif p_action = 'release' then
    if jsonb_typeof(v_payload->'attempt_ids') is distinct from 'array' then
      raise exception 'QUIZ_EVALUATION_SELECTION_INVALID' using errcode = '22023';
    end if;
    select array_agg(distinct x::uuid order by x::uuid) into v_ids from jsonb_array_elements_text(v_payload->'attempt_ids') x;
    if v_ids is null or array_position(v_ids, null) is not null or cardinality(v_ids) not between 1 and 100 then
      raise exception 'QUIZ_EVALUATION_SELECTION_INVALID' using errcode = '22023';
    end if;
    foreach v_id in array v_ids loop
      v_attempt := private.lock_owned_quiz_attempt(p_actor, v_id);
      if v_attempt.evaluation_status = 'released' then
        v_already := v_already || to_jsonb(v_id);
        continue;
      end if;
      if v_attempt.evaluation_status <> 'finalized' then
        raise exception 'QUIZ_RESULT_NOT_FINALIZED' using errcode = '55000';
      end if;
      update public.quiz_result_finalizations set released_by = p_actor, released_at = v_now where attempt_id = v_id;
      update public.quiz_attempts set evaluation_status = 'released' where id = v_id;
      insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, created_at)
      values (p_actor, 'instructor', 'quiz_result.released', 'quiz_attempt', v_id,
        jsonb_build_object('evaluation_status', 'finalized'),
        jsonb_build_object('evaluation_status', 'released', 'released_at', v_now, 'learner_id', v_attempt.learner_id), v_now);
      v_released := v_released || to_jsonb(v_id);
    end loop;
    return jsonb_build_object('released', v_released, 'already_released', v_already);
  end if;
  raise exception 'QUIZ_EVALUATION_ACTION_INVALID' using errcode = '22023';
end
$$;
revoke all on function public.manage_quiz_evaluation(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.manage_quiz_evaluation(uuid, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Evaluation Center items (RLS-scoped invoker; owning instructor or admin)
-- ---------------------------------------------------------------------------
-- Stages: evaluate = pending, finalize = evaluated, release = finalized,
-- released = released. Filters: class_id, coc_code, module_id, learner_id.
-- A module filter also matches whole-COC quizzes of that module's COC.
create function public.quiz_evaluation_queue_items(p_stage text, p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_status text;
  v_class uuid;
  v_learner uuid;
  v_module uuid;
  v_coc text;
  v_items jsonb;
begin
  if not (public.is_instructor() or public.is_admin()) then
    raise exception 'STAFF_REQUIRED' using errcode = '42501';
  end if;
  v_status := case p_stage
    when 'evaluate' then 'pending' when 'finalize' then 'evaluated'
    when 'release' then 'finalized' when 'released' then 'released' end;
  if v_status is null then raise exception 'INVALID_EVALUATION_STAGE' using errcode = '22023'; end if;
  v_class := nullif(v_filters->>'class_id', '')::uuid;
  v_learner := nullif(v_filters->>'learner_id', '')::uuid;
  v_module := nullif(v_filters->>'module_id', '')::uuid;
  v_coc := lower(nullif(btrim(v_filters->>'coc_code'), ''));

  select coalesce(jsonb_agg(item order by sort_key, item_key), '[]'::jsonb) into v_items
  from (
    select jsonb_build_object(
        'kind', 'quiz',
        'id', qa.id,
        'title', q.title,
        'learner', jsonb_build_object('id', qa.learner_id, 'name', coalesce(nullif(btrim(p.full_name), ''), 'Learner')),
        'class', jsonb_build_object('id', c.id, 'title', c.title),
        'submitted_at', qa.submitted_at,
        'status', qa.evaluation_status,
        'score', case
          when qa.evaluation_status in ('finalized', 'released') then f.total_points
          when qa.evaluation_status = 'evaluated' then pts.objective_points + pts.essay_points
          else null end,
        'max_score', coalesce(f.max_points, pts.max_points),
        'link', '/quizzes/' || q.id::text || '?tab=results&attempt=' || qa.id::text
      ) item,
      case when p_stage = 'released' then -extract(epoch from qa.submitted_at) else extract(epoch from qa.submitted_at) end sort_key,
      qa.id::text item_key
    from public.quiz_attempts qa
    join public.quiz_versions qv on qv.id = qa.quiz_version_id
    join public.quizzes q on q.id = qv.quiz_id
    join public.classes c on c.id = qa.class_id
    left join public.profiles p on p.user_id = qa.learner_id
    left join public.coc_modules cm on cm.id = q.coc_module_id
    left join public.quiz_result_finalizations f on f.attempt_id = qa.id
    cross join lateral (
      select coalesce(sum(qi.points), 0) max_points,
        coalesce(sum(qi.points) filter (where qi.item_type <> 'scenario_essay'::public.quiz_item_type and ans.is_correct), 0) objective_points,
        coalesce(sum(ls.total) filter (where qi.item_type = 'scenario_essay'::public.quiz_item_type), 0) essay_points
      from public.quiz_items qi
      left join public.quiz_answers ans on ans.quiz_attempt_id = qa.id and ans.quiz_item_id = qi.id
      left join lateral (
        select s.total from public.quiz_essay_scores s
        where s.attempt_id = qa.id and s.item_id = qi.id
        order by s.evaluated_at desc, s.id desc limit 1
      ) ls on true
      where qi.quiz_version_id = qa.quiz_version_id
        and qi.review_status = 'approved'::public.quiz_item_review_status
        and qi.removed_at is null
    ) pts
    where qa.evaluation_status = v_status
      and (v_class is null or qa.class_id = v_class)
      and (v_learner is null or qa.learner_id = v_learner)
      and (v_coc is null or cm.coc_code = v_coc)
      and (v_module is null
        or exists (select 1 from public.quiz_modules qm where qm.quiz_id = q.id and qm.module_id = v_module)
        or (not exists (select 1 from public.quiz_modules qm where qm.quiz_id = q.id)
            and exists (select 1 from public.curriculum_modules m where m.id = v_module and m.coc_module_id = q.coc_module_id)))
    limit 500
  ) scoped;
  return v_items;
end
$$;
revoke all on function public.quiz_evaluation_queue_items(text, jsonb) from public, anon;
grant execute on function public.quiz_evaluation_queue_items(text, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Learner result payload with the released state and rubric feedback
-- ---------------------------------------------------------------------------
create or replace function private.learner_quiz_result_payload(p_attempt_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_attempt public.quiz_attempts;
  v_result public.quiz_results;
  v_fin public.quiz_result_finalizations;
  v_visible boolean;
  v_payload jsonb;
begin
  select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id;
  select r.* into v_result from public.quiz_results r where r.quiz_attempt_id = p_attempt_id;
  select f.* into v_fin from public.quiz_result_finalizations f where f.attempt_id = p_attempt_id;
  v_visible := v_attempt.evaluation_status in ('not_required', 'released');
  select jsonb_build_object(
      'attempt_id', v_attempt.id,
      'status', v_attempt.status,
      'title', q.title,
      'class_title', c.title,
      'completed_at', v_attempt.completed_at,
      'submitted_at', v_attempt.submitted_at,
      'submission_kind', v_attempt.submission_kind,
      'evaluation_status', v_attempt.evaluation_status,
      'result_release_mode', qv.result_release_mode,
      'result_status', case when not v_visible then 'awaiting_evaluation'
                            when v_attempt.evaluation_status = 'released' then 'released' else 'available' end,
      'question_count', v_result.question_count,
      'answered_count', (select count(*) from public.quiz_answers ans where ans.quiz_attempt_id = v_attempt.id),
      'supplementary_only', true)
    || case
       when v_attempt.evaluation_status = 'released' then jsonb_build_object(
         'correct_count', v_result.correct_count,
         'objective_points', v_fin.objective_points,
         'essay_points', v_fin.essay_points,
         'total_points', v_fin.total_points,
         'max_points', v_fin.max_points,
         'percent', v_fin.percent,
         'released_at', v_fin.released_at,
         'item_results', coalesce((
           select jsonb_agg(case
               when ir->>'type' = 'scenario_essay' then ir || jsonb_build_object(
                 'points_awarded', coalesce(ls.total, 0),
                 'feedback', ls.feedback,
                 'evaluated', ls.id is not null,
                 'rubric', (
                   select jsonb_agg(jsonb_build_object(
                       'id', crit->'id', 'criterion', crit->'criterion', 'description', crit->'description',
                       'max_points', crit->'max_points', 'points', coalesce(ls.criterion_scores->(crit->>'id'), '0'::jsonb))
                     order by ordinal)
                   from jsonb_array_elements(qi.rubric) with ordinality rubric(crit, ordinal)))
               else ir end
             order by (ir->>'order_index')::integer)
           from jsonb_array_elements(v_result.item_results) ir
           left join public.quiz_items qi on qi.id = (ir->>'item_id')::uuid
           left join lateral (
             select s.* from public.quiz_essay_scores s
             where s.attempt_id = v_attempt.id and s.item_id = qi.id
             order by s.evaluated_at desc, s.id desc limit 1
           ) ls on true), '[]'::jsonb))
       when v_visible then jsonb_build_object(
         'correct_count', v_result.correct_count,
         'objective_points', v_result.objective_points,
         'max_points', v_result.max_points,
         'item_results', v_result.item_results)
       else jsonb_build_object('item_results', coalesce((
         select jsonb_agg(jsonb_build_object(
             'item_id', r->'item_id', 'code', r->'code', 'type', r->'type', 'prompt', r->'prompt',
             'learner_answer', r->'learner_answer', 'answered', coalesce(r->'answered', 'true'::jsonb),
             'order_index', r->'order_index')
           order by (r->>'order_index')::integer)
         from jsonb_array_elements(v_result.item_results) r), '[]'::jsonb))
       end
  into v_payload
  from public.quiz_versions qv
  join public.quizzes q on q.id = qv.quiz_id
  join public.classes c on c.id = v_attempt.class_id
  where qv.id = v_attempt.quiz_version_id;
  return v_payload;
end
$$;

notify pgrst, 'reload schema';
commit;
