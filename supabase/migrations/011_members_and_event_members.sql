create table public.tenant_financial_counters (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  next_member_number integer not null default 1 check (next_member_number > 0),
  next_payment_number integer not null default 1 check (next_payment_number > 0),
  next_receipt_number integer not null default 1 check (next_receipt_number > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tenant_financial_counters_set_updated_at
before update on public.tenant_financial_counters
for each row execute function public.set_updated_at();

create table public.members (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  member_code text not null,
  full_name text not null,
  phone_e164 text,
  alternative_phone_e164 text,
  email text,
  gender text check (gender is null or gender in ('MALE', 'FEMALE', 'OTHER', 'NOT_SPECIFIED')),
  location text,
  notes text,
  preferred_language text not null default 'sw' check (preferred_language in ('sw', 'en')),
  sms_enabled boolean not null default true,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE', 'ARCHIVED')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  archived_by uuid references auth.users(id),
  unique (tenant_id, member_code),
  check (btrim(full_name) <> ''),
  check (phone_e164 is null or phone_e164 ~ '^\+255[67][0-9]{8}$'),
  check (alternative_phone_e164 is null or alternative_phone_e164 ~ '^\+255[67][0-9]{8}$'),
  check ((status = 'ARCHIVED') = (archived_at is not null) or status <> 'ARCHIVED')
);

create unique index members_active_phone_unique
on public.members (tenant_id, phone_e164)
where phone_e164 is not null and status = 'ACTIVE';

create index members_tenant_idx on public.members(tenant_id);
create index members_status_idx on public.members(status);
create index members_phone_idx on public.members(tenant_id, phone_e164);
create index members_created_by_idx on public.members(created_by);

create trigger members_set_updated_at
before update on public.members
for each row execute function public.set_updated_at();

create table public.event_member_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  description text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(name) <> '')
);

create unique index event_member_categories_event_name_unique
on public.event_member_categories(event_id, lower(btrim(name)));

create index event_member_categories_tenant_idx on public.event_member_categories(tenant_id);
create index event_member_categories_event_idx on public.event_member_categories(event_id);

create trigger event_member_categories_set_updated_at
before update on public.event_member_categories
for each row execute function public.set_updated_at();

create table public.event_members (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  category_id uuid references public.event_member_categories(id) on delete set null,
  event_member_number text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'REMOVED')),
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  removed_by uuid references auth.users(id),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, member_id),
  check ((status = 'REMOVED') = (removed_at is not null) or status <> 'REMOVED')
);

create index event_members_tenant_idx on public.event_members(tenant_id);
create index event_members_event_idx on public.event_members(event_id);
create index event_members_member_idx on public.event_members(member_id);
create index event_members_status_idx on public.event_members(status);
create index event_members_category_idx on public.event_members(category_id);

create trigger event_members_set_updated_at
before update on public.event_members
for each row execute function public.set_updated_at();

create or replace function public.next_member_code(p_tenant_id uuid)
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
  set next_member_number = next_member_number + 1
  where tenant_id = p_tenant_id
  returning next_member_number - 1 into next_number;

  return 'MBR-' || lpad(next_number::text, 6, '0');
end;
$$;

create or replace function public.validate_member_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' and new.tenant_id <> old.tenant_id then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  new.full_name := btrim(new.full_name);
  new.email := nullif(btrim(coalesce(new.email, '')), '');
  new.phone_e164 := case when new.phone_e164 is null or btrim(new.phone_e164) = '' then null else public.normalize_tz_phone(new.phone_e164) end;
  new.alternative_phone_e164 := case when new.alternative_phone_e164 is null or btrim(new.alternative_phone_e164) = '' then null else public.normalize_tz_phone(new.alternative_phone_e164) end;

  if new.status = 'ARCHIVED' and new.archived_at is null then
    new.archived_at := now();
  end if;
  if new.status <> 'ARCHIVED' then
    new.archived_at := null;
    new.archived_by := null;
  end if;

  return new;
exception
  when unique_violation then
    raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505';
end;
$$;

create trigger members_integrity_guard
before insert or update on public.members
for each row execute function public.validate_member_integrity();

create or replace function public.validate_event_member_category()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1
    from public.events e
    where e.id = new.event_id
      and e.tenant_id = new.tenant_id
  ) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger event_member_categories_tenant_guard
before insert or update on public.event_member_categories
for each row execute function public.validate_event_member_category();

create or replace function public.validate_event_member_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' and (new.tenant_id <> old.tenant_id or new.event_id <> old.event_id or new.member_id <> old.member_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.events e
    join public.members m on m.id = new.member_id
    where e.id = new.event_id
      and e.tenant_id = new.tenant_id
      and m.tenant_id = new.tenant_id
      and m.status <> 'ARCHIVED'
  ) then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  if new.category_id is not null and not exists (
    select 1
    from public.event_member_categories c
    where c.id = new.category_id
      and c.tenant_id = new.tenant_id
      and c.event_id = new.event_id
      and c.is_active
  ) then
    raise exception 'CATEGORY_NOT_FOUND' using errcode = '22023';
  end if;

  if new.status = 'REMOVED' and new.removed_at is null then
    new.removed_at := now();
  end if;
  if new.status = 'ACTIVE' then
    new.removed_at := null;
    new.removed_by := null;
  end if;

  return new;
end;
$$;

create trigger event_members_integrity_guard
before insert or update on public.event_members
for each row execute function public.validate_event_member_integrity();
