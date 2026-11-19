-- Slice A7 (Objective 6): instructor/admin analytics RPCs. All functions are
-- STABLE SECURITY INVOKER: every row they aggregate is visible to the caller
-- under RLS, and scope is re-validated by private.analytics_scope (which
-- raises ANALYTICS_ACCESS_DENIED / ANALYTICS_FILTER_INVALID /
-- ANALYTICS_SCOPE_DENIED). Averages are null (never 0) without data; arrays
-- are empty without data. Definitions: docs/ANALYTICS_METRIC_DEFINITIONS.md.
begin;

-- ---------------------------------------------------------------------------
-- Filter bar options for the caller's scope.
-- ---------------------------------------------------------------------------
create or replace function public.get_analytics_filter_options()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope('{}'::jsonb);
begin
  return jsonb_build_object(
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.class_id, 'title', c.title, 'class_code', c.class_code) order by c.title)
      from private.analytics_classes(v_scope) c), '[]'::jsonb),
    'cocs', coalesce((
      select jsonb_agg(jsonb_build_object('code', lower(c.coc_code), 'title', c.title) order by c.coc_code)
      from public.coc_modules c
      where lower(c.coc_code) in (select cm.coc_code from public.curriculum_modules cm)), '[]'::jsonb),
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'coc_code', m.coc_code, 'code', m.code, 'title', m.title,
        'sequence_order', m.sequence_order) order by m.coc_code, m.sequence_order)
      from public.curriculum_modules m), '[]'::jsonb),
    'topics', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.topic_id, 'module_id', i.module_id, 'coc_code', i.coc_code,
        'title', i.title) order by i.coc_code, i.sequence_order, i.title)
      from private.analytics_required_items(v_scope) i where i.item_kind = 'topic'), '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object('mission_code', ms.mission_code, 'title', ms.title,
        'coc_code', lower(coc.coc_code), 'module_id', l.module_id, 'mission_number', ms.mission_number)
        order by lower(coc.coc_code), ms.mission_number)
      from public.missions ms
      join public.coc_modules coc on coc.id = ms.coc_id
      left join public.mission_curriculum_links l on l.mission_code = ms.mission_code), '[]'::jsonb),
    'quizzes', coalesce((
      select jsonb_agg(jsonb_build_object('id', q.id, 'title', q.title, 'coc_code', lower(coc.coc_code),
        'status', private.analytics_quiz_status(q.id)) order by q.title)
      from public.quizzes q
      left join public.coc_modules coc on coc.id = q.coc_module_id
      where exists (select 1 from public.quiz_versions v where v.quiz_id = q.id and v.published_at is not null)), '[]'::jsonb),
    'learners', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.learner_id, 'name', p.full_name, 'student_id', p.learner_id,
        'class_ids', x.class_ids) order by p.full_name, x.learner_id)
      from (
        select m.learner_id, jsonb_agg(m.class_id order by m.class_id) as class_ids
        from private.analytics_members(v_scope) m
        group by m.learner_id
      ) x
      join public.profiles p on p.user_id = x.learner_id), '[]'::jsonb),
    'generated_at', now()
  );
end
$$;

