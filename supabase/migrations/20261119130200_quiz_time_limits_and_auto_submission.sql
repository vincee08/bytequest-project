-- Re-defense WS4 (slice A3.2): server-enforced quiz time limits and automatic
-- submission of saved answers.
--
-- Effective expiry of an attempt = the earlier of (start + time limit) and the
-- class assignment's current deadline, so a deadline extended before expiry
-- also extends attempts in progress. An expired attempt is treated as
-- submitted at its effective expiry whenever the server processes it, so the
-- outcome never depends on when someone next opens the quiz. Processing runs
-- lazily at the start of every learner quiz RPC, in the instructor results
-- read path and before any deadline change (so a reopen or extension after a
-- deadline first finalises attempts that expired under the old deadline).
-- Attempts that expired before this migration (the cutover recorded below)
-- are left exactly as they are. Unanswered items score zero; nothing is
-- invented.
--
-- Changed SECURITY DEFINER functions (design Section 9 only): start_learner_quiz,
-- save_learner_quiz_answer, submit_learner_quiz, get_available_learner_quizzes,
-- get_learner_quiz_result. Everything else here is SECURITY INVOKER.
begin;
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 1. Attempt and result columns
-- ---------------------------------------------------------------------------
alter table public.quiz_attempts
  add column time_limit_minutes integer,
  add column submission_kind text not null default 'learner',
  add column evaluation_status text not null default 'not_required';
alter table public.quiz_attempts
  add constraint quiz_attempts_time_limit_check check (time_limit_minutes is null or time_limit_minutes between 1 and 240),
  add constraint quiz_attempts_submission_kind_check check (submission_kind in ('learner', 'auto_deadline', 'auto_time_limit')),
  add constraint quiz_attempts_evaluation_status_check check (evaluation_status in ('not_required', 'pending', 'evaluated', 'finalized', 'released'));
create index quiz_attempts_in_progress_assignment_idx on public.quiz_attempts(quiz_assignment_id) where status = 'in_progress';
create index quiz_attempts_evaluation_stage_idx on public.quiz_attempts(evaluation_status, submitted_at)
  where evaluation_status <> 'not_required';
comment on column public.quiz_attempts.time_limit_minutes is 'Snapshot of the version time limit when the attempt started.';
comment on column public.quiz_attempts.submission_kind is
  'learner: submitted by the learner. auto_deadline / auto_time_limit: submitted automatically at the effective expiry.';
comment on column public.quiz_attempts.evaluation_status is
  'not_required (immediate results) | pending (essays await scoring) | evaluated | finalized | released.';

alter table public.quiz_results
  add column objective_points numeric check (objective_points is null or objective_points >= 0),
  add column max_points numeric check (max_points is null or max_points > 0);

-- ---------------------------------------------------------------------------
-- 2. Cutover: attempts that expired before this release are never processed
-- ---------------------------------------------------------------------------
create table private.quiz_auto_submission_config (
  singleton boolean primary key default true check (singleton),
  cutover_at timestamptz not null
);
alter table private.quiz_auto_submission_config owner to postgres;
alter table private.quiz_auto_submission_config enable row level security;
revoke all on private.quiz_auto_submission_config from public, anon, authenticated;
grant all on private.quiz_auto_submission_config to service_role;
insert into private.quiz_auto_submission_config (cutover_at) values (clock_timestamp());
comment on table private.quiz_auto_submission_config is
  'Automatic quiz submission applies only to attempts whose effective expiry is at or after cutover_at (the time this migration ran).';

-- ---------------------------------------------------------------------------
-- 3. Expiry, grading and automatic submission (private, server-only)
-- ---------------------------------------------------------------------------
create function private.quiz_attempt_effective_expiry(p_attempt_id uuid)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
  select least(a.started_at + make_interval(mins => a.time_limit_minutes), asg.due_at)
  from public.quiz_attempts a
  join public.quiz_assignments asg on asg.id = a.quiz_assignment_id
  where a.id = p_attempt_id
$$;

-- Grades an attempt that the caller has locked and verified as in progress.
-- Objective items are graded now; essays stay for instructor scoring.
create function private.grade_quiz_attempt(
  p_attempt_id uuid,
  p_submitted_at timestamptz,
  p_submission_kind text,
  p_submission_key uuid
)
returns public.quiz_results
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_attempt public.quiz_attempts;
  v_mode text;
  v_now timestamptz := private.activity_server_now();
  v_question_count integer;
  v_correct_count integer;
  v_objective numeric;
  v_max numeric;
  v_answered_essays integer;
  v_essays integer;
  v_items jsonb;
  v_status text;
  v_result public.quiz_results;
