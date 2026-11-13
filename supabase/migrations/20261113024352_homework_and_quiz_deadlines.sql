-- Independent supplementary homework and class-specific quiz availability.
-- Additive only. No new SECURITY DEFINER functions, historical rewrites or resets.
begin;
set local lock_timeout = '5s';

create function private.activity_server_now() returns timestamptz
language sql volatile security invoker set search_path = ''
as $$ select pg_catalog.clock_timestamp() $$;
revoke all on function private.activity_server_now() from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.activity_server_now() to service_role;

create table public.homework_assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete restrict,
  instructor_id uuid not null references auth.users(id) on delete restrict,
  title text not null check (length(btrim(title)) between 2 and 300),
  instructions text not null check (length(btrim(instructions)) between 1 and 20000),
  status text not null default 'draft' check (status in ('draft','published')),
  deadline_at timestamptz,
  published_at timestamptz,
  revision integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status <> 'published' or published_at is not null)
);
create index homework_class_status_idx on public.homework_assignments(class_id,status,created_at desc);
create index homework_instructor_idx on public.homework_assignments(instructor_id);

create table public.homework_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.homework_assignments(id) on delete restrict,
  learner_id uuid not null references auth.users(id) on delete restrict,
  answer text not null default '' check (length(answer) <= 20000),
  submitted_at timestamptz not null,
  effective_deadline_at timestamptz,
  deadline_revision integer not null,
  lateness_seconds numeric generated always as
    (case when effective_deadline_at is null then 0 else greatest(0,extract(epoch from submitted_at-effective_deadline_at)) end) stored,
  status text not null default 'submitted' check (status in ('submitted','graded')),
  feedback text check (length(feedback) <= 10000),
  score numeric check (score is null or (score >= 0 and score <= 100)),
  graded_at timestamptz,
  graded_by uuid references auth.users(id) on delete restrict,
  unique(assignment_id,learner_id),
  check ((status='graded') = (graded_at is not null and graded_by is not null))
);
create index homework_submissions_learner_idx on public.homework_submissions(learner_id,submitted_at desc);
create index homework_submissions_grader_idx on public.homework_submissions(graded_by);

