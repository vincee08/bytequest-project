-- Slice A7 (Objective 6): learner-facing performance projection for the app's
-- PerformanceSection. STABLE SECURITY INVOKER: a learner reads only their own
-- rows under RLS, and only released assessment results (result_releases is
-- learner-visible only when current). Learning progress follows the WS3
-- methodology shared with the instructor analytics.
begin;

-- Quiz titles are not readable by learners under RLS (quizzes/quiz_versions
-- are staff-only); the existing learner result RPC returns the title of the
-- learner's own completed attempt. A failure yields null (the app shows a
-- generic label) instead of failing the whole projection.
create or replace function private.analytics_learner_quiz_title(p_attempt_id uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return public.get_learner_quiz_result(p_attempt_id) ->> 'title';
exception when others then
  return null;
end
$$;

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
  items as materialized (
    select i.*,
      case i.item_kind
        when 'topic' then (select ltp.completed_at from public.learner_topic_progress ltp
          where ltp.learner_id = v_learner and ltp.topic_id = i.topic_id)
        when 'mission' then (select pmc.verified_at from public.practice_mission_completions pmc
          where pmc.learner_id = v_learner and pmc.mission_id = i.mission_code)
        when 'coc_quiz' then (select pcp.completed_at from public.practice_coc_progress pcp
          where pcp.learner_id = v_learner and pcp.coc_code = i.coc_code)
      end as completed_at
    from private.analytics_required_items('{}'::jsonb) i
  ),
  modules as (
    select m.coc_code, m.id, count(i.item_key) as total, count(i.completed_at) as completed,
      exists (select 1 from public.learner_module_completions lmc
        where lmc.learner_id = v_learner and lmc.module_id = m.id) as recorded_complete
    from public.curriculum_modules m
    left join items i on i.module_id = m.id
    group by m.coc_code, m.id
  ),
  cocs as (
    select c.coc_code, c.title,
      (select count(*) from items i where i.coc_code = c.coc_code) as total,
      (select count(i.completed_at) from items i where i.coc_code = c.coc_code) as completed
    from (
      select lower(cm.coc_code) as coc_code, cm.title from public.coc_modules cm
      where lower(cm.coc_code) in (select m.coc_code from public.curriculum_modules m)
    ) c
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
  competency_values as (
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
  quizzes as (
    select distinct on (qa.quiz_version_id) qa.id, qa.submitted_at, qr.correct_count, qr.question_count
    from public.quiz_attempts qa
    join public.quiz_results qr on qr.quiz_attempt_id = qa.id
    where qa.learner_id = v_learner
      and qa.status = 'completed'::public.quiz_attempt_status
      and qa.submitted_at is not null
    order by qa.quiz_version_id, qa.submitted_at, qa.id
  )
  select jsonb_build_object(
    'progress', jsonb_build_object(
      'overall_percent', (select private.analytics_rate(count(i.completed_at), count(*)) from items i),
      'completed_items', (select count(i.completed_at) from items i),
      'total_items', (select count(*) from items i),
      'cocs', coalesce((
        select jsonb_agg(jsonb_build_object(
          'coc_code', c.coc_code, 'title', c.title, 'percent', private.analytics_rate(c.completed, c.total),
          'completed_items', c.completed, 'total_items', c.total,
          'modules_completed', (select count(*) from modules m where m.coc_code = c.coc_code
            and (m.recorded_complete or (m.total > 0 and m.completed = m.total))),
          'modules_total', (select count(*) from modules m where m.coc_code = c.coc_code
            and (m.total > 0 or m.recorded_complete))) order by c.coc_code)
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
          'title', h.title, 'score', case when s.status = 'graded' then s.score end, 'max_score', 100,
          'released', s.status = 'graded', 'submitted_at', s.submitted_at, 'late', s.lateness_seconds > 0)
          order by s.submitted_at desc)
        from public.homework_submissions s
        left join public.homework_assignments h on h.id = s.assignment_id
        where s.learner_id = v_learner), '[]'::jsonb)),
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'attempt_id', r.attempt_id, 'mission', r.mission_code, 'title', coalesce(r.mission_title, r.assignment_title),
        'assignment_title', r.assignment_title, 'percent', round(r.percentage, 1), 'outcome', r.outcome,
        'released_at', r.released_at) order by r.released_at desc)
      from releases r), '[]'::jsonb),
    'practice', jsonb_build_object(
      'missions_verified', (select count(*) from public.practice_mission_completions c where c.learner_id = v_learner),
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
    'updated_at', now()
  ) into v_result;
  return v_result;
end
$$;

revoke all on function private.analytics_learner_quiz_title(uuid) from public, anon;
grant execute on function private.analytics_learner_quiz_title(uuid) to authenticated, service_role;
revoke all on function public.get_my_performance() from public, anon;
grant execute on function public.get_my_performance() to authenticated, service_role;

comment on function public.get_my_performance() is
  'Objective 6 learner view: own learning progress, released criterion outcomes, quiz/homework scores, released assessment results and practice runs (SECURITY INVOKER).';

commit;
