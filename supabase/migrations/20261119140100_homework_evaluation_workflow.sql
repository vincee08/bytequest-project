-- Homework organised by COC -> mission -> module with learning objectives,
-- criteria and a maximum score, graded through Objective 4's
-- Evaluate (grade) -> Finalize -> Release workflow.
--
-- * Grades stay editable while `graded`; `finalize` locks them; `release`
--   makes them visible. Learners read their own submission directly only while
--   it is ungraded (`submitted`) or `released`, so an unreleased grade never
--   reaches a learner client (REST, Realtime or the activities API).
-- * The "Assignment graded" notification now fires on release.
-- * Backfill: grades recorded before this workflow were already visible to
--   learners, so they become `released` with identical score and feedback
--   (finalized_at = released_at = graded_at). This is the only visible-state
--   data migration approved in spec Section 7.
-- No new SECURITY DEFINER function; manage_homework stays a service-only
-- SECURITY INVOKER function with all previous actions and payloads.
begin;
set local lock_timeout = '5s';

-- 1. Assignment curriculum links, objectives, criteria, maximum score.
alter table public.homework_assignments
  add column coc_module_id uuid references public.coc_modules(id) on delete restrict,
  add column module_id uuid references public.curriculum_modules(id) on delete restrict,
  add column mission_code text references public.missions(mission_code) on delete restrict,
  add column learning_objectives text[] not null default '{}',
  add column criteria jsonb not null default '[]'::jsonb,
  add column max_score numeric not null default 100,
  add column submission_requirements text;
alter table public.homework_assignments
  add constraint homework_assignments_max_score_check check (max_score > 0),
  add constraint homework_assignments_criteria_shape_check check (jsonb_typeof(criteria) = 'array'),
  add constraint homework_assignments_objectives_count_check check (cardinality(learning_objectives) <= 20),
  add constraint homework_assignments_requirements_check
    check (submission_requirements is null or length(submission_requirements) <= 5000);
create index homework_assignments_coc_idx on public.homework_assignments(coc_module_id);
create index homework_assignments_module_idx on public.homework_assignments(module_id);
create index homework_assignments_mission_idx on public.homework_assignments(mission_code);

-- Validates a criteria list ([{id, criterion, description, max_points}]) and
-- returns its total. Shared by the assignment trigger and manage_homework.
create function private.homework_criteria_total(p_criteria jsonb)
returns numeric
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_total numeric;
begin
  if jsonb_typeof(p_criteria) <> 'array'
     or jsonb_array_length(p_criteria) > 20
     or exists (
       select 1 from jsonb_array_elements(p_criteria) c
       where jsonb_typeof(c) <> 'object'
          or exists (select 1 from jsonb_object_keys(c) k where k not in ('id', 'criterion', 'description', 'max_points'))
          or coalesce(c->>'id', '') !~ '^[A-Za-z0-9_-]{1,64}$'
          or jsonb_typeof(c->'criterion') is distinct from 'string'
          or length(btrim(c->>'criterion')) not between 1 and 200
          or coalesce(jsonb_typeof(c->'description'), 'null') not in ('string', 'null')
          or length(coalesce(c->>'description', '')) > 1000
          or jsonb_typeof(c->'max_points') is distinct from 'number'
          or (c->>'max_points')::numeric <= 0
          or (c->>'max_points')::numeric > 1000
     )
     or (select count(*) <> count(distinct c->>'id') from jsonb_array_elements(p_criteria) c) then
    raise exception 'HOMEWORK_CRITERIA_INVALID' using errcode = '22023';
  end if;
  select coalesce(sum((c->>'max_points')::numeric), 0) into v_total from jsonb_array_elements(p_criteria) c;
  return v_total;
end
$$;

