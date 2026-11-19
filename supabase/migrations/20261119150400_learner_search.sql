-- Slice A5 / WS8: server-side learner search for /learners (admin), /users
-- and the instructor learner list. SECURITY INVOKER: existing RLS decides the
-- scope (admins see every learner; instructors see learners enrolled in their
-- own active classes, and only those classes). Every whitespace/comma-separated
-- word must appear (case-insensitive, literal) in the learner's name, email,
-- student ID or one of their visible class titles. Additive; read-only.
begin;
set local lock_timeout = '5s';

create or replace function public.search_learners(
  p_query text default null,
  p_class_id uuid default null,
  p_status text default null,
  p_sort text default 'name',
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_tokens text[];
  v_status text := lower(nullif(btrim(coalesce(p_status, '')), ''));
  v_sort text := lower(coalesce(nullif(btrim(p_sort), ''), 'name'));
  v_key text;
  v_dir text;
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if not (public.is_admin() or public.is_instructor()) then
    raise exception 'STAFF_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  if v_status = 'all' then
    v_status := null;
  end if;
  if v_status is not null and v_status not in ('active', 'inactive') then
    raise exception 'SEARCH_STATUS_INVALID' using errcode = '22023';
  end if;

  v_key := split_part(v_sort, '.', 1);
  v_dir := nullif(split_part(v_sort, '.', 2), '');
  if v_key not in ('name', 'student_id', 'last_activity', 'created')
     or coalesce(v_dir, 'asc') not in ('asc', 'desc') then
    raise exception 'SEARCH_SORT_INVALID' using errcode = '22023';
  end if;
  v_dir := coalesce(v_dir, case when v_key in ('last_activity', 'created') then 'desc' else 'asc' end);

  select coalesce(array_agg(token), '{}'::text[])
  into v_tokens
  from (
    select distinct token
    from unnest(regexp_split_to_array(lower(btrim(left(coalesce(p_query, ''), 200))), '[[:space:],;]+')) token
    where token <> ''
    limit 8
  ) words;

  with visible as (
    select p.user_id, p.full_name, p.email, p.learner_id, p.learner_id_managed, p.status, p.last_activity_at, p.created_at
    from public.profiles p
    where p.role = 'learner'::public.user_role
      and (
        v_status is null
        or (v_status = 'active' and p.status = 'active'::public.account_status)
        or (v_status = 'inactive' and p.status <> 'active'::public.account_status)
      )
  ),
  member_classes as (
    select cm.learner_id, c.id, c.title
    from public.class_memberships cm
    join public.classes c on c.id = cm.class_id
    where cm.status = 'active'::public.membership_status
      and c.status = 'active'::public.class_status
  ),
  enriched as (
    select
      v.user_id, v.full_name, v.email, v.learner_id, v.learner_id_managed, v.status, v.last_activity_at, v.created_at,
      coalesce(
        jsonb_agg(jsonb_build_object('id', mc.id, 'title', mc.title) order by mc.title, mc.id) filter (where mc.id is not null),
        '[]'::jsonb
      ) as classes,
      lower(v.full_name || ' ' || v.email || ' ' || coalesce(v.learner_id, '') || ' ' || coalesce(string_agg(mc.title, ' '), '')) as haystack,
      coalesce(bool_or(mc.id = p_class_id), false) as in_class
    from visible v
    left join member_classes mc on mc.learner_id = v.user_id
    group by v.user_id, v.full_name, v.email, v.learner_id, v.learner_id_managed, v.status, v.last_activity_at, v.created_at
  ),
  filtered as (
    select e.*
    from enriched e
    where (p_class_id is null or e.in_class)
      and not exists (select 1 from unnest(v_tokens) token where position(token in e.haystack) = 0)
  ),
  ordered as (
    select f.*,
      row_number() over (
        order by
          case when v_key = 'name' and v_dir = 'asc' then lower(f.full_name) end asc,
          case when v_key = 'name' and v_dir = 'desc' then lower(f.full_name) end desc,
          case when v_key = 'student_id' and v_dir = 'asc' then lower(nullif(btrim(f.learner_id), '')) end asc nulls last,
          case when v_key = 'student_id' and v_dir = 'desc' then lower(nullif(btrim(f.learner_id), '')) end desc nulls last,
          case when v_key = 'last_activity' and v_dir = 'desc' then f.last_activity_at end desc nulls last,
          case when v_key = 'last_activity' and v_dir = 'asc' then f.last_activity_at end asc nulls last,
          case when v_key = 'created' and v_dir = 'desc' then f.created_at end desc,
          case when v_key = 'created' and v_dir = 'asc' then f.created_at end asc,
          lower(f.full_name),
          f.user_id
      ) as position,
      count(*) over () as total
    from filtered f
  )
  select jsonb_build_object(
    'total', coalesce(max(o.total), 0),
    'limit', v_limit,
    'offset', v_offset,
    'rows', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id', o.user_id,
          'full_name', o.full_name,
          'email', o.email,
          'learner_id', o.learner_id,
          'learner_id_managed', o.learner_id_managed,
          'status', o.status,
          'classes', o.classes,
          'last_activity_at', o.last_activity_at,
          'created_at', o.created_at
        ) order by o.position
      ) filter (where o.position > v_offset and o.position <= v_offset + v_limit),
      '[]'::jsonb
    )
  )
  into v_result
  from ordered o;

  return v_result;
end
$$;

revoke all on function public.search_learners(text, uuid, text, text, integer, integer) from public, anon;
grant execute on function public.search_learners(text, uuid, text, text, integer, integer) to authenticated, service_role;

comment on function public.search_learners(text, uuid, text, text, integer, integer) is
  'Staff learner search (RLS-scoped invoker). Sorts: name, student_id, last_activity, created (optional .asc/.desc). Status: active, inactive. Limit <= 100. Returns {total, limit, offset, rows}.';

commit;
