create table public.pledges (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  event_member_id uuid not null references public.event_members(id) on delete restrict,
  pledged_amount numeric(18,2) not null check (pledged_amount > 0),
  pledged_at timestamptz not null default now(),
  due_date date,
  status text not null default 'PENDING' check (status in ('PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED')),
  notes text,
  recorded_by uuid not null references auth.users(id),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_member_id),
  check ((status = 'CANCELLED') = (cancelled_at is not null) or status <> 'CANCELLED')
);

create index pledges_tenant_idx on public.pledges(tenant_id);
create index pledges_event_idx on public.pledges(event_id);
create index pledges_event_member_idx on public.pledges(event_member_id);
create index pledges_status_idx on public.pledges(status);
create index pledges_due_date_idx on public.pledges(due_date);

create trigger pledges_set_updated_at
before update on public.pledges
for each row execute function public.set_updated_at();

create table public.pledge_history (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  pledge_id uuid not null references public.pledges(id) on delete cascade,
  action text not null check (action in ('CREATED', 'AMOUNT_CHANGED', 'DUE_DATE_CHANGED', 'CANCELLED', 'REOPENED', 'STATUS_CHANGED')),
  previous_amount numeric(18,2),
  new_amount numeric(18,2),
  previous_due_date date,
  new_due_date date,
  previous_status text,
  new_status text,
  reason text,
  changed_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index pledge_history_tenant_idx on public.pledge_history(tenant_id);
create index pledge_history_event_idx on public.pledge_history(event_id);
create index pledge_history_pledge_idx on public.pledge_history(pledge_id);
create index pledge_history_created_idx on public.pledge_history(created_at desc);

create or replace function public.validate_pledge_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' and (new.tenant_id <> old.tenant_id or new.event_id <> old.event_id or new.event_member_id <> old.event_member_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
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

  if tg_op = 'UPDATE' and new.status <> 'CANCELLED' then
    new.cancelled_at := null;
    new.cancelled_by := null;
    new.cancellation_reason := null;
  end if;

  return new;
end;
$$;

create trigger pledges_integrity_guard
before insert or update on public.pledges
for each row execute function public.validate_pledge_integrity();

create or replace function public.prevent_pledge_history_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'FINANCIAL_HISTORY_APPEND_ONLY' using errcode = '42501';
end;
$$;

create trigger pledge_history_no_update
before update or delete on public.pledge_history
for each row execute function public.prevent_pledge_history_mutation();
