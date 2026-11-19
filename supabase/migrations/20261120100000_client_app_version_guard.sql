-- Final fix wave: server-side client version guard (cross-layer client
-- version marker, coordinator decision).
--
-- The installed 1.1.0 APK has no version gate. It can start a simulation
-- assessment it cannot complete, which uses up the attempt as not yet
-- competent, and an essay quiz it cannot answer. The 1.2.0+ app sends
-- x-bytequest-app-version: <semver> (kAppVersion) on every PostgREST request.
-- The server now refuses these two starts for app clients that do not
-- identify as at least public.app_release_config.min_supported_app_version.
--
-- * private.client_app_version_ok() (SECURITY INVOKER, stable). It reads the
--   header from request.headers and compares it numerically with the
--   configured minimum (major.minor.patch; build and pre-release suffixes are
--   ignored, missing parts count as zero, as the app's own parser does).
--   - A missing, unparsable or lower header from an app client is refused.
--     An app client is a signed-in request: the request role or the JWT role
--     claim is 'authenticated'. The role check uses the request settings, not
--     current_user, because the callers are SECURITY DEFINER functions.
--   - A request without the header from any other role (service role,
--     postgres, migrations, SQL suites) is not an app client and passes.
--   - A missing or malformed configured minimum falls back to 1.2.0, the
--     first version that runs simulation assessments and essay quizzes.
-- * trg_attempts_require_supported_app: SECURITY INVOKER BEFORE INSERT
--   trigger on public.attempts. An attempt on a simulation package is refused
--   before the row exists. A simulation package has a learner payload with
--   mode 'assessment' and no simulation_template, the predicate the app itself
--   uses (AuthoritativeAssessmentService.requiresAppUpdate). This covers
--   assessment and class practice assignments of the package. start_attempt
--   (a definer outside the spec section 9 list) is unchanged. Its insert is
--   the first write of a new attempt, so nothing is recorded: no attempt row,
--   no audit event, no attempt counted against the assignment.
-- * public.start_learner_quiz (spec section 9): a quiz version with a
--   delivered scenario_essay item is refused before expired attempts are
--   processed or an attempt is admitted. A resumed attempt is checked against
--   its own version. The body is otherwise identical to 20261119130200.
--
-- Error: SQLSTATE P0001, message 'APP_UPDATE_REQUIRED: Update ByteQuest to
-- version <minimum> or later to take this assessment.' (or 'this quiz.').
-- Objective-only quizzes and form-based packages keep working on 1.1.0.
begin;
set local lock_timeout = '5s';

-- major.minor.patch as integers (up to four parts); null when unparsable.
create or replace function private.app_version_parts(p_version text)
returns integer[]
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_core text := split_part(split_part(btrim(coalesce(p_version, '')), '+', 1), '-', 1);
begin
  if v_core !~ '^[0-9]{1,9}(\.[0-9]{1,9}){0,3}$' then
    return null;
  end if;
  return string_to_array(v_core, '.')::integer[];
end
$$;

comment on function private.app_version_parts(text) is
  'Numeric parts of an app version (build and pre-release suffixes ignored); null when the value is not a dotted list of up to four numbers.';

-- The configured minimum learner app version, or 1.2.0 when it is missing or
-- malformed (the first version that runs simulation assessments and essays).
create or replace function private.min_supported_app_version()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select btrim(c.value) from public.app_release_config c
      where c.key = 'min_supported_app_version'
        and private.app_version_parts(c.value) is not null),
    '1.2.0')
$$;

comment on function private.min_supported_app_version() is
  'public.app_release_config.min_supported_app_version when it parses, otherwise 1.2.0.';

create or replace function private.client_app_version_ok()
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_headers jsonb;
  v_header text;
  v_request_role text;
  v_claim_role text;
  v_client integer[];
  v_minimum integer[];
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    v_headers := null;
  end;
  if jsonb_typeof(v_headers) = 'object' then
    v_header := nullif(btrim(v_headers->>'x-bytequest-app-version'), '');
  end if;

  if v_header is null then
    -- Only a signed-in app client must identify itself. The request role
    -- survives SECURITY DEFINER calls, current_user does not.
    v_request_role := coalesce(current_setting('role', true), '');
    begin
      v_claim_role := coalesce((select auth.role()), '');
    exception when others then
      v_claim_role := '';
    end;
    return v_request_role <> 'authenticated' and v_claim_role <> 'authenticated';
  end if;

  v_client := private.app_version_parts(v_header);
  if v_client is null then
    return false;
  end if;
  v_minimum := private.app_version_parts(private.min_supported_app_version());
  -- Integer arrays compare element by element; pad both to four parts.
  return v_client || array_fill(0, array[4 - cardinality(v_client)])
    >= v_minimum || array_fill(0, array[4 - cardinality(v_minimum)]);
