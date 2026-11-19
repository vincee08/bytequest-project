-- Instructors can see every approved rubric of a published activity (needed
-- to assign centrally published simulation assessments); learners cannot see
-- rubric versions. Data-independent: the expected set is computed as the
-- table owner and compared with what each role can read. Rollback-only.
begin;
select plan(5);

create temporary table rubric_ctx as
select
  (select user_id from public.profiles where role = 'instructor' and status = 'active' order by created_at limit 1) instructor,
  (select user_id from public.profiles where role = 'learner' and status = 'active' order by created_at limit 1) learner,
  array(
    select rv.id
    from public.rubric_versions rv
    join public.activity_versions av on av.id = rv.activity_version_id
    where rv.status = 'approved' and av.status = 'published'
  ) assignable;
grant select on rubric_ctx to authenticated;

select ok(exists (select 1 from pg_policies where tablename = 'rubric_versions' and policyname = 'rubric_versions_instructor_assignable_select'),
  'instructor assignable rubric policy exists');
select ok(
  (select qual from pg_policies where tablename = 'rubric_versions' and policyname = 'rubric_versions_instructor_assignable_select')
    ~ 'approved' and
  (select qual from pg_policies where tablename = 'rubric_versions' and policyname = 'rubric_versions_instructor_assignable_select')
    ~ 'published',
  'the policy is limited to approved rubrics of published activities');

select set_config('request.jwt.claim.sub', (select instructor::text from rubric_ctx), true);
set local role authenticated;
select is(
  (select count(*)::integer from public.rubric_versions where id in (select unnest(assignable) from rubric_ctx)),
  (select cardinality(assignable) from rubric_ctx),
  'an active instructor sees every approved rubric of a published activity');
reset role;

select set_config('request.jwt.claim.sub', (select learner::text from rubric_ctx), true);
set local role authenticated;
select is((select count(*)::integer from public.rubric_versions), 0, 'learners still cannot read rubric versions');
reset role;

select ok(not has_table_privilege('authenticated', 'public.rubric_versions', 'UPDATE'), 'no write privilege was added');

select * from finish();
rollback;