begin
  select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id;
  select qv.result_release_mode into v_mode from public.quiz_versions qv where qv.id = v_attempt.quiz_version_id;

  update public.quiz_attempts
  set status = 'submitted'::public.quiz_attempt_status,
      submission_key = coalesce(p_submission_key, gen_random_uuid()),
      submitted_at = p_submitted_at,
      submission_kind = p_submission_kind
  where id = v_attempt.id;

  update public.quiz_answers ans set is_correct = (
    case
      when qi.item_type = 'scenario_essay'::public.quiz_item_type then null
      when qi.item_type in ('identification'::public.quiz_item_type, 'true_false'::public.quiz_item_type)
        then lower(btrim(ans.answer #>> '{}')) = lower(btrim(qi.correct_answer #>> '{}'))
      else ans.answer #>> '{}' = qi.correct_answer #>> '{}'
    end)
  from public.quiz_items qi
  where ans.quiz_attempt_id = v_attempt.id and qi.id = ans.quiz_item_id;

  select count(*)::integer,
    (count(*) filter (where ans.is_correct))::integer,
    coalesce(sum(qi.points) filter (where ans.is_correct), 0),
    coalesce(sum(qi.points), 0),
    (count(*) filter (where qi.item_type = 'scenario_essay'::public.quiz_item_type and ans.id is not null))::integer,
    (count(*) filter (where qi.item_type = 'scenario_essay'::public.quiz_item_type))::integer,
    jsonb_agg(jsonb_build_object(
      'item_id', qi.id,
      'code', qi.item_code,
      'type', qi.item_type,
      'prompt', qi.prompt,
      'learner_answer', ans.answer #>> '{}',
      'answered', ans.id is not null,
      'is_correct', case when qi.item_type = 'scenario_essay'::public.quiz_item_type then null else coalesce(ans.is_correct, false) end,
      'points', qi.points,
      'points_awarded', case when qi.item_type = 'scenario_essay'::public.quiz_item_type then null
                             when ans.is_correct then qi.points else 0 end,
      'order_index', qi.order_index
    ) order by qi.order_index)
  into v_question_count, v_correct_count, v_objective, v_max, v_answered_essays, v_essays, v_items
  from public.quiz_items qi
  left join public.quiz_answers ans on ans.quiz_attempt_id = v_attempt.id and ans.quiz_item_id = qi.id
  where qi.quiz_version_id = v_attempt.quiz_version_id
    and qi.review_status = 'approved'::public.quiz_item_review_status
    and qi.removed_at is null;

  -- Answered essays wait for rubric scoring; unanswered essays score zero.
  v_status := case
    when v_answered_essays > 0 then 'pending'
    when v_essays > 0 or v_mode = 'instructor_release' then 'evaluated'
    else 'not_required'
  end;

  insert into public.quiz_results (
    quiz_attempt_id, correct_count, question_count, item_results, evaluated_at, objective_points, max_points
  ) values (
    v_attempt.id, v_correct_count, v_question_count, coalesce(v_items, '[]'::jsonb), v_now, v_objective, nullif(v_max, 0)
  ) returning * into v_result;

  update public.quiz_attempts
  set status = 'completed'::public.quiz_attempt_status,
      completed_at = case when p_submission_kind = 'learner' then v_now else p_submitted_at end,
      evaluation_status = v_status
  where id = v_attempt.id;
  return v_result;
end
$$;

-- Processes one attempt if its effective expiry has passed (exactly once).
create function private.auto_submit_quiz_attempt(p_attempt_id uuid)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_attempt public.quiz_attempts;
  v_due timestamptz;
  v_limit_end timestamptz;
  v_expiry timestamptz;
  v_kind text;
  v_now timestamptz := private.activity_server_now();
  v_cutover timestamptz;
  v_result public.quiz_results;
begin
  select c.cutover_at into v_cutover from private.quiz_auto_submission_config c where c.singleton;
  if v_cutover is null then return false; end if;
  select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id;
  if not found or v_attempt.status <> 'in_progress'::public.quiz_attempt_status then return false; end if;
  -- Lock order shared with learner writes and deadline changes: assignment, then attempt.
  select asg.due_at into v_due from public.quiz_assignments asg where asg.id = v_attempt.quiz_assignment_id for share;
  select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id for update;
  if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then return false; end if;
  v_limit_end := v_attempt.started_at + make_interval(mins => v_attempt.time_limit_minutes);
  v_expiry := least(v_limit_end, v_due);
  if v_expiry is null or v_expiry > v_now or v_expiry < v_cutover then return false; end if;
  v_kind := case when v_limit_end is not null and (v_due is null or v_limit_end <= v_due)
                 then 'auto_time_limit' else 'auto_deadline' end;
  v_result := private.grade_quiz_attempt(v_attempt.id, v_expiry, v_kind, gen_random_uuid());
  insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, new_value, metadata)
  values (null, null, 'quiz_attempt.auto_submitted', 'quiz_attempt', v_attempt.id,
    jsonb_build_object(
      'quiz_assignment_id', v_attempt.quiz_assignment_id,
      'submitted_at', v_expiry,
      'submission_kind', v_kind,
      'correct_count', v_result.correct_count,
      'question_count', v_result.question_count,
      'answered_count', (select count(*) from public.quiz_answers ans where ans.quiz_attempt_id = v_attempt.id)),
    jsonb_build_object('system', true, 'learner_id', v_attempt.learner_id, 'processed_at', v_now, 'competency_authority', false));
  return true;
end
$$;

-- Interface: finalise every attempt (optionally of one assignment) whose
-- effective expiry has passed. Returns the number of attempts submitted.
create function private.auto_submit_expired_quiz_attempts(p_assignment_id uuid default null)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := private.activity_server_now();
  v_cutover timestamptz;
  v_id uuid;
  v_count integer := 0;
begin
  select c.cutover_at into v_cutover from private.quiz_auto_submission_config c where c.singleton;
  if v_cutover is null then return 0; end if;
  for v_id in
    select a.id
    from public.quiz_attempts a
    join public.quiz_assignments asg on asg.id = a.quiz_assignment_id
    where a.status = 'in_progress'::public.quiz_attempt_status
      and (p_assignment_id is null or a.quiz_assignment_id = p_assignment_id)
      and least(a.started_at + make_interval(mins => a.time_limit_minutes), asg.due_at) <= v_now
      and least(a.started_at + make_interval(mins => a.time_limit_minutes), asg.due_at) >= v_cutover
    order by a.quiz_assignment_id, a.id
  loop
    if private.auto_submit_quiz_attempt(v_id) then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end
$$;

-- Learner RPC entry: every assignment where this learner has an attempt in progress.
create function private.auto_submit_learner_quiz_attempts(p_learner_id uuid)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_assignment uuid;
  v_count integer := 0;
begin
  for v_assignment in
    select distinct a.quiz_assignment_id from public.quiz_attempts a
    where a.learner_id = p_learner_id and a.status = 'in_progress'::public.quiz_attempt_status
    order by 1
  loop
    v_count := v_count + private.auto_submit_expired_quiz_attempts(v_assignment);
  end loop;
  return v_count;
end
$$;

-- Learner-facing payloads. Totals stay hidden until results are visible.
create function private.learner_quiz_submission_payload(p_attempt_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
      'attempt_id', a.id,
      'status', a.status,
      'submitted_at', a.submitted_at,
      'submission_kind', a.submission_kind,
      'evaluation_status', a.evaluation_status,
      'evaluated_at', r.evaluated_at,
      'question_count', r.question_count,
      'result_visible', a.evaluation_status in ('not_required', 'released'))
    || case when a.evaluation_status in ('not_required', 'released')
         then jsonb_build_object('correct_count', r.correct_count, 'objective_points', r.objective_points, 'max_points', r.max_points)
         else '{}'::jsonb end
  from public.quiz_attempts a
  left join public.quiz_results r on r.quiz_attempt_id = a.id
  where a.id = p_attempt_id
$$;

create function private.learner_quiz_result_payload(p_attempt_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_attempt public.quiz_attempts;
  v_result public.quiz_results;
  v_visible boolean;
  v_payload jsonb;
begin
  select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id;
  select r.* into v_result from public.quiz_results r where r.quiz_attempt_id = p_attempt_id;
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
    || case when v_visible then jsonb_build_object(
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

revoke all on function private.quiz_attempt_effective_expiry(uuid) from public, anon, authenticated;
revoke all on function private.grade_quiz_attempt(uuid, timestamptz, text, uuid) from public, anon, authenticated;
revoke all on function private.auto_submit_quiz_attempt(uuid) from public, anon, authenticated;
revoke all on function private.auto_submit_expired_quiz_attempts(uuid) from public, anon, authenticated;
revoke all on function private.auto_submit_learner_quiz_attempts(uuid) from public, anon, authenticated;
revoke all on function private.learner_quiz_submission_payload(uuid) from public, anon, authenticated;
revoke all on function private.learner_quiz_result_payload(uuid) from public, anon, authenticated;
-- Server-side callers (deadline changes, instructor result reads) run as service_role.
grant execute on function private.quiz_attempt_effective_expiry(uuid) to service_role;
grant execute on function private.grade_quiz_attempt(uuid, timestamptz, text, uuid) to service_role;
grant execute on function private.auto_submit_quiz_attempt(uuid) to service_role;
grant execute on function private.auto_submit_expired_quiz_attempts(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Learner RPCs (definer functions approved in design Section 9)
-- ---------------------------------------------------------------------------
create or replace function public.get_available_learner_quizzes()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_learner uuid := (select auth.uid());
  v_now timestamptz;
  v_payload jsonb;
begin
  if not public.is_learner() then return jsonb_build_object('error', 'LEARNER_REQUIRED'); end if;
  perform private.auto_submit_learner_quiz_attempts(v_learner);
  v_now := private.activity_server_now();
  select coalesce(jsonb_agg(payload order by class_title, title), '[]'::jsonb) into v_payload from (
    select distinct on (q.id) jsonb_build_object(
      'assignment_id', a.id,
      'eligible_assignments', (
        select coalesce(jsonb_agg(jsonb_build_object('assignment_id', link.id, 'class_id', link.class_id) order by link.id), '[]'::jsonb)
        from public.quiz_assignments link
        join public.quiz_versions linked_version on linked_version.id = link.quiz_version_id
        join public.classes linked_class on linked_class.id = link.class_id and linked_class.status = 'active'
        join public.class_memberships member on member.class_id = link.class_id and member.learner_id = v_learner and member.status = 'active'
        where linked_version.quiz_id = q.id and link.status = 'active'
          and (linked_version.status = 'published' or link.id = latest.quiz_assignment_id)),
      'quiz_version_id', coalesce(latest.quiz_version_id, a.quiz_version_id),
      'quiz_id', q.id, 'title', q.title, 'description', q.description, 'topic', q.topic,
      'focus', q.focus, 'quiz_type', q.quiz_type, 'difficulty', q.difficulty,
      'module_codes', (
        select coalesce(jsonb_agg(m.code order by m.sequence_order), '[]'::jsonb)
        from public.quiz_modules qm join public.curriculum_modules m on m.id = qm.module_id where qm.quiz_id = q.id),
      'instructions', coalesce(a.instructions, qv.instructions), 'class_id', c.id, 'class_title', c.title,
      'coc_code', cm.coc_code, 'coc_title', cm.title,
      'question_count', (select count(*) from public.quiz_items qi where qi.quiz_version_id = coalesce(latest.quiz_version_id, qv.id)
        and qi.removed_at is null and qi.review_status = 'approved'),
      'essay_count', (select count(*) from public.quiz_items qi where qi.quiz_version_id = coalesce(latest.quiz_version_id, qv.id)
        and qi.removed_at is null and qi.review_status = 'approved' and qi.item_type = 'scenario_essay'),
      'available_at', a.available_at, 'due_at', effective.due_at, 'server_now', v_now,
      'closed_reason', case when effective.due_at <= v_now then 'deadline_passed' else null end,
      'attempts_allowed', 1,
      'is_available', avail.ok,
      'time_limit_minutes', case when latest.id is not null then latest.time_limit_minutes else qv.time_limit_minutes end,
      'result_release_mode', av.result_release_mode,
      'expires_at', case when latest.status = 'in_progress'
        then least(latest.started_at + make_interval(mins => latest.time_limit_minutes), effective.due_at) end,
      'attempt_id', latest.id, 'attempt_status', latest.status, 'answered_count', coalesce(latest.answered_count, 0),
      'started_at', latest.started_at, 'submitted_at', latest.submitted_at, 'completed_at', latest.completed_at,
      'submission_kind', case when latest.status <> 'in_progress' then latest.submission_kind end,
      'evaluation_status', latest.evaluation_status,
      'status', case
        when latest.id is null then case
          when avail.ok then 'not_started'
          when effective.due_at is not null and effective.due_at <= v_now then 'closed'
          else 'unavailable' end
        when latest.status = 'in_progress' then case
          when avail.ok and coalesce(least(latest.started_at + make_interval(mins => latest.time_limit_minutes), effective.due_at) > v_now, true)
            then 'in_progress' else 'closed' end
        when latest.evaluation_status in ('pending', 'evaluated', 'finalized') then 'awaiting_evaluation'
        when latest.evaluation_status = 'released' then 'released'
        else 'completed' end
    ) payload, c.title class_title, q.title title
    from public.quiz_assignments a
    join public.quiz_versions qv on qv.id = a.quiz_version_id
    join public.quizzes q on q.id = qv.quiz_id
    join public.classes c on c.id = a.class_id
    join public.class_memberships membership on membership.class_id = a.class_id
      and membership.learner_id = v_learner and membership.status = 'active'
    left join public.coc_modules cm on cm.id = q.coc_module_id
    left join lateral (
      select qa.id, qa.quiz_version_id, qa.quiz_assignment_id, qa.status, qa.started_at, qa.submitted_at, qa.completed_at,
        qa.time_limit_minutes, qa.submission_kind, qa.evaluation_status,
        (select count(*) from public.quiz_answers ans where ans.quiz_attempt_id = qa.id) answered_count
      from private.quiz_attempt_claims claim join public.quiz_attempts qa on qa.id = claim.attempt_id
      where claim.quiz_id = q.id and qa.learner_id = v_learner
      order by (qa.status = 'in_progress') desc, qa.started_at desc limit 1
    ) latest on true
    join public.quiz_assignments effective on effective.id = coalesce(latest.quiz_assignment_id, a.id)
    join public.quiz_versions av on av.id = coalesce(latest.quiz_version_id, qv.id)
    cross join lateral (
      select private.quiz_assignment_is_available(coalesce(latest.quiz_assignment_id, a.id), v_learner) ok
    ) avail
    where a.status = 'active' and (qv.status = 'published' or exists (
      select 1 from private.quiz_attempt_claims claim join public.quiz_attempts attempt on attempt.id = claim.attempt_id
      where claim.learner_id = v_learner and claim.quiz_id = q.id and attempt.quiz_assignment_id = a.id))
      and q.archived_at is null and c.status = 'active'
    order by q.id, (latest.quiz_assignment_id = a.id) desc nulls last, qv.version_number desc, c.title, a.id
  ) scoped;
  return v_payload;
end
$$;

create or replace function public.start_learner_quiz(
  p_assignment_id uuid,
  p_client_start_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_learner uuid := (select auth.uid());
  v_assignment public.quiz_assignments;
  v_attempt public.quiz_attempts;
  v_admitted_at timestamptz;
  v_quiz_id uuid;
  v_payload jsonb;
begin
  if not public.is_learner() then
    raise exception 'LEARNER_REQUIRED' using errcode = '42501';
  end if;
  if p_client_start_key is null then raise exception 'START_KEY_REQUIRED' using errcode='22023'; end if;
  -- Attempts whose time ran out become final before anything else is decided.
  perform private.auto_submit_learner_quiz_attempts(v_learner);
  if not private.quiz_assignment_is_available(p_assignment_id, v_learner) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode = '42501';
  end if;

  select * into v_assignment from public.quiz_assignments where id=p_assignment_id for share;
  select quiz_id into v_quiz_id from public.quiz_versions where id=v_assignment.quiz_version_id;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_learner::text || ':' || v_quiz_id::text, 0));
  select qa.* into v_attempt from private.quiz_attempt_claims claim
    join public.quiz_attempts qa on qa.id=claim.attempt_id
    where claim.learner_id=v_learner and claim.quiz_id=v_quiz_id;
  if found then
    if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then
      raise exception 'QUIZ_ATTEMPT_ALREADY_SUBMITTED' using errcode='55000';
    end if;
    perform 1 from public.quiz_assignments where id=v_attempt.quiz_assignment_id for share;
    if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id, v_learner)
       or coalesce(private.quiz_attempt_effective_expiry(v_attempt.id) <= private.activity_server_now(), false) then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
    end if;
  else
    -- Recheck access after waiting for a concurrent start/publication.
    if not private.quiz_assignment_is_available(p_assignment_id, v_learner) then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
    end if;
    v_admitted_at:=private.activity_server_now();
    if not private.quiz_assignment_is_available(p_assignment_id, v_learner) then raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501'; end if;
    insert into public.quiz_attempts(learner_id,class_id,quiz_assignment_id,quiz_version_id,client_start_key,started_at,time_limit_minutes)
    values(v_learner,v_assignment.class_id,v_assignment.id,v_assignment.quiz_version_id,p_client_start_key,v_admitted_at,
      (select qv.time_limit_minutes from public.quiz_versions qv where qv.id=v_assignment.quiz_version_id))
    returning * into v_attempt;
    perform private.write_audit_event('quiz_attempt.started','quiz_attempt',v_attempt.id,null,
      jsonb_build_object('assignment_id',v_assignment.id,'quiz_version_id',v_assignment.quiz_version_id,'quiz_id',v_quiz_id,
        'time_limit_minutes',v_attempt.time_limit_minutes));
  end if;

  select jsonb_build_object(
    'attempt_id', v_attempt.id,
    'status', v_attempt.status,
    'started_at', v_attempt.started_at,
    'server_now', private.activity_server_now(),
    'due_at', a.due_at,
    'time_limit_minutes', v_attempt.time_limit_minutes,
    'expires_at', private.quiz_attempt_effective_expiry(v_attempt.id),
    'result_release_mode', qv.result_release_mode,
    'quiz', jsonb_build_object(
      'assignment_id', a.id,
      'title', q.title,
      'description', q.description,
      'topic', q.topic,
      'focus', q.focus,
      'instructions', coalesce(a.instructions, qv.instructions),
      'class_title', c.title,
      'version_number', qv.version_number
    ),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', qi.id,
        'code', qi.item_code,
        'type', qi.item_type,
        'prompt', qi.prompt,
        'options', qi.options,
        'order_index', qi.order_index,
        'saved_answer', ans.answer #>> '{}',
        'points', qi.points,
        'scenario', qi.scenario,
        'min_words', qi.min_words,
        'max_words', qi.max_words,
        'max_answer_length', case when qi.item_type = 'scenario_essay'::public.quiz_item_type then 10000 else 2000 end,
        -- Criterion names and points only: descriptors can describe the expected answer.
        'rubric', case when qi.item_type = 'scenario_essay'::public.quiz_item_type then (
          select jsonb_agg(jsonb_build_object('id', crit->'id', 'criterion', crit->'criterion', 'max_points', crit->'max_points'))
          from jsonb_array_elements(qi.rubric) crit) end
      ) order by qi.order_index)
      from public.quiz_items qi
      left join public.quiz_answers ans
        on ans.quiz_attempt_id = v_attempt.id and ans.quiz_item_id = qi.id
      where qi.quiz_version_id = v_attempt.quiz_version_id
        and qi.review_status = 'approved'::public.quiz_item_review_status
        and qi.removed_at is null
    ), '[]'::jsonb)
  ) into v_payload
  from public.quiz_assignments a
  join public.quiz_versions qv on qv.id = a.quiz_version_id
  join public.quizzes q on q.id = qv.quiz_id
  join public.classes c on c.id = a.class_id
  where a.id = v_attempt.quiz_assignment_id;

  return v_payload;
