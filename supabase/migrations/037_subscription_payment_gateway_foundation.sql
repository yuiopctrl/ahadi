insert into public.permissions (code, name, description) values
('platform.billing.view', 'View platform billing', 'View SaaS billing and gateway operations'),
('platform.billing.manage', 'Manage platform billing', 'Manage SaaS billing operations'),
('platform.gateway.view', 'View gateways', 'View non-secret payment gateway configuration'),
('platform.gateway.manage', 'Manage gateways', 'Enable or disable payment gateways'),
('platform.reconciliation.view', 'View reconciliation', 'View gateway reconciliation diagnostics')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'platform.billing.view',
  'platform.billing.manage',
  'platform.gateway.view',
  'platform.gateway.manage',
  'platform.reconciliation.view'
)
where r.code in ('PLATFORM_OWNER', 'PLATFORM_ADMIN')
on conflict do nothing;

create table if not exists public.subscription_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  subscription_id uuid not null references public.tenant_subscriptions(id) on delete cascade,
  invoice_number text not null unique,
  purpose text not null default 'MANUAL' check (purpose in ('TRIAL_CONVERSION', 'RENEWAL', 'UPGRADE', 'MANUAL', 'ADJUSTMENT')),
  status text not null default 'ISSUED' check (status in ('DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'VOID', 'OVERDUE')),
  currency text not null default 'TZS' check (currency = upper(currency) and length(currency) = 3),
  subtotal_amount numeric(18,2) not null default 0 check (subtotal_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(18,2) not null default 0 check (total_amount >= 0),
  amount_paid numeric(18,2) not null default 0 check (amount_paid >= 0),
  amount_due numeric(18,2) not null default 0 check (amount_due >= 0),
  due_date date,
  issued_at timestamptz not null default now(),
  paid_at timestamptz,
  voided_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (amount_paid <= total_amount),
  check (amount_due = greatest(total_amount - amount_paid, 0))
);

create index if not exists subscription_invoices_tenant_idx on public.subscription_invoices(tenant_id, created_at desc);
create index if not exists subscription_invoices_subscription_idx on public.subscription_invoices(subscription_id);
create index if not exists subscription_invoices_status_idx on public.subscription_invoices(status);

drop trigger if exists subscription_invoices_set_updated_at on public.subscription_invoices;
create trigger subscription_invoices_set_updated_at
before update on public.subscription_invoices
for each row execute function public.set_updated_at();

create table if not exists public.subscription_invoice_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  invoice_id uuid not null references public.subscription_invoices(id) on delete cascade,
  description text not null,
  quantity numeric(18,2) not null default 1 check (quantity > 0),
  unit_amount numeric(18,2) not null check (unit_amount >= 0),
  total_amount numeric(18,2) not null check (total_amount >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists subscription_invoice_items_invoice_idx on public.subscription_invoice_items(invoice_id);

create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  subscription_id uuid not null references public.tenant_subscriptions(id) on delete cascade,
  payment_number text not null unique,
  payment_method text not null default 'GATEWAY',
  status text not null default 'CONFIRMED' check (status in ('PENDING', 'CONFIRMED', 'REVERSED', 'FAILED')),
  amount numeric(18,2) not null check (amount > 0),
  currency text not null default 'TZS' check (currency = upper(currency) and length(currency) = 3),
  gateway_transaction_id uuid,
  provider text,
  provider_reference text,
  paid_at timestamptz not null default now(),
  reversed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists subscription_payments_tenant_idx on public.subscription_payments(tenant_id, created_at desc);
create index if not exists subscription_payments_subscription_idx on public.subscription_payments(subscription_id);
create unique index if not exists subscription_payments_gateway_transaction_unique
on public.subscription_payments(gateway_transaction_id)
where gateway_transaction_id is not null;

drop trigger if exists subscription_payments_set_updated_at on public.subscription_payments;
create trigger subscription_payments_set_updated_at
before update on public.subscription_payments
for each row execute function public.set_updated_at();

create table if not exists public.subscription_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payment_id uuid not null references public.subscription_payments(id) on delete cascade,
  invoice_id uuid not null references public.subscription_invoices(id) on delete cascade,
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (payment_id, invoice_id)
);

create index if not exists subscription_payment_allocations_invoice_idx on public.subscription_payment_allocations(invoice_id);

create table if not exists public.subscription_payment_intents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  subscription_id uuid not null references public.tenant_subscriptions(id) on delete cascade,
  invoice_id uuid not null references public.subscription_invoices(id) on delete cascade,
  provider text not null,
  payment_method text not null default 'MOBILE_MONEY',
  provider_intent_id text,
  provider_reference text,
  idempotency_key text not null,
  requested_amount numeric(18,2) not null check (requested_amount > 0),
  currency text not null default 'TZS' check (currency = upper(currency) and length(currency) = 3),
  status text not null check (status in ('CREATED', 'PENDING', 'PROCESSING', 'SUCCEEDED', 'FAILED', 'EXPIRED', 'CANCELLED')),
  checkout_url text,
  control_number text,
  expires_at timestamptz,
  initiated_by uuid not null references auth.users(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz
);

create index if not exists subscription_payment_intents_tenant_idx on public.subscription_payment_intents(tenant_id, created_at desc);
create index if not exists subscription_payment_intents_invoice_idx on public.subscription_payment_intents(invoice_id, status);
create unique index if not exists subscription_payment_intents_provider_intent_unique
on public.subscription_payment_intents(provider, provider_intent_id)
where provider_intent_id is not null;
create unique index if not exists subscription_payment_intents_idempotency_unique
on public.subscription_payment_intents(tenant_id, invoice_id, idempotency_key);

drop trigger if exists subscription_payment_intents_set_updated_at on public.subscription_payment_intents;
create trigger subscription_payment_intents_set_updated_at
before update on public.subscription_payment_intents
for each row execute function public.set_updated_at();

create table if not exists public.subscription_gateway_transactions (
  id uuid primary key default gen_random_uuid(),
  payment_intent_id uuid not null references public.subscription_payment_intents(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  invoice_id uuid not null references public.subscription_invoices(id) on delete cascade,
  provider text not null,
  provider_transaction_id text not null,
  provider_reference text,
  transaction_type text not null check (transaction_type in ('PAYMENT', 'REVERSAL', 'REFUND')),
  amount numeric(18,2) not null check (amount >= 0),
  currency text not null default 'TZS' check (currency = upper(currency) and length(currency) = 3),
  status text not null check (status in ('PENDING', 'SUCCESS', 'FAILED', 'REVERSED')),
  paid_at timestamptz,
  payer_phone_masked text,
  raw_event_hash text,
  provider_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists subscription_gateway_transactions_tenant_idx on public.subscription_gateway_transactions(tenant_id, created_at desc);
create index if not exists subscription_gateway_transactions_invoice_idx on public.subscription_gateway_transactions(invoice_id);
create unique index if not exists subscription_gateway_transactions_provider_tx_unique
on public.subscription_gateway_transactions(provider, provider_transaction_id, transaction_type);
create unique index if not exists subscription_gateway_transactions_provider_event_unique
on public.subscription_gateway_transactions(provider, provider_event_id)
where provider_event_id is not null;

drop trigger if exists subscription_gateway_transactions_set_updated_at on public.subscription_gateway_transactions;
create trigger subscription_gateway_transactions_set_updated_at
before update on public.subscription_gateway_transactions
for each row execute function public.set_updated_at();

alter table public.subscription_payments
drop constraint if exists subscription_payments_gateway_transaction_id_fkey;

alter table public.subscription_payments
add constraint subscription_payments_gateway_transaction_id_fkey
foreign key (gateway_transaction_id) references public.subscription_gateway_transactions(id);

create table if not exists public.subscription_gateway_settings (
  provider text primary key,
  enabled boolean not null default false,
  environment text not null default 'SANDBOX' check (environment in ('SANDBOX', 'PRODUCTION')),
  supported_methods text[] not null default array['MOBILE_MONEY']::text[],
  reference_mode text not null default 'PAYMENT_INTENT' check (reference_mode in ('PAYMENT_INTENT', 'INVOICE', 'TENANT', 'PERSISTENT_CUSTOMER')),
  webhook_status text not null default 'UNCONFIGURED',
  last_successful_transaction_at timestamptz,
  last_error_at timestamptz,
  last_error_code text,
  metadata jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_gateway_settings (provider, enabled, environment, supported_methods, reference_mode, webhook_status, metadata)
values
('TEST', true, 'SANDBOX', array['MOBILE_MONEY', 'CONTROL_NUMBER']::text[], 'PAYMENT_INTENT', 'READY', '{"internalTestGateway": true}'::jsonb),
('NMB', false, 'SANDBOX', array['MOBILE_MONEY', 'CONTROL_NUMBER']::text[], 'PAYMENT_INTENT', 'CONTRACT_REQUIRED', '{"providerContractRequired": true}'::jsonb)
on conflict (provider) do update
set supported_methods = excluded.supported_methods,
    reference_mode = excluded.reference_mode,
    updated_at = now();

drop trigger if exists subscription_gateway_settings_set_updated_at on public.subscription_gateway_settings;
create trigger subscription_gateway_settings_set_updated_at
before update on public.subscription_gateway_settings
for each row execute function public.set_updated_at();

create table if not exists private.subscription_gateway_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text,
  signature_valid boolean not null default false,
  payload_hash text not null,
  processing_status text not null default 'RECEIVED' check (processing_status in ('RECEIVED', 'PROCESSING', 'PROCESSED', 'FAILED', 'IGNORED')),
  attempts integer not null default 0,
  last_error_code text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create unique index if not exists subscription_gateway_webhook_events_hash_unique
on private.subscription_gateway_webhook_events(provider, payload_hash);
create unique index if not exists subscription_gateway_webhook_events_provider_event_unique
on private.subscription_gateway_webhook_events(provider, provider_event_id)
where provider_event_id is not null;

revoke all on private.subscription_gateway_webhook_events from public;
revoke all on private.subscription_gateway_webhook_events from anon, authenticated;

alter table public.subscription_invoices enable row level security;
alter table public.subscription_invoice_items enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.subscription_payment_allocations enable row level security;
alter table public.subscription_payment_intents enable row level security;
alter table public.subscription_gateway_transactions enable row level security;
alter table public.subscription_gateway_settings enable row level security;

drop policy if exists subscription_invoices_tenant_view on public.subscription_invoices;
create policy subscription_invoices_tenant_view on public.subscription_invoices
for select using (public.has_tenant_permission(tenant_id, 'tenant.subscription.view') or public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_invoice_items_tenant_view on public.subscription_invoice_items;
create policy subscription_invoice_items_tenant_view on public.subscription_invoice_items
for select using (public.has_tenant_permission(tenant_id, 'tenant.subscription.view') or public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_payments_tenant_view on public.subscription_payments;
create policy subscription_payments_tenant_view on public.subscription_payments
for select using (public.has_tenant_permission(tenant_id, 'tenant.subscription.view') or public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_payment_allocations_tenant_view on public.subscription_payment_allocations;
create policy subscription_payment_allocations_tenant_view on public.subscription_payment_allocations
for select using (public.has_tenant_permission(tenant_id, 'tenant.subscription.view') or public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_payment_intents_tenant_view on public.subscription_payment_intents;
create policy subscription_payment_intents_tenant_view on public.subscription_payment_intents
for select using (public.has_tenant_permission(tenant_id, 'tenant.subscription.view') or public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_gateway_transactions_platform_view on public.subscription_gateway_transactions;
create policy subscription_gateway_transactions_platform_view on public.subscription_gateway_transactions
for select using (public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_gateway_settings_platform_view on public.subscription_gateway_settings;
create policy subscription_gateway_settings_platform_view on public.subscription_gateway_settings
for select using (public.has_platform_permission('platform.gateway.view') or public.has_platform_permission('platform.billing.view'));
drop policy if exists subscription_gateway_settings_platform_manage on public.subscription_gateway_settings;
create policy subscription_gateway_settings_platform_manage on public.subscription_gateway_settings
for update using (public.has_platform_permission('platform.gateway.manage'))
with check (public.has_platform_permission('platform.gateway.manage'));

create or replace function public.subscription_gateway_capabilities()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'provider', provider,
    'enabled', enabled,
    'environment', environment,
    'supportedMethods', supported_methods,
    'referenceMode', reference_mode,
    'webhookStatus', webhook_status,
    'lastSuccessfulTransactionAt', last_successful_transaction_at,
    'lastErrorAt', last_error_at,
    'lastErrorCode', last_error_code,
    'metadata', metadata
  ) order by provider), '[]'::jsonb)
  from public.subscription_gateway_settings;
$$;

create or replace function public.rpc_get_tenant_billing_summary(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'subscription', public.subscription_context_json(p_tenant_id),
    'invoices', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.created_at desc)
      from public.subscription_invoices i
      where i.tenant_id = p_tenant_id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.created_at desc)
      from public.subscription_payments p
      where p.tenant_id = p_tenant_id
    ), '[]'::jsonb),
    'pendingIntents', coalesce((
      select jsonb_agg(to_jsonb(pi) order by pi.created_at desc)
      from public.subscription_payment_intents pi
      where pi.tenant_id = p_tenant_id
        and pi.status in ('CREATED', 'PENDING', 'PROCESSING')
    ), '[]'::jsonb),
    'gateways', public.subscription_gateway_capabilities()
  )
  where public.has_tenant_permission(p_tenant_id, 'tenant.subscription.view');
$$;

create or replace function public.rpc_get_subscription_payment_intent(p_intent_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'id', pi.id,
    'tenantId', pi.tenant_id,
    'invoiceId', pi.invoice_id,
    'invoiceNumber', i.invoice_number,
    'provider', pi.provider,
    'paymentMethod', pi.payment_method,
    'status', case when pi.status in ('PENDING', 'PROCESSING') and pi.expires_at is not null and pi.expires_at < now() then 'EXPIRED' else pi.status end,
    'amount', pi.requested_amount,
    'currency', pi.currency,
    'checkoutUrl', pi.checkout_url,
    'controlNumber', pi.control_number,
    'paymentInstructions', pi.metadata ->> 'paymentInstructions',
    'expiresAt', pi.expires_at,
    'lastCheckedAt', now(),
    'invoiceStatus', i.status
  )
  from public.subscription_payment_intents pi
  join public.subscription_invoices i on i.id = pi.invoice_id
  where pi.id = p_intent_id
    and public.has_tenant_permission(pi.tenant_id, 'tenant.subscription.view');
$$;

create or replace function public.rpc_create_subscription_payment_intent(
  p_tenant_id uuid,
  p_invoice_id uuid,
  p_provider text,
  p_payment_method text,
  p_provider_intent_id text,
  p_provider_reference text,
  p_idempotency_key text,
  p_checkout_url text default null,
  p_control_number text default null,
  p_expires_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invoice_record public.subscription_invoices%rowtype;
  gateway_record public.subscription_gateway_settings%rowtype;
  intent_record public.subscription_payment_intents%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'tenant.subscription.manage') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  select * into invoice_record
  from public.subscription_invoices
  where id = p_invoice_id and tenant_id = p_tenant_id
  for update;

  if not found or invoice_record.status in ('VOID', 'PAID') or invoice_record.amount_due <= 0 then
    raise exception 'INVOICE_NOT_PAYABLE' using errcode = '22023';
  end if;

  select * into gateway_record
  from public.subscription_gateway_settings
  where provider = upper(p_provider)
  for update;

  if not found or gateway_record.enabled is not true then
    raise exception 'PAYMENT_GATEWAY_DISABLED' using errcode = '22023';
  end if;
  if not (upper(p_payment_method) = any(gateway_record.supported_methods)) then
    raise exception 'PAYMENT_PROVIDER_UNAVAILABLE' using errcode = '22023';
  end if;

  insert into public.subscription_payment_intents (
    tenant_id,
    subscription_id,
    invoice_id,
    provider,
    payment_method,
    provider_intent_id,
    provider_reference,
    idempotency_key,
    requested_amount,
    currency,
    status,
    checkout_url,
    control_number,
    expires_at,
    initiated_by,
    metadata
  )
  values (
    p_tenant_id,
    invoice_record.subscription_id,
    invoice_record.id,
    gateway_record.provider,
    upper(p_payment_method),
    p_provider_intent_id,
    p_provider_reference,
    p_idempotency_key,
    invoice_record.amount_due,
    invoice_record.currency,
    'PENDING',
    p_checkout_url,
    p_control_number,
    p_expires_at,
    auth.uid(),
    p_metadata
  )
  on conflict (tenant_id, invoice_id, idempotency_key) do update
  set updated_at = now()
  returning * into intent_record;

  perform public.write_audit_log(p_tenant_id, 'SUBSCRIPTION_PAYMENT_INTENT_CREATED', 'subscription_payment_intent', intent_record.id, null, null, to_jsonb(intent_record));

  return public.rpc_get_subscription_payment_intent(intent_record.id);
end;
$$;

create or replace function public.rpc_confirm_subscription_gateway_payment(
  p_provider text,
  p_provider_intent_id text,
  p_provider_transaction_id text,
  p_provider_reference text,
  p_provider_event_id text,
  p_amount numeric,
  p_currency text,
  p_status text,
  p_paid_at timestamptz,
  p_payload_hash text default null,
  p_payer_phone_masked text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  intent_record public.subscription_payment_intents%rowtype;
  invoice_record public.subscription_invoices%rowtype;
  gateway_tx_id uuid;
  payment_id uuid;
  payment_number text;
  allocated_amount numeric(18,2);
  webhook_event_id uuid;
begin
  insert into private.subscription_gateway_webhook_events (
    provider,
    provider_event_id,
    signature_valid,
    payload_hash,
    processing_status,
    attempts
  )
  values (
    upper(p_provider),
    nullif(p_provider_event_id, ''),
    true,
    coalesce(nullif(p_payload_hash, ''), encode(digest(upper(p_provider) || ':' || coalesce(p_provider_intent_id, '') || ':' || coalesce(p_provider_transaction_id, ''), 'sha256'), 'hex')),
    'PROCESSING',
    1
  )
  on conflict (provider, payload_hash) do update
  set attempts = private.subscription_gateway_webhook_events.attempts + 1,
      processing_status = case
        when private.subscription_gateway_webhook_events.processing_status = 'PROCESSED' then 'IGNORED'
        else 'PROCESSING'
      end,
      last_error_code = null
  returning id into webhook_event_id;

  select * into intent_record
  from public.subscription_payment_intents
  where provider = upper(p_provider)
    and provider_intent_id = p_provider_intent_id
  for update;

  if not found then
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_TRANSACTION_UNKNOWN', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_TRANSACTION_UNKNOWN', 'provider', upper(p_provider), 'providerIntentId', p_provider_intent_id);
  end if;

  select * into invoice_record
  from public.subscription_invoices
  where id = intent_record.invoice_id
  for update;

  if intent_record.status = 'SUCCEEDED' then
    update private.subscription_gateway_webhook_events
    set processing_status = 'IGNORED', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'DUPLICATE', 'intentId', intent_record.id, 'invoiceId', intent_record.invoice_id);
  end if;
  if upper(p_currency) <> intent_record.currency then
    update public.subscription_payment_intents set status = 'FAILED', failed_at = now(), metadata = metadata || jsonb_build_object('failureCode', 'PAYMENT_CURRENCY_MISMATCH') where id = intent_record.id;
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_CURRENCY_MISMATCH', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_CURRENCY_MISMATCH', 'intentId', intent_record.id, 'expectedCurrency', intent_record.currency, 'providerCurrency', upper(p_currency));
  end if;
  if p_amount <> intent_record.requested_amount then
    update public.subscription_payment_intents set status = 'FAILED', failed_at = now(), metadata = metadata || jsonb_build_object('failureCode', 'PAYMENT_AMOUNT_MISMATCH', 'providerAmount', p_amount) where id = intent_record.id;
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_AMOUNT_MISMATCH', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_AMOUNT_MISMATCH', 'intentId', intent_record.id, 'expectedAmount', intent_record.requested_amount, 'providerAmount', p_amount);
  end if;
  if upper(p_status) <> 'SUCCESS' then
    update public.subscription_payment_intents set status = 'FAILED', failed_at = now(), metadata = metadata || jsonb_build_object('failureCode', upper(p_status)) where id = intent_record.id;
    perform public.write_audit_log(intent_record.tenant_id, 'SUBSCRIPTION_GATEWAY_PAYMENT_FAILED', 'subscription_payment_intent', intent_record.id, null, null, jsonb_build_object('providerStatus', p_status));
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = upper(p_status), processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'FAILED', 'intentId', intent_record.id);
  end if;

  insert into public.subscription_gateway_transactions (
    payment_intent_id,
    tenant_id,
    invoice_id,
    provider,
    provider_transaction_id,
    provider_reference,
    transaction_type,
    amount,
    currency,
    status,
    paid_at,
    payer_phone_masked,
    raw_event_hash,
    provider_event_id
  )
  values (
    intent_record.id,
    intent_record.tenant_id,
    intent_record.invoice_id,
    intent_record.provider,
    p_provider_transaction_id,
    p_provider_reference,
    'PAYMENT',
    p_amount,
    upper(p_currency),
    'SUCCESS',
    coalesce(p_paid_at, now()),
    p_payer_phone_masked,
    p_payload_hash,
    p_provider_event_id
  )
  on conflict (provider, provider_transaction_id, transaction_type) do update
  set updated_at = now()
  returning id into gateway_tx_id;

  if exists (select 1 from public.subscription_payments where gateway_transaction_id = gateway_tx_id) then
    update public.subscription_payment_intents set status = 'SUCCEEDED', completed_at = coalesce(completed_at, now()) where id = intent_record.id;
    update private.subscription_gateway_webhook_events
    set processing_status = 'IGNORED', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'DUPLICATE', 'intentId', intent_record.id, 'gatewayTransactionId', gateway_tx_id);
  end if;

  payment_number := 'SUBPAY-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  insert into public.subscription_payments (
    tenant_id,
    subscription_id,
    payment_number,
    payment_method,
    status,
    amount,
    currency,
    gateway_transaction_id,
    provider,
    provider_reference,
    paid_at,
    metadata
  )
  values (
    intent_record.tenant_id,
    intent_record.subscription_id,
    payment_number,
    'GATEWAY',
    'CONFIRMED',
    p_amount,
    upper(p_currency),
    gateway_tx_id,
    intent_record.provider,
    p_provider_reference,
    coalesce(p_paid_at, now()),
    jsonb_build_object('paymentIntentId', intent_record.id, 'providerTransactionId', p_provider_transaction_id)
  )
  returning id into payment_id;

  allocated_amount := least(p_amount, invoice_record.amount_due);
  insert into public.subscription_payment_allocations (tenant_id, payment_id, invoice_id, amount)
  values (intent_record.tenant_id, payment_id, invoice_record.id, allocated_amount);

  update public.subscription_invoices
  set amount_paid = amount_paid + allocated_amount,
      amount_due = greatest(total_amount - (amount_paid + allocated_amount), 0),
      status = case when amount_paid + allocated_amount >= total_amount then 'PAID' else 'PARTIALLY_PAID' end,
      paid_at = case when amount_paid + allocated_amount >= total_amount then coalesce(p_paid_at, now()) else paid_at end
  where id = invoice_record.id;

  update public.tenant_subscriptions
  set status = case when status = 'TRIAL' and invoice_record.purpose = 'TRIAL_CONVERSION' then 'ACTIVE' else status end,
      current_period_start = case when invoice_record.purpose in ('RENEWAL', 'TRIAL_CONVERSION') then now() else current_period_start end,
      current_period_end = case
        when invoice_record.purpose in ('RENEWAL', 'TRIAL_CONVERSION') then
          case coalesce(plan_snapshot ->> 'billing_interval', 'MONTHLY')
            when 'QUARTERLY' then now() + interval '3 months'
            when 'YEARLY' then now() + interval '1 year'
            else now() + interval '1 month'
          end
        else current_period_end
      end
  where id = intent_record.subscription_id;

  update public.subscription_payment_intents
  set status = 'SUCCEEDED', completed_at = coalesce(p_paid_at, now())
  where id = intent_record.id;

  update public.subscription_gateway_settings
  set last_successful_transaction_at = now(), last_error_at = null, last_error_code = null
  where provider = intent_record.provider;

  perform public.write_audit_log(intent_record.tenant_id, 'SUBSCRIPTION_GATEWAY_PAYMENT_CONFIRMED', 'subscription_payment', payment_id, null, null, jsonb_build_object('invoiceId', invoice_record.id, 'gatewayTransactionId', gateway_tx_id));

  update private.subscription_gateway_webhook_events
  set processing_status = 'PROCESSED', processed_at = now()
  where id = webhook_event_id;

  return jsonb_build_object(
    'status', 'PROCESSED',
    'intentId', intent_record.id,
    'gatewayTransactionId', gateway_tx_id,
    'subscriptionPaymentId', payment_id,
    'invoiceId', invoice_record.id
  );
