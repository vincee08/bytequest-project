-- Re-defense revision WS1 (slice A2.2): curriculum content publication
-- workflow (owner decision 2).
--
--   draft -> submitted -> evaluated (passed) | needs_revision -> finalized
--         -> approved -> published -> unpublished -> published (republish)
--   archive_topic retires a topic and every revision.
--
-- | Action        | Who                          | From                     |
-- |---------------|------------------------------|--------------------------|
-- | create_topic  | instructor or admin          | (new topic, revision 1)  |
-- | edit_revision | revision author, topic       | draft, needs_revision    |
-- |               | creator, or admin            | (in place); published or |
-- |               |                              | unpublished (new draft)  |
-- | submit        | revision author              | draft, needs_revision    |
-- | evaluate      | admin (notes >= 10 chars)    | submitted                |
-- | finalize      | revision author or admin     | evaluated                |
-- | approve       | admin                        | finalized                |
-- | publish       | admin                        | approved, unpublished    |
-- | unpublish     | admin                        | published                |
-- | archive_topic | admin                        | any non-archived topic   |
-- | complete_topic| learner, published topic in  | -                        |
-- |               | an unlocked module           |                          |
--
-- Learners only ever read the published revision (RLS from the foundation);
-- a new draft never hides it. Every transition appends a
-- content_publication_events row and an audit_events row. Service-only
-- SECURITY INVOKER function: the authenticated dashboard/mobile routes call it
-- with the service role after verifying the caller.

begin;

