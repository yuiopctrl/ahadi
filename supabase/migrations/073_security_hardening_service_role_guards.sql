-- Security hardening review before RSVP-2.
--
-- Context: RSVP-1 (migration 072) discovered live, by actually running
-- migrations against a throwaway Postgres 17 instance and inspecting the
-- resulting pg_proc.proacl, that `revoke all ... from public; grant ... to
-- service_role;` is NOT a sufficient access boundary on its own for a
-- SECURITY DEFINER RPC that is meant to be service-only. This Supabase
-- Postgres image runs a built-in event trigger, issue_pg_graphql_access
-- (fires on ddl_command_end, which a REVOKE/GRANT statement itself is),
-- that automatically re-grants EXECUTE on every function in schema public
-- to anon/authenticated/service_role -- including immediately after an
-- explicit REVOKE. RSVP-1 fixed this for its own two public RPCs with an
-- in-function guard, require_service_role() (already defined in migration
-- 072, reused here unchanged). This migration audits every other function
-- in the schema for the same class of gap and closes the one real one
-- found: rpc_verify_phone_pin.
--
-- Audit result (see the accompanying report for the full breakdown):
--   - rpc_verify_phone_pin (migration 054/055): genuinely service-only
--     (it IS the pre-authentication phone+PIN login RPC -- there is no
--     session yet when it runs, so it cannot check auth.uid()) and was
--     relying only on the grant/revoke pair. THIS IS THE REAL GAP --
--     hardened below.
--   - rpc_set_my_pin / rpc_verify_my_pin / rpc_has_my_pin / rpc_change_my_pin
--     (migrations 008/009/056/062): all correctly scope every operation to
--     auth.uid() and reject when it is null (SESSION_REQUIRED). These are
--     ordinary authenticated self-service RPCs, not service-only -- adding
--     require_service_role() to them would break normal logged-in PIN
--     management, so they are deliberately left unchanged. Even under the
--     event-trigger over-grant, an anon caller of these gets
--     SESSION_REQUIRED, not a data leak, because auth.uid() is null for
--     anon regardless of grants.
--   - Every other "verify/service/admin/secret/token/otp/pin/internal"-
--     matching function in the schema (rpc_complete_tenant_onboarding,
--     rpc_invite_tenant_user, rpc_accept_my_tenant_invitations, etc.) is a
--     normal auth.uid()+permission-checked tenant RPC granted to
--     `authenticated`, not `service_role` -- out of scope for this guard by
--     design (see instruction not to add service-role guards to ordinary
--     authenticated RPCs).
--   - rpc_get_public_invitation_detail / rpc_submit_public_invitation_rsvp
--     (migration 072) already have require_service_role() from RSVP-1 --
--     re-verified live in this pass, unchanged here.
--
-- has_event_financial_access review (see report item 7): inspected its
-- body (migration 018). It is a GENERIC event-scoped permission checker --
-- p_permission is a caller-supplied parameter, not hardcoded to a
-- pledge/payment code, and it was already being reused for non-financial
-- permissions before RSVP-1 (e.g. rpc_create_member_and_attach_to_event
-- calls it with 'members.create'). It does not require the caller to hold
-- any pledges.*/payments.* permission to pass for 'invitation.*'/'rsvp.*'
-- -- the "financial" in its name is a historical misnomer, not a semantic
-- restriction. No replacement helper was introduced; live tests (see the
-- report) prove an invitation.view+rsvp.manage-only role can use the
-- invitation/RSVP RPCs while a pledges.create+payments.create-only role
-- cannot call rpc_record_manual_rsvp.

create or replace function public.require_service_role()
returns void
language plpgsql
stable
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
end;
$$;

do $$
declare
  pgcrypto_schema text;