end
$$;

comment on function private.client_app_version_ok() is
  'False when a signed-in app client sends no, an unparsable or a lower x-bytequest-app-version header than the minimum supported app version; true for every other request.';

create or replace function private.require_supported_app_for_simulation_attempt()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
       select 1
       from public.activity_versions av
       where av.id = new.activity_version_id
         and av.learner_payload->>'mode' = 'assessment'
         and av.learner_payload->>'simulation_template' is null)
     and not private.client_app_version_ok() then
    raise exception using
      errcode = 'P0001',
      message = format('APP_UPDATE_REQUIRED: Update ByteQuest to version %s or later to take this assessment.',
        private.min_supported_app_version());
  end if;
  return new;
end
$$;

comment on function private.require_supported_app_for_simulation_attempt() is
  'Refuses an attempt on a simulation package (mode assessment, no simulation_template) from an app client older than the minimum supported version.';

drop trigger if exists trg_attempts_require_supported_app on public.attempts;
create trigger trg_attempts_require_supported_app
  before insert on public.attempts
  for each row execute function private.require_supported_app_for_simulation_attempt();

-- True when the quiz version delivers a scenario essay to learners (the
-- items start_learner_quiz returns: approved and not removed).
create or replace function private.quiz_version_has_scenario_essay(p_quiz_version_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.quiz_items qi
    where qi.quiz_version_id = p_quiz_version_id
      and qi.item_type = 'scenario_essay'::public.quiz_item_type
      and qi.review_status = 'approved'::public.quiz_item_review_status
      and qi.removed_at is null)
$$;

-- Same body as 20261119130200 plus the two version checks.
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
  v_app_supported boolean := private.client_app_version_ok();
begin
  if not public.is_learner() then
    raise exception 'LEARNER_REQUIRED' using errcode = '42501';
  end if;
  if p_client_start_key is null then raise exception 'START_KEY_REQUIRED' using errcode='22023'; end if;
  -- An app that cannot answer scenario essays is refused before anything is
  -- processed or recorded.
  if not v_app_supported and private.quiz_version_has_scenario_essay(
       (select qa.quiz_version_id from public.quiz_assignments qa where qa.id = p_assignment_id)) then
    raise exception using
      errcode = 'P0001',
      message = format('APP_UPDATE_REQUIRED: Update ByteQuest to version %s or later to take this quiz.',
        private.min_supported_app_version());
  end if;
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
    -- A resumed attempt may belong to another version of the same quiz.
    if not v_app_supported and private.quiz_version_has_scenario_essay(v_attempt.quiz_version_id) then
      raise exception using
        errcode = 'P0001',
        message = format('APP_UPDATE_REQUIRED: Update ByteQuest to version %s or later to take this quiz.',
          private.min_supported_app_version());
    end if;
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

-- Private helpers: the definer callers run as their owner; the service role
-- may insert attempts directly (fixtures, maintenance), which fires the
-- trigger as service_role.
revoke all on function private.app_version_parts(text) from public, anon, authenticated;
revoke all on function private.min_supported_app_version() from public, anon, authenticated;
revoke all on function private.client_app_version_ok() from public, anon, authenticated;
revoke all on function private.require_supported_app_for_simulation_attempt() from public, anon, authenticated;
revoke all on function private.quiz_version_has_scenario_essay(uuid) from public, anon, authenticated;
grant execute on function private.app_version_parts(text) to service_role;
grant execute on function private.min_supported_app_version() to service_role;
grant execute on function private.client_app_version_ok() to service_role;
grant execute on function private.require_supported_app_for_simulation_attempt() to service_role;
grant execute on function private.quiz_version_has_scenario_essay(uuid) to service_role;
-- create or replace keeps start_learner_quiz's owner, SECURITY DEFINER and
-- grants (authenticated only).

notify pgrst, 'reload schema';

commit;
