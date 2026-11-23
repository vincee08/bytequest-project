-- Panel revision (2026-11-23): learner status also reflects deadlines and the
-- completion of required work, not only activity, progress and performance.
--
-- falling_behind now also applies when, in the selected period, a learner has
-- at least one deadline that passed without a submission:
--   * published homework whose current deadline passed with no submission
--     (private.analytics_homework_facts.missing: the learner was enrolled
--     before the deadline; a moved deadline is the deadline that counts);
--   * a published quiz whose assignment deadline passed with no attempt, for a
--     learner enrolled in that class before the deadline. A quiz that is still
--     open to the learner through any assignment (reopened or later deadline)
--     is not missed, an assignment closed before its deadline was withdrawn
--     and is not missed, and an attempt started before the deadline counts
--     (the server submits it when its time runs out).
-- The threshold is one missed deadline. This is a ByteQuest operational
-- signal, not a TESDA rule. "struggling" (performance) is unchanged.
-- Additive: replaces analytics functions only, writes no data, and adds no
-- SECURITY DEFINER function. Definitions: docs/ANALYTICS_METRIC_DEFINITIONS.md.
begin;
set local lock_timeout = '5s';

-- One row per (learner, quiz) whose deadline passed without an attempt.
create or replace function private.analytics_missed_quizzes(p_scope jsonb)
returns table (learner_id uuid, quiz_id uuid, title text, due_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  with eligible as materialized (
    select mb.learner_id, mb.enrolled_at, q.id as quiz_id, q.title, qa.due_at, qa.closed_at
    from public.quiz_assignments qa
    join private.analytics_members(p_scope) mb on mb.class_id = qa.class_id
    join public.quiz_versions qv on qv.id = qa.quiz_version_id
    join public.quizzes q on q.id = qv.quiz_id
    left join public.coc_modules coc on coc.id = q.coc_module_id
    where qv.published_at is not null
      and qv.status in ('published'::public.content_version_status, 'retired'::public.content_version_status)
      and private.analytics_source_applicable(p_scope, 'quizzes')
      and private.analytics_quiz_matches(p_scope, lower(coc.coc_code), q.id, q.topic_id)
  ),
  past_due as (
    select e.*
    from eligible e
    where e.due_at is not null
      and e.due_at >= (p_scope ->> 'from')::timestamptz
      and e.due_at <= least((p_scope ->> 'to')::timestamptz, now())
      and e.enrolled_at <= e.due_at
      and (e.closed_at is null or e.closed_at >= e.due_at)
  )
  select distinct on (d.learner_id, d.quiz_id) d.learner_id, d.quiz_id, d.title, d.due_at
  from past_due d
  where not exists (
      select 1
      from public.quiz_attempts a
      join public.quiz_versions v on v.id = a.quiz_version_id
      where a.learner_id = d.learner_id
        and v.quiz_id = d.quiz_id
        and (a.status in ('submitted'::public.quiz_attempt_status, 'completed'::public.quiz_attempt_status)
          or (a.status = 'in_progress'::public.quiz_attempt_status and a.started_at <= d.due_at))
    )
    and not exists (
      select 1
      from eligible o
      where o.learner_id = d.learner_id
        and o.quiz_id = d.quiz_id
        and (o.due_at is null or o.due_at > now())
        and (o.closed_at is null or o.closed_at > now())
    )
  order by d.learner_id, d.quiz_id, d.due_at desc
$$;

revoke all on function private.analytics_missed_quizzes(jsonb) from public, anon;
grant execute on function private.analytics_missed_quizzes(jsonb) to authenticated, service_role;

-- Same signature and columns as 20261119170400; adds the missed-deadline rule.
create or replace function private.analytics_learner_metrics(p_scope jsonb)
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
  missed_quizzes as materialized (select * from private.analytics_missed_quizzes(p_scope)),
  missed_work as (
    select h.learner_id, 'homework'::text as kind, h.title, h.deadline_at
    from homework h where h.missing
    union all
    select mq.learner_id, 'quiz'::text, mq.title, mq.due_at from missed_quizzes mq
  ),
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
      (select count(*) from missed_quizzes mq where mq.learner_id = a.learner_id)::integer as quiz_missed,
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
      b.hw_missing + b.quiz_missed >= 1 as missed_deadlines,
      (select coalesce(jsonb_agg(jsonb_build_object('kind', w.kind, 'title', w.title, 'deadline_at', w.deadline_at)
          order by w.deadline_at desc, w.title), '[]'::jsonb)
        from (select mw.* from missed_work mw where mw.learner_id = b.learner_id
          order by mw.deadline_at desc, mw.title limit 5) w) as missed_items,
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
      when f.inactive or f.below_median or f.missed_deadlines then 'falling_behind'
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
    || (case when f.missed_deadlines then jsonb_build_array(jsonb_build_object(
        'code', 'missed_deadlines', 'kind', 'falling_behind', 'threshold', 1,
        'missed_count', f.hw_missing + f.quiz_missed,
        'homework_missed', f.hw_missing, 'quizzes_missed', f.quiz_missed,
        'items', f.missed_items))
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

-- Same as 20261119170500 plus the missed-deadline threshold.
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
      'quiz_average_below', 75, 'incomplete_runs_on_one_mission', 3, 'missed_deadlines_at_least', 1),
    'counts', jsonb_build_object(
      'on_track', (select count(*) from metrics m where m.status = 'on_track'),
      'struggling', (select count(*) from metrics m where m.status = 'struggling'),
      'falling_behind', (select count(*) from metrics m where m.status = 'falling_behind')),
    'generated_at', now()
  ) into v_result;
  return v_result;
end
$$;

comment on function public.get_learner_performance(jsonb) is
  'Objective 6 learner list with documented on_track / struggling / falling_behind rules, including missed deadlines (SECURITY INVOKER).';

commit;