end;
$$;

create or replace function public.rpc_confirm_subscription_gateway_reversal(
  p_provider text,
  p_provider_transaction_id text,
  p_provider_event_id text,
  p_amount numeric,
  p_currency text,
  p_reversed_at timestamptz,
  p_payload_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  original_tx public.subscription_gateway_transactions%rowtype;
  payment_record public.subscription_payments%rowtype;
  invoice_record public.subscription_invoices%rowtype;
  reversed_amount numeric(18,2);
  reversal_tx_id uuid;
  webhook_event_id uuid;
begin
  insert into private.subscription_gateway_webhook_events (
    provider,
    provider_event_id,
    signature_valid,
    payload_hash,
    processing_status,
    attempts
  )
  values (
    upper(p_provider),
    nullif(p_provider_event_id, ''),
    true,
    coalesce(nullif(p_payload_hash, ''), encode(digest(upper(p_provider) || ':REVERSAL:' || coalesce(p_provider_transaction_id, ''), 'sha256'), 'hex')),
    'PROCESSING',
    1
  )
  on conflict (provider, payload_hash) do update
  set attempts = private.subscription_gateway_webhook_events.attempts + 1,
      processing_status = case
        when private.subscription_gateway_webhook_events.processing_status = 'PROCESSED' then 'IGNORED'
        else 'PROCESSING'
      end,
      last_error_code = null
  returning id into webhook_event_id;

  select * into original_tx
  from public.subscription_gateway_transactions
  where provider = upper(p_provider)
    and provider_transaction_id = p_provider_transaction_id
    and transaction_type = 'PAYMENT'
  for update;

  if not found then
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_TRANSACTION_UNKNOWN', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_TRANSACTION_UNKNOWN', 'provider', upper(p_provider), 'providerTransactionId', p_provider_transaction_id);
  end if;

  if upper(p_currency) <> original_tx.currency then
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_CURRENCY_MISMATCH', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_CURRENCY_MISMATCH', 'gatewayTransactionId', original_tx.id);
  end if;

  if p_amount <> original_tx.amount then
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_AMOUNT_MISMATCH', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_AMOUNT_MISMATCH', 'gatewayTransactionId', original_tx.id);
  end if;

  insert into public.subscription_gateway_transactions (
    payment_intent_id,
    tenant_id,
    invoice_id,
    provider,
    provider_transaction_id,
    provider_reference,
    transaction_type,
    amount,
    currency,
    status,
    paid_at,
    raw_event_hash,
    provider_event_id
  )
  values (
    original_tx.payment_intent_id,
    original_tx.tenant_id,
    original_tx.invoice_id,
    original_tx.provider,
    original_tx.provider_transaction_id,
    original_tx.provider_reference,
    'REVERSAL',
    p_amount,
    upper(p_currency),
    'REVERSED',
    coalesce(p_reversed_at, now()),
    p_payload_hash,
    p_provider_event_id
  )
  on conflict (provider, provider_transaction_id, transaction_type) do update
  set updated_at = now()
  returning id into reversal_tx_id;

  select * into payment_record
  from public.subscription_payments
  where gateway_transaction_id = original_tx.id
  for update;

  if not found then
    update private.subscription_gateway_webhook_events
    set processing_status = 'FAILED', last_error_code = 'PAYMENT_TRANSACTION_UNKNOWN', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'REQUIRES_REVIEW', 'code', 'PAYMENT_TRANSACTION_UNKNOWN', 'gatewayTransactionId', original_tx.id);
  end if;

  if payment_record.status = 'REVERSED' then
    update private.subscription_gateway_webhook_events
    set processing_status = 'IGNORED', processed_at = now()
    where id = webhook_event_id;
    return jsonb_build_object('status', 'DUPLICATE', 'gatewayTransactionId', original_tx.id, 'reversalGatewayTransactionId', reversal_tx_id);
  end if;

  select coalesce(sum(amount), 0) into reversed_amount
  from public.subscription_payment_allocations
  where payment_id = payment_record.id
    and invoice_id = original_tx.invoice_id;

  select * into invoice_record
  from public.subscription_invoices
  where id = original_tx.invoice_id
  for update;

  update public.subscription_payments
  set status = 'REVERSED',
      reversed_at = coalesce(p_reversed_at, now()),
      metadata = metadata || jsonb_build_object('reversalGatewayTransactionId', reversal_tx_id)
  where id = payment_record.id;

  update public.subscription_invoices
  set amount_paid = greatest(amount_paid - reversed_amount, 0),
      amount_due = greatest(total_amount - greatest(amount_paid - reversed_amount, 0), 0),
      status = case
        when greatest(amount_paid - reversed_amount, 0) <= 0 then 'ISSUED'
        when greatest(amount_paid - reversed_amount, 0) >= total_amount then 'PAID'
        else 'PARTIALLY_PAID'
      end,
      paid_at = case when greatest(amount_paid - reversed_amount, 0) >= total_amount then paid_at else null end
  where id = invoice_record.id;

  update public.tenant_subscriptions
  set status = case
    when status = 'ACTIVE' and invoice_record.purpose in ('TRIAL_CONVERSION', 'RENEWAL', 'UPGRADE') then 'PAST_DUE'
    else status
  end
  where id = invoice_record.subscription_id;

  update private.subscription_gateway_webhook_events
  set processing_status = 'PROCESSED', processed_at = now()
  where id = webhook_event_id;

  perform public.write_audit_log(original_tx.tenant_id, 'SUBSCRIPTION_GATEWAY_PAYMENT_REVERSED', 'subscription_payment', payment_record.id, null, null, jsonb_build_object('invoiceId', invoice_record.id, 'gatewayTransactionId', original_tx.id, 'reversalGatewayTransactionId', reversal_tx_id));

  return jsonb_build_object(
    'status', 'PROCESSED',
    'gatewayTransactionId', original_tx.id,
    'reversalGatewayTransactionId', reversal_tx_id,
    'subscriptionPaymentId', payment_record.id,
    'invoiceId', invoice_record.id
  );
