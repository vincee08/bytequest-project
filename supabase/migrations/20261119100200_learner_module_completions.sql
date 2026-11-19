-- Re-defense foundation: durable module completion records. Written only by
-- the server-side unlock refresh (sequential-unlocking slice) the first time
-- a learner completes a module; consumed by gamification and analytics. Rows
-- are never deleted, so later content changes cannot revoke an achievement.

begin;

create table public.learner_module_completions (
  learner_id uuid not null references public.profiles(user_id) on delete restrict,
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  completed_at timestamptz not null default now(),
  primary key (learner_id, module_id)
);

create trigger trg_learner_module_completions_append_only
  before update or delete on public.learner_module_completions
  for each row execute function private.prevent_append_only_mutation();

alter table public.learner_module_completions enable row level security;

create policy learner_module_completions_read on public.learner_module_completions
  for select to authenticated using (
    learner_id = (select auth.uid()) or public.is_admin()
    or private.current_instructor_teaches_learner(learner_id)
  );

grant select on public.learner_module_completions to authenticated;
grant all on public.learner_module_completions to service_role;

notify pgrst, 'reload schema';

commit;
