create table public.events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  event_type text not null check (event_type in ('WEDDING', 'SENDOFF', 'FUNERAL', 'FUNDRAISER', 'BIRTHDAY', 'GRADUATION', 'RELIGIOUS', 'OTHER')),
  custom_event_type text,
  description text,
  event_date date,
  venue text,
  target_amount numeric(18,2) check (target_amount is null or target_amount >= 0),
  pledge_deadline date,
  status text not null default 'DRAFT' check (status in ('DRAFT', 'ACTIVE', 'CLOSED', 'CANCELLED', 'ARCHIVED')),
  payment_instructions text,
  created_by uuid not null references auth.users(id),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  check ((event_type = 'OTHER' and custom_event_type is not null) or event_type <> 'OTHER')
);

create index events_tenant_id_idx on public.events(tenant_id);
create index events_status_idx on public.events(status);
create index events_created_by_idx on public.events(created_by);

create trigger events_set_updated_at
before update on public.events
for each row execute function public.set_updated_at();

create table public.event_user_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  tenant_user_id uuid not null references public.tenant_users(id) on delete cascade,
  access_level text not null check (access_level in ('VIEW', 'COLLECT', 'MANAGE')),
  assigned_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (event_id, tenant_user_id)
);

create index event_user_assignments_tenant_id_idx on public.event_user_assignments(tenant_id);
create index event_user_assignments_event_id_idx on public.event_user_assignments(event_id);
create index event_user_assignments_tenant_user_id_idx on public.event_user_assignments(tenant_user_id);

create or replace function public.next_event_code(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  next_number integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text, 42));
  select coalesce(max(substring(code from '[0-9]+$')::integer), 0) + 1
    into next_number
    from public.events
    where tenant_id = p_tenant_id;
  return 'EVT-' || lpad(next_number::text, 4, '0');
end;
$$;

create or replace function public.validate_event_assignment_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.events e
    join public.tenant_users tu on tu.id = new.tenant_user_id
    where e.id = new.event_id
      and e.tenant_id = new.tenant_id
      and tu.tenant_id = new.tenant_id
  ) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger event_assignment_tenant_guard
before insert or update on public.event_user_assignments
for each row execute function public.validate_event_assignment_tenant();
