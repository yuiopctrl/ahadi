create or replace function public.rpc_get_my_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with platform_permissions as (
    select array[
      'platform.dashboard.view',
      'platform.tenants.view',
      'platform.tenants.manage',
      'platform.plans.view',
      'platform.plans.manage',
      'platform.subscriptions.manage',
      'platform.sms.view',
      'platform.audit.view',
      'platform.settings.manage'
    ]::text[] as owner_permissions
  )
  select jsonb_build_object(
    'profile', to_jsonb(p),
    'isPlatformUser', pu.id is not null and pu.status = 'ACTIVE',
    'platformRole', case when pu.status = 'ACTIVE' then pu.role else null end,
    'platformStatus', pu.status,
    'platformPermissions', case
      when pu.status <> 'ACTIVE' or pu.id is null then '[]'::jsonb
      when pu.role = 'PLATFORM_OWNER' then to_jsonb(platform_permissions.owner_permissions)
      when pu.role = 'PLATFORM_ADMIN' then '["platform.dashboard.view","platform.tenants.view","platform.tenants.manage","platform.plans.view","platform.plans.manage","platform.subscriptions.manage","platform.sms.view"]'::jsonb
      when pu.role = 'PLATFORM_SUPPORT' then '["platform.dashboard.view","platform.tenants.view","platform.sms.view"]'::jsonb
      when pu.role = 'PLATFORM_AUDITOR' then '["platform.dashboard.view","platform.audit.view"]'::jsonb
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
  left join public.platform_users pu on pu.user_id = p.id
  cross join platform_permissions
  where p.id = auth.uid();
$$;

comment on function public.rpc_get_my_context() is
'Returns tenant and platform context independently. Platform ownership must be bootstrapped manually in public.platform_users after the intended administrator authenticates.';