-- ---------------------------------------------------------------------------
-- Overview tab.
-- ---------------------------------------------------------------------------
create or replace function public.get_analytics_overview(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope(p_filters);
  v_from timestamptz := (v_scope ->> 'from')::timestamptz;
  v_to timestamptz := (v_scope ->> 'to')::timestamptz;
  v_result jsonb;
begin
  with
  classes as materialized (select * from private.analytics_classes(v_scope)),
  members as materialized (select * from private.analytics_members(v_scope)),
  population as materialized (select distinct m.learner_id from members m),
  activity as materialized (select * from private.analytics_last_activity(v_scope)),
  assessments as materialized (select * from private.analytics_assessment_facts(v_scope)),
  quiz_facts as materialized (select * from private.analytics_quiz_facts(v_scope)),
  quiz_scores as materialized (select * from quiz_facts q where q.class_in_scope and q.in_period),
  quiz_eligible as materialized (
    select distinct e.learner_id, e.quiz_id from private.analytics_quiz_eligibility(v_scope) e
  ),
  quiz_completed as materialized (
    select e.learner_id, e.quiz_id from quiz_eligible e
    where exists (select 1 from quiz_facts q where q.learner_id = e.learner_id and q.quiz_id = e.quiz_id)
  ),
  homework as materialized (select * from private.analytics_homework_facts(v_scope)),
  runs as materialized (select * from private.analytics_practice_runs(v_scope)),
  completions as materialized (select * from private.analytics_practice_completions(v_scope)),
  progress as materialized (select * from private.analytics_learner_progress(v_scope)),
  items as materialized (select * from private.analytics_required_items(v_scope)),
  mission_items as materialized (select i.mission_code from items i where i.item_kind = 'mission'),
  events as materialized (
    select (a.submitted_at at time zone 'Asia/Manila')::date as day, 'assessments'::text as kind
    from assessments a where a.submitted_at is not null
    union all
    select (q.submitted_at at time zone 'Asia/Manila')::date, 'quizzes' from quiz_scores q
    union all
    select (h.submitted_at at time zone 'Asia/Manila')::date, 'homework' from homework h where h.submitted_in_period
    union all
    select (r.event_at at time zone 'Asia/Manila')::date, 'practice_runs' from runs r where r.in_period
    union all
    select (c.verified_at at time zone 'Asia/Manila')::date, 'verified' from completions c where c.in_period
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'filters', private.analytics_public_filters(v_scope),
    'population', jsonb_build_object(
      'description', case
        when v_scope ->> 'learner_id' is not null then 'The selected learner'
        when v_scope ->> 'class_id' is not null then
          'Active learners in ' || coalesce((select c.title from classes c limit 1), 'the selected class')
        when v_scope ->> 'role' = 'admin' then 'Active learners in every active class'
        else 'Active learners in your active classes'
      end,
      'enrolled', (select count(*) from population),
      'active_in_period', (select count(*) from activity a where a.last_activity_at >= v_from),
      'completed', (select count(*) from progress p where p.total_items > 0 and p.completed_items = p.total_items)),
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.class_id, 'title', c.title, 'class_code', c.class_code,
        'enrolled', (select count(distinct m.learner_id) from members m where m.class_id = c.class_id)) order by c.title)
      from classes c), '[]'::jsonb),
    'assessments', (
      select jsonb_build_object(
        'applicable', private.analytics_source_applicable(v_scope, 'assessments'),
        'attempts', count(*),
        'submitted', count(*) filter (where a.submitted_at is not null),
        'released', count(*) filter (where a.released_at is not null),
        'competent', count(*) filter (where a.outcome = 'competent'),
        'not_yet_competent', count(*) filter (where a.outcome = 'not_yet_competent'),
        'competent_rate', private.analytics_rate(count(*) filter (where a.outcome = 'competent'),
          count(*) filter (where a.outcome in ('competent', 'not_yet_competent'))),
        'avg_percent', round(avg(a.percentage) filter (where a.released_at is not null), 1),
        'pending_release', count(*) filter (where a.submitted_at is not null and a.released_at is null))
      from assessments a),
    'quizzes', jsonb_build_object(
      'applicable', private.analytics_source_applicable(v_scope, 'quizzes'),
      'submitted', (select count(*) from quiz_scores),
      'scored', (select count(*) from quiz_scores q where q.scored),
      'pending', (select count(*) from quiz_scores q where not q.scored),
      'avg_percent', (select round(avg(q.percent), 1) from quiz_scores q where q.scored),
      'eligible', (select count(*) from quiz_eligible),
      'completed', (select count(*) from quiz_completed),
      'completion_rate', private.analytics_rate((select count(*) from quiz_completed), (select count(*) from quiz_eligible))),
    'homework', (
      select jsonb_build_object(
        'applicable', private.analytics_source_applicable(v_scope, 'homework'),
        'eligible', count(*) filter (where h.open_in_period),
        'submitted', count(*) filter (where h.submitted_in_period),
        'graded', count(*) filter (where h.submitted_in_period and h.released),
        'missing', count(*) filter (where h.missing),
        'late', count(*) filter (where h.submitted_in_period and h.late),
        'avg_percent', round(avg(h.percent) filter (where h.submitted_in_period), 1),
        'completion_rate', private.analytics_rate(count(*) filter (where h.open_in_period and h.submission_id is not null),
          count(*) filter (where h.open_in_period)))
      from homework h),
    'missions', jsonb_build_object(
      'applicable', private.analytics_source_applicable(v_scope, 'practice'),
      'verified', (select count(*) from completions c where c.in_period),
      'learners_verified', (select count(distinct c.learner_id) from completions c where c.in_period),
      'completion_rate', private.analytics_rate(
        (select count(*) from completions c where c.mission_code in (select mi.mission_code from mission_items mi)),
        (select count(*) from population) * (select count(*) from mission_items)),
      'runs', (select count(*) from runs r where r.in_period),
      'successful_runs', (select count(*) from runs r where r.in_period and r.outcome = 'verified'),
      'failed_runs', (select count(*) from runs r where r.in_period and r.outcome = 'incomplete'),
      'avg_duration_seconds', (select round(avg(r.duration_seconds), 1) from runs r
        where r.in_period and r.outcome = 'verified' and r.duration_seconds is not null)),
    'learning_progress', jsonb_build_object(
      'applicable', private.analytics_source_applicable(v_scope, 'learning') and exists (select 1 from items),
      'avg_percent', (select round(avg(p.percent), 1) from progress p),
      'items_total', (select count(*) from items),
      'definition', 'Completed required items (published topics, server-verified practice missions and the COC practice quiz) divided by all required items in scope, averaged once per learner.'),
    'trend', case when exists (select 1 from events) then (
      select jsonb_agg(jsonb_build_object('date', t.day, 'assessments', t.assessments, 'quizzes', t.quizzes,
        'homework', t.homework, 'practice_runs', t.practice_runs, 'verified', t.verified) order by t.day)
      from (
        select d.day::date as day,
          count(e.kind) filter (where e.kind = 'assessments') as assessments,
          count(e.kind) filter (where e.kind = 'quizzes') as quizzes,
          count(e.kind) filter (where e.kind = 'homework') as homework,
          count(e.kind) filter (where e.kind = 'practice_runs') as practice_runs,
          count(e.kind) filter (where e.kind = 'verified') as verified
        from generate_series((v_from at time zone 'Asia/Manila')::date, (v_to at time zone 'Asia/Manila')::date,
          interval '1 day') d(day)
        left join events e on e.day = d.day::date
        group by d.day
      ) t) else '[]'::jsonb end,
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- Classes tab: comparison of the scoped classes. Class-bound results
-- (assessments, quizzes, homework) are attributed to the class of the
-- attempt/submission; practice and learning progress belong to the learner.
-- ---------------------------------------------------------------------------
create or replace function public.get_class_performance(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope(p_filters);
  v_from timestamptz := (v_scope ->> 'from')::timestamptz;
  v_result jsonb;
begin
  with
  classes as materialized (select * from private.analytics_classes(v_scope)),
  members as materialized (select * from private.analytics_members(v_scope)),
  population as materialized (select distinct m.learner_id from members m),
  activity as materialized (select * from private.analytics_last_activity(v_scope)),
  assessments as materialized (select * from private.analytics_assessment_facts(v_scope)),
  quizzes as materialized (
    select * from private.analytics_quiz_facts(v_scope) q where q.class_in_scope and q.in_period
  ),
  homework as materialized (select * from private.analytics_homework_facts(v_scope)),
  completions as materialized (select * from private.analytics_practice_completions(v_scope)),
  progress as materialized (select * from private.analytics_learner_progress(v_scope)),
  mission_items as materialized (
    select i.mission_code from private.analytics_required_items(v_scope) i where i.item_kind = 'mission'
  ),
  scores as materialized (
    select a.class_id, a.learner_id, a.percentage as pct from assessments a
    where a.released_at is not null and a.percentage is not null
    union all
    select q.class_id, q.learner_id, q.percent from quizzes q where q.scored
    union all
    select h.class_id, h.learner_id, h.percent from homework h where h.percent is not null and h.submitted_in_period
  ),
  class_learner_scores as materialized (
    select s.class_id, s.learner_id, avg(s.pct) as score from scores s group by s.class_id, s.learner_id
  ),
  learner_scores as (select s.learner_id, avg(s.pct) as score from scores s group by s.learner_id),
  class_rows as (
    select c.class_id, c.title, c.class_code,
      (select count(distinct m.learner_id) from members m where m.class_id = c.class_id) as enrolled,
      (select count(*) from activity a where a.last_activity_at >= v_from
        and a.learner_id in (select m.learner_id from members m where m.class_id = c.class_id)) as active,
      (select round(avg(cls.score), 1) from class_learner_scores cls where cls.class_id = c.class_id) as avg_score,
      (select round(avg(q.percent), 1) from quizzes q where q.class_id = c.class_id and q.scored) as quiz_avg,
      (select private.analytics_rate(count(*) filter (where a.outcome = 'competent'),
          count(*) filter (where a.outcome in ('competent', 'not_yet_competent')))
        from assessments a where a.class_id = c.class_id) as competent_rate,
      private.analytics_rate(
        (select count(*) from completions co
          join members m on m.learner_id = co.learner_id and m.class_id = c.class_id
          where co.mission_code in (select mi.mission_code from mission_items mi)),
        (select count(*) from members m where m.class_id = c.class_id) * (select count(*) from mission_items)) as mission_rate,
      (select private.analytics_rate(count(*) filter (where h.submission_id is not null), count(*))
        from homework h where h.class_id = c.class_id and h.open_in_period) as assignment_rate,
      (select round(avg(p.percent), 1) from progress p
        join members m on m.learner_id = p.learner_id and m.class_id = c.class_id) as progress_avg,
      (select jsonb_build_object('learner_id', cls.learner_id, 'name', pr.full_name, 'score', round(cls.score, 1))
        from class_learner_scores cls join public.profiles pr on pr.user_id = cls.learner_id
        where cls.class_id = c.class_id order by cls.score desc, pr.full_name, cls.learner_id limit 1) as highest,
      (select jsonb_build_object('learner_id', cls.learner_id, 'name', pr.full_name, 'score', round(cls.score, 1))
        from class_learner_scores cls join public.profiles pr on pr.user_id = cls.learner_id
        where cls.class_id = c.class_id order by cls.score asc, pr.full_name, cls.learner_id limit 1) as lowest
    from classes c
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_scope ->> 'from', 'to', v_scope ->> 'to'),
    'filters', private.analytics_public_filters(v_scope),
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.class_id, 'title', r.title, 'class_code', r.class_code, 'enrolled', r.enrolled,
        'active_in_period', r.active, 'avg_score', r.avg_score, 'quiz_avg', r.quiz_avg,
        'assessment_competent_rate', r.competent_rate, 'mission_completion_rate', r.mission_rate,
        'assignment_completion_rate', r.assignment_rate, 'progress_avg', r.progress_avg,
        'highest', r.highest, 'lowest', r.lowest) order by r.title)
      from class_rows r), '[]'::jsonb),
    'summary', jsonb_build_object(
      'enrolled', (select count(*) from population),
      'active_in_period', (select count(*) from activity a where a.last_activity_at >= v_from),
      'avg_score', (select round(avg(ls.score), 1) from learner_scores ls),
      'quiz_avg', (select round(avg(q.percent), 1) from quizzes q where q.scored),
      'assessment_competent_rate', (select private.analytics_rate(count(*) filter (where a.outcome = 'competent'),
          count(*) filter (where a.outcome in ('competent', 'not_yet_competent'))) from assessments a),
      'mission_completion_rate', private.analytics_rate(
        (select count(*) from completions co where co.mission_code in (select mi.mission_code from mission_items mi)),
        (select count(*) from population) * (select count(*) from mission_items)),
      'assignment_completion_rate', (select private.analytics_rate(count(*) filter (where h.submission_id is not null), count(*))
        from homework h where h.open_in_period),
      'progress_avg', (select round(avg(p.percent), 1) from progress p)),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- Learners tab: one row per learner with status and reasons.
