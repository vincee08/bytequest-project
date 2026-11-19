-- Slice A7 (Objective 6): private SECURITY INVOKER helpers shared by every
-- analytics function. Each data source is one fact helper so a new source (or
-- a new column of an existing source) is a local change:
--   analytics_assessment_facts   technical assessment attempts (+ current release)
--   analytics_quiz_facts         one submitted attempt per learner per quiz
--   analytics_quiz_eligibility   learner x quiz pairs that were open in the period
--   analytics_homework_facts     learner x published homework pairs (+ submission)
--   analytics_practice_runs      recorded practice runs (practice_mission_runs)
--   analytics_practice_completions server-verified practice completions
--   analytics_required_items / analytics_learning_items / analytics_learner_progress
--                                learning progress (topics + missions + COC quiz)
--   analytics_last_activity      latest recorded learning activity per learner
-- All helpers run with the caller's rights, so row visibility is always the
-- caller's RLS scope. Metric definitions: docs/ANALYTICS_METRIC_DEFINITIONS.md.
begin;

-- ---------------------------------------------------------------------------
-- Filter parsing
-- ---------------------------------------------------------------------------
create or replace function private.analytics_filter_text(p_filters jsonb, p_key text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_value jsonb := p_filters -> p_key;
begin
  if v_value is null or jsonb_typeof(v_value) = 'null' then
    return null;
  end if;
  if jsonb_typeof(v_value) <> 'string' then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023',
      detail = format('Filter %s must be a string.', p_key);
  end if;
  return nullif(btrim(v_value #>> '{}'), '');
end
$$;

create or replace function private.analytics_filter_uuid(p_filters jsonb, p_key text)
returns uuid
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_text text := private.analytics_filter_text(p_filters, p_key);
begin
  if v_text is null then
    return null;
  end if;
  if v_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023',
      detail = format('Filter %s must be a UUID.', p_key);
  end if;
  return v_text::uuid;
end
$$;

create or replace function private.analytics_filter_time(p_filters jsonb, p_key text)
returns timestamptz
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_text text := private.analytics_filter_text(p_filters, p_key);
begin
  if v_text is null then
    return null;
  end if;
  -- Only ISO dates/timestamps; PostgreSQL words such as 'yesterday' are refused.
  if v_text !~ '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)?)?$' then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023',
      detail = format('Filter %s must be an ISO date or timestamp.', p_key);
  end if;
  begin
    return v_text::timestamptz;
  exception when others then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023',
      detail = format('Filter %s is not a valid date.', p_key);
  end;
end
$$;

-- ---------------------------------------------------------------------------
-- Scope: validated, normalized filters + caller role.
-- p_filters = {class_id, coc_code, module_id, topic_id, mission_code, quiz_id,
-- learner_id, from, to}. Unknown keys are rejected. Default period: last 30
-- days ending now; maximum period 366 days. Instructors are limited to the
-- active classes they own, admins to every active class.
-- ---------------------------------------------------------------------------
create or replace function private.analytics_scope(p_filters jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_role text;
  v_unknown text;
  v_class uuid;
  v_module uuid;
  v_topic uuid;
  v_quiz uuid;
  v_learner uuid;
  v_coc text;
  v_mission text;
  v_from timestamptz;
  v_to timestamptz;
  v_scope jsonb;
begin
  if auth.uid() is null then
    raise exception 'ANALYTICS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if public.is_admin() then
    v_role := 'admin';
  elsif public.is_instructor() then
    v_role := 'instructor';
  else
    raise exception 'ANALYTICS_ACCESS_DENIED' using errcode = '42501';
  end if;

  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'Filters must be a JSON object.';
  end if;
  select string_agg(k, ', ' order by k) into v_unknown
  from jsonb_object_keys(v_filters) k
  where k not in ('class_id', 'coc_code', 'module_id', 'topic_id', 'mission_code', 'quiz_id', 'learner_id', 'from', 'to');
  if v_unknown is not null then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'Unknown filter: ' || v_unknown;
  end if;

  v_class := private.analytics_filter_uuid(v_filters, 'class_id');
  v_module := private.analytics_filter_uuid(v_filters, 'module_id');
  v_topic := private.analytics_filter_uuid(v_filters, 'topic_id');
  v_quiz := private.analytics_filter_uuid(v_filters, 'quiz_id');
  v_learner := private.analytics_filter_uuid(v_filters, 'learner_id');
  v_coc := lower(private.analytics_filter_text(v_filters, 'coc_code'));
  v_mission := lower(private.analytics_filter_text(v_filters, 'mission_code'));

  if v_coc is not null and v_coc !~ '^coc[1-4]$' then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'coc_code must be coc1 to coc4.';
  end if;
  if v_mission is not null and not exists (select 1 from public.missions m where m.mission_code = v_mission) then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'Unknown mission_code.';
  end if;
  if v_module is not null and not exists (select 1 from public.curriculum_modules cm where cm.id = v_module) then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'Unknown module_id.';
  end if;
  if v_topic is not null and not exists (select 1 from public.curriculum_topics t where t.id = v_topic) then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'Unknown topic_id.';
  end if;

  v_to := coalesce(private.analytics_filter_time(v_filters, 'to'), now());
  v_from := coalesce(private.analytics_filter_time(v_filters, 'from'), v_to - interval '30 days');
  if v_from > v_to then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'from must not be after to.';
  end if;
  if v_to - v_from > interval '366 days' then
    raise exception 'ANALYTICS_FILTER_INVALID' using errcode = '22023', detail = 'The period cannot exceed 366 days.';
  end if;

  -- Under RLS an instructor only sees owned classes, so a foreign or unknown
  -- class is indistinguishable and denied with one error.
  if v_class is not null and not exists (
    select 1 from public.classes c
    where c.id = v_class and (v_role = 'admin' or c.instructor_id = (select auth.uid()))
  ) then
    raise exception 'ANALYTICS_SCOPE_DENIED' using errcode = '42501';
  end if;
  if v_quiz is not null and not exists (select 1 from public.quizzes q where q.id = v_quiz) then
    raise exception 'ANALYTICS_SCOPE_DENIED' using errcode = '42501';
  end if;

  v_scope := jsonb_build_object(
    'role', v_role,
    'class_id', v_class,
    'coc_code', v_coc,
    'module_id', v_module,
    'topic_id', v_topic,
    'mission_code', v_mission,
    'quiz_id', v_quiz,
    'learner_id', v_learner,
    'from', v_from,
    'to', v_to
  );

  -- The learner must be an active member of a class in the caller's scope
  -- (ignoring the class filter: a learner outside the selected class gives an
  -- empty, not a denied, result).
  if v_learner is not null and not exists (
    select 1 from private.analytics_members(v_scope - 'class_id' - 'learner_id') m where m.learner_id = v_learner
  ) then
    raise exception 'ANALYTICS_SCOPE_DENIED' using errcode = '42501';
  end if;

  return v_scope;
end
$$;

-- Normalized filters echoed back to clients (no role).
create or replace function private.analytics_public_filters(p_scope jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select p_scope - 'role'
$$;

-- A record positioned at (coc, module, topic, mission, quiz) matches the scope
-- only if it carries every curriculum filter that is set. A record that cannot
-- be positioned on a set filter (null) is excluded, never mixed in.
create or replace function private.analytics_matches(
  p_scope jsonb,
  p_coc text,
  p_module uuid,
  p_topic uuid,
  p_mission text,
  p_quiz uuid
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    (p_scope ->> 'coc_code' is null or p_scope ->> 'coc_code' = p_coc)
    and (p_scope ->> 'module_id' is null or (p_scope ->> 'module_id')::uuid = p_module)
    and (p_scope ->> 'topic_id' is null or (p_scope ->> 'topic_id')::uuid = p_topic)
    and (p_scope ->> 'mission_code' is null or p_scope ->> 'mission_code' = p_mission)
    and (p_scope ->> 'quiz_id' is null or (p_scope ->> 'quiz_id')::uuid = p_quiz),
    false)
$$;

-- Which curriculum dimensions each source can be positioned on today. A source
-- is not applicable when a set filter is outside its dimensions. Update here
-- when a source gains curriculum links (quizzes: modules/topics in A3;
-- homework: COC/module/mission in A4).
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
    when 'homework' then p_scope ->> 'coc_code' is null and p_scope ->> 'module_id' is null
      and p_scope ->> 'topic_id' is null and p_scope ->> 'mission_code' is null and p_scope ->> 'quiz_id' is null
    when 'learning' then p_scope ->> 'quiz_id' is null
    else false
  end
$$;

-- Percentage rounded to one decimal; null (never a division by zero) when the
-- denominator is empty.
create or replace function private.analytics_rate(p_numerator numeric, p_denominator numeric)
returns numeric
language sql
immutable
security invoker
set search_path = ''
as $$
  select case when coalesce(p_denominator, 0) > 0
    then round(coalesce(p_numerator, 0) * 100 / p_denominator, 1) end
$$;

-- Availability label of a quiz from its versions (draft = never published).
-- A3 adds an explicit availability status; switch to it at integration.
create or replace function private.analytics_quiz_status(p_quiz_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when q.archived_at is not null then 'archived'
    when exists (select 1 from public.quiz_versions v where v.quiz_id = q.id
      and v.status = 'published'::public.content_version_status) then 'published'
    when exists (select 1 from public.quiz_versions v where v.quiz_id = q.id and v.published_at is not null) then 'retired'
    else 'draft'
  end
  from public.quizzes q
  where q.id = p_quiz_id
$$;

-- ---------------------------------------------------------------------------
-- Population
-- ---------------------------------------------------------------------------
create or replace function private.analytics_classes(p_scope jsonb)
returns table (class_id uuid, title text, class_code text)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.title, c.class_code
  from public.classes c
  where c.status = 'active'::public.class_status
    and (p_scope ->> 'role' = 'admin' or c.instructor_id = (select auth.uid()))
    and (p_scope ->> 'class_id' is null or c.id = (p_scope ->> 'class_id')::uuid)
$$;

-- Active learner memberships of the scoped classes. One row per
-- (class, learner); callers use distinct learner_id for population counts.
create or replace function private.analytics_members(p_scope jsonb)
returns table (class_id uuid, learner_id uuid, enrolled_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select cm.class_id, cm.learner_id, cm.enrolled_at
  from public.class_memberships cm
  join private.analytics_classes(p_scope) c on c.class_id = cm.class_id
  join public.profiles p on p.user_id = cm.learner_id
  where cm.status = 'active'::public.membership_status
    and p.role = 'learner'::public.user_role
    and (p_scope ->> 'learner_id' is null or cm.learner_id = (p_scope ->> 'learner_id')::uuid)
$$;

-- ---------------------------------------------------------------------------
-- Source: technical assessment attempts (assessment-type assignments).
-- Attributed to the period by submission (start for unsubmitted attempts).
-- Released = a current result_releases row; pending = submitted, not released.
-- ---------------------------------------------------------------------------
create or replace function private.analytics_assessment_facts(p_scope jsonb)
returns table (
  attempt_id uuid,
  learner_id uuid,
  class_id uuid,
  assignment_id uuid,
  assignment_title text,
  mission_code text,
  mission_title text,
  coc_code text,
  module_id uuid,
  status text,
  started_at timestamptz,
  submitted_at timestamptz,
  event_at timestamptz,
  released_at timestamptz,
  score_revision_id uuid,
  outcome text,
  percentage numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select a.id, a.learner_id, a.class_id, a.assignment_id, asg.title,
    m.mission_code, m.title, lower(coc.coc_code), link.module_id,
    a.status::text, a.started_at, a.submitted_at, coalesce(a.submitted_at, a.started_at),
    rel.released_at, rel.score_revision_id, rel.outcome, rel.percentage
  from public.attempts a
  join (select distinct mb.class_id, mb.learner_id from private.analytics_members(p_scope) mb) mem
    on mem.class_id = a.class_id and mem.learner_id = a.learner_id
  join public.assignments asg
    on asg.id = a.assignment_id and asg.assignment_type = 'assessment'::public.assignment_type
  join public.activity_versions av on av.id = a.activity_version_id
  join public.missions m on m.id = av.mission_id
  join public.coc_modules coc on coc.id = m.coc_id
  left join public.mission_curriculum_links link on link.mission_code = m.mission_code
  left join lateral (
    select rr.released_at, rr.score_revision_id, sr.outcome::text as outcome, sr.percentage
    from public.result_releases rr
    join public.score_revisions sr on sr.id = rr.score_revision_id
    where rr.attempt_id = a.id and rr.is_current
    order by rr.released_at desc
    limit 1
  ) rel on true
  where coalesce(a.submitted_at, a.started_at) >= (p_scope ->> 'from')::timestamptz
    and coalesce(a.submitted_at, a.started_at) <= (p_scope ->> 'to')::timestamptz
    and private.analytics_source_applicable(p_scope, 'assessments')
    and private.analytics_matches(p_scope, lower(coc.coc_code), link.module_id, null, m.mission_code, null)
$$;

-- ---------------------------------------------------------------------------
-- Source: quizzes. Only versions that were published count, and only
-- submitted attempts (submitted_at set, by the period end). One attempt per
-- learner per quiz: the earliest submitted attempt in any class the caller can
-- analyse. class_in_scope/in_period decide whether the score is attributed to
-- the selected classes and period; completion uses the attempt regardless of
-- class because a learner has one attempt per quiz.
-- scored = a quiz_results row exists; otherwise the attempt is pending.
-- ---------------------------------------------------------------------------
create or replace function private.analytics_quiz_facts(p_scope jsonb)
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
  in_period boolean
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
      qr.quiz_attempt_id is not null as scored, qr.correct_count, qr.question_count
    from public.quiz_attempts qa
    join population p on p.learner_id = qa.learner_id
    join owned o on o.class_id = qa.class_id
    join public.quiz_versions qv on qv.id = qa.quiz_version_id
    join public.quizzes q on q.id = qv.quiz_id
    left join public.coc_modules coc on coc.id = q.coc_module_id
    left join public.quiz_results qr on qr.quiz_attempt_id = qa.id
    where qa.status in ('submitted'::public.quiz_attempt_status, 'completed'::public.quiz_attempt_status)
      and qa.submitted_at is not null
      and qa.submitted_at <= (p_scope ->> 'to')::timestamptz
      and qv.published_at is not null
      and qv.status in ('published'::public.content_version_status, 'retired'::public.content_version_status)
      and private.analytics_source_applicable(p_scope, 'quizzes')
      and private.analytics_matches(p_scope, lower(coc.coc_code), null, null, null, q.id)
    order by qa.learner_id, q.id, qa.submitted_at, qa.id
  )
  select c.id, c.learner_id, c.class_id, c.quiz_assignment_id, c.quiz_id, c.quiz_version_id, c.title, c.coc_code,
    c.status, c.submitted_at, c.scored, c.correct_count, c.question_count,
    case when c.scored and c.question_count > 0
      then round(c.correct_count::numeric * 100 / c.question_count, 4) end,
    exists (select 1 from scoped s where s.class_id = c.class_id),
    c.submitted_at >= (p_scope ->> 'from')::timestamptz
  from candidates c
$$;

-- Learner x quiz pairs for quizzes (published versions) assigned to a scoped
-- class and open at some point in the period: opened on or before the period
-- end and not due/closed before the period start. Eligibility uses current
-- active membership.
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
    and private.analytics_source_applicable(p_scope, 'quizzes')
    and private.analytics_matches(p_scope, lower(coc.coc_code), null, null, null, q.id)
$$;

-- ---------------------------------------------------------------------------
-- Source: homework. One row per (published homework, active class member).
-- Released (score visible to the learner) = status 'graded' today; A4 adds
-- finalized/released states. Score maximum is 100 until A4 adds max_score.
-- A graded submission without a score is never turned into a number.
-- Missing = deadline passed within the period (and before now) without a
-- submission by the period end.
-- ---------------------------------------------------------------------------
create or replace function private.analytics_homework_facts(p_scope jsonb)
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
  released boolean,
  score numeric,
  max_score numeric,
  percent numeric,
  open_in_period boolean,
  missing boolean,
  submitted_in_period boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select h.id, h.class_id, mb.learner_id, h.title, h.deadline_at, h.published_at,
    s.id, s.submitted_at, coalesce(s.lateness_seconds > 0, false), s.status,
    coalesce(s.status = 'graded', false),
    case when s.status = 'graded' then s.score end,
    100::numeric,
    case when s.status = 'graded' and s.score is not null then round(s.score * 100 / 100, 4) end,
    h.deadline_at is null or h.deadline_at >= (p_scope ->> 'from')::timestamptz,
    s.id is null and h.deadline_at is not null
      and h.deadline_at >= (p_scope ->> 'from')::timestamptz
      and h.deadline_at <= least((p_scope ->> 'to')::timestamptz, now()),
    coalesce(s.submitted_at >= (p_scope ->> 'from')::timestamptz, false)
  from public.homework_assignments h
  join private.analytics_members(p_scope) mb on mb.class_id = h.class_id
  left join public.homework_submissions s
    on s.assignment_id = h.id and s.learner_id = mb.learner_id
   and s.submitted_at <= (p_scope ->> 'to')::timestamptz
  where h.status = 'published'
    and h.published_at is not null
    and h.published_at <= (p_scope ->> 'to')::timestamptz
    and private.analytics_source_applicable(p_scope, 'homework')
$$;

-- ---------------------------------------------------------------------------
-- Source: recorded practice runs (server-computed, append-only). All runs up
-- to the period end; in_period marks runs that ended in the period. Practice
-- is not class-bound: a learner's runs count once per population.
-- ---------------------------------------------------------------------------
create or replace function private.analytics_practice_runs(p_scope jsonb)
returns table (
  run_id uuid,
  learner_id uuid,
  mission_code text,
  coc_code text,
  module_id uuid,
  run_number integer,
  outcome text,
  duration_seconds integer,
  action_count integer,
  invalid_count integer,
  correction_count integer,
  event_at timestamptz,
  in_period boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.id, r.learner_id, r.mission_id, left(r.mission_id, 4), link.module_id, r.run_number, r.outcome,
    r.duration_seconds, r.action_count, r.invalid_count, r.correction_count,
    coalesce(r.ended_at, r.created_at),
    coalesce(r.ended_at, r.created_at) >= (p_scope ->> 'from')::timestamptz
  from public.practice_mission_runs r
  join (select distinct mb.learner_id from private.analytics_members(p_scope) mb) pop on pop.learner_id = r.learner_id
  left join public.mission_curriculum_links link on link.mission_code = r.mission_id
  where coalesce(r.ended_at, r.created_at) <= (p_scope ->> 'to')::timestamptz
    and private.analytics_source_applicable(p_scope, 'practice')
    and private.analytics_matches(p_scope, left(r.mission_id, 4), link.module_id, null, r.mission_id, null)
$$;

-- Server-verified practice completions up to the period end (one per learner
-- and mission). Incomplete runs never create a completion.
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
    and private.analytics_source_applicable(p_scope, 'practice')
    and private.analytics_matches(p_scope, left(c.mission_id, 4), link.module_id, null, c.mission_id, null)
$$;

-- ---------------------------------------------------------------------------
-- Learning progress (WS3 methodology): required items are published topics,
-- missions placed in a module, and one COC practice quiz per COC.
-- ---------------------------------------------------------------------------
create or replace function private.analytics_required_items(p_scope jsonb)
returns table (
  item_kind text,
  item_key text,
  title text,
  coc_code text,
  module_id uuid,
  topic_id uuid,
  mission_code text,
  sequence_order integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select i.item_kind, i.item_key, i.title, i.coc_code, i.module_id, i.topic_id, i.mission_code, i.sequence_order
  from (
    select 'topic'::text as item_kind, t.id::text as item_key, rev.title, m.coc_code, m.id as module_id,
      t.id as topic_id, null::text as mission_code, t.sequence_order
    from public.curriculum_topics t
    join public.curriculum_modules m on m.id = t.module_id
    join lateral (
      select r.title
      from public.curriculum_topic_revisions r
      where r.topic_id = t.id and r.status = 'published'::public.content_publication_status
      order by r.revision_number desc
      limit 1
    ) rev on true
    where t.archived_at is null
    union all
    select 'mission', l.mission_code, ms.title, m.coc_code, m.id, null, l.mission_code, l.sequence_order
    from public.mission_curriculum_links l
    join public.curriculum_modules m on m.id = l.module_id
    join public.missions ms on ms.mission_code = l.mission_code
    union all
    select 'coc_quiz', c.coc_code, 'COC practice quiz', c.coc_code, null, null, null, 1000
    from (select distinct cm.coc_code from public.curriculum_modules cm) c
  ) i
  where private.analytics_source_applicable(p_scope, 'learning')
    and private.analytics_matches(p_scope, i.coc_code, i.module_id, i.topic_id, i.mission_code, null)
$$;

-- One row per (population learner, required item) with the completion time
-- (null = not completed by the period end).
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
          and pmc.verified_at <= (p_scope ->> 'to')::timestamptz)
      when 'coc_quiz' then (
        select pcp.completed_at from public.practice_coc_progress pcp
        where pcp.learner_id = p.learner_id and pcp.coc_code = i.coc_code
          and pcp.completed_at <= (p_scope ->> 'to')::timestamptz)
    end
  from (select distinct mb.learner_id from private.analytics_members(p_scope) mb) p
  cross join private.analytics_required_items(p_scope) i
$$;

create or replace function private.analytics_learner_progress(p_scope jsonb)
returns table (learner_id uuid, completed_items integer, total_items integer, percent numeric)
language sql
stable
security invoker
set search_path = ''
as $$
  select li.learner_id, count(li.completed_at)::integer, count(*)::integer,
    round(count(li.completed_at)::numeric * 100 / count(*), 4)
  from private.analytics_learning_items(p_scope) li
  group by li.learner_id
$$;

-- Latest recorded learning activity (any source, up to the period end) per
-- population learner. Curriculum filters do not apply: activity is activity.
create or replace function private.analytics_last_activity(p_scope jsonb)
returns table (learner_id uuid, enrolled_at timestamptz, last_activity_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  with
  population as (
    select mb.learner_id, min(mb.enrolled_at) as enrolled_at
    from private.analytics_members(p_scope) mb
    group by mb.learner_id
  ),
  owned as (select oc.class_id from private.analytics_classes(p_scope - 'class_id') oc),
  events as (
    select a.learner_id, greatest(a.started_at, a.submitted_at) as at
    from public.attempts a
    join owned o on o.class_id = a.class_id
    where a.learner_id in (select p.learner_id from population p)
    union all
    select qa.learner_id, greatest(qa.started_at, qa.submitted_at)
    from public.quiz_attempts qa
    join owned o on o.class_id = qa.class_id
    where qa.learner_id in (select p.learner_id from population p)
    union all
    select s.learner_id, s.submitted_at
    from public.homework_submissions s
    where s.learner_id in (select p.learner_id from population p)
    union all
    select r.learner_id, coalesce(r.ended_at, r.created_at)
    from public.practice_mission_runs r
    where r.learner_id in (select p.learner_id from population p)
    union all
    select c.learner_id, c.verified_at
    from public.practice_mission_completions c
    where c.learner_id in (select p.learner_id from population p)
    union all
    select t.learner_id, t.completed_at
    from public.learner_topic_progress t
    where t.learner_id in (select p.learner_id from population p)
  )
  select p.learner_id, p.enrolled_at,
    max(e.at) filter (where e.at <= (p_scope ->> 'to')::timestamptz)
  from population p
  left join events e on e.learner_id = p.learner_id
  group by p.learner_id, p.enrolled_at
$$;

-- ---------------------------------------------------------------------------
-- Per-learner metrics and status (documented thresholds):
--   falling_behind: no recorded activity for 14 days (since enrolment when the
--     learner has none), or learning progress below half of the class median
--     (highest median among the learner's scoped classes; medians are computed
--     over the whole class, independent of a learner filter).
--   struggling: quiz average below 75 %, a not-yet-competent latest released
--     result on a mission, or 3+ incomplete practice runs on one mission that
--     is still not verified.
--   on_track otherwise. Falling behind takes precedence; all reasons listed.
-- ---------------------------------------------------------------------------
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
    f.hw_submitted, f.hw_missing, f.hw_late, f.last_activity_at,
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

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'private.analytics_filter_text(jsonb, text)',
    'private.analytics_filter_uuid(jsonb, text)',
    'private.analytics_filter_time(jsonb, text)',
    'private.analytics_scope(jsonb)',
    'private.analytics_public_filters(jsonb)',
    'private.analytics_matches(jsonb, text, uuid, uuid, text, uuid)',
    'private.analytics_source_applicable(jsonb, text)',
    'private.analytics_rate(numeric, numeric)',
    'private.analytics_quiz_status(uuid)',
    'private.analytics_classes(jsonb)',
    'private.analytics_members(jsonb)',
    'private.analytics_assessment_facts(jsonb)',
    'private.analytics_quiz_facts(jsonb)',
    'private.analytics_quiz_eligibility(jsonb)',
    'private.analytics_homework_facts(jsonb)',
    'private.analytics_practice_runs(jsonb)',
    'private.analytics_practice_completions(jsonb)',
    'private.analytics_required_items(jsonb)',
    'private.analytics_learning_items(jsonb)',
    'private.analytics_learner_progress(jsonb)',
    'private.analytics_last_activity(jsonb)',
    'private.analytics_learner_metrics(jsonb)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated, service_role', v_signature);
  end loop;
end
$$;

commit;
