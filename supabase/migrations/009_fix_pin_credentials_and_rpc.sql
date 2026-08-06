create schema if not exists extensions;
create schema if not exists private;

create extension if not exists pgcrypto
with schema extensions;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create table if not exists private.user_pin_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  last_changed_at timestamptz not null default now(),
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.user_pin_credentials
  add column if not exists pin_hash text,
  add column if not exists failed_attempts integer not null default 0,
  add column if not exists locked_until timestamptz,
  add column if not exists last_changed_at timestamptz not null default now(),
  add column if not exists last_verified_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'private.user_pin_credentials'::regclass
      and contype = 'c'
      and conname = 'user_pin_credentials_failed_attempts_check'
  ) then
    alter table private.user_pin_credentials
      add constraint user_pin_credentials_failed_attempts_check check (failed_attempts >= 0);
  end if;
end;
$$;

drop trigger if exists user_pin_credentials_set_updated_at on private.user_pin_credentials;
create trigger user_pin_credentials_set_updated_at
before update on private.user_pin_credentials
for each row execute function public.set_updated_at();

revoke all on private.user_pin_credentials from public;
revoke all on private.user_pin_credentials from anon, authenticated;

create or replace function public.is_weak_pin(p_pin text)
returns boolean
language sql
immutable
as $$
  select p_pin !~ '^[0-9]{4}$'
    or p_pin in (
      '0000', '1111', '2222', '3333', '4444',
      '5555', '6666', '7777', '8888', '9999',
      '1234', '4321'
    );
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
    create or replace function public.rpc_set_my_pin(p_pin text)
    returns jsonb
    language plpgsql
    security definer
    set search_path = pg_catalog, public, private, %1$I
    as $function$
    declare
      v_user_id uuid := auth.uid();
      v_pin_hash text;
    begin
      if v_user_id is null then
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

      v_pin_hash := %1$I.crypt(p_pin, %1$I.gen_salt('bf', 10));

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

      perform public.write_audit_log(null, 'pin.changed', 'profile', v_user_id, null, null, null, 'User set application PIN');

      return jsonb_build_object('ok', true);
    end;
    $function$;
  $ddl$, pgcrypto_schema);

  execute format($ddl$
    create or replace function public.rpc_verify_my_pin(p_pin text)
    returns jsonb
    language plpgsql
    security definer
    set search_path = pg_catalog, public, private, %1$I
    as $function$
    declare
      caller uuid := auth.uid();
      credential private.user_pin_credentials%%rowtype;
      remaining integer;
    begin
      if caller is null then
        raise exception 'SESSION_REQUIRED' using errcode = '42501';
      end if;

      select * into credential from private.user_pin_credentials where user_id = caller for update;
      if not found then
        raise exception 'PIN_REQUIRED' using errcode = '22023';
      end if;

      if credential.locked_until is not null and credential.locked_until > now() then
        remaining := greatest(0, 5 - credential.failed_attempts);
        return jsonb_build_object('ok', false, 'locked_until', credential.locked_until, 'remaining_attempts', remaining);
      end if;

      if credential.pin_hash = %1$I.crypt(p_pin, credential.pin_hash) then
        update private.user_pin_credentials
        set failed_attempts = 0, locked_until = null, last_verified_at = now()
        where user_id = caller;
        return jsonb_build_object('ok', true, 'locked_until', null);
      end if;

      update private.user_pin_credentials
      set failed_attempts = failed_attempts + 1,
          locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end
      where user_id = caller
      returning * into credential;

      remaining := greatest(0, 5 - credential.failed_attempts);
      return jsonb_build_object('ok', false, 'locked_until', credential.locked_until, 'remaining_attempts', remaining);
    end;
    $function$;
  $ddl$, pgcrypto_schema);
end;
$$;

create or replace function public.rpc_has_my_pin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, private
as $$
  select exists (select 1 from private.user_pin_credentials where user_id = auth.uid());
$$;

revoke all on function public.rpc_set_my_pin(text) from public;
grant execute on function public.rpc_set_my_pin(text) to authenticated;

revoke all on function public.rpc_verify_my_pin(text) from public;
grant execute on function public.rpc_verify_my_pin(text) to authenticated;

revoke all on function public.rpc_has_my_pin() from public;
grant execute on function public.rpc_has_my_pin() to authenticated;
