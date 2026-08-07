insert into public.permissions (code, name, description) values
('messages.view', 'View messages', 'View tenant SMS message history'),
('messages.send', 'Send messages', 'Send or resend tenant SMS messages')
on conflict (code) do update set name = excluded.name, description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('messages.view', 'messages.send')
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'messages.view'
where r.code in ('COLLECTOR', 'VIEWER')
on conflict do nothing;

create table if not exists public.sms_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  channel text not null default 'SMS' check (channel = 'SMS'),
  body text not null,
  language text not null default 'sw' check (language in ('sw', 'en')),
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(code) <> ''),
  check (btrim(name) <> ''),
  check (btrim(body) <> '')
);

create unique index if not exists sms_templates_tenant_code_language_unique
on public.sms_templates(coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language);

create trigger sms_templates_set_updated_at
before update on public.sms_templates
for each row execute function public.set_updated_at();

insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active)
values (
  null,
  'PAYMENT_CONFIRMATION',
  'Payment confirmation',
  'SMS',
  'Ndugu {{member_name}}, tumepokea TZS {{payment_amount}} kwa ajili ya {{event_name}} kupitia {{payment_method}}. Jumla uliyolipa ni TZS {{total_paid}} na salio la ahadi ni TZS {{outstanding}}. Risiti: {{receipt_number}}. Asante.',
  'sw',
  true,
  true
)
on conflict do nothing;

create table if not exists public.sms_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  member_id uuid references public.members(id) on delete set null,
  event_member_id uuid references public.event_members(id) on delete set null,
  payment_id uuid references public.payments(id) on delete set null,
  receipt_id uuid references public.receipts(id) on delete set null,
  template_code text,
  phone_e164 text not null,
  message_body text not null,
  status text not null default 'QUEUED' check (status in ('QUEUED', 'PROCESSING', 'SENT', 'DELIVERED', 'FAILED', 'CANCELLED')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 3 check (max_attempts > 0),
  next_attempt_at timestamptz not null default now(),
  processing_started_at timestamptz,
  last_error_code text,
  last_error_message text,
  provider_message_id text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  check (phone_e164 ~ '^\+255[67][0-9]{8}$'),
  check (btrim(message_body) <> '')
);

create index if not exists sms_outbox_status_idx on public.sms_outbox(status);
create index if not exists sms_outbox_next_attempt_idx on public.sms_outbox(next_attempt_at);
create index if not exists sms_outbox_tenant_idx on public.sms_outbox(tenant_id);
create index if not exists sms_outbox_member_idx on public.sms_outbox(member_id);
create index if not exists sms_outbox_payment_idx on public.sms_outbox(payment_id);
create unique index if not exists sms_outbox_idempotency_active_unique
on public.sms_outbox(idempotency_key)
where idempotency_key is not null and status <> 'CANCELLED';
create unique index if not exists sms_outbox_payment_confirmation_unique
on public.sms_outbox(payment_id, template_code)
where payment_id is not null and template_code = 'PAYMENT_CONFIRMATION' and status <> 'CANCELLED';

create trigger sms_outbox_set_updated_at
before update on public.sms_outbox
for each row execute function public.set_updated_at();

alter table public.sms_templates enable row level security;
alter table public.sms_outbox enable row level security;

drop policy if exists sms_templates_select on public.sms_templates;
create policy sms_templates_select on public.sms_templates
for select using (is_system or (tenant_id is not null and public.has_tenant_permission(tenant_id, 'messages.view')));

drop policy if exists sms_outbox_select on public.sms_outbox;
create policy sms_outbox_select on public.sms_outbox
for select using (public.has_tenant_permission(tenant_id, 'messages.view'));

create or replace function public.render_sms_template(p_body text, p_variables jsonb)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rendered text := p_body;
  variable record;
begin
  for variable in select key, value from jsonb_each_text(coalesce(p_variables, '{}'::jsonb)) loop
    rendered := replace(rendered, '{{' || variable.key || '}}', variable.value);
    rendered := replace(rendered, '{{ ' || variable.key || ' }}', variable.value);
  end loop;
  return rendered;
end;
$$;

create or replace function public.format_tzs_sms_amount(p_amount numeric)
returns text
language sql
stable
as $$
  select trim(to_char(coalesce(p_amount, 0), 'FM999G999G999G999G999G990'));
$$;

create or replace function public.payment_method_sms_name(p_method text)
returns text
language sql
stable
as $$
  select case p_method
    when 'CASH' then 'Cash'
    when 'M_PESA' then 'M-Pesa'
    when 'AIRTEL_MONEY' then 'Airtel Money'
    when 'MIX_BY_YAS' then 'Mixx by Yas'
    when 'HALOPESA' then 'Halopesa'
    when 'BANK_TRANSFER' then 'Bank Transfer'
    when 'CHEQUE' then 'Cheque'
    when 'OTHER' then 'Other'
    else initcap(replace(coalesce(p_method, ''), '_', ' '))
  end;
