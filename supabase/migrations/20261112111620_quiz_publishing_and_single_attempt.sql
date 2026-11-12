-- Reason-free publication and one supplementary quiz attempt per learner.
-- Preserve every historical row. New helpers are SECURITY INVOKER; existing
-- elevated RPCs retain their authentication/ownership checks and signatures.
begin;
set local lock_timeout='5s';

-- Prevent an insert from slipping between historical backfill and trigger setup.
lock table public.quiz_attempts in share row exclusive mode;
create table private.quiz_attempt_claims (
  learner_id uuid not null references auth.users(id) on delete restrict,
  quiz_id uuid not null references public.quizzes(id) on delete restrict,
  attempt_id uuid not null unique references public.quiz_attempts(id) on delete restrict,
  primary key(learner_id,quiz_id)
);
alter table private.quiz_attempt_claims enable row level security;
alter table private.quiz_attempt_claims owner to postgres;
revoke all on private.quiz_attempt_claims from public,anon,authenticated;
-- Submitted/completed history exhausts the quiz; otherwise resume the oldest run.
insert into private.quiz_attempt_claims(learner_id,quiz_id,attempt_id)
select distinct on(a.learner_id,v.quiz_id) a.learner_id,v.quiz_id,a.id
from public.quiz_attempts a join public.quiz_versions v on v.id=a.quiz_version_id
order by a.learner_id,v.quiz_id,(a.status='completed'::public.quiz_attempt_status) desc,
  (a.status<>'in_progress'::public.quiz_attempt_status) desc,a.started_at,a.id;

create function private.claim_quiz_attempt() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='UPDATE' then
    if (new.learner_id,new.quiz_version_id,new.quiz_assignment_id,new.class_id) is distinct from
       (old.learner_id,old.quiz_version_id,old.quiz_assignment_id,old.class_id) then
      raise exception 'QUIZ_ATTEMPT_IDENTITY_IMMUTABLE' using errcode='55000';
    end if;
    return new;
  end if;
  insert into private.quiz_attempt_claims(learner_id,quiz_id,attempt_id)
  select new.learner_id,v.quiz_id,new.id from public.quiz_versions v where v.id=new.quiz_version_id;
  return new;
end $$;
revoke all on function private.claim_quiz_attempt() from public,anon,authenticated;
create trigger quiz_attempts_claim after insert on public.quiz_attempts for each row execute function private.claim_quiz_attempt();
create trigger quiz_attempts_identity before update of learner_id,quiz_version_id,quiz_assignment_id,class_id on public.quiz_attempts for each row execute function private.claim_quiz_attempt();

-- Serialize review/removal with publication, including direct calls to existing
-- review RPCs. After publication wins, the original immutability check rejects edits.
create or replace function private.protect_quiz_item_history()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_status public.content_version_status;
begin
  select qv.status into v_status from public.quiz_versions qv where qv.id=old.quiz_version_id for share;
  if v_status<>'draft'::public.content_version_status then
    raise exception 'PUBLISHED_QUIZ_ITEMS_ARE_IMMUTABLE' using errcode='55000';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;

create or replace function public.publish_quiz_version(p_quiz_version_id uuid,p_reason text default null)
returns public.quiz_versions
language plpgsql
security definer
set search_path = ''
as $$
declare v_version public.quiz_versions; v_quiz public.quizzes; v_old jsonb;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  select qv.* into v_version from public.quiz_versions qv where qv.id=p_quiz_version_id for update;
  if not found then raise exception 'QUIZ_VERSION_NOT_FOUND' using errcode='P0002'; end if;
  select q.* into v_quiz from public.quizzes q where q.id=v_version.quiz_id for update;
  if v_quiz.instructor_id<>(select auth.uid()) then raise exception 'QUIZ_SCOPE_DENIED' using errcode='42501'; end if;
  if v_version.status='published'::public.content_version_status and v_quiz.archived_at is null then return v_version; end if;
  if v_quiz.archived_at is not null or v_version.status<>'draft'::public.content_version_status then raise exception 'DRAFT_ACTIVE_QUIZ_REQUIRED' using errcode='22023'; end if;
  if not exists(select 1 from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null and qi.review_status='approved'::public.quiz_item_review_status) then
    raise exception 'APPROVED_QUIZ_ITEM_REQUIRED' using errcode='22023';
  end if;
  if exists(select 1 from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null and qi.review_status<>'approved'::public.quiz_item_review_status) then
    raise exception 'ALL_QUIZ_ITEMS_REQUIRE_APPROVAL' using errcode='22023';
  end if;
  v_old:=to_jsonb(v_version);
  update public.quiz_versions set status='retired'::public.content_version_status,retired_at=now()
  where quiz_id=v_quiz.id and status='published'::public.content_version_status;
  update public.quiz_versions set status='published'::public.content_version_status,published_by=(select auth.uid()),published_at=now()
  where id=v_version.id returning * into v_version;
  perform private.write_audit_event('quiz_version.published','quiz_version',v_version.id,v_old,to_jsonb(v_version),nullif(btrim(p_reason),''),
    jsonb_build_object('quiz_id',v_quiz.id,'approved_items',(select count(*) from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null)));
  return v_version;