end
$$;

create or replace function public.save_learner_quiz_answer(
  p_attempt_id uuid,
  p_item_id uuid,
  p_answer text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_learner uuid := (select auth.uid());
  v_text text := btrim(coalesce(p_answer, ''));
  v_assignment uuid;
  v_attempt public.quiz_attempts;
  v_item public.quiz_items;
  v_expiry timestamptz;
  v_admitted_at timestamptz;
  v_answer public.quiz_answers;
begin
  if not public.is_learner() then raise exception 'LEARNER_REQUIRED' using errcode = '42501'; end if;
  if length(v_text) not between 1 and 10000 then
    raise exception 'QUIZ_ANSWER_REQUIRED' using errcode = '22023';
  end if;
  select a.quiz_assignment_id into v_assignment from public.quiz_attempts a
  where a.id = p_attempt_id and a.learner_id = v_learner;
  if not found then raise exception 'QUIZ_ATTEMPT_NOT_FOUND' using errcode = 'P0002'; end if;
  perform private.auto_submit_expired_quiz_attempts(v_assignment);
  perform 1 from public.quiz_assignments where id = v_assignment for share;
  select * into v_attempt from public.quiz_attempts where id = p_attempt_id for update;
  if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then
    if v_attempt.submission_kind <> 'learner' then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode = '42501', detail = 'QUIZ_ATTEMPT_EXPIRED';
    end if;
    raise exception 'QUIZ_ATTEMPT_ALREADY_SUBMITTED' using errcode = '55000';
  end if;
  if not exists(select 1 from private.quiz_attempt_claims where learner_id=v_learner and attempt_id=v_attempt.id) then
    raise exception 'QUIZ_ATTEMPT_ALREADY_USED' using errcode='55000';
  end if;
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id, v_learner) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  v_expiry := private.quiz_attempt_effective_expiry(v_attempt.id);
  if v_expiry is not null and v_expiry <= private.activity_server_now() then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode = '42501', detail = 'QUIZ_ATTEMPT_EXPIRED';
  end if;
  select qi.* into v_item from public.quiz_items qi
  where qi.id = p_item_id
    and qi.quiz_version_id = v_attempt.quiz_version_id
    and qi.review_status = 'approved'::public.quiz_item_review_status
    and qi.removed_at is null;
  if not found then raise exception 'QUIZ_ITEM_NOT_AVAILABLE' using errcode = '42501'; end if;
  if v_item.item_type <> 'scenario_essay'::public.quiz_item_type and length(v_text) > 2000 then
    raise exception 'QUIZ_ANSWER_REQUIRED' using errcode = '22023';
  end if;

  v_admitted_at:=private.activity_server_now();
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id, v_learner)
     or (v_expiry is not null and v_expiry <= v_admitted_at) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  insert into public.quiz_answers(
    quiz_attempt_id, quiz_item_id, quiz_version_id, answer, answered_at
  ) values(
    v_attempt.id, p_item_id, v_attempt.quiz_version_id, to_jsonb(v_text), v_admitted_at
  )
  on conflict (quiz_attempt_id, quiz_item_id)
  do update set answer = excluded.answer, is_correct = null, answered_at = v_admitted_at
  returning * into v_answer;
  return jsonb_build_object(
    'attempt_id', v_attempt.id,
    'item_id', p_item_id,
    'saved', true,
    'answered_at', v_answer.answered_at,
    'expires_at', v_expiry
  );