$$;

create or replace function public.rpc_enqueue_payment_confirmation_sms(p_tenant_id uuid, p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  payment_record public.payments%rowtype;
  member_record public.members%rowtype;
  event_record public.events%rowtype;
  receipt_record public.receipts%rowtype;
  template_body text;
  message text;
  outbox_id uuid;
  idempotency text;
  total_paid numeric(18,2);
  outstanding numeric(18,2);
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into payment_record
  from public.payments
  where id = p_payment_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;
  if not public.has_event_financial_access(payment_record.tenant_id, payment_record.event_id, 'payments.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if payment_record.status = 'REVERSED' then
    return jsonb_build_object('smsQueued', false, 'reason', 'PAYMENT_REVERSED');
  end if;

  select m.* into member_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = payment_record.event_member_id
    and em.tenant_id = p_tenant_id
    and em.event_id = payment_record.event_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  if member_record.phone_e164 is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'NO_PHONE');
  end if;
  if member_record.sms_enabled = false then
    return jsonb_build_object('smsQueued', false, 'reason', 'SMS_DISABLED');
  end if;

  select * into event_record from public.events where id = payment_record.event_id and tenant_id = p_tenant_id;
  select * into receipt_record from public.receipts where payment_id = payment_record.id and tenant_id = p_tenant_id;
  if receipt_record.id is null then
    raise exception 'RECEIPT_NOT_FOUND' using errcode = '22023';
  end if;

  idempotency := 'PAYMENT_CONFIRMATION:' || payment_record.id::text;
  select id into outbox_id
  from public.sms_outbox
  where idempotency_key = idempotency
    and status <> 'CANCELLED';
  if found then
    return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED');
  end if;

  select body into template_body
  from public.sms_templates
  where code = 'PAYMENT_CONFIRMATION'
    and channel = 'SMS'
    and language = coalesce(member_record.preferred_language, 'sw')
    and is_active
    and (tenant_id = p_tenant_id or tenant_id is null)
  order by tenant_id nulls last
  limit 1;
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;

  total_paid := coalesce((
    select sum(pa.allocated_amount)
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where p.event_member_id = payment_record.event_member_id
      and p.status = 'CONFIRMED'
  ), 0)::numeric(18,2);

  outstanding := coalesce((
    select sum(greatest(pl.pledged_amount - public.confirmed_pledge_allocated_amount(pl.id), 0))
    from public.pledges pl
    where pl.event_member_id = payment_record.event_member_id
      and pl.status <> 'CANCELLED'
  ), 0)::numeric(18,2);

  message := public.render_sms_template(template_body, jsonb_build_object(
    'member_name', member_record.full_name,
    'payment_amount', public.format_tzs_sms_amount(payment_record.amount),
    'event_name', event_record.name,
    'payment_method', public.payment_method_sms_name(payment_record.payment_method),
    'total_paid', public.format_tzs_sms_amount(total_paid),
    'outstanding', public.format_tzs_sms_amount(outstanding),
    'receipt_number', receipt_record.receipt_number
  ));

  insert into public.sms_outbox (
    tenant_id, event_id, member_id, event_member_id, payment_id, receipt_id, template_code,
    phone_e164, message_body, status, idempotency_key
  )
  values (
    p_tenant_id, payment_record.event_id, member_record.id, payment_record.event_member_id, payment_record.id, receipt_record.id, 'PAYMENT_CONFIRMATION',
    member_record.phone_e164, message, 'QUEUED', idempotency
  )
  returning id into outbox_id;

  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id);
exception
  when unique_violation then
    select id into outbox_id
    from public.sms_outbox
    where idempotency_key = idempotency
      and status <> 'CANCELLED';
    return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED');
end;
$$;