create table public.homework_files (
  id uuid primary key,
  assignment_id uuid not null references public.homework_assignments(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  kind text not null check (kind in ('instruction','answer')),
  submission_id uuid references public.homework_submissions(id) on delete restrict,
  filename text not null check (length(filename) between 1 and 200),
  object_path text not null unique,
  mime_type text not null,
  size_bytes integer not null check (size_bytes between 1 and 10485760),
  created_at timestamptz not null default clock_timestamp(),
  check (kind='answer' or submission_id is null)
);
create index homework_files_assignment_idx on public.homework_files(assignment_id,kind);
create index homework_files_submission_idx on public.homework_files(submission_id);
create index homework_files_owner_idx on public.homework_files(owner_id);

alter table public.homework_assignments enable row level security;
alter table public.homework_submissions enable row level security;
alter table public.homework_files enable row level security;
revoke all on public.homework_assignments,public.homework_submissions,public.homework_files from anon,authenticated;
grant select on public.homework_assignments,public.homework_submissions,public.homework_files to authenticated;
grant all on public.homework_assignments,public.homework_submissions,public.homework_files to service_role;

create policy homework_read on public.homework_assignments for select to authenticated using (
  public.is_admin() or public.instructor_owns_class(class_id) or
  (status='published' and public.is_learner() and public.learner_is_enrolled(class_id,(select auth.uid()))
    and exists(select 1 from public.classes c where c.id=class_id and c.status='active'))
);
create policy homework_submission_read on public.homework_submissions for select to authenticated using (
  exists(select 1 from public.homework_assignments h where h.id=assignment_id and
    (public.is_admin() or public.instructor_owns_class(h.class_id) or (public.is_learner() and learner_id=(select auth.uid()))))
);
create policy homework_file_read on public.homework_files for select to authenticated using (
  exists(select 1 from public.homework_assignments h where h.id=assignment_id and
    (kind='instruction' or (public.is_learner() and owner_id=(select auth.uid())) or
     (submission_id is not null and (public.is_admin() or public.instructor_owns_class(h.class_id)))))
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('homework-files','homework-files',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp','text/plain'])
on conflict(id) do nothing;
create policy homework_storage_read on storage.objects for select to authenticated using (
  bucket_id='homework-files' and exists(select 1 from public.homework_files f where f.object_path=name)
);
-- No client upload/update/delete policy. The bounded, validated server upload
-- and service-only transaction below recheck role, membership and lifecycle.

create function public.manage_homework(p_actor uuid,p_action text,p_payload jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  v_role public.user_role;
  h public.homework_assignments;
  s public.homework_submissions;
  f public.homework_files;
  v_old jsonb;
  v_now timestamptz;
  v_ids uuid[];
begin
  select role into v_role from public.profiles where user_id=p_actor and status='active';
  if not found then raise exception 'ACTIVE_ACCOUNT_REQUIRED' using errcode='42501'; end if;
  if p_action='create' then
    if v_role<>'instructor' or not exists(select 1 from public.classes where id=(p_payload->>'class_id')::uuid and instructor_id=p_actor and status='active') then
      raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode='42501';
    end if;
    insert into public.homework_assignments(class_id,instructor_id,title,instructions,deadline_at)
    values((p_payload->>'class_id')::uuid,p_actor,btrim(p_payload->>'title'),btrim(p_payload->>'instructions'),(p_payload->>'deadline_at')::timestamptz) returning * into h;
  else
    select * into h from public.homework_assignments where id=(p_payload->>'assignment_id')::uuid for update;
    if not found then raise exception 'HOMEWORK_NOT_FOUND' using errcode='P0002'; end if;
    if not exists(select 1 from public.classes where id=h.class_id and status='active' and
      ((v_role='instructor' and instructor_id=p_actor) or (v_role='learner' and exists(
        select 1 from public.class_memberships m where m.class_id=h.class_id and m.learner_id=p_actor and m.status='active')))) then
      raise exception 'HOMEWORK_SCOPE_DENIED' using errcode='42501';
    end if;
    v_old:=to_jsonb(h);
    if p_action in ('edit','publish','deadline','grade') and (v_role<>'instructor' or h.instructor_id<>p_actor) then
      raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode='42501';
    end if;
    if p_action='edit' then
      if h.status<>'draft' then raise exception 'DRAFT_HOMEWORK_REQUIRED' using errcode='55000'; end if;
      update public.homework_assignments set title=btrim(p_payload->>'title'),instructions=btrim(p_payload->>'instructions'),
        deadline_at=(p_payload->>'deadline_at')::timestamptz,revision=revision+1,updated_at=clock_timestamp() where id=h.id returning * into h;
    elsif p_action='publish' then
      if h.status='published' then return to_jsonb(h); end if;
      update public.homework_assignments set status='published',published_at=clock_timestamp(),updated_at=clock_timestamp() where id=h.id returning * into h;
    elsif p_action='deadline' then
      update public.homework_assignments set deadline_at=(p_payload->>'deadline_at')::timestamptz,revision=revision+1,updated_at=clock_timestamp()
      where id=h.id returning * into h;
    elsif p_action='submit' then
      if v_role<>'learner' or h.status<>'published' then raise exception 'PUBLISHED_HOMEWORK_REQUIRED' using errcode='42501'; end if;
      select * into s from public.homework_submissions where assignment_id=h.id and learner_id=p_actor;
      if found then return to_jsonb(s); end if;
      select coalesce(array_agg(x::uuid),'{}'::uuid[]) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'file_ids','[]'::jsonb)) x;
      if cardinality(v_ids)>5 or cardinality(v_ids)<>(select count(distinct x) from unnest(v_ids) x) or
        cardinality(v_ids)<>(select count(*) from public.homework_files where id=any(v_ids) and assignment_id=h.id and owner_id=p_actor and kind='answer' and submission_id is null) then
        raise exception 'HOMEWORK_FILES_INVALID' using errcode='22023'; end if;
      if length(btrim(coalesce(p_payload->>'answer','')))=0 and cardinality(v_ids)=0 then
        raise exception 'ANSWER_OR_FILE_REQUIRED' using errcode='22023'; end if;
      v_now:=private.activity_server_now();
      insert into public.homework_submissions(assignment_id,learner_id,answer,submitted_at,effective_deadline_at,deadline_revision)
      values(h.id,p_actor,btrim(coalesce(p_payload->>'answer','')),v_now,h.deadline_at,h.revision) returning * into s;
      update public.homework_files set submission_id=s.id where id=any(v_ids);
      insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,new_value)
      values(p_actor,v_role,'homework.submitted','homework_submission',s.id,jsonb_build_object('assignment_id',h.id,'submitted_at',s.submitted_at,'effective_deadline_at',s.effective_deadline_at,'lateness_seconds',s.lateness_seconds));
      return to_jsonb(s);
    elsif p_action='grade' then
      select * into s from public.homework_submissions where id=(p_payload->>'submission_id')::uuid and assignment_id=h.id for update;
      if not found then raise exception 'SUBMISSION_NOT_FOUND' using errcode='P0002'; end if;
      if s.status='graded' then return to_jsonb(s); end if;
      update public.homework_submissions set status='graded',feedback=nullif(btrim(p_payload->>'feedback'),''),score=(p_payload->>'score')::numeric,
        graded_by=p_actor,graded_at=private.activity_server_now() where id=s.id returning * into s;
      insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,new_value)
      values(p_actor,v_role,'homework.graded','homework_submission',s.id,jsonb_build_object('assignment_id',h.id,'graded_at',s.graded_at,'score',s.score));
      return to_jsonb(s);
    elsif p_action='attach' then
      if not ((v_role='instructor' and h.instructor_id=p_actor and h.status='draft' and p_payload->>'kind'='instruction') or
        (v_role='learner' and h.status='published' and p_payload->>'kind'='answer' and not exists(
          select 1 from public.homework_submissions where assignment_id=h.id and learner_id=p_actor))) then
        raise exception 'HOMEWORK_UPLOAD_DENIED' using errcode='42501'; end if;
      select * into f from public.homework_files where id=(p_payload->>'file_id')::uuid and owner_id=p_actor and assignment_id=h.id;
      if found then return to_jsonb(f); end if;
      if (select count(*) from public.homework_files where assignment_id=h.id and owner_id=p_actor and kind=p_payload->>'kind')>=5 then
        raise exception 'HOMEWORK_FILE_LIMIT' using errcode='22023'; end if;
      insert into public.homework_files(id,assignment_id,owner_id,kind,filename,object_path,mime_type,size_bytes)
      values((p_payload->>'file_id')::uuid,h.id,p_actor,p_payload->>'kind',p_payload->>'filename',p_payload->>'object_path',p_payload->>'mime_type',(p_payload->>'size_bytes')::integer) returning * into f;
      return to_jsonb(f);
    else raise exception 'HOMEWORK_ACTION_INVALID' using errcode='22023'; end if;
  end if;
  insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,old_value,new_value)
  values(p_actor,v_role,'homework.'||p_action,'homework_assignment',h.id,v_old,to_jsonb(h));
  return to_jsonb(h);
