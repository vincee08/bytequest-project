-- Slice A6 (Objective 2): learner rewards projection and opt-in class
-- leaderboard. The leaderboard shows only learners who share an active class
-- with the caller and opted in; the caller is always included. Rollback-only.
begin;
select plan(48);

create temporary table rw_people (
  key text primary key,
  id uuid not null default gen_random_uuid(),
  full_name text not null
);
insert into rw_people (key, full_name) values
  ('teacher', 'Rewards Teacher'), ('teacher_b', 'Other Teacher'),
  ('me', 'Ana Reyes'), ('ben', 'Ben Santos'), ('carla', 'Carla Mendoza'), ('dina', 'Dina Cruz'),
  ('eli', 'Eli Ramos'), ('fe', 'Fe Lim'), ('gio', 'Gio Tan'), ('hana', 'Hana Uy'), ('newbie', 'Ivy');
insert into rw_people (key, full_name)
select 'extra' || lpad(n::text, 2, '0'), 'Extra' || lpad(n::text, 2, '0') || ' Learner' from generate_series(1, 10) n;
create temporary table rw_classes (key text primary key, id uuid not null default gen_random_uuid());
insert into rw_classes (key) values ('a'), ('b'), ('z');
grant select on rw_people, rw_classes to authenticated, service_role;
create function pg_temp.rw(p_key text) returns uuid language sql stable as $$ select id from rw_people where key = p_key $$;
create function pg_temp.cls(p_key text) returns uuid language sql stable as $$ select id from rw_classes where key = p_key $$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@rewards-rollback.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', full_name), now(), now()
from rw_people;
update public.profiles set role = 'instructor' where user_id in (pg_temp.rw('teacher'), pg_temp.rw('teacher_b'));

insert into public.classes (id, title, class_code, instructor_id, created_by)
select id, 'Rewards rollback class ' || key, left(id::text, 12),
  pg_temp.rw(case when key = 'b' then 'teacher_b' else 'teacher' end),
  pg_temp.rw(case when key = 'b' then 'teacher_b' else 'teacher' end)
from rw_classes;
update public.classes set status = 'archived', archived_at = now(), archived_by = pg_temp.rw('teacher'),
  archive_reason = 'Rollback archived class'
where id = pg_temp.cls('z');
insert into public.class_memberships (class_id, learner_id, enrolled_by)
select pg_temp.cls(v.class_key), pg_temp.rw(v.person), pg_temp.rw(case when v.class_key = 'b' then 'teacher_b' else 'teacher' end)
from (values ('a', 'me'), ('a', 'ben'), ('a', 'carla'), ('a', 'gio'), ('a', 'hana'), ('a', 'newbie'),
             ('b', 'dina'), ('z', 'me'), ('z', 'fe')) v(class_key, person);
insert into public.class_memberships (class_id, learner_id, enrolled_by, status, deactivated_by, deactivated_at, deactivation_reason)
select pg_temp.cls('a'), pg_temp.rw('eli'), pg_temp.rw('teacher'), 'deactivated', pg_temp.rw('teacher'), now(),
  'Rollback deactivated membership';

-- Real awards through the trusted award path (gio is awarded before ben so the
-- tie order below cannot come from insertion order).
set local role service_role;
select private.gamification_award(pg_temp.rw('me'), 'practice_mission_verified', 'coc1_m' || n,
  '2026-04-01 08:00:00+00'::timestamptz + make_interval(hours => n))
from generate_series(1, 3) n;
select private.gamification_award(pg_temp.rw(v.person), 'coc_completed', v.coc, now())
from (values ('gio', 'coc1'), ('ben', 'coc1'), ('carla', 'coc1'), ('dina', 'coc1'), ('dina', 'coc2'), ('dina', 'coc3'),
             ('eli', 'coc1'), ('eli', 'coc2'), ('fe', 'coc1'), ('fe', 'coc2'),
             ('hana', 'coc1'), ('hana', 'coc2'), ('hana', 'coc3')) v(person, coc);
select private.gamification_award(pg_temp.rw(v.person), 'module_completed', gen_random_uuid()::text, now())
from (values ('carla'), ('carla'), ('eli'), ('eli'), ('fe'), ('hana')) v(person);
reset role;

update public.profiles set show_on_leaderboard = true
where user_id in (pg_temp.rw('gio'), pg_temp.rw('dina'), pg_temp.rw('eli'), pg_temp.rw('fe'), pg_temp.rw('hana'));
update public.profiles set status = 'deactivated', deactivated_at = now(), deactivation_reason = 'Rollback deactivated account'
where user_id = pg_temp.rw('hana');

