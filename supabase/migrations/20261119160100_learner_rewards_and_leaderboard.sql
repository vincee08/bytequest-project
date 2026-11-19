-- Slice A6 (Objective 2): learner Rewards projection and opt-in class
-- leaderboard.
--
-- public.get_learner_rewards() is SECURITY INVOKER and runs under the
-- caller's RLS. Learners cannot read classmates' profiles or point events, so
-- the leaderboard reads public.gamification_leaderboard_entries: a derived,
-- privacy-preserving projection holding only a "First name L." display name,
-- the points total, the opt-in flag and an active-learner flag. A classmate's
-- row is visible to a learner only when that classmate opted in and both are
-- active members of the same active class (checked with the existing
-- public.learner_is_enrolled helper). Every column is derived by a trigger
-- from profiles and learner_point_events, so no write can store a value that
-- differs from the source records.
--
-- Additive only; no new SECURITY DEFINER function.

begin;
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- Opt-in preference (learners toggle their own row; existing profile RLS
-- limits updates to self)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column show_on_leaderboard boolean not null default false;
grant update (show_on_leaderboard) on public.profiles to authenticated;
comment on column public.profiles.show_on_leaderboard is
  'Learner opt-in: show my first name, last initial and points to classmates in my active classes.';

-- "First name L." Never exposes an email address or a full surname.
create function private.gamification_display_name(p_full_name text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_parts text[] := regexp_split_to_array(btrim(coalesce(p_full_name, '')), '\s+');
  v_first text := left(split_part(coalesce(v_parts[1], ''), '@', 1), 40);
  v_last text;
begin
  if v_first = '' then
    return 'Learner';
  end if;
  if cardinality(v_parts) > 1 then
    v_last := v_parts[cardinality(v_parts)];
    if v_last <> '' and position('@' in v_last) = 0 then
      return v_first || ' ' || upper(left(v_last, 1)) || '.';
    end if;
  end if;
  return v_first;
end
$$;

-- ---------------------------------------------------------------------------
-- Leaderboard projection
-- ---------------------------------------------------------------------------
create table public.gamification_leaderboard_entries (
  learner_id uuid primary key references public.profiles(user_id) on delete cascade,
  display_name text not null default 'Learner' check (length(display_name) between 1 and 60),
  points integer not null default 0 check (points >= 0),
  show_on_leaderboard boolean not null default false,
  is_active_learner boolean not null default false,
  updated_at timestamptz not null default now()
);

create index gamification_leaderboard_entries_visible_idx
  on public.gamification_leaderboard_entries (points desc)
  where show_on_leaderboard and is_active_learner;

-- Every column is re-derived on every write, whoever performs it.
create function private.gamification_leaderboard_derive()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_full_name text;
  v_show boolean;
  v_active boolean;
begin
  select p.full_name,
         p.show_on_leaderboard,
         p.role = 'learner'::public.user_role and p.status = 'active'::public.account_status
  into v_full_name, v_show, v_active
  from public.profiles p
  where p.user_id = new.learner_id;
  new.display_name := private.gamification_display_name(v_full_name);
  new.show_on_leaderboard := coalesce(v_show, false);
  new.is_active_learner := coalesce(v_active, false);
  new.points := coalesce((
    select sum(e.points) from public.learner_point_events e where e.learner_id = new.learner_id
  ), 0);
  new.updated_at := now();
  return new;
end
$$;

create trigger trg_gamification_leaderboard_entries_derive
  before insert or update on public.gamification_leaderboard_entries
  for each row execute function private.gamification_leaderboard_derive();

-- New awards refresh the learner's total (runs in the trusted award path).
create function private.gamification_leaderboard_refresh_points()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into public.gamification_leaderboard_entries (learner_id)
  select new.learner_id
  where exists (select 1 from public.profiles p where p.user_id = new.learner_id)
  on conflict (learner_id) do update set updated_at = excluded.updated_at;
  return null;
end
$$;

create trigger trg_learner_point_events_refresh_leaderboard
  after insert on public.learner_point_events
  for each row execute function private.gamification_leaderboard_refresh_points();

-- Profiles create the entry and keep name, opt-in and account state current.
-- A learner's own opt-in toggle runs this as that learner, which is why the
-- entry grants exactly one updatable column and re-derives everything.
create function private.gamification_leaderboard_refresh_profile()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.gamification_leaderboard_entries (learner_id)
    values (new.user_id)
    on conflict (learner_id) do nothing;
  elsif new.full_name is distinct from old.full_name
     or new.show_on_leaderboard is distinct from old.show_on_leaderboard
     or new.role is distinct from old.role
     or new.status is distinct from old.status then
    update public.gamification_leaderboard_entries
    set show_on_leaderboard = new.show_on_leaderboard
    where learner_id = new.user_id;
  end if;
  return null;
end
$$;

create trigger trg_profiles_refresh_leaderboard
  after insert or update of full_name, show_on_leaderboard, role, status on public.profiles
  for each row execute function private.gamification_leaderboard_refresh_profile();

insert into public.gamification_leaderboard_entries (learner_id)
select p.user_id from public.profiles p
on conflict (learner_id) do nothing;

alter table public.gamification_leaderboard_entries enable row level security;

-- Own entry; admins and owning instructors for analytics; opted-in active
-- learners who share an active class with the calling learner.
create policy gamification_leaderboard_entries_read on public.gamification_leaderboard_entries
  for select to authenticated using (
    learner_id = (select auth.uid())
    or (select public.is_admin())
    or private.current_instructor_teaches_learner(learner_id)
    or (
      show_on_leaderboard
      and is_active_learner
      and (select public.is_learner())
      and exists (
        select 1
        from public.class_memberships mine
        join public.classes c on c.id = mine.class_id
        where mine.learner_id = (select auth.uid())
          and mine.status = 'active'::public.membership_status
          and c.status = 'active'::public.class_status
          and public.learner_is_enrolled(mine.class_id, gamification_leaderboard_entries.learner_id)
      )
    )
  );

create policy gamification_leaderboard_entries_refresh_own on public.gamification_leaderboard_entries
  for update to authenticated
  using (learner_id = (select auth.uid()))
  with check (learner_id = (select auth.uid()));

revoke all on public.gamification_leaderboard_entries from public, anon, authenticated;
grant select on public.gamification_leaderboard_entries to authenticated;
grant update (show_on_leaderboard) on public.gamification_leaderboard_entries to authenticated;
grant all on public.gamification_leaderboard_entries to service_role;

-- ---------------------------------------------------------------------------
-- Learner Rewards projection
-- ---------------------------------------------------------------------------
create function public.get_learner_rewards()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_profile public.profiles;
  v_points integer;
  v_name text;
begin
  -- is_learner() is null (not false) for a deactivated account.
  if v_me is null or not coalesce(public.is_learner(), false) then
    raise exception 'LEARNER_REQUIRED' using errcode = '42501';
  end if;

  select * into v_profile from public.profiles p where p.user_id = v_me;
  select coalesce(sum(e.points), 0)::integer into v_points
  from public.learner_point_events e
  where e.learner_id = v_me;
  v_name := private.gamification_display_name(v_profile.full_name);

  return jsonb_build_object(
    'points', v_points,
    'level', public.gamification_level_for_points(v_points),
    'show_on_leaderboard', coalesce(v_profile.show_on_leaderboard, false),
    'achievements', coalesce((
      select jsonb_agg(jsonb_build_object(
          'code', a.achievement_code,
          'title', a.title,
          'description', a.description,
          'icon', a.icon,
          'earned_at', ua.earned_at,
          'progress_current', case when ua.id is not null then progress.target
                                   else least(progress.current, progress.target) end,
          'progress_target', progress.target)
        order by a.sort_order, a.achievement_code)
      from public.achievements a
      left join public.user_achievements ua on ua.achievement_id = a.id and ua.user_id = v_me
      cross join lateral (
        select
          case when a.rule->>'type' = 'count' then (a.rule->>'min')::integer else 1 end as target,
          (select count(*)::integer
           from public.learner_point_events e
           where e.learner_id = v_me
             and e.event_type = a.rule->>'event_type'
             and (a.rule->>'type' = 'count' or e.source_id = a.rule->>'source_id')) as current
      ) progress
      where a.rule is not null
    ), '[]'::jsonb),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object(
          'event_type', x.event_type,
          'label', x.label,
          'points', x.points,
          'awarded_at', x.awarded_at,
          'source_id', x.source_id,
          'detail', x.detail)
        order by x.awarded_at desc, x.id desc)
      from (
        select e.id, e.event_type, r.label, e.points, e.awarded_at, e.source_id, e.detail
        from public.learner_point_events e
        join public.gamification_point_rules r on r.event_type = e.event_type
        where e.learner_id = v_me
        order by e.awarded_at desc, e.id desc
        limit 10
      ) x
    ), '[]'::jsonb),
    'points_by_category', coalesce((
      select jsonb_agg(jsonb_build_object(
          'event_type', r.event_type,
          'label', r.label,
          'points', coalesce(s.points, 0),
          'count', coalesce(s.events, 0),
          'points_each', r.points,
          'active', r.active)
        order by r.sort_order, r.event_type)
      from public.gamification_point_rules r
      left join (
        select e.event_type, sum(e.points)::integer as points, count(*)::integer as events
        from public.learner_point_events e
        where e.learner_id = v_me
        group by e.event_type
      ) s on s.event_type = r.event_type
      where r.active or coalesce(s.points, 0) > 0
    ), '[]'::jsonb),
    'leaderboard', coalesce((
      with board as (
        select l.learner_id, l.display_name, l.points
        from public.gamification_leaderboard_entries l
        where l.learner_id <> v_me and l.show_on_leaderboard and l.is_active_learner
        union all
        select v_me, v_name, v_points
      ),
      ranked as (
        select b.learner_id, b.display_name, b.points,
               rank() over (order by b.points desc) as standing,
               row_number() over (order by b.points desc, b.display_name, b.learner_id) as position
        from board b
      )
      select jsonb_agg(jsonb_build_object(
          'rank', ranked.standing,
          'display_name', ranked.display_name,
          'points', ranked.points,
          'is_me', ranked.learner_id = v_me)
        order by ranked.position)
      from ranked
      where ranked.position <= 10 or ranked.learner_id = v_me
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function private.gamification_display_name(text) from public, anon, authenticated;
grant execute on function private.gamification_display_name(text) to authenticated, service_role;
revoke all on function private.gamification_leaderboard_derive() from public, anon, authenticated;
revoke all on function private.gamification_leaderboard_refresh_points() from public, anon, authenticated;
revoke all on function private.gamification_leaderboard_refresh_profile() from public, anon, authenticated;
revoke all on function public.get_learner_rewards() from public, anon;
grant execute on function public.get_learner_rewards() to authenticated;

comment on table public.gamification_leaderboard_entries is
  'Derived, privacy-preserving leaderboard projection (display name, points, opt-in). Columns are re-derived from profiles and learner_point_events on every write.';
comment on function public.get_learner_rewards() is
  'Learner Rewards tab: points, level progress, achievements, recent points, points by category and the opt-in class leaderboard. Motivational only; never used for competency.';

notify pgrst, 'reload schema';

commit;