end
$$;

create or replace function public.submit_learner_quiz(
  p_attempt_id uuid,
  p_submission_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_learner uuid := (select auth.uid());
  v_assignment uuid;
  v_attempt public.quiz_attempts;
  v_expiry timestamptz;
  v_admitted_at timestamptz;
  v_question_count integer;
  v_answer_count integer;
  v_result public.quiz_results;
begin
  if not public.is_learner() then raise exception 'LEARNER_REQUIRED' using errcode = '42501'; end if;
  select a.quiz_assignment_id into v_assignment from public.quiz_attempts a
  where a.id = p_attempt_id and a.learner_id = v_learner;
  if not found then raise exception 'QUIZ_ATTEMPT_NOT_FOUND' using errcode = 'P0002'; end if;
  -- After expiry the saved answers are submitted automatically; return that result.
  perform private.auto_submit_expired_quiz_attempts(v_assignment);
  perform 1 from public.quiz_assignments where id = v_assignment for share;
  select * into v_attempt from public.quiz_attempts where id = p_attempt_id for update;

  if v_attempt.status = 'completed'::public.quiz_attempt_status then
    return private.learner_quiz_submission_payload(v_attempt.id);
  end if;
  if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then
    raise exception 'QUIZ_SUBMISSION_IN_PROGRESS' using errcode = '55000';
  end if;
  if not exists(select 1 from private.quiz_attempt_claims where learner_id=v_learner and attempt_id=v_attempt.id) then
    raise exception 'QUIZ_ATTEMPT_ALREADY_USED' using errcode='55000';
  end if;
  v_expiry := private.quiz_attempt_effective_expiry(v_attempt.id);
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id, v_learner)
     or (v_expiry is not null and v_expiry <= private.activity_server_now()) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  select count(*) into v_question_count from public.quiz_items qi
  where qi.quiz_version_id = v_attempt.quiz_version_id
    and qi.review_status = 'approved'::public.quiz_item_review_status
    and qi.removed_at is null;
  select count(*) into v_answer_count from public.quiz_answers qa
  where qa.quiz_attempt_id = v_attempt.id;
  if v_question_count < 1 or v_answer_count <> v_question_count then
    raise exception 'ANSWER_EVERY_QUESTION_BEFORE_SUBMISSION' using errcode = '22023';
  end if;

  v_admitted_at:=private.activity_server_now();
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id, v_learner)
     or (v_expiry is not null and v_expiry <= v_admitted_at) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  v_result := private.grade_quiz_attempt(v_attempt.id, v_admitted_at, 'learner', p_submission_key);

  perform private.write_audit_event(
    'quiz_attempt.completed', 'quiz_attempt', v_attempt.id, null,
    jsonb_build_object(
      'quiz_assignment_id', v_attempt.quiz_assignment_id,
      'correct_count', v_result.correct_count,
      'question_count', v_result.question_count,
      'objective_points', v_result.objective_points,
      'max_points', v_result.max_points,
      'evaluation_status', (select evaluation_status from public.quiz_attempts where id = v_attempt.id)
    ), null, jsonb_build_object('competency_authority', false)
  );
  return private.learner_quiz_submission_payload(v_attempt.id);
