create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  event_member_id uuid not null references public.event_members(id) on delete restrict,
  payment_number text not null,
  amount numeric(18,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('CASH', 'M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA', 'BANK_TRANSFER', 'CHEQUE', 'OTHER')),
  payment_date timestamptz not null default now(),
  transaction_reference text,
  provider_name text,
  notes text,
  status text not null default 'CONFIRMED' check (status in ('CONFIRMED', 'REVERSED', 'CANCELLED')),
  received_by uuid not null references auth.users(id),
  idempotency_key uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, payment_number),
  unique (tenant_id, idempotency_key)
);

create unique index payments_non_cash_reference_unique
on public.payments(tenant_id, lower(btrim(transaction_reference)))
where transaction_reference is not null and payment_method <> 'CASH' and status <> 'CANCELLED';

create index payments_tenant_idx on public.payments(tenant_id);
create index payments_event_idx on public.payments(event_id);
create index payments_event_member_idx on public.payments(event_member_id);
create index payments_status_idx on public.payments(status);
create index payments_payment_date_idx on public.payments(payment_date desc);

create trigger payments_set_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  payment_id uuid not null references public.payments(id) on delete restrict,
  pledge_id uuid not null references public.pledges(id) on delete restrict,
  allocated_amount numeric(18,2) not null check (allocated_amount > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index payment_allocations_tenant_idx on public.payment_allocations(tenant_id);
create index payment_allocations_event_idx on public.payment_allocations(event_id);
create index payment_allocations_payment_idx on public.payment_allocations(payment_id);
create index payment_allocations_pledge_idx on public.payment_allocations(pledge_id);

create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  payment_id uuid not null unique references public.payments(id) on delete restrict,
  receipt_number text not null,
  issued_at timestamptz not null default now(),
  issued_by uuid not null references auth.users(id),
  voided_at timestamptz,
  voided_by uuid references auth.users(id),
  void_reason text,
  created_at timestamptz not null default now(),
  unique (tenant_id, receipt_number)
);

create index receipts_tenant_idx on public.receipts(tenant_id);
create index receipts_event_idx on public.receipts(event_id);
create index receipts_payment_idx on public.receipts(payment_id);
create index receipts_issued_at_idx on public.receipts(issued_at desc);

create table public.payment_reversals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  payment_id uuid not null unique references public.payments(id) on delete restrict,
  reason text not null,
  reversed_by uuid not null references auth.users(id),
  reversed_at timestamptz not null default now(),
  original_payment_snapshot jsonb not null,
  idempotency_key uuid,
  created_at timestamptz not null default now(),
  unique (tenant_id, idempotency_key),
  check (btrim(reason) <> '')
);

create index payment_reversals_tenant_idx on public.payment_reversals(tenant_id);
create index payment_reversals_event_idx on public.payment_reversals(event_id);
create index payment_reversals_reversed_at_idx on public.payment_reversals(reversed_at desc);

create or replace function public.next_payment_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  next_number integer;
begin
  insert into public.tenant_financial_counters (tenant_id)
  values (p_tenant_id)
  on conflict (tenant_id) do nothing;

  update public.tenant_financial_counters
  set next_payment_number = next_payment_number + 1
  where tenant_id = p_tenant_id
  returning next_payment_number - 1 into next_number;

  return 'PAY-' || lpad(next_number::text, 6, '0');
end;
$$;

create or replace function public.next_receipt_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  next_number integer;
  prefix text;
begin
  insert into public.tenant_financial_counters (tenant_id)
  values (p_tenant_id)
  on conflict (tenant_id) do nothing;

  update public.tenant_financial_counters
  set next_receipt_number = next_receipt_number + 1
  where tenant_id = p_tenant_id
  returning next_receipt_number - 1 into next_number;

  select coalesce(nullif(btrim(receipt_prefix), ''), 'AHD') into prefix
  from public.tenant_settings
  where tenant_id = p_tenant_id;

  return coalesce(prefix, 'AHD') || '-' || lpad(next_number::text, 6, '0');
end;
$$;

create or replace function public.payment_allocated_amount(p_payment_id uuid)
returns numeric
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(sum(allocated_amount), 0)::numeric(18,2)
  from public.payment_allocations
  where payment_id = p_payment_id;
$$;

create or replace function public.payment_unallocated_amount(p_payment_id uuid)
returns numeric
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select greatest(0, p.amount - public.payment_allocated_amount(p.id))::numeric(18,2)
  from public.payments p
  where p.id = p_payment_id;
$$;

create or replace function public.confirmed_pledge_allocated_amount(p_pledge_id uuid)
returns numeric
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(sum(pa.allocated_amount), 0)::numeric(18,2)
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.pledge_id = p_pledge_id
    and p.status = 'CONFIRMED';
$$;

