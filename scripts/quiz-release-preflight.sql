-- READ ONLY. Run against the approved release target before requesting the
-- final production write approval. Output contains counts/catalog metadata.
begin read only;
select current_database() database_name,current_setting('server_version') postgres_version;
select 'quizzes' relation,count(*) rows from public.quizzes
union all select 'versions',count(*) from public.quiz_versions
union all select 'items',count(*) from public.quiz_items
union all select 'assignments',count(*) from public.quiz_assignments
union all select 'attempts',count(*) from public.quiz_attempts
union all select 'answers',count(*) from public.quiz_answers
union all select 'results',count(*) from public.quiz_results;
select count(*) learner_quiz_pairs_with_historical_duplicates,coalesce(sum(attempt_count-1),0) extra_historical_attempts
from (select a.learner_id,v.quiz_id,count(*) attempt_count
  from public.quiz_attempts a join public.quiz_versions v on v.id=a.quiz_version_id
  group by a.learner_id,v.quiz_id having count(*)>1) historical;
select n.nspname schema_name,p.proname,pg_get_function_identity_arguments(p.oid) signature,
  p.prosecdef security_definer,pg_get_userbyid(p.proowner) owner,md5(pg_get_functiondef(p.oid)) definition_hash,
  has_function_privilege('anon',p.oid,'execute') anonymous_execute,
  has_function_privilege('authenticated',p.oid,'execute') authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='public' and p.proname in ('publish_quiz_version','assign_published_quiz','get_available_learner_quizzes','start_learner_quiz','save_learner_quiz_answer','submit_learner_quiz','publish_and_assign_quiz','reorder_quiz_items'))
  or (n.nspname='private' and p.proname in ('quiz_assignment_is_available','protect_quiz_item_history'))
order by n.nspname,p.proname;
select c.relname,c.relrowsecurity,c.relacl from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('quizzes','quiz_versions','quiz_items','quiz_assignments','quiz_attempts','quiz_answers','quiz_results');
select version,name from supabase_migrations.schema_migrations where version='20261112111620';
rollback;