-- ---------------------------------------------------------------------------
create or replace function public.get_learner_performance(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope(p_filters);
  v_result jsonb;
begin
  with metrics as materialized (select * from private.analytics_learner_metrics(v_scope))
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_scope ->> 'from', 'to', v_scope ->> 'to'),
    'filters', private.analytics_public_filters(v_scope),
    'learners', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.learner_id, 'name', m.name, 'student_id', m.student_id, 'email', m.email, 'classes', m.classes,
        'progress_percent', m.progress_percent, 'completed_items', m.completed_items, 'total_items', m.total_items,
        'performance_score', m.performance_score, 'quiz_avg', m.quiz_avg, 'quizzes_scored', m.quiz_scored,
        'assessment', jsonb_build_object('released', m.assessment_released, 'competent', m.assessment_competent,
          'pending', m.assessment_pending),
        'missions_verified', m.missions_verified, 'practice_runs', m.practice_runs,
        'assignments', jsonb_build_object('submitted', m.homework_submitted, 'missing', m.homework_missing,
          'late', m.homework_late),
        'last_activity_at', m.last_activity_at, 'status', m.status, 'reasons', m.reasons)
        order by case m.status when 'falling_behind' then 0 when 'struggling' then 1 else 2 end, m.name, m.learner_id)
      from metrics m), '[]'::jsonb),
    'thresholds', jsonb_build_object('inactivity_days', 14, 'progress_ratio_of_class_median', 0.5,
      'quiz_average_below', 75, 'incomplete_runs_on_one_mission', 3),
    'counts', jsonb_build_object(
      'on_track', (select count(*) from metrics m where m.status = 'on_track'),
      'struggling', (select count(*) from metrics m where m.status = 'struggling'),
      'falling_behind', (select count(*) from metrics m where m.status = 'falling_behind')),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- Learner profile (instructor/admin view of one learner in scope).