create or replace function public.calculated_pledge_status(p_pledge_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  pledge_record public.pledges%rowtype;
  paid_amount numeric(18,2);
begin
  select * into pledge_record from public.pledges where id = p_pledge_id;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;
  if pledge_record.cancelled_at is not null or pledge_record.status = 'CANCELLED' then
    return 'CANCELLED';
  end if;

  paid_amount := public.confirmed_pledge_allocated_amount(p_pledge_id);

  if paid_amount >= pledge_record.pledged_amount then
    return 'PAID';
  elsif paid_amount > 0 then
    return 'PARTIALLY_PAID';
  elsif pledge_record.due_date is not null and pledge_record.due_date < current_date then
    return 'OVERDUE';
  else
    return 'PENDING';
  end if;
end;
$$;

create or replace function public.refresh_pledge_status(p_pledge_id uuid, p_changed_by uuid default null)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  old_status text;
  new_status text;
  pledge_record public.pledges%rowtype;
begin
  select * into pledge_record from public.pledges where id = p_pledge_id for update;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;

  old_status := pledge_record.status;
  new_status := public.calculated_pledge_status(p_pledge_id);

  if old_status is distinct from new_status then
    update public.pledges set status = new_status where id = p_pledge_id;
    insert into public.pledge_history (tenant_id, event_id, pledge_id, action, previous_status, new_status, changed_by)
    values (pledge_record.tenant_id, pledge_record.event_id, p_pledge_id, 'STATUS_CHANGED', old_status, new_status, coalesce(p_changed_by, auth.uid(), pledge_record.recorded_by));
  end if;

  return new_status;
end;
$$;

create or replace function public.validate_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.tenant_id <> old.tenant_id or new.event_id <> old.event_id or new.event_member_id <> old.event_member_id then
      raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
    end if;
    if old.status = 'CONFIRMED' and new.amount <> old.amount then
      raise exception 'PAYMENT_AMOUNT_INVALID' using errcode = '22023';
    end if;
    if old.status = 'REVERSED' and new.status <> 'REVERSED' then
      raise exception 'PAYMENT_ALREADY_REVERSED' using errcode = '22023';
    end if;
  end if;

  if not exists (
    select 1
    from public.event_members em
    where em.id = new.event_member_id
      and em.tenant_id = new.tenant_id
      and em.event_id = new.event_id
      and em.status = 'ACTIVE'
  ) then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  new.transaction_reference := nullif(btrim(coalesce(new.transaction_reference, '')), '');
  new.provider_name := nullif(btrim(coalesce(new.provider_name, '')), '');

  return new;
exception
  when unique_violation then
    raise exception 'PAYMENT_REFERENCE_DUPLICATE' using errcode = '23505';
end;
$$;

create trigger payments_integrity_guard
before insert or update on public.payments
for each row execute function public.validate_payment_integrity();

create or replace function public.validate_payment_allocation_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  payment_record public.payments%rowtype;
  pledge_record public.pledges%rowtype;
  total_for_payment numeric(18,2);
begin
  select * into payment_record from public.payments where id = new.payment_id for update;
  if not found or payment_record.status <> 'CONFIRMED' then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;

  select * into pledge_record from public.pledges where id = new.pledge_id for update;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;
  if pledge_record.status = 'CANCELLED' then
    raise exception 'PLEDGE_CANCELLED' using errcode = '22023';
  end if;

  if payment_record.tenant_id <> pledge_record.tenant_id
    or payment_record.event_id <> pledge_record.event_id
    or payment_record.event_member_id <> pledge_record.event_member_id
    or new.tenant_id <> payment_record.tenant_id
    or new.event_id <> payment_record.event_id then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(sum(allocated_amount), 0) into total_for_payment
  from public.payment_allocations
  where payment_id = new.payment_id
    and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);

  if total_for_payment + new.allocated_amount > payment_record.amount then
    raise exception 'PAYMENT_AMOUNT_INVALID' using errcode = '22023';
  end if;

  return new;
end;
$$;

create trigger payment_allocations_integrity_guard
before insert or update on public.payment_allocations
for each row execute function public.validate_payment_allocation_integrity();

create or replace function public.refresh_pledge_status_from_allocation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.refresh_pledge_status(coalesce(new.pledge_id, old.pledge_id), coalesce(new.created_by, old.created_by, auth.uid()));
  return new;
end;
$$;

create trigger payment_allocations_refresh_pledge_status
after insert or update on public.payment_allocations
for each row execute function public.refresh_pledge_status_from_allocation();

create or replace function public.refresh_pledges_after_payment_status_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  pledge_record record;
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    for pledge_record in
      select distinct pledge_id from public.payment_allocations where payment_id = new.id
    loop
      perform public.refresh_pledge_status(pledge_record.pledge_id, auth.uid());
    end loop;
  end if;
  return new;
end;
$$;

create trigger payments_refresh_pledge_status
after update on public.payments
for each row execute function public.refresh_pledges_after_payment_status_change();

create or replace function public.prevent_financial_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'FINANCIAL_HISTORY_APPEND_ONLY' using errcode = '42501';
end;
$$;

create trigger payments_no_delete before delete on public.payments for each row execute function public.prevent_financial_delete();
create trigger payment_allocations_no_delete before delete on public.payment_allocations for each row execute function public.prevent_financial_delete();
create trigger receipts_no_delete before delete on public.receipts for each row execute function public.prevent_financial_delete();
create trigger payment_reversals_no_update_delete before update or delete on public.payment_reversals for each row execute function public.prevent_financial_delete();
