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

alter table public.tenant_financial_counters enable row level security;
alter table public.members enable row level security;
alter table public.event_member_categories enable row level security;
alter table public.event_members enable row level security;
alter table public.pledges enable row level security;
alter table public.pledge_history enable row level security;
alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.receipts enable row level security;
alter table public.payment_reversals enable row level security;

create policy members_select on public.members
for select using (public.has_tenant_permission(tenant_id, 'members.view'));
create policy members_update on public.members
for update using (public.has_tenant_permission(tenant_id, 'members.update'))
with check (public.has_tenant_permission(tenant_id, 'members.update'));

create policy event_member_categories_select on public.event_member_categories
for select using (public.has_event_financial_access(tenant_id, event_id, 'members.view', 'VIEW'));
create policy event_member_categories_manage on public.event_member_categories
for all using (public.has_event_financial_access(tenant_id, event_id, 'members.update', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'members.update', 'MANAGE'));

create policy event_members_select on public.event_members
for select using (public.has_event_financial_access(tenant_id, event_id, 'members.view', 'VIEW'));
create policy event_members_update on public.event_members
for update using (public.has_event_financial_access(tenant_id, event_id, 'members.assign_event', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'members.assign_event', 'MANAGE'));

create policy pledges_select on public.pledges
for select using (public.has_event_financial_access(tenant_id, event_id, 'pledges.view', 'VIEW'));
create policy pledges_update on public.pledges
for update using (public.has_event_financial_access(tenant_id, event_id, 'pledges.update', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'pledges.update', 'MANAGE'));

create policy pledge_history_select on public.pledge_history
for select using (public.has_event_financial_access(tenant_id, event_id, 'pledges.view', 'VIEW'));

create policy payments_select on public.payments
for select using (public.has_event_financial_access(tenant_id, event_id, 'payments.view', 'VIEW'));
create policy payments_update_reversal_only on public.payments
for update using (public.has_event_financial_access(tenant_id, event_id, 'payments.reverse', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'payments.reverse', 'MANAGE'));

create policy payment_allocations_select on public.payment_allocations
for select using (public.has_event_financial_access(tenant_id, event_id, 'payments.view', 'VIEW'));

create policy receipts_select on public.receipts
for select using (public.has_event_financial_access(tenant_id, event_id, 'receipts.view', 'VIEW'));

create policy payment_reversals_select on public.payment_reversals
for select using (public.has_event_financial_access(tenant_id, event_id, 'payments.view', 'VIEW'));

grant execute on function public.rpc_create_member_and_attach_to_event(uuid, uuid, text, text, text, text, text, uuid, text) to authenticated;
grant execute on function public.rpc_attach_existing_member_to_event(uuid, uuid, uuid, uuid, text) to authenticated;
grant execute on function public.rpc_remove_event_member(uuid, uuid, uuid) to authenticated;
grant execute on function public.rpc_create_or_update_pledge(uuid, uuid, uuid, numeric, date, text, text) to authenticated;
grant execute on function public.rpc_cancel_pledge(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.rpc_record_installment_payment(uuid, uuid, uuid, numeric, text, timestamptz, text, text, text, uuid, uuid) to authenticated;
grant execute on function public.rpc_reverse_payment(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.rpc_get_event_financial_summary(uuid, uuid) to authenticated;
