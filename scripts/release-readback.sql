-- Read-only read-back of the re-defense release (rollout plan step 5 on
-- hosted, and the rehearsal on the restored copy). One row, one JSON value.
-- Hosted: supabase db query --linked -f scripts/release-readback.sql
-- Compare redefense_versions with the release manifest: it must list every
-- migration version >= 20261119100000 that the manifest names, nothing else.
select jsonb_build_object(
  'redefense_versions', (select coalesce(jsonb_agg(version order by version), '[]'::jsonb)
    from supabase_migrations.schema_migrations where version >= '20261119100000'),
  'latest_version', (select max(version) from supabase_migrations.schema_migrations),
  'public_tables_without_rls', (select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity),
  'practice_contracts', (select count(*) from public.practice_mission_contracts),
  'coc1_m2_contract_version', (select version from public.practice_mission_contracts where mission_id = 'coc1_m2'),
  'curriculum_modules', (select count(*) from public.curriculum_modules),
  'performance_criteria', (select count(*) from public.learning_outcomes),
  'mission_curriculum_links', (select count(*) from public.mission_curriculum_links),
  'min_supported_app_version', (select value from public.app_release_config where key = 'min_supported_app_version'),
  'scenario_essay_enum', exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'quiz_item_type' and e.enumlabel = 'scenario_essay'),
  'published_simulation_assessments', (select count(*) from public.activity_curriculum_links l
    join public.activity_versions v on v.id = l.activity_version_id
    where l.delivery_kind = 'simulation' and v.status = 'published')
) as readback;
