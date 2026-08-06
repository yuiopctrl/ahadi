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

create or replace function public.ensure_tenant_write_access(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_status text;
begin
  select status into tenant_status from public.tenants where id = p_tenant_id;
  if tenant_status is null then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if tenant_status in ('SUSPENDED', 'CANCELLED', 'ARCHIVED') then
    raise exception 'SUBSCRIPTION_BLOCKED' using errcode = '22023';
  end if;
  if tenant_status = 'EXPIRED' then
    raise exception 'SUBSCRIPTION_READ_ONLY' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.pledge_financial_summary(p_pledge_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  pledge_record public.pledges%rowtype;
  total_paid numeric(18,2);
begin
  select * into pledge_record from public.pledges where id = p_pledge_id;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;

  total_paid := public.confirmed_pledge_allocated_amount(p_pledge_id);

  return jsonb_build_object(
    'pledge_id', pledge_record.id,
    'pledged_amount', pledge_record.pledged_amount,
    'total_paid', total_paid,
    'outstanding_amount', greatest(pledge_record.pledged_amount - total_paid, 0),
    'pledge_status', public.calculated_pledge_status(p_pledge_id)
  );
end;
$$;

create or replace function public.rpc_create_member_and_attach_to_event(
  p_tenant_id uuid,
  p_event_id uuid,
  p_full_name text,
  p_phone text default null,
  p_alternative_phone text default null,
  p_email text default null,
  p_location text default null,
  p_category_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  normalized_phone text;
  normalized_alt_phone text;
  member_id uuid;
  event_member_id uuid;
  member_code text;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if btrim(coalesce(p_full_name, '')) = '' then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  normalized_phone := case when p_phone is null or btrim(p_phone) = '' then null else public.normalize_tz_phone(p_phone) end;
  normalized_alt_phone := case when p_alternative_phone is null or btrim(p_alternative_phone) = '' then null else public.normalize_tz_phone(p_alternative_phone) end;

  if normalized_phone is not null and exists (
    select 1 from public.members
    where tenant_id = p_tenant_id and phone_e164 = normalized_phone and status = 'ACTIVE'
  ) then
    raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505';
  end if;

  member_code := public.next_member_code(p_tenant_id);
  insert into public.members (tenant_id, member_code, full_name, phone_e164, alternative_phone_e164, email, location, notes, created_by)
  values (p_tenant_id, member_code, p_full_name, normalized_phone, normalized_alt_phone, nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_location, '')), ''), p_notes, caller)
  returning id into member_id;

  insert into public.event_members (tenant_id, event_id, member_id, category_id, notes, created_by)
  values (p_tenant_id, p_event_id, member_id, p_category_id, p_notes, caller)
  returning id into event_member_id;

  perform public.write_audit_log(p_tenant_id, 'member.created', 'member', member_id, p_event_id, null, jsonb_build_object('member_code', member_code));
  perform public.write_audit_log(p_tenant_id, 'event_member.attached', 'event_member', event_member_id, p_event_id, null, jsonb_build_object('member_id', member_id));

  return jsonb_build_object('member_id', member_id, 'event_member_id', event_member_id, 'member_code', member_code);
end;
$$;

