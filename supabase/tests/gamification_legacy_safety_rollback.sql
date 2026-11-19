-- Slice A6 fix round 1: the legacy user_achievements table is extended safely.
-- (a) Duplicate legacy awards never fail the migration: history is kept in
--     place, the earliest row per key is the award, and awarding stays
--     exactly once without the unique index.
-- (b) The append-only award history still allows the declared ON DELETE
--     CASCADE from auth.users during the guarded admin account removal, while
--     direct UPDATE/DELETE stays rejected. Rollback-only.
begin;
select plan(18);

create temporary table legacy_ctx (
  admin_id uuid not null default gen_random_uuid(),
  learner_l uuid not null default gen_random_uuid(),
  learner_m uuid not null default gen_random_uuid(),
  learner_n uuid not null default gen_random_uuid(),
  action_id bigint
);
insert into legacy_ctx default values;
grant select on legacy_ctx to authenticated, service_role;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@legacy-safety-rollback.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', name), now(), now()
from legacy_ctx cross join lateral (values
  (admin_id, 'Legacy Safety Admin'), (learner_l, 'Lara Legacy'), (learner_m, 'Mia Removed'), (learner_n, 'Noel Points')) t(id, name);
update public.profiles set role = 'admin' where user_id = (select admin_id from legacy_ctx);

with inserted as (
  insert into public.practice_mission_actions (learner_id, client_action_id, mission_id, phase_id, action_type, target, value, client_occurred_at)
  select learner_l, 'legacy-safety-rollback', 'coc1_m2', 'inspect', 'object_inspected', 'case', '{}'::jsonb, now() from legacy_ctx
  returning id)
update legacy_ctx set action_id = (select id from inserted);

-- ---------------------------------------------------------------------------
-- (a) Duplicate-safe uniqueness
-- ---------------------------------------------------------------------------
select is(private.gamification_ensure_award_index(), 'exists', 'the unique award index is present on a clean database');
drop index public.user_achievements_user_achievement_key;
select is(private.gamification_ensure_award_index(), 'created', 'the index is created when no duplicate awards exist');
select ok(to_regclass('public.user_achievements_user_achievement_key') is not null, 'the created index is in place');

-- Simulate a legacy database that already holds a duplicated award.
drop index public.user_achievements_user_achievement_key;
-- A production-shaped copy also enforces uniqueness with its own pre-existing
-- constraint; drop it inside this rolled-back transaction so the legacy
-- duplicate scenario can be simulated on any copy (local or restored).
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.user_achievements'::regclass and contype = 'u'
             and conkey @> array[(select attnum from pg_attribute where attrelid = 'public.user_achievements'::regclass and attname = 'user_id'),
                                 (select attnum from pg_attribute where attrelid = 'public.user_achievements'::regclass and attname = 'achievement_id')]::int2[]
  loop
    execute format('alter table public.user_achievements drop constraint %I', c.conname);
  end loop;
end
$$;
insert into public.user_achievements (user_id, achievement_id, earned_at)
select c.learner_l, a.id, v.earned_at
from legacy_ctx c, public.achievements a,
  (values ('2025-01-01 08:00:00+00'::timestamptz), ('2025-02-01 08:00:00+00'::timestamptz)) v(earned_at)
where a.achievement_code = 'first_mission';
select is(private.gamification_ensure_award_index(), 'skipped_duplicates',
  'duplicate legacy awards skip the index instead of failing the migration');
select ok(to_regclass('public.user_achievements_user_achievement_key') is null, 'no index is forced onto duplicate history');
select is((select count(*)::integer from public.user_achievements where user_id = (select learner_l from legacy_ctx)), 2,
  'duplicate award history is kept in place');
select is((select format('%s|%s', count(*), min(earned_at)) from public.learner_achievements
  where learner_id = (select learner_l from legacy_ctx) and code = 'first_mission'),
  format('1|%s', '2025-01-01 08:00:00+00'::timestamptz), 'readers treat the earliest row per key as the award');

