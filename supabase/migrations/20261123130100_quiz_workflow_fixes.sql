-- Panel revision (2026-11-23): quiz workflow fixes.
--
-- 1. Quiz answers are typed text. A question that asks the learner to attach
--    or upload an image or file can never be satisfied, so learners could
--    "submit without the image". An approved, active item may not carry such a
--    request, and a version that contains one cannot be published
--    (QUIZ_UPLOAD_RESPONSE_UNSUPPORTED). Images and files are collected with
--    homework, whose submission rules are enforced (20261123090100). The
--    dashboard applies the same patterns before saving
--    (ByteQuest-Web-Dashboard/src/lib/quizzes/upload-requests.ts).
-- 2. assign_published_quiz refuses a deadline that has already passed, as
--    publish_and_assign_quiz already did (FUTURE_DEADLINE_REQUIRED).
--
-- Published items and existing assignments are not rewritten. The guards are
-- SECURITY INVOKER; no new SECURITY DEFINER function.
begin;
set local lock_timeout = '5s';

create or replace function private.quiz_text_requests_upload(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(btrim(p_text), '') <> '' and (
    -- "Attach one image of...", "and upload a screenshot", "Take a clear photo..."
    p_text ~* '(^|[.!?;:]\s*|\n\s*|\y(and|then|please|also)\s+)(attach|upload|submit|send|include|provide|take|capture|add)\s+(a|an|one|two|three|your|the)\s+([a-z-]+\s+){0,2}(images?|photos?|photographs?|pictures?|screenshots?|snapshots?)\y'
    -- "Required: written answer and one image file"
    or p_text ~* '\y(required?|requirements?)\y[^.!?\n]{0,60}\y(images?|photos?|pictures?|screenshots?)\s+(files?|attachments?)\y'
    -- "One image file is required"
    or p_text ~* '\y(one|an?|two|three|[0-9])\s+(images?|photos?|pictures?|screenshots?)\s+(files?|attachments?)\y[^.!?\n]{0,40}\y(required|needed)\y'
    -- "Upload your file.", "Attach your report document."
    or p_text ~* '(^|[.!?;:]\s*|\n\s*|\y(and|then|please|also)\s+)(attach|upload|submit|send)\s+(your|a|an|one)\s+([a-z-]+\s+)?(files?|documents?|pdfs?|attachments?)\y'
  )
$$;

create or replace function private.quiz_item_requests_upload(
  p_prompt text,
  p_scenario text,
  p_rubric jsonb
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select private.quiz_text_requests_upload(p_prompt)
    or private.quiz_text_requests_upload(p_scenario)
    or exists (
      select 1
      from jsonb_array_elements(case when jsonb_typeof(p_rubric) = 'array' then p_rubric else '[]'::jsonb end) as e(criterion)
      where jsonb_typeof(e.criterion) = 'object'
        and (private.quiz_text_requests_upload(e.criterion->>'criterion')
             or private.quiz_text_requests_upload(e.criterion->>'description'))
    )
$$;

-- Approval (or editing an approved item) refuses an upload request.
create or replace function private.reject_quiz_item_upload_request()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if new.review_status = 'approved'::public.quiz_item_review_status
     and new.removed_at is null
     and private.quiz_item_requests_upload(new.prompt, new.scenario, new.rubric) then
    raise exception 'QUIZ_UPLOAD_RESPONSE_UNSUPPORTED'
      using errcode = '22023',
            detail = coalesce(new.item_code, new.id::text),
            hint = 'Quiz answers are typed text. Collect images and files with homework.';
  end if;
  return new;
end
$$;

drop trigger if exists trg_quiz_items_reject_upload_request on public.quiz_items;
create trigger trg_quiz_items_reject_upload_request
  before insert or update of prompt, scenario, rubric, review_status, removed_at on public.quiz_items
  for each row execute function private.reject_quiz_item_upload_request();

-- Publishing re-checks items approved before this guard existed.
create or replace function private.reject_quiz_version_upload_request()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_items text;
begin
  select string_agg(coalesce(qi.item_code, qi.id::text), ', ' order by qi.order_index)
  into v_items
  from public.quiz_items qi
  where qi.quiz_version_id = new.id
    and qi.removed_at is null
    and private.quiz_item_requests_upload(qi.prompt, qi.scenario, qi.rubric);
  if v_items is not null then
    raise exception 'QUIZ_UPLOAD_RESPONSE_UNSUPPORTED'
      using errcode = '22023',
            detail = v_items,
            hint = 'Quiz answers are typed text. Collect images and files with homework.';
  end if;
  return new;
end
$$;

drop trigger if exists trg_quiz_versions_reject_upload_request on public.quiz_versions;
create trigger trg_quiz_versions_reject_upload_request
  before update of status on public.quiz_versions
  for each row
  when (new.status = 'published'::public.content_version_status
        and old.status is distinct from 'published'::public.content_version_status)
  execute function private.reject_quiz_version_upload_request();

revoke all on function private.quiz_text_requests_upload(text) from public, anon, authenticated;
revoke all on function private.quiz_item_requests_upload(text, text, jsonb) from public, anon, authenticated;
revoke all on function private.reject_quiz_item_upload_request() from public, anon, authenticated;
revoke all on function private.reject_quiz_version_upload_request() from public, anon, authenticated;
grant execute on function private.quiz_text_requests_upload(text) to service_role;
grant execute on function private.quiz_item_requests_upload(text, text, jsonb) to service_role;

-- Latest definition: 20261112111620_quiz_publishing_and_single_attempt.sql,
-- with a deadline that has already passed refused.
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
  if p_due_at is not null and p_due_at <= private.activity_server_now() then
    raise exception 'FUTURE_DEADLINE_REQUIRED' using errcode = '22023';
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

revoke all on function public.assign_published_quiz(uuid,uuid,timestamptz,timestamptz,integer,text) from public, anon;
grant execute on function public.assign_published_quiz(uuid,uuid,timestamptz,timestamptz,integer,text) to authenticated;

notify pgrst, 'reload schema';
commit;