-- ---------------------------------------------------------------------------
-- Schema, privileges and definer surface
-- ---------------------------------------------------------------------------
select is((select format('%s|%s', column_default, is_nullable) from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles' and column_name = 'show_on_leaderboard'), 'false|NO',
  'profiles.show_on_leaderboard defaults to false and is required');
select ok(has_column_privilege('authenticated', 'public.profiles', 'show_on_leaderboard', 'UPDATE'),
  'learners may update their own leaderboard preference');
select ok(not (select prosecdef from pg_proc where oid = 'public.get_learner_rewards()'::regprocedure),
  'get_learner_rewards is SECURITY INVOKER');
select ok(has_function_privilege('authenticated', 'public.get_learner_rewards()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_learner_rewards()', 'EXECUTE'),
  'only signed-in users can call get_learner_rewards');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosecdef
    and (p.proname like 'gamification%' or p.proname = 'get_learner_rewards')), 0,
  'the rewards projection adds no SECURITY DEFINER function');
select ok((select relrowsecurity from pg_class where oid = 'public.gamification_leaderboard_entries'::regclass),
  'RLS is enabled on the leaderboard entries');
select ok(not has_table_privilege('authenticated', 'public.gamification_leaderboard_entries', 'INSERT, DELETE, TRUNCATE')
  and not has_column_privilege('authenticated', 'public.gamification_leaderboard_entries', 'points', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.gamification_leaderboard_entries', 'display_name', 'UPDATE')
  and not has_table_privilege('anon', 'public.gamification_leaderboard_entries', 'SELECT'),
  'clients cannot create, delete or change points or names on leaderboard entries');
select is(array[
    private.gamification_display_name('Ana Reyes'), private.gamification_display_name('  Mike   Angelo  Casono '),
    private.gamification_display_name('Madonna'), private.gamification_display_name(''),
    private.gamification_display_name(null), private.gamification_display_name('qa.learner1@bytequest.local')],
  array['Ana R.', 'Mike C.', 'Madonna', 'Learner', 'Learner', 'qa.learner1'],
  'display names show the first name and last initial only, never an email address');

-- ---------------------------------------------------------------------------
-- Projection rows follow profiles and awards
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('newbie')),
  'every new profile receives a leaderboard entry');
select is((select format('%s|%s|%s|%s', display_name, points, show_on_leaderboard::text, is_active_learner::text)
  from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('carla')), 'Carla M.|500|false|true',
  'entry points equal the sum of awarded events and opt-in defaults to off');
select is((select format('%s|%s', show_on_leaderboard::text, is_active_learner::text)
  from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('hana')), 'true|false',
  'a deactivated account is never an active leaderboard learner');

-- A learner toggles their own preference through the profile column grant.
select set_config('request.jwt.claim.sub', pg_temp.rw('ben')::text, true);
set local role authenticated;
update public.profiles set show_on_leaderboard = true where user_id = auth.uid();
reset role;
select ok((select show_on_leaderboard from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('ben')),
  'opting in through the profile updates the leaderboard entry');

-- ---------------------------------------------------------------------------
-- The caller's rewards
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', pg_temp.rw('me')::text, true);
set local role authenticated;
select is(public.get_learner_rewards()->'points', '150'::jsonb, 'points are the sum of the caller''s events');
select is(public.get_learner_rewards()->'level',
  '{"level":2,"title":"Apprentice","min_points":100,"next_level":3,"next_min_points":300,"progress_percent":25}'::jsonb,
  'the level and progress come from the thresholds');
select is(public.get_learner_rewards()->'show_on_leaderboard', 'false'::jsonb, 'the caller''s opt-in preference is returned');
select is(jsonb_array_length(public.get_learner_rewards()->'achievements'), 12, 'all configured achievements are listed');
select is((select string_agg(a->>'code', ',' order by ord) from jsonb_array_elements(public.get_learner_rewards()->'achievements')
  with ordinality t(a, ord) where a->>'earned_at' is not null), 'first_mission,assembly_ready',
  'earned achievements carry their earned time');
select is((select format('%s|%s/%s|%s', a->'earned_at', a->>'progress_current', a->>'progress_target', a->>'icon')
  from jsonb_array_elements(public.get_learner_rewards()->'achievements') a where a->>'code' = 'five_missions'),
  'null|3/5|military_tech', 'locked achievements show progress toward their rule');
select is((select string_agg(e->>'source_id', ',' order by ord) from jsonb_array_elements(public.get_learner_rewards()->'recent')
  with ordinality t(e, ord)), 'coc1_m3,coc1_m2,coc1_m1', 'recent points are newest first');
