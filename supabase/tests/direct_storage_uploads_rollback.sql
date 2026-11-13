begin;
create temp table direct_upload_test as select gen_random_uuid() teacher,gen_random_uuid() other_teacher,
  gen_random_uuid() learner,gen_random_uuid() class_id,gen_random_uuid() upload_id,gen_random_uuid() homework_id;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',id||'@direct-upload.invalid','',
  '{"provider":"email","providers":["email"]}','{"full_name":"Direct upload rollback fixture"}',now(),now()
from direct_upload_test cross join lateral(values(teacher),(other_teacher),(learner)) ids(id);
update public.profiles set role='instructor' where user_id in(select teacher from direct_upload_test union select other_teacher from direct_upload_test);
insert into public.classes(id,title,class_code,instructor_id,created_by)
select class_id,'Direct upload rollback','DU-'||left(class_id::text,8),teacher,teacher from direct_upload_test;
grant all on direct_upload_test to service_role,authenticated;
do $$ begin
  if has_table_privilege('authenticated','public.file_upload_intents','SELECT') or
     has_function_privilege('authenticated','public.manage_file_upload(uuid,text,jsonb)','EXECUTE') or
     has_function_privilege('anon','public.manage_file_upload(uuid,text,jsonb)','EXECUTE') or
     (select prosecdef from pg_proc where oid='public.manage_file_upload(uuid,text,jsonb)'::regprocedure) then
    raise exception 'DIRECT_UPLOAD_PRIVILEGE_LEAK'; end if;
end $$;
set local role service_role;
do $$
declare t record; spec jsonb; u jsonb; again jsonb; claim jsonb; completed jsonb; denied boolean; h jsonb; path text;
begin
  select * into t from direct_upload_test;
  spec:=jsonb_build_object('id',t.upload_id,'purpose','resource','target_id',t.class_id,
    'filename','network.pdf','mime','application/pdf','size',52428800,'sha256',repeat('a',64),'title','Network resource','description','');
  denied:=false;
  begin perform public.manage_file_upload(t.other_teacher,'prepare',spec); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'FOREIGN_CLASS_UPLOAD_ALLOWED'; end if;
  denied:=false;
  begin perform public.manage_file_upload(t.learner,'prepare',spec); exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'LEARNER_RESOURCE_UPLOAD_ALLOWED'; end if;
  denied:=false;
  begin perform public.manage_file_upload(t.teacher,'prepare',spec||'{"size":52428801}'); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'OVERSIZE_RESOURCE_ALLOWED'; end if;
  u:=public.manage_file_upload(t.teacher,'prepare',spec);
  again:=public.manage_file_upload(t.teacher,'prepare',spec);
  if u->>'object_path'<>again->>'object_path' or (select count(*) from public.file_upload_intents where id=t.upload_id)<>1 then raise exception 'UPLOAD_RETRY_DUPLICATED'; end if;
  claim:=public.manage_file_upload(t.teacher,'claim',jsonb_build_object('id',t.upload_id));
  denied:=false;
  begin perform public.manage_file_upload(t.teacher,'claim',jsonb_build_object('id',t.upload_id)); exception when object_not_in_prerequisite_state then denied:=true; end;
  if not denied then raise exception 'DOUBLE_VERIFICATION_LEASE'; end if;
  denied:=false;
  begin perform public.manage_file_upload(t.teacher,'commit',jsonb_build_object('id',t.upload_id,'lease_id',gen_random_uuid())); exception when object_not_in_prerequisite_state then denied:=true; end;
  if not denied then raise exception 'FORGED_LEASE_ALLOWED'; end if;
  completed:=public.manage_file_upload(t.teacher,'commit',jsonb_build_object('id',t.upload_id,'lease_id',claim->>'lease_id'));
  again:=public.manage_file_upload(t.teacher,'prepare',spec);
  if completed->'result' is distinct from again->'result' or (select count(*) from public.learning_resources where id=t.upload_id)<>1 then raise exception 'METADATA_RETRY_DUPLICATED'; end if;
  h:=public.manage_homework(t.teacher,'create',jsonb_build_object('class_id',t.class_id,'title','Upload worksheet','instructions','Write a report.'));
  update direct_upload_test set homework_id=(h->>'id')::uuid;
  perform public.manage_homework(t.teacher,'publish',jsonb_build_object('assignment_id',h->>'id'));
end $$;
reset role;
insert into public.class_memberships(class_id,learner_id,enrolled_by) select class_id,learner,teacher from direct_upload_test;
set local role service_role;
do $$ declare t record; spec jsonb; u jsonb; claim jsonb; denied boolean:=false;
begin
  select * into t from direct_upload_test;
  spec:=jsonb_build_object('id',gen_random_uuid(),'purpose','homework','target_id',t.homework_id,'filename','answer.txt','mime','text/plain','size',10485761,'sha256',repeat('b',64),'title','','description','');
  begin perform public.manage_file_upload(t.learner,'prepare',spec); exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'OVERSIZE_HOMEWORK_ALLOWED'; end if;
  spec:=spec||'{"size":10485760}';
  u:=public.manage_file_upload(t.learner,'prepare',spec);
  claim:=public.manage_file_upload(t.learner,'claim',jsonb_build_object('id',u->>'id'));
  update public.class_memberships set status='deactivated',deactivated_by=t.teacher,deactivated_at=clock_timestamp(),deactivation_reason='Synthetic rollback revocation' where class_id=t.class_id and learner_id=t.learner;
  denied:=false;
  begin perform public.manage_file_upload(t.learner,'commit',jsonb_build_object('id',u->>'id','lease_id',claim->>'lease_id')); exception when insufficient_privilege then denied:=true; end;
  if not denied or exists(select 1 from public.homework_files where id=(u->>'id')::uuid) then raise exception 'REVOKED_UPLOAD_COMMITTED'; end if;
  update public.file_upload_intents set expires_at=clock_timestamp()-interval '1 minute',lease_until=null where id=(u->>'id')::uuid;
  claim:=public.manage_file_upload(null,'claim_cleanup','{}');
  if jsonb_array_length(claim)<>1 then raise exception 'ORPHAN_CLEANUP_SCOPE_FAILED'; end if;
  perform public.manage_file_upload(null,'finish_cleanup',jsonb_build_object('id',claim->0->>'id','lease_id',claim->0->>'lease_id'));
  if not exists(select 1 from public.learning_resources where id=t.upload_id) then raise exception 'CLEANUP_REMOVED_RESOURCE_HISTORY'; end if;
end $$;
reset role;
rollback;
