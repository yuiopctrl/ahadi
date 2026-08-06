create table public.onboarding_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  request_hash text not null,
  result jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

alter table public.onboarding_requests enable row level security;

create or replace function public.rpc_complete_tenant_onboarding(
  p_plan_code text,
  p_tenant_name text,
  p_tenant_phone text,
  p_tenant_email text default null,
  p_first_event_name text default null,
  p_event_type text default 'OTHER',
  p_event_date date default null,
  p_venue text default null,
  p_target_amount numeric default null,
  p_pledge_deadline date default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  key text := coalesce(nullif(p_idempotency_key, ''), md5(coalesce(p_plan_code, '') || ':' || coalesce(p_tenant_name, '') || ':' || coalesce(p_first_event_name, '')));
  request_hash text := encode(digest(coalesce(p_plan_code, '') || ':' || coalesce(p_tenant_name, '') || ':' || coalesce(p_tenant_phone, '') || ':' || coalesce(p_first_event_name, ''), 'sha256'), 'hex');
  existing public.onboarding_requests%rowtype;
  profile_record public.profiles%rowtype;
  plan_record public.subscription_plans%rowtype;
  role_record public.roles%rowtype;
  tenant_id uuid;
  subscription_id uuid;
  event_id uuid;
  tenant_user_id uuid;
  tenant_code text;
  tenant_slug text;
  event_code text;
  result jsonb;
  normalized_phone text;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(caller::text || ':' || key, 7));

  select * into existing from public.onboarding_requests where user_id = caller and idempotency_key = key for update;
  if found and existing.result is not null then
    return existing.result;
  elsif found and existing.request_hash <> request_hash then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  elsif not found then
    insert into public.onboarding_requests (user_id, idempotency_key, request_hash)
    values (caller, key, request_hash);
  end if;

  select * into profile_record from public.profiles where id = caller for update;
  if not found then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if profile_record.onboarding_completed_at is not null then
    raise exception 'ONBOARDING_ALREADY_COMPLETED' using errcode = '23505';
  end if;

  normalized_phone := public.normalize_tz_phone(p_tenant_phone);

  select * into plan_record
  from public.subscription_plans
  where code = upper(p_plan_code) and is_active and is_public
  for share;
  if not found or plan_record.max_active_events < 1 then
    raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
  end if;

  tenant_code := public.generate_tenant_code();
  tenant_slug := public.generate_unique_tenant_slug(p_tenant_name);

  insert into public.tenants (id, code, slug, name, phone_e164, email, status, created_by)
  values (gen_random_uuid(), tenant_code, tenant_slug, p_tenant_name, normalized_phone, nullif(p_tenant_email, ''), case when plan_record.trial_days > 0 then 'TRIAL' else 'ACTIVE' end, caller)
  returning id into tenant_id;

  insert into public.tenant_settings (tenant_id, receipt_prefix, default_event_type)
  values (tenant_id, replace(tenant_code, '-', ''), p_event_type);

  insert into public.tenant_subscriptions (
    tenant_id,
    plan_id,
    status,
    trial_ends_at,
    current_period_start,
    current_period_end,
    plan_snapshot
  )
  values (
    tenant_id,
    plan_record.id,
    case when plan_record.trial_days > 0 then 'TRIAL' else 'ACTIVE' end,
    case when plan_record.trial_days > 0 then now() + make_interval(days => plan_record.trial_days) else null end,
    now(),
    case when plan_record.billing_interval = 'MONTHLY' then now() + interval '1 month'
         when plan_record.billing_interval = 'QUARTERLY' then now() + interval '3 months'
         when plan_record.billing_interval = 'YEARLY' then now() + interval '1 year'
         else null end,
    jsonb_build_object(
      'code', plan_record.code,
      'name', plan_record.name,
      'currency', plan_record.currency,
      'price_amount', plan_record.price_amount,
      'billing_interval', plan_record.billing_interval,
      'max_active_events', plan_record.max_active_events,
      'max_members', plan_record.max_members,
      'max_users', plan_record.max_users,
      'included_sms', plan_record.included_sms,
      'features', plan_record.features
    )
  )
  returning id into subscription_id;

  insert into public.tenant_users (tenant_id, user_id, status, is_owner, joined_at)
  values (tenant_id, caller, 'ACTIVE', true, now())
  returning id into tenant_user_id;

  select * into role_record from public.roles where code = 'TENANT_OWNER' and tenant_id is null;
  insert into public.tenant_user_roles (tenant_user_id, role_id, assigned_by)
  values (tenant_user_id, role_record.id, caller);

  event_code := public.next_event_code(tenant_id);
  insert into public.events (tenant_id, code, name, event_type, event_date, venue, target_amount, pledge_deadline, status, created_by)
  values (tenant_id, event_code, p_first_event_name, p_event_type, p_event_date, nullif(p_venue, ''), p_target_amount, p_pledge_deadline, 'ACTIVE', caller)
  returning id into event_id;

  insert into public.event_user_assignments (tenant_id, event_id, tenant_user_id, access_level, assigned_by)
  values (tenant_id, event_id, tenant_user_id, 'MANAGE', caller);

  update public.profiles
  set onboarding_completed_at = now(), status = 'ACTIVE'
  where id = caller;

  perform public.write_audit_log(tenant_id, 'tenant.onboarded', 'tenant', tenant_id, null, null, jsonb_build_object('plan_code', plan_record.code));
  perform public.write_audit_log(tenant_id, 'event.created', 'event', event_id, event_id, null, jsonb_build_object('event_code', event_code));

  result := jsonb_build_object(
    'tenant_id', tenant_id,
    'tenant_code', tenant_code,
    'tenant_slug', tenant_slug,
    'subscription_id', subscription_id,
    'event_id', event_id,
    'event_code', event_code
  );

  update public.onboarding_requests set result = result where user_id = caller and idempotency_key = key;
  return result;
