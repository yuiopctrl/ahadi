insert into public.permissions (code, name, description) values
  ('messages.manage_templates', 'Manage message templates', 'Customize tenant SMS templates'),
  ('messages.send', 'Send messages', 'Send or resend tenant SMS messages'),
  ('messages.view', 'View messages', 'View tenant SMS message history')
on conflict (code) do update set name = excluded.name, description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('messages.view', 'messages.send', 'messages.manage_templates')
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('messages.view', 'messages.send')
where r.code in ('TREASURER', 'COLLECTOR')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'messages.view'
where r.code = 'VIEWER'
on conflict do nothing;

insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active)
values (
  null,
  'BALANCE_REMINDER',
  'Balance reminder',
  'SMS',
  'Ndugu {{member_name}}, salio la ahadi yako kwa ajili ya {{event_name}} ni TZS {{outstanding}} kati ya TZS {{pledged_amount}}. Tafadhali kamilisha malipo{{due_text}}. Asante.',
  'sw',
  true,
  true
)
on conflict do nothing;

create table if not exists public.sms_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  batch_type text not null check (batch_type in ('BALANCE_REMINDER')),
  requested_count integer not null default 0 check (requested_count >= 0),
  queued_count integer not null default 0 check (queued_count >= 0),
  skipped_count integer not null default 0 check (skipped_count >= 0),
  created_by uuid not null references auth.users(id),
  idempotency_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (tenant_id, idempotency_key)
);

alter table public.sms_outbox
  add column if not exists batch_id uuid references public.sms_batches(id) on delete set null,
  add column if not exists original_outbox_id uuid references public.sms_outbox(id) on delete set null;

create index if not exists sms_outbox_batch_idx on public.sms_outbox(batch_id);
create index if not exists sms_outbox_template_event_member_idx on public.sms_outbox(tenant_id, event_id, event_member_id, template_code, created_at desc);

create table if not exists public.event_reminder_settings (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  balance_reminders_enabled boolean not null default false,
  due_soon_days integer not null default 7 check (due_soon_days >= 0 and due_soon_days <= 60),
  overdue_reminders_enabled boolean not null default false,
  reminder_time time,
  timezone text not null default 'Africa/Dar_es_Salaam',
  last_scheduler_run_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, event_id)
);

drop trigger if exists event_reminder_settings_set_updated_at on public.event_reminder_settings;
create trigger event_reminder_settings_set_updated_at
before update on public.event_reminder_settings
for each row execute function public.set_updated_at();

alter table public.sms_batches enable row level security;
alter table public.event_reminder_settings enable row level security;

drop policy if exists sms_batches_select on public.sms_batches;
create policy sms_batches_select on public.sms_batches
for select using (public.has_tenant_permission(tenant_id, 'messages.view'));

drop policy if exists event_reminder_settings_select on public.event_reminder_settings;
create policy event_reminder_settings_select on public.event_reminder_settings
for select using (public.has_tenant_permission(tenant_id, 'messages.view'));

drop policy if exists event_reminder_settings_manage on public.event_reminder_settings;
create policy event_reminder_settings_manage on public.event_reminder_settings
for all using (public.has_tenant_permission(tenant_id, 'messages.manage_templates'))
with check (public.has_tenant_permission(tenant_id, 'messages.manage_templates'));

create or replace function public.balance_reminder_due_text(p_due_date date)
returns text
language sql
stable
as $$
  select case
    when p_due_date is null then ''
    when p_due_date < current_date then ' ambayo tarehe yake ya mwisho ilikuwa ' || to_char(p_due_date, 'DD/MM/YYYY')
    else ' kabla ya ' || to_char(p_due_date, 'DD/MM/YYYY')
  end;
$$;

