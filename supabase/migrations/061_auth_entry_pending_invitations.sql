create or replace function public.rpc_list_my_tenant_invitations()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  profile_record public.profiles%rowtype;
  result jsonb;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into profile_record
  from public.profiles
  where id = caller
    and status = 'ACTIVE';
  if not found or profile_record.phone_e164 is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'invitationId', ti.id,
    'tenantId', t.id,
    'tenantName', t.name,
    'tenantCode', t.code,
    'fullName', ti.full_name,
    'phoneE164', ti.phone_e164,
    'email', ti.email,
    'roleCode', ti.role_code,
    'status', ti.status,
    'invitedAt', ti.created_at,
    'lastSentAt', ti.last_sent_at
  ) order by ti.created_at), '[]'::jsonb)
  into result
  from public.tenant_invitations ti
  join public.tenants t on t.id = ti.tenant_id
  where ti.phone_e164 = profile_record.phone_e164
    and ti.status = 'INVITED';

  return result;
end;
$$;

create or replace function public.rpc_accept_tenant_invitation(p_invitation_id uuid)
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
  profile_name_backfilled boolean := false;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into profile_record
  from public.profiles
  where id = caller
    and status = 'ACTIVE';
  if not found then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into invitation_record
  from public.tenant_invitations
  where id = p_invitation_id
    and status = 'INVITED'
  for update;
  if not found then
    raise exception 'INVITATION_INVALID' using errcode = '22023';
  end if;
  if invitation_record.phone_e164 <> profile_record.phone_e164 then
    raise exception 'INVITATION_INVALID' using errcode = '42501';
  end if;

  if btrim(coalesce(profile_record.full_name, '')) = '' and btrim(coalesce(invitation_record.full_name, '')) <> '' then
    update public.profiles
    set full_name = btrim(invitation_record.full_name),
        updated_at = now()
    where id = caller
      and btrim(coalesce(full_name, '')) = '';
    profile_name_backfilled := true;
  end if;

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
  set status = 'ACCEPTED',
      accepted_by = caller,
      accepted_at = now()
  where id = invitation_record.id;

  perform public.write_audit_log(invitation_record.tenant_id, 'invitation.accepted', 'tenant_user', tenant_user_id, null, jsonb_build_object('invitationId', invitation_record.id), jsonb_build_object('targetUserId', caller, 'role', invitation_record.role_code, 'profileNameBackfilled', profile_name_backfilled));

  return jsonb_build_object(
    'ok', true,
    'tenantId', invitation_record.tenant_id,
    'tenantUserId', tenant_user_id,
    'profileNameBackfilled', profile_name_backfilled
  );
end;
$$;

create or replace function public.rpc_decline_tenant_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  profile_record public.profiles%rowtype;
  invitation_record public.tenant_invitations%rowtype;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into profile_record
  from public.profiles
  where id = caller
    and status = 'ACTIVE';
  if not found then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  update public.tenant_invitations
  set status = 'REVOKED',
      updated_at = now()
  where id = p_invitation_id
    and phone_e164 = profile_record.phone_e164
    and status = 'INVITED'
  returning * into invitation_record;

  if not found then
    raise exception 'INVITATION_INVALID' using errcode = '22023';
  end if;

  perform public.write_audit_log(invitation_record.tenant_id, 'invitation.declined', 'tenant_invitation', p_invitation_id, null, jsonb_build_object('phone', invitation_record.phone_e164, 'role', invitation_record.role_code), jsonb_build_object('targetUserId', caller));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rpc_accept_my_tenant_invitations()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  return jsonb_build_object('accepted', 0, 'requiresExplicitAcceptance', true);
end;
$$;

create or replace function public.rpc_get_my_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with platform_permissions as (
    select array[
      'platform.dashboard.view','platform.tenants.view','platform.tenants.manage','platform.plans.view','platform.plans.manage','platform.subscriptions.manage','platform.sms.view','platform.audit.view','platform.settings.manage',
      'platform.beta.view','platform.beta.manage','platform.support.view','platform.support.manage','platform.feedback.view','platform.features.view','platform.features.manage','platform.system_errors.view','platform.support_session.start'
    ]::text[] as owner_permissions
  )
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'fullName', p.full_name,
      'phoneE164', p.phone_e164,
      'email', p.email,
      'avatarUrl', p.avatar_url,
      'status', p.status,
      'preferredLanguage', p.preferred_language,
      'onboardingCompletedAt', p.onboarding_completed_at
    ),
    'isPlatformUser', pu.id is not null and pu.status = 'ACTIVE',
    'platformRole', case when pu.status = 'ACTIVE' then pu.role else null end,
    'platformStatus', pu.status,
    'platformPermissions', case
      when pu.status <> 'ACTIVE' or pu.id is null then '[]'::jsonb
      when pu.role = 'PLATFORM_OWNER' then to_jsonb(platform_permissions.owner_permissions)
      when pu.role = 'PLATFORM_ADMIN' then '["platform.dashboard.view","platform.tenants.view","platform.tenants.manage","platform.plans.view","platform.plans.manage","platform.subscriptions.manage","platform.sms.view","platform.beta.view","platform.beta.manage","platform.support.view","platform.support.manage","platform.feedback.view","platform.features.view","platform.features.manage","platform.system_errors.view"]'::jsonb
      when pu.role = 'PLATFORM_SUPPORT' then '["platform.dashboard.view","platform.tenants.view","platform.sms.view","platform.support.view","platform.support.manage","platform.feedback.view","platform.system_errors.view"]'::jsonb
      when pu.role = 'PLATFORM_AUDITOR' then '["platform.dashboard.view","platform.audit.view","platform.system_errors.view"]'::jsonb
      else '[]'::jsonb
    end,
    'onboardingCompleted', p.onboarding_completed_at is not null,
    'tenantMemberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tenantUserId', tu.id,
        'tenantId', t.id,
        'tenantCode', t.code,
        'tenantName', t.name,
        'tenantSlug', t.slug,
        'tenantStatus', t.status,
        'membershipStatus', tu.status,
        'isOwner', tu.is_owner,
        'roles', coalesce((select jsonb_agg(r.code order by r.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id where tur.tenant_user_id = tu.id and r.code not like 'platform.%'), '[]'::jsonb),
        'permissions', coalesce((select jsonb_agg(distinct perm.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id join public.role_permissions rp on rp.role_id = r.id join public.permissions perm on perm.id = rp.permission_id where tur.tenant_user_id = tu.id and perm.code not like 'platform.%'), '[]'::jsonb),
        'subscription', public.subscription_context_json(t.id),
        'accessibleEvents', public.event_summary_json(t.id)
      ) order by t.created_at)
      from public.tenant_users tu
      join public.tenants t on t.id = tu.tenant_id
      where tu.user_id = auth.uid() and tu.status <> 'REMOVED'
    ), '[]'::jsonb),
    'pendingInvitations', public.rpc_list_my_tenant_invitations()
  )
  from public.profiles p
  left join public.platform_users pu on pu.user_id = p.id
  cross join platform_permissions
  where p.id = auth.uid();
$$;

grant execute on function public.rpc_list_my_tenant_invitations() to authenticated;
grant execute on function public.rpc_accept_tenant_invitation(uuid) to authenticated;
grant execute on function public.rpc_decline_tenant_invitation(uuid) to authenticated;
grant execute on function public.rpc_accept_my_tenant_invitations() to authenticated;
grant execute on function public.rpc_get_my_context() to authenticated;

notify pgrst, 'reload schema';
