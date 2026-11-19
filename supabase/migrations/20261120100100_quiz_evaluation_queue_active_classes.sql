-- Final fix wave (demo-data review m4; final review SQL-B M4): the quiz part
-- of the Evaluation Center queue skips archived classes in its action stages,
-- as the technical and homework parts of public.get_evaluation_queue already
-- do (20261119140200: "Action stages list active classes only"). Evaluate,
-- Finalize and Release list quiz attempts of active classes only; Released
-- keeps every visible released result. Reactivating a class brings its work
-- back. Body otherwise identical to 20261119130600 (same signature, SECURITY
-- INVOKER, grants kept by create or replace).
begin;
set local lock_timeout = '5s';

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
      -- Action stages list active classes only; Released lists every result.
      and (v_status = 'released' or c.status = 'active'::public.class_status)
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