create or replace function public.rpc_attach_existing_member_to_event(
  p_tenant_id uuid,
  p_event_id uuid,
  p_member_id uuid,
  p_category_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  existing public.event_members%rowtype;
  event_member_id uuid;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.assign_event', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.members where id = p_member_id and tenant_id = p_tenant_id and status <> 'ARCHIVED') then
    raise exception 'MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select * into existing from public.event_members where event_id = p_event_id and member_id = p_member_id for update;
  if found and existing.status = 'ACTIVE' then
    raise exception 'MEMBER_ALREADY_IN_EVENT' using errcode = '23505';
  elsif found then
    update public.event_members
    set status = 'ACTIVE', category_id = p_category_id, notes = p_notes, removed_at = null, removed_by = null
    where id = existing.id
    returning id into event_member_id;
  else
    insert into public.event_members (tenant_id, event_id, member_id, category_id, notes, created_by)
    values (p_tenant_id, p_event_id, p_member_id, p_category_id, p_notes, caller)
    returning id into event_member_id;
  end if;

  perform public.write_audit_log(p_tenant_id, 'event_member.attached', 'event_member', event_member_id, p_event_id, null, jsonb_build_object('member_id', p_member_id));
  return jsonb_build_object('event_member_id', event_member_id, 'member_id', p_member_id);
end;
$$;

create or replace function public.rpc_remove_event_member(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.assign_event', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  update public.event_members
  set status = 'REMOVED', removed_at = now(), removed_by = caller
  where id = p_event_member_id and tenant_id = p_tenant_id and event_id = p_event_id
  returning id into p_event_member_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  perform public.write_audit_log(p_tenant_id, 'event_member.removed', 'event_member', p_event_member_id, p_event_id, null, null);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rpc_create_or_update_pledge(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid,
  p_amount numeric,
  p_due_date date default null,
  p_notes text default null,
  p_change_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  existing public.pledges%rowtype;
  pledge_id uuid;
  allocated numeric(18,2);
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'PLEDGE_AMOUNT_INVALID' using errcode = '22023';
  end if;
  if not exists (select 1 from public.event_members where id = p_event_member_id and tenant_id = p_tenant_id and event_id = p_event_id and status = 'ACTIVE') then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select * into existing from public.pledges where event_member_id = p_event_member_id for update;
  if found then
    if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.update', 'COLLECT') then
      raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
    end if;
    if existing.status = 'CANCELLED' then
      raise exception 'PLEDGE_CANCELLED' using errcode = '22023';
    end if;
    allocated := public.confirmed_pledge_allocated_amount(existing.id);
    if p_amount < allocated then
      raise exception 'PLEDGE_BELOW_PAID_AMOUNT' using errcode = '22023';
    end if;
    if p_amount < existing.pledged_amount and btrim(coalesce(p_change_reason, '')) = '' then
      raise exception 'INVALID_INPUT' using errcode = '22023';
    end if;
    update public.pledges
    set pledged_amount = p_amount,
        due_date = p_due_date,
        notes = p_notes
    where id = existing.id
    returning id into pledge_id;

    if p_amount is distinct from existing.pledged_amount then
      insert into public.pledge_history (tenant_id, event_id, pledge_id, action, previous_amount, new_amount, reason, changed_by)
      values (p_tenant_id, p_event_id, pledge_id, 'AMOUNT_CHANGED', existing.pledged_amount, p_amount, p_change_reason, caller);
    end if;
    if p_due_date is distinct from existing.due_date then
      insert into public.pledge_history (tenant_id, event_id, pledge_id, action, previous_due_date, new_due_date, reason, changed_by)
      values (p_tenant_id, p_event_id, pledge_id, 'DUE_DATE_CHANGED', existing.due_date, p_due_date, p_change_reason, caller);
    end if;
  else
    insert into public.pledges (tenant_id, event_id, event_member_id, pledged_amount, due_date, notes, recorded_by)
    values (p_tenant_id, p_event_id, p_event_member_id, p_amount, p_due_date, p_notes, caller)
    returning id into pledge_id;
    insert into public.pledge_history (tenant_id, event_id, pledge_id, action, new_amount, new_due_date, new_status, changed_by)
    values (p_tenant_id, p_event_id, pledge_id, 'CREATED', p_amount, p_due_date, 'PENDING', caller);
  end if;

  perform public.refresh_pledge_status(pledge_id, caller);
  perform public.write_audit_log(p_tenant_id, 'pledge.upserted', 'pledge', pledge_id, p_event_id, null, public.pledge_financial_summary(pledge_id));
  return public.pledge_financial_summary(pledge_id);
end;
$$;

create or replace function public.rpc_cancel_pledge(
  p_tenant_id uuid,
  p_event_id uuid,
  p_pledge_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  previous_status text;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.cancel', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  select status into previous_status
  from public.pledges
  where id = p_pledge_id and tenant_id = p_tenant_id and event_id = p_event_id
  for update;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;

  update public.pledges
  set status = 'CANCELLED', cancelled_at = now(), cancelled_by = caller, cancellation_reason = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_pledge_id and tenant_id = p_tenant_id and event_id = p_event_id;
  insert into public.pledge_history (tenant_id, event_id, pledge_id, action, previous_status, new_status, reason, changed_by)
  values (p_tenant_id, p_event_id, p_pledge_id, 'CANCELLED', previous_status, 'CANCELLED', p_reason, caller);
  perform public.write_audit_log(p_tenant_id, 'pledge.cancelled', 'pledge', p_pledge_id, p_event_id, null, jsonb_build_object('reason', p_reason));
  return public.pledge_financial_summary(p_pledge_id);
end;
$$;

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

  if p_idempotency_key is not null then
    select * into existing_payment from public.payments where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      select r.id, r.receipt_number into receipt_id, receipt_number from public.receipts r where r.payment_id = existing_payment.id;
      allocated_amount := public.payment_allocated_amount(existing_payment.id);
      if p_pledge_id is not null then
        total_paid := public.confirmed_pledge_allocated_amount(p_pledge_id);
        pledge_status := public.calculated_pledge_status(p_pledge_id);
        select pledged_amount - least(pledged_amount, total_paid) into outstanding from public.pledges where id = p_pledge_id;
      end if;
      return jsonb_build_object(
        'payment_id', existing_payment.id,
        'payment_number', existing_payment.payment_number,
        'receipt_id', receipt_id,
        'receipt_number', receipt_number,
        'payment_amount', existing_payment.amount,
        'allocated_amount', allocated_amount,
        'unallocated_amount', public.payment_unallocated_amount(existing_payment.id),
        'pledged_amount', coalesce((select pledged_amount from public.pledges where id = p_pledge_id), 0),
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

  if p_pledge_id is not null then
    select * into pledge_record from public.pledges where id = p_pledge_id and tenant_id = p_tenant_id and event_id = p_event_id and event_member_id = p_event_member_id for update;
    if not found then
      raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
    end if;
    if pledge_record.status = 'CANCELLED' then
      raise exception 'PLEDGE_CANCELLED' using errcode = '22023';
    end if;
    outstanding := greatest(pledge_record.pledged_amount - public.confirmed_pledge_allocated_amount(pledge_record.id), 0);
    allocated_amount := least(p_amount, outstanding);
    if allocated_amount > 0 then
      insert into public.payment_allocations (tenant_id, event_id, payment_id, pledge_id, allocated_amount, created_by)
      values (p_tenant_id, p_event_id, payment_id, p_pledge_id, allocated_amount, caller);
    end if;
    perform public.refresh_pledge_status(p_pledge_id, caller);
    total_paid := public.confirmed_pledge_allocated_amount(p_pledge_id);
    pledge_status := public.calculated_pledge_status(p_pledge_id);
  end if;

  receipt_number := public.next_receipt_number(p_tenant_id);
  insert into public.receipts (tenant_id, event_id, payment_id, receipt_number, issued_by)
  values (p_tenant_id, p_event_id, payment_id, receipt_number, caller)
  returning id into receipt_id;

  perform public.write_audit_log(p_tenant_id, 'payment.recorded', 'payment', payment_id, p_event_id, null, jsonb_build_object('payment_number', payment_number, 'receipt_number', receipt_number, 'amount', p_amount));

  return jsonb_build_object(
    'payment_id', payment_id,
    'payment_number', payment_number,
    'receipt_id', receipt_id,
    'receipt_number', receipt_number,
    'payment_amount', p_amount,
    'allocated_amount', allocated_amount,
    'unallocated_amount', greatest(p_amount - allocated_amount, 0),
    'pledged_amount', coalesce(pledge_record.pledged_amount, 0),
    'total_paid', total_paid,
    'outstanding_amount', greatest(coalesce(pledge_record.pledged_amount, 0) - total_paid, 0),
    'pledge_status', pledge_status
  );
end;
$$;

create or replace function public.rpc_reverse_payment(
  p_tenant_id uuid,
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  payment_record public.payments%rowtype;
  allocation_record record;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'PAYMENT_REVERSAL_REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into payment_record from public.payments where id = p_payment_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;
  if not public.has_event_financial_access(payment_record.tenant_id, payment_record.event_id, 'payments.reverse', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if payment_record.status = 'REVERSED' or exists (select 1 from public.payment_reversals where payment_id = p_payment_id) then
    raise exception 'PAYMENT_ALREADY_REVERSED' using errcode = '22023';
  end if;
  if payment_record.status <> 'CONFIRMED' then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;

  insert into public.payment_reversals (tenant_id, event_id, payment_id, reason, reversed_by, original_payment_snapshot, idempotency_key)
  values (
    payment_record.tenant_id,
    payment_record.event_id,
    payment_record.id,
    p_reason,
    caller,
    jsonb_build_object(
      'payment', to_jsonb(payment_record),
      'allocations', coalesce((select jsonb_agg(to_jsonb(pa)) from public.payment_allocations pa where pa.payment_id = payment_record.id), '[]'::jsonb),
      'receipt', (select to_jsonb(r) from public.receipts r where r.payment_id = payment_record.id)
    ),
    p_idempotency_key
  );

  update public.payments set status = 'REVERSED' where id = payment_record.id;

  for allocation_record in select distinct pledge_id from public.payment_allocations where payment_id = payment_record.id loop
    perform public.refresh_pledge_status(allocation_record.pledge_id, caller);
  end loop;

  perform public.write_audit_log(payment_record.tenant_id, 'payment.reversed', 'payment', payment_record.id, payment_record.event_id, to_jsonb(payment_record), jsonb_build_object('reason', p_reason));
  return public.rpc_get_event_financial_summary(payment_record.tenant_id, payment_record.event_id);
end;
$$;

create or replace function public.rpc_get_event_financial_summary(p_tenant_id uuid, p_event_id uuid)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'memberCount', (select count(*) from public.event_members em where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE'),
    'membersWithPledges', (select count(*) from public.pledges p join public.event_members em on em.id = p.event_member_id where p.tenant_id = p_tenant_id and p.event_id = p_event_id and em.status = 'ACTIVE' and p.status <> 'CANCELLED'),
    'membersWithoutPledges', (select count(*) from public.event_members em where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE' and not exists (select 1 from public.pledges p where p.event_member_id = em.id and p.status <> 'CANCELLED')),
    'totalPledged', coalesce((select sum(pledged_amount) from public.pledges where tenant_id = p_tenant_id and event_id = p_event_id and status <> 'CANCELLED'), 0),
    'totalConfirmedPayments', coalesce((select sum(amount) from public.payments where tenant_id = p_tenant_id and event_id = p_event_id and status = 'CONFIRMED'), 0),
    'totalAllocatedToPledges', coalesce((select sum(pa.allocated_amount) from public.payment_allocations pa join public.payments p on p.id = pa.payment_id where pa.tenant_id = p_tenant_id and pa.event_id = p_event_id and p.status = 'CONFIRMED'), 0),
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
