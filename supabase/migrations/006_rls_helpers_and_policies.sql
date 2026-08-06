create or replace function public.is_platform_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_users
    where user_id = auth.uid() and status = 'ACTIVE'
  );
$$;

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
        or (pu.role = 'PLATFORM_ADMIN' and permission_code in ('platform.dashboard.view','platform.tenants.view','platform.tenants.manage','platform.plans.view','platform.plans.manage','platform.subscriptions.manage','platform.sms.view'))
        or (pu.role = 'PLATFORM_SUPPORT' and permission_code in ('platform.dashboard.view','platform.tenants.view','platform.sms.view'))
        or (pu.role = 'PLATFORM_AUDITOR' and permission_code in ('platform.dashboard.view','platform.audit.view'))
      )
  );
$$;

create or replace function public.is_tenant_member(tenant_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.tenant_users
    where tenant_id = tenant_uuid and user_id = auth.uid() and status <> 'REMOVED'
  );
$$;

create or replace function public.is_active_tenant_member(tenant_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenant_users tu
    join public.tenants t on t.id = tu.tenant_id
    where tu.tenant_id = tenant_uuid
      and tu.user_id = auth.uid()
      and tu.status = 'ACTIVE'
      and t.status in ('TRIAL','ACTIVE')
  );
$$;

create or replace function public.has_tenant_permission(tenant_uuid uuid, permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenant_users tu
    join public.tenant_user_roles tur on tur.tenant_user_id = tu.id
    join public.roles r on r.id = tur.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where tu.tenant_id = tenant_uuid
      and tu.user_id = auth.uid()
      and tu.status = 'ACTIVE'
      and p.code = permission_code
      and (r.tenant_id is null or r.tenant_id = tenant_uuid)
  );
$$;

create or replace function public.can_access_event(event_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.events e
    where e.id = event_uuid
      and (
        public.has_tenant_permission(e.tenant_id, 'events.view')
        or exists (
          select 1
          from public.event_user_assignments eua
          join public.tenant_users tu on tu.id = eua.tenant_user_id
          where eua.event_id = e.id
            and tu.user_id = auth.uid()
            and tu.status = 'ACTIVE'
        )
      )
  );
$$;

create or replace function public.can_manage_event(event_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.events e
    where e.id = event_uuid
      and (
        public.has_tenant_permission(e.tenant_id, 'events.update')
        or exists (
          select 1
          from public.event_user_assignments eua
          join public.tenant_users tu on tu.id = eua.tenant_user_id
          where eua.event_id = e.id
            and eua.access_level = 'MANAGE'
            and tu.user_id = auth.uid()
            and tu.status = 'ACTIVE'
        )
      )
  );
$$;

alter table public.subscription_plans enable row level security;
alter table public.tenants enable row level security;
alter table public.tenant_settings enable row level security;
alter table public.tenant_subscriptions enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.tenant_users enable row level security;
alter table public.tenant_user_roles enable row level security;
alter table public.platform_users enable row level security;
alter table public.events enable row level security;
alter table public.event_user_assignments enable row level security;
alter table public.audit_logs enable row level security;

create policy subscription_plans_public_select on public.subscription_plans
for select using ((is_active and is_public) or public.has_platform_permission('platform.plans.view'));
create policy subscription_plans_platform_manage on public.subscription_plans
for all using (public.has_platform_permission('platform.plans.manage'))
with check (public.has_platform_permission('platform.plans.manage'));

create policy profiles_self_select on public.profiles
for select using (id = auth.uid() or public.has_platform_permission('platform.tenants.view'));
create policy profiles_self_update on public.profiles
for update using (id = auth.uid())
with check (id = auth.uid());

create policy tenants_member_select on public.tenants
for select using (public.is_active_tenant_member(id) or public.has_platform_permission('platform.tenants.view'));
create policy tenants_tenant_update on public.tenants
for update using (public.has_tenant_permission(id, 'tenant.manage'))
with check (public.has_tenant_permission(id, 'tenant.manage') and status = (select status from public.tenants old_t where old_t.id = tenants.id));
create policy tenants_platform_manage on public.tenants
for all using (public.has_platform_permission('platform.tenants.manage'))
with check (public.has_platform_permission('platform.tenants.manage'));

