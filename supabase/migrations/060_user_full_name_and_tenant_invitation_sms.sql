create or replace function public.sms_template_allowed_variables(p_code text)
returns jsonb
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_code, '')))
    when 'PLEDGE_REQUEST' then '["member_name","event_name","event_date","pledge_deadline"]'::jsonb
    when 'PLEDGE_REGISTRATION' then '["member_name","pledge_amount","event_name","due_date"]'::jsonb
    when 'PAYMENT_CONFIRMATION' then '["member_name","payment_amount","payment_method","event_name","balance","receipt_number"]'::jsonb
    when 'BALANCE_REMINDER' then '["member_name","event_name","balance","due_date"]'::jsonb
    when 'PLEDGE_COMPLETED' then '["member_name","pledge_amount","event_name"]'::jsonb
    when 'TENANT_INVITATION' then '["tenant_name","invitee_name","role"]'::jsonb
    else '[]'::jsonb
  end;
$$;

insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active, allowed_variables)
values (
  null,
  'TENANT_INVITATION',
  'Tenant Invitation',
  'SMS',
  'Umealikwa kutumia Ahadi kwa {{tenant_name}}. Fungua Ahadi na uthibitishe namba yako.',
  'sw',
  true,
  true,
  public.sms_template_allowed_variables('TENANT_INVITATION')
)
on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language)
do update set
  name = excluded.name,
  body = excluded.body,
  allowed_variables = excluded.allowed_variables,
  is_system = true,
  is_active = true,
  updated_at = now()
where sms_templates.tenant_id is null;

update public.sms_templates
set allowed_variables = public.sms_template_allowed_variables(code)
where code in ('PLEDGE_REQUEST', 'PLEDGE_REGISTRATION', 'PAYMENT_CONFIRMATION', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED', 'TENANT_INVITATION');

create or replace function public.rpc_upsert_sms_template(p_tenant_id uuid, p_code text, p_body text, p_language text default 'sw')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  normalized_body text := btrim(coalesce(p_body, ''));
  display_name text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if normalized_body = '' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  display_name := case normalized_code
    when 'PLEDGE_REQUEST' then 'Pledge Request'
    when 'PLEDGE_REGISTRATION' then 'Pledge Registration'
    when 'PAYMENT_CONFIRMATION' then 'Payment Confirmation'
    when 'BALANCE_REMINDER' then 'Balance Reminder'
    when 'PLEDGE_COMPLETED' then 'Pledge Completed'
    when 'TENANT_INVITATION' then 'Tenant Invitation'
    else null
  end;
  if display_name is null then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active, allowed_variables)
  values (p_tenant_id, normalized_code, display_name, 'SMS', normalized_body, coalesce(nullif(p_language, ''), 'sw'), false, true, public.sms_template_allowed_variables(normalized_code))
  on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language)
  do update set body = excluded.body, name = excluded.name, is_active = true, allowed_variables = excluded.allowed_variables, updated_at = now();
  return public.sms_template_detail(p_tenant_id, normalized_code, coalesce(nullif(p_language, ''), 'sw'));
end;
$$;

