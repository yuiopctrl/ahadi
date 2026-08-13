create table if not exists public.tenant_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  phone_e164 text not null check (phone_e164 ~ '^\+255[67][0-9]{8}$'),
  full_name text not null default '',
  email text,
  role_code text not null check (role_code in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER', 'COLLECTOR', 'VIEWER')),
  status text not null default 'INVITED' check (status in ('INVITED', 'ACCEPTED', 'REVOKED', 'EXPIRED')),
  invited_by uuid references auth.users(id),
  accepted_by uuid references auth.users(id),
  last_sent_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tenant_invitations_tenant_idx on public.tenant_invitations(tenant_id);
create index if not exists tenant_invitations_phone_idx on public.tenant_invitations(phone_e164);
create unique index if not exists tenant_invitations_pending_unique
on public.tenant_invitations(tenant_id, phone_e164)
where status = 'INVITED';

drop trigger if exists tenant_invitations_set_updated_at on public.tenant_invitations;
create trigger tenant_invitations_set_updated_at
before update on public.tenant_invitations
for each row execute function public.set_updated_at();

alter table public.tenant_invitations enable row level security;

drop policy if exists tenant_invitations_view on public.tenant_invitations;
create policy tenant_invitations_view on public.tenant_invitations
for select using (public.has_tenant_permission(tenant_id, 'users.view'));

drop policy if exists tenant_invitations_manage on public.tenant_invitations;
create policy tenant_invitations_manage on public.tenant_invitations
for all using (public.has_tenant_permission(tenant_id, 'users.invite'))
with check (public.has_tenant_permission(tenant_id, 'users.invite'));

create or replace function public.active_tenant_owner_count(p_tenant_id uuid)
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select count(*)::integer
  from public.tenant_users tu
  where tu.tenant_id = p_tenant_id
    and tu.status = 'ACTIVE'
    and (
      tu.is_owner = true
      or exists (
        select 1
        from public.tenant_user_roles tur
        join public.roles r on r.id = tur.role_id
        where tur.tenant_user_id = tu.id
          and r.code = 'TENANT_OWNER'
      )
    );
$$;

create or replace function public.current_user_is_tenant_owner(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.tenant_users tu
    left join public.tenant_user_roles tur on tur.tenant_user_id = tu.id
    left join public.roles r on r.id = tur.role_id
    where tu.tenant_id = p_tenant_id
      and tu.user_id = auth.uid()
      and tu.status = 'ACTIVE'
      and (tu.is_owner = true or r.code = 'TENANT_OWNER')
  );
$$;

create or replace function public.assign_single_tenant_role(p_tenant_user_id uuid, p_role_code text, p_assigned_by uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  role_record public.roles%rowtype;
begin
  select * into role_record
  from public.roles
  where code = p_role_code
    and scope = 'TENANT'
    and tenant_id is null
  limit 1;

  if not found then
    raise exception 'ROLE_NOT_FOUND' using errcode = '22023';
  end if;

  delete from public.tenant_user_roles where tenant_user_id = p_tenant_user_id;
  insert into public.tenant_user_roles (tenant_user_id, role_id, assigned_by)
  values (p_tenant_user_id, role_record.id, p_assigned_by);

  update public.tenant_users
  set is_owner = (p_role_code = 'TENANT_OWNER')
  where id = p_tenant_user_id;
end;
$$;

create or replace function public.rpc_list_tenant_users(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.sort_at desc nulls last), '[]'::jsonb)
  into result
  from (
    select
      tu.id as tenant_user_id,
      null::uuid as invitation_id,
      tu.id as row_id,
      'USER'::text as row_type,
      tu.user_id,
      p.full_name,
      p.phone_e164,
      p.email,
      tu.status,
      tu.is_owner,
      tu.joined_at,
      tu.created_at,
      tu.updated_at,
      p.last_seen_at,
      tu.updated_at as sort_at,
      coalesce((select jsonb_agg(r.code order by r.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id where tur.tenant_user_id = tu.id and r.code not like 'platform.%'), '[]'::jsonb) as roles,
      coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'accessLevel', eua.access_level) order by e.name) from public.event_user_assignments eua join public.events e on e.id = eua.event_id where eua.tenant_user_id = tu.id), '[]'::jsonb) as assigned_events
    from public.tenant_users tu
    join public.profiles p on p.id = tu.user_id
    where tu.tenant_id = p_tenant_id
      and tu.status <> 'REMOVED'

    union all

    select
      null::uuid as tenant_user_id,
      ti.id as invitation_id,
      ti.id as row_id,
      'INVITATION'::text as row_type,
      null::uuid as user_id,
      ti.full_name,
      ti.phone_e164,
      ti.email,
      ti.status,
      false as is_owner,
      null::timestamptz as joined_at,
      ti.created_at,
      ti.updated_at,
      null::timestamptz as last_seen_at,
      ti.updated_at as sort_at,
      jsonb_build_array(ti.role_code) as roles,
      '[]'::jsonb as assigned_events
    from public.tenant_invitations ti
    where ti.tenant_id = p_tenant_id
      and ti.status = 'INVITED'
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_invite_tenant_user(
  p_tenant_id uuid,
  p_full_name text,
  p_phone_e164 text,
  p_email text,
  p_role_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor uuid := auth.uid();
  existing_profile public.profiles%rowtype;
  existing_tenant_user public.tenant_users%rowtype;
  tenant_user_id uuid;
  invitation_record public.tenant_invitations%rowtype;
begin
  if actor is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.invite') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_role_code not in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER', 'COLLECTOR', 'VIEWER') then
    raise exception 'ROLE_NOT_FOUND' using errcode = '22023';
  end if;
  if p_role_code = 'TENANT_OWNER' and not public.current_user_is_tenant_owner(p_tenant_id) then
    raise exception 'OWNER_ROLE_REQUIRES_OWNER' using errcode = '42501';
  end if;

  select * into existing_profile
  from public.profiles
  where phone_e164 = p_phone_e164
    and status = 'ACTIVE'
  limit 1;

  if found then
    select * into existing_tenant_user
    from public.tenant_users
    where tenant_id = p_tenant_id
      and user_id = existing_profile.id
    limit 1;

    if found and existing_tenant_user.status in ('ACTIVE', 'INVITED', 'SUSPENDED') then
      raise exception 'USER_ALREADY_IN_TENANT' using errcode = '23505';
    end if;

    insert into public.tenant_users (tenant_id, user_id, status, is_owner, invited_by, joined_at)
    values (p_tenant_id, existing_profile.id, 'ACTIVE', p_role_code = 'TENANT_OWNER', actor, now())
    on conflict (tenant_id, user_id) do update set
      status = 'ACTIVE',
      is_owner = (p_role_code = 'TENANT_OWNER'),
      invited_by = actor,
      joined_at = coalesce(public.tenant_users.joined_at, now()),
      updated_at = now()
    returning id into tenant_user_id;

    perform public.assign_single_tenant_role(tenant_user_id, p_role_code, actor);

    update public.tenant_invitations
    set status = 'ACCEPTED', accepted_by = existing_profile.id, accepted_at = now()
    where tenant_id = p_tenant_id and phone_e164 = p_phone_e164 and status = 'INVITED';

    perform public.write_audit_log(p_tenant_id, 'user.invited', 'tenant_user', tenant_user_id, null, null, jsonb_build_object('targetUserId', existing_profile.id, 'role', p_role_code, 'existingUser', true));
    return jsonb_build_object('kind', 'USER', 'tenantUserId', tenant_user_id, 'status', 'ACTIVE', 'smsQueued', false);
  end if;

  select * into invitation_record
  from public.tenant_invitations
  where tenant_id = p_tenant_id
    and phone_e164 = p_phone_e164
    and status = 'INVITED'
  limit 1;

  if found then
    return jsonb_build_object('kind', 'INVITATION', 'invitationId', invitation_record.id, 'status', 'INVITED', 'alreadyPending', true, 'smsQueued', false);
  end if;

  insert into public.tenant_invitations (tenant_id, phone_e164, full_name, email, role_code, invited_by, last_sent_at)
  values (p_tenant_id, p_phone_e164, coalesce(nullif(btrim(p_full_name), ''), ''), nullif(btrim(coalesce(p_email, '')), ''), p_role_code, actor, now())
  returning * into invitation_record;

  perform public.write_audit_log(p_tenant_id, 'user.invited', 'tenant_invitation', invitation_record.id, null, null, jsonb_build_object('phone', p_phone_e164, 'role', p_role_code, 'existingUser', false, 'smsQueued', false));
  return jsonb_build_object('kind', 'INVITATION', 'invitationId', invitation_record.id, 'status', 'INVITED', 'alreadyPending', false, 'smsQueued', false);
