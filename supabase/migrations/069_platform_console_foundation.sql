-- Batch 8: Changisha Platform Console foundation.
--
-- Adds the backend capabilities the new Flutter platform admin app needs
-- that don't already exist:
--   - platform staff management (list/add/change role/change status),
--     with final-PLATFORM_OWNER protection enforced here so it can never
--     be bypassed by a future caller
--   - subscription plan create/update (previously view-only despite
--     platform.plans.manage already existing and being RLS-wired)
--   - organization (tenant) status change (ACTIVE/SUSPENDED)
--   - subscription admin actions: change plan, change status
--   - a platform audit log listing RPC (audit_logs already stores both
--     tenant and platform-only rows; this just exposes a filtered,
--     paginated view of it)
--   - a real platform system health RPC (SMS queue depth/failures,
--     recent frontend errors, open support requests -- no fabricated
--     subsystems)
--
-- Everything follows the exact pattern already established in migration
-- 030 (has_platform_permission() checked inside the function body as a
-- second line of defense beyond the Express-side requirePlatformPermission
-- middleware, write_audit_log() called for every mutation).
--
-- Deliberately NOT built here: real "controlled support access" elevation.
-- public.support_access_sessions (030) only ever inserts a row and writes
-- an audit log -- nothing anywhere consumes scope/expires_at/status to
-- actually grant elevated tenant access, and there is no revoke path.
-- Building that safely is a separate, security-critical piece of work;
-- shipping a fake "impersonation" UI on top of a session record nobody
-- enforces would be worse than not having the feature, so the Flutter
-- console surfaces existing/started sessions read-only and leaves any
-- "act as this organization" affordance out entirely.

-- ---------------------------------------------------------------------
-- Part 1: new platform permissions
-- ---------------------------------------------------------------------
-- platform.users.manage is intentionally NOT added to any role's explicit
-- list below (PLATFORM_ADMIN/PLATFORM_SUPPORT/PLATFORM_AUDITOR) -- granting
-- or revoking platform staff access is a privilege-escalation-sensitive
-- action, so only PLATFORM_OWNER (which bypasses the explicit list via the
-- `permission_code like 'platform.%'` owner rule already in
-- has_platform_permission) can call the manage RPCs below. View access is
-- fine for admins/auditors.

insert into public.permissions (code, name, description) values
('platform.users.view', 'View platform users', 'View Changisha platform staff accounts and roles'),
('platform.users.manage', 'Manage platform users', 'Add platform staff, change their role, or suspend/reactivate them')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

create or replace function public.has_platform_permission(permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.platform_users pu
    where pu.user_id = auth.uid()
      and pu.status = 'ACTIVE'
      and (
        pu.role = 'PLATFORM_OWNER'
        or (pu.role = 'PLATFORM_ADMIN' and permission_code in (
          'platform.dashboard.view','platform.tenants.view','platform.tenants.manage','platform.plans.view','platform.plans.manage','platform.subscriptions.manage','platform.sms.view',
          'platform.beta.view','platform.beta.manage','platform.support.view','platform.support.manage','platform.feedback.view','platform.features.view','platform.features.manage',
          'platform.system_errors.view','platform.support_session.start','platform.users.view','platform.audit.view'
        ))
        or (pu.role = 'PLATFORM_SUPPORT' and permission_code in ('platform.dashboard.view','platform.tenants.view','platform.sms.view','platform.support.view','platform.support.manage','platform.feedback.view','platform.system_errors.view','platform.support_session.start'))
        or (pu.role = 'PLATFORM_AUDITOR' and permission_code in ('platform.dashboard.view','platform.audit.view','platform.system_errors.view','platform.users.view','platform.tenants.view','platform.plans.view'))
      )
  );
$$;

