create or replace function public.rpc_get_platform_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_platform_permission('platform.dashboard.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'totalTenants', (select count(*) from public.tenants),
    'trialTenants', (select count(*) from public.tenants where status = 'TRIAL'),
    'activeTenants', (select count(*) from public.tenants where status = 'ACTIVE'),
    'suspendedTenants', (select count(*) from public.tenants where status = 'SUSPENDED'),
    'betaTenants', (select count(*) from public.tenants where lifecycle_tag in ('BETA', 'PILOT')),
    'totalEvents', (select count(*) from public.events),
    'subscriptionsExpiringSoon', (select count(*) from public.tenant_subscriptions where status in ('TRIAL', 'ACTIVE') and coalesce(trial_ends_at, current_period_end) is not null and coalesce(trial_ends_at, current_period_end) <= now() + interval '14 days'),
    'openSupportRequests', (select count(*) from public.support_requests where status in ('OPEN', 'IN_PROGRESS', 'WAITING_CUSTOMER')),
    'newFeedbackItems', (select count(*) from public.product_feedback where status = 'NEW'),
    'failedSmsBacklog', (select count(*) from public.sms_outbox where status = 'FAILED'),
    'recentSystemErrors', (select count(*) from public.frontend_error_reports where created_at >= now() - interval '24 hours'),
    'frontendErrors14d', (select count(*) from public.frontend_error_reports where created_at >= now() - interval '14 days')
  );
end;
$$;

create or replace function public.rpc_get_platform_tenant_detail(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
  milestones jsonb;
begin
  if not public.has_platform_permission('platform.tenants.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  milestones := public.tenant_activation_milestones(p_tenant_id);

  select jsonb_build_object(
    'tenant', to_jsonb(t),
    'subscription', case when ts.id is null then null else to_jsonb(ts) || jsonb_build_object('planCode', sp.code, 'planName', sp.name) end,
    'owner', to_jsonb(owner_profile),
    'health', public.tenant_health_state(p_tenant_id),
    'activation', milestones,
    'milestones', milestones,
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'status', e.status, 'eventDate', e.event_date) order by e.created_at desc) from public.events e where e.tenant_id = p_tenant_id), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object('id', tu.id, 'status', tu.status, 'isOwner', tu.is_owner, 'fullName', p.full_name, 'phone', p.phone_e164) order by tu.created_at) from public.tenant_users tu join public.profiles p on p.id = tu.user_id where tu.tenant_id = p_tenant_id), '[]'::jsonb),
    'supportRequests', coalesce((select jsonb_agg(to_jsonb(sr) order by sr.created_at desc) from public.support_requests sr where sr.tenant_id = p_tenant_id), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(row_data order by row_data ->> 'createdAt' desc) from (select jsonb_build_object('action', al.action, 'entityType', al.entity_type, 'reason', al.reason, 'createdAt', al.created_at) as row_data from public.audit_logs al where al.tenant_id = p_tenant_id order by al.created_at desc limit 50) audit_rows), '[]'::jsonb)
  )
  into result
  from public.tenants t
  left join lateral (select * from public.tenant_subscriptions where tenant_id = t.id order by created_at desc limit 1) ts on true
  left join public.subscription_plans sp on sp.id = ts.plan_id
  left join lateral (
    select p.full_name, p.phone_e164, p.email
    from public.tenant_users owner_tu
    join public.profiles p on p.id = owner_tu.user_id
    where owner_tu.tenant_id = t.id and owner_tu.status = 'ACTIVE' and owner_tu.is_owner = true
    order by owner_tu.created_at
    limit 1
  ) owner_profile on true
  where t.id = p_tenant_id;

  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.rpc_get_platform_beta_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  settings jsonb;
  funnel jsonb;
begin
  if not public.has_platform_permission('platform.beta.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  settings := public.rpc_get_rollout_settings_public();
  funnel := coalesce((
    select jsonb_object_agg(event_name, count)
    from (
      select event_name, count(*)::integer
      from public.product_events
      where event_name in ('REGISTRATION_STARTED','OTP_VERIFIED','PIN_CONFIGURED','PACKAGE_SELECTED','ORGANIZATION_COMPLETED','ADMIN_PROFILE_COMPLETED','FIRST_EVENT_COMPLETED','TENANT_CREATED','ONBOARDING_COMPLETED','PAYMENT_RECORDED','REPORT_VIEWED','REPORT_EXPORTED')
        and created_at >= now() - interval '30 days'
      group by event_name
    ) f
  ), '{}'::jsonb);

  return jsonb_build_object(
    'settings', settings,
    'invitations', coalesce((
      select jsonb_agg(row_data order by row_data ->> 'createdAt' desc)
      from (
        select jsonb_build_object(
          'id', id,
          'displayCodeSuffix', display_code_suffix,
          'suffix', display_code_suffix,
          'status', status,
          'intendedName', intended_name,
          'intendedPhone', intended_phone_e164,
          'maxUses', max_uses,
          'useCount', use_count,
          'expiresAt', expires_at,
          'createdAt', created_at
        ) as row_data
        from public.beta_invitations
        order by created_at desc
        limit 100
      ) invite_rows
    ), '[]'::jsonb),
    'recentRegistrations', coalesce((
      select jsonb_agg(row_data order by row_data ->> 'createdAt' desc)
      from (
        select jsonb_build_object(
          'id', t.id,
          'code', t.code,
          'name', t.name,
          'status', t.status,
          'lifecycleTag', t.lifecycle_tag,
          'commercialStatus', t.commercial_status,
          'createdAt', t.created_at,
          'health', public.tenant_health_state(t.id) ->> 'state'
        ) as row_data
        from public.tenants t
        where t.created_at >= now() - interval '30 days'
        order by t.created_at desc
        limit 25
      ) tenant_rows
    ), '[]'::jsonb),
    'onboardingFunnel', funnel,
    'funnel', funnel,
    'health', jsonb_build_object(
      'attentionTenants', (select count(*) from public.tenants t where public.tenant_health_state(t.id) ->> 'state' = 'ATTENTION'),
      'blockedTenants', (select count(*) from public.tenants t where public.tenant_health_state(t.id) ->> 'state' = 'BLOCKED'),
      'failedSmsBacklog', (select count(*) from public.sms_outbox where status = 'FAILED'),
      'openSupportRequests', (select count(*) from public.support_requests where status in ('OPEN','IN_PROGRESS','WAITING_CUSTOMER'))
    ),
    'feedback', coalesce((
      select jsonb_agg(row_data order by row_data ->> 'createdAt' desc)
      from (
        select jsonb_build_object('id', pf.id, 'category', pf.category, 'message', left(pf.message, 180), 'status', pf.status, 'tenantName', t.name, 'createdAt', pf.created_at) as row_data
        from public.product_feedback pf
        left join public.tenants t on t.id = pf.tenant_id
        order by pf.created_at desc
        limit 20
      ) feedback_rows
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.rpc_get_platform_dashboard() to authenticated;
grant execute on function public.rpc_get_platform_tenant_detail(uuid) to authenticated;
grant execute on function public.rpc_get_platform_beta_dashboard() to authenticated;
