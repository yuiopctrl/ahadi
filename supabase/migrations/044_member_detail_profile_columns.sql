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
  ) as last_payment_date,
  m.alternative_phone_e164,
  m.email,
  m.location,
  m.sms_enabled,
  p.due_date,
  coalesce(p.due_date, e.pledge_deadline) as effective_due_date,
  (p.due_date is not null) as has_custom_due_date,
  m.notes,
  m.preferred_language,
  m.status as member_status
from public.event_members em
join public.events e on e.id = em.event_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED';

grant select on public.v_event_members_list to authenticated;
