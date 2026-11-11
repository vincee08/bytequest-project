-- Owner evidence collection for the hosted mobile testing gate.
-- Select the authorized ByteQuest production project in Supabase first.
-- This file reads catalogs and aggregate counts; it does not run evaluators,
-- access tokens/passwords, copy learner rows, or change migration history.
-- Keep the exported result in private evidence storage, outside Git.
begin isolation level repeatable read read only;

with relations as (
  select c.*, n.nspname
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'storage')
    and c.relkind in ('r', 'p', 'v', 'm', 'S')
), functions as (
  select p.*, n.nspname
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
)
select jsonb_build_object(
  'captured_at', current_timestamp,
  'transaction_read_only', current_setting('transaction_read_only'),
  'server_version', current_setting('server_version'),
  'schemas', (
    select jsonb_agg(jsonb_build_object('name', n.nspname,
      'owner', pg_catalog.pg_get_userbyid(n.nspowner), 'acl', n.nspacl::text)
      order by n.nspname)
    from pg_catalog.pg_namespace n where n.nspname in ('public', 'storage')
  ),
  'realtime_publication', (
    select coalesce(jsonb_agg(to_jsonb(p) order by p.schemaname, p.tablename),
      '[]'::jsonb) from pg_catalog.pg_publication_tables p
    where p.pubname = 'supabase_realtime'
  ),
  'migration_history', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'version', to_jsonb(m)->>'version',
      'name', to_jsonb(m)->>'name',
      'recorded_statements_md5', md5((to_jsonb(m)->'statements')::text)
    ) order by to_jsonb(m)->>'version'), '[]'::jsonb)
    from supabase_migrations.schema_migrations m
  ),
  'relations', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'schema', c.nspname, 'name', c.relname, 'kind', c.relkind,
      'owner', pg_catalog.pg_get_userbyid(c.relowner),
      'rls_enabled', c.relrowsecurity, 'rls_forced', c.relforcerowsecurity,
      'acl', c.relacl::text,
      'effective_acl', coalesce(c.relacl, pg_catalog.acldefault(
        case when c.relkind = 'S' then 'S'::"char" else 'r'::"char" end,
        c.relowner))::text,
      'view_definition', case when c.relkind in ('v', 'm')
        then pg_catalog.pg_get_viewdef(c.oid, true) else null end
    ) order by c.nspname, c.relname), '[]'::jsonb) from relations c
  ),
  'columns', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'schema', c.nspname, 'relation', c.relname, 'position', a.attnum,
      'name', a.attname, 'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
      'not_null', a.attnotnull, 'identity', a.attidentity,
      'generated', a.attgenerated, 'acl', a.attacl::text,
      'default', pg_catalog.pg_get_expr(d.adbin, d.adrelid)
    ) order by c.nspname, c.relname, a.attnum), '[]'::jsonb)
    from relations c join pg_catalog.pg_attribute a on a.attrelid = c.oid
    left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attnum > 0 and not a.attisdropped
  ),
  'constraints', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'schema', c.nspname, 'relation', c.relname, 'name', k.conname,
      'validated', k.convalidated,
      'definition', pg_catalog.pg_get_constraintdef(k.oid, true)
    ) order by c.nspname, c.relname, k.conname), '[]'::jsonb)
    from relations c join pg_catalog.pg_constraint k on k.conrelid = c.oid
  ),
  'indexes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'schema', c.nspname, 'relation', c.relname,
      'valid', i.indisvalid, 'ready', i.indisready,
      'definition', pg_catalog.pg_get_indexdef(i.indexrelid)
    ) order by c.nspname, c.relname, i.indexrelid), '[]'::jsonb)
    from relations c join pg_catalog.pg_index i on i.indrelid = c.oid
  ),
  'triggers', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'schema', c.nspname, 'relation', c.relname, 'name', t.tgname,
      'enabled', t.tgenabled,
      'definition', pg_catalog.pg_get_triggerdef(t.oid, true)
    ) order by c.nspname, c.relname, t.tgname), '[]'::jsonb)
    from relations c join pg_catalog.pg_trigger t on t.tgrelid = c.oid
    where not t.tgisinternal
  ),
  'policies', (
    select coalesce(jsonb_agg(to_jsonb(p) order by p.schemaname, p.tablename,
      p.policyname), '[]'::jsonb)
    from pg_catalog.pg_policies p where p.schemaname in ('public', 'storage')
  ),
  'functions', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'signature', p.oid::regprocedure::text,
      'result', pg_catalog.pg_get_function_result(p.oid),
      'owner', pg_catalog.pg_get_userbyid(p.proowner),
      'security_definer', p.prosecdef, 'volatility', p.provolatile,
      'config', p.proconfig, 'acl', p.proacl::text,
      'effective_acl', coalesce(p.proacl,
        pg_catalog.acldefault('f'::"char", p.proowner))::text,
      'definition_md5', md5(pg_catalog.pg_get_functiondef(p.oid)),
      'definition', case when p.proname like 'practice\_%' escape '\'
        or p.proname in ('get_practice_learning_path', 'is_learner')
        then pg_catalog.pg_get_functiondef(p.oid) else null end
    ) order by p.oid::regprocedure::text), '[]'::jsonb) from functions p
  ),
  'practice_contracts', (
    select jsonb_agg(jsonb_build_object(
      'mission_id', mission_id, 'version', version,
      'definition_md5', md5(definition::text),
      'phase_count', jsonb_array_length(definition->'phases'),
      'first_phase_id', definition#>>'{phases,0,id}',
      'second_phase_id', definition#>>'{phases,1,id}',
      'first_phase_placement_items', coalesce(jsonb_array_length(
        definition#>'{phases,0,presentation,equipment,placement,items}'), 0)
    ) order by mission_id) from public.practice_mission_contracts
  ),
  'preservation_counts', jsonb_build_object(
    'profiles', (select count(*) from public.profiles),
    'practice_actions', (select count(*) from public.practice_mission_actions),
    'coc1_m1_actions', (select count(*) from public.practice_mission_actions
      where mission_id = 'coc1_m1'),
    'coc1_m1_learners_with_actions', (select count(distinct learner_id)
      from public.practice_mission_actions where mission_id = 'coc1_m1'),
    'practice_completions', (select count(*) from public.practice_mission_completions),
    'practice_coc_progress', (select count(*) from public.practice_coc_progress),
    'practice_quiz_attempts', (select count(*) from public.practice_quiz_attempts),
    'assessment_attempts', (select count(*) from public.attempts),
    'score_revisions', (select count(*) from public.score_revisions),
    'result_releases', (select count(*) from public.result_releases)
  ),
  'coc1_m1_completion_versions', (
    select coalesce(jsonb_agg(to_jsonb(v) order by v.contract_version), '[]'::jsonb)
    from (select contract_version, count(*) as completions
      from public.practice_mission_completions where mission_id = 'coc1_m1'
      group by contract_version) v
  )
) as hosted_mobile_evidence;

rollback;
