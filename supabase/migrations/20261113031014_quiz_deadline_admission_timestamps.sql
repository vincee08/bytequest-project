-- Record admission time after locks and final availability validation.
-- A transaction that waited across a deadline cannot use transaction-start now().
-- Completed grading/history and one-attempt claims are preserved.
begin;
set local lock_timeout='5s';

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
  if not private.quiz_assignment_is_available(p_assignment_id, (select auth.uid())) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode = '42501';
  end if;

  select * into v_assignment from public.quiz_assignments where id=p_assignment_id for share;
  select quiz_id into v_quiz_id from public.quiz_versions where id=v_assignment.quiz_version_id;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended((select auth.uid())::text || ':' || v_quiz_id::text, 0));
  select qa.* into v_attempt from private.quiz_attempt_claims claim
    join public.quiz_attempts qa on qa.id=claim.attempt_id
    where claim.learner_id=(select auth.uid()) and claim.quiz_id=v_quiz_id;
  if found then
    if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then
      raise exception 'QUIZ_ATTEMPT_ALREADY_SUBMITTED' using errcode='55000';
    end if;
    perform 1 from public.quiz_assignments where id=v_attempt.quiz_assignment_id for share;
    if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id,(select auth.uid())) then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
    end if;
  else
    -- Recheck access after waiting for a concurrent start/publication.
    if not private.quiz_assignment_is_available(p_assignment_id,(select auth.uid())) then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
    end if;
    v_admitted_at:=private.activity_server_now();
    if not private.quiz_assignment_is_available(p_assignment_id,(select auth.uid())) then raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501'; end if;
    insert into public.quiz_attempts(learner_id,class_id,quiz_assignment_id,quiz_version_id,client_start_key,started_at)
    values((select auth.uid()),v_assignment.class_id,v_assignment.id,v_assignment.quiz_version_id,p_client_start_key,v_admitted_at)
    returning * into v_attempt;
    perform private.write_audit_event('quiz_attempt.started','quiz_attempt',v_attempt.id,null,
      jsonb_build_object('assignment_id',v_assignment.id,'quiz_version_id',v_assignment.quiz_version_id,'quiz_id',v_quiz_id));
  end if;

  select jsonb_build_object(
    'attempt_id', v_attempt.id,
    'status', v_attempt.status,
    'started_at', v_attempt.started_at,
    'server_now',private.activity_server_now(),
    'due_at',(select due_at from public.quiz_assignments where id=v_attempt.quiz_assignment_id),
    'quiz', jsonb_build_object(
      'assignment_id', a.id,
      'title', q.title,
      'description', q.description,
      'topic', q.topic,
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
        'saved_answer', ans.answer #>> '{}'
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
  v_attempt public.quiz_attempts;
  v_admitted_at timestamptz;
  v_answer public.quiz_answers;
begin
  if not public.is_learner() then raise exception 'LEARNER_REQUIRED' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_answer, ''))) not between 1 and 2000 then
    raise exception 'QUIZ_ANSWER_REQUIRED' using errcode = '22023';
  end if;
  select * into v_attempt from public.quiz_attempts
  where id = p_attempt_id and learner_id = (select auth.uid()) for update;
  if not found then raise exception 'QUIZ_ATTEMPT_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then
    raise exception 'QUIZ_ATTEMPT_ALREADY_SUBMITTED' using errcode = '55000';
  end if;
  if not exists(select 1 from private.quiz_attempt_claims where learner_id=(select auth.uid()) and attempt_id=v_attempt.id) then
    raise exception 'QUIZ_ATTEMPT_ALREADY_USED' using errcode='55000';
  end if;
  perform 1 from public.quiz_assignments where id=v_attempt.quiz_assignment_id for share;
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id,(select auth.uid())) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.quiz_items qi
    where qi.id = p_item_id
      and qi.quiz_version_id = v_attempt.quiz_version_id
      and qi.review_status = 'approved'::public.quiz_item_review_status
      and qi.removed_at is null
  ) then raise exception 'QUIZ_ITEM_NOT_AVAILABLE' using errcode = '42501'; end if;

  v_admitted_at:=private.activity_server_now();
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id,(select auth.uid())) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  insert into public.quiz_answers(
    quiz_attempt_id, quiz_item_id, quiz_version_id, answer, answered_at
  ) values(
    v_attempt.id, p_item_id, v_attempt.quiz_version_id, to_jsonb(btrim(p_answer)), v_admitted_at
  )
  on conflict (quiz_attempt_id, quiz_item_id)
  do update set answer = excluded.answer, is_correct = null, answered_at = v_admitted_at
  returning * into v_answer;
  return jsonb_build_object(
    'attempt_id', v_attempt.id,
    'item_id', p_item_id,
    'saved', true,
    'answered_at', v_answer.answered_at
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
  v_attempt public.quiz_attempts;
  v_admitted_at timestamptz;
  v_question_count integer;
  v_answer_count integer;
  v_correct_count integer;
  v_results jsonb;
  v_result public.quiz_results;
begin
  if not public.is_learner() then raise exception 'LEARNER_REQUIRED' using errcode = '42501'; end if;
  select * into v_attempt from public.quiz_attempts
  where id = p_attempt_id and learner_id = (select auth.uid()) for update;
  if not found then raise exception 'QUIZ_ATTEMPT_NOT_FOUND' using errcode = 'P0002'; end if;

  if v_attempt.status = 'completed'::public.quiz_attempt_status then
    select * into v_result from public.quiz_results where quiz_attempt_id = v_attempt.id;
    return jsonb_build_object(
      'attempt_id', v_attempt.id, 'status', v_attempt.status,
      'correct_count', v_result.correct_count,
      'question_count', v_result.question_count,
      'evaluated_at', v_result.evaluated_at
    );
  end if;
  if v_attempt.status <> 'in_progress'::public.quiz_attempt_status then
    raise exception 'QUIZ_SUBMISSION_IN_PROGRESS' using errcode = '55000';
  end if;

  if not exists(select 1 from private.quiz_attempt_claims where learner_id=(select auth.uid()) and attempt_id=v_attempt.id) then
    raise exception 'QUIZ_ATTEMPT_ALREADY_USED' using errcode='55000';
  end if;
  perform 1 from public.quiz_assignments where id=v_attempt.quiz_assignment_id for share;
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id,(select auth.uid())) then
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
  if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id,(select auth.uid())) then
    raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
  end if;
  update public.quiz_attempts set
    status = 'submitted'::public.quiz_attempt_status,
    submission_key = p_submission_key,
    submitted_at = v_admitted_at
  where id = v_attempt.id;

  update public.quiz_answers ans set is_correct = (
    case
      when qi.item_type in ('identification'::public.quiz_item_type, 'true_false'::public.quiz_item_type)
        then lower(btrim(ans.answer #>> '{}')) = lower(btrim(qi.correct_answer #>> '{}'))
      else ans.answer #>> '{}' = qi.correct_answer #>> '{}'
    end
  )
  from public.quiz_items qi
  where ans.quiz_attempt_id = v_attempt.id and qi.id = ans.quiz_item_id;

  select count(*) filter (where ans.is_correct),
    jsonb_agg(jsonb_build_object(
      'item_id', qi.id,
      'code', qi.item_code,
      'type', qi.item_type,
      'prompt', qi.prompt,
      'learner_answer', ans.answer #>> '{}',
      'is_correct', ans.is_correct,
      'order_index', qi.order_index
    ) order by qi.order_index)
  into v_correct_count, v_results
  from public.quiz_answers ans
  join public.quiz_items qi on qi.id = ans.quiz_item_id
  where ans.quiz_attempt_id = v_attempt.id;

  insert into public.quiz_results(
    quiz_attempt_id, correct_count, question_count, item_results
  ) values (
    v_attempt.id, v_correct_count, v_question_count, coalesce(v_results, '[]'::jsonb)
  ) returning * into v_result;

  update public.quiz_attempts set
    status = 'completed'::public.quiz_attempt_status,
    completed_at = v_result.evaluated_at
  where id = v_attempt.id;

  perform private.write_audit_event(
    'quiz_attempt.completed', 'quiz_attempt', v_attempt.id, null,
    jsonb_build_object(
      'quiz_assignment_id', v_attempt.quiz_assignment_id,
      'correct_count', v_correct_count,
      'question_count', v_question_count
    ), null, jsonb_build_object('competency_authority', false)
  );

  return jsonb_build_object(
    'attempt_id', v_attempt.id,
    'status', 'completed',
    'correct_count', v_correct_count,
    'question_count', v_question_count,
    'evaluated_at', v_result.evaluated_at
  );
end
$$;

notify pgrst,'reload schema';
commit;
