-- 063_event_summary_financial_totals
-- event_summary_json powers the mobile app's tenant-context event list (dashboard
-- and events screens). It previously omitted financial totals, so every
-- EventSummaryCard rendered from that list showed "TZS -" even though the
-- per-event financial summary RPC had real figures. Bring the two in line.

create or replace function public.event_summary_json(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'code', e.code,
    'name', e.name,
    'eventType', e.event_type,
    'customEventType', e.custom_event_type,
    'status', e.status,
    'eventDate', e.event_date,
    'venue', e.venue,
    'pledgeDeadline', e.pledge_deadline,
    'targetAmount', e.target_amount,
    'memberCount', (
      select count(*) from public.event_members em
      where em.tenant_id = p_tenant_id and em.event_id = e.id and em.status = 'ACTIVE'
    ),
    'totalPledged', coalesce((
      select sum(pl.pledged_amount) from public.pledges pl
      where pl.tenant_id = p_tenant_id and pl.event_id = e.id and pl.status <> 'CANCELLED'
    ), 0),
    'totalCollected', coalesce((
      select sum(pa.allocated_amount) from public.payment_allocations pa
      join public.payments pay on pay.id = pa.payment_id
      where pa.tenant_id = p_tenant_id and pa.event_id = e.id and pay.status = 'CONFIRMED'
    ), 0),
    'totalOutstanding', coalesce((
      select sum(greatest(pl.pledged_amount - public.confirmed_pledge_allocated_amount(pl.id), 0))
      from public.pledges pl
      where pl.tenant_id = p_tenant_id and pl.event_id = e.id and pl.status <> 'CANCELLED'
    ), 0)
  ) order by case e.status when 'ACTIVE' then 0 when 'DRAFT' then 1 else 2 end, e.event_date nulls last, e.created_at desc), '[]'::jsonb)
  from public.events e
  where e.tenant_id = p_tenant_id
    and (public.has_tenant_permission(p_tenant_id, 'events.view') or public.can_access_event(e.id));
$$;
