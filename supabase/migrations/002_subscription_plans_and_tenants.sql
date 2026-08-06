create table public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code = upper(code) and code ~ '^[A-Z0-9_]+$'),
  name text not null,
  description text not null,
  currency text not null default 'TZS' check (currency = upper(currency) and length(currency) = 3),
  price_amount numeric(18,2) not null default 0 check (price_amount >= 0),
  billing_interval text not null check (billing_interval in ('MONTHLY', 'QUARTERLY', 'YEARLY', 'CUSTOM')),
  trial_days integer not null default 0 check (trial_days >= 0),
  max_active_events integer not null check (max_active_events >= 0),
  max_members integer not null check (max_members >= 0),
  max_users integer not null check (max_users >= 0),
  included_sms integer not null default 0 check (included_sms >= 0),
  features jsonb not null default '{}'::jsonb,
  is_public boolean not null default true,
  is_active boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger subscription_plans_set_updated_at
before update on public.subscription_plans
for each row execute function public.set_updated_at();

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default public.generate_tenant_code(),
  slug text not null unique,
  name text not null,
  legal_name text,
  phone_e164 text not null check (phone_e164 ~ '^\+255[67][0-9]{8}$'),
  email text,
  country_code text not null default 'TZ' check (country_code = 'TZ'),
  timezone text not null default 'Africa/Dar_es_Salaam',
  currency text not null default 'TZS' check (currency = 'TZS'),
  status text not null default 'TRIAL' check (status in ('TRIAL', 'ACTIVE', 'SUSPENDED', 'EXPIRED', 'CANCELLED', 'ARCHIVED')),
  created_by uuid not null references auth.users(id),
  suspended_at timestamptz,
  suspension_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'SUSPENDED') = (suspended_at is not null) or status <> 'SUSPENDED')
);

create index tenants_status_idx on public.tenants(status);
create index tenants_slug_idx on public.tenants(slug);

create trigger tenants_set_updated_at
before update on public.tenants
for each row execute function public.set_updated_at();

create table public.tenant_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  receipt_prefix text not null default 'AHD',
  sms_sender_name text,
  default_event_type text,
  default_pledge_deadline_days integer check (default_pledge_deadline_days is null or default_pledge_deadline_days >= 0),
  logo_url text,
  primary_color text check (primary_color is null or primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  mobile_money_instructions text,
  bank_payment_instructions text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tenant_settings_set_updated_at
before update on public.tenant_settings
for each row execute function public.set_updated_at();

create table public.tenant_subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null check (status in ('TRIAL', 'ACTIVE', 'PAST_DUE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')),
  starts_at timestamptz not null default now(),
  trial_ends_at timestamptz,
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  plan_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (current_period_end is null or current_period_end >= current_period_start)
);

create unique index tenant_subscriptions_one_current_idx
on public.tenant_subscriptions(tenant_id)
where status in ('TRIAL', 'ACTIVE');

create index tenant_subscriptions_tenant_id_idx on public.tenant_subscriptions(tenant_id);
create index tenant_subscriptions_status_idx on public.tenant_subscriptions(status);
create index tenant_subscriptions_current_period_end_idx on public.tenant_subscriptions(current_period_end);

create trigger tenant_subscriptions_set_updated_at
before update on public.tenant_subscriptions
for each row execute function public.set_updated_at();