begin
  select namespace.nspname into pgcrypto_schema
  from pg_extension extension
  join pg_namespace namespace on namespace.oid = extension.extnamespace
  where extension.extname = 'pgcrypto';

  if pgcrypto_schema is null then
    raise exception using
      errcode = '42883',
      message = 'pgcrypto extension is not available';
  end if;

  execute format($ddl$
    create or replace function public.rpc_verify_phone_pin(p_phone text, p_pin text)
    returns jsonb
    language plpgsql
    security definer
    set search_path = pg_catalog, public, private, auth, %1$I
    as $function$
    declare
      normalized_phone text;
      normalized_digits text;
      matched_auth_user auth.users%%rowtype;
      matched_profile public.profiles%%rowtype;
      credential private.user_pin_credentials%%rowtype;
      remaining integer;
      metadata_name text;
    begin
      -- Grants alone (revoke from public / grant to service_role, below)
      -- were found insufficient in this environment -- see the header
      -- comment. This RPC runs pre-authentication (it IS the login step),
      -- so it cannot check auth.uid(); the only available signal for "is
      -- this really our backend calling, not a direct anon/authenticated
      -- PostgREST request" is the PostgREST-resolved role itself.
      perform public.require_service_role();

      normalized_phone := public.normalize_tz_phone(p_phone);
      normalized_digits := regexp_replace(normalized_phone, '\D', '', 'g');

      if p_pin is null or p_pin !~ '^[0-9]{4}$' then
        raise exception 'PIN_INVALID' using errcode = '22023';
      end if;

      select * into matched_auth_user
      from auth.users auth_user
      where auth_user.phone_confirmed_at is not null
        and regexp_replace(coalesce(auth_user.phone, ''), '\D', '', 'g') = normalized_digits
      order by auth_user.updated_at desc nulls last, auth_user.created_at desc
      limit 1;

      if not found then
        return jsonb_build_object('ok', false, 'reason', 'NO_VERIFIED_ACCOUNT');
      end if;

      metadata_name := coalesce(matched_auth_user.raw_user_meta_data ->> 'full_name', matched_auth_user.raw_user_meta_data ->> 'name', '');

      insert into public.profiles (id, full_name, phone_e164, email, status)
      values (matched_auth_user.id, metadata_name, normalized_phone, matched_auth_user.email, 'PENDING')
      on conflict (id) do update set
        phone_e164 = excluded.phone_e164,
        email = coalesce(public.profiles.email, excluded.email),
        full_name = case when btrim(public.profiles.full_name) = '' then excluded.full_name else public.profiles.full_name end,
        status = case when public.profiles.status = 'DISABLED' then 'DISABLED' else public.profiles.status end,
        updated_at = now()
      returning * into matched_profile;

      if matched_profile.status = 'DISABLED' then
        return jsonb_build_object('ok', false, 'reason', 'NO_VERIFIED_ACCOUNT');
      end if;

      select * into credential
      from private.user_pin_credentials
      where user_id = matched_auth_user.id
      for update;

      if not found then
        return jsonb_build_object('ok', false, 'reason', 'PIN_REQUIRED');
      end if;

      if credential.locked_until is not null and credential.locked_until > now() then
        remaining := greatest(0, 5 - credential.failed_attempts);
        return jsonb_build_object(
          'ok', false,
          'reason', 'PIN_LOCKED',
          'locked_until', credential.locked_until,
          'remaining_attempts', remaining
        );
      end if;

      if credential.pin_hash = %1$I.crypt(p_pin, credential.pin_hash) then
        update private.user_pin_credentials
        set failed_attempts = 0,
            locked_until = null,
            last_verified_at = now()
        where user_id = matched_auth_user.id;

        return jsonb_build_object(
          'ok', true,
          'user_id', matched_auth_user.id,
          'phone', normalized_phone,
          'locked_until', null
        );
      end if;

      update private.user_pin_credentials
      set failed_attempts = failed_attempts + 1,
          locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end
      where user_id = matched_auth_user.id
      returning * into credential;

      remaining := greatest(0, 5 - credential.failed_attempts);
      return jsonb_build_object(
        'ok', false,
        'reason', case when credential.locked_until is null then 'PIN_INVALID' else 'PIN_LOCKED' end,
        'locked_until', credential.locked_until,
        'remaining_attempts', remaining
      );
    exception
      when others then
        if sqlerrm = 'INVALID_PHONE' then
          raise exception 'INVALID_PHONE' using errcode = '22023';
        end if;
        raise;
    end;
    $function$;
  $ddl$, pgcrypto_schema);
end;
$$;

revoke all on function public.rpc_verify_phone_pin(text, text) from public;
grant execute on function public.rpc_verify_phone_pin(text, text) to service_role;

notify pgrst, 'reload schema';
