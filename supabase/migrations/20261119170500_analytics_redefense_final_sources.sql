-- Slice A7, final integration round (all seven slices merged).
--   * Quizzes (A3): an instructor-release quiz counts only once its result is
--     released and is scored from quiz_result_finalizations; pending,
--     evaluated and finalized attempts are pending evaluation and never enter
--     an average. Immediate quizzes keep quiz_results (points when recorded,
--     otherwise correct answers). Quizzes are positioned by quiz_modules and
--     topic_id. Essay rubric criteria join the criteria analytics from the
--     current essay score (latest per attempt and item: evaluated_at desc,
--     sequence desc).
--   * Simulation (A1): simulation_condition rubric criteria are reported as
--     simulation steps with their step titles; mission analytics aggregate
--     practice_mission_runs.step_results (most-missed steps, incorrect
--     attempts per step); recent runs in the learner profile list the steps
--     that were missed.
--   * Gamification (A6): points and level ("Engagement") in the learner list
--     and profile, reported apart from competency and scores.
--   * Review Minor 4: the per-quiz title wrapper is removed. Learners cannot
--     read quiz titles under RLS (a learner policy on quizzes would recurse
--     through the quiz_versions staff policy), so get_my_performance returns
--     no title and the app reads titles in one call from its quiz list.
-- Additive: analytics functions plus one titles-only generated column; no data
-- is written and no SECURITY DEFINER function is added.
-- Definitions: docs/ANALYTICS_METRIC_DEFINITIONS.md.
begin;

-- ---------------------------------------------------------------------------
-- 1. Practice step titles (A1). Contract definitions hold the answer keys and
--    stay unreadable for clients; this column holds only each step's phase
--    id, number and title (the review phase is not a step).
-- ---------------------------------------------------------------------------
create function private.analytics_contract_steps(p_definition jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.value ->> 'id', 'step', p.step, 'title', p.value ->> 'title')
    order by p.step), '[]'::jsonb)
  from (
    select x.value, (row_number() over (order by x.ordinality))::integer as step
    from jsonb_array_elements(case when jsonb_typeof(p_definition -> 'phases') = 'array'
      then p_definition -> 'phases' else '[]'::jsonb end) with ordinality x(value, ordinality)
    where x.value ->> 'primaryInteraction' is distinct from 'review'
  ) p
$$;

alter table public.practice_mission_contracts
  add column step_titles jsonb generated always as (private.analytics_contract_steps(definition)) stored;
comment on column public.practice_mission_contracts.step_titles is
  'Titles-only projection of the contract phases, review phase excluded: [{id, step, title}]. Readable by active users; the definition (answer keys) is not.';
grant select (step_titles) on public.practice_mission_contracts to authenticated;