select is((select format('%s|%s|%s', e->>'label', e->>'points', e->>'detail')
  from jsonb_array_elements(public.get_learner_rewards()->'recent') with ordinality t(e, ord) where ord = 1),
  format('Practice mission verified|50|%s', (select title from public.missions where mission_code = 'coc1_m3')),
  'recent points carry the rule label and the source title');
select is((select string_agg(format('%s:%s:%s:%s', c->>'event_type', c->>'points', c->>'count', c->>'points_each'), ',' order by ord)
  from jsonb_array_elements(public.get_learner_rewards()->'points_by_category') with ordinality t(c, ord)),
  'practice_mission_verified:150:3:50,topic_completed:0:0:10,module_completed:0:0:100,coc_completed:0:0:300,'
  || 'quiz_submitted:0:0:20,homework_submitted_on_time:0:0:15,assessment_released:0:0:40',
  'points by category list every active rule in a stable order');

-- ---------------------------------------------------------------------------
-- Leaderboard scope
-- ---------------------------------------------------------------------------
select is(public.get_learner_rewards()->'leaderboard',
  '[{"rank":1,"display_name":"Ben S.","points":300,"is_me":false},'
  '{"rank":1,"display_name":"Gio T.","points":300,"is_me":false},'
  '{"rank":3,"display_name":"Ana R.","points":150,"is_me":true}]'::jsonb,
  'only opted-in classmates in an active class appear, ties share a rank and the caller is always included');
select is((select string_agg(display_name, ',' order by display_name) from public.gamification_leaderboard_entries),
  'Ana R.,Ben S.,Gio T.', 'a learner can read only their own entry and opted-in classmates');
select throws_ok($$update public.gamification_leaderboard_entries set points = 99999 where learner_id = auth.uid()$$,
  '42501', null, 'a learner cannot change leaderboard points');
select throws_ok($$insert into public.gamification_leaderboard_entries (learner_id) values (auth.uid())$$,
  '42501', null, 'a learner cannot insert leaderboard entries');
select throws_ok($$delete from public.gamification_leaderboard_entries$$, '42501', null, 'a learner cannot delete leaderboard entries');
with changed as (
  update public.gamification_leaderboard_entries set show_on_leaderboard = true where learner_id = auth.uid() returning 1)
select is((select count(*)::integer from changed), 0,
  'a direct client update changes no leaderboard entry; only the profile trigger refreshes it');
update public.gamification_leaderboard_entries set show_on_leaderboard = false where learner_id = pg_temp.rw('ben');
update public.profiles set show_on_leaderboard = true where user_id = pg_temp.rw('carla');
select is((select show_on_leaderboard from public.gamification_leaderboard_entries where learner_id = auth.uid()), false,
  'a direct entry update cannot diverge from the profile preference');
reset role;
select is(format('%s|%s',
    (select show_on_leaderboard::text from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('ben')),
    (select show_on_leaderboard::text from public.profiles where user_id = pg_temp.rw('carla'))),
  'true|false', 'a learner cannot change another learner''s preference or entry');

-- Cross-class and archived-class isolation.
select set_config('request.jwt.claim.sub', pg_temp.rw('dina')::text, true);
set local role authenticated;
select is(public.get_learner_rewards()->'leaderboard', '[{"rank":1,"display_name":"Dina C.","points":900,"is_me":true}]'::jsonb,
  'learners in another class never appear');
select set_config('request.jwt.claim.sub', pg_temp.rw('fe')::text, true);
select is(public.get_learner_rewards()->'leaderboard', '[{"rank":1,"display_name":"Fe L.","points":700,"is_me":true}]'::jsonb,
  'an archived class does not form a leaderboard');
select set_config('request.jwt.claim.sub', pg_temp.rw('carla')::text, true);
select is(public.get_learner_rewards()->'leaderboard',
  '[{"rank":1,"display_name":"Carla M.","points":500,"is_me":true},'
  '{"rank":2,"display_name":"Ben S.","points":300,"is_me":false},'
  '{"rank":2,"display_name":"Gio T.","points":300,"is_me":false}]'::jsonb,
  'an opted-out learner still sees themselves and opted-in classmates');

-- Opting in and out takes effect immediately for classmates.
update public.profiles set show_on_leaderboard = true where user_id = auth.uid();
select set_config('request.jwt.claim.sub', pg_temp.rw('me')::text, true);
select is(public.get_learner_rewards()->'leaderboard'->0, '{"rank":1,"display_name":"Carla M.","points":500,"is_me":false}'::jsonb,
  'an opted-in classmate appears for others');
