-- Private, service-only upload journal and transactional metadata finalization.
-- Existing multipart APIs and historical resources/submissions remain valid.
begin;
set local lock_timeout='5s';

create table public.file_upload_intents (
  id uuid primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  purpose text not null check(purpose in ('resource','homework')),
  target_id uuid not null,
  bucket text not null check(bucket in ('learning-resources','homework-files')),
  object_path text not null unique,
  spec jsonb not null check(octet_length(spec::text)<=6000),
  state text not null default 'pending' check(state in ('pending','verifying','complete','rejected','cleaning','cleaned')),
  expires_at timestamptz not null,
  lease_id uuid,
  lease_until timestamptz,
  result jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.file_upload_intents enable row level security;
revoke all on public.file_upload_intents from public,anon,authenticated;
grant select,insert,update on public.file_upload_intents to service_role;
create index file_upload_cleanup_idx on public.file_upload_intents(expires_at) where state<>'complete' and state<>'cleaned';
create index file_upload_actor_idx on public.file_upload_intents(actor_id,expires_at);

create function private.assert_file_upload_scope(p_actor uuid,p_purpose text,p_target uuid)
returns void language plpgsql security invoker set search_path='' as $$
declare v_role public.user_role; h public.homework_assignments;
begin
  select role into v_role from public.profiles where user_id=p_actor and status='active' for share;
  if not found then raise exception 'ACTIVE_ACCOUNT_REQUIRED' using errcode='42501'; end if;
  if p_purpose='resource' then
    perform 1 from public.classes where id=p_target and instructor_id=p_actor and status='active' and v_role='instructor' for share;
    if not found then raise exception 'CLASS_SCOPE_DENIED' using errcode='42501'; end if;
  elsif p_purpose='homework' then
    select * into h from public.homework_assignments where id=p_target;
    if not found or not exists(select 1 from public.classes where id=h.class_id and status='active') or not (
      (v_role='instructor' and h.instructor_id=p_actor and h.status='draft') or
      (v_role='learner' and h.status='published' and exists(select 1 from public.class_memberships where class_id=h.class_id and learner_id=p_actor and status='active')
        and not exists(select 1 from public.homework_submissions where assignment_id=h.id and learner_id=p_actor))
    ) then raise exception 'HOMEWORK_UPLOAD_DENIED' using errcode='42501'; end if;
  else raise exception 'UPLOAD_PURPOSE_INVALID' using errcode='22023'; end if;
end $$;
revoke all on function private.assert_file_upload_scope(uuid,text,uuid) from public,anon,authenticated;
grant execute on function private.assert_file_upload_scope(uuid,text,uuid) to service_role;

create function public.manage_file_upload(p_actor uuid,p_action text,p_spec jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  u public.file_upload_intents; v_id uuid; v_purpose text; v_target uuid;
  v_mime text; v_size bigint; v_ext text; v_bucket text; v_path text;
  v_role public.user_role; v_result jsonb; v_batch jsonb:='[]';
begin
  if p_action='claim_cleanup' then
    for u in select * from public.file_upload_intents
      where state not in ('complete','cleaned') and expires_at<clock_timestamp()
        and (lease_until is null or lease_until<clock_timestamp())
      order by expires_at for update skip locked limit 20
    loop
      -- Any historical metadata reference protects the bytes, including archives.
      if exists(select 1 from public.learning_resources where storage_path=u.object_path and storage_bucket=u.bucket) or
         exists(select 1 from public.homework_files where object_path=u.object_path and u.bucket='homework-files') then
        update public.file_upload_intents set state='complete',updated_at=clock_timestamp() where id=u.id;
      else
        update public.file_upload_intents set state='cleaning',lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '10 minutes',updated_at=clock_timestamp()
          where id=u.id returning * into u;
        v_batch:=v_batch||jsonb_build_array(to_jsonb(u));
      end if;
    end loop;
    return v_batch;
  end if;
  v_id:=(p_spec->>'id')::uuid;
  if p_action='prepare' then
    v_purpose:=p_spec->>'purpose'; v_target:=(p_spec->>'target_id')::uuid;
    perform private.assert_file_upload_scope(p_actor,v_purpose,v_target);
    v_mime:=p_spec->>'mime'; v_size:=(p_spec->>'size')::bigint;
    v_ext:=case v_mime when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png'
      when 'image/webp' then 'webp' when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' when 'text/plain' then 'txt' end;
    if v_id is null or coalesce(p_spec->>'sha256','')!~'^[a-f0-9]{64}$' or v_size is null or v_size<1 or v_ext is null or
      (v_purpose='resource' and (v_size>52428800 or v_mime='text/plain' or length(btrim(coalesce(p_spec->>'title',''))) not between 2 and 300 or length(coalesce(p_spec->>'description',''))>2000)) or
      (v_purpose='homework' and (v_size>10485760 or v_mime in ('video/mp4','video/webm'))) then
      raise exception 'UPLOAD_SPEC_INVALID' using errcode='22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended(p_actor::text,92831));
    select * into u from public.file_upload_intents where id=v_id for update;
    if found then
      if u.actor_id<>p_actor or u.spec<>p_spec then raise exception 'UPLOAD_IDENTITY_MISMATCH' using errcode='42501'; end if;
      if u.state='complete' then return to_jsonb(u); end if;
      if u.state='cleaning' or (u.state='verifying' and u.lease_until>clock_timestamp()) then raise exception 'UPLOAD_BUSY' using errcode='55000'; end if;
      if u.state='rejected' then raise exception 'UPLOAD_REJECTED' using errcode='22023'; end if;
    end if;
    if (select count(*) from public.file_upload_intents where actor_id=p_actor and id<>v_id and state not in ('complete','cleaned') and expires_at>clock_timestamp())>=10 then
      raise exception 'UPLOAD_PENDING_LIMIT' using errcode='55000'; end if;
    v_bucket:=case v_purpose when 'resource' then 'learning-resources' else 'homework-files' end;
    -- A fresh path after cleanup keeps a delayed old delete/upload from touching a new generation.
    v_path:=case v_purpose when 'resource' then format('classes/%s/resources/%s/%s.%s',v_target,v_id,gen_random_uuid(),v_ext)
      else format('%s/%s/%s-%s.%s',v_target,p_actor,v_id,gen_random_uuid(),v_ext) end;
    insert into public.file_upload_intents(id,actor_id,purpose,target_id,bucket,object_path,spec,expires_at)
    values(v_id,p_actor,v_purpose,v_target,v_bucket,v_path,p_spec,clock_timestamp()+interval '125 minutes')
    on conflict(id) do update set state='pending',
      object_path=case when file_upload_intents.state='cleaned' then excluded.object_path else file_upload_intents.object_path end,
      expires_at=excluded.expires_at,lease_id=null,lease_until=null,updated_at=clock_timestamp()
    returning * into u;
    return to_jsonb(u);
  end if;
  select * into u from public.file_upload_intents where id=v_id for update;
  if not found then raise exception 'UPLOAD_NOT_FOUND' using errcode='P0002'; end if;
  if p_action='finish_cleanup' then
    if u.state<>'cleaning' or u.lease_id is distinct from (p_spec->>'lease_id')::uuid then raise exception 'CLEANUP_LEASE_INVALID' using errcode='55000'; end if;
    update public.file_upload_intents set state='cleaned',lease_id=null,lease_until=null,updated_at=clock_timestamp() where id=u.id;
    return '{}'::jsonb;
  end if;
  if u.actor_id is distinct from p_actor then raise exception 'UPLOAD_SCOPE_DENIED' using errcode='42501'; end if;
  perform private.assert_file_upload_scope(p_actor,u.purpose,u.target_id);
  if u.state='complete' then return to_jsonb(u); end if;
  if u.expires_at<=clock_timestamp() or u.state in ('cleaning','cleaned','rejected') then raise exception 'UPLOAD_EXPIRED_OR_REJECTED' using errcode='55000'; end if;
  if p_action='claim' then
    if u.state='verifying' and u.lease_until>clock_timestamp() then raise exception 'UPLOAD_BUSY' using errcode='55000'; end if;
    update public.file_upload_intents set state='verifying',lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '5 minutes',updated_at=clock_timestamp()
      where id=u.id returning * into u;
    return to_jsonb(u);
  end if;
  if u.state<>'verifying' or u.lease_id is distinct from (p_spec->>'lease_id')::uuid or u.lease_until<=clock_timestamp() then
    raise exception 'UPLOAD_LEASE_INVALID' using errcode='55000'; end if;
  if p_action in ('reject','retry') then
    update public.file_upload_intents set state=case p_action when 'reject' then 'rejected' else 'pending' end,
      lease_id=null,lease_until=null,updated_at=clock_timestamp() where id=u.id;
    return '{}'::jsonb;
  end if;
  if p_action<>'commit' then raise exception 'UPLOAD_ACTION_INVALID' using errcode='22023'; end if;
  select role into v_role from public.profiles where user_id=p_actor;
  if u.purpose='homework' then
    -- Reuse the existing authoritative attach transaction, limits and audit contract.
    v_result:=public.manage_homework(p_actor,'attach',jsonb_build_object('assignment_id',u.target_id,'file_id',u.id,
      'kind',case v_role when 'instructor' then 'instruction' else 'answer' end,'filename',u.spec->>'filename',
      'object_path',u.object_path,'mime_type',u.spec->>'mime','size_bytes',u.spec->'size'));
  else
    insert into public.learning_resources(id,class_id,title,description,storage_bucket,storage_path,mime_type,size_bytes,status,uploaded_by)
    values(u.id,u.target_id,btrim(u.spec->>'title'),nullif(btrim(u.spec->>'description'),''),u.bucket,u.object_path,u.spec->>'mime',(u.spec->>'size')::bigint,'active',p_actor)
    returning to_jsonb(learning_resources) into v_result;
    insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,new_value,metadata)
    values(p_actor,v_role,'learning_resource.created','learning_resource',u.id,v_result,
      jsonb_build_object('class_id',u.target_id,'upload_method','signed_storage','mime_type',u.spec->>'mime','size_bytes',u.spec->'size'));
  end if;
  update public.file_upload_intents set state='complete',result=v_result,lease_id=null,lease_until=null,updated_at=clock_timestamp() where id=u.id returning * into u;
  return to_jsonb(u);
end $$;
revoke all on function public.manage_file_upload(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.manage_file_upload(uuid,text,jsonb) to service_role;
commit;
