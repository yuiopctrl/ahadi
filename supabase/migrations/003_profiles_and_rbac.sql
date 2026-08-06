create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone_e164 text not null check (phone_e164 ~ '^\+255[67][0-9]{8}$'),
  email text,
  avatar_url text,
  status text not null default 'PENDING' check (status in ('PENDING', 'ACTIVE', 'SUSPENDED', 'DISABLED')),
  preferred_language text not null default 'sw' check (preferred_language in ('sw', 'en')),
  onboarding_completed_at timestamptz,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_status_idx on public.profiles(status);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_phone text;
  metadata_name text;
begin
  normalized_phone := public.normalize_tz_phone(coalesce(new.phone, new.raw_user_meta_data ->> 'phone', ''));
  metadata_name := coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '');

  insert into public.profiles (id, full_name, phone_e164, email, status)
  values (new.id, metadata_name, normalized_phone, new.email, 'PENDING')
  on conflict (id) do nothing;

  return new;
exception
  when others then
    insert into public.profiles (id, full_name, phone_e164, email, status)
    values (new.id, '', '+255700000000', new.email, 'PENDING')
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  scope text not null check (scope in ('SYSTEM', 'TENANT')),
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  unique (code),
  check ((scope = 'SYSTEM' and tenant_id is null and is_system) or (scope = 'TENANT'))
);

create index roles_tenant_id_idx on public.roles(tenant_id);
create trigger roles_set_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.tenant_users (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'INVITED' check (status in ('INVITED', 'ACTIVE', 'SUSPENDED', 'REMOVED')),
  is_owner boolean not null default false,
  invited_by uuid references auth.users(id),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);

create index tenant_users_tenant_id_idx on public.tenant_users(tenant_id);
create index tenant_users_user_id_idx on public.tenant_users(user_id);
create index tenant_users_status_idx on public.tenant_users(status);

create trigger tenant_users_set_updated_at
before update on public.tenant_users
for each row execute function public.set_updated_at();

create table public.tenant_user_roles (
  tenant_user_id uuid not null references public.tenant_users(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  assigned_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (tenant_user_id, role_id)
);

create index tenant_user_roles_tenant_user_id_idx on public.tenant_user_roles(tenant_user_id);

create table public.platform_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null check (role in ('PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'SUSPENDED', 'DISABLED')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index platform_users_user_id_idx on public.platform_users(user_id);
create index platform_users_status_idx on public.platform_users(status);

create trigger platform_users_set_updated_at
before update on public.platform_users
for each row execute function public.set_updated_at();

comment on table public.platform_users is
'Bootstrap manually after intended owner authenticates: insert into public.platform_users (user_id, role, status) values (''<auth.users.id>'', ''PLATFORM_OWNER'', ''ACTIVE'');';
