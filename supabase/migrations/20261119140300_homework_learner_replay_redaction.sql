-- Review fix (slice A4): a learner's idempotent `submit` retry returned the
-- full submission row, including an unreleased score, feedback, criterion
-- scores and grader fields. Learner-facing submission payloads now go through
-- one redaction rule: grade fields only once the result is released.
-- manage_homework is re-declared unchanged except for the two learner
-- `submit` returns. No new SECURITY DEFINER function.
begin;
set local lock_timeout = '5s';

-- Learner view of a submission row: before release every grade, feedback,
-- criterion-score, grader and evaluation-stamp field is null.
create function private.learner_homework_submission(p_row public.homework_submissions)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select case when p_row.status = 'released' then to_jsonb(p_row)
    else to_jsonb(p_row) || jsonb_build_object(
      'score', null, 'feedback', null, 'criterion_scores', null,
      'graded_by', null, 'graded_at', null,
      'finalized_by', null, 'finalized_at', null,
      'released_by', null, 'released_at', null)
  end
$$;
revoke all on function private.learner_homework_submission(public.homework_submissions) from public, anon, authenticated;
grant execute on function private.learner_homework_submission(public.homework_submissions) to service_role;

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
    -- A retry returns the learner view: no grade fields before release.
    if found then return private.learner_homework_submission(s); end if;
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
    return private.learner_homework_submission(s);
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

notify pgrst, 'reload schema';
commit;
