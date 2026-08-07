create or replace function public.rpc_list_event_members(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.full_name), '[]'::jsonb)
  into result
  from (
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
    left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED'
    where em.tenant_id = p_tenant_id
      and em.event_id = p_event_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_list_event_pledges(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.due_date asc nulls last, row_data.member_name), '[]'::jsonb)
  into result
  from (
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
    left join public.event_member_categories c on c.id = em.category_id
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_list_event_payments(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.payment_date desc), '[]'::jsonb)
  into result
  from (
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
    left join public.profiles pr on pr.id = p.received_by
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
  ) row_data;

  return result;
end;
$$;

grant execute on function public.rpc_list_event_members(uuid, uuid) to authenticated;
grant execute on function public.rpc_list_event_pledges(uuid, uuid) to authenticated;
grant execute on function public.rpc_list_event_payments(uuid, uuid) to authenticated;
