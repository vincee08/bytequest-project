begin;

select plan(4);

select is(
  (
    select count(*)::integer
    from public.missions
    where mission_code ~ '^coc[1-4]_m[1-5]$'
  ),
  20,
  'the canonical ByteQuest catalog contains all 20 missions'
);

select is(
  (
    select count(*)::integer
    from public.missions
    where mission_code ~ '^coc[1-4]_m[1-5]$'
      and nullif(btrim(scenario), '') is null
  ),
  0,
  'every canonical mission has a scenario for grounded activity authoring'
);

select is(
  (
    select count(*)::integer
    from public.missions
    where mission_code ~ '^coc[1-4]_m[1-5]$'
      and nullif(btrim(objective), '') is null
  ),
  0,
  'every canonical mission has a learning objective'
);

select is(
  (
    select count(*)::integer
    from public.missions
    where mission_code ~ '^coc[1-4]_m[1-5]$'
      and cardinality(skills_assessed) = 0
  ),
  0,
  'every canonical mission identifies assessed skills'
);

select * from finish();

rollback;