-- Validates criterion scores ({"<criterion id>": points}) against the
-- assignment criteria and returns their total.
create function private.homework_criterion_scores_total(p_criteria jsonb, p_scores jsonb)
returns numeric
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_total numeric;
begin
  if jsonb_typeof(p_scores) is distinct from 'object'
     or jsonb_array_length(p_criteria) = 0
     or (select count(*) from jsonb_object_keys(p_scores)) <> jsonb_array_length(p_criteria)
     or exists (
       select 1 from jsonb_each(p_scores) s
       left join jsonb_array_elements(p_criteria) c on c->>'id' = s.key
       where c is null
          or jsonb_typeof(s.value) <> 'number'
          or (s.value #>> '{}')::numeric < 0
          or (s.value #>> '{}')::numeric > (c->>'max_points')::numeric
     ) then
    raise exception 'HOMEWORK_CRITERION_SCORES_INVALID' using errcode = '22023';
  end if;
  select coalesce(sum((s.value #>> '{}')::numeric), 0) into v_total from jsonb_each(p_scores) s;
  return v_total;
end
$$;

create function private.validate_homework_assignment()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_total numeric := private.homework_criteria_total(new.criteria);
  v_module_coc uuid;
  v_mission_coc uuid;
begin
  if jsonb_array_length(new.criteria) > 0 and new.max_score <> v_total then
    raise exception 'HOMEWORK_MAX_SCORE_MUST_EQUAL_CRITERIA_TOTAL' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(new.learning_objectives) o where o is null or length(btrim(o)) not between 1 and 500) then
    raise exception 'HOMEWORK_OBJECTIVES_INVALID' using errcode = '22023';
  end if;
  if new.module_id is not null then
    select m.coc_module_id into v_module_coc from public.curriculum_modules m where m.id = new.module_id;
  end if;
  if new.mission_code is not null then
    select m.coc_id into v_mission_coc from public.missions m where m.mission_code = new.mission_code;
  end if;
  if (new.module_id is not null or new.mission_code is not null) and new.coc_module_id is null
     or new.coc_module_id is distinct from coalesce(v_module_coc, new.coc_module_id)
     or new.coc_module_id is distinct from coalesce(v_mission_coc, new.coc_module_id) then
    raise exception 'HOMEWORK_CURRICULUM_MISMATCH' using errcode = '22023';
  end if;
  return new;
end
$$;
create trigger validate_homework_assignment
before insert or update of criteria, max_score, learning_objectives, coc_module_id, module_id, mission_code
on public.homework_assignments
for each row execute function private.validate_homework_assignment();

-- 2. Submission lifecycle: submitted -> graded -> finalized -> released.
alter table public.homework_submissions
  add column criterion_scores jsonb,
  add column finalized_by uuid references auth.users(id) on delete restrict,
  add column finalized_at timestamptz,
  add column released_by uuid references auth.users(id) on delete restrict,
  add column released_at timestamptz;
-- Replaced additively: the status list grows, the graded-stamp rule becomes a
-- full lifecycle rule, and the fixed 0-100 score bound becomes the
-- assignment's own maximum (trigger below). Plain DROPs fail loudly if a
-- target database differs from the reviewed schema.
alter table public.homework_submissions drop constraint homework_submissions_status_check;
alter table public.homework_submissions drop constraint homework_submissions_check;
alter table public.homework_submissions drop constraint homework_submissions_score_check;
alter table public.homework_submissions
  add constraint homework_submissions_status_check
    check (status in ('submitted', 'graded', 'finalized', 'released')),
  add constraint homework_submissions_score_nonnegative_check check (score is null or score >= 0),
  add constraint homework_submissions_criterion_scores_shape_check
    check (criterion_scores is null or jsonb_typeof(criterion_scores) = 'object'),
  add constraint homework_submissions_lifecycle_check check (
    case status
      when 'submitted' then graded_at is null and graded_by is null and score is null and feedback is null
        and criterion_scores is null and finalized_at is null and finalized_by is null
        and released_at is null and released_by is null
      when 'graded' then graded_at is not null and graded_by is not null
        and finalized_at is null and finalized_by is null and released_at is null and released_by is null
      when 'finalized' then graded_at is not null and graded_by is not null
        and finalized_at is not null and finalized_by is not null and released_at is null and released_by is null
      when 'released' then graded_at is not null and graded_by is not null
        and finalized_at is not null and finalized_by is not null and released_at is not null and released_by is not null
      else false
    end
  );
create index homework_submissions_assignment_status_idx on public.homework_submissions(assignment_id, status);
create index homework_submissions_finalizer_idx on public.homework_submissions(finalized_by);
create index homework_submissions_releaser_idx on public.homework_submissions(released_by);

create function private.validate_homework_grade()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_assignment public.homework_assignments;
  v_total numeric;
begin
  if new.score is null and new.criterion_scores is null then
    return new;
  end if;
  select h.* into v_assignment from public.homework_assignments h where h.id = new.assignment_id;
  if new.score is not null and new.score > v_assignment.max_score then
    raise exception 'HOMEWORK_SCORE_EXCEEDS_MAX' using errcode = '22023';
  end if;
  if new.criterion_scores is not null then
    v_total := private.homework_criterion_scores_total(v_assignment.criteria, new.criterion_scores);
    if new.score is distinct from v_total then
      raise exception 'HOMEWORK_SCORE_MUST_EQUAL_CRITERIA_TOTAL' using errcode = '22023';
    end if;
  elsif jsonb_array_length(v_assignment.criteria) > 0 then
    raise exception 'HOMEWORK_CRITERION_SCORES_REQUIRED' using errcode = '22023';
  end if;
  return new;
end
$$;
create trigger validate_homework_grade
before insert or update of score, criterion_scores on public.homework_submissions
for each row execute function private.validate_homework_grade();

revoke all on function private.homework_criteria_total(jsonb) from public, anon, authenticated;
revoke all on function private.homework_criterion_scores_total(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.validate_homework_assignment() from public, anon, authenticated;
revoke all on function private.validate_homework_grade() from public, anon, authenticated;
grant execute on function private.homework_criteria_total(jsonb) to service_role;
grant execute on function private.homework_criterion_scores_total(jsonb, jsonb) to service_role;
grant execute on function private.validate_homework_assignment() to service_role;
grant execute on function private.validate_homework_grade() to service_role;

-- 3. Learners read their own submission directly only before grading or
-- after release. Instructors and admins keep their previous visibility. The
-- activities API reads a learner's in-evaluation submission with the service
-- client and exposes no grade fields until release.
drop policy homework_submission_read on public.homework_submissions;
create policy homework_submission_read on public.homework_submissions for select to authenticated using (
  exists (
    select 1 from public.homework_assignments h
    where h.id = homework_submissions.assignment_id
      and (
        public.is_admin()
        or public.instructor_owns_class(h.class_id)
        or (public.is_learner()
          and homework_submissions.learner_id = (select auth.uid())
          and homework_submissions.status in ('submitted', 'released'))
      )
  )
);

-- 4. Actions. Every previous action and payload keeps working; new optional
-- fields default to the previous behaviour (unlinked, max score 100).
create or replace function public.manage_homework(p_actor uuid, p_action text, p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_role public.user_role;
  h public.homework_assignments;
  s public.homework_submissions;
  f public.homework_files;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_old jsonb;
  v_now timestamptz;
  v_ids uuid[];
  v_id uuid;
  v_results jsonb := '[]'::jsonb;
  v_assignment_id uuid;
  v_coc uuid;
  v_module uuid;
  v_mission text;
  v_objectives text[];
  v_criteria jsonb;
  v_max numeric;
  v_requirements text;
  v_feedback text;
  v_score numeric;
  v_scores jsonb;
  v_total numeric;
begin
  select role into v_role from public.profiles where user_id = p_actor and status = 'active';
  if not found then raise exception 'ACTIVE_ACCOUNT_REQUIRED' using errcode = '42501'; end if;

  -- Bulk Finalize / Release across the instructor's own classes, with a
  -- result per submission (one failure never blocks the others).
  if p_action in ('finalize', 'release') then
    if v_role <> 'instructor' then
      raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
    end if;
    if jsonb_typeof(v_payload->'submission_ids') = 'array' then
      select coalesce(array_agg(x::uuid order by ord), '{}'::uuid[]) into v_ids
      from jsonb_array_elements_text(v_payload->'submission_ids') with ordinality t(x, ord);
    elsif v_payload ? 'submission_id' then
      v_ids := array[(v_payload->>'submission_id')::uuid];
    else
      v_ids := '{}'::uuid[];
    end if;
    if cardinality(v_ids) not between 1 and 50
       or cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
      raise exception 'HOMEWORK_SUBMISSION_IDS_INVALID' using errcode = '22023';
    end if;
    v_now := private.activity_server_now();
    foreach v_id in array v_ids loop
      begin
        select * into s from public.homework_submissions where id = v_id for update;
        if not found then raise exception 'SUBMISSION_NOT_FOUND' using errcode = 'P0002'; end if;
        select * into h from public.homework_assignments where id = s.assignment_id;
        if h.instructor_id <> p_actor or not exists (
          select 1 from public.classes c where c.id = h.class_id and c.instructor_id = p_actor and c.status = 'active'
        ) then
          raise exception 'HOMEWORK_SCOPE_DENIED' using errcode = '42501';
        end if;
        if p_action = 'finalize' then
          if s.status = 'graded' then
            update public.homework_submissions set status = 'finalized', finalized_by = p_actor, finalized_at = v_now
            where id = s.id returning * into s;
            insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value)
            values (p_actor, v_role, 'homework.finalized', 'homework_submission', s.id, jsonb_build_object('status', 'graded'),
              jsonb_build_object('assignment_id', h.id, 'status', s.status, 'finalized_at', s.finalized_at, 'score', s.score, 'max_score', h.max_score));
            v_results := v_results || jsonb_build_object('submission_id', s.id, 'ok', true, 'changed', true, 'status', s.status);
          elsif s.status in ('finalized', 'released') then
            v_results := v_results || jsonb_build_object('submission_id', s.id, 'ok', true, 'changed', false, 'status', s.status);
          else
            raise exception 'HOMEWORK_GRADE_REQUIRED' using errcode = '55000';
          end if;
        else
          if s.status = 'finalized' then
            update public.homework_submissions set status = 'released', released_by = p_actor, released_at = v_now
            where id = s.id returning * into s;
            -- Delivers the learner's "result released" notification.
            insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value)
            values (p_actor, v_role, 'homework.released', 'homework_submission', s.id, jsonb_build_object('status', 'finalized'),
              jsonb_build_object('assignment_id', h.id, 'status', s.status, 'released_at', s.released_at, 'score', s.score, 'max_score', h.max_score));
            v_results := v_results || jsonb_build_object('submission_id', s.id, 'ok', true, 'changed', true, 'status', s.status);
          elsif s.status = 'released' then
            v_results := v_results || jsonb_build_object('submission_id', s.id, 'ok', true, 'changed', false, 'status', s.status);
          else
            raise exception 'HOMEWORK_FINALIZE_REQUIRED' using errcode = '55000';
          end if;
        end if;
      exception when others then
        v_results := v_results || jsonb_build_object('submission_id', v_id, 'ok', false, 'error', sqlerrm, 'code', sqlstate);
      end;
    end loop;
    return jsonb_build_object(
      'action', p_action,
      'results', v_results,
      'succeeded', (select count(*) from jsonb_array_elements(v_results) r where (r->>'ok')::boolean),
      'failed', (select count(*) from jsonb_array_elements(v_results) r where not (r->>'ok')::boolean));
  end if;

  if p_action = 'create' then
    if v_role <> 'instructor' or not exists(select 1 from public.classes where id = (v_payload->>'class_id')::uuid and instructor_id = p_actor and status = 'active') then
      raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
    end if;
  else
    v_assignment_id := coalesce((v_payload->>'assignment_id')::uuid, case when p_action = 'grade' then (
      select assignment_id from public.homework_submissions where id = (v_payload->>'submission_id')::uuid) end);
    select * into h from public.homework_assignments where id = v_assignment_id for update;
    if not found then raise exception 'HOMEWORK_NOT_FOUND' using errcode = 'P0002'; end if;
    if not exists(select 1 from public.classes where id = h.class_id and status = 'active' and
      ((v_role = 'instructor' and instructor_id = p_actor) or (v_role = 'learner' and exists(
        select 1 from public.class_memberships m where m.class_id = h.class_id and m.learner_id = p_actor and m.status = 'active')))) then
      raise exception 'HOMEWORK_SCOPE_DENIED' using errcode = '42501';
    end if;
    v_old := to_jsonb(h);
    if p_action in ('edit', 'publish', 'deadline', 'grade') and (v_role <> 'instructor' or h.instructor_id <> p_actor) then
      raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
    end if;
  end if;

  if p_action in ('create', 'edit') then
    if p_action = 'edit' and h.status <> 'draft' then raise exception 'DRAFT_HOMEWORK_REQUIRED' using errcode = '55000'; end if;
    -- Absent keys keep the stored value (create: the previous defaults), so
    -- edits from older clients never clear curriculum fields.
    v_mission := case when v_payload ? 'mission_code' then nullif(btrim(v_payload->>'mission_code'), '') else h.mission_code end;
    v_module := case when v_payload ? 'module_id' then (v_payload->>'module_id')::uuid
      when v_payload ? 'mission_code' then (select l.module_id from public.mission_curriculum_links l where l.mission_code = v_mission)
      else h.module_id end;
    v_coc := case when v_payload ? 'coc_module_id' then (v_payload->>'coc_module_id')::uuid
      when v_payload ? 'mission_code' or v_payload ? 'module_id' then coalesce(
        (select m.coc_id from public.missions m where m.mission_code = v_mission),
        (select m.coc_module_id from public.curriculum_modules m where m.id = v_module))
      else h.coc_module_id end;
    if v_mission is not null and not exists (select 1 from public.missions m where m.mission_code = v_mission) then
      raise exception 'HOMEWORK_CURRICULUM_MISMATCH' using errcode = '22023';
    end if;
    if v_payload ? 'learning_objectives' then
      if jsonb_typeof(v_payload->'learning_objectives') <> 'array'
         or exists (select 1 from jsonb_array_elements(v_payload->'learning_objectives') o where jsonb_typeof(o) <> 'string') then
        raise exception 'HOMEWORK_OBJECTIVES_INVALID' using errcode = '22023';
      end if;
      select coalesce(array_agg(btrim(o) order by ord), '{}'::text[]) into v_objectives
      from jsonb_array_elements_text(v_payload->'learning_objectives') with ordinality t(o, ord)
      where btrim(o) <> '';
    else
      v_objectives := coalesce(h.learning_objectives, '{}'::text[]);
    end if;
    if v_payload ? 'criteria' then
      if jsonb_typeof(v_payload->'criteria') <> 'array'
         or exists (select 1 from jsonb_array_elements(v_payload->'criteria') c where jsonb_typeof(c) <> 'object') then
        raise exception 'HOMEWORK_CRITERIA_INVALID' using errcode = '22023';
      end if;
      select coalesce(jsonb_agg(jsonb_build_object(
          'id', coalesce(nullif(btrim(c->>'id'), ''), 'c' || ord),
          'criterion', btrim(coalesce(c->>'criterion', '')),
          'description', nullif(btrim(coalesce(c->>'description', '')), ''),
          'max_points', c->'max_points') order by ord), '[]'::jsonb)
      into v_criteria
      from jsonb_array_elements(v_payload->'criteria') with ordinality t(c, ord);
    else
      v_criteria := coalesce(h.criteria, '[]'::jsonb);
    end if;
    v_total := private.homework_criteria_total(v_criteria);
    if jsonb_array_length(v_criteria) > 0 then
      if v_payload ? 'max_score' and jsonb_typeof(v_payload->'max_score') <> 'null'
         and (v_payload->>'max_score')::numeric <> v_total then
        raise exception 'HOMEWORK_MAX_SCORE_MUST_EQUAL_CRITERIA_TOTAL' using errcode = '22023';
      end if;
      v_max := v_total;
    elsif v_payload ? 'max_score' and jsonb_typeof(v_payload->'max_score') <> 'null' then
      v_max := (v_payload->>'max_score')::numeric;
    else
      v_max := coalesce(case when v_payload ? 'criteria' then null else h.max_score end, 100);
    end if;
    if v_max <= 0 or v_max > 1000 then raise exception 'HOMEWORK_MAX_SCORE_INVALID' using errcode = '22023'; end if;
    v_requirements := case when v_payload ? 'submission_requirements'
      then nullif(btrim(coalesce(v_payload->>'submission_requirements', '')), '') else h.submission_requirements end;

    if p_action = 'create' then
      insert into public.homework_assignments(class_id, instructor_id, title, instructions, deadline_at,
        coc_module_id, module_id, mission_code, learning_objectives, criteria, max_score, submission_requirements)
      values((v_payload->>'class_id')::uuid, p_actor, btrim(v_payload->>'title'), btrim(v_payload->>'instructions'),
        (v_payload->>'deadline_at')::timestamptz, v_coc, v_module, v_mission, v_objectives, v_criteria, v_max, v_requirements)
      returning * into h;
    else
      update public.homework_assignments set title = btrim(v_payload->>'title'), instructions = btrim(v_payload->>'instructions'),
        deadline_at = (v_payload->>'deadline_at')::timestamptz, coc_module_id = v_coc, module_id = v_module, mission_code = v_mission,
        learning_objectives = v_objectives, criteria = v_criteria, max_score = v_max, submission_requirements = v_requirements,
        revision = revision + 1, updated_at = clock_timestamp()
      where id = h.id returning * into h;
    end if;
  elsif p_action = 'publish' then
    if h.status = 'published' then return to_jsonb(h); end if;
    update public.homework_assignments set status = 'published', published_at = clock_timestamp(), updated_at = clock_timestamp() where id = h.id returning * into h;
  elsif p_action = 'deadline' then
    update public.homework_assignments set deadline_at = (v_payload->>'deadline_at')::timestamptz, revision = revision + 1, updated_at = clock_timestamp()
    where id = h.id returning * into h;
  elsif p_action = 'submit' then
    if v_role <> 'learner' or h.status <> 'published' then raise exception 'PUBLISHED_HOMEWORK_REQUIRED' using errcode = '42501'; end if;
    select * into s from public.homework_submissions where assignment_id = h.id and learner_id = p_actor;
    if found then return to_jsonb(s); end if;
    select coalesce(array_agg(x::uuid), '{}'::uuid[]) into v_ids from jsonb_array_elements_text(coalesce(v_payload->'file_ids', '[]'::jsonb)) x;
    if cardinality(v_ids) > 5 or cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) or
      cardinality(v_ids) <> (select count(*) from public.homework_files where id = any(v_ids) and assignment_id = h.id and owner_id = p_actor and kind = 'answer' and submission_id is null) then
      raise exception 'HOMEWORK_FILES_INVALID' using errcode = '22023'; end if;
    if length(btrim(coalesce(v_payload->>'answer', ''))) = 0 and cardinality(v_ids) = 0 then
      raise exception 'ANSWER_OR_FILE_REQUIRED' using errcode = '22023'; end if;
    v_now := private.activity_server_now();
    insert into public.homework_submissions(assignment_id, learner_id, answer, submitted_at, effective_deadline_at, deadline_revision)
    values(h.id, p_actor, btrim(coalesce(v_payload->>'answer', '')), v_now, h.deadline_at, h.revision) returning * into s;
    update public.homework_files set submission_id = s.id where id = any(v_ids);
    insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, new_value)
    values(p_actor, v_role, 'homework.submitted', 'homework_submission', s.id, jsonb_build_object('assignment_id', h.id, 'submitted_at', s.submitted_at, 'effective_deadline_at', s.effective_deadline_at, 'lateness_seconds', s.lateness_seconds));
    return to_jsonb(s);
  elsif p_action = 'grade' then
    -- Evaluate stage: a draft grade, editable until finalized, never visible
    -- to the learner before release.
    select * into s from public.homework_submissions where id = (v_payload->>'submission_id')::uuid and assignment_id = h.id for update;
    if not found then raise exception 'SUBMISSION_NOT_FOUND' using errcode = 'P0002'; end if;
    if s.status in ('finalized', 'released') then raise exception 'HOMEWORK_GRADE_LOCKED' using errcode = '55000'; end if;
    if v_payload ? 'criterion_scores' and coalesce(jsonb_typeof(v_payload->'criterion_scores'), 'null') not in ('object', 'null') then
      raise exception 'HOMEWORK_CRITERION_SCORES_INVALID' using errcode = '22023';
    end if;
    v_feedback := nullif(btrim(v_payload->>'feedback'), '');
    v_score := (v_payload->>'score')::numeric;
    v_scores := case when jsonb_typeof(v_payload->'criterion_scores') = 'object' and v_payload->'criterion_scores' <> '{}'::jsonb
      then v_payload->'criterion_scores' end;
    if v_scores is not null then
      v_total := private.homework_criterion_scores_total(h.criteria, v_scores);
      if v_score is null then
        v_score := v_total;
      elsif v_score <> v_total then
        raise exception 'HOMEWORK_SCORE_MUST_EQUAL_CRITERIA_TOTAL' using errcode = '22023';
      end if;
    elsif v_score is not null and jsonb_array_length(h.criteria) > 0 then
      raise exception 'HOMEWORK_CRITERION_SCORES_REQUIRED' using errcode = '22023';
    end if;
    if v_score is not null and v_score < 0 then
      raise exception 'HOMEWORK_SCORE_INVALID' using errcode = '22023';
    end if;
    if v_score is not null and v_score > h.max_score then
      raise exception 'HOMEWORK_SCORE_EXCEEDS_MAX' using errcode = '22023';
    end if;
    if s.status = 'graded' and s.score is not distinct from v_score and s.feedback is not distinct from v_feedback
       and s.criterion_scores is not distinct from v_scores then
      return to_jsonb(s);
    end if;
    v_old := to_jsonb(s);
    update public.homework_submissions set status = 'graded', feedback = v_feedback, score = v_score, criterion_scores = v_scores,
      graded_by = p_actor, graded_at = private.activity_server_now()
    where id = s.id returning * into s;
    insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value)
    values(p_actor, v_role, case when v_old->>'status' = 'graded' then 'homework.grade_updated' else 'homework.graded' end,
      'homework_submission', s.id,
      case when v_old->>'status' = 'graded' then jsonb_build_object('score', v_old->'score', 'criterion_scores', v_old->'criterion_scores', 'graded_at', v_old->'graded_at') end,
      jsonb_build_object('assignment_id', h.id, 'graded_at', s.graded_at, 'score', s.score, 'criterion_scores', s.criterion_scores, 'max_score', h.max_score));
    return to_jsonb(s);
  elsif p_action = 'attach' then
    if not ((v_role = 'instructor' and h.instructor_id = p_actor and h.status = 'draft' and v_payload->>'kind' = 'instruction') or
      (v_role = 'learner' and h.status = 'published' and v_payload->>'kind' = 'answer' and not exists(
        select 1 from public.homework_submissions where assignment_id = h.id and learner_id = p_actor))) then
      raise exception 'HOMEWORK_UPLOAD_DENIED' using errcode = '42501'; end if;
    select * into f from public.homework_files where id = (v_payload->>'file_id')::uuid and owner_id = p_actor and assignment_id = h.id;
    if found then return to_jsonb(f); end if;
    if (select count(*) from public.homework_files where assignment_id = h.id and owner_id = p_actor and kind = v_payload->>'kind') >= 5 then
      raise exception 'HOMEWORK_FILE_LIMIT' using errcode = '22023'; end if;
    insert into public.homework_files(id, assignment_id, owner_id, kind, filename, object_path, mime_type, size_bytes)
    values((v_payload->>'file_id')::uuid, h.id, p_actor, v_payload->>'kind', v_payload->>'filename', v_payload->>'object_path', v_payload->>'mime_type', (v_payload->>'size_bytes')::integer) returning * into f;
    return to_jsonb(f);
  else
    raise exception 'HOMEWORK_ACTION_INVALID' using errcode = '22023';
  end if;
  insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value)
  values(p_actor, v_role, 'homework.' || p_action, 'homework_assignment', h.id, v_old, to_jsonb(h));
  return to_jsonb(h);