create function public.manage_curriculum_content(p_actor uuid, p_action text, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_role public.user_role;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_topic public.curriculum_topics;
  v_revision public.curriculum_topic_revisions;
  v_old public.curriculum_topic_revisions;
  v_other public.curriculum_topic_revisions;
  v_module public.curriculum_modules;
  v_progress public.learner_topic_progress;
  v_title text;
  v_summary text;
  v_body text;
  v_outcomes uuid[];
  v_notes text;
  v_result text;
  v_learner uuid;
begin
  select p.role into v_role
  from public.profiles p
  where p.user_id = p_actor and p.status = 'active'::public.account_status;
  if not found then
    raise exception 'ACTIVE_ACCOUNT_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'CURRICULUM_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  -- -------------------------------------------------------------------------
  -- Learner: record topic completion
  -- -------------------------------------------------------------------------
  if p_action = 'complete_topic' then
    if v_role <> 'learner'::public.user_role then
      raise exception 'LEARNER_REQUIRED' using errcode = '42501';
    end if;
    select * into v_topic from public.curriculum_topics where id = (v_payload->>'topic_id')::uuid;
    if not found or v_topic.archived_at is not null then
      raise exception 'TOPIC_NOT_FOUND' using errcode = 'P0002';
    end if;
    select * into v_revision from public.curriculum_topic_revisions
    where topic_id = v_topic.id and status = 'published'::public.content_publication_status
    order by revision_number desc limit 1;
    if not found then
      raise exception 'TOPIC_NOT_PUBLISHED' using errcode = 'P0002';
    end if;
    select * into v_module from public.curriculum_modules where id = v_topic.module_id;
    if not exists (
      select 1 from public.learner_module_states(p_actor, v_module.coc_code) s
      where s.module_id = v_topic.module_id and s.unlocked
    ) then
      raise exception 'MODULE_LOCKED' using errcode = '42501';
    end if;
    insert into public.learner_topic_progress(learner_id, topic_id, revision_id)
    values (p_actor, v_topic.id, v_revision.id)
    on conflict (learner_id, topic_id) do nothing
    returning * into v_progress;
    if v_progress.learner_id is null then
      select * into v_progress from public.learner_topic_progress
      where learner_id = p_actor and topic_id = v_topic.id;
      return jsonb_build_object('progress', to_jsonb(v_progress), 'already_completed', true);
    end if;
    insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, new_value, metadata)
    values (p_actor, v_role, 'curriculum.topic_completed', 'curriculum_topic', v_topic.id, to_jsonb(v_progress),
      jsonb_build_object('module_id', v_topic.module_id, 'revision_id', v_revision.id));
    return jsonb_build_object('progress', to_jsonb(v_progress), 'already_completed', false);
  end if;

  if v_role not in ('instructor'::public.user_role, 'admin'::public.user_role) then
    raise exception 'CURRICULUM_STAFF_REQUIRED' using errcode = '42501';
  end if;

  -- -------------------------------------------------------------------------
  -- Create a topic with its first draft revision
  -- -------------------------------------------------------------------------
  if p_action = 'create_topic' then
    select * into v_module from public.curriculum_modules where id = (v_payload->>'module_id')::uuid;
    if not found then
      raise exception 'MODULE_NOT_FOUND' using errcode = 'P0002';
    end if;
    v_title := btrim(coalesce(v_payload->>'title', ''));
    v_summary := nullif(btrim(coalesce(v_payload->>'summary', '')), '');
    v_body := coalesce(v_payload->>'body_markdown', '');
    select coalesce(array_agg(distinct x::uuid), '{}'::uuid[]) into v_outcomes
    from jsonb_array_elements_text(coalesce(v_payload->'outcome_ids', '[]'::jsonb)) x;
    if length(v_title) < 2 or length(v_title) > 200 then
      raise exception 'TITLE_REQUIRED' using errcode = '22023';
    end if;
    if length(coalesce(v_summary, '')) > 1000 or length(v_body) > 60000 then
      raise exception 'CONTENT_TOO_LONG' using errcode = '22023';
    end if;
    if exists (select 1 from unnest(v_outcomes) o where not exists (
      select 1 from public.learning_outcomes lo where lo.id = o and lo.module_id = v_module.id)) then
      raise exception 'OUTCOME_NOT_IN_MODULE' using errcode = '22023';
    end if;
    insert into public.curriculum_topics(module_id, sequence_order, created_by)
    values (v_module.id,
      coalesce((select max(t.sequence_order) from public.curriculum_topics t where t.module_id = v_module.id), 0) + 1,
      p_actor)
    returning * into v_topic;
    insert into public.curriculum_topic_revisions(topic_id, revision_number, title, summary, body_markdown,
      outcome_ids, status, author_id)
    values (v_topic.id, 1, v_title, v_summary, v_body, v_outcomes, 'draft', p_actor)
    returning * into v_revision;
    insert into public.content_publication_events(entity_type, entity_id, revision_id, from_status, to_status, actor_id, note)
    values ('topic', v_topic.id, v_revision.id, null, 'draft', p_actor, 'Topic created');
    insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, new_value, metadata)
    values (p_actor, v_role, 'curriculum.create_topic', 'curriculum_topic_revision', v_revision.id, to_jsonb(v_revision),
      jsonb_build_object('topic_id', v_topic.id, 'module_id', v_module.id));
    return jsonb_build_object('topic', to_jsonb(v_topic), 'revision', to_jsonb(v_revision));
  end if;

  -- -------------------------------------------------------------------------
  -- Archive a topic (admin)
  -- -------------------------------------------------------------------------
  if p_action = 'archive_topic' then
    if v_role <> 'admin'::public.user_role then
      raise exception 'ADMIN_REQUIRED' using errcode = '42501';
    end if;
    select * into v_topic from public.curriculum_topics where id = (v_payload->>'topic_id')::uuid for update;
    if not found then
      raise exception 'TOPIC_NOT_FOUND' using errcode = 'P0002';
    end if;
    if v_topic.archived_at is not null then
      return jsonb_build_object('topic', to_jsonb(v_topic), 'revision', null);
    end if;
    update public.curriculum_topics set archived_at = now() where id = v_topic.id returning * into v_topic;
    for v_other in
      select * from public.curriculum_topic_revisions
      where topic_id = v_topic.id and status <> 'archived'::public.content_publication_status
      order by revision_number
      for update
    loop
      update public.curriculum_topic_revisions set status = 'archived' where id = v_other.id;
      insert into public.content_publication_events(entity_type, entity_id, revision_id, from_status, to_status, actor_id, note)
      values ('topic', v_topic.id, v_other.id, v_other.status, 'archived', p_actor, nullif(btrim(coalesce(v_payload->>'note', '')), ''));
    end loop;
    insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, new_value, reason, metadata)
    values (p_actor, v_role, 'curriculum.archive_topic', 'curriculum_topic', v_topic.id, to_jsonb(v_topic),
      nullif(btrim(coalesce(v_payload->>'note', '')), ''), jsonb_build_object('module_id', v_topic.module_id));
    -- Fewer required items can complete a module: record it for every learner
    -- who has reached it (unlocks and completions are never removed).
    for v_learner in select u.learner_id from public.learner_module_unlocks u where u.module_id = v_topic.module_id loop
      perform public.refresh_learner_unlocks(v_learner);
    end loop;
    return jsonb_build_object('topic', to_jsonb(v_topic), 'revision', null);
  end if;

  -- -------------------------------------------------------------------------
  -- Revision actions
  -- -------------------------------------------------------------------------
  -- Lock order topic -> revision (same as archive_topic) to avoid deadlocks.
  select * into v_topic from public.curriculum_topics
  where id = (select x.topic_id from public.curriculum_topic_revisions x where x.id = (v_payload->>'revision_id')::uuid)
  for update;
  if not found then
    raise exception 'REVISION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into v_revision from public.curriculum_topic_revisions where id = (v_payload->>'revision_id')::uuid for update;
  if v_topic.archived_at is not null then
    raise exception 'TOPIC_ARCHIVED' using errcode = '55000';
  end if;
  v_old := v_revision;

  if p_action = 'edit_revision' then
    if not (v_role = 'admin'::public.user_role or v_revision.author_id = p_actor or v_topic.created_by = p_actor) then
      raise exception 'REVISION_AUTHOR_REQUIRED' using errcode = '42501';
    end if;
    v_title := btrim(coalesce(v_payload->>'title', v_revision.title));
    v_summary := case when v_payload ? 'summary' then nullif(btrim(coalesce(v_payload->>'summary', '')), '') else v_revision.summary end;
    v_body := case when v_payload ? 'body_markdown' then coalesce(v_payload->>'body_markdown', '') else v_revision.body_markdown end;
    if v_payload ? 'outcome_ids' then
      select coalesce(array_agg(distinct x::uuid), '{}'::uuid[]) into v_outcomes
      from jsonb_array_elements_text(coalesce(v_payload->'outcome_ids', '[]'::jsonb)) x;
    else
      v_outcomes := v_revision.outcome_ids;
    end if;
    if length(v_title) < 2 or length(v_title) > 200 then
      raise exception 'TITLE_REQUIRED' using errcode = '22023';
    end if;
    if length(coalesce(v_summary, '')) > 1000 or length(v_body) > 60000 then
      raise exception 'CONTENT_TOO_LONG' using errcode = '22023';
    end if;
    if exists (select 1 from unnest(v_outcomes) o where not exists (
      select 1 from public.learning_outcomes lo where lo.id = o and lo.module_id = v_topic.module_id)) then
      raise exception 'OUTCOME_NOT_IN_MODULE' using errcode = '22023';
    end if;

    if v_revision.status in ('draft'::public.content_publication_status, 'needs_revision'::public.content_publication_status) then
      update public.curriculum_topic_revisions
      set title = v_title, summary = v_summary, body_markdown = v_body, outcome_ids = v_outcomes
      where id = v_revision.id
      returning * into v_revision;
      insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
      values (p_actor, v_role, 'curriculum.edit_revision', 'curriculum_topic_revision', v_revision.id,
        to_jsonb(v_old), to_jsonb(v_revision), jsonb_build_object('topic_id', v_topic.id));
      return jsonb_build_object('topic', to_jsonb(v_topic), 'revision', to_jsonb(v_revision));
    elsif v_revision.status in ('published'::public.content_publication_status, 'unpublished'::public.content_publication_status) then
      if exists (
        select 1 from public.curriculum_topic_revisions x
        where x.topic_id = v_topic.id and x.status in ('draft', 'submitted', 'needs_revision', 'evaluated', 'finalized', 'approved')
      ) then
        raise exception 'REVISION_IN_PROGRESS' using errcode = '55000';
      end if;
      insert into public.curriculum_topic_revisions(topic_id, revision_number, title, summary, body_markdown,
        outcome_ids, status, author_id)
      values (v_topic.id,
        (select max(x.revision_number) from public.curriculum_topic_revisions x where x.topic_id = v_topic.id) + 1,
        v_title, v_summary, v_body, v_outcomes, 'draft', p_actor)
      returning * into v_revision;
      insert into public.content_publication_events(entity_type, entity_id, revision_id, from_status, to_status, actor_id, note)
      values ('topic', v_topic.id, v_revision.id, null, 'draft', p_actor,
        'New revision based on revision ' || v_old.revision_number);
      insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
      values (p_actor, v_role, 'curriculum.create_revision', 'curriculum_topic_revision', v_revision.id,
        to_jsonb(v_old), to_jsonb(v_revision), jsonb_build_object('topic_id', v_topic.id, 'based_on', v_old.id));
      return jsonb_build_object('topic', to_jsonb(v_topic), 'revision', to_jsonb(v_revision));
    else
      raise exception 'REVISION_LOCKED' using errcode = '55000';
    end if;
  end if;

  if p_action = 'submit' then
    if v_revision.author_id is distinct from p_actor then
      raise exception 'REVISION_AUTHOR_REQUIRED' using errcode = '42501';
    end if;
    if v_revision.status not in ('draft'::public.content_publication_status, 'needs_revision'::public.content_publication_status) then
      raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '55000';
    end if;
    if length(btrim(v_revision.body_markdown)) = 0 then
      raise exception 'BODY_REQUIRED' using errcode = '22023';
    end if;
    update public.curriculum_topic_revisions set status = 'submitted', submitted_at = now()
    where id = v_revision.id returning * into v_revision;
  elsif p_action = 'evaluate' then
    if v_role <> 'admin'::public.user_role then
      raise exception 'ADMIN_REQUIRED' using errcode = '42501';
    end if;
    if v_revision.status <> 'submitted'::public.content_publication_status then
      raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '55000';
    end if;
    v_result := v_payload->>'result';
    v_notes := btrim(coalesce(v_payload->>'notes', ''));
    if v_result is null or v_result not in ('passed', 'needs_revision') then
      raise exception 'EVALUATION_RESULT_INVALID' using errcode = '22023';
    end if;
    if length(v_notes) < 10 or length(v_notes) > 4000 then
      raise exception 'EVALUATION_NOTES_REQUIRED' using errcode = '22023';
    end if;
    update public.curriculum_topic_revisions
    set status = case when v_result = 'passed' then 'evaluated'::public.content_publication_status
                      else 'needs_revision'::public.content_publication_status end,
        evaluated_by = p_actor, evaluated_at = now(), evaluation_notes = v_notes
    where id = v_revision.id returning * into v_revision;
  elsif p_action = 'finalize' then
    if not (v_role = 'admin'::public.user_role or v_revision.author_id = p_actor) then
      raise exception 'REVISION_AUTHOR_REQUIRED' using errcode = '42501';
    end if;
    if v_revision.status <> 'evaluated'::public.content_publication_status then
      raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '55000';
    end if;
    update public.curriculum_topic_revisions set status = 'finalized', finalized_by = p_actor, finalized_at = now()
    where id = v_revision.id returning * into v_revision;
  elsif p_action = 'approve' then
    if v_role <> 'admin'::public.user_role then
      raise exception 'ADMIN_REQUIRED' using errcode = '42501';
    end if;
    if v_revision.status <> 'finalized'::public.content_publication_status then
      raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '55000';
    end if;
    update public.curriculum_topic_revisions set status = 'approved', approved_by = p_actor, approved_at = now()
    where id = v_revision.id returning * into v_revision;
  elsif p_action = 'publish' then
    if v_role <> 'admin'::public.user_role then
      raise exception 'ADMIN_REQUIRED' using errcode = '42501';
    end if;
    if v_revision.status not in ('approved'::public.content_publication_status, 'unpublished'::public.content_publication_status) then
      raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '55000';
    end if;
    -- The previously published revision of this topic is replaced.
    for v_other in
      select * from public.curriculum_topic_revisions
      where topic_id = v_topic.id and id <> v_revision.id and status = 'published'::public.content_publication_status
      for update
    loop
      update public.curriculum_topic_revisions set status = 'unpublished', unpublished_by = p_actor, unpublished_at = now()
      where id = v_other.id;
      insert into public.content_publication_events(entity_type, entity_id, revision_id, from_status, to_status, actor_id, note)
      values ('topic', v_topic.id, v_other.id, 'published', 'unpublished', p_actor,
        'Replaced by revision ' || v_revision.revision_number);
    end loop;
    update public.curriculum_topic_revisions set status = 'published', published_by = p_actor, published_at = now()
    where id = v_revision.id returning * into v_revision;
  elsif p_action = 'unpublish' then
    if v_role <> 'admin'::public.user_role then
      raise exception 'ADMIN_REQUIRED' using errcode = '42501';
    end if;
    if v_revision.status <> 'published'::public.content_publication_status then
      raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '55000';
    end if;
    update public.curriculum_topic_revisions set status = 'unpublished', unpublished_by = p_actor, unpublished_at = now()
    where id = v_revision.id returning * into v_revision;
  else
    raise exception 'CURRICULUM_ACTION_INVALID' using errcode = '22023';
  end if;

  insert into public.content_publication_events(entity_type, entity_id, revision_id, from_status, to_status, actor_id, note)
  values ('topic', v_topic.id, v_revision.id, v_old.status, v_revision.status, p_actor,
    coalesce(case when p_action = 'evaluate' then v_notes end, nullif(btrim(coalesce(v_payload->>'note', '')), '')));
  insert into public.audit_events(actor_id, actor_role, action, target_type, target_id, old_value, new_value, reason, metadata)
  values (p_actor, v_role, 'curriculum.' || p_action, 'curriculum_topic_revision', v_revision.id,
    jsonb_build_object('status', v_old.status), jsonb_build_object('status', v_revision.status),
    case when p_action = 'evaluate' then v_notes end,
    jsonb_build_object('topic_id', v_topic.id, 'module_id', v_topic.module_id, 'revision_number', v_revision.revision_number));

  if p_action = 'unpublish' then
    for v_learner in select u.learner_id from public.learner_module_unlocks u where u.module_id = v_topic.module_id loop
      perform public.refresh_learner_unlocks(v_learner);
    end loop;
  end if;

  return jsonb_build_object('topic', to_jsonb(v_topic), 'revision', to_jsonb(v_revision));
end
$$;

revoke all on function public.manage_curriculum_content(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.manage_curriculum_content(uuid, text, jsonb) to service_role;

comment on function public.manage_curriculum_content(uuid, text, jsonb) is
  'Service-only curriculum content workflow: create/edit topics and revisions, submit, evaluate, finalize, approve, publish, unpublish, archive; learner topic completion. Enforces stage order and roles; appends content_publication_events and audit_events.';

notify pgrst, 'reload schema';

commit;