end $$;
revoke all on function public.manage_homework(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.manage_homework(uuid,text,jsonb) to service_role;

-- Service-only invoker, mirroring homework's narrow server-side boundary.
create function public.set_quiz_assignment_deadline(p_actor uuid,p_assignment_id uuid,p_deadline timestamptz,p_reopen boolean default false)
returns public.quiz_assignments language plpgsql security invoker set search_path='' as $$
declare a public.quiz_assignments; v_old timestamptz; v_now timestamptz; v_quiz uuid;
begin
  select * into a from public.quiz_assignments where id=p_assignment_id for update;
  if not found then raise exception 'QUIZ_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  if not exists(select 1 from public.profiles p join public.classes c on c.instructor_id=p.user_id
    join public.quiz_versions v on v.id=a.quiz_version_id join public.quizzes q on q.id=v.quiz_id
    where p.user_id=p_actor and p.role='instructor' and p.status='active' and c.id=a.class_id and c.status='active'
      and q.instructor_id=p_actor and q.archived_at is null and v.status='published') or a.status<>'active' then
    raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode='42501'; end if;
  v_now:=private.activity_server_now(); v_old:=a.due_at;
  if p_deadline is not null and (p_deadline<=v_now or (a.available_at is not null and p_deadline<=a.available_at)) then
    raise exception 'FUTURE_DEADLINE_REQUIRED' using errcode='22023'; end if;
  if p_reopen and (a.due_at is null or a.due_at>v_now or p_deadline is null) then
    raise exception 'EXPIRED_QUIZ_AND_FUTURE_DEADLINE_REQUIRED' using errcode='22023'; end if;
  if not p_reopen and a.due_at is not null and a.due_at<=v_now then
    raise exception 'USE_REOPEN_QUIZ' using errcode='22023'; end if;
  select quiz_id into v_quiz from public.quiz_versions where id=a.quiz_version_id;
  update public.quiz_assignments set due_at=p_deadline where id=a.id returning * into a;
  insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,old_value,new_value,metadata,created_at)
  values(p_actor,'instructor',case when p_reopen then 'quiz.reopened' else 'quiz.deadline_changed' end,'quiz_assignment',a.id,
    jsonb_build_object('deadline',v_old),jsonb_build_object('deadline',p_deadline),jsonb_build_object('quiz_id',v_quiz,'class_id',a.class_id,'reopened_at',case when p_reopen then v_now end),v_now);
  return a;