create or replace function public.rpc_list_sms_history(p_tenant_id uuid)
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
  if not public.has_tenant_permission(p_tenant_id, 'messages.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      o.id,
      o.tenant_id,
      o.event_id,
      e.name as event_name,
      o.member_id,
      m.full_name as member_name,
      o.payment_id,
      o.receipt_id,
      o.template_code,
      o.phone_e164,
      o.status,
      o.attempt_count,
      o.created_at,
      o.sent_at,
      o.delivered_at,
      o.failed_at,
      o.last_error_code,
      o.last_error_message
    from public.sms_outbox o
    left join public.events e on e.id = o.event_id
    left join public.members m on m.id = o.member_id
    where o.tenant_id = p_tenant_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_claim_sms_outbox(p_batch_size integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  with candidates as (
    select o.id
    from public.sms_outbox o
    left join public.payments p on p.id = o.payment_id
    where o.status in ('QUEUED', 'FAILED')
      and o.next_attempt_at <= now()
      and o.attempt_count < o.max_attempts
      and (o.payment_id is null or p.status <> 'REVERSED')
    order by o.next_attempt_at, o.created_at
    limit greatest(1, least(coalesce(p_batch_size, 10), 50))
    for update of o skip locked
  ),
  claimed as (
    update public.sms_outbox o
    set status = 'PROCESSING',
        processing_started_at = now(),
        attempt_count = attempt_count + 1,
        last_error_code = null,
        last_error_message = null
    from candidates c
    where o.id = c.id
    returning o.id, o.tenant_id, o.event_id, o.member_id, o.payment_id, o.receipt_id, o.template_code, o.phone_e164, o.message_body, o.status, o.attempt_count, o.max_attempts
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb)
  into result
  from claimed;

  return result;
end;
$$;

create or replace function public.rpc_mark_sms_sent(p_outbox_id uuid, p_provider_message_id text default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.sms_outbox
  set status = 'SENT',
      provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
      sent_at = now(),
      failed_at = null,
      processing_started_at = null
  where id = p_outbox_id
    and status = 'PROCESSING';
end;
$$;

create or replace function public.rpc_mark_sms_failed(p_outbox_id uuid, p_error_code text, p_error_message text, p_retryable boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  row_attempt_count integer;
  row_max_attempts integer;
  delay interval;
begin
  select attempt_count, max_attempts into row_attempt_count, row_max_attempts
  from public.sms_outbox
  where id = p_outbox_id
    and status = 'PROCESSING';
  if not found then
    return;
  end if;

  delay := case
    when row_attempt_count <= 1 then interval '2 minutes'
    when row_attempt_count = 2 then interval '10 minutes'
    else interval '10 minutes'
  end;

  update public.sms_outbox
  set status = case when p_retryable and row_attempt_count < row_max_attempts then 'QUEUED' else 'FAILED' end,
      next_attempt_at = case when p_retryable and row_attempt_count < row_max_attempts then now() + delay else next_attempt_at end,
      failed_at = case when p_retryable and row_attempt_count < row_max_attempts then null else now() end,
      processing_started_at = null,
      last_error_code = left(coalesce(p_error_code, 'SMS_PROVIDER_FAILED'), 80),
      last_error_message = left(coalesce(p_error_message, 'SMS provider failed'), 160)
  where id = p_outbox_id;
end;
$$;

grant select on public.sms_templates, public.sms_outbox to authenticated;
grant execute on function public.render_sms_template(text, jsonb) to authenticated;
grant execute on function public.format_tzs_sms_amount(numeric) to authenticated;
grant execute on function public.payment_method_sms_name(text) to authenticated;
grant execute on function public.rpc_enqueue_payment_confirmation_sms(uuid, uuid) to authenticated;
grant execute on function public.rpc_list_sms_history(uuid) to authenticated;
grant execute on function public.rpc_claim_sms_outbox(integer) to authenticated;
grant execute on function public.rpc_mark_sms_sent(uuid, text) to authenticated;
grant execute on function public.rpc_mark_sms_failed(uuid, text, text, boolean) to authenticated;

create or replace function public.rpc_create_member_and_attach_to_event(
  p_tenant_id uuid,
  p_event_id uuid,
  p_full_name text,
  p_phone text default null,
  p_alternative_phone text default null,
  p_email text default null,
  p_location text default null,
  p_category_id uuid default null,
  p_notes text default null,
  p_sms_enabled boolean default true
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
  insert into public.members (tenant_id, member_code, full_name, phone_e164, alternative_phone_e164, email, location, notes, sms_enabled, created_by)
  values (p_tenant_id, member_code, p_full_name, normalized_phone, normalized_alt_phone, nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_location, '')), ''), p_notes, coalesce(p_sms_enabled, true), caller)
  returning id into member_id;

  insert into public.event_members (tenant_id, event_id, member_id, category_id, notes, created_by)
  values (p_tenant_id, p_event_id, member_id, p_category_id, p_notes, caller)
  returning id into event_member_id;

  perform public.write_audit_log(p_tenant_id, 'member.created', 'member', member_id, p_event_id, null, jsonb_build_object('member_code', member_code));
  perform public.write_audit_log(p_tenant_id, 'event_member.attached', 'event_member', event_member_id, p_event_id, null, jsonb_build_object('member_id', member_id));

  return jsonb_build_object('member_id', member_id, 'event_member_id', event_member_id, 'member_code', member_code);
end;
$$;

grant execute on function public.rpc_create_member_and_attach_to_event(uuid, uuid, text, text, text, text, text, uuid, text, boolean) to authenticated;
