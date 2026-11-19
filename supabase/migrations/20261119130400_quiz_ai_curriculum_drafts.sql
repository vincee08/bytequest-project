-- Re-defense WS4 (slice A3.4): AI quiz drafts grounded in the quiz curriculum
-- (module, performance criteria, topic, focus) may include scenario essays
-- with rubrics, and "Regenerate this question" replaces one draft question in
-- one audited step: the original is removed with a reason (its row and text
-- stay in history) and the replacement takes its position.
--
-- Service-only SECURITY INVOKER function called by the authenticated AI route
-- after begin_ai_quiz_generation; the existing definer complete_ai_quiz_generation
-- is unchanged. Drafts are never approved or published automatically.
begin;
set local lock_timeout = '5s';

create function public.complete_ai_quiz_draft(
  p_actor uuid,
  p_generation_id uuid,
  p_provider text,
  p_model text,
  p_items jsonb,
  p_replace_item_id uuid default null,
  p_replace_reason text default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_generation public.ai_quiz_generations;
  v_version public.quiz_versions;
  v_item jsonb;
  v_count integer;
  v_order integer;
  v_type public.quiz_item_type;
  v_rubric jsonb;
  v_points numeric;
  v_scenario text;
  v_min integer;
  v_max integer;
  v_original public.quiz_items;
  v_new public.quiz_items;
  v_ids jsonb := '[]'::jsonb;
  v_slot integer;
  v_now timestamptz := clock_timestamp();
  v_reason text := nullif(btrim(p_replace_reason), '');
begin
  if not exists (
    select 1 from public.profiles p
    where p.user_id = p_actor and p.role = 'instructor'::public.user_role and p.status = 'active'::public.account_status
  ) then
    raise exception 'INSTRUCTOR_REQUIRED' using errcode = '42501';
  end if;
  select g.* into v_generation from public.ai_quiz_generations g where g.id = p_generation_id for update;
  if not found then raise exception 'AI_GENERATION_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_generation.status <> 'requested'::public.ai_generation_status or v_generation.instructor_id <> p_actor then
    raise exception 'AI_GENERATION_STATE_DENIED' using errcode = '22023';
  end if;
  select qv.* into v_version
  from public.quiz_versions qv
  join public.quizzes q on q.id = qv.quiz_id
  where qv.id = v_generation.quiz_version_id and q.instructor_id = p_actor and q.archived_at is null
  for update of qv;
  if not found or v_version.status <> 'draft'::public.content_version_status then
    raise exception 'DRAFT_QUIZ_VERSION_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'AI_ITEMS_ARRAY_REQUIRED' using errcode = '22023';
  end if;
  v_count := jsonb_array_length(p_items);
  if v_count < 1 or v_count > v_generation.requested_count or v_count > 10 then
    raise exception 'AI_ITEM_COUNT_INVALID' using errcode = '22023';
  end if;
  if p_replace_item_id is not null then
    if v_count <> 1 then raise exception 'AI_ITEM_COUNT_INVALID' using errcode = '22023'; end if;
    if v_reason is null then raise exception 'REMOVAL_REASON_REQUIRED' using errcode = '22023'; end if;
    select qi.* into v_original from public.quiz_items qi
    where qi.id = p_replace_item_id and qi.quiz_version_id = v_version.id and qi.removed_at is null
    for update;
    if not found then raise exception 'QUIZ_ITEM_NOT_FOUND' using errcode = 'P0002'; end if;
  end if;

  select coalesce(max(qi.order_index), 0) into v_order from public.quiz_items qi where qi.quiz_version_id = v_version.id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if coalesce(v_item->>'item_type', '') not in ('multiple_choice', 'true_false', 'identification', 'scenario_based', 'scenario_essay') then
      raise exception 'AI_ITEM_CONTRACT_INVALID' using errcode = '22023';
    end if;
    v_type := (v_item->>'item_type')::public.quiz_item_type;
    if length(btrim(coalesce(v_item->>'prompt', ''))) not between 5 and 2000
       or not coalesce(private.validate_quiz_item(v_type, coalesce(v_item->'options', '[]'::jsonb),
         to_jsonb(coalesce(v_item->>'correct_answer', ''))), false) then
      raise exception 'AI_ITEM_CONTRACT_INVALID' using errcode = '22023';
    end if;
    if v_type = 'scenario_essay'::public.quiz_item_type then
      v_rubric := private.normalize_quiz_rubric(v_item->'rubric');
      v_scenario := nullif(btrim(v_item->>'scenario'), '');
      v_min := case when jsonb_typeof(v_item->'min_words') = 'number' then (v_item->>'min_words')::numeric::integer end;
      v_max := case when jsonb_typeof(v_item->'max_words') = 'number' then (v_item->>'max_words')::numeric::integer end;
      if v_rubric is null or length(coalesce(v_scenario, '')) not between 10 and 4000
         or (v_min is not null and v_min not between 1 and 5000) or (v_max is not null and v_max not between 1 and 5000)
         or (v_min is not null and v_max is not null and v_min > v_max) then
        raise exception 'AI_ITEM_CONTRACT_INVALID' using errcode = '22023';
      end if;
      v_points := private.quiz_rubric_total(v_rubric);
    else
      v_rubric := null; v_scenario := null; v_min := null; v_max := null; v_points := 1;
    end if;
    v_order := v_order + 1;
    insert into public.quiz_items (
      quiz_version_id, item_code, item_type, prompt, options, correct_answer, explanation, origin,
      ai_generation_id, order_index, created_by, scenario, rubric, points, min_words, max_words
    ) values (
      v_version.id, 'ITEM-' || lpad(v_order::text, 3, '0'), v_type, btrim(v_item->>'prompt'),
      coalesce(v_item->'options', '[]'::jsonb), to_jsonb(coalesce(v_item->>'correct_answer', '')),
      nullif(btrim(v_item->>'explanation'), ''), 'ai_generated_draft'::public.quiz_item_origin,
      v_generation.id, v_order, p_actor, v_scenario, v_rubric, v_points, v_min, v_max
    ) returning * into v_new;
    v_ids := v_ids || to_jsonb(v_new.id);
  end loop;

  if v_original.id is not null then
    -- The replacement takes the original's slot; the original keeps its text.
    v_slot := v_original.order_index;
    update public.quiz_items set order_index = v_order + 1 where id = v_original.id;
    update public.quiz_items set order_index = v_slot where id = v_new.id;
    update public.quiz_items
    set removed_at = v_now, removed_by = p_actor, removal_reason = v_reason,
        review_status = 'rejected'::public.quiz_item_review_status, review_notes = v_reason,
        reviewed_by = p_actor, reviewed_at = v_now
    where id = v_original.id;
    insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, reason, metadata, created_at)
    values (p_actor, 'instructor', 'quiz_item.removed', 'quiz_item', v_original.id, to_jsonb(v_original),
      (select to_jsonb(qi) from public.quiz_items qi where qi.id = v_original.id), v_reason,
      jsonb_build_object('replaced_by', v_new.id, 'ai_generation_id', v_generation.id), v_now);
    insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, new_value, reason, metadata, created_at)
    values (p_actor, 'instructor', 'quiz_item.regenerated', 'quiz_item', v_new.id,
      jsonb_build_object('original_item_id', v_original.id, 'replacement_item_id', v_new.id,
        'ai_generation_id', v_generation.id, 'order_index', v_slot),
      v_reason, jsonb_build_object('draft_only', true, 'auto_publish', false), v_now);
  end if;

  update public.ai_quiz_generations
  set provider = btrim(p_provider), model = btrim(p_model), status = 'completed'::public.ai_generation_status,
      generated_count = v_count, completed_at = now()
  where id = v_generation.id;
  insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, new_value, metadata, outcome)
  values (p_actor, 'instructor', 'quiz.ai_draft.completed', 'ai_quiz_generation', v_generation.id,
    jsonb_build_object('quiz_version_id', v_version.id, 'provider', btrim(p_provider), 'model', btrim(p_model),
      'generated_count', v_count, 'replaced_item_id', v_original.id),
    jsonb_build_object('draft_only', true, 'auto_publish', false, 'competency_authority', false), 'success');
  return jsonb_build_object('generated_count', v_count, 'item_ids', v_ids, 'replaced_item_id', v_original.id);
end
$$;
revoke all on function public.complete_ai_quiz_draft(uuid, uuid, text, text, jsonb, uuid, text) from public, anon, authenticated;
grant execute on function public.complete_ai_quiz_draft(uuid, uuid, text, text, jsonb, uuid, text) to service_role;

notify pgrst, 'reload schema';
commit;