create policy tenant_settings_view on public.tenant_settings
for select using (public.is_active_tenant_member(tenant_id) or public.has_platform_permission('platform.tenants.view'));
create policy tenant_settings_manage on public.tenant_settings
for update using (public.has_tenant_permission(tenant_id, 'tenant.settings.manage'))
with check (public.has_tenant_permission(tenant_id, 'tenant.settings.manage'));

create policy tenant_subscriptions_view on public.tenant_subscriptions
for select using (public.has_tenant_permission(tenant_id, 'tenant.subscription.view') or public.has_platform_permission('platform.tenants.view'));
create policy tenant_subscriptions_platform_manage on public.tenant_subscriptions
for all using (public.has_platform_permission('platform.subscriptions.manage'))
with check (public.has_platform_permission('platform.subscriptions.manage'));

create policy tenant_users_view on public.tenant_users
for select using (public.is_active_tenant_member(tenant_id) or public.has_platform_permission('platform.tenants.view'));
create policy tenant_users_manage on public.tenant_users
for all using (public.has_tenant_permission(tenant_id, 'users.invite') or public.has_tenant_permission(tenant_id, 'users.manage_roles'))
with check (public.has_tenant_permission(tenant_id, 'users.invite') or public.has_tenant_permission(tenant_id, 'users.manage_roles'));

create policy roles_select on public.roles
for select using (scope = 'TENANT' or public.has_platform_permission('platform.settings.manage'));
create policy roles_manage on public.roles
for all using (public.has_platform_permission('platform.settings.manage') or (tenant_id is not null and public.has_tenant_permission(tenant_id, 'users.manage_roles')))
with check (public.has_platform_permission('platform.settings.manage') or (tenant_id is not null and public.has_tenant_permission(tenant_id, 'users.manage_roles')));

create policy permissions_select on public.permissions
for select using (code not like 'platform.%' or public.is_platform_user());
create policy role_permissions_select on public.role_permissions
for select using (exists (select 1 from public.roles r where r.id = role_id and (r.scope = 'TENANT' or public.is_platform_user())));
create policy tenant_user_roles_view on public.tenant_user_roles
for select using (exists (select 1 from public.tenant_users tu where tu.id = tenant_user_id and public.is_active_tenant_member(tu.tenant_id)));

create policy platform_users_self_or_platform on public.platform_users
for select using (user_id = auth.uid() or public.has_platform_permission('platform.settings.manage') or public.has_platform_permission('platform.audit.view'));

create policy events_select on public.events
for select using (public.has_tenant_permission(tenant_id, 'events.view') or public.can_access_event(id) or public.has_platform_permission('platform.tenants.view'));
create policy events_insert on public.events
for insert with check (public.has_tenant_permission(tenant_id, 'events.create'));
create policy events_update on public.events
for update using (public.can_manage_event(id))
with check (tenant_id = (select tenant_id from public.events old_e where old_e.id = events.id) and public.can_manage_event(id));

create policy event_assignments_select on public.event_user_assignments
for select using (
  exists (
    select 1 from public.tenant_users tu
    where tu.id = tenant_user_id and tu.user_id = auth.uid() and tu.status = 'ACTIVE'
  )
  or public.has_tenant_permission(tenant_id, 'events.assign_users')
);
create policy event_assignments_manage on public.event_user_assignments
for all using (public.has_tenant_permission(tenant_id, 'events.assign_users'))
with check (public.has_tenant_permission(tenant_id, 'events.assign_users'));

create policy audit_logs_select on public.audit_logs
for select using (
  (tenant_id is not null and public.has_tenant_permission(tenant_id, 'audit.view'))
  or public.has_platform_permission('platform.audit.view')
);
