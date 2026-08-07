-- 018_repair_event_financial_access

insert into public.permissions (code, name, description) values
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
('receipts.print', 'Print receipts', 'Print payment receipts')
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
  'members.view','members.create','members.update','members.archive','members.assign_event',
  'pledges.view','pledges.create','pledges.update','pledges.cancel',
  'payments.view','payments.create','payments.reverse',
  'receipts.view','receipts.print'
)
where r.code = 'EVENT_ADMIN'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'members.view',
  'pledges.view','pledges.create','pledges.update','pledges.cancel',
  'payments.view','payments.create','payments.reverse',
  'receipts.view','receipts.print'
)
where r.code = 'TREASURER'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'members.view','members.create','members.assign_event',
  'pledges.view','pledges.create',
  'payments.view','payments.create',
  'receipts.view','receipts.print'
)
where r.code = 'COLLECTOR'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('members.view','pledges.view','payments.view','receipts.view','receipts.print')
where r.code = 'VIEWER'
on conflict do nothing;

create or replace function public.has_event_financial_access(p_tenant_id uuid, p_event_id uuid, p_permission text, p_min_assignment_level text default 'VIEW')
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.events e
    where e.id = p_event_id
      and e.tenant_id = p_tenant_id
      and (
        public.has_tenant_permission(p_tenant_id, p_permission)
        or (
          p_min_assignment_level = 'VIEW'
          and (
            public.has_tenant_permission(p_tenant_id, 'events.view')
            or exists (
              select 1
              from public.event_user_assignments eua
              join public.tenant_users tu on tu.id = eua.tenant_user_id
              where eua.event_id = p_event_id
                and eua.tenant_id = p_tenant_id
                and tu.user_id = auth.uid()
                and tu.status = 'ACTIVE'
            )
          )
        )
        or exists (
          select 1
          from public.event_user_assignments eua
          join public.tenant_users tu on tu.id = eua.tenant_user_id
          join public.tenant_user_roles tur on tur.tenant_user_id = tu.id
          join public.roles r on r.id = tur.role_id
          join public.role_permissions rp on rp.role_id = r.id
          join public.permissions perm on perm.id = rp.permission_id
          where eua.event_id = p_event_id
            and eua.tenant_id = p_tenant_id
            and tu.user_id = auth.uid()
            and tu.status = 'ACTIVE'
            and perm.code = p_permission
            and (
              p_min_assignment_level = 'VIEW'
              or (p_min_assignment_level = 'COLLECT' and eua.access_level in ('COLLECT', 'MANAGE'))
              or (p_min_assignment_level = 'MANAGE' and eua.access_level = 'MANAGE')
            )
        )
      )
  );
$$;

comment on function public.has_event_financial_access(uuid, uuid, text, text) is
'Checks event-scoped financial access. VIEW operations also allow users who can view the event, while write operations continue to require the requested financial permission and assignment level.';