-- Phase ids of a simulation_condition rule, with their step numbers and titles.
create function private.analytics_criterion_steps(p_mission text, p_rule jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case when p_rule ->> 'operator' = 'simulation_condition' and jsonb_typeof(p_rule -> 'phase_ids') = 'array' then
    coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', ph.value #>> '{}',
          'step', coalesce((t.value ->> 'step')::integer,
            nullif(substring(ph.value #>> '{}' from '_p([0-9]+)$'), '')::integer),
          'title', coalesce(t.value ->> 'title', ph.value #>> '{}'))
        order by ph.ordinality)
      from jsonb_array_elements(p_rule -> 'phase_ids') with ordinality ph(value, ordinality)
      left join lateral (
        select x.value
        from public.practice_mission_contracts c
        cross join lateral jsonb_array_elements(coalesce(c.step_titles, '[]'::jsonb)) x
        where c.mission_id = p_mission and x.value ->> 'id' = ph.value #>> '{}'
        limit 1
      ) t on true), '[]'::jsonb)
  else '[]'::jsonb end
$$;

-- One row per recorded practice run and step (practice_mission_runs.step_results).
-- Incorrect attempts = invalid actions + failed checks recorded for the step.
create function private.analytics_run_steps(p_scope jsonb)
returns table (
  run_id uuid,
  learner_id uuid,
  mission_code text,
  outcome text,
  in_period boolean,
  phase_id text,
  step integer,
  title text,
  done boolean,
  incorrect integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.run_id, r.learner_id, r.mission_code, r.outcome, r.in_period, s.key,
    coalesce((t.value ->> 'step')::integer, nullif(substring(s.key from '_p([0-9]+)$'), '')::integer),
    coalesce(t.value ->> 'title', s.key),
    coalesce((s.value ->> 'done')::boolean, false),
    coalesce((s.value ->> 'invalid')::integer, 0) + coalesce((s.value ->> 'failed_checks')::integer, 0)
  from private.analytics_practice_runs(p_scope) r
  join public.practice_mission_runs pr on pr.id = r.run_id
  cross join lateral jsonb_each(case when jsonb_typeof(pr.step_results) = 'object'
    then pr.step_results else '{}'::jsonb end) s
  left join lateral (
    select x.value
    from public.practice_mission_contracts c
    cross join lateral jsonb_array_elements(coalesce(c.step_titles, '[]'::jsonb)) x
    where c.mission_id = r.mission_code and x.value ->> 'id' = s.key
    limit 1
  ) t on true
  where jsonb_typeof(s.value) = 'object'
$$;

-- ---------------------------------------------------------------------------
-- 2. Quizzes (A3)
-- ---------------------------------------------------------------------------
create or replace function private.analytics_source_applicable(p_scope jsonb, p_source text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_source
    when 'assessments' then p_scope ->> 'topic_id' is null and p_scope ->> 'quiz_id' is null
    when 'practice' then p_scope ->> 'topic_id' is null and p_scope ->> 'quiz_id' is null
    when 'quizzes' then p_scope ->> 'mission_code' is null
    when 'homework' then p_scope ->> 'topic_id' is null and p_scope ->> 'quiz_id' is null
    when 'learning' then p_scope ->> 'quiz_id' is null
    else false
  end
$$;

-- A quiz sits at its COC, at every module in quiz_modules (no rows = the whole
-- COC, so it matches no module filter) and at its topic; never at a mission.
create function private.analytics_quiz_matches(p_scope jsonb, p_coc text, p_quiz uuid, p_topic uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (p_scope ->> 'coc_code' is null or p_scope ->> 'coc_code' = p_coc)
    and (p_scope ->> 'module_id' is null or exists (
      select 1 from public.quiz_modules qm
      where qm.quiz_id = p_quiz and qm.module_id = (p_scope ->> 'module_id')::uuid))
    and (p_scope ->> 'topic_id' is null or (p_scope ->> 'topic_id')::uuid = p_topic)
    and p_scope ->> 'mission_code' is null
    and (p_scope ->> 'quiz_id' is null or (p_scope ->> 'quiz_id')::uuid = p_quiz),
    false)
$$;

-- Evaluate -> Finalize -> Release -> Released, as in public.get_evaluation_queue
-- and public.quiz_evaluation_queue_items (quizzes: pending, evaluated, finalized).
create or replace function private.analytics_evaluation_stage(p_kind text, p_status text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_kind
    when 'technical' then case p_status
      when 'submitted' then 'evaluate' when 'evaluated' then 'evaluate'
      when 'under_review' then 'finalize' when 'finalized' then 'release' when 'released' then 'released' end
    when 'homework' then case p_status
      when 'submitted' then 'evaluate' when 'graded' then 'finalize'
      when 'finalized' then 'release' when 'released' then 'released' end
    when 'quiz' then case p_status
      when 'pending' then 'evaluate' when 'evaluated' then 'finalize'
      when 'finalized' then 'release' when 'released' then 'released' end
  end
$$;

-- Quiz facts: one submitted attempt per learner and quiz.
--   immediate (evaluation_status not_required): scored from quiz_results,
--     points when recorded (objective_points / max_points), otherwise
--     correct answers / questions;
--   instructor_release: scored only once released, from the finalization
--     (percent, total_points, max_points); pending, evaluated and finalized
--     attempts are pending evaluation (scored = false, no percent).
drop function if exists private.analytics_quiz_facts(jsonb);
create function private.analytics_quiz_facts(p_scope jsonb)
returns table (
  attempt_id uuid,
  learner_id uuid,
  class_id uuid,
  quiz_assignment_id uuid,
  quiz_id uuid,
  quiz_version_id uuid,
  quiz_title text,
  coc_code text,
  status text,
  submitted_at timestamptz,
  scored boolean,
  correct_count integer,
  question_count integer,
  percent numeric,
  class_in_scope boolean,
  in_period boolean,
  release_mode text,
  evaluation_status text,
  stage text,
  score numeric,
  max_score numeric,
  released_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  with
  population as (select distinct mb.learner_id from private.analytics_members(p_scope) mb),
  owned as (select oc.class_id from private.analytics_classes(p_scope - 'class_id') oc),
  scoped as (select sc.class_id from private.analytics_classes(p_scope) sc),
  candidates as (
    select distinct on (qa.learner_id, q.id)
      qa.id, qa.learner_id, qa.class_id, qa.quiz_assignment_id, q.id as quiz_id, qa.quiz_version_id,
      q.title, lower(coc.coc_code) as coc_code, qa.status::text as status, qa.submitted_at,
      qv.result_release_mode, qa.evaluation_status,
      qr.quiz_attempt_id is not null as has_result, qr.correct_count, qr.question_count,
      qr.objective_points, qr.max_points as result_max,
      f.percent as final_percent, f.total_points as final_total, f.max_points as final_max, f.released_at
    from public.quiz_attempts qa
    join population p on p.learner_id = qa.learner_id
    join owned o on o.class_id = qa.class_id
    join public.quiz_versions qv on qv.id = qa.quiz_version_id
    join public.quizzes q on q.id = qv.quiz_id
    left join public.coc_modules coc on coc.id = q.coc_module_id
    left join public.quiz_results qr on qr.quiz_attempt_id = qa.id
    left join public.quiz_result_finalizations f on f.attempt_id = qa.id
    where qa.status in ('submitted'::public.quiz_attempt_status, 'completed'::public.quiz_attempt_status)
      and qa.submitted_at is not null
      and qa.submitted_at <= (p_scope ->> 'to')::timestamptz
      and qv.published_at is not null
      and qv.status in ('published'::public.content_version_status, 'retired'::public.content_version_status)
      and private.analytics_source_applicable(p_scope, 'quizzes')
      and private.analytics_quiz_matches(p_scope, lower(coc.coc_code), q.id, q.topic_id)
    order by qa.learner_id, q.id, qa.submitted_at, qa.id
  ),
  shaped as (
    select c.*,
      case
        when c.evaluation_status = 'not_required' then c.has_result
        when c.evaluation_status = 'released' then c.released_at is not null and c.final_percent is not null
        else false
      end as is_scored
    from candidates c
  )
  select s.id, s.learner_id, s.class_id, s.quiz_assignment_id, s.quiz_id, s.quiz_version_id, s.title, s.coc_code,
    s.status, s.submitted_at, s.is_scored, s.correct_count, s.question_count,
    case
      when not s.is_scored then null
      when s.evaluation_status = 'released' then s.final_percent
      when s.objective_points is not null and s.result_max > 0 then round(s.objective_points * 100 / s.result_max, 4)
      when s.question_count > 0 then round(s.correct_count::numeric * 100 / s.question_count, 4)
    end,
    exists (select 1 from scoped x where x.class_id = s.class_id),
    s.submitted_at >= (p_scope ->> 'from')::timestamptz,
    s.result_release_mode, s.evaluation_status,
    private.analytics_evaluation_stage('quiz', s.evaluation_status),
    case
      when not s.is_scored then null
      when s.evaluation_status = 'released' then s.final_total
      else coalesce(s.objective_points, s.correct_count)
    end,
    case
      when not s.is_scored then null
      when s.evaluation_status = 'released' then s.final_max
      else coalesce(s.result_max, s.question_count)
    end,
    s.released_at
  from shaped s
$$;

create or replace function private.analytics_quiz_eligibility(p_scope jsonb)
returns table (learner_id uuid, class_id uuid, quiz_id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct mb.learner_id, mb.class_id, q.id
  from public.quiz_assignments qa
  join private.analytics_members(p_scope) mb on mb.class_id = qa.class_id
  join public.quiz_versions qv on qv.id = qa.quiz_version_id
  join public.quizzes q on q.id = qv.quiz_id
  left join public.coc_modules coc on coc.id = q.coc_module_id
  where qv.published_at is not null
    and qv.status in ('published'::public.content_version_status, 'retired'::public.content_version_status)
    and coalesce(qa.available_at, qa.created_at) <= (p_scope ->> 'to')::timestamptz
    and coalesce(least(qa.due_at, qa.closed_at), 'infinity'::timestamptz) >= (p_scope ->> 'from')::timestamptz
    and mb.enrolled_at <= coalesce(least(qa.due_at, qa.closed_at), 'infinity'::timestamptz)
    and private.analytics_source_applicable(p_scope, 'quizzes')
    and private.analytics_quiz_matches(p_scope, lower(coc.coc_code), q.id, q.topic_id)
$$;

-- ---------------------------------------------------------------------------
-- 3. Engagement (A6): points to the period end, points in the period and the
--    level from public.gamification_level_for_points. Never mixed into scores.
-- ---------------------------------------------------------------------------
create function private.analytics_engagement_json(p_points integer, p_points_in_period integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'points', coalesce(p_points, 0),
    'points_in_period', coalesce(p_points_in_period, 0),
    'level', (l.value ->> 'level')::integer,
    'level_title', l.value ->> 'title',
    'next_level_points', (l.value ->> 'next_min_points')::integer,
    'level_progress_percent', (l.value ->> 'progress_percent')::integer)
  from (select public.gamification_level_for_points(coalesce(p_points, 0)) as value) l
$$;

-- ---------------------------------------------------------------------------
-- 4. Staff functions
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
  stages as materialized (
    select 'technical'::text as kind, private.analytics_evaluation_stage('technical', a.status) as stage
    from assessments a where a.submitted_at is not null
    union all
    select 'homework', h.stage from homework h where h.submitted_in_period
    union all
    select 'quiz', q.stage from quiz_scores q where q.stage is not null
  ),
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
        'released', count(*) filter (where h.submitted_in_period and h.released),
        'pending_evaluation', count(*) filter (where h.submitted_in_period and not h.released),
        'missing', count(*) filter (where h.missing),
        'late', count(*) filter (where h.submitted_in_period and h.late),
        'avg_percent', round(avg(h.percent) filter (where h.submitted_in_period), 1),
        'completion_rate', private.analytics_rate(count(*) filter (where h.open_in_period and h.submission_id is not null),
          count(*) filter (where h.open_in_period)))
      from homework h),
    'evaluation', jsonb_build_object(
      'technical', (select jsonb_build_object(
          'evaluate', count(*) filter (where s.stage = 'evaluate'), 'finalize', count(*) filter (where s.stage = 'finalize'),
          'release', count(*) filter (where s.stage = 'release'), 'released', count(*) filter (where s.stage = 'released'))
        from stages s where s.kind = 'technical'),
      'homework', (select jsonb_build_object(
          'evaluate', count(*) filter (where s.stage = 'evaluate'), 'finalize', count(*) filter (where s.stage = 'finalize'),
          'release', count(*) filter (where s.stage = 'release'), 'released', count(*) filter (where s.stage = 'released'))
        from stages s where s.kind = 'homework'),
      'quiz', (select jsonb_build_object(
          'evaluate', count(*) filter (where s.stage = 'evaluate'), 'finalize', count(*) filter (where s.stage = 'finalize'),
          'release', count(*) filter (where s.stage = 'release'), 'released', count(*) filter (where s.stage = 'released'))
        from stages s where s.kind = 'quiz'),
      'total', (select jsonb_build_object(
          'evaluate', count(*) filter (where s.stage = 'evaluate'), 'finalize', count(*) filter (where s.stage = 'finalize'),
          'release', count(*) filter (where s.stage = 'release'), 'released', count(*) filter (where s.stage = 'released'))
        from stages s)),
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
      'definition', 'Completed required items (published topics, server-verified practice missions of an accepted contract version and the COC practice quiz) divided by all required items in scope, averaged once per learner.'),
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
  with
  metrics as materialized (select * from private.analytics_learner_metrics(v_scope)),
  engagement as materialized (
    select e.learner_id, sum(e.points)::integer as points,
      coalesce(sum(e.points) filter (where e.awarded_at >= (v_scope ->> 'from')::timestamptz), 0)::integer as points_in_period
    from public.learner_point_events e
    where e.learner_id in (select m.learner_id from metrics m)
      and e.awarded_at <= (v_scope ->> 'to')::timestamptz
    group by e.learner_id
  )
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
          'late', m.homework_late, 'pending_evaluation', m.homework_pending),
        'last_activity_at', m.last_activity_at, 'status', m.status, 'reasons', m.reasons,
        'engagement', private.analytics_engagement_json(coalesce(e.points, 0), coalesce(e.points_in_period, 0)))
        order by case m.status when 'falling_behind' then 0 when 'struggling' then 1 else 2 end, m.name, m.learner_id)
      from metrics m left join engagement e on e.learner_id = m.learner_id), '[]'::jsonb),
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
  run_steps as materialized (select * from private.analytics_run_steps(v_scope)),
  completions as materialized (select * from private.analytics_practice_completions(v_scope)),
  engagement as materialized (
    select coalesce(sum(e.points), 0)::integer as points,
      coalesce(sum(e.points) filter (where e.awarded_at >= v_from), 0)::integer as points_in_period
    from public.learner_point_events e
    where e.learner_id = p_learner and e.awarded_at <= v_to
  ),
  module_completions as materialized (
    select lmc.module_id, lmc.completed_at from public.learner_module_completions lmc
    where lmc.learner_id = p_learner and lmc.completed_at <= v_to
  ),
  stages as materialized (
    select private.analytics_evaluation_stage('technical', a.status) as stage
    from assessments a where a.submitted_at is not null
    union all
    select h.stage from homework h where h.submitted_in_period
    union all
    select q.stage from quizzes q where q.stage is not null
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
    select h.submitted_at, 'homework_submitted', h.title, jsonb_build_object('late', h.late, 'status', h.status)
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
          'late', m.homework_late, 'pending_evaluation', m.homework_pending))
      from metrics m limit 1),
    'evaluation', (select jsonb_build_object(
        'evaluate', count(*) filter (where s.stage = 'evaluate'), 'finalize', count(*) filter (where s.stage = 'finalize'),
        'release', count(*) filter (where s.stage = 'release'), 'released', count(*) filter (where s.stage = 'released'))
      from stages s),
    'engagement', (select private.analytics_engagement_json(e.points, e.points_in_period)
        || jsonb_build_object(
          'achievements', (select count(*) from public.learner_achievements la
            where la.learner_id = p_learner and la.earned_at <= v_to),
          'recent_events', coalesce((
            select jsonb_agg(jsonb_build_object('event_type', x.event_type, 'label', x.label, 'points', x.points,
              'detail', x.detail, 'awarded_at', x.awarded_at) order by x.awarded_at desc)
            from (
              select pe.event_type, gr.label, pe.points, pe.detail, pe.awarded_at
              from public.learner_point_events pe
              left join public.gamification_point_rules gr on gr.event_type = pe.event_type
              where pe.learner_id = p_learner and pe.awarded_at between v_from and v_to
              order by pe.awarded_at desc, pe.id desc limit 5
            ) x), '[]'::jsonb))
      from engagement e),
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
        'score', q.score, 'max_score', q.max_score, 'release_mode', q.release_mode, 'stage', q.stage,
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
            'correction_count', rr.correction_count, 'ended_at', rr.event_at,
            'missed_steps', coalesce((
              select jsonb_agg(jsonb_build_object('phase_id', st.phase_id, 'step', st.step, 'title', st.title,
                'done', st.done, 'incorrect', st.incorrect) order by st.step nulls last, st.phase_id)
              from run_steps st where st.run_id = rr.run_id and (not st.done or st.incorrect > 0)), '[]'::jsonb))
            order by rr.event_at desc)
          from (select r.* from runs r where r.mission_code = x.mission_code and r.in_period
            order by r.event_at desc limit 5) rr), '[]'::jsonb))
        order by x.mission_code)
      from (select r.mission_code from runs r union select c.mission_code from completions c) x
      left join public.missions ms on ms.mission_code = x.mission_code), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object('homework_id', h.homework_id, 'title', h.title, 'class_title', h.class_title,
        'deadline_at', h.deadline_at, 'submitted_at', h.submitted_at, 'late', h.late,
        'status', case
          when h.submission_id is not null then h.status
          when h.missing then 'missing'
          else 'open' end,
        'stage', h.stage,
        'score', h.score, 'max_score', h.max_score, 'percent', round(h.percent, 1)) order by h.deadline_at nulls last, h.title)
      from homework h), '[]'::jsonb),
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object('attempt_id', a.attempt_id, 'mission_code', a.mission_code,
        'title', a.mission_title, 'assignment_title', a.assignment_title,
        'class_title', (select c.title from classes c where c.class_id = a.class_id),
        'status', a.status, 'stage', private.analytics_evaluation_stage('technical', a.status),
        'simulation', exists (select 1 from public.attempts att
          join public.rubric_criteria rc on rc.rubric_version_id = att.rubric_version_id
          where att.id = a.attempt_id and rc.evidence_rule ->> 'operator' = 'simulation_condition'),
        'submitted_at', a.submitted_at, 'released_at', a.released_at,
        'percent', round(a.percentage, 1), 'outcome', a.outcome,
        'criteria', case when a.released_at is null then '[]'::jsonb else coalesce((
          select jsonb_agg(jsonb_build_object('criterion_id', rc.id, 'code', rc.criterion_code, 'title', rc.title,
            'observation', cv ->> 'observation', 'score', nullif(cv ->> 'score_value', '')::numeric,
            'max', rc.max_value,
            'steps', private.analytics_criterion_steps(a.mission_code, rc.evidence_rule)) order by rc.order_index)
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
    'release_mode', (select v.result_release_mode from public.quiz_versions v where v.quiz_id = q.id
      order by (v.status = 'published'::public.content_version_status) desc, v.version_number desc limit 1),
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
        coalesce(c.class_id, e.class_id) as class_id, c.score, c.max_score, c.percent, c.submitted_at, c.stage,
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
      select qi.id, qi.item_code, qi.prompt, qi.item_type::text as item_type, qv.version_number, qi.order_index, qi.points,
        qi.item_type = 'scenario_essay'::public.quiz_item_type as is_essay,
        (select round(avg(ls.total), 2) from scored s
          cross join lateral (
            select es.total from public.quiz_essay_scores es
            where es.attempt_id = s.attempt_id and es.item_id = qi.id
            order by es.evaluated_at desc, es.sequence desc
            limit 1) ls) as avg_points,
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
          'release_mode', (select v.result_release_mode from public.quiz_versions v where v.quiz_id = q.id
            order by (v.status = 'published'::public.content_version_status) desc, v.version_number desc limit 1),
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
          'type', it.item_type, 'version_number', it.version_number, 'answered', it.answered,
          'correct', case when it.is_essay then null else it.correct end,
          'correct_rate', case when it.is_essay then null else private.analytics_rate(it.correct, it.answered) end,
          'points', it.points,
          'avg_points', case when it.is_essay then it.avg_points end,
          'avg_percent', case when it.is_essay and it.points > 0 and it.avg_points is not null
            then round(it.avg_points * 100 / it.points, 1) end) order by it.version_number, it.order_index)
        from items it), '[]'::jsonb),
      'results', coalesce((
        select jsonb_agg(jsonb_build_object('learner_id', r.learner_id, 'name', r.full_name, 'student_id', r.student_id,
          'class_id', r.class_id, 'class_title', (select c.title from classes c where c.class_id = r.class_id),
          'score', r.score, 'max_score', r.max_score, 'percent', round(r.percent, 1),
          'status', r.status, 'stage', r.stage, 'submitted_at', r.submitted_at)
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
  runs as materialized (select * from private.analytics_practice_runs(v_scope) r where r.in_period),
  step_stats as materialized (
    select s.mission_code, s.phase_id, min(s.step) as step, min(s.title) as title,
      count(*) as runs,
      count(*) filter (where not s.done or s.incorrect > 0) as missed,
      count(*) filter (where not s.done) as not_completed,
      round(avg(s.incorrect), 2) as avg_incorrect
    from private.analytics_run_steps(v_scope) s
    where s.in_period
    group by s.mission_code, s.phase_id
  ),
  completions as materialized (select * from private.analytics_practice_completions(v_scope)),
  assessments as materialized (select * from private.analytics_assessment_facts(v_scope)),
  mission_codes as (
    select r.mission_code from runs r
    union select c.mission_code from completions c
  ),
  mission_rows as (
    select ms.mission_code, ms.title, ms.mission_number, lower(coc.coc_code) as coc_code,
      cm.id as module_id, cm.code as module_code, cm.title as module_title,
      (select count(*) from population) as in_scope,
      (select count(distinct x.learner_id) from (
        select r.learner_id from runs r where r.mission_code = ms.mission_code
        union select c.learner_id from completions c where c.mission_code = ms.mission_code and c.in_period) x) as attempted,
      (select count(*) from completions c where c.mission_code = ms.mission_code and c.in_period) as verified,
      (select count(*) from completions c where c.mission_code = ms.mission_code) as verified_to_date,
      (select count(*) from runs r where r.mission_code = ms.mission_code) as run_count,
      (select count(*) from runs r where r.mission_code = ms.mission_code and r.outcome = 'verified') as successful,
      (select count(*) from runs r where r.mission_code = ms.mission_code and r.outcome = 'incomplete') as failed,
      (select count(distinct r.learner_id) from runs r where r.mission_code = ms.mission_code) as runners,
      (select avg(r.duration_seconds) from runs r where r.mission_code = ms.mission_code
        and r.outcome = 'verified' and r.duration_seconds is not null) as avg_duration,
      (select avg(r.invalid_count) from runs r where r.mission_code = ms.mission_code) as avg_invalid
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
        'learners_in_scope', m.in_scope,
        'learners_attempted', m.attempted, 'learners_verified', m.verified,
        'learners_verified_to_date', m.verified_to_date,
        'completion_rate_to_date', private.analytics_rate(m.verified_to_date, m.in_scope),
        'runs', m.run_count, 'successful_runs', m.successful, 'failed_runs', m.failed,
        'avg_runs_per_learner', case when m.runners > 0 then round(m.run_count::numeric / m.runners, 1) end,
        'avg_duration_seconds', round(m.avg_duration, 1),
        'avg_invalid_actions', round(m.avg_invalid, 1),
        'steps', coalesce((
          select jsonb_agg(jsonb_build_object('phase_id', st.phase_id, 'step', st.step, 'title', st.title,
            'runs', st.runs, 'missed', st.missed, 'missed_rate', private.analytics_rate(st.missed, st.runs),
            'not_completed', st.not_completed, 'avg_incorrect', st.avg_incorrect)
            order by st.step nulls last, st.phase_id)
          from step_stats st where st.mission_code = m.mission_code), '[]'::jsonb),
        'most_missed', coalesce((
          select jsonb_agg(jsonb_build_object('phase_id', x.phase_id, 'step', x.step, 'title', x.title,
            'runs', x.runs, 'missed', x.missed, 'missed_rate', private.analytics_rate(x.missed, x.runs),
            'avg_incorrect', x.avg_incorrect) order by x.missed desc, x.avg_incorrect desc, x.step nulls last, x.phase_id)
          from (
            select st.* from step_stats st
            where st.mission_code = m.mission_code and (st.missed > 0 or st.avg_incorrect > 0)
            order by st.missed desc, st.avg_incorrect desc, st.step nulls last, st.phase_id
            limit 3
          ) x), '[]'::jsonb)) order by m.coc_code, m.mission_number)
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
  assessment_criteria as (
    select case when rc.evidence_rule ->> 'operator' = 'simulation_condition' then 'simulation' else 'assessment' end as source,
      rc.id::text as criterion_key, rc.criterion_code as code,
      rc.title, rc.max_value, rc.order_index,
      min(l.mission_code) as mission_code, min(l.mission_title) as mission_title, min(l.mission_title) as activity_title,
      count(distinct l.learner_id) as learners, avg(l.score_value) as avg_score,
      count(*) filter (where l.observation = 'satisfied') as satisfied,
      count(*) filter (where l.observation is distinct from 'satisfied') as not_satisfied,
      private.analytics_criterion_steps(min(l.mission_code), rc.evidence_rule) as steps
    from latest l
    join public.rubric_criteria rc on rc.id = l.criterion_id
    group by rc.id
  ),
  homework_scores as (
    select hf.learner_id, ha.id as homework_id, ha.title as homework_title, ha.mission_code,
      c.ordinality::integer as order_index, c.value ->> 'id' as criterion_ref, c.value ->> 'criterion' as criterion_title,
      (c.value ->> 'max_points')::numeric as max_points,
      (hs.criterion_scores ->> (c.value ->> 'id'))::numeric as points
    from private.analytics_homework_facts(v_scope) hf
    join public.homework_submissions hs on hs.id = hf.submission_id
    join public.homework_assignments ha on ha.id = hf.homework_id
    cross join lateral jsonb_array_elements(ha.criteria) with ordinality c(value, ordinality)
    where hf.released and hf.submitted_in_period
      and hs.criterion_scores is not null
      and hs.criterion_scores ? (c.value ->> 'id')
  ),
  homework_criteria as (
    select 'homework'::text as source, h.homework_id::text || ':' || h.criterion_ref as criterion_key,
      h.criterion_ref as code, h.criterion_title as title, h.max_points as max_value, h.order_index,
      h.mission_code, (select ms.title from public.missions ms where ms.mission_code = h.mission_code) as mission_title,
      h.homework_title as activity_title,
      count(distinct h.learner_id) as learners, avg(h.points) as avg_score,
      null::bigint as satisfied, null::bigint as not_satisfied, '[]'::jsonb as steps
    from homework_scores h
    group by h.homework_id, h.homework_title, h.mission_code, h.criterion_ref, h.criterion_title, h.max_points, h.order_index
  ),
  -- Essay rubric criteria (A3): released quiz attempts only; the current essay
  -- score is the latest per attempt and item (evaluated_at desc, sequence desc).
  essay_attempts as materialized (
    select q.attempt_id, q.learner_id, q.quiz_id, q.quiz_title, q.quiz_version_id
    from private.analytics_quiz_facts(v_scope) q
    where q.scored and q.evaluation_status = 'released' and q.class_in_scope and q.in_period
  ),
  essay_scores as (
    select ea.learner_id, ea.quiz_title, qi.id as item_id, qi.item_code, qi.order_index as item_order,
      c.ordinality::integer as criterion_order, c.value ->> 'id' as criterion_ref, c.value ->> 'criterion' as criterion_title,
      (c.value ->> 'max_points')::numeric as max_points,
      (ls.criterion_scores ->> (c.value ->> 'id'))::numeric as points
    from essay_attempts ea
    join public.quiz_items qi on qi.quiz_version_id = ea.quiz_version_id
      and qi.item_type = 'scenario_essay'::public.quiz_item_type
      and qi.review_status = 'approved'::public.quiz_item_review_status
      and qi.removed_at is null
    cross join lateral (
      select s.criterion_scores from public.quiz_essay_scores s
      where s.attempt_id = ea.attempt_id and s.item_id = qi.id
      order by s.evaluated_at desc, s.sequence desc
      limit 1
    ) ls
    cross join lateral jsonb_array_elements(case when jsonb_typeof(qi.rubric) = 'array' then qi.rubric else '[]'::jsonb end)
      with ordinality c(value, ordinality)
    where ls.criterion_scores ? (c.value ->> 'id')
  ),
  essay_criteria as (
    select 'essay'::text as source, e.item_id::text || ':' || e.criterion_ref as criterion_key,
      e.criterion_ref as code, e.criterion_title as title, e.max_points as max_value,
      e.item_order * 100 + e.criterion_order as order_index,
      null::text as mission_code, null::text as mission_title, e.quiz_title || ' · ' || e.item_code as activity_title,
      count(distinct e.learner_id) as learners, avg(e.points) as avg_score,
      null::bigint as satisfied, null::bigint as not_satisfied, '[]'::jsonb as steps
    from essay_scores e
    group by e.item_id, e.item_code, e.item_order, e.quiz_title, e.criterion_ref, e.criterion_title, e.max_points, e.criterion_order
  ),
  all_criteria as (
    select * from assessment_criteria
    union all
    select * from homework_criteria
    union all
    select * from essay_criteria
  ),
  scored as (
    select ac.*, coalesce(
      case when ac.max_value > 0 and ac.avg_score is not null then round(ac.avg_score * 100 / ac.max_value, 1) end,
      private.analytics_rate(ac.satisfied, ac.satisfied + ac.not_satisfied)) as percent
    from all_criteria ac
  ),
  ranked as (
    select s.*,
      row_number() over (order by s.percent desc, s.learners desc, s.code, s.criterion_key) as best_rank,
      row_number() over (order by s.percent asc, s.learners desc, s.code, s.criterion_key) as worst_rank,
      count(*) over () as n
    from scored s where s.percent is not null
  ),
  shaped as (
    select r.*, jsonb_build_object('source', r.source, 'criterion_id', r.criterion_key, 'code', r.code,
      'title', r.title, 'mission_code', r.mission_code, 'mission_title', r.mission_title,
      'activity_title', r.activity_title, 'max', r.max_value,
      'avg', round(r.avg_score, 2), 'percent', r.percent, 'evaluated_learners', r.learners,
      'satisfied', r.satisfied, 'not_satisfied', r.not_satisfied, 'steps', r.steps) as item,
      least(3, ceil(r.n / 2.0))::integer as strong_count
    from ranked r
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_scope ->> 'from', 'to', v_scope ->> 'to'),
    'filters', private.analytics_public_filters(v_scope),
    'criteria', coalesce((select jsonb_agg(s.item order by s.source, s.mission_code nulls last, s.activity_title, s.order_index, s.code)
      from shaped s), '[]'::jsonb),
    'strongest', coalesce((select jsonb_agg(s.item order by s.best_rank) from shaped s
      where s.best_rank <= s.strong_count), '[]'::jsonb),
    'weakest', coalesce((select jsonb_agg(s.item order by s.worst_rank) from shaped s
      where s.worst_rank <= least(3, s.n - s.strong_count)), '[]'::jsonb),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Learner view
-- ---------------------------------------------------------------------------
create or replace function public.get_my_performance()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_learner uuid := auth.uid();
  v_result jsonb;
begin
  if v_learner is null or not public.is_learner() then
    raise exception 'ANALYTICS_LEARNER_REQUIRED' using errcode = '42501';
  end if;

  with
  states as materialized (select * from public.learner_module_states(v_learner)),
  quiz_passed as materialized (
    select pcp.coc_code from public.practice_coc_progress pcp where pcp.learner_id = v_learner
  ),
  cocs as (
    select c.coc_code, c.title,
      coalesce(sum(s.topics_done + s.missions_done), 0)::integer
        + case when exists (select 1 from quiz_passed q where q.coc_code = c.coc_code) then 1 else 0 end as done,
      coalesce(sum(s.topics_total + s.missions_total), 0)::integer + 1 as total,
      (count(s.module_id) filter (where s.completed))::integer as modules_completed,
      count(s.module_id)::integer as modules_total
    from (
      select lower(cm.coc_code) as coc_code, cm.title from public.coc_modules cm
      where lower(cm.coc_code) in (select m.coc_code from public.curriculum_modules m)
    ) c
    left join states s on s.coc_code = c.coc_code
    group by c.coc_code, c.title
  ),
  releases as materialized (
    select a.id as attempt_id, rr.released_at, sr.percentage, sr.outcome::text as outcome, sr.criterion_values,
      asg.title as assignment_title, ms.mission_code, ms.title as mission_title
    from public.result_releases rr
    join public.attempts a on a.id = rr.attempt_id
    join public.score_revisions sr on sr.id = rr.score_revision_id
    left join public.assignments asg on asg.id = a.assignment_id
    left join public.activity_versions av on av.id = a.activity_version_id
    left join public.missions ms on ms.id = av.mission_id
    where rr.is_current and a.learner_id = v_learner
  ),
  latest_per_mission as (
    select distinct on (coalesce(r.mission_code, r.attempt_id::text)) r.*
    from releases r
    order by coalesce(r.mission_code, r.attempt_id::text), r.released_at desc, r.attempt_id desc
  ),
  competency_values as materialized (
    select l.attempt_id, l.mission_code, l.mission_title, l.released_at,
      (cv ->> 'criterion_id')::uuid as criterion_id, cv ->> 'observation' as observation
    from latest_per_mission l
    cross join lateral jsonb_array_elements(case when jsonb_typeof(l.criterion_values) = 'array'
      then l.criterion_values else '[]'::jsonb end) cv
    where cv ? 'criterion_id'
    union all
    (select distinct on (cr.attempt_id, cr.rubric_criterion_id)
      l.attempt_id, l.mission_code, l.mission_title, l.released_at, cr.rubric_criterion_id, cr.observation::text
    from latest_per_mission l
    join public.criterion_results cr on cr.attempt_id = l.attempt_id
    where jsonb_typeof(l.criterion_values) is distinct from 'array' or jsonb_array_length(l.criterion_values) = 0
    order by cr.attempt_id, cr.rubric_criterion_id, cr.evaluated_at desc, cr.id desc)
  ),
  -- Visible results only: immediate results from quiz_results (points when
  -- recorded), instructor-release results from their finalization once
  -- released. RLS hides everything else from the learner as well.
  quizzes as materialized (
    select qa.id, qa.quiz_assignment_id, qa.submitted_at, qa.evaluation_status, qr.correct_count, qr.question_count,
      case when qa.evaluation_status = 'released' then f.percent
        when qr.objective_points is not null and qr.max_points > 0 then round(qr.objective_points * 100 / qr.max_points, 1)
        when qr.question_count > 0 then round(qr.correct_count::numeric * 100 / qr.question_count, 1) end as percent,
      -- Points when recorded (finalization, or objective points); null for
      -- results recorded before points, which report answers only.
      case when qa.evaluation_status = 'released' then f.total_points
        when qr.objective_points is not null and qr.max_points > 0 then qr.objective_points end as score,
      case when qa.evaluation_status = 'released' then f.max_points
        when qr.objective_points is not null and qr.max_points > 0 then qr.max_points end as max_score
    from public.quiz_attempts qa
    left join public.quiz_results qr on qr.quiz_attempt_id = qa.id
    left join public.quiz_result_finalizations f on f.attempt_id = qa.id
    where qa.learner_id = v_learner
      and qa.status = 'completed'::public.quiz_attempt_status
      and qa.submitted_at is not null
      and ((qa.evaluation_status = 'not_required' and qr.quiz_attempt_id is not null)
        or (qa.evaluation_status = 'released' and f.released_at is not null))
  ),
  -- Learners read their own submission only while ungraded or once released (A4).
  homework as materialized (
    select s.id, s.status, s.score, s.submitted_at, s.lateness_seconds, h.title, h.max_score
    from public.homework_submissions s
    left join public.homework_assignments h on h.id = s.assignment_id
    where s.learner_id = v_learner
  )
  select jsonb_build_object(
    'progress', jsonb_build_object(
      'overall_percent', (select private.analytics_rate(sum(c.done), sum(c.total)) from cocs c),
      'completed_items', (select coalesce(sum(c.done), 0) from cocs c),
      'total_items', (select coalesce(sum(c.total), 0) from cocs c),
      'cocs', coalesce((
        select jsonb_agg(jsonb_build_object(
          'coc_code', c.coc_code, 'title', c.title, 'percent', private.analytics_rate(c.done, c.total),
          'completed_items', c.done, 'total_items', c.total,
          'modules_completed', c.modules_completed, 'modules_total', c.modules_total) order by c.coc_code)
        from cocs c), '[]'::jsonb)),
    'competency', coalesce((
      select jsonb_agg(jsonb_build_object(
        'criterion', rc.title, 'code', rc.criterion_code, 'mission_code', v.mission_code,
        'mission_title', v.mission_title, 'outcome', v.observation, 'released_at', v.released_at)
        order by v.released_at desc, v.mission_code, rc.order_index nulls last)
      from competency_values v
      left join public.rubric_criteria rc on rc.id = v.criterion_id), '[]'::jsonb),
    'scores', jsonb_build_object(
      'quizzes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'attempt_id', q.id, 'assignment_id', q.quiz_assignment_id,
          'percent', q.percent, 'score', q.score, 'max_score', q.max_score,
          'correct_count', q.correct_count, 'question_count', q.question_count,
          'released', q.evaluation_status = 'released', 'submitted_at', q.submitted_at)
          order by q.submitted_at desc)
        from quizzes q), '[]'::jsonb),
      'homework', coalesce((
        select jsonb_agg(jsonb_build_object(
          'title', h.title, 'score', case when h.status = 'released' then h.score end,
          'max_score', coalesce(h.max_score, 100),
          'percent', case when h.status = 'released' and h.score is not null and h.max_score > 0
            then round(h.score * 100 / h.max_score, 1) end,
          'released', h.status = 'released', 'submitted_at', h.submitted_at, 'late', h.lateness_seconds > 0)
          order by h.submitted_at desc)
        from homework h), '[]'::jsonb)),
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'attempt_id', r.attempt_id, 'mission', r.mission_code, 'title', coalesce(r.mission_title, r.assignment_title),
        'assignment_title', r.assignment_title, 'percent', round(r.percentage, 1), 'outcome', r.outcome,
        'released_at', r.released_at) order by r.released_at desc)
      from releases r), '[]'::jsonb),
    'practice', jsonb_build_object(
      'missions_verified', (select count(*) from public.practice_mission_completions c
        where c.learner_id = v_learner and public.practice_completion_accepted(c.mission_id, c.contract_version)),
      'runs', (select count(*) from public.practice_mission_runs r where r.learner_id = v_learner),
      'best_times', coalesce((
        select jsonb_agg(jsonb_build_object('mission_code', b.mission_id, 'title', ms.title, 'best_seconds', b.best)
          order by b.mission_id)
        from (
          select r.mission_id, min(r.duration_seconds) as best
          from public.practice_mission_runs r
          where r.learner_id = v_learner and r.outcome = 'verified' and r.duration_seconds is not null
          group by r.mission_id
        ) b
        left join public.missions ms on ms.mission_code = b.mission_id), '[]'::jsonb)),
    'summary', jsonb_build_object(
      'quiz_avg', (select round(avg(q.percent), 1) from quizzes q where q.percent is not null),
      'homework_avg', (select round(avg(h.score * 100 / h.max_score), 1)
        from homework h where h.status = 'released' and h.score is not null and h.max_score > 0),
      'homework_released', (select count(*) from homework h where h.status = 'released'),
      'assessments_released', (select count(*) from releases),
      'assessments_competent', (select count(*) from releases r where r.outcome = 'competent'),
      'criteria_total', (select count(*) from competency_values),
      'criteria_achieved', (select count(*) from competency_values v where v.observation = 'satisfied')),
    'updated_at', now()
  ) into v_result;
  return v_result;
end
$$;

drop function if exists private.analytics_learner_quiz_title(uuid);

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'private.analytics_contract_steps(jsonb)',
    'private.analytics_criterion_steps(text, jsonb)',
    'private.analytics_run_steps(jsonb)',
    'private.analytics_quiz_matches(jsonb, text, uuid, uuid)',
    'private.analytics_quiz_facts(jsonb)',
    'private.analytics_engagement_json(integer, integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated, service_role', v_signature);
  end loop;
end
$$;

notify pgrst, 'reload schema';

commit;
