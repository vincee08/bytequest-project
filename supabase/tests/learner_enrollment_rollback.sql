-- Target only isolated QA. Existing lifecycle contracts, no schema changes.
begin;
create temporary table enrollment_test_context as
select
  (select user_id from public.profiles where role='instructor' and status='active' order by user_id limit 1) instructor,
  (select user_id from public.profiles where role='instructor' and status='active' order by user_id offset 1 limit 1) other_instructor,
  -- A learner with no active class: a learner belongs to one active class at a time.
  (select p.user_id from public.profiles p where p.role='learner' and p.status='active'
     and not exists(select 1 from public.class_memberships cm where cm.learner_id=p.user_id and cm.status='active')
   order by p.user_id limit 1) learner,
  null::uuid renewed_membership;
grant select, update on enrollment_test_context to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',instructor,'role','authenticated')::text, true) is not null as claims_set from enrollment_test_context;
do $$
declare
  ctx record;
  first_class public.classes;
  other_class public.classes;
  original public.class_memberships;
  retained public.class_memberships;
  renewed public.class_memberships;
  denied boolean := false;
begin
  select * into ctx from enrollment_test_context;
  if ctx.instructor is null or ctx.other_instructor is null or ctx.learner is null then raise exception 'QA_FIXTURES_REQUIRED'; end if;
  first_class := public.create_class('Rollback enrollment QA');
  other_class := public.create_class('Rollback multi-class QA');
  original := public.enroll_learner(first_class.id,ctx.learner);
  -- One active class per learner (20261123090000): a second class is refused
  -- with a stable code that does not name the first class.
  begin perform public.enroll_learner(other_class.id,ctx.learner);
  exception when unique_violation then denied:=(sqlerrm='LEARNER_ALREADY_IN_ANOTHER_CLASS'); end;
  if not denied then raise exception 'SECOND_ACTIVE_CLASS_ALLOWED'; end if;
  if exists(select 1 from public.class_memberships where class_id=other_class.id and learner_id=ctx.learner) then raise exception 'REFUSED_MEMBERSHIP_WRITTEN'; end if;
  denied:=false;
  begin perform public.enroll_learner(first_class.id,ctx.learner);
  exception when unique_violation then denied:=true; end;
  if not denied then raise exception 'DUPLICATE_ACTIVE_MEMBERSHIP_ALLOWED'; end if;
  retained := public.deactivate_class_membership(original.id,'Rollback history preservation regression');
  renewed := public.enroll_learner(first_class.id,ctx.learner);
  if renewed.id=original.id then raise exception 'HISTORICAL_ROW_OVERWRITTEN'; end if;
  if (select to_jsonb(cm) from public.class_memberships cm where id=retained.id)<>to_jsonb(retained) then raise exception 'HISTORICAL_ROW_CHANGED'; end if;
  if (select count(*) from public.class_memberships where class_id=first_class.id and learner_id=ctx.learner and status='active')<>1 then raise exception 'ACTIVE_MEMBER_COUNT_INCORRECT'; end if;
  update enrollment_test_context set renewed_membership=renewed.id;
  denied:=false;
  begin perform public.enroll_learner(first_class.id,ctx.instructor);
  exception when invalid_parameter_value then denied:=true; end;
  if not denied then raise exception 'NON_LEARNER_ENROLLED'; end if;
  perform public.archive_class(other_class.id,'Rollback archived-class access regression');
  denied:=false;
  begin perform public.enroll_learner(other_class.id,ctx.learner);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'ARCHIVED_CLASS_ENROLLMENT_ALLOWED'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ctx.other_instructor,'role','authenticated')::text,true);
  denied:=false;
  begin perform public.enroll_learner(first_class.id,ctx.learner);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'CROSS_INSTRUCTOR_ENROLLMENT_ALLOWED'; end if;
  if exists(select 1 from public.class_memberships where class_id=first_class.id) then raise exception 'CROSS_CLASS_RLS_LEAK'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ctx.learner,'role','authenticated')::text,true);
  denied:=false;
  begin perform public.enroll_learner(first_class.id,ctx.learner);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'LEARNER_SELF_ENROLLMENT_ALLOWED'; end if;
  if not (select relrowsecurity from pg_class where oid='public.profiles'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.class_memberships'::regclass) then raise exception 'RLS_NOT_ENABLED'; end if;
end $$;
reset role;
-- Audit reads intentionally remain admin-only; inspect this assertion only
-- after leaving the authenticated instructor/learner RLS checks above.
do $$ begin
  if not exists(select 1 from public.audit_events where target_id=(select renewed_membership from enrollment_test_context) and action='class_membership.enrolled') then raise exception 'ENROLLMENT_AUDIT_MISSING'; end if;
end $$;
rollback;
\echo PASS isolated authenticated enrollment lifecycle, RLS, audit and retained history; rolled back
