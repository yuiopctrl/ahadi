create table private.user_pin_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  last_changed_at timestamptz not null default now(),
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger user_pin_credentials_set_updated_at
before update on private.user_pin_credentials
for each row execute function public.set_updated_at();

create or replace function public.is_weak_pin(p_pin text)
returns boolean
language sql
immutable
as $$
  select p_pin !~ '^[0-9]{4}$'
    or p_pin in ('0000','1111','1234','4321')
    or p_pin ~ '^([0-9])\1{3}$';
$$;

create or replace function public.rpc_set_my_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if public.is_weak_pin(p_pin) then
    raise exception 'PIN_INVALID' using errcode = '22023';
  end if;

  insert into private.user_pin_credentials (user_id, pin_hash, failed_attempts, locked_until, last_changed_at)
  values (caller, crypt(p_pin, gen_salt('bf')), 0, null, now())
  on conflict (user_id) do update set
    pin_hash = excluded.pin_hash,
    failed_attempts = 0,
    locked_until = null,
    last_changed_at = now(),
    updated_at = now();

  perform public.write_audit_log(null, 'pin.changed', 'profile', caller, null, null, null, 'User set application PIN');
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rpc_has_my_pin()
returns boolean
language sql
stable
security definer
set search_path = private
as $$
  select exists (select 1 from private.user_pin_credentials where user_id = auth.uid());
$$;

create or replace function public.rpc_verify_my_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  credential private.user_pin_credentials%rowtype;
  remaining integer;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into credential from private.user_pin_credentials where user_id = caller for update;
  if not found then
    raise exception 'PIN_REQUIRED' using errcode = '22023';
  end if;

  if credential.locked_until is not null and credential.locked_until > now() then
    remaining := greatest(0, 5 - credential.failed_attempts);
    return jsonb_build_object('ok', false, 'locked_until', credential.locked_until, 'remaining_attempts', remaining);
  end if;

  if credential.pin_hash = crypt(p_pin, credential.pin_hash) then
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
$$;