-- ---------------------------------------------------------------------------
create or replace function public.get_learner_profile_analytics(p_learner uuid, p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb;
  v_from timestamptz;
  v_to timestamptz;
  v_result jsonb;
begin
  if p_learner is null then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'A learner is required.';
  end if;
  v_scope := private.analytics_scope((coalesce(p_filters, '{}'::jsonb) - 'learner_id')
    || jsonb_build_object('learner_id', p_learner::text));
  v_from := (v_scope ->> 'from')::timestamptz;
  v_to := (v_scope ->> 'to')::timestamptz;

  with
  members as materialized (select * from private.analytics_members(v_scope)),
  classes as materialized (select * from private.analytics_classes(v_scope)),
  metrics as materialized (select * from private.analytics_learner_metrics(v_scope)),
  items as materialized (select * from private.analytics_learning_items(v_scope)),
  assessments as materialized (select * from private.analytics_assessment_facts(v_scope)),
  quizzes as materialized (
    select q.*, c.title as class_title from private.analytics_quiz_facts(v_scope) q
    left join classes c on c.class_id = q.class_id
    where q.class_in_scope and q.in_period
  ),
  homework as materialized (
    select h.*, c.title as class_title from private.analytics_homework_facts(v_scope) h
    left join classes c on c.class_id = h.class_id
    where h.open_in_period or h.submitted_in_period
  ),
  runs as materialized (select * from private.analytics_practice_runs(v_scope)),
  completions as materialized (select * from private.analytics_practice_completions(v_scope)),
  module_completions as materialized (
    select lmc.module_id, lmc.completed_at from public.learner_module_completions lmc
    where lmc.learner_id = p_learner and lmc.completed_at <= v_to
  ),
  module_rows as (
    select cm.id, cm.coc_code, cm.code, cm.title, cm.sequence_order,
      count(i.item_key) as total, count(i.completed_at) as completed,
      (select mc.completed_at from module_completions mc where mc.module_id = cm.id) as recorded_completed_at,
      coalesce(jsonb_agg(jsonb_build_object('id', i.topic_id, 'title', i.title, 'completed_at', i.completed_at)
        order by i.title) filter (where i.item_kind = 'topic'), '[]'::jsonb) as topics,
      coalesce(jsonb_agg(jsonb_build_object('mission_code', i.mission_code, 'title', i.title, 'verified_at', i.completed_at)
        order by i.mission_code) filter (where i.item_kind = 'mission'), '[]'::jsonb) as missions
    from public.curriculum_modules cm
    left join items i on i.module_id = cm.id
    where private.analytics_source_applicable(v_scope, 'learning')
      and (v_scope ->> 'coc_code' is null or cm.coc_code = v_scope ->> 'coc_code')
      and (v_scope ->> 'module_id' is null or cm.id = (v_scope ->> 'module_id')::uuid)
    group by cm.id, cm.coc_code, cm.code, cm.title, cm.sequence_order
    having (v_scope ->> 'topic_id' is null and v_scope ->> 'mission_code' is null) or count(i.item_key) > 0
  ),
  coc_rows as (
    select c.coc_code, c.title,
      (select count(*) from items i where i.coc_code = c.coc_code) as total,
      (select count(i.completed_at) from items i where i.coc_code = c.coc_code) as completed,
      (select max(i.completed_at) from items i where i.coc_code = c.coc_code and i.item_kind = 'coc_quiz') as quiz_passed_at
    from (select lower(cm.coc_code) as coc_code, cm.title from public.coc_modules cm) c
    where c.coc_code in (select m.coc_code from module_rows m)
       or exists (select 1 from items i where i.coc_code = c.coc_code)
  ),
  timeline as (
    select a.submitted_at as at, 'assessment_submitted'::text as kind, a.mission_title as title,
      jsonb_build_object('status', a.status, 'assignment', a.assignment_title) as detail
    from assessments a where a.submitted_at is not null
    union all
    select a.released_at, 'assessment_released', a.mission_title,
      jsonb_build_object('outcome', a.outcome, 'percent', round(a.percentage, 1))
    from assessments a where a.released_at is not null and a.released_at between v_from and v_to
    union all
    select q.submitted_at, 'quiz_submitted', q.quiz_title,
      jsonb_build_object('percent', round(q.percent, 1), 'scored', q.scored)
    from quizzes q
    union all
    select h.submitted_at, 'homework_submitted', h.title, jsonb_build_object('late', h.late, 'released', h.released)
    from homework h where h.submitted_in_period
    union all
    select r.event_at, 'practice_run', (select ms.title from public.missions ms where ms.mission_code = r.mission_code),
      jsonb_build_object('mission_code', r.mission_code, 'outcome', r.outcome, 'run_number', r.run_number,
        'duration_seconds', r.duration_seconds, 'invalid_actions', r.invalid_count)
    from runs r where r.in_period
    union all
    select c.verified_at, 'mission_verified', (select ms.title from public.missions ms where ms.mission_code = c.mission_code),
      jsonb_build_object('mission_code', c.mission_code)
    from completions c where c.in_period
    union all
    select i.completed_at, case i.item_kind when 'topic' then 'topic_completed' else 'coc_quiz_passed' end, i.title,
      jsonb_build_object('coc_code', i.coc_code)
    from items i where i.item_kind in ('topic', 'coc_quiz') and i.completed_at between v_from and v_to
    union all
    select mc.completed_at, 'module_completed', (select cm.code || ' ' || cm.title from public.curriculum_modules cm where cm.id = mc.module_id),
      jsonb_build_object('module_id', mc.module_id)
    from module_completions mc where mc.completed_at between v_from and v_to
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'filters', private.analytics_public_filters(v_scope),
    'learner', (select jsonb_build_object('id', p.user_id, 'name', p.full_name, 'student_id', p.learner_id,
        'email', p.email, 'account_status', p.status::text)
      from public.profiles p where p.user_id = p_learner),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.class_id, 'title', c.title) order by c.title)
      from classes c where c.class_id in (select m.class_id from members m)), '[]'::jsonb),
    'status', (select jsonb_build_object('status', m.status, 'reasons', m.reasons, 'last_activity_at', m.last_activity_at,
        'progress_percent', m.progress_percent, 'performance_score', m.performance_score, 'quiz_avg', m.quiz_avg,
        'missions_verified', m.missions_verified, 'practice_runs', m.practice_runs,
        'assessment', jsonb_build_object('released', m.assessment_released, 'competent', m.assessment_competent,
          'pending', m.assessment_pending),
        'assignments', jsonb_build_object('submitted', m.homework_submitted, 'missing', m.homework_missing,
          'late', m.homework_late))
      from metrics m limit 1),
    'progress', jsonb_build_object(
      'overall_percent', (select private.analytics_rate(count(i.completed_at), count(*)) from items i),
      'completed_items', (select count(i.completed_at) from items i),
      'total_items', (select count(*) from items i),
      'cocs', coalesce((
        select jsonb_agg(jsonb_build_object(
          'coc_code', c.coc_code, 'title', c.title, 'percent', private.analytics_rate(c.completed, c.total),
          'completed_items', c.completed, 'total_items', c.total, 'coc_quiz_passed_at', c.quiz_passed_at,
          'modules', coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', m.id, 'code', m.code, 'title', m.title, 'sequence_order', m.sequence_order,
              'percent', private.analytics_rate(m.completed, m.total), 'completed_items', m.completed,
              'total_items', m.total,
              'completed_at', coalesce(m.recorded_completed_at,
                case when m.total > 0 and m.completed = m.total then
                  (select max(i.completed_at) from items i where i.module_id = m.id) end),
              'topics', m.topics, 'missions', m.missions) order by m.sequence_order)
            from module_rows m where m.coc_code = c.coc_code), '[]'::jsonb)) order by c.coc_code)
        from coc_rows c), '[]'::jsonb)),
    'quizzes', coalesce((
      select jsonb_agg(jsonb_build_object('quiz_id', q.quiz_id, 'title', q.quiz_title, 'class_title', q.class_title,
        'percent', round(q.percent, 1), 'correct_count', q.correct_count, 'question_count', q.question_count,
        'status', case when q.scored then 'scored' else 'pending' end, 'submitted_at', q.submitted_at)
        order by q.submitted_at desc)
      from quizzes q), '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mission_code', x.mission_code, 'title', ms.title, 'coc_code', left(x.mission_code, 4),
        'module_code', (select cm.code from public.mission_curriculum_links l join public.curriculum_modules cm on cm.id = l.module_id
          where l.mission_code = x.mission_code),
        'verified_at', (select c.verified_at from completions c where c.mission_code = x.mission_code),
        'runs', (select count(*) from runs r where r.mission_code = x.mission_code and r.in_period),
        'successful_runs', (select count(*) from runs r where r.mission_code = x.mission_code and r.in_period and r.outcome = 'verified'),
        'failed_runs', (select count(*) from runs r where r.mission_code = x.mission_code and r.in_period and r.outcome = 'incomplete'),
        'best_duration_seconds', (select min(r.duration_seconds) from runs r
          where r.mission_code = x.mission_code and r.outcome = 'verified'),
        'avg_invalid_actions', (select round(avg(r.invalid_count), 1) from runs r where r.mission_code = x.mission_code and r.in_period),
        'last_run_at', (select max(r.event_at) from runs r where r.mission_code = x.mission_code),
        'recent_runs', coalesce((
          select jsonb_agg(jsonb_build_object('run_number', rr.run_number, 'outcome', rr.outcome,
            'duration_seconds', rr.duration_seconds, 'invalid_count', rr.invalid_count,
            'correction_count', rr.correction_count, 'ended_at', rr.event_at) order by rr.event_at desc)
          from (select r.* from runs r where r.mission_code = x.mission_code and r.in_period
            order by r.event_at desc limit 5) rr), '[]'::jsonb))
        order by x.mission_code)
      from (select r.mission_code from runs r union select c.mission_code from completions c) x
      left join public.missions ms on ms.mission_code = x.mission_code), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object('homework_id', h.homework_id, 'title', h.title, 'class_title', h.class_title,
        'deadline_at', h.deadline_at, 'submitted_at', h.submitted_at, 'late', h.late,
        'status', case
          when h.submission_id is not null and h.released then 'graded'
          when h.submission_id is not null then 'submitted'
          when h.missing then 'missing'
          else 'open' end,
        'score', h.score, 'max_score', h.max_score) order by h.deadline_at nulls last, h.title)
      from homework h), '[]'::jsonb),
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object('attempt_id', a.attempt_id, 'mission_code', a.mission_code,
        'title', a.mission_title, 'assignment_title', a.assignment_title,
        'class_title', (select c.title from classes c where c.class_id = a.class_id),
        'status', a.status, 'submitted_at', a.submitted_at, 'released_at', a.released_at,
        'percent', round(a.percentage, 1), 'outcome', a.outcome,
        'criteria', case when a.released_at is null then '[]'::jsonb else coalesce((
          select jsonb_agg(jsonb_build_object('criterion_id', rc.id, 'code', rc.criterion_code, 'title', rc.title,
            'observation', cv ->> 'observation', 'score', nullif(cv ->> 'score_value', '')::numeric,
            'max', rc.max_value) order by rc.order_index)
          from public.score_revisions sr
          cross join lateral jsonb_array_elements(case when jsonb_typeof(sr.criterion_values) = 'array'
            then sr.criterion_values else '[]'::jsonb end) cv
          join public.rubric_criteria rc on rc.id = (cv ->> 'criterion_id')::uuid
          where sr.id = a.score_revision_id and cv ? 'criterion_id'), '[]'::jsonb) end)
        order by coalesce(a.released_at, a.submitted_at, a.started_at) desc)
      from assessments a), '[]'::jsonb),
    'timeline', coalesce((
      select jsonb_agg(jsonb_build_object('at', t.at, 'kind', t.kind, 'title', t.title, 'detail', t.detail)
        order by t.at desc)
      from (select * from timeline tl where tl.at is not null order by tl.at desc limit 100) t), '[]'::jsonb),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- Quizzes tab: summary list (ignores the quiz selection) + one quiz detail.