-- ---------------------------------------------------------------------
-- Part 2: platform staff management (final-owner protection lives here)
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_platform_users()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if not public.has_platform_permission('platform.users.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      pu.id as platform_user_id,
      pu.user_id,
      pu.role,
      pu.status,
      pu.created_at,
      pu.updated_at,
      p.full_name,
      p.phone_e164,
      p.email,
      p.last_seen_at
    from public.platform_users pu
    join public.profiles p on p.id = pu.user_id
  ) row_data;

  return result;
end;
$$;

grant execute on function public.rpc_list_platform_users() to authenticated;

create or replace function public.rpc_add_platform_user(p_phone_e164 text, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_profile public.profiles%rowtype;
  v_existing public.platform_users%rowtype;
  v_result public.platform_users%rowtype;
begin
  if not public.has_platform_permission('platform.users.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_role not in ('PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR') then
    raise exception 'INVALID_PLATFORM_ROLE' using errcode = '22023';
  end if;

  select * into v_profile from public.profiles where phone_e164 = p_phone_e164;
  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = '22023';
  end if;

  select * into v_existing from public.platform_users where user_id = v_profile.id;

  if found then
    update public.platform_users
    set role = p_role, status = 'ACTIVE', updated_at = now()
    where id = v_existing.id
    returning * into v_result;
    perform public.write_audit_log(null, 'PLATFORM_USER_REACTIVATED', 'platform_user', v_result.id, null,
      to_jsonb(v_existing), to_jsonb(v_result), null);
  else
    insert into public.platform_users (user_id, role, status, created_by)
    values (v_profile.id, p_role, 'ACTIVE', auth.uid())
    returning * into v_result;
    perform public.write_audit_log(null, 'PLATFORM_USER_ADDED', 'platform_user', v_result.id, null,
      null, to_jsonb(v_result), null);
  end if;

  return to_jsonb(v_result) || jsonb_build_object('fullName', v_profile.full_name, 'phoneE164', v_profile.phone_e164);
end;
$$;

grant execute on function public.rpc_add_platform_user(text, text) to authenticated;

create or replace function public.rpc_set_platform_user_role(p_platform_user_id uuid, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.platform_users%rowtype;
  v_after public.platform_users%rowtype;
  v_other_active_owners integer;
begin
  if not public.has_platform_permission('platform.users.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_role not in ('PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR') then
    raise exception 'INVALID_PLATFORM_ROLE' using errcode = '22023';
  end if;

  select * into v_before from public.platform_users where id = p_platform_user_id;
  if not found then
    raise exception 'PLATFORM_USER_NOT_FOUND' using errcode = '22023';
  end if;

  if v_before.role = 'PLATFORM_OWNER' and v_before.status = 'ACTIVE' and p_role <> 'PLATFORM_OWNER' then
    select count(*) into v_other_active_owners
    from public.platform_users
    where role = 'PLATFORM_OWNER' and status = 'ACTIVE' and id <> p_platform_user_id;
    if v_other_active_owners = 0 then
      raise exception 'CANNOT_REMOVE_LAST_PLATFORM_OWNER' using errcode = '22023';
    end if;
  end if;

  update public.platform_users
  set role = p_role, updated_at = now()
  where id = p_platform_user_id
  returning * into v_after;

  perform public.write_audit_log(null, 'PLATFORM_USER_ROLE_CHANGED', 'platform_user', v_after.id, null,
    to_jsonb(v_before), to_jsonb(v_after), null);

  return to_jsonb(v_after);
end;
$$;

grant execute on function public.rpc_set_platform_user_role(uuid, text) to authenticated;

create or replace function public.rpc_set_platform_user_status(p_platform_user_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.platform_users%rowtype;
  v_after public.platform_users%rowtype;
  v_other_active_owners integer;
begin
  if not public.has_platform_permission('platform.users.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_status not in ('ACTIVE', 'SUSPENDED', 'DISABLED') then
    raise exception 'INVALID_PLATFORM_USER_STATUS' using errcode = '22023';
  end if;

  select * into v_before from public.platform_users where id = p_platform_user_id;
  if not found then
    raise exception 'PLATFORM_USER_NOT_FOUND' using errcode = '22023';
  end if;

  if v_before.role = 'PLATFORM_OWNER' and v_before.status = 'ACTIVE' and p_status <> 'ACTIVE' then
    select count(*) into v_other_active_owners
    from public.platform_users
    where role = 'PLATFORM_OWNER' and status = 'ACTIVE' and id <> p_platform_user_id;
    if v_other_active_owners = 0 then
      raise exception 'CANNOT_REMOVE_LAST_PLATFORM_OWNER' using errcode = '22023';
    end if;
  end if;

  update public.platform_users
  set status = p_status, updated_at = now()
  where id = p_platform_user_id
  returning * into v_after;

  perform public.write_audit_log(null, 'PLATFORM_USER_STATUS_CHANGED', 'platform_user', v_after.id, null,
    to_jsonb(v_before), to_jsonb(v_after), p_reason);

  return to_jsonb(v_after);
end;
$$;

grant execute on function public.rpc_set_platform_user_status(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Part 3: subscription plan create/update
-- ---------------------------------------------------------------------

create or replace function public.rpc_create_platform_plan(
  p_code text, p_name text, p_description text, p_currency text, p_price_amount numeric,
  p_billing_interval text, p_trial_days integer, p_max_active_events integer, p_max_members integer,
  p_max_users integer, p_included_sms integer, p_features jsonb, p_is_public boolean, p_is_active boolean,
  p_display_order integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_plan public.subscription_plans%rowtype;
begin
  if not public.has_platform_permission('platform.plans.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  insert into public.subscription_plans (
    code, name, description, currency, price_amount, billing_interval, trial_days,
    max_active_events, max_members, max_users, included_sms, features, is_public, is_active, display_order
  ) values (
    upper(p_code), p_name, p_description, upper(p_currency), p_price_amount, p_billing_interval, p_trial_days,
    p_max_active_events, p_max_members, p_max_users, p_included_sms, coalesce(p_features, '{}'::jsonb), p_is_public, p_is_active, p_display_order
  )
  returning * into v_plan;

  perform public.write_audit_log(null, 'PLATFORM_PLAN_CREATED', 'subscription_plan', v_plan.id, null, null, to_jsonb(v_plan), null);

  return to_jsonb(v_plan);
exception when unique_violation then
  raise exception 'PLAN_CODE_ALREADY_EXISTS' using errcode = '23505';
end;
$$;

grant execute on function public.rpc_create_platform_plan(text, text, text, text, numeric, text, integer, integer, integer, integer, integer, jsonb, boolean, boolean, integer) to authenticated;

create or replace function public.rpc_update_platform_plan(
  p_plan_id uuid, p_name text, p_description text, p_currency text, p_price_amount numeric,
  p_billing_interval text, p_trial_days integer, p_max_active_events integer, p_max_members integer,
  p_max_users integer, p_included_sms integer, p_features jsonb, p_is_public boolean, p_is_active boolean,
  p_display_order integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.subscription_plans%rowtype;
  v_after public.subscription_plans%rowtype;
begin
  if not public.has_platform_permission('platform.plans.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into v_before from public.subscription_plans where id = p_plan_id;
  if not found then
    raise exception 'PLAN_NOT_FOUND' using errcode = '22023';
  end if;

  update public.subscription_plans set
    name = p_name,
    description = p_description,
    currency = upper(p_currency),
    price_amount = p_price_amount,
    billing_interval = p_billing_interval,
    trial_days = p_trial_days,
    max_active_events = p_max_active_events,
    max_members = p_max_members,
    max_users = p_max_users,
    included_sms = p_included_sms,
    features = coalesce(p_features, '{}'::jsonb),
    is_public = p_is_public,
    is_active = p_is_active,
    display_order = p_display_order,
    updated_at = now()
  where id = p_plan_id
  returning * into v_after;

  perform public.write_audit_log(null, 'PLATFORM_PLAN_UPDATED', 'subscription_plan', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after), null);

  return to_jsonb(v_after);
end;
$$;

grant execute on function public.rpc_update_platform_plan(uuid, text, text, text, numeric, text, integer, integer, integer, integer, integer, jsonb, boolean, boolean, integer) to authenticated;

-- ---------------------------------------------------------------------
-- Part 4: organization (tenant) status management
-- ---------------------------------------------------------------------

create or replace function public.rpc_set_tenant_status(p_tenant_id uuid, p_status text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.tenants%rowtype;
  v_after public.tenants%rowtype;
begin
  if not public.has_platform_permission('platform.tenants.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_status not in ('ACTIVE', 'SUSPENDED') then
    raise exception 'INVALID_TENANT_STATUS' using errcode = '22023';
  end if;
  if p_status = 'SUSPENDED' and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into v_before from public.tenants where id = p_tenant_id;
  if not found then
    raise exception 'TENANT_NOT_FOUND' using errcode = '22023';
  end if;

  update public.tenants set
    status = p_status,
    suspended_at = case when p_status = 'SUSPENDED' then now() else null end,
    suspension_reason = case when p_status = 'SUSPENDED' then p_reason else null end,
    updated_at = now()
  where id = p_tenant_id
  returning * into v_after;

  perform public.write_audit_log(p_tenant_id, 'TENANT_STATUS_CHANGED', 'tenant', p_tenant_id, null,
    jsonb_build_object('status', v_before.status), jsonb_build_object('status', v_after.status), p_reason);

  return to_jsonb(v_after);
end;
$$;

grant execute on function public.rpc_set_tenant_status(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Part 5: subscription admin actions
-- ---------------------------------------------------------------------

create or replace function public.rpc_change_tenant_subscription_plan(p_tenant_id uuid, p_plan_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_before public.tenant_subscriptions%rowtype;
  v_after public.tenant_subscriptions%rowtype;
begin
  if not public.has_platform_permission('platform.subscriptions.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into v_plan from public.subscription_plans where id = p_plan_id;
  if not found then
    raise exception 'PLAN_NOT_FOUND' using errcode = '22023';
  end if;

  select * into v_before
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id and status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
  order by created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = '22023';
  end if;

  update public.tenant_subscriptions
  set plan_id = p_plan_id, plan_snapshot = to_jsonb(v_plan), updated_at = now()
  where id = v_before.id
  returning * into v_after;

  perform public.write_audit_log(p_tenant_id, 'TENANT_SUBSCRIPTION_PLAN_CHANGED', 'tenant_subscription', v_after.id, null,
    jsonb_build_object('planId', v_before.plan_id), jsonb_build_object('planId', v_after.plan_id, 'planCode', v_plan.code), p_reason);

  return to_jsonb(v_after);
end;
$$;

grant execute on function public.rpc_change_tenant_subscription_plan(uuid, uuid, text) to authenticated;

create or replace function public.rpc_set_tenant_subscription_status(p_tenant_id uuid, p_status text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.tenant_subscriptions%rowtype;
  v_after public.tenant_subscriptions%rowtype;
begin
  if not public.has_platform_permission('platform.subscriptions.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_status not in ('ACTIVE', 'SUSPENDED', 'CANCELLED', 'TRIAL') then
    raise exception 'INVALID_SUBSCRIPTION_STATUS' using errcode = '22023';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into v_before
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id
  order by created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = '22023';
  end if;

  update public.tenant_subscriptions set
    status = p_status,
    cancelled_at = case when p_status = 'CANCELLED' then now() else null end,
    cancellation_reason = case when p_status = 'CANCELLED' then p_reason else null end,
    updated_at = now()
  where id = v_before.id
  returning * into v_after;

  -- This is a platform-recorded manual override, never a payment
  -- confirmation -- the audit log (with p_reason) is the durable record
  -- that this ACTIVE/TRIAL status was set by an admin, not a gateway.
  perform public.write_audit_log(p_tenant_id, 'TENANT_SUBSCRIPTION_STATUS_CHANGED', 'tenant_subscription', v_after.id, null,
    jsonb_build_object('status', v_before.status), jsonb_build_object('status', v_after.status), p_reason);

  return to_jsonb(v_after);
end;
$$;

grant execute on function public.rpc_set_tenant_subscription_status(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Part 6: platform audit log listing
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_platform_audit_log(
  p_action text default null,
  p_tenant_id uuid default null,
  p_entity_type text default null,
  p_actor_user_id uuid default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_before_id bigint default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_items jsonb;
  v_next_cursor bigint;
begin
  if not public.has_platform_permission('platform.audit.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.id desc), '[]'::jsonb), min(row_data.id)
  into v_items, v_next_cursor
  from (
    select
      al.id, al.tenant_id, t.name as tenant_name, al.actor_user_id, actor_profile.full_name as actor_name,
      al.actor_platform_user_id, al.action, al.entity_type, al.entity_id, al.event_id,
      al.old_values, al.new_values, al.reason, al.created_at
    from public.audit_logs al
    left join public.tenants t on t.id = al.tenant_id
    left join public.profiles actor_profile on actor_profile.id = al.actor_user_id
    where (p_action is null or al.action = p_action)
      and (p_tenant_id is null or al.tenant_id = p_tenant_id)
      and (p_entity_type is null or al.entity_type = p_entity_type)
      and (p_actor_user_id is null or al.actor_user_id = p_actor_user_id)
      and (p_date_from is null or al.created_at >= p_date_from)
      and (p_date_to is null or al.created_at <= p_date_to)
      and (p_before_id is null or al.id < p_before_id)
    order by al.id desc
    limit v_limit
  ) row_data;

  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when jsonb_array_length(v_items) = v_limit then v_next_cursor else null end
  );
end;
$$;

grant execute on function public.rpc_list_platform_audit_log(text, uuid, text, uuid, timestamptz, timestamptz, bigint, integer) to authenticated;

-- ---------------------------------------------------------------------
-- Part 7: platform system health
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_platform_system_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_sms_pending integer;
  v_sms_failed_24h integer;
  v_sms_sent_today integer;
  v_recent_errors integer;
  v_open_support integer;
begin
  if not public.has_platform_permission('platform.system_errors.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select count(*)::integer into v_sms_pending from public.sms_outbox where status = 'QUEUED';
  select count(*)::integer into v_sms_failed_24h from public.sms_outbox where status = 'FAILED' and updated_at >= now() - interval '24 hours';
  select count(*)::integer into v_sms_sent_today from public.sms_outbox where status in ('SENT', 'DELIVERED') and created_at >= date_trunc('day', now());
  select count(*)::integer into v_recent_errors from public.frontend_error_reports where created_at >= now() - interval '24 hours';
  select count(*)::integer into v_open_support from public.support_requests where status in ('OPEN', 'IN_PROGRESS', 'WAITING_CUSTOMER');

  return jsonb_build_object(
    'api', jsonb_build_object('status', 'HEALTHY'),
    'database', jsonb_build_object('status', 'HEALTHY'),
    'smsQueue', jsonb_build_object('pending', v_sms_pending, 'failedLast24h', v_sms_failed_24h, 'sentToday', v_sms_sent_today,
      'status', case when v_sms_failed_24h > 0 then 'WARNING' else 'HEALTHY' end),
    'recentErrors24h', v_recent_errors,
    'openSupportRequests', v_open_support,
    'generatedAt', now()
  );
end;
$$;

grant execute on function public.rpc_get_platform_system_health() to authenticated;

-- ---------------------------------------------------------------------
-- Part 8: extend the existing tenant list with billing fields the new
-- Subscriptions screen needs (billing interval/price/period dates).
-- Purely additive JSON keys -- safe for the existing React platform
-- client, which only reads the fields it already knows about.
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_platform_tenants()
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
  if not public.has_platform_permission('platform.tenants.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      t.id, t.code, t.name, t.phone_e164, t.email, t.status, t.lifecycle_tag, t.commercial_status, t.operational_notice, t.created_at,
      sp.id as plan_id, sp.code as plan_code, sp.name as plan_name, sp.billing_interval as plan_billing_interval,
      sp.price_amount as plan_price_amount, sp.currency as plan_currency,
      ts.status as subscription_status, ts.starts_at as subscription_starts_at, ts.trial_ends_at,
      ts.current_period_start, ts.current_period_end,
      greatest(ceil(extract(epoch from (ts.trial_ends_at - now())) / 86400), 0)::integer as trial_days_remaining,
      (select count(*)::integer from public.events e where e.tenant_id = t.id and e.status in ('DRAFT', 'ACTIVE')) as active_event_count,
      (select count(*)::integer from public.members m where m.tenant_id = t.id and m.status = 'ACTIVE') as member_count,
      (select count(*)::integer from public.tenant_users tu where tu.tenant_id = t.id and tu.status = 'ACTIVE') as user_count,
      (select count(*)::integer from public.sms_outbox so where so.tenant_id = t.id and so.status in ('SENT', 'DELIVERED')) as sms_sent_count,
      (select count(*)::integer from public.sms_outbox so where so.tenant_id = t.id and so.status = 'FAILED') as failed_sms_count,
      owner_profile.full_name as owner_name, owner_profile.phone_e164 as owner_phone, owner_profile.email as owner_email,
      public.tenant_health_state(t.id) ->> 'state' as health,
      public.tenant_health_state(t.id) ->> 'warning' as health_warning,
      public.tenant_health_state(t.id) ->> 'lastActivityAt' as last_activity_at
    from public.tenants t
    left join lateral (select * from public.tenant_subscriptions current_ts where current_ts.tenant_id = t.id order by current_ts.created_at desc limit 1) ts on true
    left join public.subscription_plans sp on sp.id = ts.plan_id
    left join lateral (
      select p.*
      from public.tenant_users owner_tu
      join public.profiles p on p.id = owner_tu.user_id
      where owner_tu.tenant_id = t.id and owner_tu.status = 'ACTIVE' and owner_tu.is_owner = true
      order by owner_tu.created_at
      limit 1
    ) owner_profile on true
  ) row_data;

  return result;
end;
$$;

-- ---------------------------------------------------------------------
-- Part 9: extend the existing plan list with the fields the new plan
-- editor needs to prefill an edit form (description/trial_days/features
-- were previously only visible via a direct table read). Additive JSON
-- keys only -- safe for the existing React platform client.
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_platform_plans()
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
  if not public.has_platform_permission('platform.plans.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.display_order, row_data.price_amount), '[]'::jsonb)
  into result
  from (
    select
      id, code, name, description, currency, price_amount, billing_interval, trial_days,
      max_active_events, max_users, max_members, included_sms, features, is_active, is_public, display_order
    from public.subscription_plans
  ) row_data;

  return result;
end;
$$;

-- ---------------------------------------------------------------------
-- Part 10: rpc_get_rollout_settings_public() never exposed
-- default_trial_days, so the Platform Console (and rpc_update_rollout_
-- settings, which returns via this same function) had no way to read
-- back the value it can write. Additive JSON key only.
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_rollout_settings_public()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'registrationMode', registration_mode,
    'betaModeEnabled', beta_mode_enabled,
    'defaultTrialDays', default_trial_days,
    'supportEmail', support_email,
    'supportPhone', support_phone,
    'maintenanceNotice', maintenance_notice,
    'maintenanceMode', maintenance_mode,
    'minimumSupportedWebVersion', minimum_supported_web_version,
    'releaseChannel', release_channel,
    'webVersion', web_version
  )
  from public.platform_settings
  where id = true;
$$;

notify pgrst, 'reload schema';
