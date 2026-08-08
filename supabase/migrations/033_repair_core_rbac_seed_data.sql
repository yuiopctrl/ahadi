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
('members.view', 'View members', 'View tenant members and event members'),
('members.create', 'Create members', 'Create tenant members'),
('members.update', 'Update members', 'Update tenant member details'),
('members.archive', 'Archive members', 'Archive tenant members'),
('members.assign_event', 'Assign event members', 'Attach members to events'),
('pledges.view', 'View pledges', 'View event pledges'),
('pledges.create', 'Create pledges', 'Create event pledges'),
('pledges.update', 'Update pledges', 'Update event pledges'),
('pledges.cancel', 'Cancel pledges', 'Cancel event pledges'),
('payments.view', 'View payments', 'View event payments'),
('payments.create', 'Create payments', 'Record installment payments'),
('payments.reverse', 'Reverse payments', 'Reverse confirmed payments'),
('receipts.view', 'View receipts', 'View payment receipts'),
('receipts.print', 'Print receipts', 'Print payment receipts'),
('reports.view', 'View reports', 'View reports'),
('reports.export', 'Export reports', 'Export event financial reports'),
('messages.view', 'View messages', 'View tenant SMS message history'),
('messages.send', 'Send messages', 'Send or resend tenant SMS messages'),
('messages.manage_templates', 'Manage message templates', 'Customize tenant SMS templates'),
('shares.whatsapp.view', 'View WhatsApp share lists', 'Generate privacy-friendly event contributor lists for sharing'),
('shares.whatsapp.financial', 'View financial WhatsApp share lists', 'Generate contributor lists that include pledged, paid, or outstanding amounts'),
('audit.view', 'View audit', 'View tenant audit logs'),
('platform.dashboard.view', 'Platform dashboard', 'View platform dashboard'),
('platform.tenants.view', 'View platform tenants', 'View tenants across platform'),
('platform.tenants.manage', 'Manage platform tenants', 'Manage tenants across platform'),
('platform.plans.view', 'View platform plans', 'View subscription plans'),
('platform.plans.manage', 'Manage platform plans', 'Manage subscription plans'),
('platform.subscriptions.manage', 'Manage platform subscriptions', 'Manage tenant subscriptions'),
('platform.sms.view', 'View platform SMS', 'View SMS operations'),
('platform.audit.view', 'View platform audit', 'View platform audit logs'),
('platform.settings.manage', 'Manage platform settings', 'Manage platform settings'),
('platform.beta.view', 'View beta rollout', 'View beta rollout operations'),
('platform.beta.manage', 'Manage beta rollout', 'Manage registration policy and beta invitations'),
('platform.support.view', 'View support desk', 'View support tickets and safe tenant support context'),
('platform.support.manage', 'Manage support desk', 'Assign tickets and update support workflow'),
('platform.feedback.view', 'View product feedback', 'View beta product feedback'),
('platform.features.view', 'View feature flags', 'View feature flag configuration'),
('platform.features.manage', 'Manage feature flags', 'Manage global and tenant feature flag overrides'),
('platform.system_errors.view', 'View system errors', 'View first-party operational error reports'),
('platform.support_session.start', 'Start support session', 'Start controlled read-only support sessions')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

insert into public.roles (code, name, description, scope, is_system) values
('TENANT_OWNER', 'Tenant Owner', 'Full tenant administration except platform-only functions', 'TENANT', true),
('EVENT_ADMIN', 'Event Admin', 'Manages events, assignments, reports and messages', 'TENANT', true),
('TREASURER', 'Treasurer', 'Views tenant, events and reports for financial oversight', 'TENANT', true),
('COLLECTOR', 'Collector', 'Views assigned events and records delegated collections', 'TENANT', true),
('VIEWER', 'Viewer', 'Read-only event and report access', 'TENANT', true)
on conflict (code) do update
set name = excluded.name,
    description = excluded.description,
    scope = excluded.scope,
    is_system = excluded.is_system;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.code = 'TENANT_OWNER'
  and r.tenant_id is null
  and p.code not like 'platform.%'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'tenant.view','users.view','users.invite','users.manage_roles',
  'events.view','events.create','events.update','events.close','events.archive','events.assign_users',
  'members.view','members.create','members.update','members.archive','members.assign_event',
  'pledges.view','pledges.create','pledges.update','pledges.cancel',
  'payments.view','payments.create','payments.reverse',
  'receipts.view','receipts.print',
  'reports.view','reports.export',
  'messages.view','messages.send','messages.manage_templates',
  'shares.whatsapp.view','shares.whatsapp.financial'
)
where r.code = 'EVENT_ADMIN'
  and r.tenant_id is null
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'tenant.view','events.view',
  'members.view',
  'pledges.view','pledges.create','pledges.update','pledges.cancel',
  'payments.view','payments.create','payments.reverse',
  'receipts.view','receipts.print',
  'reports.view','reports.export',
  'messages.view','messages.send',
  'shares.whatsapp.view','shares.whatsapp.financial'
)
where r.code = 'TREASURER'
  and r.tenant_id is null
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'tenant.view','events.view',
  'members.view','members.create','members.assign_event',
  'pledges.view','pledges.create',
  'payments.view','payments.create',
  'receipts.view','receipts.print',
  'messages.view','messages.send',
  'shares.whatsapp.view','shares.whatsapp.financial'
)
where r.code = 'COLLECTOR'
  and r.tenant_id is null
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'events.view',
  'members.view',
  'pledges.view',
  'payments.view',
  'receipts.view','receipts.print',
  'reports.view',
  'messages.view',
  'shares.whatsapp.view'
)
where r.code = 'VIEWER'
  and r.tenant_id is null
on conflict do nothing;