create or replace function public.balance_reminder_financial_state(p_tenant_id uuid, p_event_id uuid)
returns table (
  tenant_id uuid,
  event_id uuid,
  event_member_id uuid,
  member_id uuid,
  member_code text,
  full_name text,
  phone text,
  category text,
  pledged_amount numeric(18,2),
  total_paid numeric(18,2),
  outstanding_amount numeric(18,2),
  due_date date,
  days_overdue integer,
  pledge_status text,
  last_payment_date timestamptz,
  sms_enabled boolean,
  member_status text,
  event_member_status text,
  preferred_language text,
  event_name text,
  last_balance_reminder_at timestamptz,
  last_balance_reminder_status text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    em.tenant_id,
    em.event_id,
    em.id as event_member_id,
    m.id as member_id,
    m.member_code,
    m.full_name,
    m.phone_e164 as phone,
    c.name as category,
    p.pledged_amount::numeric(18,2),
    coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as total_paid,
    greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
    coalesce(p.due_date, e.pledge_deadline) as due_date,
    case when coalesce(p.due_date, e.pledge_deadline) is not null and coalesce(p.due_date, e.pledge_deadline) < current_date then current_date - coalesce(p.due_date, e.pledge_deadline) else 0 end as days_overdue,
    p.status as pledge_status,
    (
      select max(pay.payment_date)
      from public.payments pay
      join public.payment_allocations pa on pa.payment_id = pay.id
      where pa.pledge_id = p.id and pay.status = 'CONFIRMED'
    ) as last_payment_date,
    m.sms_enabled,
    m.status as member_status,
    em.status as event_member_status,
    m.preferred_language,
    e.name as event_name,
    (
      select max(o.created_at)
      from public.sms_outbox o
      where o.tenant_id = em.tenant_id
        and o.event_id = em.event_id
        and o.event_member_id = em.id
        and o.template_code = 'BALANCE_REMINDER'
        and o.status <> 'CANCELLED'
    ) as last_balance_reminder_at,
    (
      select o.status
      from public.sms_outbox o
      where o.tenant_id = em.tenant_id
        and o.event_id = em.event_id
        and o.event_member_id = em.id
        and o.template_code = 'BALANCE_REMINDER'
        and o.status <> 'CANCELLED'
      order by o.created_at desc
      limit 1
    ) as last_balance_reminder_status
  from public.pledges p
  join public.event_members em on em.id = p.event_member_id
  join public.events e on e.id = p.event_id
  join public.members m on m.id = em.member_id
  left join public.event_member_categories c on c.id = em.category_id
  where p.tenant_id = p_tenant_id
    and p.event_id = p_event_id
    and p.status <> 'CANCELLED'
    and em.status = 'ACTIVE'
    and m.status = 'ACTIVE';
$$;

create or replace view public.v_event_outstanding_members
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  m.full_name as member_name,
  m.phone_e164 as phone,
  c.name as category,
  p.pledged_amount::numeric(18,2),
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as paid_amount,
  greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  coalesce(p.due_date, e.pledge_deadline) as due_date,
  case when coalesce(p.due_date, e.pledge_deadline) is not null and coalesce(p.due_date, e.pledge_deadline) < current_date then current_date - coalesce(p.due_date, e.pledge_deadline) else 0 end as days_overdue,
  p.status as pledge_status,
  (
    select max(pay.payment_date)
    from public.payments pay
    join public.payment_allocations pa on pa.payment_id = pay.id
    where pa.pledge_id = p.id and pay.status = 'CONFIRMED'
  ) as last_payment_date,
  coalesce(p.due_date, e.pledge_deadline) as effective_due_date,
  (p.due_date is not null) as has_custom_due_date,
  em.id as event_member_id,
  m.id as member_id,
  m.member_code,
  m.sms_enabled,
  (
    select max(o.created_at)
    from public.sms_outbox o
    where o.tenant_id = p.tenant_id
      and o.event_id = p.event_id
      and o.event_member_id = em.id
      and o.template_code = 'BALANCE_REMINDER'
      and o.status <> 'CANCELLED'
  ) as last_balance_reminder_at,
  (
    select o.status
    from public.sms_outbox o
    where o.tenant_id = p.tenant_id
      and o.event_id = p.event_id
      and o.event_member_id = em.id
      and o.template_code = 'BALANCE_REMINDER'
      and o.status <> 'CANCELLED'
    order by o.created_at desc
    limit 1
  ) as last_balance_reminder_status
from public.pledges p
join public.events e on e.id = p.event_id
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
where p.status in ('PENDING', 'PARTIALLY_PAID', 'OVERDUE')
  and em.status = 'ACTIVE'
  and m.status = 'ACTIVE'
  and greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0) > 0;