end
$$;

create or replace function public.get_learner_quiz_result(p_attempt_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_attempt public.quiz_attempts;
begin
  if not public.is_learner() then raise exception 'LEARNER_REQUIRED' using errcode = '42501'; end if;
  select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id and a.learner_id = (select auth.uid());
  if found and v_attempt.status = 'in_progress'::public.quiz_attempt_status then
    perform private.auto_submit_expired_quiz_attempts(v_attempt.quiz_assignment_id);
    select a.* into v_attempt from public.quiz_attempts a where a.id = p_attempt_id;
  end if;
  if v_attempt.id is null or v_attempt.status <> 'completed'::public.quiz_attempt_status then
    raise exception 'QUIZ_RESULT_NOT_AVAILABLE' using errcode = 'P0002';
  end if;
  return private.learner_quiz_result_payload(v_attempt.id);
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Deadline changes and "Close now" (service-only invoker, existing route)
-- ---------------------------------------------------------------------------
revoke all on function public.set_quiz_assignment_deadline(uuid,uuid,timestamptz,boolean) from public,anon,authenticated,service_role;
drop function public.set_quiz_assignment_deadline(uuid,uuid,timestamptz,boolean);
create function public.set_quiz_assignment_deadline(
  p_actor uuid,
  p_assignment_id uuid,
  p_deadline timestamptz,
  p_reopen boolean default false,
  p_close_now boolean default false
)
returns public.quiz_assignments language plpgsql security invoker set search_path='' as $$
declare a public.quiz_assignments; v_old timestamptz; v_now timestamptz; v_quiz uuid; v_finalized integer;
begin
  select * into a from public.quiz_assignments where id=p_assignment_id for update;
  if not found then raise exception 'QUIZ_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  if not exists(select 1 from public.profiles p join public.classes c on c.instructor_id=p.user_id
    join public.quiz_versions v on v.id=a.quiz_version_id join public.quizzes q on q.id=v.quiz_id
    where p.user_id=p_actor and p.role='instructor' and p.status='active' and c.id=a.class_id and c.status='active'
      and q.instructor_id=p_actor and q.archived_at is null and v.status='published') or a.status<>'active' then
    raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode='42501'; end if;
  v_now:=private.activity_server_now(); v_old:=a.due_at;
  -- Attempts that expired under the deadline in force are final before it changes,
  -- so a reopen or extension after expiry never revives them.
  v_finalized:=private.auto_submit_expired_quiz_attempts(a.id);
  select quiz_id into v_quiz from public.quiz_versions where id=a.quiz_version_id;
  if coalesce(p_close_now,false) then
    if coalesce(p_reopen,false) then raise exception 'CLOSE_OR_REOPEN_REQUIRED' using errcode='22023'; end if;
    if a.due_at is not null and a.due_at<=v_now then raise exception 'QUIZ_ALREADY_CLOSED' using errcode='22023'; end if;
    if a.available_at is not null and a.available_at>=v_now then raise exception 'QUIZ_NOT_YET_OPEN' using errcode='22023'; end if;
    update public.quiz_assignments set due_at=v_now where id=a.id returning * into a;
    insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,old_value,new_value,metadata,created_at)
    values(p_actor,'instructor','quiz.deadline_changed','quiz_assignment',a.id,
      jsonb_build_object('deadline',v_old),jsonb_build_object('deadline',v_now),
      jsonb_build_object('quiz_id',v_quiz,'class_id',a.class_id,'closed_now',true,'finalized_before_change',v_finalized),v_now);
    -- Attempts in progress end at the close time with their saved answers.
    perform private.auto_submit_expired_quiz_attempts(a.id);
    return a;
  end if;
  if p_deadline is not null and (p_deadline<=v_now or (a.available_at is not null and p_deadline<=a.available_at)) then
    raise exception 'FUTURE_DEADLINE_REQUIRED' using errcode='22023'; end if;
  if p_reopen and (a.due_at is null or a.due_at>v_now or p_deadline is null) then
    raise exception 'EXPIRED_QUIZ_AND_FUTURE_DEADLINE_REQUIRED' using errcode='22023'; end if;
  if not p_reopen and a.due_at is not null and a.due_at<=v_now then
    raise exception 'USE_REOPEN_QUIZ' using errcode='22023'; end if;
  update public.quiz_assignments set due_at=p_deadline where id=a.id returning * into a;
  insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,old_value,new_value,metadata,created_at)
  values(p_actor,'instructor',case when p_reopen then 'quiz.reopened' else 'quiz.deadline_changed' end,'quiz_assignment',a.id,
    jsonb_build_object('deadline',v_old),jsonb_build_object('deadline',p_deadline),
    jsonb_build_object('quiz_id',v_quiz,'class_id',a.class_id,'reopened_at',case when p_reopen then v_now end,
      'finalized_before_change',v_finalized),v_now);
  return a;