end;
$$;

create or replace function public.rpc_resend_tenant_invitation(p_tenant_id uuid, p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invitation_record public.tenant_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.invite') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  update public.tenant_invitations
  set last_sent_at = now()
  where id = p_invitation_id
    and tenant_id = p_tenant_id
    and status = 'INVITED'
  returning * into invitation_record;

  if not found then
    raise exception 'INVITATION_INVALID' using errcode = '22023';
  end if;

  perform public.write_audit_log(p_tenant_id, 'invitation.resent', 'tenant_invitation', p_invitation_id, null, null, jsonb_build_object('phone', invitation_record.phone_e164, 'role', invitation_record.role_code, 'smsQueued', false));
  return jsonb_build_object('ok', true, 'smsQueued', false);
end;
$$;

create or replace function public.rpc_update_tenant_user_role(p_tenant_id uuid, p_tenant_user_id uuid, p_role_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target public.tenant_users%rowtype;
  old_roles jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.manage_roles') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_role_code not in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER', 'COLLECTOR', 'VIEWER') then
    raise exception 'ROLE_NOT_FOUND' using errcode = '22023';
  end if;
  if p_role_code = 'TENANT_OWNER' and not public.current_user_is_tenant_owner(p_tenant_id) then
    raise exception 'OWNER_ROLE_REQUIRES_OWNER' using errcode = '42501';
  end if;

  select * into target from public.tenant_users where id = p_tenant_user_id and tenant_id = p_tenant_id and status <> 'REMOVED' for update;
  if not found then
    raise exception 'USER_NOT_FOUND' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(r.code order by r.code), '[]'::jsonb)
  into old_roles
  from public.tenant_user_roles tur
  join public.roles r on r.id = tur.role_id
  where tur.tenant_user_id = p_tenant_user_id;

  if (target.is_owner or old_roles ? 'TENANT_OWNER') and p_role_code <> 'TENANT_OWNER' and public.active_tenant_owner_count(p_tenant_id) <= 1 then
    raise exception 'LAST_OWNER_REQUIRED' using errcode = '23514';
  end if;

  perform public.assign_single_tenant_role(p_tenant_user_id, p_role_code, auth.uid());
  perform public.write_audit_log(p_tenant_id, 'user.role_changed', 'tenant_user', p_tenant_user_id, null, jsonb_build_object('roles', old_roles), jsonb_build_object('roles', jsonb_build_array(p_role_code)));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rpc_set_tenant_user_status(p_tenant_id uuid, p_tenant_user_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target public.tenant_users%rowtype;
  old_status text;
  target_roles jsonb;
  action_name text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if p_status not in ('ACTIVE', 'SUSPENDED', 'REMOVED') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.suspend') and not public.has_tenant_permission(p_tenant_id, 'users.manage_roles') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into target from public.tenant_users where id = p_tenant_user_id and tenant_id = p_tenant_id and status <> 'REMOVED' for update;
  if not found then
    raise exception 'USER_NOT_FOUND' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(r.code order by r.code), '[]'::jsonb)
  into target_roles
  from public.tenant_user_roles tur
  join public.roles r on r.id = tur.role_id
  where tur.tenant_user_id = p_tenant_user_id;

  if p_status in ('SUSPENDED', 'REMOVED') and (target.is_owner or target_roles ? 'TENANT_OWNER') and public.active_tenant_owner_count(p_tenant_id) <= 1 then
    raise exception 'LAST_OWNER_REQUIRED' using errcode = '23514';
  end if;

  old_status := target.status;
  update public.tenant_users
  set status = p_status,
      joined_at = case when p_status = 'ACTIVE' then coalesce(joined_at, now()) else joined_at end,
      updated_at = now()
  where id = p_tenant_user_id;

  action_name := case p_status
    when 'ACTIVE' then 'user.reactivated'
    when 'SUSPENDED' then 'user.suspended'
    else 'user.removed'
  end;

  perform public.write_audit_log(p_tenant_id, action_name, 'tenant_user', p_tenant_user_id, null, jsonb_build_object('status', old_status), jsonb_build_object('status', p_status));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rpc_accept_my_tenant_invitations()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  profile_record public.profiles%rowtype;
  invitation_record public.tenant_invitations%rowtype;
  tenant_user_id uuid;
  accepted_count integer := 0;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into profile_record from public.profiles where id = caller and status = 'ACTIVE';
  if not found then
    return jsonb_build_object('accepted', 0);
  end if;

  for invitation_record in
    select * from public.tenant_invitations
    where phone_e164 = profile_record.phone_e164
      and status = 'INVITED'
    for update
  loop
    insert into public.tenant_users (tenant_id, user_id, status, is_owner, invited_by, joined_at)
    values (invitation_record.tenant_id, caller, 'ACTIVE', invitation_record.role_code = 'TENANT_OWNER', invitation_record.invited_by, now())
    on conflict (tenant_id, user_id) do update set
      status = 'ACTIVE',
      is_owner = (invitation_record.role_code = 'TENANT_OWNER'),
      joined_at = coalesce(public.tenant_users.joined_at, now()),
      updated_at = now()
    returning id into tenant_user_id;

    perform public.assign_single_tenant_role(tenant_user_id, invitation_record.role_code, invitation_record.invited_by);

    update public.tenant_invitations
    set status = 'ACCEPTED', accepted_by = caller, accepted_at = now()
    where id = invitation_record.id;

    perform public.write_audit_log(invitation_record.tenant_id, 'invitation.accepted', 'tenant_user', tenant_user_id, null, jsonb_build_object('invitationId', invitation_record.id), jsonb_build_object('targetUserId', caller, 'role', invitation_record.role_code));
    accepted_count := accepted_count + 1;
  end loop;

  return jsonb_build_object('accepted', accepted_count);