create or replace function public.resolve_sms_template_body(p_tenant_id uuid, p_code text, p_language text)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select body
  from public.sms_templates
  where code = p_code
    and channel = 'SMS'
    and language = coalesce(nullif(p_language, ''), 'sw')
    and is_active
    and (tenant_id = p_tenant_id or tenant_id is null)
  order by case when tenant_id = p_tenant_id then 0 else 1 end
  limit 1;
$$;

create or replace function public.render_balance_reminder_message(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  state_record record;
  template_body text;
begin
  select * into state_record
  from public.balance_reminder_financial_state(p_tenant_id, p_event_id)
  where event_member_id = p_event_member_id;

  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  template_body := public.resolve_sms_template_body(p_tenant_id, 'BALANCE_REMINDER', state_record.preferred_language);
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;

  return public.render_sms_template(template_body, jsonb_build_object(
    'member_name', state_record.full_name,
    'event_name', state_record.event_name,
    'pledged_amount', public.format_tzs_sms_amount(state_record.pledged_amount),
    'total_paid', public.format_tzs_sms_amount(state_record.total_paid),
    'outstanding', public.format_tzs_sms_amount(state_record.outstanding_amount),
    'due_date', case when state_record.due_date is null then '' else to_char(state_record.due_date, 'DD/MM/YYYY') end,
    'due_text', public.balance_reminder_due_text(state_record.due_date)
  ));
end;
$$;

create or replace function public.balance_reminder_ineligibility_reason(p_phone text, p_sms_enabled boolean, p_outstanding numeric, p_recent_sent_at timestamptz, p_cooldown_hours integer)
returns text
language sql
stable
as $$
  select case
    when coalesce(p_outstanding, 0) <= 0 then 'NO_OUTSTANDING'
    when p_phone is null or p_phone !~ '^\+255[67][0-9]{8}$' then 'NO_PHONE'
    when coalesce(p_sms_enabled, false) = false then 'SMS_DISABLED'
    when p_recent_sent_at is not null and p_recent_sent_at > now() - make_interval(hours => greatest(coalesce(p_cooldown_hours, 24), 0)) then 'RECENTLY_SENT'
    else null
  end;
$$;

create or replace function public.sms_allowance_status(p_tenant_id uuid, p_requested integer)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with current_subscription as (
    select
      ts.current_period_start,
      coalesce(ts.current_period_end, now() + interval '100 years') as current_period_end,
      coalesce((ts.plan_snapshot ->> 'included_sms')::integer, sp.included_sms, 0) as included_sms
    from public.tenant_subscriptions ts
    join public.subscription_plans sp on sp.id = ts.plan_id
    where ts.tenant_id = p_tenant_id
      and ts.status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
    order by ts.created_at desc
    limit 1
  ),
  used as (
    select count(*)::integer as used_sms
    from public.sms_outbox o
    join current_subscription cs on true
    where o.tenant_id = p_tenant_id
      and o.created_at >= cs.current_period_start
      and o.created_at < cs.current_period_end
      and o.status <> 'CANCELLED'
  )
  select case
    when coalesce((select included_sms from current_subscription), 0) <= 0 then jsonb_build_object('status', 'UNLIMITED', 'allowed', p_requested, 'requested', p_requested, 'remaining', null)
    else jsonb_build_object(
      'status', case
        when greatest((select included_sms from current_subscription) - coalesce((select used_sms from used), 0), 0) = 0 then 'LIMIT_REACHED'
        when greatest((select included_sms from current_subscription) - coalesce((select used_sms from used), 0), 0) < p_requested then 'LOW_BALANCE'
        else 'AVAILABLE'
      end,
      'allowed', greatest((select included_sms from current_subscription) - coalesce((select used_sms from used), 0), 0),
      'requested', p_requested,
      'remaining', greatest((select included_sms from current_subscription) - coalesce((select used_sms from used), 0), 0)
    )
  end;
$$;

create or replace function public.rpc_list_event_outstanding_members(p_tenant_id uuid, p_event_id uuid, p_due_soon_days integer default 7, p_cooldown_hours integer default 24)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data."dueDate" asc nulls last, row_data."fullName"), '[]'::jsonb)
  into result
  from (
    select
      state.event_member_id as "eventMemberId",
      state.member_id as "memberId",
      state.member_code as "memberCode",
      state.full_name as "fullName",
      state.phone,
      state.category,
      state.pledged_amount as "pledgedAmount",
      state.total_paid as "totalPaid",
      state.outstanding_amount as "outstandingAmount",
      state.due_date as "dueDate",
      state.days_overdue as "daysOverdue",
      (state.due_date >= current_date and state.due_date <= current_date + greatest(coalesce(p_due_soon_days, 7), 0)) as "isDueSoon",
      state.pledge_status as "pledgeStatus",
      state.last_payment_date as "lastPaymentDate",
      state.sms_enabled as "smsEnabled",
      state.last_balance_reminder_at as "lastBalanceReminderAt",
      state.last_balance_reminder_status as "lastBalanceReminderStatus",
      public.balance_reminder_ineligibility_reason(state.phone, state.sms_enabled, state.outstanding_amount, state.last_balance_reminder_at, p_cooldown_hours) as "ineligibleReason",
      case when public.balance_reminder_ineligibility_reason(state.phone, state.sms_enabled, state.outstanding_amount, state.last_balance_reminder_at, p_cooldown_hours) is null then public.render_balance_reminder_message(p_tenant_id, p_event_id, state.event_member_id) else null end as "messagePreview"
    from public.balance_reminder_financial_state(p_tenant_id, p_event_id) state
    where state.outstanding_amount > 0
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_get_balance_reminder_template(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_body text;
  system_body text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select body into tenant_body from public.sms_templates where tenant_id = p_tenant_id and code = 'BALANCE_REMINDER' and language = 'sw' and is_active limit 1;
  select body into system_body from public.sms_templates where tenant_id is null and code = 'BALANCE_REMINDER' and language = 'sw' and is_active limit 1;

  if tenant_body is null and system_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'templateCode', 'BALANCE_REMINDER',
    'language', 'sw',
    'body', coalesce(tenant_body, system_body),
    'systemBody', system_body,
    'hasTenantOverride', tenant_body is not null,
    'variables', '["member_name","event_name","pledged_amount","total_paid","outstanding","due_date","due_text"]'::jsonb
  );
end;
$$;

create or replace function public.rpc_upsert_balance_reminder_template(p_tenant_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_body text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  normalized_body := btrim(coalesce(p_body, ''));
  if normalized_body = '' or length(normalized_body) > 918 then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  if normalized_body ~ '<[^>]+>' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;

  insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active)
  values (p_tenant_id, 'BALANCE_REMINDER', 'Balance reminder', 'SMS', normalized_body, 'sw', false, true)
  on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language)
  do update set body = excluded.body, is_active = true, updated_at = now();

  return public.rpc_get_balance_reminder_template(p_tenant_id);