create or replace function public.rpc_enqueue_tenant_invitation_sms(
  p_tenant_id uuid,
  p_phone_e164 text,
  p_full_name text,
  p_role_code text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_record public.tenants%rowtype;
  provider_settings record;
  template_body text;
  message text;
  idempotency text := coalesce(nullif(btrim(p_idempotency_key), ''), 'TENANT_INVITATION:' || p_tenant_id::text || ':' || p_phone_e164);
  outbox_id uuid;
  allowance jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.invite') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_phone_e164 is null or p_phone_e164 !~ '^\+255[67][0-9]{8}$' then
    return jsonb_build_object('smsQueued', false, 'reason', 'INVALID_PHONE', 'template', 'TENANT_INVITATION');
  end if;
  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED', 'template', 'TENANT_INVITATION');
  end if;

  select * into tenant_record
  from public.tenants
  where id = p_tenant_id
  limit 1;
  if not found then
    raise exception 'TENANT_NOT_FOUND' using errcode = '22023';
  end if;

  select id into outbox_id
  from public.sms_outbox
  where idempotency_key = idempotency
    and status <> 'CANCELLED'
  limit 1;
  if found then
    return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', 'TENANT_INVITATION');
  end if;

  template_body := public.resolve_sms_template_body(p_tenant_id, 'TENANT_INVITATION', 'sw');
  if template_body is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'TEMPLATE_NOT_FOUND', 'template', 'TENANT_INVITATION');
  end if;

  message := public.render_sms_template(template_body, jsonb_build_object(
    'tenant_name', tenant_record.name,
    'invitee_name', coalesce(nullif(btrim(p_full_name), ''), 'Ndugu'),
    'role', coalesce(nullif(btrim(p_role_code), ''), 'mtumiaji')
  ));

  if public.sms_character_count(message) > public.sms_max_characters() then
    message := 'Umealikwa kutumia Ahadi. Fungua Ahadi na uthibitishe namba yako ili kujiunga na kikundi.';
  end if;
  if public.sms_character_count(message) > public.sms_max_characters() then
    return jsonb_build_object('smsQueued', false, 'reason', 'SMS_CHARACTER_LIMIT_EXCEEDED', 'template', 'TENANT_INVITATION');
  end if;

  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if coalesce(nullif(allowance ->> 'allowed', '')::integer, 1) < 1 then
    return jsonb_build_object('smsQueued', false, 'reason', 'SMS_LIMIT_REACHED', 'template', 'TENANT_INVITATION', 'allowance', allowance);
  end if;

  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);

  insert into public.sms_outbox (tenant_id, template_code, phone_e164, message_body, status, idempotency_key, sender_id, provider)
  values (p_tenant_id, 'TENANT_INVITATION', p_phone_e164, message, 'QUEUED', idempotency, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;

  return jsonb_build_object(
    'smsQueued', true,
    'outboxId', outbox_id,
    'template', 'TENANT_INVITATION',
    'provider', provider_settings.provider_code,
    'senderId', provider_settings.sender_id
  );
exception when unique_violation then
  select id into outbox_id
  from public.sms_outbox
  where idempotency_key = idempotency
    and status <> 'CANCELLED'
  limit 1;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', 'TENANT_INVITATION');
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
  notification jsonb := jsonb_build_object('smsQueued', false, 'reason', 'NOT_ATTEMPTED', 'template', 'TENANT_INVITATION');
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

    notification := public.rpc_enqueue_tenant_invitation_sms(
      p_tenant_id,
      existing_profile.phone_e164,
      existing_profile.full_name,
      p_role_code,
      'TENANT_INVITATION:USER:' || tenant_user_id::text
    );

    perform public.write_audit_log(p_tenant_id, 'user.invited', 'tenant_user', tenant_user_id, null, null, jsonb_build_object('targetUserId', existing_profile.id, 'role', p_role_code, 'existingUser', true, 'notification', notification));
    return jsonb_build_object('kind', 'USER', 'tenantUserId', tenant_user_id, 'status', 'ACTIVE', 'smsQueued', coalesce((notification ->> 'smsQueued')::boolean, false), 'notification', notification);
  end if;

  select * into invitation_record
  from public.tenant_invitations
  where tenant_id = p_tenant_id
    and phone_e164 = p_phone_e164
    and status = 'INVITED'
  limit 1;

  if found then
    notification := jsonb_build_object('smsQueued', false, 'reason', 'ALREADY_PENDING', 'template', 'TENANT_INVITATION');
    return jsonb_build_object('kind', 'INVITATION', 'invitationId', invitation_record.id, 'status', 'INVITED', 'alreadyPending', true, 'smsQueued', false, 'notification', notification);
  end if;

  insert into public.tenant_invitations (tenant_id, phone_e164, full_name, email, role_code, invited_by)
  values (p_tenant_id, p_phone_e164, coalesce(nullif(btrim(p_full_name), ''), ''), nullif(btrim(coalesce(p_email, '')), ''), p_role_code, actor)
  returning * into invitation_record;

  notification := public.rpc_enqueue_tenant_invitation_sms(
    p_tenant_id,
    invitation_record.phone_e164,
    invitation_record.full_name,
    invitation_record.role_code,
    'TENANT_INVITATION:INVITATION:' || invitation_record.id::text
  );

  if coalesce((notification ->> 'smsQueued')::boolean, false) then
    update public.tenant_invitations
    set last_sent_at = now()
    where id = invitation_record.id;
  end if;

  perform public.write_audit_log(p_tenant_id, 'user.invited', 'tenant_invitation', invitation_record.id, null, null, jsonb_build_object('phone', p_phone_e164, 'role', p_role_code, 'existingUser', false, 'notification', notification));
  return jsonb_build_object('kind', 'INVITATION', 'invitationId', invitation_record.id, 'status', 'INVITED', 'alreadyPending', false, 'smsQueued', coalesce((notification ->> 'smsQueued')::boolean, false), 'notification', notification);
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
  notification jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'users.invite') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into invitation_record
  from public.tenant_invitations
  where id = p_invitation_id
    and tenant_id = p_tenant_id
    and status = 'INVITED'
  for update;

  if not found then
    raise exception 'INVITATION_INVALID' using errcode = '22023';
  end if;

  notification := public.rpc_enqueue_tenant_invitation_sms(
    p_tenant_id,
    invitation_record.phone_e164,
    invitation_record.full_name,
    invitation_record.role_code,
    'TENANT_INVITATION:RESEND:' || invitation_record.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MI')
  );

  if coalesce((notification ->> 'smsQueued')::boolean, false) then
    update public.tenant_invitations
    set last_sent_at = now()
    where id = p_invitation_id;
  end if;

  perform public.write_audit_log(p_tenant_id, 'invitation.resent', 'tenant_invitation', p_invitation_id, null, null, jsonb_build_object('phone', invitation_record.phone_e164, 'role', invitation_record.role_code, 'notification', notification));
  return jsonb_build_object('ok', true, 'smsQueued', coalesce((notification ->> 'smsQueued')::boolean, false), 'notification', notification);
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
  profile_name_backfilled boolean := false;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into profile_record from public.profiles where id = caller and status = 'ACTIVE';
  if not found then
    return jsonb_build_object('accepted', 0, 'profileNameBackfilled', false);
  end if;

  for invitation_record in
    select * from public.tenant_invitations
    where phone_e164 = profile_record.phone_e164
      and status = 'INVITED'
    for update
  loop
    if btrim(coalesce(profile_record.full_name, '')) = '' and btrim(coalesce(invitation_record.full_name, '')) <> '' then
      update public.profiles
      set full_name = btrim(invitation_record.full_name),
          updated_at = now()
      where id = caller
        and btrim(coalesce(full_name, '')) = '';
      profile_record.full_name := btrim(invitation_record.full_name);
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
    set status = 'ACCEPTED', accepted_by = caller, accepted_at = now()
    where id = invitation_record.id;

    perform public.write_audit_log(invitation_record.tenant_id, 'invitation.accepted', 'tenant_user', tenant_user_id, null, jsonb_build_object('invitationId', invitation_record.id), jsonb_build_object('targetUserId', caller, 'role', invitation_record.role_code, 'profileNameBackfilled', profile_name_backfilled));
    accepted_count := accepted_count + 1;
  end loop;

  return jsonb_build_object('accepted', accepted_count, 'profileNameBackfilled', profile_name_backfilled);
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
    ), '[]'::jsonb)
  )
  from public.profiles p
  left join public.platform_users pu on pu.user_id = p.id
  cross join platform_permissions
  where p.id = auth.uid();