select set_config('request.jwt.claim.sub', pg_temp.rw('carla')::text, true);
update public.profiles set show_on_leaderboard = false where user_id = auth.uid();
select set_config('request.jwt.claim.sub', pg_temp.rw('me')::text, true);
select ok(not exists (select 1 from jsonb_array_elements(public.get_learner_rewards()->'leaderboard') e
  where e->>'display_name' = 'Carla M.'), 'opting out removes the learner from classmates'' leaderboards');

-- Name changes follow the profile.
select set_config('request.jwt.claim.sub', pg_temp.rw('ben')::text, true);
update public.profiles set full_name = 'Benjamin Santos' where user_id = auth.uid();
select set_config('request.jwt.claim.sub', pg_temp.rw('me')::text, true);
select is(public.get_learner_rewards()->'leaderboard'->0->>'display_name', 'Benjamin S.',
  'display names follow profile name changes');
reset role;

-- Top ten plus the caller.
insert into public.class_memberships (class_id, learner_id, enrolled_by)
select pg_temp.cls('a'), id, pg_temp.rw('teacher') from rw_people where key like 'extra%';
set local role service_role;
select private.gamification_award(id, 'coc_completed', 'coc1', now()) from rw_people where key like 'extra%';
reset role;
update public.profiles set show_on_leaderboard = true where user_id in (select id from rw_people where key like 'extra%');
select set_config('request.jwt.claim.sub', pg_temp.rw('me')::text, true);
set local role authenticated;
select is(jsonb_array_length(public.get_learner_rewards()->'leaderboard'), 11, 'the leaderboard shows the top ten plus the caller');
select is(public.get_learner_rewards()->'leaderboard'->10, '{"rank":13,"display_name":"Ana R.","points":150,"is_me":true}'::jsonb,
  'a caller outside the top ten is appended with their true rank');
select is((select count(*)::integer from jsonb_array_elements(public.get_learner_rewards()->'leaderboard') e
  where (e->>'is_me')::boolean), 1, 'the caller appears exactly once');
select ok((select bool_and((e->>'rank')::integer = 1) from jsonb_array_elements(public.get_learner_rewards()->'leaderboard') e
  where not (e->>'is_me')::boolean), 'tied classmates share the same rank');
select is(public.get_learner_rewards()->'leaderboard', public.get_learner_rewards()->'leaderboard',
  'the leaderboard order is deterministic');
select ok((select bool_and(e ? 'rank' and e ? 'display_name' and e ? 'points' and e ? 'is_me' and not e ? 'learner_id')
  from jsonb_array_elements(public.get_learner_rewards()->'leaderboard') e), 'leaderboard rows expose no account identifiers');

-- A new learner sees a truthful empty state.
select set_config('request.jwt.claim.sub', pg_temp.rw('newbie')::text, true);
select is(format('%s|%s|%s|%s', public.get_learner_rewards()->'points', public.get_learner_rewards()->'level'->>'title',
    public.get_learner_rewards()->'recent', (select count(*) from jsonb_array_elements(public.get_learner_rewards()->'achievements') a
      where a->>'earned_at' is not null)),
  '0|Trainee|[]|0', 'a new learner has zero points, Trainee level, no recent points and no earned achievements');
select is((select sum((c->>'points')::integer) from jsonb_array_elements(public.get_learner_rewards()->'points_by_category') c), 0::bigint,
  'a new learner has no points in any category');
select is((public.get_learner_rewards()->'leaderboard'->-1)->>'is_me', 'true', 'a new learner is still included in their leaderboard');

-- Only active learners can call the projection.
select set_config('request.jwt.claim.sub', pg_temp.rw('teacher')::text, true);
select throws_ok($$select public.get_learner_rewards()$$, '42501', 'LEARNER_REQUIRED', 'instructors cannot call the learner projection');
select set_config('request.jwt.claim.sub', pg_temp.rw('hana')::text, true);
select throws_ok($$select public.get_learner_rewards()$$, '42501', 'LEARNER_REQUIRED', 'deactivated learners cannot call the projection');

-- Owning instructors read entries for analytics; other instructors do not.
select set_config('request.jwt.claim.sub', pg_temp.rw('teacher')::text, true);
select ok(exists (select 1 from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('carla')),
  'the class instructor reads entries of learners who did not opt in');
select set_config('request.jwt.claim.sub', pg_temp.rw('teacher_b')::text, true);
select is((select count(*)::integer from public.gamification_leaderboard_entries where learner_id = pg_temp.rw('me')), 0,
  'another instructor cannot read entries outside their classes');
reset role;

select * from finish();
rollback;