end
$$;

create or replace function public.assign_published_quiz(
  p_class_id uuid,
  p_quiz_version_id uuid,
  p_available_at timestamptz default null,
  p_due_at timestamptz default null,
  p_attempts_allowed integer default 1,
  p_instructions text default null
)
returns public.quiz_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment public.quiz_assignments;
begin
  if not public.is_instructor() or not public.instructor_owns_class(p_class_id) then
    raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
  end if;
  if not exists(select 1 from public.classes where id=p_class_id and status='active'::public.class_status) then
    raise exception 'ACTIVE_CLASS_REQUIRED' using errcode='22023';
  end if;
  if p_due_at is not null and p_available_at is not null and p_due_at <= p_available_at then
    raise exception 'INVALID_AVAILABILITY_WINDOW' using errcode = '22023';
  end if;
  if p_attempts_allowed is not null and p_attempts_allowed <> 1 then
    raise exception 'INVALID_ATTEMPT_LIMIT' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.quiz_versions qv
    join public.quizzes q on q.id = qv.quiz_id
    where qv.id = p_quiz_version_id
      and qv.status = 'published'::public.content_version_status
      and q.instructor_id = (select auth.uid())
      and q.archived_at is null
  ) then
    raise exception 'PUBLISHED_QUIZ_SCOPE_REQUIRED' using errcode = '42501';
  end if;

  insert into public.quiz_assignments(
    class_id, quiz_version_id, assigned_by, available_at, due_at,
    attempts_allowed, instructions
  ) values (
    p_class_id, p_quiz_version_id, (select auth.uid()), p_available_at,
    p_due_at, 1, nullif(btrim(p_instructions), '')
  ) on conflict (class_id, quiz_version_id) where status='active'::public.assignment_status
  do nothing returning * into v_assignment;
  if not found then
    select * into v_assignment from public.quiz_assignments
    where class_id=p_class_id and quiz_version_id=p_quiz_version_id and status='active'::public.assignment_status;
    return v_assignment;
  end if;

  perform private.write_audit_event(
    'quiz.assigned', 'quiz_assignment', v_assignment.id, null,
    to_jsonb(v_assignment), null,
    jsonb_build_object('class_id', p_class_id, 'quiz_version_id', p_quiz_version_id)
  );
  return v_assignment;
end
$$;