-- Awarding stays exactly once without the index.
set local role service_role;
insert into public.practice_mission_completions (learner_id, mission_id, contract_version, evidence_through_id, verified_at)
select learner_l, mission, 'legacy-safety', action_id, now() from legacy_ctx cross join (values ('coc1_m2'), ('coc1_m3')) m(mission);
reset role;
select is((select string_agg(format('%s:%s', a.achievement_code, s.n), ',' order by a.achievement_code)
  from (select achievement_id, count(*) n from public.user_achievements where user_id = (select learner_l from legacy_ctx)
        group by achievement_id) s
  join public.achievements a on a.id = s.achievement_id),
  'assembly_ready:1,first_mission:2', 'each achievement is awarded once and legacy duplicates are not multiplied');
select set_config('request.jwt.claim.sub', (select learner_l::text from legacy_ctx), true);
set local role authenticated;
select is(jsonb_array_length(public.get_learner_rewards()->'achievements'), 12,
  'the rewards projection lists each achievement once');
select is((select (a->>'earned_at')::timestamptz from jsonb_array_elements(public.get_learner_rewards()->'achievements') a
  where a->>'code' = 'first_mission'), '2025-01-01 08:00:00+00'::timestamptz, 'with the earliest earned time');
reset role;

-- ---------------------------------------------------------------------------
-- (b) Append-only history and the guarded account removal
-- ---------------------------------------------------------------------------
insert into public.user_achievements (user_id, achievement_id)
select c.learner_m, a.id from legacy_ctx c, public.achievements a where a.achievement_code = 'on_time';
set local role service_role;
select throws_ok(format('delete from public.user_achievements where user_id = %L', (select learner_m from legacy_ctx)),
  '55000', 'user_achievements is append-only', 'a direct delete of award history is rejected');
select throws_ok(format('update public.user_achievements set earned_at = now() where user_id = %L', (select learner_m from legacy_ctx)),
  '55000', 'user_achievements is append-only', 'award history cannot be rewritten');
reset role;

select set_config('request.jwt.claim.sub', (select admin_id::text from legacy_ctx), true);
set local role authenticated;
select public.admin_set_account_status(learner_m, 'deactivated'::public.account_status, 'Rollback removal readiness check')
from legacy_ctx;
select is((public.admin_account_removal_readiness((select learner_m from legacy_ctx))->>'safe_to_remove')::boolean, true,
  'a learner with only legacy awards passes the removal readiness gate');
reset role;
-- The trusted removal route then deletes the Auth identity.
delete from auth.users where id = (select learner_m from legacy_ctx);
select is((select count(*)::integer from public.user_achievements where user_id = (select learner_m from legacy_ctx)), 0,
  'the guarded account removal cascades through award history');
select ok(not exists (select 1 from public.profiles where user_id = (select learner_m from legacy_ctx))
  and not exists (select 1 from public.gamification_leaderboard_entries where learner_id = (select learner_m from legacy_ctx)),
  'the profile and its leaderboard entry go with the identity');

-- Point history still blocks removal: the gate reports it and the FK refuses.
set local role service_role;
select private.gamification_award(learner_n, 'practice_mission_verified', 'coc1_m1', now()) from legacy_ctx;
reset role;
select set_config('request.jwt.claim.sub', (select admin_id::text from legacy_ctx), true);
set local role authenticated;
select public.admin_set_account_status(learner_n, 'deactivated'::public.account_status, 'Rollback removal readiness check')
from legacy_ctx;
select ok(public.admin_account_removal_readiness((select learner_n from legacy_ctx))->'blockers' @> '[{"table":"learner_point_events"}]'::jsonb,
  'point history is reported as a removal blocker');
reset role;
select throws_ok(format('delete from auth.users where id = %L', (select learner_n from legacy_ctx)),
  '23503', null, 'point history cannot be cascaded away');
select is((select count(*)::integer from public.learner_achievements where learner_id = (select learner_n from legacy_ctx)), 1,
  'the blocked removal keeps the learner''s award history');

select * from finish();
rollback;