end;
$$;

create or replace function public.rpc_get_my_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'profile', to_jsonb(p),
    'isPlatformUser', pu.id is not null and pu.status = 'ACTIVE',
    'platformRole', pu.role,
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
        'roles', coalesce((select jsonb_agg(r.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id where tur.tenant_user_id = tu.id), '[]'::jsonb),
        'permissions', coalesce((select jsonb_agg(distinct perm.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id join public.role_permissions rp on rp.role_id = r.id join public.permissions perm on perm.id = rp.permission_id where tur.tenant_user_id = tu.id), '[]'::jsonb),
        'subscription', (select jsonb_build_object('id', ts.id, 'status', ts.status, 'planCode', sp.code, 'planName', sp.name, 'trialEndsAt', ts.trial_ends_at, 'currentPeriodEnd', ts.current_period_end, 'limits', ts.plan_snapshot) from public.tenant_subscriptions ts join public.subscription_plans sp on sp.id = ts.plan_id where ts.tenant_id = t.id and ts.status in ('TRIAL','ACTIVE','PAST_DUE') order by ts.created_at desc limit 1),
        'accessibleEvents', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'code', e.code, 'name', e.name, 'eventType', e.event_type, 'status', e.status, 'eventDate', e.event_date)) from public.events e where e.tenant_id = t.id and (public.has_tenant_permission(t.id, 'events.view') or public.can_access_event(e.id))), '[]'::jsonb)
      ))
      from public.tenant_users tu
      join public.tenants t on t.id = tu.tenant_id
      where tu.user_id = auth.uid() and tu.status <> 'REMOVED'
    ), '[]'::jsonb)
  )
  from public.profiles p
  left join public.platform_users pu on pu.user_id = p.id and pu.status = 'ACTIVE'
  where p.id = auth.uid();
$$;