end;
$$;

do $$
declare
  pgcrypto_schema text;
  ddl text;
begin
  select namespace.nspname into pgcrypto_schema
  from pg_extension extension
  join pg_namespace namespace on namespace.oid = extension.extnamespace
  where extension.extname = 'pgcrypto';

  if pgcrypto_schema is null then
    create schema if not exists extensions;
    create extension if not exists pgcrypto with schema extensions;
    pgcrypto_schema := 'extensions';
  end if;

  ddl := format($function$
    create or replace function public.rpc_change_my_pin(p_current_pin text, p_new_pin text)
    returns jsonb
    language plpgsql
    security definer
    set search_path = pg_catalog, public, private, %1$I
    as $inner$
    declare
      caller uuid := auth.uid();
      credential private.user_pin_credentials%%rowtype;
      remaining integer;
      new_hash text;
    begin
      if caller is null then
        raise exception 'SESSION_REQUIRED' using errcode = '42501';
      end if;
      if p_current_pin is null or p_current_pin !~ '^[0-9]{4}$' or p_new_pin is null or p_new_pin !~ '^[0-9]{4}$' then
        raise exception 'PIN_INVALID' using errcode = '22023';
      end if;
      if public.is_weak_pin(p_new_pin) then
        raise exception 'PIN_TOO_WEAK' using errcode = '22023';
      end if;

      select * into credential from private.user_pin_credentials where user_id = caller for update;
      if not found then
        raise exception 'PIN_REQUIRED' using errcode = '22023';
      end if;

      if credential.locked_until is not null and credential.locked_until > now() then
        remaining := greatest(0, 5 - credential.failed_attempts);
        return jsonb_build_object('ok', false, 'locked_until', credential.locked_until, 'remaining_attempts', remaining);
      end if;

      if credential.pin_hash <> %1$I.crypt(p_current_pin, credential.pin_hash) then
        update private.user_pin_credentials
        set failed_attempts = failed_attempts + 1,
            locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end
        where user_id = caller
        returning * into credential;

        remaining := greatest(0, 5 - credential.failed_attempts);
        return jsonb_build_object('ok', false, 'locked_until', credential.locked_until, 'remaining_attempts', remaining);
      end if;

      new_hash := %1$I.crypt(p_new_pin, %1$I.gen_salt('bf', 10));

      update private.user_pin_credentials
      set pin_hash = new_hash,
          failed_attempts = 0,
          locked_until = null,
          last_changed_at = now(),
          last_verified_at = null,
          updated_at = now()
      where user_id = caller;

      perform public.write_audit_log(null, 'pin.changed', 'profile', caller, null, null, null, 'User changed application PIN');
      return jsonb_build_object('ok', true);
    end;
    $inner$;
  $function$, pgcrypto_schema);

  execute ddl;
end;
$$;

revoke all on function public.rpc_change_my_pin(text, text) from public;
grant execute on function public.rpc_change_my_pin(text, text) to authenticated;
grant execute on function public.rpc_list_tenant_users(uuid) to authenticated;
grant execute on function public.rpc_invite_tenant_user(uuid, text, text, text, text) to authenticated;
grant execute on function public.rpc_resend_tenant_invitation(uuid, uuid) to authenticated;
grant execute on function public.rpc_update_tenant_user_role(uuid, uuid, text) to authenticated;
grant execute on function public.rpc_set_tenant_user_status(uuid, uuid, text) to authenticated;
grant execute on function public.rpc_accept_my_tenant_invitations() to authenticated;