-- ---------------------------------------------------------------------------
create or replace function public.get_quiz_analytics(p_quiz_id uuid, p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope(p_filters);
  v_quiz uuid := coalesce(p_quiz_id, (v_scope ->> 'quiz_id')::uuid);
  v_list_scope jsonb;
  v_detail_scope jsonb;
  v_list jsonb;
  v_detail jsonb;
begin
  if v_quiz is not null and not exists (select 1 from public.quizzes q where q.id = v_quiz) then
    raise exception 'ANALYTICS_SCOPE_DENIED' using errcode = '42501';
  end if;
  v_list_scope := jsonb_set(v_scope, '{quiz_id}', 'null'::jsonb);

  with
  facts as materialized (select * from private.analytics_quiz_facts(v_list_scope)),
  eligible as materialized (
    select distinct e.learner_id, e.quiz_id from private.analytics_quiz_eligibility(v_list_scope) e
  ),
  quiz_ids as (
    select f.quiz_id from facts f where f.class_in_scope and f.in_period
    union
    select e.quiz_id from eligible e
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', q.id, 'title', q.title, 'coc_code', lower(coc.coc_code), 'status', private.analytics_quiz_status(q.id),
    'participants', (select count(*) from facts f where f.quiz_id = q.id and f.class_in_scope and f.in_period),
    'pending', (select count(*) from facts f where f.quiz_id = q.id and f.class_in_scope and f.in_period and not f.scored),
    'eligible', (select count(*) from eligible e where e.quiz_id = q.id),
    'completion_rate', private.analytics_rate(
      (select count(*) from eligible e where e.quiz_id = q.id
        and exists (select 1 from facts f where f.learner_id = e.learner_id and f.quiz_id = e.quiz_id)),
      (select count(*) from eligible e where e.quiz_id = q.id)),
    'average', (select round(avg(f.percent), 1) from facts f where f.quiz_id = q.id and f.class_in_scope and f.in_period and f.scored),
    'highest', (select round(max(f.percent), 1) from facts f where f.quiz_id = q.id and f.class_in_scope and f.in_period and f.scored),
    'lowest', (select round(min(f.percent), 1) from facts f where f.quiz_id = q.id and f.class_in_scope and f.in_period and f.scored))
    order by q.title, q.id), '[]'::jsonb)
  into v_list
  from public.quizzes q
  left join public.coc_modules coc on coc.id = q.coc_module_id
  where q.id in (select qi.quiz_id from quiz_ids qi);

  if v_quiz is not null then
    v_detail_scope := jsonb_set(v_scope, '{quiz_id}', to_jsonb(v_quiz::text));
    with
    classes as materialized (select * from private.analytics_classes(v_detail_scope)),
    facts as materialized (select * from private.analytics_quiz_facts(v_detail_scope)),
    counted as materialized (select * from facts f where f.class_in_scope and f.in_period),
    scored as materialized (select * from counted c where c.scored),
    eligible as materialized (
      select e.learner_id, min(e.class_id::text)::uuid as class_id
      from private.analytics_quiz_eligibility(v_detail_scope) e group by e.learner_id
    ),
    learners as (select c.learner_id from counted c union select e.learner_id from eligible e),
    result_rows as (
      select l.learner_id, p.full_name, p.learner_id as student_id,
        coalesce(c.class_id, e.class_id) as class_id, c.correct_count, c.question_count, c.percent, c.submitted_at,
        case
          when c.attempt_id is not null and c.scored then 'scored'
          when c.attempt_id is not null then 'pending'
          when exists (select 1 from facts f where f.learner_id = l.learner_id) then 'other_class'
          else 'not_submitted'
        end as status
      from learners l
      join public.profiles p on p.user_id = l.learner_id
      left join counted c on c.learner_id = l.learner_id
      left join eligible e on e.learner_id = l.learner_id
    ),
    items as (
      select qi.id, qi.item_code, qi.prompt, qi.item_type::text as item_type, qv.version_number, qi.order_index,
        (select count(*) from public.quiz_answers ans
          where ans.quiz_item_id = qi.id and ans.quiz_attempt_id in (select s.attempt_id from scored s)) as answered,
        (select count(*) from public.quiz_answers ans
          where ans.quiz_item_id = qi.id and ans.is_correct
            and ans.quiz_attempt_id in (select s.attempt_id from scored s)) as correct
      from public.quiz_items qi
      join public.quiz_versions qv on qv.id = qi.quiz_version_id
      where qi.quiz_version_id in (select distinct s.quiz_version_id from scored s)
        and qi.removed_at is null
        and qi.review_status = 'approved'::public.quiz_item_review_status
    )
    select jsonb_build_object(
      'quiz', (select jsonb_build_object('id', q.id, 'title', q.title, 'coc_code', lower(coc.coc_code),
          'status', private.analytics_quiz_status(q.id),
          'question_count', (select count(*) from public.quiz_items qi
            where qi.quiz_version_id = (select v.id from public.quiz_versions v where v.quiz_id = q.id
              order by (v.status = 'published'::public.content_version_status) desc, v.version_number desc limit 1)
              and qi.removed_at is null and qi.review_status = 'approved'::public.quiz_item_review_status))
        from public.quizzes q left join public.coc_modules coc on coc.id = q.coc_module_id where q.id = v_quiz),
      'participants', (select count(*) from counted),
      'pending', (select count(*) from counted c where not c.scored),
      'eligible', (select count(*) from eligible),
      'completed', (select count(*) from eligible e where exists (select 1 from facts f where f.learner_id = e.learner_id)),
      'completion_rate', private.analytics_rate(
        (select count(*) from eligible e where exists (select 1 from facts f where f.learner_id = e.learner_id)),
        (select count(*) from eligible)),
      'average', (select round(avg(s.percent), 1) from scored s),
      'highest', (select round(max(s.percent), 1) from scored s),
      'lowest', (select round(min(s.percent), 1) from scored s),
      'distribution', case when exists (select 1 from scored) then (
        select jsonb_agg(jsonb_build_object(
          'bucket', case when b.i = 9 then '90-100' else (b.i * 10)::text || '-' || (b.i * 10 + 9)::text end,
          'min', b.i * 10, 'max', case when b.i = 9 then 100 else b.i * 10 + 9 end,
          'count', (select count(*) from scored s where least(floor(s.percent / 10), 9) = b.i)) order by b.i)
        from generate_series(0, 9) b(i)) else '[]'::jsonb end,
      'per_question', coalesce((
        select jsonb_agg(jsonb_build_object('item_id', it.id, 'code', it.item_code, 'prompt', it.prompt,
          'type', it.item_type, 'version_number', it.version_number, 'answered', it.answered, 'correct', it.correct,
          'correct_rate', private.analytics_rate(it.correct, it.answered)) order by it.version_number, it.order_index)
        from items it), '[]'::jsonb),
      'results', coalesce((
        select jsonb_agg(jsonb_build_object('learner_id', r.learner_id, 'name', r.full_name, 'student_id', r.student_id,
          'class_id', r.class_id, 'class_title', (select c.title from classes c where c.class_id = r.class_id),
          'score', r.correct_count, 'max_score', r.question_count, 'percent', round(r.percent, 1),
          'status', r.status, 'submitted_at', r.submitted_at)
          order by r.percent desc nulls last, r.full_name, r.learner_id)
        from result_rows r), '[]'::jsonb)
    ) into v_detail;
  end if;

  return jsonb_build_object(
    'period', jsonb_build_object('from', v_scope ->> 'from', 'to', v_scope ->> 'to'),
    'filters', private.analytics_public_filters(v_scope),
    'quizzes', v_list,
    'quiz', v_detail -> 'quiz',
    'participants', coalesce((v_detail ->> 'participants')::integer, 0),
    'pending', coalesce((v_detail ->> 'pending')::integer, 0),
    'eligible', coalesce((v_detail ->> 'eligible')::integer, 0),
    'completed', coalesce((v_detail ->> 'completed')::integer, 0),
    'completion_rate', v_detail -> 'completion_rate',
    'average', v_detail -> 'average',
    'highest', v_detail -> 'highest',
    'lowest', v_detail -> 'lowest',
    'distribution', coalesce(v_detail -> 'distribution', '[]'::jsonb),
    'per_question', coalesce(v_detail -> 'per_question', '[]'::jsonb),
    'results', coalesce(v_detail -> 'results', '[]'::jsonb),
    'generated_at', now()
  );