-- One PostgREST request/transaction. Existing RPCs continue to own security,
-- publication audit and assignment audit; no fabricated publication reason.
create function public.publish_and_assign_quiz(p_quiz_version_id uuid,p_class_ids uuid[],p_instructions text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_status public.content_version_status; v_class uuid; v_assignment public.quiz_assignments; v_assignments jsonb:='[]'::jsonb;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  if coalesce(cardinality(p_class_ids),0) not between 1 and 100 or array_position(p_class_ids,null) is not null then
    raise exception 'SELECT_TARGET_CLASSES' using errcode='22023';
  end if;
  select status into v_status from public.quiz_versions where id=p_quiz_version_id;
  if not found then raise exception 'QUIZ_SCOPE_DENIED' using errcode='42501'; end if;
  if v_status='draft'::public.content_version_status then perform public.publish_quiz_version(p_quiz_version_id); end if;
  for v_class in select distinct unnest(p_class_ids) order by 1 loop
    v_assignment:=public.assign_published_quiz(v_class,p_quiz_version_id,p_instructions=>p_instructions);
    v_assignments:=v_assignments||jsonb_build_array(to_jsonb(v_assignment));
  end loop;
  return jsonb_build_object('quiz_version_id',p_quiz_version_id,'assignments',v_assignments);
end $$;
revoke all on function public.publish_and_assign_quiz(uuid,uuid[],text) from public,anon;
grant execute on function public.publish_and_assign_quiz(uuid,uuid[],text) to authenticated;

-- Reorder through the existing validated/audited mutation API. Content edits
-- and reordered items return to draft review. Two passes avoid unique slots.
create function public.reorder_quiz_items(p_quiz_version_id uuid,p_item_ids uuid[])
returns void language plpgsql security invoker set search_path='' as $$
declare v_item public.quiz_items; v_id uuid; v_max integer; v_slots integer[]; v_index integer:=0;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quiz_version_id::text,1));
  if not exists(select 1 from public.quiz_versions v join public.quizzes q on q.id=v.quiz_id
    where v.id=p_quiz_version_id and v.status='draft'::public.content_version_status
      and q.instructor_id=(select auth.uid()) and q.archived_at is null) then
    raise exception 'DRAFT_ACTIVE_QUIZ_REQUIRED' using errcode='42501';
  end if;
  if p_item_ids is null or array_position(p_item_ids,null) is not null
    or cardinality(p_item_ids)<>(select count(distinct id) from unnest(p_item_ids) id)
    or cardinality(p_item_ids)<>(select count(*) from public.quiz_items where quiz_version_id=p_quiz_version_id and removed_at is null)
    or exists(select 1 from unnest(p_item_ids) requested(item_id) where not exists(select 1 from public.quiz_items qi where qi.id=requested.item_id and qi.quiz_version_id=p_quiz_version_id and qi.removed_at is null)) then
    raise exception 'QUIZ_ORDER_CHANGED_REFRESH_REQUIRED' using errcode='22023';
  end if;
  select coalesce(max(order_index),0) into v_max from public.quiz_items where quiz_version_id=p_quiz_version_id;
  select array_agg(order_index order by order_index) into v_slots from public.quiz_items where quiz_version_id=p_quiz_version_id and removed_at is null;
  foreach v_id in array p_item_ids loop
    v_index:=v_index+1;
    select * into v_item from public.quiz_items where id=v_id;
    perform public.upsert_quiz_item(p_quiz_version_id,v_item.item_type,v_item.prompt,v_item.options,v_item.correct_answer,v_item.explanation,v_max+v_index,v_item.id);
  end loop;
  -- Keep removed items' reserved slots intact.
  v_index:=0;
  foreach v_id in array p_item_ids loop
    v_index:=v_index+1;
    select * into v_item from public.quiz_items where id=v_id;
    perform public.upsert_quiz_item(p_quiz_version_id,v_item.item_type,v_item.prompt,v_item.options,v_item.correct_answer,v_item.explanation,v_slots[v_index],v_item.id);
  end loop;
end $$;
revoke all on function public.reorder_quiz_items(uuid,uuid[]) from public,anon;
grant execute on function public.reorder_quiz_items(uuid,uuid[]) to authenticated;

create or replace function private.quiz_assignment_is_available(
  p_assignment_id uuid,
  p_learner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.quiz_assignments a
    join public.quiz_versions qv on qv.id = a.quiz_version_id
    join public.quizzes q on q.id = qv.quiz_id
    join public.classes c on c.id = a.class_id
    join public.class_memberships cm
      on cm.class_id = a.class_id and cm.learner_id = p_learner_id
    where a.id = p_assignment_id
      and a.status = 'active'::public.assignment_status
      and (a.available_at is null or a.available_at <= now())
      and (a.due_at is null or a.due_at >= now())
      and (qv.status = 'published'::public.content_version_status or exists (
        select 1 from private.quiz_attempt_claims claim
        join public.quiz_attempts attempt on attempt.id=claim.attempt_id
        where claim.learner_id=p_learner_id and claim.quiz_id=q.id
          and attempt.quiz_assignment_id=a.id and attempt.status='in_progress'::public.quiz_attempt_status
      ))
      and q.archived_at is null
      and c.status = 'active'::public.class_status
      and cm.status = 'active'::public.membership_status
  )
$$;

