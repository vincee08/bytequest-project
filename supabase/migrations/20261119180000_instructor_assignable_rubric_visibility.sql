-- Re-defense integration fix: instructors must be able to assign the
-- published simulation assessments. The original rubric_versions_staff_select
-- policy (20260807102000) only shows an instructor rubrics already used in
-- their own classes or rubrics of activities they created, but the simulation
-- assessment packages are published centrally (scripts/publish-simulation-
-- assessments.mjs). Instructors therefore saw every published activity but no
-- approved rubric, and the dashboard reported "no approved matching rubric".
--
-- This additive policy lets an active instructor read APPROVED rubric versions
-- whose activity version is PUBLISHED, which is the metadata the assignment
-- form needs. Rubric criteria keep their existing staff-only policy, learners
-- gain nothing, and no write privilege changes.

begin;

create policy rubric_versions_instructor_assignable_select
on public.rubric_versions for select to authenticated
using (
  public.is_instructor()
  and public.is_active_user()
  and status = 'approved'
  and exists (
    select 1
    from public.activity_versions av
    where av.id = rubric_versions.activity_version_id
      and av.status = 'published'
  )
);

comment on policy rubric_versions_instructor_assignable_select on public.rubric_versions is
  'Active instructors can read approved rubric versions of published activities so they can assign centrally published assessments.';

notify pgrst, 'reload schema';

commit;
