begin;
do $$
declare
  instructor uuid;
  q public.quizzes;
  v public.quiz_versions;
  g public.ai_quiz_generations;
  retry public.ai_quiz_generations;
  context jsonb := jsonb_build_object('request_id', gen_random_uuid(), 'source_mode','class_resource', 'classification','supplementary');
  denied boolean := false;
begin
  select user_id into instructor from public.profiles where role='instructor' and status='active' order by created_at limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',instructor,'role','authenticated')::text,true);
  q := public.create_instructor_quiz('Resource request regression','Network review');
  select * into v from public.quiz_versions where quiz_id=q.id;
  g := public.begin_ai_quiz_generation(v.id,'openrouter','qa-free',context,1);
  begin perform public.begin_ai_quiz_generation(v.id,'openrouter','qa-free',context,1);
  exception when sqlstate '55000' then denied:=true; end;
  if not denied then raise exception 'DUPLICATE_PROVIDER_REQUEST_ALLOWED'; end if;
  denied:=false;
  begin perform public.begin_ai_quiz_generation(v.id,'openrouter','qa-free',jsonb_build_object('request_id',gen_random_uuid()),1);
  exception when sqlstate '55000' then denied:=true; end;
  if not denied then raise exception 'CONCURRENT_GENERATION_ALLOWED'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',instructor,'role','service_role')::text,true);
  perform public.complete_ai_quiz_generation(g.id,instructor,'openrouter','qa-free','[{"item_type":"true_false","prompt":"A router connects different networks.","options":[],"correct_answer":"true","explanation":"Routers route network traffic."}]');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',instructor,'role','authenticated')::text,true);
  retry:=public.begin_ai_quiz_generation(v.id,'openrouter','qa-free',context,1);
  if retry.id<>g.id or retry.status<>'completed' then raise exception 'AI_IDEMPOTENCY_FAILED'; end if;
  if (select count(*) from public.quiz_items where quiz_version_id=v.id)<>1 then raise exception 'DUPLICATE_AI_DRAFT'; end if;
  if exists(select 1 from public.quiz_items where quiz_version_id=v.id and review_status<>'draft') then raise exception 'AI_AUTO_APPROVAL'; end if;
  if (select status from public.quiz_versions where id=v.id)<>'draft' then raise exception 'AI_AUTO_PUBLICATION'; end if;
  if has_table_privilege('authenticated','public.resource_upload_jobs','SELECT') or has_table_privilege('anon','public.resource_upload_jobs','INSERT') then raise exception 'UPLOAD_JOURNAL_EXPOSED'; end if;
  if not (select relrowsecurity from pg_class where oid='public.resource_upload_jobs'::regclass) then raise exception 'UPLOAD_JOURNAL_RLS_DISABLED'; end if;
end $$;
rollback;
