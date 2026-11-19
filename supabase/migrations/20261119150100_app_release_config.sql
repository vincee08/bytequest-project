-- Slice A5 / WS0: minimum supported learner app version.
-- Older installed app versions do not know module locks or simulation-based
-- assessments; the new app reads this value at its splash screen and asks for
-- an update when it is below the minimum. Public, non-secret release values
-- only: the splash check runs before sign-in, so anon may read as well.
-- Writes are service-role only (release procedure). Additive.
begin;
set local lock_timeout = '5s';

create table if not exists public.app_release_config (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{2,63}$'),
  value text not null check (length(btrim(value)) between 1 and 200),
  updated_at timestamptz not null default now()
);

comment on table public.app_release_config is
  'Public, non-secret learner app release settings (for example min_supported_app_version). Service-role writes only.';

alter table public.app_release_config enable row level security;

drop policy if exists app_release_config_read on public.app_release_config;
create policy app_release_config_read
  on public.app_release_config
  for select
  to anon, authenticated
  using (true);

revoke all on public.app_release_config from public, anon, authenticated;
grant select on public.app_release_config to anon, authenticated;
grant all on public.app_release_config to service_role;

drop trigger if exists trg_app_release_config_updated_at on public.app_release_config;
create trigger trg_app_release_config_updated_at
  before update on public.app_release_config
  for each row execute function public.set_updated_at();

insert into public.app_release_config (key, value)
values ('min_supported_app_version', '1.2.0')
on conflict (key) do nothing;

commit;
