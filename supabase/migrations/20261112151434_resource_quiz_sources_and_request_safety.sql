-- Additive request guards only. Existing attempts, grades and published items
-- are untouched. Existing definer RPC keeps its signature and authorization.
begin;

create unique index ai_quiz_generations_request_identity
  on public.ai_quiz_generations(instructor_id, quiz_version_id, (input_context->>'request_id'))
  where input_context->>'request_id' is not null;

create table public.resource_upload_jobs (
  id uuid primary key,
  class_id uuid not null references public.classes(id) on delete restrict,
  instructor_id uuid not null references public.profiles(user_id) on delete restrict,
  storage_path text not null unique,
  state text not null default 'pending' check (state in ('pending', 'complete', 'cleanup_required', 'cleaned')),
  updated_at timestamptz not null default now()
);
alter table public.resource_upload_jobs enable row level security;
revoke all on public.resource_upload_jobs from public, anon, authenticated;
grant select, insert, update on public.resource_upload_jobs to service_role;
comment on table public.resource_upload_jobs is 'Server-only upload compensation journal; no document text or credentials. Interrupted uploads can be reconciled without deleting learner history.';

create or replace function public.begin_ai_quiz_generation(
  p_quiz_version_id uuid, p_provider text, p_model text,
  p_input_context jsonb, p_requested_count integer
)
returns public.ai_quiz_generations
language plpgsql security definer set search_path = ''
as $$
declare v_generation public.ai_quiz_generations;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  if btrim(coalesce(p_provider,'')) <> 'openrouter'
     or length(btrim(coalesce(p_model,''))) not between 2 and 120
     or p_requested_count is null or p_requested_count not between 1 and 10
     or jsonb_typeof(coalesce(p_input_context,'{}'::jsonb)) <> 'object'
     or octet_length(coalesce(p_input_context,'{}'::jsonb)::text) > 16000 then
    raise exception 'INVALID_AI_GENERATION_REQUEST' using errcode='22023';
  end if;
  if p_input_context ? 'request_id' and coalesce(p_input_context->>'request_id','') !~ '^[0-9a-f-]{36}$' then
    raise exception 'INVALID_AI_REQUEST_ID' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.quiz_versions qv join public.quizzes q on q.id=qv.quiz_id
    where qv.id=p_quiz_version_id and qv.status='draft'::public.content_version_status
      and q.instructor_id=(select auth.uid()) and q.archived_at is null
  ) then raise exception 'QUIZ_VERSION_SCOPE_OR_STATE_DENIED' using errcode='42501'; end if;

  -- One provider/processing request per instructor at a time across devices.
  perform pg_advisory_xact_lock(hashtextextended((select auth.uid())::text, 68411));
  if p_input_context ? 'request_id' then
    select * into v_generation from public.ai_quiz_generations
      where instructor_id=(select auth.uid()) and quiz_version_id=p_quiz_version_id
        and input_context->>'request_id'=p_input_context->>'request_id';
    if found then
      if v_generation.input_context <> p_input_context or v_generation.requested_count <> p_requested_count then
        raise exception 'AI_REQUEST_ID_REUSED' using errcode='22023';
      end if;
      if v_generation.status='requested'::public.ai_generation_status then
        raise exception 'AI_GENERATION_IN_PROGRESS' using errcode='55000';
      end if;
      return v_generation;
    end if;
  end if;
  if exists (select 1 from public.ai_quiz_generations where instructor_id=(select auth.uid())
    and status='requested'::public.ai_generation_status and requested_at > now()-interval '5 minutes') then
    raise exception 'AI_GENERATION_IN_PROGRESS' using errcode='55000';
  end if;
  insert into public.ai_quiz_generations(instructor_id,quiz_version_id,provider,model,input_context,requested_count)
    values((select auth.uid()),p_quiz_version_id,'openrouter',btrim(p_model),coalesce(p_input_context,'{}'::jsonb),p_requested_count)
    returning * into v_generation;
  perform private.write_audit_event('quiz.ai_draft.requested','ai_quiz_generation',v_generation.id,null,
    jsonb_build_object('quiz_version_id',p_quiz_version_id,'provider','openrouter','model',v_generation.model,'requested_count',p_requested_count));
  return v_generation;
end
$$;
revoke all on function public.begin_ai_quiz_generation(uuid,text,text,jsonb,integer) from public, anon;
grant execute on function public.begin_ai_quiz_generation(uuid,text,text,jsonb,integer) to authenticated;

commit;
