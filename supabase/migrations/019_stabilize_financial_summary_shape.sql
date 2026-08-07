-- 019_stabilize_financial_summary_shape

create or replace function public.rpc_get_event_financial_summary(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
  allocated_total numeric(18,2);
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  allocated_total := coalesce((
    select sum(pa.allocated_amount)
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.tenant_id = p_tenant_id
      and pa.event_id = p_event_id
      and p.status = 'CONFIRMED'
  ), 0)::numeric(18,2);

  select jsonb_build_object(
    'memberCount', (select count(*) from public.event_members em where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE'),
    'membersWithPledges', (select count(*) from public.pledges p join public.event_members em on em.id = p.event_member_id where p.tenant_id = p_tenant_id and p.event_id = p_event_id and em.status = 'ACTIVE' and p.status <> 'CANCELLED'),
    'membersWithoutPledges', (select count(*) from public.event_members em where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE' and not exists (select 1 from public.pledges p where p.event_member_id = em.id and p.status <> 'CANCELLED')),
    'totalPledged', coalesce((select sum(pledged_amount) from public.pledges where tenant_id = p_tenant_id and event_id = p_event_id and status <> 'CANCELLED'), 0),
    'totalConfirmedPayments', coalesce((select sum(amount) from public.payments where tenant_id = p_tenant_id and event_id = p_event_id and status = 'CONFIRMED'), 0),
    'totalAllocated', allocated_total,
    'totalAllocatedToPledges', allocated_total,
    'totalUnallocated', coalesce((select sum(public.payment_unallocated_amount(p.id)) from public.payments p where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status = 'CONFIRMED'), 0),
    'totalOutstanding', coalesce((select sum(greatest(pl.pledged_amount - public.confirmed_pledge_allocated_amount(pl.id), 0)) from public.pledges pl where pl.tenant_id = p_tenant_id and pl.event_id = p_event_id and pl.status <> 'CANCELLED'), 0),
    'fullyPaidCount', (select count(*) from public.pledges where tenant_id = p_tenant_id and event_id = p_event_id and status = 'PAID'),
    'partiallyPaidCount', (select count(*) from public.pledges where tenant_id = p_tenant_id and event_id = p_event_id and status = 'PARTIALLY_PAID'),
    'unpaidCount', (select count(*) from public.pledges where tenant_id = p_tenant_id and event_id = p_event_id and status in ('PENDING', 'OVERDUE')),
    'overdueCount', (select count(*) from public.pledges where tenant_id = p_tenant_id and event_id = p_event_id and status = 'OVERDUE'),
    'paymentsToday', coalesce((select sum(amount) from public.payments where tenant_id = p_tenant_id and event_id = p_event_id and status = 'CONFIRMED' and payment_date::date = current_date), 0),
    'paymentsThisMonth', coalesce((select sum(amount) from public.payments where tenant_id = p_tenant_id and event_id = p_event_id and status = 'CONFIRMED' and date_trunc('month', payment_date) = date_trunc('month', now())), 0)
  ) into result;

  return result;
end;
$$;

grant execute on function public.rpc_get_event_financial_summary(uuid, uuid) to authenticated;
