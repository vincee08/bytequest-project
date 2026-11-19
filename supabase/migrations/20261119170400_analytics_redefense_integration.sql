-- Slice A7, integration round 1 (after slices A2, A4 and A5 merged).
--   * A2 methodology: a practice mission counts as complete only for an
--     accepted contract version (public.practice_completion_accepted); the
--     learner view takes its progress and module counts from
--     public.learner_module_states, exactly like the Progress screen.
--   * A4 homework: max_score, criteria/criterion_scores, the
--     submitted -> graded -> finalized -> released lifecycle and curriculum
--     links. Averages use released grades only; anything submitted and not yet
--     released is pending evaluation. Technical `under_review` is pending.
--     Evaluate / Finalize / Release counts use the Evaluation Center mapping.
--   * Review fixes: homework "missing" and quiz eligibility ignore learners
--     enrolled after the deadline; mission analytics label every column as
--     period or to-date.
-- Additive: replaces analytics functions only; no data is written, no
-- SECURITY DEFINER function is added. Definitions: docs/ANALYTICS_METRIC_DEFINITIONS.md.
begin;

-- ---------------------------------------------------------------------------
-- Homework is now positioned on COC / module / mission (A4).
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
    when 'quizzes' then p_scope ->> 'module_id' is null and p_scope ->> 'topic_id' is null
      and p_scope ->> 'mission_code' is null
    when 'homework' then p_scope ->> 'topic_id' is null and p_scope ->> 'quiz_id' is null
    when 'learning' then p_scope ->> 'quiz_id' is null
    else false
  end
$$;

-- Evaluate -> Finalize -> Release -> Released, as in public.get_evaluation_queue.
-- A technical attempt still `submitted` (automated evaluation not recorded)
-- waits in Evaluate too.
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
  end
$$;