create or replace function public.rpc_get_tenant_context(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  allowed boolean;
begin
  allowed := public.is_active_tenant_member(p_tenant_id) or public.has_platform_permission('platform.tenants.view');
  if not allowed then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return (
    select jsonb_build_object(
      'tenant', to_jsonb(t),
      'subscription', (
        select jsonb_build_object('id', ts.id, 'status', ts.status, 'planCode', sp.code, 'planName', sp.name, 'trialEndsAt', ts.trial_ends_at, 'currentPeriodEnd', ts.current_period_end, 'limits', ts.plan_snapshot)
        from public.tenant_subscriptions ts
        join public.subscription_plans sp on sp.id = ts.plan_id
        where ts.tenant_id = t.id
        order by ts.created_at desc
        limit 1
      ),
      'membership', (
        select jsonb_build_object('id', tu.id, 'status', tu.status, 'isOwner', tu.is_owner)
        from public.tenant_users tu
        where tu.tenant_id = t.id and tu.user_id = auth.uid()
        limit 1
      ),
      'roles', coalesce((select jsonb_agg(r.code) from public.tenant_users tu join public.tenant_user_roles tur on tur.tenant_user_id = tu.id join public.roles r on r.id = tur.role_id where tu.tenant_id = t.id and tu.user_id = auth.uid()), '[]'::jsonb),
      'permissions', coalesce((select jsonb_agg(distinct p.code) from public.tenant_users tu join public.tenant_user_roles tur on tur.tenant_user_id = tu.id join public.roles r on r.id = tur.role_id join public.role_permissions rp on rp.role_id = r.id join public.permissions p on p.id = rp.permission_id where tu.tenant_id = t.id and tu.user_id = auth.uid()), '[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'code', e.code, 'name', e.name, 'eventType', e.event_type, 'status', e.status, 'eventDate', e.event_date)) from public.events e where e.tenant_id = t.id and (public.has_tenant_permission(t.id, 'events.view') or public.can_access_event(e.id))), '[]'::jsonb)
    )
    from public.tenants t
    where t.id = p_tenant_id
  );
end;
$$;

create or replace function public.active_event_count(p_tenant_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.events
  where tenant_id = p_tenant_id
    and status in ('DRAFT', 'ACTIVE');
$$;

create or replace function public.active_user_count(p_tenant_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.tenant_users
  where tenant_id = p_tenant_id
    and status in ('INVITED', 'ACTIVE');
$$;

create or replace function public.member_count(p_tenant_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select 0::integer;
$$;

create or replace function public.included_sms_allowance(p_tenant_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((ts.plan_snapshot ->> 'included_sms')::integer, 0)
  from public.tenant_subscriptions ts
  where ts.tenant_id = p_tenant_id and ts.status in ('TRIAL', 'ACTIVE')
  order by ts.created_at desc
  limit 1;
$$;

create or replace function public.rpc_create_event(
  p_tenant_id uuid,
  p_name text,
  p_event_type text,
  p_event_date date default null,
  p_venue text default null,
  p_target_amount numeric default null,
  p_pledge_deadline date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan_limit integer;
  event_code text;
  event_id uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'events.create') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce((ts.plan_snapshot ->> 'max_active_events')::integer, 0)
    into plan_limit
    from public.tenant_subscriptions ts
    where ts.tenant_id = p_tenant_id and ts.status in ('TRIAL', 'ACTIVE')
    order by ts.created_at desc
    limit 1;

  if plan_limit is null or plan_limit <= 0 or public.active_event_count(p_tenant_id) >= plan_limit then
    raise exception 'SUBSCRIPTION_INACTIVE' using errcode = '22023';
  end if;

  event_code := public.next_event_code(p_tenant_id);
  insert into public.events (tenant_id, code, name, event_type, event_date, venue, target_amount, pledge_deadline, status, created_by)
  values (p_tenant_id, event_code, p_name, p_event_type, p_event_date, nullif(p_venue, ''), p_target_amount, p_pledge_deadline, 'ACTIVE', auth.uid())
  returning id into event_id;

  perform public.write_audit_log(p_tenant_id, 'event.created', 'event', event_id, event_id, null, jsonb_build_object('event_code', event_code));

  return jsonb_build_object('event_id', event_id, 'event_code', event_code);
end;
$$;
