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
    create or replace function public.rpc_set_my_pin(p_pin text)
    returns jsonb
    language plpgsql
    security definer
    set search_path = pg_catalog, public, private, auth, %1$I
    as $function$
    declare
      v_user_id uuid := auth.uid();
      v_auth_phone text;
      v_normalized_phone text;
      v_email text;
      v_metadata_name text;
      v_pin_hash text;
    begin
      if v_user_id is null then
        raise exception using
          errcode = '42501',
          message = 'SESSION_REQUIRED';
      end if;

      select
        auth_user.phone,
        auth_user.email,
        coalesce(auth_user.raw_user_meta_data ->> 'full_name', auth_user.raw_user_meta_data ->> 'name', '')
      into v_auth_phone, v_email, v_metadata_name
      from auth.users auth_user
      where auth_user.id = v_user_id
        and auth_user.phone_confirmed_at is not null;

      if not found or nullif(btrim(coalesce(v_auth_phone, '')), '') is null then
        raise exception using
          errcode = '42501',
          message = 'SESSION_REQUIRED';
      end if;

      if p_pin is null or p_pin !~ '^[0-9]{4}$' then
        raise exception using
          errcode = '22023',
          message = 'PIN_INVALID';
      end if;

      if public.is_weak_pin(p_pin) then
        raise exception using
          errcode = '22023',
          message = 'PIN_TOO_WEAK';
      end if;

      v_normalized_phone := public.normalize_tz_phone(v_auth_phone);
      v_pin_hash := %1$I.crypt(p_pin, %1$I.gen_salt('bf', 10));

      insert into public.profiles (id, full_name, phone_e164, email, status)
      values (v_user_id, coalesce(v_metadata_name, ''), v_normalized_phone, v_email, 'ACTIVE')
      on conflict (id) do update set
        phone_e164 = excluded.phone_e164,
        email = coalesce(public.profiles.email, excluded.email),
        full_name = case
          when btrim(coalesce(public.profiles.full_name, '')) = '' then excluded.full_name
          else public.profiles.full_name
        end,
        status = case
          when public.profiles.status in ('DISABLED', 'SUSPENDED') then public.profiles.status
          else 'ACTIVE'
        end,
        updated_at = now();

      insert into private.user_pin_credentials (
        user_id,
        pin_hash,
        failed_attempts,
        locked_until,
        last_changed_at,
        created_at,
        updated_at
      )
      values (
        v_user_id,
        v_pin_hash,
        0,
        null,
        now(),
        now(),
        now()
      )
      on conflict (user_id) do update set
        pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null,
        last_changed_at = now(),
        updated_at = now();

      perform public.write_audit_log(null, 'pin.changed', 'profile', v_user_id, null, null, jsonb_build_object('profileStatus', 'ACTIVE'), 'User set application PIN');

      return jsonb_build_object('ok', true);
    end;
    $function$;
  $ddl$, pgcrypto_schema);
end;
$$;

update public.profiles profile
set status = 'ACTIVE',
    email = coalesce(profile.email, auth_user.email),
    full_name = case
      when btrim(coalesce(profile.full_name, '')) = '' then coalesce(auth_user.raw_user_meta_data ->> 'full_name', auth_user.raw_user_meta_data ->> 'name', '')
      else profile.full_name
    end,
    updated_at = now()
from auth.users auth_user
where profile.id = auth_user.id
  and profile.status = 'PENDING'
  and auth_user.phone_confirmed_at is not null
  and regexp_replace(coalesce(auth_user.phone, ''), '\D', '', 'g') = regexp_replace(profile.phone_e164, '\D', '', 'g')
  and exists (
    select 1
    from private.user_pin_credentials credential
    where credential.user_id = profile.id
  );

revoke all on function public.rpc_set_my_pin(text) from public;
grant execute on function public.rpc_set_my_pin(text) to authenticated;

notify pgrst, 'reload schema';
