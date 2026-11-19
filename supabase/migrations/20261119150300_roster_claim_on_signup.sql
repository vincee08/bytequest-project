-- Slice A5 / WS8, spec Section 9: public.handle_new_user claims pending roster
-- entries. After the profile is provisioned exactly as before, pending entries
-- whose normalized email equals the new user's email (and whose student ID is
-- empty or equals the sign-up metadata student ID when one is provided) are
-- claimed: an active membership is created, the entry is marked enrolled, the
-- student ID is set as staff-managed when the profile has none, and audit
-- events are written. The claim runs in its own subtransaction: any error is
-- logged and audited, never raised, so it can never fail the sign-up.
-- Known limitation (documented): sign-up email is not verified while SMTP is
-- deferred; the instructor can remove a claimed enrollment from the class.
begin;
set local lock_timeout = '5s';

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(new.email, '')));
  v_meta_student_id text := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'learner_id'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'student_id'), '')
  );
  v_profile public.profiles;
  v_entry record;
  v_membership public.class_memberships;
  v_distinct_ids integer;
  v_student_id text;
begin
  insert into public.profiles (user_id, email, full_name, role, status)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'learner'::public.user_role,
    'active'::public.account_status
  )
  on conflict (user_id) do update
    set email = excluded.email;

  if v_email = '' then
    return new;
  end if;

  begin
    select * into v_profile from public.profiles where user_id = new.id;

    if v_profile.role = 'learner'::public.user_role
       and v_profile.status = 'active'::public.account_status then
      for v_entry in
        select e.id, e.class_id, e.student_id, coalesce(e.created_by, c.instructor_id) as enrolled_by
        from public.class_roster_entries e
        join public.classes c on c.id = e.class_id
        where e.email_normalized = v_email
          and e.status = 'pending'
          and c.status = 'active'::public.class_status
          and (v_meta_student_id is null or e.student_id is null or lower(e.student_id) = lower(v_meta_student_id))
        order by e.created_at, e.id
        for update of e
      loop
        v_membership := null;
        insert into public.class_memberships (class_id, learner_id, status, enrolled_by)
        values (v_entry.class_id, new.id, 'active'::public.membership_status, v_entry.enrolled_by)
        on conflict (class_id, learner_id) where status = 'active'::public.membership_status do nothing
        returning * into v_membership;

        update public.class_roster_entries
        set status = 'enrolled', claimed_user_id = new.id, claimed_at = clock_timestamp()
        where id = v_entry.id;

        if v_membership.id is not null then
          insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
          values (
            new.id, 'learner'::public.user_role, 'class_membership.enrolled', 'class_membership', v_membership.id,
            null, to_jsonb(v_membership),
            jsonb_build_object('class_id', v_entry.class_id, 'learner_id', new.id, 'source', 'roster_claim', 'roster_entry_id', v_entry.id)
          );
        end if;

        insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, metadata)
        values (
          new.id, 'learner'::public.user_role, 'class_roster_entry.claimed', 'class_roster_entry', v_entry.id,
          jsonb_build_object('class_id', v_entry.class_id, 'learner_id', new.id, 'membership_id', v_membership.id)
        );
      end loop;

      -- Set the student ID only when every claimed entry agrees on one value,
      -- the profile has none and no other learner already uses it.
      select count(distinct lower(e.student_id)), (array_agg(e.student_id order by e.created_at, e.id))[1]
      into v_distinct_ids, v_student_id
      from public.class_roster_entries e
      where e.claimed_user_id = new.id
        and e.status = 'enrolled'
        and e.student_id is not null;

      if v_distinct_ids = 1
         and nullif(btrim(v_profile.learner_id), '') is null
         and not exists (
           select 1 from public.profiles o
           where o.role = 'learner'::public.user_role
             and o.user_id <> new.id
             and lower(btrim(o.learner_id)) = lower(v_student_id)
         ) then
        update public.profiles
        set learner_id = v_student_id, learner_id_managed = true
        where user_id = new.id;

        insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
        values (
          new.id, 'learner'::public.user_role, 'profile.student_id_set', 'profile', new.id,
          jsonb_build_object('learner_id', v_profile.learner_id, 'learner_id_managed', v_profile.learner_id_managed),
          jsonb_build_object('learner_id', v_student_id, 'learner_id_managed', true),
          jsonb_build_object('source', 'roster_claim')
        );
      end if;
    end if;
  exception when others then
    raise warning 'ROSTER_CLAIM_FAILED user=% sqlstate=% message=%', new.id, sqlstate, sqlerrm;
    begin
      insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, metadata, outcome)
      values (
        new.id, 'learner'::public.user_role, 'class_roster_entry.claim_failed', 'profile', new.id,
        jsonb_build_object('sqlstate', sqlstate), 'failed'
      );
    exception when others then
      raise warning 'ROSTER_CLAIM_AUDIT_FAILED user=%', new.id;
    end;
  end;

  return new;
end
$$;

-- Auth signup invokes this function through the auth.users trigger only.
revoke execute on function public.handle_new_user() from public, anon, authenticated, service_role;

comment on function public.handle_new_user() is
  'Auth profile provisioning trigger helper (fixed search_path, no client EXECUTE). Also claims pending class roster entries for the new email; claim errors are logged and audited, never raised.';

commit;