end $$;
revoke all on function public.set_quiz_assignment_deadline(uuid,uuid,timestamptz,boolean) from public,anon,authenticated;
grant execute on function public.set_quiz_assignment_deadline(uuid,uuid,timestamptz,boolean) to service_role;

-- Additional quiz RPC replacements follow, retaining the existing elevated
-- endpoints and canonical one-attempt claims unchanged.

create or replace function private.quiz_assignment_is_available(
  p_assignment_id uuid,
  p_learner_id uuid
)
returns boolean
language sql
volatile
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
      and (a.available_at is null or a.available_at <= private.activity_server_now())
      and (a.due_at is null or a.due_at > private.activity_server_now())
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
volatile
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
          'due_at', effective.due_at,
          'server_now', private.activity_server_now(),
          'closed_reason',case when effective.due_at<=private.activity_server_now() then 'deadline_passed' else null end,
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
        join public.quiz_assignments effective on effective.id=coalesce(latest.quiz_assignment_id,a.id)
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
    perform 1 from public.quiz_assignments where id=v_attempt.quiz_assignment_id for share;
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

  insert into public.quiz_answers(
    quiz_attempt_id, quiz_item_id, quiz_version_id, answer
  ) values(
    v_attempt.id, p_item_id, v_attempt.quiz_version_id, to_jsonb(btrim(p_answer))
  )
  on conflict (quiz_attempt_id, quiz_item_id)
  do update set answer = excluded.answer, is_correct = null, answered_at = private.activity_server_now()
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

  update public.quiz_attempts set
    status = 'submitted'::public.quiz_attempt_status,
    submission_key = p_submission_key,
    submitted_at = private.activity_server_now()
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

drop function public.publish_and_assign_quiz(uuid,uuid[],text);
create function public.publish_and_assign_quiz(p_quiz_version_id uuid,p_class_ids uuid[],p_instructions text default null,p_due_at timestamptz default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_status public.content_version_status; v_class uuid; v_assignment public.quiz_assignments; v_assignments jsonb:='[]'::jsonb;
begin
  if p_due_at is not null and p_due_at<=clock_timestamp() then raise exception 'FUTURE_DEADLINE_REQUIRED' using errcode='22023'; end if;
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  if coalesce(cardinality(p_class_ids),0) not between 1 and 100 or array_position(p_class_ids,null) is not null then
    raise exception 'SELECT_TARGET_CLASSES' using errcode='22023';
  end if;
  select status into v_status from public.quiz_versions where id=p_quiz_version_id;
  if not found then raise exception 'QUIZ_SCOPE_DENIED' using errcode='42501'; end if;
  if v_status='draft'::public.content_version_status then perform public.publish_quiz_version(p_quiz_version_id); end if;
  for v_class in select distinct unnest(p_class_ids) order by 1 loop
    v_assignment:=public.assign_published_quiz(v_class,p_quiz_version_id,p_due_at=>p_due_at,p_instructions=>p_instructions);
    v_assignments:=v_assignments||jsonb_build_array(to_jsonb(v_assignment));
  end loop;
  return jsonb_build_object('quiz_version_id',p_quiz_version_id,'assignments',v_assignments);
end $$;

revoke all on function public.publish_and_assign_quiz(uuid,uuid[],text,timestamptz) from public,anon;
grant execute on function public.publish_and_assign_quiz(uuid,uuid[],text,timestamptz) to authenticated;

do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
   alter publication supabase_realtime add table public.homework_assignments,public.homework_submissions;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
