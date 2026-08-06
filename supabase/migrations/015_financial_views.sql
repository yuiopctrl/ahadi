create or replace view public.v_event_members_list
with (security_invoker = true)
as
select
  em.tenant_id,
  em.event_id,
  em.id as event_member_id,
  m.id as member_id,
  m.member_code,
  m.full_name,
  m.phone_e164,
  c.name as category,
  em.status as event_member_status,
  p.id as pledge_id,
  p.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as total_allocated,
  greatest(coalesce(p.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  p.status as pledge_status,
  (
    select max(pay.payment_date)
    from public.payments pay
    where pay.event_member_id = em.id
      and pay.status = 'CONFIRMED'
  ) as last_payment_date
from public.event_members em
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED';

create or replace view public.v_event_pledges_list
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  p.id as pledge_id,
  p.event_member_id,
  m.full_name as member_name,
  m.phone_e164,
  c.name as category,
  p.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as total_allocated,
  greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  p.due_date,
  p.status,
  (
    select max(pay.payment_date)
    from public.payments pay
    join public.payment_allocations pa on pa.payment_id = pay.id
    where pa.pledge_id = p.id
      and pay.status = 'CONFIRMED'
  ) as last_payment_date
from public.pledges p
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id;

create or replace view public.v_event_payments_list
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  p.id as payment_id,
  p.payment_number,
  r.id as receipt_id,
  r.receipt_number,
  p.event_member_id,
  m.full_name as member_name,
  p.amount,
  public.payment_allocated_amount(p.id)::numeric(18,2) as allocated_amount,
  public.payment_unallocated_amount(p.id)::numeric(18,2) as unallocated_amount,
  p.payment_method,
  p.transaction_reference,
  p.payment_date,
  p.status,
  pr.full_name as received_by_name
from public.payments p
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.receipts r on r.payment_id = p.id
left join public.profiles pr on pr.id = p.received_by;

create or replace view public.v_event_outstanding_members
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  m.full_name as member_name,
  m.phone_e164 as phone,
  c.name as category,
  p.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as paid_amount,
  greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  p.due_date,
  case when p.due_date is not null and p.due_date < current_date and p.status <> 'PAID' then current_date - p.due_date else 0 end as days_overdue,
  p.status as pledge_status,
  (
    select max(pay.payment_date)
    from public.payments pay
    join public.payment_allocations pa on pa.payment_id = pay.id
    where pa.pledge_id = p.id
      and pay.status = 'CONFIRMED'
  ) as last_payment_date
from public.pledges p
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
where p.status in ('PENDING', 'PARTIALLY_PAID', 'OVERDUE');

create or replace view public.v_receipt_detail
with (security_invoker = true)
as
select
  r.tenant_id,
  r.event_id,
  r.id as receipt_id,
  r.receipt_number,
  r.issued_at,
  t.name as tenant_name,
  ts.logo_url as tenant_logo_url,
  e.name as event_name,
  e.event_date,
  m.full_name as member_name,
  m.phone_e164 as member_phone,
  p.id as payment_id,
  p.payment_number,
  p.amount as payment_amount,
  public.payment_allocated_amount(p.id)::numeric(18,2) as allocated_amount,
  public.payment_unallocated_amount(p.id)::numeric(18,2) as unallocated_excess,
  p.payment_method,
  p.transaction_reference,
  p.provider_name,
  p.payment_date,
  p.status as payment_status,
  pl.id as pledge_id,
  pl.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(pl.id), 0)::numeric(18,2) as total_paid_toward_pledge,
  greatest(coalesce(pl.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(pl.id), 0), 0)::numeric(18,2) as outstanding_amount,
  receiver.full_name as received_by,
  rev.reason as reversal_reason,
  rev.reversed_at
from public.receipts r
join public.payments p on p.id = r.payment_id
join public.tenants t on t.id = r.tenant_id
left join public.tenant_settings ts on ts.tenant_id = r.tenant_id
join public.events e on e.id = r.event_id
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.payment_allocations pa on pa.payment_id = p.id
left join public.pledges pl on pl.id = pa.pledge_id
left join public.profiles receiver on receiver.id = p.received_by
left join public.payment_reversals rev on rev.payment_id = p.id;