end
$$;
revoke all on function public.manage_homework(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.manage_homework(uuid, text, jsonb) to service_role;

-- 5. The learner's grade notification fires when the result is released.
-- (Same SECURITY INVOKER dispatcher; only the homework grading branch moves
-- from `homework.graded` to `homework.released`.)
create or replace function private.deliver_activity_notification() returns trigger
language plpgsql security invoker set search_path='' as $$
declare
  v_class uuid; v_activity uuid; v_kind text; v_title text; v_heading text;
  v_message text; v_key text; v_recipient uuid; v_class_title text;
begin
  -- The audit row is written only by the existing trusted mutation boundary.
  -- Never accept notification payloads/titles or recipients from the caller.
  if new.actor_role <> 'instructor' or not exists (
    select 1 from public.profiles where user_id=new.actor_id and role='instructor' and status='active'
  ) then return new; end if;
  if new.action='quiz.assigned' then
    select a.class_id,a.id,q.title into v_class,v_activity,v_title
    from public.quiz_assignments a join public.quiz_versions v on v.id=a.quiz_version_id
    join public.quizzes q on q.id=v.quiz_id
    where a.id=new.target_id and a.status='active' and v.status='published' and q.instructor_id=new.actor_id and q.archived_at is null;
    v_kind:='quiz'; v_heading:='New Quiz Assigned';
  elsif new.action='assignment.created' then
    select a.class_id,a.id,a.title into v_class,v_activity,v_title
    from public.assignments a join public.activity_versions v on v.id=a.activity_version_id
    where a.id=new.target_id and a.status='active' and v.status='published';
    v_kind:='technical'; v_heading:='Technical Activity Assigned';
  elsif new.action in ('homework.publish','homework.deadline') then
    if new.action='homework.deadline' and new.old_value->'deadline_at' is not distinct from new.new_value->'deadline_at' then return new; end if;
    select class_id,id,title into v_class,v_activity,v_title from public.homework_assignments
    where id=new.target_id and status='published' and instructor_id=new.actor_id;
    v_kind:='homework'; v_heading:=case when new.action='homework.publish' then 'New Homework Assignment' else 'Homework Deadline Updated' end;
  elsif new.action='homework.released' then
    select h.class_id,h.id,h.title,s.learner_id into v_class,v_activity,v_title,v_recipient
    from public.homework_submissions s join public.homework_assignments h on h.id=s.assignment_id
    where s.id=new.target_id and s.status='released' and s.released_by=new.actor_id and h.instructor_id=new.actor_id;
    v_kind:='homework'; v_heading:='Homework Result Released';
  elsif new.action in ('quiz.reopened','quiz.deadline_changed') then
    if new.old_value->'deadline' is not distinct from new.new_value->'deadline' then return new; end if;
    select a.class_id,a.id,q.title into v_class,v_activity,v_title
    from public.quiz_assignments a join public.quiz_versions v on v.id=a.quiz_version_id
    join public.quizzes q on q.id=v.quiz_id where a.id=new.target_id and a.status='active'
    and v.status='published' and q.instructor_id=new.actor_id and q.archived_at is null;
    v_kind:='quiz'; v_heading:=case when new.action='quiz.reopened' then 'Quiz Reopened' else 'Quiz Deadline Updated' end;
  else return new; end if;
  select title into v_class_title from public.classes where id=v_class and instructor_id=new.actor_id and status='active';
  if not found or v_activity is null then return new; end if;
  v_message:=case
    when new.action='homework.released' then 'Your instructor released your result for '||v_title||'.'
    when new.action='quiz.reopened' then v_title||' has been reopened. Check the updated deadline and your current attempt status.'
    when new.action in ('quiz.deadline_changed','homework.deadline') then 'Your instructor updated the deadline for '||v_title||'. Open the activity for current availability.'
    else 'Your instructor assigned '||v_title||' to '||v_class_title||'.' end;
  v_key:=new.action||':'||new.target_id::text;
  if new.action in ('quiz.reopened','quiz.deadline_changed','homework.deadline') then v_key:=v_key||':'||new.id::text; end if;
  insert into public.notifications(user_id,title,message,type,event_key,metadata,created_at)
  select m.learner_id,v_heading,v_message,'system',v_key,
    jsonb_build_object('event_type',new.action,'activity_type',v_kind,'activity_id',v_activity,'class_id',v_class,'class_title',v_class_title),
    clock_timestamp()
  from public.class_memberships m join public.profiles p on p.user_id=m.learner_id
  where m.class_id=v_class and m.status='active' and p.role='learner' and p.status='active'
    and (v_recipient is null or m.learner_id=v_recipient)
  on conflict(user_id,event_key) where event_key is not null do nothing;
  return new;
end $$;
revoke all on function private.deliver_activity_notification() from public,anon,authenticated,service_role;
drop trigger deliver_activity_notification on public.audit_events;
create trigger deliver_activity_notification after insert on public.audit_events
for each row when (new.action in ('quiz.assigned','assignment.created','homework.publish','homework.deadline','homework.released','quiz.reopened','quiz.deadline_changed'))
execute function private.deliver_activity_notification();

-- 6. Backfill: grades recorded before this workflow were already visible.
-- The cutover keeps the backfill from ever releasing a grade saved under the
-- new workflow, even if it is run again.
create table private.homework_release_cutover (
  singleton boolean primary key default true check (singleton),
  applied_at timestamptz not null default clock_timestamp()
);
alter table private.homework_release_cutover enable row level security;
revoke all on private.homework_release_cutover from public, anon, authenticated;
grant all on private.homework_release_cutover to service_role;
insert into private.homework_release_cutover default values;

create function private.release_pre_workflow_homework_grades()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cutover timestamptz;
  v_count integer;
begin
  select applied_at into v_cutover from private.homework_release_cutover;
  if v_cutover is null then raise exception 'HOMEWORK_RELEASE_CUTOVER_MISSING' using errcode = '55000'; end if;
  with released as (
    update public.homework_submissions
    set status = 'released',
        finalized_by = graded_by, finalized_at = graded_at,
        released_by = graded_by, released_at = graded_at
    where status = 'graded' and graded_at <= v_cutover
    returning id, assignment_id, score, graded_at
  )
  insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value, reason, metadata)
  select null, null, 'homework.release_backfill', 'homework_submission', r.id,
    jsonb_build_object('status', 'graded'),
    jsonb_build_object('assignment_id', r.assignment_id, 'status', 'released', 'score', r.score, 'released_at', r.graded_at),
    'Graded before the Evaluate/Finalize/Release workflow; already visible to the learner',
    jsonb_build_object('cutover', v_cutover)
  from released r;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;
revoke all on function private.release_pre_workflow_homework_grades() from public, anon, authenticated, service_role;
select private.release_pre_workflow_homework_grades();

notify pgrst, 'reload schema';
commit;
