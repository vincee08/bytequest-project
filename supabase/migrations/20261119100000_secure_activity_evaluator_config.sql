-- Re-defense revision (WS0, R11.1): assessment evaluator rules must never be
-- readable by learners. 20260810111000 granted SELECT on the whole
-- activity_versions table, which re-exposed evaluator_config to every learner
-- who can see an assigned version through RLS. Restore the explicit column
-- grant pattern from 20260807102000, this time including every non-secret
-- column (RLS policies on rubric tables read created_by with the caller's
-- privileges, which is why the table-wide grant was once needed). Every
-- application query selects explicit columns that are all included below;
-- evaluator access stays inside PostgreSQL evaluation functions and
-- service-role server routes.

begin;

revoke select on table public.activity_versions from authenticated;

grant select (
  id,
  mission_id,
  module_version_id,
  version_number,
  title,
  instructions,
  delivery_mode,
  learner_payload,
  status,
  created_by,
  published_by,
  published_at,
  retired_at,
  created_at,
  updated_at
) on public.activity_versions to authenticated;

notify pgrst, 'reload schema';

commit;
