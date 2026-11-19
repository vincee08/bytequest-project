-- Re-defense A3 review fix: learners see no quiz total, percentage,
-- objective points, item results, essay scores or per-item correctness
-- before an instructor-release result is released, whichever way they read.
--
-- The result RPCs already hid these values, but the learner branches of the
-- quiz_results and quiz_answers SELECT policies (20260814123000 /
-- 20260812120000) still exposed the rows to direct PostgREST queries. The
-- learner branch now requires evaluation_status not_required (immediate
-- results; also every attempt still in progress) or released. In-progress
-- answers carry no correctness (grading happens at submission), so saved
-- answers stay readable and resumable. Staff branches are unchanged.
-- quiz_essay_scores and quiz_result_finalizations were already gated.
--
-- Review minor items fixed in the same step (service-only / RLS invoker
-- functions, same signatures): essays the learner never answered cannot be
-- given points; evaluation requires the actor to teach the class and own the
-- quiz; the Evaluation Center item list is ordered before its 500-item cap.
begin;
set local lock_timeout = '5s';

drop policy if exists quiz_results_select_scoped on public.quiz_results;
create policy quiz_results_select_scoped on public.quiz_results for select to authenticated
using (exists (
  select 1 from public.quiz_attempts qa
  where qa.id = quiz_results.quiz_attempt_id
    and (
      public.is_admin()
      or exists (
        select 1 from public.classes c
        where c.id = qa.class_id and c.instructor_id = (select auth.uid()))
      or (qa.learner_id = (select auth.uid())
          and qa.evaluation_status in ('not_required', 'released'))
    )
));

drop policy if exists quiz_answers_select_scoped on public.quiz_answers;
create policy quiz_answers_select_scoped on public.quiz_answers for select to authenticated
using (exists (
  select 1 from public.quiz_attempts qa
  where qa.id = quiz_answers.quiz_attempt_id
    and (
      public.is_admin()
      or public.instructor_owns_class(qa.class_id)
      or (qa.learner_id = (select auth.uid())
          and (qa.status = 'in_progress'::public.quiz_attempt_status
               or qa.evaluation_status in ('not_required', 'released')))
    )
));

comment on policy quiz_results_select_scoped on public.quiz_results is
  'Owning class instructor and admins always; the learner only for immediate results or after the instructor releases them.';
comment on policy quiz_answers_select_scoped on public.quiz_answers is
  'Owning class instructor and admins always; the learner while the attempt is in progress (ungraded) and for immediate or released results.';

-- Evaluation needs the class instructor who also owns the quiz.
create or replace function private.lock_owned_quiz_attempt(p_actor uuid, p_attempt_id uuid)
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
  join public.quiz_versions qv on qv.id = a.quiz_version_id
  join public.quizzes q on q.id = qv.quiz_id
  where a.id = p_attempt_id and c.instructor_id = p_actor and q.instructor_id = p_actor
  for update of a;
  if not found then raise exception 'QUIZ_EVALUATION_SCOPE_DENIED' using errcode = '42501'; end if;
  return v_attempt;
end
$$;

create or replace function public.manage_quiz_evaluation(p_actor uuid, p_action text, p_payload jsonb)
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
    -- Unanswered essays score zero; nothing is invented.
    if not exists (
      select 1 from public.quiz_answers ans
      where ans.quiz_attempt_id = v_attempt.id and ans.quiz_item_id = v_item.id
    ) then
      raise exception 'QUIZ_ESSAY_NOT_ANSWERED' using errcode = '22023';
    end if;
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

-- Same contract as 20261119130300; the 500-item cap now applies after ordering.
create or replace function public.quiz_evaluation_queue_items(p_stage text, p_filters jsonb default '{}'::jsonb)
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
    order by sort_key, item_key
    limit 500
  ) scoped;
  return v_items;
end
$$;

notify pgrst, 'reload schema';
commit;
