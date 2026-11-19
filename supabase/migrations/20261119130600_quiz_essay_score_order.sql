-- Re-defense A3 fix round 2: the current essay score is chosen
-- deterministically.
--
-- The current score for an attempt and item was the row with the latest
-- evaluated_at, then the highest id. The id is a random uuid, so two scores
-- with the same evaluated_at resolved arbitrarily. That happens whenever the
-- server clock is pinned (the rollback suites score twice in one transaction)
-- and whenever clock_timestamp() repeats a microsecond. Every score now gets a
-- sequence number at insert, and every reader orders by evaluated_at desc,
-- sequence desc: of scores with the same evaluated_at, the one recorded last is
-- current. Writes to one attempt are serialised by its row lock
-- (private.lock_owned_quiz_attempt), so a higher sequence always means
-- recorded later.
--
-- Readers updated (same signatures; create or replace keeps the grants):
-- private.quiz_attempt_points (scored-essay count and finalize totals),
-- public.quiz_evaluation_queue_items (Evaluation Center score) and
-- private.learner_quiz_result_payload (released learner result). The dashboard
-- instructor view applies the same rule. Existing rows get sequence numbers
-- when the column is added; no other data changes and score history stays
-- append-only.
begin;
set local lock_timeout = '5s';

alter table public.quiz_essay_scores
  add column sequence bigint generated always as identity;
comment on column public.quiz_essay_scores.sequence is
  'Monotonic insert order. The current score for an attempt and item is the row with the latest evaluated_at, then the highest sequence.';

drop index if exists public.quiz_essay_scores_attempt_item_idx;
create index quiz_essay_scores_current_idx
  on public.quiz_essay_scores(attempt_id, item_id, evaluated_at desc, sequence desc);

create or replace function private.quiz_attempt_points(p_attempt_id uuid)
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
    -- Current score: latest evaluated_at, then the highest sequence.
    select distinct on (s.item_id) s.item_id, s.total
    from public.quiz_essay_scores s
    where s.attempt_id = p_attempt_id
    order by s.item_id, s.evaluated_at desc, s.sequence desc
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

-- Same contract as 20261119130500; only the current-score ordering changes.
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
        order by s.evaluated_at desc, s.sequence desc limit 1
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

-- Same payload as 20261119130300; only the current-score ordering changes.
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
             order by s.evaluated_at desc, s.sequence desc limit 1
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
