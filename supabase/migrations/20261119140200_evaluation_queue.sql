-- Evaluation Center queue (Objective 4): one read of the four stages
--   Evaluate -> Finalize -> Release -> Released
-- across technical assessments, homework and instructor-released quizzes.
--
-- SECURITY INVOKER: every row comes through the caller's existing RLS
-- (instructors: their own classes; admins: everything). Action stages list
-- active classes only (archived classes cannot be finalized or released);
-- Released lists every visible result.
--
-- Stage mapping
--   technical attempts: evaluated | under_review | finalized | released
--   homework:           submitted | graded       | finalized | released
--   quizzes:            from slice A3's public.quiz_evaluation_queue_items
--                       (called only when installed; same item shape).
begin;
set local lock_timeout = '5s';

create function public.get_evaluation_queue(p_stage text, p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_class uuid;
  v_learner uuid;
  v_module uuid;
  v_kind text;
  v_coc text;
  v_limit integer := 50;
  v_offset integer := 0;
  v_stages constant text[] := array['evaluate', 'finalize', 'release', 'released'];
  v_stage text;
  v_quiz_available boolean := false;
  v_quiz jsonb;
  v_quiz_items jsonb := '[]'::jsonb;
  v_quiz_counts jsonb := '{}'::jsonb;
  v_counts jsonb;
  v_items jsonb;
begin
  if p_stage is null or not (p_stage = any(v_stages)) then
    raise exception 'EVALUATION_STAGE_INVALID' using errcode = '22023';
  end if;
  if not public.is_staff() then
    raise exception 'STAFF_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(v_filters) <> 'object'
     or exists (select 1 from jsonb_each(v_filters) f
       where f.key in ('class_id', 'learner_id', 'module_id', 'kind', 'coc_code') and jsonb_typeof(f.value) not in ('string', 'null')
          or f.key in ('limit', 'offset') and jsonb_typeof(f.value) not in ('number', 'null'))
     or coalesce(v_filters->>'class_id', '00000000-0000-0000-0000-000000000000') !~ c_uuid
     or coalesce(v_filters->>'learner_id', '00000000-0000-0000-0000-000000000000') !~ c_uuid
     or coalesce(v_filters->>'module_id', '00000000-0000-0000-0000-000000000000') !~ c_uuid
     or coalesce(v_filters->>'kind', 'technical') not in ('technical', 'quiz', 'homework')
     or coalesce(v_filters->>'coc_code', 'coc1') !~ '^coc[1-4]$'
     or coalesce(v_filters->>'limit', '50') !~ '^[0-9]{1,3}$'
     or coalesce(v_filters->>'offset', '0') !~ '^[0-9]{1,6}$' then
    raise exception 'EVALUATION_FILTERS_INVALID' using errcode = '22023';
  end if;
  v_class := (v_filters->>'class_id')::uuid;
  v_learner := (v_filters->>'learner_id')::uuid;
  v_module := (v_filters->>'module_id')::uuid;
  v_kind := v_filters->>'kind';
  v_coc := v_filters->>'coc_code';
  v_limit := coalesce((v_filters->>'limit')::integer, 50);
  v_offset := coalesce((v_filters->>'offset')::integer, 0);
  if v_limit not between 1 and 100 then
    raise exception 'EVALUATION_FILTERS_INVALID' using errcode = '22023';
  end if;

  -- Quiz essays (slice A3). Dynamic so this function works before and after
  -- that function is installed.
  v_quiz_available := to_regprocedure('public.quiz_evaluation_queue_items(text,jsonb)') is not null;
  if v_quiz_available and (v_kind is null or v_kind = 'quiz') then
    foreach v_stage in array v_stages loop
      execute 'select public.quiz_evaluation_queue_items($1, $2)'
        into v_quiz
        using v_stage, jsonb_strip_nulls(jsonb_build_object(
          'class_id', v_class, 'coc_code', v_coc, 'module_id', v_module, 'learner_id', v_learner));
      if jsonb_typeof(v_quiz) is distinct from 'array' then
        v_quiz := '[]'::jsonb;
      end if;
      v_quiz_counts := v_quiz_counts || jsonb_build_object(v_stage, jsonb_array_length(v_quiz));
      if v_stage = p_stage then
        v_quiz_items := v_quiz;
      end if;
    end loop;
  end if;

  with technical as (
    select
      case a.status
        when 'evaluated' then 'evaluate' when 'under_review' then 'finalize'
        when 'finalized' then 'release' else 'released' end as stage,
      jsonb_build_object(
        'kind', 'technical',
        'id', a.id,
        'title', coalesce(asg.title, m.title, 'Technical assessment'),
        'learner', jsonb_build_object('id', a.learner_id, 'name', p.full_name),
        'class', jsonb_build_object('id', c.id, 'title', c.title),
        'submitted_at', a.submitted_at,
        'status', a.status,
        'score', latest.total_value,
        'max_score', latest.max_value,
        'outcome', latest.outcome,
        'coc_code', coc.coc_code,
        'module_id', coalesce(acl.module_id, mcl.module_id),
        'mission_code', m.mission_code,
        'stage_at', coalesce(a.released_at, a.finalized_at, a.evaluated_at, a.submitted_at),
        'link', '/attempts/' || a.id::text) as item,
      a.submitted_at
    from public.attempts a
    join public.classes c on c.id = a.class_id
    left join public.assignments asg on asg.id = a.assignment_id
    left join public.activity_versions av on av.id = a.activity_version_id
    left join public.missions m on m.id = av.mission_id
    left join public.coc_modules coc on coc.id = m.coc_id
    left join public.activity_curriculum_links acl on acl.activity_version_id = a.activity_version_id
    left join public.mission_curriculum_links mcl on mcl.mission_code = m.mission_code
    left join public.profiles p on p.user_id = a.learner_id
    left join lateral (
      select sr.total_value, sr.max_value, sr.outcome
      from public.score_revisions sr
      where sr.attempt_id = a.id
      order by sr.revision_number desc
      limit 1
    ) latest on true
    where a.status in ('evaluated', 'under_review', 'finalized', 'released')
      and (a.status = 'released' or c.status = 'active')
      and (v_kind is null or v_kind = 'technical')
      and (v_class is null or a.class_id = v_class)
      and (v_learner is null or a.learner_id = v_learner)
      and (v_coc is null or coc.coc_code = v_coc)
      and (v_module is null or coalesce(acl.module_id, mcl.module_id) = v_module)
  ),
  homework as (
    select
      case s.status
        when 'submitted' then 'evaluate' when 'graded' then 'finalize'
        when 'finalized' then 'release' else 'released' end as stage,
      jsonb_build_object(
        'kind', 'homework',
        'id', s.id,
        'title', h.title,
        'learner', jsonb_build_object('id', s.learner_id, 'name', p.full_name),
        'class', jsonb_build_object('id', c.id, 'title', c.title),
        'submitted_at', s.submitted_at,
        'status', s.status,
        'score', s.score,
        'max_score', h.max_score,
        'late', s.lateness_seconds > 0,
        'coc_code', coalesce(coc.coc_code, cm.coc_code),
        'module_id', h.module_id,
        'mission_code', h.mission_code,
        'assignment_id', h.id,
        'stage_at', coalesce(s.released_at, s.finalized_at, s.graded_at, s.submitted_at),
        'link', '/classes/' || h.class_id::text || '/assignments/' || h.id::text || '?submission=' || s.id::text) as item,
      s.submitted_at
    from public.homework_submissions s
    join public.homework_assignments h on h.id = s.assignment_id
    join public.classes c on c.id = h.class_id
    left join public.coc_modules coc on coc.id = h.coc_module_id
    left join public.curriculum_modules cm on cm.id = h.module_id
    left join public.profiles p on p.user_id = s.learner_id
    where (s.status = 'released' or c.status = 'active')
      and (v_kind is null or v_kind = 'homework')
      and (v_class is null or h.class_id = v_class)
      and (v_learner is null or s.learner_id = v_learner)
      and (v_coc is null or coalesce(coc.coc_code, cm.coc_code) = v_coc)
      and (v_module is null or h.module_id = v_module)
  ),
  quiz as (
    select p_stage as stage, q as item, (q->>'submitted_at')::timestamptz as submitted_at
    from jsonb_array_elements(v_quiz_items) q
  ),
  combined as (
    select stage, item, submitted_at from technical
    union all
    select stage, item, submitted_at from homework
  )
  select
    (select jsonb_object_agg(st, (select count(*) from combined x where x.stage = st)
        + coalesce((v_quiz_counts->>st)::integer, 0))
     from unnest(v_stages) st),
    (select coalesce(jsonb_agg(page.item order by page.ord), '[]'::jsonb)
     from (
       select y.item, row_number() over (
           order by
             case when p_stage = 'released' then null else y.submitted_at end asc nulls last,
             case when p_stage = 'released' then y.submitted_at end desc nulls last,
             y.item->>'kind', y.item->>'id') as ord
       from (
         select item, submitted_at from combined where stage = p_stage
         union all
         select item, submitted_at from quiz
       ) y
       order by ord
       offset v_offset
       limit v_limit
     ) page)
  into v_counts, v_items;

  return jsonb_build_object(
    'stage', p_stage,
    'counts', v_counts,
    'total', (v_counts->>p_stage)::integer,
    'limit', v_limit,
    'offset', v_offset,
    'quiz_available', v_quiz_available,
    'items', v_items);
end
$$;

revoke all on function public.get_evaluation_queue(text, jsonb) from public, anon;
grant execute on function public.get_evaluation_queue(text, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
