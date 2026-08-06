insert into public.permissions (code, name, description) values
('tenant.view', 'View tenant', 'View tenant workspace'),
('tenant.manage', 'Manage tenant', 'Manage tenant profile'),
('tenant.settings.view', 'View settings', 'View tenant settings'),
('tenant.settings.manage', 'Manage settings', 'Update tenant settings'),
('tenant.subscription.view', 'View subscription', 'View tenant subscription'),
('tenant.subscription.manage', 'Manage subscription', 'Manage tenant subscription'),
('users.view', 'View users', 'View tenant users'),
('users.invite', 'Invite users', 'Invite tenant users'),
('users.manage_roles', 'Manage roles', 'Assign tenant roles'),
('users.suspend', 'Suspend users', 'Suspend tenant users'),
('events.view', 'View events', 'View tenant events'),
('events.create', 'Create events', 'Create tenant events'),
('events.update', 'Update events', 'Update tenant events'),
('events.close', 'Close events', 'Close tenant events'),
('events.archive', 'Archive events', 'Archive tenant events'),
('events.assign_users', 'Assign event users', 'Assign users to events'),
('reports.view', 'View reports', 'View reports'),
('reports.export', 'Export reports', 'Export reports'),
('messages.view', 'View messages', 'View messages'),
('messages.send', 'Send messages', 'Send messages'),
('messages.manage_templates', 'Manage message templates', 'Manage message templates'),
('audit.view', 'View audit', 'View tenant audit logs'),
('platform.dashboard.view', 'Platform dashboard', 'View platform dashboard'),
('platform.tenants.view', 'View platform tenants', 'View tenants across platform'),
('platform.tenants.manage', 'Manage platform tenants', 'Manage tenants across platform'),
('platform.plans.view', 'View platform plans', 'View subscription plans'),
('platform.plans.manage', 'Manage platform plans', 'Manage subscription plans'),
('platform.subscriptions.manage', 'Manage platform subscriptions', 'Manage tenant subscriptions'),
('platform.sms.view', 'View platform SMS', 'View SMS operations'),
('platform.audit.view', 'View platform audit', 'View platform audit logs'),
('platform.settings.manage', 'Manage platform settings', 'Manage platform settings')
on conflict (code) do update set name = excluded.name, description = excluded.description;

insert into public.roles (code, name, description, scope, is_system) values
('TENANT_OWNER', 'Tenant Owner', 'Full tenant administration except platform-only functions', 'TENANT', true),
('EVENT_ADMIN', 'Event Admin', 'Manages events, assignments, reports and messages', 'TENANT', true),
('TREASURER', 'Treasurer', 'Views tenant, events and reports for financial oversight', 'TENANT', true),
('COLLECTOR', 'Collector', 'Views assigned events and prepares for future collection workflows', 'TENANT', true),
('VIEWER', 'Viewer', 'Read-only event and report access', 'TENANT', true)
on conflict (code) do update set name = excluded.name, description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.code = 'TENANT_OWNER' and p.code not like 'platform.%'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'tenant.view','users.view','events.view','events.create','events.update','events.close','events.archive','events.assign_users',
  'reports.view','reports.export','messages.view','messages.send','messages.manage_templates'
)
where r.code = 'EVENT_ADMIN'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('tenant.view','events.view','reports.view','reports.export')
where r.code = 'TREASURER'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('tenant.view','events.view')
where r.code = 'COLLECTOR'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('events.view','reports.view')
where r.code = 'VIEWER'
on conflict do nothing;