$$;

do $$
declare
  backfilled_count integer;
begin
  with invitation_names as (
    select
      phone_e164,
      min(btrim(full_name)) as full_name,
      count(distinct btrim(full_name)) as name_count
    from public.tenant_invitations
    where btrim(coalesce(full_name, '')) <> ''
    group by phone_e164
  ),
  updated as (
    update public.profiles p
    set full_name = invitation_names.full_name,
        updated_at = now()
    from invitation_names
    where p.phone_e164 = invitation_names.phone_e164
      and btrim(coalesce(p.full_name, '')) = ''
      and invitation_names.name_count = 1
    returning p.id
  )
  select count(*) into backfilled_count from updated;

  raise notice 'profiles.full_name backfilled from deterministic tenant invitations: %', backfilled_count;
end;
$$;

revoke all on function public.rpc_enqueue_tenant_invitation_sms(uuid, text, text, text, text) from public;
grant execute on function public.rpc_enqueue_tenant_invitation_sms(uuid, text, text, text, text) to authenticated;
grant execute on function public.rpc_upsert_sms_template(uuid, text, text, text) to authenticated;
grant execute on function public.rpc_invite_tenant_user(uuid, text, text, text, text) to authenticated;
grant execute on function public.rpc_resend_tenant_invitation(uuid, uuid) to authenticated;
grant execute on function public.rpc_accept_my_tenant_invitations() to authenticated;
grant execute on function public.rpc_get_my_context() to authenticated;

notify pgrst, 'reload schema';
