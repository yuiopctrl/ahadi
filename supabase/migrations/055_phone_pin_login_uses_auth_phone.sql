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