end;
$$;

create or replace function public.rpc_reset_balance_reminder_template(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  update public.sms_templates
  set is_active = false, updated_at = now()
  where tenant_id = p_tenant_id
    and code = 'BALANCE_REMINDER'
    and language = 'sw';

  return public.rpc_get_balance_reminder_template(p_tenant_id);
end;
$$;

create or replace function public.rpc_enqueue_balance_reminder_sms(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid,
  p_idempotency_key text,
  p_cooldown_hours integer default 24,
  p_original_outbox_id uuid default null,
  p_batch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  state_record record;
  reason text;
  message text;
  outbox_id uuid;
  idempotency text;
  allowance jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  idempotency := coalesce(nullif(btrim(p_idempotency_key), ''), gen_random_uuid()::text);
  if exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
    select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('queued', true, 'outboxId', outbox_id, 'status', 'QUEUED', 'reason', 'IDEMPOTENT_REPLAY');
  end if;

  select * into state_record
  from public.balance_reminder_financial_state(p_tenant_id, p_event_id)
  where event_member_id = p_event_member_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  reason := public.balance_reminder_ineligibility_reason(state_record.phone, state_record.sms_enabled, state_record.outstanding_amount, state_record.last_balance_reminder_at, p_cooldown_hours);
  if reason = 'NO_OUTSTANDING' then
    return jsonb_build_object('queued', false, 'reason', 'NO_OUTSTANDING_BALANCE');
  elsif reason = 'NO_PHONE' then
    return jsonb_build_object('queued', false, 'reason', 'MEMBER_PHONE_MISSING');
  elsif reason = 'SMS_DISABLED' then
    return jsonb_build_object('queued', false, 'reason', 'MEMBER_SMS_DISABLED');
  elsif reason = 'RECENTLY_SENT' then
    return jsonb_build_object('queued', false, 'reason', 'RECENTLY_SENT', 'lastSentAt', state_record.last_balance_reminder_at);
  end if;

  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if allowance ->> 'status' = 'LIMIT_REACHED' then
    raise exception 'SMS_LIMIT_REACHED' using errcode = '22023';
  end if;

  message := public.render_balance_reminder_message(p_tenant_id, p_event_id, p_event_member_id);

  insert into public.sms_outbox (
    tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, original_outbox_id, batch_id
  )
  values (
    p_tenant_id, p_event_id, state_record.member_id, p_event_member_id, 'BALANCE_REMINDER', state_record.phone, message, 'QUEUED', idempotency, p_original_outbox_id, p_batch_id
  )
  returning id into outbox_id;

  return jsonb_build_object('queued', true, 'outboxId', outbox_id, 'memberId', state_record.member_id, 'status', 'QUEUED');
end;
$$;

create or replace function public.rpc_enqueue_balance_reminder_bulk(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_ids uuid[],
  p_idempotency_key text,
  p_cooldown_hours integer default 24,
  p_max_batch_size integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  requested integer;
  invalid_count integer;
  eligible_count integer;
  batch_id uuid;
  member_id uuid;
  single_result jsonb;
  v_queued_count integer := 0;
  no_phone integer := 0;
  sms_disabled integer := 0;
  recently_sent integer := 0;
  no_outstanding integer := 0;
  allowance jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  requested := coalesce(array_length(p_event_member_ids, 1), 0);
  if requested = 0 then
    raise exception 'REMINDER_BATCH_EMPTY' using errcode = '22023';
  end if;
  if requested > greatest(coalesce(p_max_batch_size, 100), 1) then
    raise exception 'REMINDER_BATCH_TOO_LARGE' using errcode = '22023';
  end if;

  select count(*) into invalid_count
  from unnest(p_event_member_ids) ids(id)
  left join public.event_members em on em.id = ids.id and em.tenant_id = p_tenant_id and em.event_id = p_event_id
  where em.id is null;
  if invalid_count > 0 then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select count(*) into eligible_count
  from public.balance_reminder_financial_state(p_tenant_id, p_event_id) state
  join unnest(p_event_member_ids) ids(id) on ids.id = state.event_member_id
  where public.balance_reminder_ineligibility_reason(state.phone, state.sms_enabled, state.outstanding_amount, state.last_balance_reminder_at, p_cooldown_hours) is null;

  allowance := public.sms_allowance_status(p_tenant_id, eligible_count);
  if allowance ->> 'status' = 'LIMIT_REACHED' then
    raise exception 'SMS_LIMIT_REACHED' using errcode = '22023';
  end if;
  if allowance ->> 'status' = 'LOW_BALANCE' then
    return jsonb_build_object('requested', requested, 'queued', 0, 'skipped', jsonb_build_object('noPhone', 0, 'smsDisabled', 0, 'recentlySent', 0, 'noOutstanding', 0, 'invalidMember', 0), 'smsAllowance', allowance);
  end if;

  insert into public.sms_batches (tenant_id, event_id, batch_type, requested_count, queued_count, skipped_count, created_by, idempotency_key)
  values (p_tenant_id, p_event_id, 'BALANCE_REMINDER', requested, 0, 0, auth.uid(), p_idempotency_key)
  on conflict (tenant_id, idempotency_key) do update set idempotency_key = excluded.idempotency_key
  returning id into batch_id;

  for member_id in select unnest(p_event_member_ids) loop
    single_result := public.rpc_enqueue_balance_reminder_sms(p_tenant_id, p_event_id, member_id, 'BALANCE_REMINDER:' || batch_id::text || ':' || member_id::text, p_cooldown_hours, null, batch_id);
    if single_result ->> 'queued' = 'true' then
      v_queued_count := v_queued_count + 1;
    elsif single_result ->> 'reason' = 'MEMBER_PHONE_MISSING' then
      no_phone := no_phone + 1;
    elsif single_result ->> 'reason' = 'MEMBER_SMS_DISABLED' then
      sms_disabled := sms_disabled + 1;
    elsif single_result ->> 'reason' = 'RECENTLY_SENT' then
      recently_sent := recently_sent + 1;
    elsif single_result ->> 'reason' = 'NO_OUTSTANDING_BALANCE' then
      no_outstanding := no_outstanding + 1;
    end if;
  end loop;

  update public.sms_batches
  set queued_count = v_queued_count,
      skipped_count = requested - v_queued_count,
      metadata = jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled, 'recentlySent', recently_sent, 'noOutstanding', no_outstanding, 'invalidMember', 0)
  where id = batch_id;

  return jsonb_build_object(
    'requested', requested,
    'queued', v_queued_count,
    'skipped', jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled, 'recentlySent', recently_sent, 'noOutstanding', no_outstanding, 'invalidMember', 0),
    'batchId', batch_id,
    'smsAllowance', allowance
  );
end;
$$;

create or replace function public.rpc_resend_failed_balance_reminder(p_tenant_id uuid, p_outbox_id uuid, p_idempotency_key text, p_cooldown_hours integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  original_record public.sms_outbox%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into original_record
  from public.sms_outbox
  where id = p_outbox_id
    and tenant_id = p_tenant_id
    and template_code = 'BALANCE_REMINDER'
    and status = 'FAILED';
  if not found then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;

  return public.rpc_enqueue_balance_reminder_sms(p_tenant_id, original_record.event_id, original_record.event_member_id, p_idempotency_key, p_cooldown_hours, original_record.id, null);
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
      case o.template_code when 'PAYMENT_CONFIRMATION' then 'Payment Confirmation' when 'BALANCE_REMINDER' then 'Balance Reminder' else initcap(replace(coalesce(o.template_code, 'Message'), '_', ' ')) end as message_type,
      o.phone_e164,
      o.status,
      o.attempt_count,
      o.created_at,
      o.sent_at,
      o.delivered_at,
      o.failed_at,
      o.last_error_code,
      o.last_error_message,
      o.original_outbox_id,
      o.batch_id
    from public.sms_outbox o
    left join public.events e on e.id = o.event_id
    left join public.members m on m.id = o.member_id
    where o.tenant_id = p_tenant_id
  ) row_data;

  return result;
end;
$$;

grant select on public.sms_batches, public.event_reminder_settings to authenticated;
grant execute on function public.balance_reminder_due_text(date) to authenticated;
grant execute on function public.balance_reminder_financial_state(uuid, uuid) to authenticated;
grant execute on function public.resolve_sms_template_body(uuid, text, text) to authenticated;
grant execute on function public.render_balance_reminder_message(uuid, uuid, uuid) to authenticated;
grant execute on function public.balance_reminder_ineligibility_reason(text, boolean, numeric, timestamptz, integer) to authenticated;
grant execute on function public.sms_allowance_status(uuid, integer) to authenticated;
grant execute on function public.rpc_list_event_outstanding_members(uuid, uuid, integer, integer) to authenticated;
grant execute on function public.rpc_get_balance_reminder_template(uuid) to authenticated;
grant execute on function public.rpc_upsert_balance_reminder_template(uuid, text) to authenticated;
grant execute on function public.rpc_reset_balance_reminder_template(uuid) to authenticated;
grant execute on function public.rpc_enqueue_balance_reminder_sms(uuid, uuid, uuid, text, integer, uuid, uuid) to authenticated;
grant execute on function public.rpc_enqueue_balance_reminder_bulk(uuid, uuid, uuid[], text, integer, integer) to authenticated;
grant execute on function public.rpc_resend_failed_balance_reminder(uuid, uuid, text, integer) to authenticated;