end;
$$;

create or replace function public.rpc_get_platform_gateway_settings()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.subscription_gateway_capabilities()
  where public.has_platform_permission('platform.gateway.view') or public.has_platform_permission('platform.billing.view');
$$;

create or replace function public.rpc_get_platform_gateway_reconciliation()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(row_to_json(rows) order by created_at desc), '[]'::jsonb)
  from (
    select
      gt.id,
      gt.created_at,
      gt.provider,
      gt.provider_transaction_id,
      gt.provider_reference,
      gt.amount,
      gt.currency,
      gt.status as gateway_status,
      i.invoice_number,
      i.status as invoice_status,
      p.id as subscription_payment_id,
      case
        when p.id is null and gt.status = 'SUCCESS' then 'UNMATCHED'
        when p.amount is distinct from gt.amount then 'MISMATCH'
        when i.status not in ('PAID', 'PARTIALLY_PAID') and gt.status = 'SUCCESS' then 'REQUIRES_REVIEW'
        else 'MATCHED'
      end as reconciliation_status
    from public.subscription_gateway_transactions gt
    join public.subscription_invoices i on i.id = gt.invoice_id
    left join public.subscription_payments p on p.gateway_transaction_id = gt.id
  ) rows
  where public.has_platform_permission('platform.reconciliation.view') or public.has_platform_permission('platform.billing.view');
$$;

grant execute on function public.subscription_gateway_capabilities() to authenticated;
grant execute on function public.rpc_get_tenant_billing_summary(uuid) to authenticated;
grant execute on function public.rpc_get_subscription_payment_intent(uuid) to authenticated;
grant execute on function public.rpc_create_subscription_payment_intent(uuid, uuid, text, text, text, text, text, text, text, timestamptz, jsonb) to authenticated;
grant execute on function public.rpc_confirm_subscription_gateway_payment(text, text, text, text, text, numeric, text, text, timestamptz, text, text) to anon, authenticated;
grant execute on function public.rpc_confirm_subscription_gateway_reversal(text, text, text, numeric, text, timestamptz, text) to anon, authenticated;
grant execute on function public.rpc_get_platform_gateway_settings() to authenticated;
grant execute on function public.rpc_get_platform_gateway_reconciliation() to authenticated;

notify pgrst, 'reload schema';
