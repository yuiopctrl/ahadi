create or replace function public.rpc_record_installment_payment(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_payment_date timestamptz default now(),
  p_transaction_reference text default null,
  p_provider_name text default null,
  p_notes text default null,
  p_pledge_id uuid default null,
  p_idempotency_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  event_record public.events%rowtype;
  existing_payment public.payments%rowtype;
  payment_id uuid;
  payment_number text;
  receipt_id uuid;
  receipt_number text;
  pledge_record public.pledges%rowtype;
  outstanding numeric(18,2) := 0;
  allocated_amount numeric(18,2) := 0;
  total_paid numeric(18,2) := 0;
  pledge_status text := null;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if p_amount is null or p_amount <= 0 then
    raise exception 'PAYMENT_AMOUNT_INVALID' using errcode = '22023';
  end if;
  if p_pledge_id is null then
    raise exception 'PLEDGE_REQUIRED_FOR_PAYMENT' using errcode = '22023';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found or event_record.status <> 'ACTIVE' then
    raise exception 'EVENT_NOT_ACTIVE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.event_members where id = p_event_member_id and tenant_id = p_tenant_id and event_id = p_event_id and status = 'ACTIVE') then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select * into pledge_record
  from public.pledges
  where id = p_pledge_id
    and tenant_id = p_tenant_id
    and event_id = p_event_id
    and event_member_id = p_event_member_id
  for update;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;
  if pledge_record.status = 'CANCELLED' then
    raise exception 'PLEDGE_CANCELLED' using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    select * into existing_payment from public.payments where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      select r.id, r.receipt_number into receipt_id, receipt_number from public.receipts r where r.payment_id = existing_payment.id;
      allocated_amount := public.payment_allocated_amount(existing_payment.id);
      total_paid := public.confirmed_pledge_allocated_amount(p_pledge_id);
      pledge_status := public.calculated_pledge_status(p_pledge_id);
      select pledged_amount - least(pledged_amount, total_paid) into outstanding from public.pledges where id = p_pledge_id;
      return jsonb_build_object(
        'payment_id', existing_payment.id,
        'payment_number', existing_payment.payment_number,
        'receipt_id', receipt_id,
        'receipt_number', receipt_number,
        'payment_amount', existing_payment.amount,
        'allocated_amount', allocated_amount,
        'unallocated_amount', public.payment_unallocated_amount(existing_payment.id),
        'pledged_amount', pledge_record.pledged_amount,
        'total_paid', total_paid,
        'outstanding_amount', greatest(coalesce(outstanding, 0), 0),
        'pledge_status', pledge_status
      );
    end if;
  end if;

  if p_payment_method <> 'CASH' and nullif(btrim(coalesce(p_transaction_reference, '')), '') is not null and exists (
    select 1 from public.payments
    where tenant_id = p_tenant_id
      and lower(btrim(transaction_reference)) = lower(btrim(p_transaction_reference))
      and payment_method <> 'CASH'
      and status <> 'CANCELLED'
  ) then
    raise exception 'PAYMENT_REFERENCE_DUPLICATE' using errcode = '23505';
  end if;

  payment_number := public.next_payment_number(p_tenant_id);
  insert into public.payments (
    tenant_id, event_id, event_member_id, payment_number, amount, payment_method, payment_date,
    transaction_reference, provider_name, notes, received_by, idempotency_key
  )
  values (
    p_tenant_id, p_event_id, p_event_member_id, payment_number, p_amount, p_payment_method, coalesce(p_payment_date, now()),
    p_transaction_reference, p_provider_name, p_notes, caller, p_idempotency_key
  )
  returning id into payment_id;

  outstanding := greatest(pledge_record.pledged_amount - public.confirmed_pledge_allocated_amount(pledge_record.id), 0);
  allocated_amount := least(p_amount, outstanding);
  if allocated_amount > 0 then
    insert into public.payment_allocations (tenant_id, event_id, payment_id, pledge_id, allocated_amount, created_by)
    values (p_tenant_id, p_event_id, payment_id, p_pledge_id, allocated_amount, caller);
  end if;
  perform public.refresh_pledge_status(p_pledge_id, caller);
  total_paid := public.confirmed_pledge_allocated_amount(p_pledge_id);
  pledge_status := public.calculated_pledge_status(p_pledge_id);

  receipt_number := public.next_receipt_number(p_tenant_id);
  insert into public.receipts (tenant_id, event_id, payment_id, receipt_number, issued_by)
  values (p_tenant_id, p_event_id, payment_id, receipt_number, caller)
  returning id into receipt_id;

  perform public.write_audit_log(p_tenant_id, 'payment.recorded', 'payment', payment_id, p_event_id, null, jsonb_build_object('payment_number', payment_number, 'receipt_number', receipt_number, 'amount', p_amount, 'pledge_id', p_pledge_id));

  return jsonb_build_object(
    'payment_id', payment_id,
    'payment_number', payment_number,
    'receipt_id', receipt_id,
    'receipt_number', receipt_number,
    'payment_amount', p_amount,
    'allocated_amount', allocated_amount,
    'unallocated_amount', greatest(p_amount - allocated_amount, 0),
    'pledged_amount', pledge_record.pledged_amount,
    'total_paid', total_paid,
    'outstanding_amount', greatest(pledge_record.pledged_amount - total_paid, 0),
    'pledge_status', pledge_status
  );
end;
$$;

create or replace function public.rpc_remove_event_member(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  normalized_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Member removed from event');
  event_member_record public.event_members%rowtype;
  payment_record public.payments%rowtype;
  allocation_record record;
  pledge_record public.pledges%rowtype;
  reversed_count integer := 0;
  cancelled_count integer := 0;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.assign_event', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into event_member_record
  from public.event_members
  where id = p_event_member_id and tenant_id = p_tenant_id and event_id = p_event_id
  for update;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  for payment_record in
    select *
    from public.payments
    where tenant_id = p_tenant_id
      and event_id = p_event_id
      and event_member_id = p_event_member_id
      and status = 'CONFIRMED'
    for update
  loop
    if not exists (select 1 from public.payment_reversals where payment_id = payment_record.id) then
      insert into public.payment_reversals (tenant_id, event_id, payment_id, reason, reversed_by, original_payment_snapshot)
      values (
        payment_record.tenant_id,
        payment_record.event_id,
        payment_record.id,
        normalized_reason,
        caller,
        jsonb_build_object(
          'payment', to_jsonb(payment_record),
          'allocations', coalesce((select jsonb_agg(to_jsonb(pa)) from public.payment_allocations pa where pa.payment_id = payment_record.id), '[]'::jsonb),
          'receipt', (select to_jsonb(r) from public.receipts r where r.payment_id = payment_record.id)
        )
      );
    end if;

    update public.payments set status = 'REVERSED' where id = payment_record.id;
    reversed_count := reversed_count + 1;

    for allocation_record in select distinct pledge_id from public.payment_allocations where payment_id = payment_record.id loop
      perform public.refresh_pledge_status(allocation_record.pledge_id, caller);
    end loop;
  end loop;

  for pledge_record in
    select *
    from public.pledges
    where tenant_id = p_tenant_id
      and event_id = p_event_id
      and event_member_id = p_event_member_id
      and status <> 'CANCELLED'
    for update
  loop
    update public.pledges
    set status = 'CANCELLED',
        cancelled_at = now(),
        cancelled_by = caller,
        cancellation_reason = normalized_reason
    where id = pledge_record.id;

    insert into public.pledge_history (tenant_id, event_id, pledge_id, action, previous_status, new_status, reason, changed_by)
    values (p_tenant_id, p_event_id, pledge_record.id, 'CANCELLED', pledge_record.status, 'CANCELLED', normalized_reason, caller);
    cancelled_count := cancelled_count + 1;
  end loop;

  update public.event_members
  set status = 'REMOVED', removed_at = now(), removed_by = caller
  where id = p_event_member_id and tenant_id = p_tenant_id and event_id = p_event_id;

  perform public.write_audit_log(
    p_tenant_id,
    'event_member.removed',
    'event_member',
    p_event_member_id,
    p_event_id,
    to_jsonb(event_member_record),
    jsonb_build_object('reason', normalized_reason, 'reversedPayments', reversed_count, 'cancelledPledges', cancelled_count)
  );

  return jsonb_build_object(
    'ok', true,
    'eventMemberId', p_event_member_id,
    'reversedPayments', reversed_count,
    'cancelledPledges', cancelled_count,
    'reason', normalized_reason
  );
end;
$$;

grant execute on function public.rpc_record_installment_payment(uuid, uuid, uuid, numeric, text, timestamptz, text, text, text, uuid, uuid) to authenticated;
grant execute on function public.rpc_remove_event_member(uuid, uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