-- ---------------------------------------------------------------------------
-- Homework facts: one row per (published homework, active class member).
-- percent = released score / max_score (released grades only). Eligibility and
-- "missing" ignore learners enrolled after the deadline unless they submitted.
-- ---------------------------------------------------------------------------
drop function if exists private.analytics_homework_facts(jsonb);
create function private.analytics_homework_facts(p_scope jsonb)
returns table (
  homework_id uuid,
  class_id uuid,
  learner_id uuid,
  title text,
  deadline_at timestamptz,
  published_at timestamptz,
  submission_id uuid,
  submitted_at timestamptz,
  late boolean,
  status text,
  stage text,
  released boolean,
  score numeric,
  max_score numeric,
  percent numeric,
  open_in_period boolean,
  missing boolean,
  submitted_in_period boolean,
  coc_code text,
  module_id uuid,
  mission_code text,
  enrolled_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select h.id, h.class_id, mb.learner_id, h.title, h.deadline_at, h.published_at,
    s.id, s.submitted_at, coalesce(s.lateness_seconds > 0, false), s.status,
    private.analytics_evaluation_stage('homework', s.status),
    coalesce(s.status = 'released', false),
    s.score,
    h.max_score,
    case when s.status = 'released' and s.score is not null and h.max_score > 0
      then round(s.score * 100 / h.max_score, 4) end,
    (h.deadline_at is null or h.deadline_at >= (p_scope ->> 'from')::timestamptz)
      and (s.id is not null or h.deadline_at is null or mb.enrolled_at <= h.deadline_at),
    s.id is null and h.deadline_at is not null
      and mb.enrolled_at <= h.deadline_at
      and h.deadline_at >= (p_scope ->> 'from')::timestamptz
      and h.deadline_at <= least((p_scope ->> 'to')::timestamptz, now()),
    coalesce(s.submitted_at >= (p_scope ->> 'from')::timestamptz, false),
    lower(coalesce(coc.coc_code, cm.coc_code, left(h.mission_code, 4))),
    coalesce(h.module_id, link.module_id),
    h.mission_code,
    mb.enrolled_at
  from public.homework_assignments h
  join private.analytics_members(p_scope) mb on mb.class_id = h.class_id
  left join public.coc_modules coc on coc.id = h.coc_module_id
  left join public.curriculum_modules cm on cm.id = h.module_id
  left join public.mission_curriculum_links link on link.mission_code = h.mission_code
  left join public.homework_submissions s
    on s.assignment_id = h.id and s.learner_id = mb.learner_id
   and s.submitted_at <= (p_scope ->> 'to')::timestamptz
  where h.status = 'published'
    and h.published_at is not null
    and h.published_at <= (p_scope ->> 'to')::timestamptz
    and private.analytics_source_applicable(p_scope, 'homework')
    and private.analytics_matches(p_scope, lower(coalesce(coc.coc_code, cm.coc_code, left(h.mission_code, 4))),
      coalesce(h.module_id, link.module_id), null, h.mission_code, null)
$$;

-- Quiz eligibility: the learner must have been enrolled before the quiz closed.
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
    and private.analytics_matches(p_scope, lower(coc.coc_code), null, null, null, q.id)
$$;

-- Practice completions: accepted contract versions only (A2 methodology).
create or replace function private.analytics_practice_completions(p_scope jsonb)
returns table (
  learner_id uuid,
  mission_code text,
  coc_code text,
  module_id uuid,
  verified_at timestamptz,
  in_period boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.learner_id, c.mission_id, left(c.mission_id, 4), link.module_id, c.verified_at,
    c.verified_at >= (p_scope ->> 'from')::timestamptz
  from public.practice_mission_completions c
  join (select distinct mb.learner_id from private.analytics_members(p_scope) mb) pop on pop.learner_id = c.learner_id
  left join public.mission_curriculum_links link on link.mission_code = c.mission_id
  where c.verified_at <= (p_scope ->> 'to')::timestamptz
    and public.practice_completion_accepted(c.mission_id, c.contract_version)
    and private.analytics_source_applicable(p_scope, 'practice')
    and private.analytics_matches(p_scope, left(c.mission_id, 4), link.module_id, null, c.mission_id, null)
$$;

create or replace function private.analytics_learning_items(p_scope jsonb)
returns table (
  learner_id uuid,
  item_kind text,
  item_key text,
  title text,
  coc_code text,
  module_id uuid,
  topic_id uuid,
  mission_code text,
  completed_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.learner_id, i.item_kind, i.item_key, i.title, i.coc_code, i.module_id, i.topic_id, i.mission_code,
    case i.item_kind
      when 'topic' then (
        select ltp.completed_at from public.learner_topic_progress ltp
        where ltp.learner_id = p.learner_id and ltp.topic_id = i.topic_id
          and ltp.completed_at <= (p_scope ->> 'to')::timestamptz)
      when 'mission' then (
        select pmc.verified_at from public.practice_mission_completions pmc
        where pmc.learner_id = p.learner_id and pmc.mission_id = i.mission_code
          and pmc.verified_at <= (p_scope ->> 'to')::timestamptz
          and public.practice_completion_accepted(pmc.mission_id, pmc.contract_version))
      when 'coc_quiz' then (
        select pcp.completed_at from public.practice_coc_progress pcp
        where pcp.learner_id = p.learner_id and pcp.coc_code = i.coc_code
          and pcp.completed_at <= (p_scope ->> 'to')::timestamptz)
    end
  from (select distinct mb.learner_id from private.analytics_members(p_scope) mb) p
  cross join private.analytics_required_items(p_scope) i
$$;

-- ---------------------------------------------------------------------------
-- Per-learner metrics: adds homework pending evaluation (submitted in the
-- period, not yet released). Status rules unchanged.
-- ---------------------------------------------------------------------------
drop function if exists private.analytics_learner_metrics(jsonb);
create function private.analytics_learner_metrics(p_scope jsonb)
returns table (
  learner_id uuid,
  name text,
  student_id text,
  email text,
  classes jsonb,
  progress_percent numeric,
  completed_items integer,
  total_items integer,
  performance_score numeric,
  quiz_avg numeric,
  quiz_scored integer,
  assessment_released integer,
  assessment_competent integer,
  assessment_pending integer,
  missions_verified integer,
  practice_runs integer,
  homework_submitted integer,
  homework_missing integer,
  homework_late integer,
  homework_pending integer,
  last_activity_at timestamptz,
  status text,
  reasons jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  with
  members as materialized (select * from private.analytics_members(p_scope)),
  classes as materialized (select * from private.analytics_classes(p_scope)),
  activity as materialized (select * from private.analytics_last_activity(p_scope)),
  progress as materialized (select * from private.analytics_learner_progress(p_scope)),
  class_medians as materialized (
    select mb.class_id, percentile_cont(0.5) within group (order by lp.percent) as median
    from private.analytics_members(p_scope - 'learner_id') mb
    join private.analytics_learner_progress(p_scope - 'learner_id') lp on lp.learner_id = mb.learner_id
    group by mb.class_id
  ),
  assessments as materialized (select * from private.analytics_assessment_facts(p_scope)),
  quizzes as materialized (
    select * from private.analytics_quiz_facts(p_scope) qf where qf.class_in_scope and qf.in_period
  ),
  homework as materialized (select * from private.analytics_homework_facts(p_scope)),
  runs as materialized (select * from private.analytics_practice_runs(p_scope)),
  completions as materialized (select * from private.analytics_practice_completions(p_scope)),
  scores as (
    select a.learner_id, a.percentage as pct from assessments a
    where a.released_at is not null and a.percentage is not null
    union all
    select q.learner_id, q.percent from quizzes q where q.scored
    union all
    select h.learner_id, h.percent from homework h where h.percent is not null and h.submitted_in_period
  ),
  latest_release as (
    select distinct on (a.learner_id, a.mission_code) a.learner_id, a.mission_code, a.mission_title, a.outcome
    from assessments a
    where a.released_at is not null
    order by a.learner_id, a.mission_code, a.released_at desc, a.attempt_id desc
  ),
  run_struggles as (
    select r.learner_id, r.mission_code, count(*)::integer as incomplete_runs
    from runs r
    where r.in_period and r.outcome = 'incomplete'
      and not exists (
        select 1 from completions c where c.learner_id = r.learner_id and c.mission_code = r.mission_code
      )
    group by r.learner_id, r.mission_code
    having count(*) >= 3
  ),
  base as (
    select a.learner_id, a.enrolled_at, a.last_activity_at,
      pr.full_name, pr.learner_id as student_id, pr.email,
      coalesce((
        select jsonb_agg(jsonb_build_object('id', c.class_id, 'title', c.title) order by c.title)
        from members m join classes c on c.class_id = m.class_id
        where m.learner_id = a.learner_id
      ), '[]'::jsonb) as classes,
      p.percent as progress, p.completed_items, p.total_items,
      (select avg(s.pct) from scores s where s.learner_id = a.learner_id) as performance_score,
      (select avg(q.percent) from quizzes q where q.learner_id = a.learner_id and q.scored) as quiz_avg,
      (select count(*) from quizzes q where q.learner_id = a.learner_id and q.scored)::integer as quiz_scored,
      (select count(*) from assessments x where x.learner_id = a.learner_id and x.released_at is not null)::integer as released,
      (select count(*) from assessments x where x.learner_id = a.learner_id and x.outcome = 'competent')::integer as competent,
      (select count(*) from assessments x where x.learner_id = a.learner_id
        and x.submitted_at is not null and x.released_at is null)::integer as pending,
      (select count(*) from completions c where c.learner_id = a.learner_id)::integer as verified,
      (select count(*) from runs r where r.learner_id = a.learner_id and r.in_period)::integer as run_count,
      (select count(*) from homework h where h.learner_id = a.learner_id and h.submitted_in_period)::integer as hw_submitted,
      (select count(*) from homework h where h.learner_id = a.learner_id and h.missing)::integer as hw_missing,
      (select count(*) from homework h where h.learner_id = a.learner_id and h.submitted_in_period and h.late)::integer as hw_late,
      (select count(*) from homework h where h.learner_id = a.learner_id and h.submitted_in_period and not h.released)::integer as hw_pending,
      (select cm.median from members m join class_medians cm on cm.class_id = m.class_id
        where m.learner_id = a.learner_id order by cm.median desc nulls last limit 1) as class_median,
      (select c.title from members m join class_medians cm on cm.class_id = m.class_id join classes c on c.class_id = m.class_id
        where m.learner_id = a.learner_id order by cm.median desc nulls last, c.title limit 1) as median_class_title
    from activity a
    join public.profiles pr on pr.user_id = a.learner_id
    left join progress p on p.learner_id = a.learner_id
  ),
  flagged as (
    select b.*,
      coalesce(b.last_activity_at, b.enrolled_at) < least(now(), (p_scope ->> 'to')::timestamptz) - interval '14 days' as inactive,
      b.progress is not null and b.class_median is not null and b.class_median > 0
        and b.progress < b.class_median * 0.5 as below_median,
      b.quiz_avg is not null and b.quiz_avg < 75 as low_quiz,
      (select coalesce(jsonb_agg(lr.mission_title order by lr.mission_title), '[]'::jsonb)
        from latest_release lr where lr.learner_id = b.learner_id and lr.outcome = 'not_yet_competent') as nyc_missions,
      (select coalesce(jsonb_agg(jsonb_build_object('mission_code', rs.mission_code,
          'title', (select ms.title from public.missions ms where ms.mission_code = rs.mission_code),
          'incomplete_runs', rs.incomplete_runs) order by rs.mission_code), '[]'::jsonb)
        from run_struggles rs where rs.learner_id = b.learner_id) as run_missions
    from base b
  )
  select f.learner_id, f.full_name, f.student_id, f.email, f.classes,
    round(f.progress, 1), f.completed_items, f.total_items,
    round(f.performance_score, 1), round(f.quiz_avg, 1), f.quiz_scored,
    f.released, f.competent, f.pending, f.verified, f.run_count,
    f.hw_submitted, f.hw_missing, f.hw_late, f.hw_pending, f.last_activity_at,
    case
      when f.inactive or f.below_median then 'falling_behind'
      when f.low_quiz or jsonb_array_length(f.nyc_missions) > 0 or jsonb_array_length(f.run_missions) > 0 then 'struggling'
      else 'on_track'
    end,
    (case when f.inactive then jsonb_build_array(jsonb_build_object(
        'code', 'inactive', 'kind', 'falling_behind', 'threshold_days', 14,
        'last_activity_at', f.last_activity_at,
        'days_inactive', floor(extract(epoch from (least(now(), (p_scope ->> 'to')::timestamptz)
          - coalesce(f.last_activity_at, f.enrolled_at))) / 86400)::integer))
      else '[]'::jsonb end)
    || (case when f.below_median then jsonb_build_array(jsonb_build_object(
        'code', 'below_class_median', 'kind', 'falling_behind', 'progress_percent', round(f.progress, 1),
        'class_median', round(f.class_median::numeric, 1), 'class_title', f.median_class_title))
      else '[]'::jsonb end)
    || (case when f.low_quiz then jsonb_build_array(jsonb_build_object(
        'code', 'quiz_average_low', 'kind', 'struggling', 'quiz_avg', round(f.quiz_avg, 1), 'threshold', 75))
      else '[]'::jsonb end)
    || (case when jsonb_array_length(f.nyc_missions) > 0 then jsonb_build_array(jsonb_build_object(
        'code', 'not_yet_competent', 'kind', 'struggling', 'missions', f.nyc_missions))
      else '[]'::jsonb end)
    || (case when jsonb_array_length(f.run_missions) > 0 then jsonb_build_array(jsonb_build_object(
        'code', 'repeated_incomplete_runs', 'kind', 'struggling', 'threshold', 3, 'missions', f.run_missions))
      else '[]'::jsonb end)
  from flagged f
$$;

-- ---------------------------------------------------------------------------
-- Overview: homework (released averages, pending evaluation) and the
-- Evaluate / Finalize / Release counts of work submitted in the period.
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
          'late', m.homework_late, 'pending_evaluation', m.homework_pending),
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
-- Learner profile: homework lifecycle, evaluation stage counts.
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
  stages as materialized (
    select private.analytics_evaluation_stage('technical', a.status) as stage
    from assessments a where a.submitted_at is not null
    union all
    select h.stage from homework h where h.submitted_in_period
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
        'submitted_at', a.submitted_at, 'released_at', a.released_at,
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
-- Missions: every column is either "in the period" or explicitly "to date"
-- (by the period end). Missions with activity in the period or a verified
-- completion to date are listed.
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
  runs as materialized (select * from private.analytics_practice_runs(v_scope) r where r.in_period),
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
-- Criteria: released assessment rubric criteria plus released homework
-- criteria (A4 criterion_scores). One value per learner per criterion.
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
  assessment_criteria as (
    select 'assessment'::text as source, l.criterion_id::text as criterion_key, rc.criterion_code as code,
      rc.title, rc.max_value, rc.order_index,
      min(l.mission_code) as mission_code, min(l.mission_title) as mission_title, min(l.mission_title) as activity_title,
      count(distinct l.learner_id) as learners, avg(l.score_value) as avg_score,
      count(*) filter (where l.observation = 'satisfied') as satisfied,
      count(*) filter (where l.observation is distinct from 'satisfied') as not_satisfied
    from latest l
    join public.rubric_criteria rc on rc.id = l.criterion_id
    group by l.criterion_id, rc.criterion_code, rc.title, rc.max_value, rc.order_index
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
      null::bigint as satisfied, null::bigint as not_satisfied
    from homework_scores h
    group by h.homework_id, h.homework_title, h.mission_code, h.criterion_ref, h.criterion_title, h.max_points, h.order_index
  ),
  all_criteria as (
    select * from assessment_criteria
    union all
    select * from homework_criteria
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
      'satisfied', r.satisfied, 'not_satisfied', r.not_satisfied) as item,
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
-- Learner view: progress and module counts from learner_module_states (the
-- Progress screen's methodology), released homework percentages, and a
-- server-computed summary for the compact Progress-screen section.
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
  quizzes as materialized (
    select distinct on (qa.quiz_version_id) qa.id, qa.submitted_at, qr.correct_count, qr.question_count
    from public.quiz_attempts qa
    join public.quiz_results qr on qr.quiz_attempt_id = qa.id
    where qa.learner_id = v_learner
      and qa.status = 'completed'::public.quiz_attempt_status
      and qa.submitted_at is not null
    order by qa.quiz_version_id, qa.submitted_at, qa.id
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
          'attempt_id', q.id, 'title', private.analytics_learner_quiz_title(q.id),
          'percent', private.analytics_rate(q.correct_count, q.question_count),
          'correct_count', q.correct_count, 'question_count', q.question_count, 'submitted_at', q.submitted_at)
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
      'quiz_avg', (select round(avg(q.correct_count::numeric * 100 / q.question_count), 1)
        from quizzes q where q.question_count > 0),
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

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'private.analytics_source_applicable(jsonb, text)',
    'private.analytics_evaluation_stage(text, text)',
    'private.analytics_homework_facts(jsonb)',
    'private.analytics_quiz_eligibility(jsonb)',
    'private.analytics_practice_completions(jsonb)',
    'private.analytics_learning_items(jsonb)',
    'private.analytics_learner_metrics(jsonb)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated, service_role', v_signature);
  end loop;
end
$$;

notify pgrst, 'reload schema';

commit;