end $$;
revoke all on function public.set_quiz_assignment_deadline(uuid,uuid,timestamptz,boolean,boolean) from public,anon,authenticated;
grant execute on function public.set_quiz_assignment_deadline(uuid,uuid,timestamptz,boolean,boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Instructor results read path (service-only invoker behind the dashboard)
-- ---------------------------------------------------------------------------
create function public.process_expired_quiz_attempts(p_actor uuid, p_quiz_id uuid default null)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_role public.user_role;
  v_assignment uuid;
  v_count integer := 0;
begin
  select p.role into v_role from public.profiles p where p.user_id = p_actor and p.status = 'active';
  if v_role is null or v_role not in ('instructor'::public.user_role, 'admin'::public.user_role) then
    raise exception 'STAFF_REQUIRED' using errcode = '42501';
  end if;
  if p_quiz_id is not null and v_role = 'instructor'::public.user_role
     and not exists (select 1 from public.quizzes q where q.id = p_quiz_id and q.instructor_id = p_actor) then
    raise exception 'QUIZ_SCOPE_DENIED' using errcode = '42501';
  end if;
  for v_assignment in
    select a.id
    from public.quiz_assignments a
    join public.quiz_versions v on v.id = a.quiz_version_id
    join public.quizzes q on q.id = v.quiz_id
    join public.classes c on c.id = a.class_id
    where (p_quiz_id is null or q.id = p_quiz_id)
      and (v_role = 'admin'::public.user_role or c.instructor_id = p_actor or q.instructor_id = p_actor)
      and exists (select 1 from public.quiz_attempts t where t.quiz_assignment_id = a.id and t.status = 'in_progress'::public.quiz_attempt_status)
    order by a.id
  loop
    v_count := v_count + private.auto_submit_expired_quiz_attempts(v_assignment);
  end loop;
  return v_count;
end
$$;
revoke all on function public.process_expired_quiz_attempts(uuid, uuid) from public, anon, authenticated;
grant execute on function public.process_expired_quiz_attempts(uuid, uuid) to service_role;

notify pgrst, 'reload schema';
commit;