end
$$;

-- ---------------------------------------------------------------------------
-- Missions tab: practice (recorded runs + verified completions) and technical
-- assessment attempts, labelled separately. Attempt counts come from recorded
-- runs/attempts, never from completion counts.
-- ---------------------------------------------------------------------------
create or replace function public.get_mission_analytics(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope(p_filters);
  v_result jsonb;
begin
  with
  population as materialized (select distinct m.learner_id from private.analytics_members(v_scope) m),
  runs as materialized (select * from private.analytics_practice_runs(v_scope)),
  completions as materialized (select * from private.analytics_practice_completions(v_scope)),
  assessments as materialized (select * from private.analytics_assessment_facts(v_scope)),
  mission_codes as (select r.mission_code from runs r union select c.mission_code from completions c),
  mission_rows as (
    select ms.mission_code, ms.title, ms.mission_number, lower(coc.coc_code) as coc_code,
      cm.id as module_id, cm.code as module_code, cm.title as module_title,
      (select count(*) from population) as in_scope,
      (select count(distinct x.learner_id) from (
        select r.learner_id from runs r where r.mission_code = ms.mission_code
        union select c.learner_id from completions c where c.mission_code = ms.mission_code) x) as attempted,
      (select count(*) from completions c where c.mission_code = ms.mission_code) as verified,
      (select count(*) from runs r where r.mission_code = ms.mission_code and r.in_period) as run_count,
      (select count(*) from runs r where r.mission_code = ms.mission_code and r.in_period and r.outcome = 'verified') as successful,
      (select count(*) from runs r where r.mission_code = ms.mission_code and r.in_period and r.outcome = 'incomplete') as failed,
      (select count(distinct r.learner_id) from runs r where r.mission_code = ms.mission_code and r.in_period) as runners,
      (select avg(r.duration_seconds) from runs r where r.mission_code = ms.mission_code and r.in_period
        and r.outcome = 'verified' and r.duration_seconds is not null) as avg_duration,
      (select avg(r.invalid_count) from runs r where r.mission_code = ms.mission_code and r.in_period) as avg_invalid
    from public.missions ms
    join public.coc_modules coc on coc.id = ms.coc_id
    left join public.mission_curriculum_links l on l.mission_code = ms.mission_code
    left join public.curriculum_modules cm on cm.id = l.module_id
    where ms.mission_code in (select mc.mission_code from mission_codes mc)
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_scope ->> 'from', 'to', v_scope ->> 'to'),
    'filters', private.analytics_public_filters(v_scope),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mission_code', m.mission_code, 'title', m.title, 'coc_code', m.coc_code,
        'module', case when m.module_id is null then null
          else jsonb_build_object('id', m.module_id, 'code', m.module_code, 'title', m.module_title) end,
        'learners_in_scope', m.in_scope, 'learners_attempted', m.attempted, 'learners_verified', m.verified,
        'completion_rate', private.analytics_rate(m.verified, m.in_scope),
        'runs', m.run_count, 'successful_runs', m.successful, 'failed_runs', m.failed,
        'avg_runs_per_learner', case when m.runners > 0 then round(m.run_count::numeric / m.runners, 1) end,
        'avg_duration_seconds', round(m.avg_duration, 1),
        'avg_invalid_actions', round(m.avg_invalid, 1)) order by m.coc_code, m.mission_number)
      from mission_rows m), '[]'::jsonb),
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mission_code', x.mission_code, 'title', x.mission_title, 'coc_code', x.coc_code,
        'attempts', x.attempts, 'submitted', x.submitted, 'released', x.released, 'competent', x.competent,
        'not_yet_competent', x.nyc, 'pending', x.pending, 'avg_percent', x.avg_percent) order by x.mission_code)
      from (
        select a.mission_code, min(a.mission_title) as mission_title, min(a.coc_code) as coc_code,
          count(*) as attempts,
          count(*) filter (where a.submitted_at is not null) as submitted,
          count(*) filter (where a.released_at is not null) as released,
          count(*) filter (where a.outcome = 'competent') as competent,
          count(*) filter (where a.outcome = 'not_yet_competent') as nyc,
          count(*) filter (where a.submitted_at is not null and a.released_at is null) as pending,
          round(avg(a.percentage) filter (where a.released_at is not null), 1) as avg_percent
        from assessments a
        group by a.mission_code
      ) x), '[]'::jsonb),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- Criteria tab: assessment rubric criteria from released results. The released