create or replace function public.get_available_learner_quizzes()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not public.is_learner() then
      (select jsonb_build_object('error', 'LEARNER_REQUIRED'))
    else coalesce((
      select jsonb_agg(payload order by class_title, title)
      from (
        select distinct on (q.id) jsonb_build_object(
          'assignment_id', a.id,
          'quiz_version_id', coalesce(latest.quiz_version_id,a.quiz_version_id),
          'quiz_id', q.id,
          'title', q.title,
          'description', q.description,
          'topic', q.topic,
          'instructions', coalesce(a.instructions, qv.instructions),
          'class_id', c.id,
          'class_title', c.title,
          'coc_code', cm.coc_code,
          'coc_title', cm.title,
          'question_count', (
            select count(*) from public.quiz_items qi
            where qi.quiz_version_id = coalesce(latest.quiz_version_id,qv.id)
              and qi.removed_at is null
              and qi.review_status = 'approved'::public.quiz_item_review_status
          ),
          'available_at', a.available_at,
          'due_at', a.due_at,
          'attempts_allowed', 1,
          'is_available', private.quiz_assignment_is_available(coalesce(latest.quiz_assignment_id,a.id), (select auth.uid())),
          'attempt_id', latest.id,
          'attempt_status', latest.status,
          'answered_count', coalesce(latest.answered_count, 0),
          'started_at', latest.started_at,
          'completed_at', latest.completed_at
        ) as payload,
        c.title as class_title,
        q.title as title
        from public.quiz_assignments a
        join public.quiz_versions qv on qv.id = a.quiz_version_id
        join public.quizzes q on q.id = qv.quiz_id
        join public.classes c on c.id = a.class_id
        join public.class_memberships membership
          on membership.class_id = a.class_id
         and membership.learner_id = (select auth.uid())
         and membership.status = 'active'::public.membership_status
        left join public.coc_modules cm on cm.id = q.coc_module_id
        left join lateral (
          select qa.id, qa.quiz_version_id, qa.quiz_assignment_id, qa.status, qa.started_at, qa.completed_at,
            (select count(*) from public.quiz_answers ans where ans.quiz_attempt_id = qa.id) as answered_count
          from private.quiz_attempt_claims claim
          join public.quiz_attempts qa on qa.id=claim.attempt_id
          where claim.quiz_id = q.id
            and qa.learner_id = (select auth.uid())
          order by (qa.status = 'in_progress'::public.quiz_attempt_status) desc,
            qa.started_at desc
          limit 1
        ) latest on true
        where a.status = 'active'::public.assignment_status
          and (qv.status = 'published'::public.content_version_status or exists (
            select 1 from private.quiz_attempt_claims claim
            join public.quiz_attempts attempt on attempt.id=claim.attempt_id
            where claim.learner_id=(select auth.uid()) and claim.quiz_id=q.id
              and attempt.quiz_assignment_id=a.id
          ))
          and q.archived_at is null
          and c.status = 'active'::public.class_status
        order by q.id,(latest.quiz_assignment_id=a.id) desc nulls last,qv.version_number desc,c.title,a.id
      ) scoped
    ), '[]'::jsonb)
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
  v_assignment public.quiz_assignments;
  v_attempt public.quiz_attempts;
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
    if not private.quiz_assignment_is_available(v_attempt.quiz_assignment_id,(select auth.uid())) then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
    end if;
  else
    -- Recheck access after waiting for a concurrent start/publication.
    if not private.quiz_assignment_is_available(p_assignment_id,(select auth.uid())) then
      raise exception 'QUIZ_NOT_AVAILABLE' using errcode='42501';
    end if;
    insert into public.quiz_attempts(learner_id,class_id,quiz_assignment_id,quiz_version_id,client_start_key)
    values((select auth.uid()),v_assignment.class_id,v_assignment.id,v_assignment.quiz_version_id,p_client_start_key)
    returning * into v_attempt;
    perform private.write_audit_event('quiz_attempt.started','quiz_attempt',v_attempt.id,null,
      jsonb_build_object('assignment_id',v_assignment.id,'quiz_version_id',v_assignment.quiz_version_id,'quiz_id',v_quiz_id));
  end if;

  select jsonb_build_object(
    'attempt_id', v_attempt.id,
    'status', v_attempt.status,
    'started_at', v_attempt.started_at,
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

  insert into public.quiz_answers(
    quiz_attempt_id, quiz_item_id, quiz_version_id, answer
  ) values(
    v_attempt.id, p_item_id, v_attempt.quiz_version_id, to_jsonb(btrim(p_answer))
  )
  on conflict (quiz_attempt_id, quiz_item_id)
  do update set answer = excluded.answer, is_correct = null, answered_at = now()
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

  update public.quiz_attempts set
    status = 'submitted'::public.quiz_attempt_status,
    submission_key = p_submission_key,
    submitted_at = now()
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