-- score revision's criterion values are authoritative (instructor adjustments
-- included); criterion_results are the fallback for legacy revisions. Each
-- learner counts once per criterion (latest released result).
-- ---------------------------------------------------------------------------
create or replace function public.get_criteria_analytics(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_scope jsonb := private.analytics_scope(p_filters);
  v_result jsonb;
begin
  with
  released as materialized (
    select * from private.analytics_assessment_facts(v_scope) a where a.released_at is not null
  ),
  revision_values as (
    select a.learner_id, a.attempt_id, a.released_at, a.mission_code, a.mission_title,
      (cv ->> 'criterion_id')::uuid as criterion_id, cv ->> 'observation' as observation,
      nullif(cv ->> 'score_value', '')::numeric as score_value
    from released a
    join public.score_revisions sr on sr.id = a.score_revision_id
    cross join lateral jsonb_array_elements(case when jsonb_typeof(sr.criterion_values) = 'array'
      then sr.criterion_values else '[]'::jsonb end) cv
    where cv ? 'criterion_id'
  ),
  fallback_values as (
    select distinct on (cr.attempt_id, cr.rubric_criterion_id)
      a.learner_id, a.attempt_id, a.released_at, a.mission_code, a.mission_title,
      cr.rubric_criterion_id as criterion_id, cr.observation::text as observation, cr.score_value
    from released a
    join public.criterion_results cr on cr.attempt_id = a.attempt_id
    where not exists (select 1 from revision_values rv where rv.attempt_id = a.attempt_id)
    order by cr.attempt_id, cr.rubric_criterion_id, cr.evaluated_at desc, cr.id desc
  ),
  latest as (
    select distinct on (v.learner_id, v.criterion_id) v.*
    from (select * from revision_values union all select * from fallback_values) v
    order by v.learner_id, v.criterion_id, v.released_at desc, v.attempt_id desc
  ),
  per_criterion as (
    select l.criterion_id, rc.criterion_code, rc.title, rc.max_value, rc.order_index,
      min(l.mission_code) as mission_code, min(l.mission_title) as mission_title,
      count(distinct l.learner_id) as learners, avg(l.score_value) as avg_score,
      count(*) filter (where l.observation = 'satisfied') as satisfied,
      count(*) filter (where l.observation is distinct from 'satisfied') as not_satisfied
    from latest l
    join public.rubric_criteria rc on rc.id = l.criterion_id
    group by l.criterion_id, rc.criterion_code, rc.title, rc.max_value, rc.order_index
  ),
  scored as (
    select pc.*, coalesce(
      case when pc.max_value > 0 and pc.avg_score is not null then round(pc.avg_score * 100 / pc.max_value, 1) end,
      private.analytics_rate(pc.satisfied, pc.satisfied + pc.not_satisfied)) as percent
    from per_criterion pc
  ),
  ranked as (
    select s.*,
      row_number() over (order by s.percent desc, s.learners desc, s.criterion_code) as best_rank,
      row_number() over (order by s.percent asc, s.learners desc, s.criterion_code) as worst_rank,
      count(*) over () as n
    from scored s where s.percent is not null
  ),
  shaped as (
    select r.*, jsonb_build_object('source', 'assessment', 'criterion_id', r.criterion_id, 'code', r.criterion_code,
      'title', r.title, 'mission_code', r.mission_code, 'mission_title', r.mission_title, 'max', r.max_value,
      'avg', round(r.avg_score, 2), 'percent', r.percent, 'evaluated_learners', r.learners,
      'satisfied', r.satisfied, 'not_satisfied', r.not_satisfied) as item,
      least(3, ceil(r.n / 2.0))::integer as strong_count
    from ranked r
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_scope ->> 'from', 'to', v_scope ->> 'to'),
    'filters', private.analytics_public_filters(v_scope),
    'criteria', coalesce((select jsonb_agg(s.item order by s.mission_code, s.order_index, s.criterion_code) from shaped s), '[]'::jsonb),
    'strongest', coalesce((select jsonb_agg(s.item order by s.best_rank) from shaped s
      where s.best_rank <= s.strong_count), '[]'::jsonb),
    'weakest', coalesce((select jsonb_agg(s.item order by s.worst_rank) from shaped s
      where s.worst_rank <= least(3, s.n - s.strong_count)), '[]'::jsonb),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.get_analytics_filter_options()',
    'public.get_analytics_overview(jsonb)',
    'public.get_class_performance(jsonb)',
    'public.get_learner_performance(jsonb)',
    'public.get_learner_profile_analytics(uuid, jsonb)',
    'public.get_quiz_analytics(uuid, jsonb)',
    'public.get_mission_analytics(jsonb)',
    'public.get_criteria_analytics(jsonb)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated, service_role', v_signature);
  end loop;
end
$$;

comment on function public.get_analytics_overview(jsonb) is
  'Objective 6 overview: population, assessments, quizzes, homework, practice missions and learning progress for the caller''s RLS scope (SECURITY INVOKER).';
comment on function public.get_learner_performance(jsonb) is
  'Objective 6 learner list with documented on_track / struggling / falling_behind rules (SECURITY INVOKER).';

commit;
