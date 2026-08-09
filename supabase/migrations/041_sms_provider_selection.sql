insert into public.permissions (code, name, description) values
('platform.sms.manage', 'Manage platform SMS', 'Manage global SMS providers and sender IDs')
on conflict (code) do update set name = excluded.name, description = excluded.description;

create table if not exists public.sms_providers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'DISABLED')),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sms_provider_sender_ids (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null references public.sms_providers(code) on update cascade on delete cascade,
  sender_id text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'DISABLED')),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_code, sender_id)
);

drop trigger if exists sms_providers_set_updated_at on public.sms_providers;
create trigger sms_providers_set_updated_at
before update on public.sms_providers
for each row execute function public.set_updated_at();

drop trigger if exists sms_provider_sender_ids_set_updated_at on public.sms_provider_sender_ids;
create trigger sms_provider_sender_ids_set_updated_at
before update on public.sms_provider_sender_ids
for each row execute function public.set_updated_at();

create unique index if not exists sms_providers_one_default_idx
on public.sms_providers(is_default)
where is_default;

create unique index if not exists sms_provider_sender_ids_one_default_idx
on public.sms_provider_sender_ids(provider_code, is_default)
where is_default;

update public.sms_providers set is_default = false;

insert into public.sms_providers (code, name, status, is_default) values
('NEXTSMS', 'NextSMS', 'ACTIVE', true),
('WEBBULKSMS', 'WebBulkSMS', 'ACTIVE', false)
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  is_default = excluded.is_default;

update public.sms_provider_sender_ids set is_default = false;

insert into public.sms_provider_sender_ids (provider_code, sender_id, status, is_default) values
('NEXTSMS', 'MICHANGO', 'ACTIVE', true),
('NEXTSMS', 'SHEREHE', 'ACTIVE', false),
('NEXTSMS', 'KIKAO', 'ACTIVE', false),
('WEBBULKSMS', 'YUIOP APPS', 'ACTIVE', true)
on conflict (provider_code, sender_id) do update set
  status = excluded.status,
  is_default = excluded.is_default;

alter table public.tenant_settings
  add column if not exists sms_provider_code text,
  add column if not exists sms_provider_explicit boolean not null default false;

alter table public.sms_outbox
  add column if not exists provider text,
  add column if not exists sender_id text;

alter table public.tenant_settings
drop constraint if exists tenant_settings_sms_sender_id_allowed;

alter table public.sms_outbox
drop constraint if exists sms_outbox_sender_id_allowed;

create or replace function public.normalize_sms_provider_code(p_provider_code text)
returns text
language plpgsql
immutable
as $$
declare
  normalized text := upper(btrim(coalesce(p_provider_code, '')));
begin
  if normalized not in ('NEXTSMS', 'WEBBULKSMS') then
    raise exception 'SMS_PROVIDER_NOT_SUPPORTED' using errcode = '22023';
  end if;
  return normalized;
end;
$$;

create or replace function public.sms_default_provider_code()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select code
  from public.sms_providers
  where status = 'ACTIVE' and is_default
  order by updated_at desc
  limit 1;
$$;

create or replace function public.sms_provider_default_sender_id(p_provider_code text)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_provider text := public.normalize_sms_provider_code(p_provider_code);
  selected_sender text;
begin
  select sender_id into selected_sender
  from public.sms_provider_sender_ids
  where provider_code = normalized_provider
    and status = 'ACTIVE'
    and is_default
  order by updated_at desc
  limit 1;

  if selected_sender is null then
    select sender_id into selected_sender
    from public.sms_provider_sender_ids
    where provider_code = normalized_provider
      and status = 'ACTIVE'
    order by sender_id
    limit 1;
  end if;

  if selected_sender is null then
    raise exception 'SMS_PROVIDER_SENDER_NOT_CONFIGURED' using errcode = '22023';
  end if;

  return selected_sender;
end;
$$;

create or replace function public.validate_sms_provider_sender(p_provider_code text, p_sender_id text)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_provider text := public.normalize_sms_provider_code(p_provider_code);
  normalized_sender text := upper(btrim(coalesce(p_sender_id, '')));
begin
  if not exists (select 1 from public.sms_providers where code = normalized_provider and status = 'ACTIVE') then
    raise exception 'SMS_PROVIDER_NOT_ACTIVE' using errcode = '22023';
  end if;

  if normalized_sender = '' then
    normalized_sender := public.sms_provider_default_sender_id(normalized_provider);
  end if;

  if not exists (
    select 1
    from public.sms_provider_sender_ids
    where provider_code = normalized_provider
      and sender_id = normalized_sender
      and status = 'ACTIVE'
  ) then
    raise exception 'SMS_PROVIDER_SENDER_NOT_ALLOWED' using errcode = '22023';
  end if;

  return normalized_sender;
end;
$$;

create or replace function public.tenant_sms_provider_settings(p_tenant_id uuid)
returns table(provider_code text, sender_id text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_provider text;
  tenant_sender text;
  effective_provider text;
  effective_sender text;
begin
  select sms_provider_code, sms_sender_id
  into tenant_provider, tenant_sender
  from public.tenant_settings
  where tenant_id = p_tenant_id;

  effective_provider := coalesce(nullif(upper(btrim(tenant_provider)), ''), public.sms_default_provider_code());
  if effective_provider is null then
    raise exception 'SMS_DEFAULT_PROVIDER_NOT_CONFIGURED' using errcode = '22023';
  end if;

  effective_sender := public.validate_sms_provider_sender(effective_provider, tenant_sender);
  return query select effective_provider, effective_sender;
end;
$$;

create or replace function public.tenant_sms_sender_id(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select sender_id from public.tenant_sms_provider_settings(p_tenant_id);
$$;

create or replace function public.tenant_sms_provider_code(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select provider_code from public.tenant_sms_provider_settings(p_tenant_id);
$$;

create or replace function public.tenant_sms_settings_json(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  selected_provider text;
  selected_sender text;
  result jsonb;
begin
  select provider_code, sender_id into selected_provider, selected_sender
  from public.tenant_sms_provider_settings(p_tenant_id);

  select jsonb_build_object(
    'smsEnabled', coalesce(ts.sms_enabled, true),
    'selectedProvider', selected_provider,
    'provider', selected_provider,
    'selectedSenderId', selected_sender,
    'senderId', selected_sender,
    'defaultLanguage', coalesce(nullif(ts.sms_default_language, ''), 'sw'),
    'allowedSenderIds', coalesce((select jsonb_agg(sender_id order by is_default desc, sender_id) from public.sms_provider_sender_ids where provider_code = selected_provider and status = 'ACTIVE'), '[]'::jsonb),
    'providers', public.sms_active_providers_json()
  )
  into result
  from public.tenant_settings ts
  where ts.tenant_id = p_tenant_id;

  return result;
end;
$$;

create or replace function public.sms_active_providers_json()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', p.code,
    'name', p.name,
    'isDefault', p.is_default,
    'senderIds', coalesce((select jsonb_agg(s.sender_id order by s.is_default desc, s.sender_id) from public.sms_provider_sender_ids s where s.provider_code = p.code and s.status = 'ACTIVE'), '[]'::jsonb)
  ) order by p.is_default desc, p.name), '[]'::jsonb)
  from public.sms_providers p
  where p.status = 'ACTIVE';
$$;

create or replace function public.platform_sms_providers_json()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', p.code,
    'name', p.name,
    'status', p.status,
    'isDefault', p.is_default,
    'senderIds', coalesce((select jsonb_agg(jsonb_build_object('senderId', s.sender_id, 'status', s.status, 'isDefault', s.is_default) order by s.is_default desc, s.sender_id) from public.sms_provider_sender_ids s where s.provider_code = p.code), '[]'::jsonb)
  ) order by p.is_default desc, p.name), '[]'::jsonb)
  from public.sms_providers p;
$$;

create or replace function public.rpc_get_sms_settings(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  return public.tenant_sms_settings_json(p_tenant_id);
end;
$$;

drop function if exists public.rpc_update_sms_settings(uuid, boolean, text, text);

create or replace function public.rpc_update_sms_settings(p_tenant_id uuid, p_sms_enabled boolean, p_sender_id text, p_default_language text default 'sw', p_provider_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  previous_provider text;
  previous_sender text;
  requested_provider text;
  requested_sender text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_settings') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select provider_code, sender_id into previous_provider, previous_sender
  from public.tenant_sms_provider_settings(p_tenant_id);

  requested_provider := coalesce(nullif(upper(btrim(p_provider_code)), ''), previous_provider, public.sms_default_provider_code());
  requested_sender := public.validate_sms_provider_sender(requested_provider, p_sender_id);

  update public.tenant_settings
  set sms_enabled = coalesce(p_sms_enabled, true),
      sms_provider_code = requested_provider,
      sms_provider_explicit = true,
      sms_sender_id = requested_sender,
      sms_default_language = case when coalesce(p_default_language, 'sw') in ('sw', 'en') then coalesce(p_default_language, 'sw') else 'sw' end
  where tenant_id = p_tenant_id;

  perform public.write_audit_log(
    p_tenant_id,
    'TENANT_SMS_PROVIDER_CHANGED',
    'tenant_settings',
    p_tenant_id,
    null,
    jsonb_build_object('previousProvider', previous_provider, 'previousSender', previous_sender),
    jsonb_build_object('newProvider', requested_provider, 'newSender', requested_sender)
  );

  return public.tenant_sms_settings_json(p_tenant_id);
end;
$$;

create or replace function public.rpc_get_sms_provider_options(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  return public.tenant_sms_settings_json(p_tenant_id);
end;
$$;

create or replace function public.rpc_get_platform_sms_providers()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or not public.has_platform_permission('platform.sms.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  return jsonb_build_object('providers', public.platform_sms_providers_json());
end;
$$;

create or replace function public.rpc_update_platform_sms_provider(p_provider_code text, p_status text default null, p_is_default boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_provider text := public.normalize_sms_provider_code(p_provider_code);
  normalized_status text := upper(btrim(coalesce(p_status, '')));
begin
  if auth.uid() is null or not public.has_platform_permission('platform.sms.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if normalized_status not in ('', 'ACTIVE', 'DISABLED') then
    raise exception 'SMS_PROVIDER_STATUS_INVALID' using errcode = '22023';
  end if;
  if coalesce(p_is_default, false) and normalized_status = 'DISABLED' then
    raise exception 'SMS_DEFAULT_PROVIDER_MUST_BE_ACTIVE' using errcode = '22023';
  end if;

  if coalesce(p_is_default, false) then
    update public.sms_providers set is_default = false where code <> normalized_provider;
  end if;

  update public.sms_providers
  set status = case when normalized_status = '' then status else normalized_status end,
      is_default = coalesce(p_is_default, is_default)
  where code = normalized_provider;

  if not exists (select 1 from public.sms_providers where status = 'ACTIVE' and is_default) then
    raise exception 'SMS_DEFAULT_PROVIDER_NOT_CONFIGURED' using errcode = '22023';
  end if;

  perform public.write_audit_log(null, 'PLATFORM_SMS_PROVIDER_UPDATED', 'sms_provider', null, null, null, jsonb_build_object('provider', normalized_provider, 'status', nullif(normalized_status, ''), 'isDefault', p_is_default));
  return jsonb_build_object('providers', public.platform_sms_providers_json());
end;
$$;

create or replace function public.rpc_update_platform_sms_sender_id(p_provider_code text, p_sender_id text, p_status text default null, p_is_default boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_provider text := public.normalize_sms_provider_code(p_provider_code);
  normalized_sender text := upper(btrim(coalesce(p_sender_id, '')));
  normalized_status text := upper(btrim(coalesce(p_status, '')));
begin
  if auth.uid() is null or not public.has_platform_permission('platform.sms.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if normalized_sender = '' then
    raise exception 'SMS_SENDER_ID_REQUIRED' using errcode = '22023';
  end if;
  if normalized_status not in ('', 'ACTIVE', 'DISABLED') then
    raise exception 'SMS_SENDER_STATUS_INVALID' using errcode = '22023';
  end if;
  if coalesce(p_is_default, false) and normalized_status = 'DISABLED' then
    raise exception 'SMS_DEFAULT_SENDER_MUST_BE_ACTIVE' using errcode = '22023';
  end if;

  if coalesce(p_is_default, false) then
    update public.sms_provider_sender_ids set is_default = false where provider_code = normalized_provider and sender_id <> normalized_sender;
  end if;

  update public.sms_provider_sender_ids
  set status = case when normalized_status = '' then status else normalized_status end,
      is_default = coalesce(p_is_default, is_default)
  where provider_code = normalized_provider and sender_id = normalized_sender;

  if not found then
    raise exception 'SMS_PROVIDER_SENDER_NOT_ALLOWED' using errcode = '22023';
  end if;

  perform public.sms_provider_default_sender_id(normalized_provider);
  perform public.write_audit_log(null, 'PLATFORM_SMS_SENDER_UPDATED', 'sms_provider_sender_id', null, null, null, jsonb_build_object('provider', normalized_provider, 'senderId', normalized_sender, 'status', nullif(normalized_status, ''), 'isDefault', p_is_default));
  return jsonb_build_object('providers', public.platform_sms_providers_json());
end;
$$;

update public.tenant_settings ts
set sms_provider_code = 'NEXTSMS',
    sms_sender_id = 'MICHANGO'
where (ts.sms_provider_code is null or btrim(ts.sms_provider_code) = '')
  and coalesce(ts.sms_provider_explicit, false) = false;

update public.sms_outbox
set provider = 'NEXTSMS',
    sender_id = 'MICHANGO'
where (provider is null or btrim(provider) = '' or provider = 'WEBBULKSMS')
  and status in ('QUEUED', 'FAILED');

alter table public.tenant_settings
drop constraint if exists tenant_settings_sms_provider_code_supported;
alter table public.tenant_settings
add constraint tenant_settings_sms_provider_code_supported
check (sms_provider_code is null or upper(btrim(sms_provider_code)) in ('NEXTSMS', 'WEBBULKSMS'));

alter table public.sms_outbox
drop constraint if exists sms_outbox_provider_supported;
alter table public.sms_outbox
add constraint sms_outbox_provider_supported
check (provider is null or upper(btrim(provider)) in ('NEXTSMS', 'WEBBULKSMS'));

drop view if exists public.v_sms_provider_selection_migration_report;
create view public.v_sms_provider_selection_migration_report as
select
  count(*) filter (where sms_provider_code = 'NEXTSMS' and sms_sender_id = 'MICHANGO' and coalesce(sms_provider_explicit, false) = false) as tenants_using_default_nextsms,
  count(*) filter (where sms_provider_code is null or btrim(sms_provider_code) = '') as tenants_without_provider,
  count(*) as total_tenant_settings
from public.tenant_settings;

create or replace function public.sms_preview_json(p_template_code text, p_event_member_id uuid, p_member_name text, p_phone text, p_sender_id text, p_message text)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'templateCode', upper(btrim(coalesce(p_template_code, ''))),
    'member', jsonb_build_object(
      'eventMemberId', p_event_member_id,
      'name', coalesce(p_member_name, 'Member'),
      'phoneMasked', case when p_phone is null then 'No phone' else left(p_phone, 4) || repeat('*', greatest(length(p_phone) - 7, 0)) || right(p_phone, 3) end
    ),
    'provider', (select provider_code from public.tenant_sms_provider_settings((select tenant_id from public.event_members where id = p_event_member_id limit 1))),
    'senderId', p_sender_id,
    'message', public.normalize_sms_message_text(p_message),
    'characters', public.sms_character_count(p_message),
    'maxCharacters', public.sms_max_characters(),
    'remainingCharacters', public.sms_max_characters() - public.sms_character_count(p_message),
    'valid', public.sms_character_count(p_message) <= public.sms_max_characters(),
    'reason', case when public.sms_character_count(p_message) > public.sms_max_characters() then 'SMS_CHARACTER_LIMIT_EXCEEDED' else null end
  );
$$;

create or replace function public.rpc_enqueue_pledge_registration_sms(p_tenant_id uuid, p_event_id uuid, p_pledge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  pledge_record public.pledges%rowtype;
  member_record public.members%rowtype;
  event_record public.events%rowtype;
  effective_due_date date;
  template_body text;
  message text;
  outbox_id uuid;
  idempotency text;
  provider_settings record;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.create', 'COLLECT') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.tenant_sms_enabled(p_tenant_id) then return jsonb_build_object('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED', 'template', 'PLEDGE_REGISTRATION'); end if;
  select * into pledge_record from public.pledges where id = p_pledge_id and tenant_id = p_tenant_id and event_id = p_event_id;
  if not found then raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023'; end if;
  select m.* into member_record from public.event_members em join public.members m on m.id = em.member_id where em.id = pledge_record.event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id;
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;
  if member_record.phone_e164 is null then return jsonb_build_object('smsQueued', false, 'reason', 'NO_PHONE', 'template', 'PLEDGE_REGISTRATION'); end if;
  if coalesce(member_record.sms_enabled, true) = false then return jsonb_build_object('smsQueued', false, 'reason', 'SMS_DISABLED', 'template', 'PLEDGE_REGISTRATION'); end if;
  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  effective_due_date := coalesce(pledge_record.due_date, event_record.pledge_deadline);
  idempotency := 'PLEDGE_REGISTRATION:' || pledge_record.id::text;
  select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
  if found then return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', 'PLEDGE_REGISTRATION'); end if;
  template_body := case when effective_due_date is null then public.compact_default_sms_template('PLEDGE_REGISTRATION', false) else public.resolve_sms_template_body(p_tenant_id, 'PLEDGE_REGISTRATION', member_record.preferred_language) end;
  if template_body is null then return jsonb_build_object('smsQueued', false, 'reason', 'TEMPLATE_NOT_FOUND', 'template', 'PLEDGE_REGISTRATION'); end if;
  message := public.render_sms_template(template_body, jsonb_build_object('member_name', member_record.full_name, 'pledge_amount', public.format_tzs_sms_amount(pledge_record.pledged_amount), 'event_name', event_record.name, 'due_date', public.pledge_due_date_text(effective_due_date)));
  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, sender_id, provider)
  values (p_tenant_id, p_event_id, member_record.id, pledge_record.event_member_id, 'PLEDGE_REGISTRATION', member_record.phone_e164, message, 'QUEUED', idempotency, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'template', 'PLEDGE_REGISTRATION', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
exception when unique_violation then
  select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', 'PLEDGE_REGISTRATION');
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
  pledge_record public.pledges%rowtype;
  template_code text;
  template_body text;
  message text;
  outbox_id uuid;
  idempotency text;
  outstanding numeric(18,2);
  provider_settings record;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  select * into payment_record from public.payments where id = p_payment_id and tenant_id = p_tenant_id;
  if not found then raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023'; end if;
  if not public.has_event_financial_access(payment_record.tenant_id, payment_record.event_id, 'payments.create', 'COLLECT') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if payment_record.status = 'REVERSED' then return jsonb_build_object('smsQueued', false, 'reason', 'PAYMENT_REVERSED'); end if;
  if not public.tenant_sms_enabled(p_tenant_id) then return jsonb_build_object('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED'); end if;
  select m.* into member_record from public.event_members em join public.members m on m.id = em.member_id where em.id = payment_record.event_member_id and em.tenant_id = p_tenant_id and em.event_id = payment_record.event_id;
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;
  if member_record.phone_e164 is null then return jsonb_build_object('smsQueued', false, 'reason', 'NO_PHONE'); end if;
  if coalesce(member_record.sms_enabled, true) = false then return jsonb_build_object('smsQueued', false, 'reason', 'SMS_DISABLED'); end if;
  select * into event_record from public.events where id = payment_record.event_id and tenant_id = p_tenant_id;
  select * into receipt_record from public.receipts where payment_id = payment_record.id and tenant_id = p_tenant_id;
  select * into pledge_record from public.pledges where id = payment_record.pledge_id and tenant_id = p_tenant_id;
  outstanding := case when pledge_record.id is not null then greatest(pledge_record.pledged_amount - public.confirmed_pledge_allocated_amount(pledge_record.id), 0) else 0 end;
  template_code := case when pledge_record.id is not null and outstanding <= 0 then 'PLEDGE_COMPLETED' else 'PAYMENT_CONFIRMATION' end;
  idempotency := template_code || ':' || payment_record.id::text;
  select id into outbox_id from public.sms_outbox where payment_id = p_payment_id and template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED') and status <> 'CANCELLED' limit 1;
  if found then return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', template_code); end if;
  template_body := public.resolve_sms_template_body(p_tenant_id, template_code, member_record.preferred_language);
  if template_body is null then return jsonb_build_object('smsQueued', false, 'reason', 'TEMPLATE_NOT_FOUND', 'template', template_code); end if;
  message := public.render_sms_template(template_body, jsonb_build_object('member_name', member_record.full_name, 'payment_amount', public.format_tzs_sms_amount(payment_record.amount), 'payment_method', public.payment_method_sms_name(payment_record.payment_method), 'event_name', event_record.name, 'balance', public.format_tzs_sms_amount(outstanding), 'receipt_number', receipt_record.receipt_number, 'pledge_amount', public.format_tzs_sms_amount(coalesce(pledge_record.pledged_amount, payment_record.amount))));
  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, payment_id, receipt_id, template_code, phone_e164, message_body, status, idempotency_key, sender_id, provider)
  values (p_tenant_id, payment_record.event_id, member_record.id, payment_record.event_member_id, payment_record.id, receipt_record.id, template_code, member_record.phone_e164, message, 'QUEUED', idempotency, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'template', template_code, 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
exception when unique_violation then
  select id into outbox_id from public.sms_outbox where payment_id = p_payment_id and template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED') and status <> 'CANCELLED' limit 1;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', template_code);
end;
$$;

create or replace function public.rpc_enqueue_balance_reminder_sms(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid, p_idempotency_key text, p_cooldown_hours integer default 24, p_original_outbox_id uuid default null, p_batch_id uuid default null)
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
  provider_settings record;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.tenant_sms_enabled(p_tenant_id) then return jsonb_build_object('queued', false, 'template', 'BALANCE_REMINDER', 'reason', 'TENANT_SMS_DISABLED'); end if;
  idempotency := coalesce(nullif(btrim(p_idempotency_key), ''), gen_random_uuid()::text);
  if exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
    select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('queued', true, 'outboxId', outbox_id, 'status', 'QUEUED', 'reason', 'IDEMPOTENT_REPLAY');
  end if;
  select * into state_record from public.balance_reminder_financial_state(p_tenant_id, p_event_id) where event_member_id = p_event_member_id;
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;
  reason := public.balance_reminder_ineligibility_reason(state_record.phone, state_record.sms_enabled, state_record.outstanding_amount, state_record.last_balance_reminder_at, p_cooldown_hours);
  if reason = 'NO_OUTSTANDING' then return jsonb_build_object('queued', false, 'reason', 'NO_OUTSTANDING_BALANCE');
  elsif reason = 'NO_PHONE' then return jsonb_build_object('queued', false, 'reason', 'MEMBER_PHONE_MISSING');
  elsif reason = 'SMS_DISABLED' then return jsonb_build_object('queued', false, 'reason', 'MEMBER_SMS_DISABLED');
  elsif reason = 'RECENTLY_SENT' then return jsonb_build_object('queued', false, 'reason', 'RECENTLY_SENT', 'lastSentAt', state_record.last_balance_reminder_at);
  end if;
  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if allowance ->> 'status' = 'LIMIT_REACHED' then raise exception 'SMS_LIMIT_REACHED' using errcode = '22023'; end if;
  message := public.render_balance_reminder_message(p_tenant_id, p_event_id, p_event_member_id);
  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, original_outbox_id, batch_id, sender_id, provider)
  values (p_tenant_id, p_event_id, state_record.member_id, p_event_member_id, 'BALANCE_REMINDER', state_record.phone, message, 'QUEUED', idempotency, p_original_outbox_id, p_batch_id, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;
  return jsonb_build_object('queued', true, 'outboxId', outbox_id, 'memberId', state_record.member_id, 'status', 'QUEUED', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
end;
$$;

create or replace function public.rpc_enqueue_pledge_request_sms(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid, p_idempotency_key text, p_cooldown_hours integer default 24, p_original_outbox_id uuid default null, p_batch_id uuid default null)
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
  provider_settings record;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.tenant_sms_enabled(p_tenant_id) then return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'TENANT_SMS_DISABLED'); end if;
  idempotency := coalesce(nullif(btrim(p_idempotency_key), ''), gen_random_uuid()::text);
  if exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
    select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('queued', true, 'template', 'PLEDGE_REQUEST', 'outboxId', outbox_id, 'status', 'QUEUED', 'reason', 'IDEMPOTENT_REPLAY');
  end if;
  select * into state_record from public.pledge_request_state(p_tenant_id, p_event_id) where event_member_id = p_event_member_id;
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;
  reason := public.pledge_request_ineligibility_reason(state_record.phone, state_record.sms_enabled, state_record.has_pledge, state_record.last_pledge_request_at, p_cooldown_hours);
  if reason = 'HAS_PLEDGE' then return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'HAS_PLEDGE');
  elsif reason = 'NO_PHONE' then return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'MEMBER_PHONE_MISSING');
  elsif reason = 'SMS_DISABLED' then return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'MEMBER_SMS_DISABLED');
  elsif reason = 'RECENTLY_SENT' then return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'RECENTLY_SENT', 'lastSentAt', state_record.last_pledge_request_at);
  end if;
  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if allowance ->> 'status' = 'LIMIT_REACHED' then raise exception 'SMS_LIMIT_REACHED' using errcode = '22023'; end if;
  message := public.render_pledge_request_message(p_tenant_id, p_event_id, p_event_member_id);
  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, original_outbox_id, batch_id, sender_id, provider)
  values (p_tenant_id, p_event_id, state_record.member_id, p_event_member_id, 'PLEDGE_REQUEST', state_record.phone, message, 'QUEUED', idempotency, p_original_outbox_id, p_batch_id, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;
  return jsonb_build_object('queued', true, 'template', 'PLEDGE_REQUEST', 'outboxId', outbox_id, 'memberId', state_record.member_id, 'status', 'QUEUED', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
end;
$$;

create or replace function public.rpc_claim_tenant_sms_outbox(p_tenant_id uuid, p_batch_size integer default 10, p_outbox_ids uuid[] default null, p_batch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  with candidates as (
    select o.id
    from public.sms_outbox o
    left join public.payments p on p.id = o.payment_id
    where o.tenant_id = p_tenant_id
      and o.status in ('QUEUED', 'FAILED')
      and o.next_attempt_at <= now()
      and o.attempt_count < o.max_attempts
      and (p_outbox_ids is null or o.id = any(p_outbox_ids))
      and (p_batch_id is null or o.batch_id = p_batch_id)
      and (o.payment_id is null or p.status <> 'REVERSED')
      and o.provider is not null
      and o.sender_id is not null
      and exists (select 1 from public.sms_providers sp where sp.code = o.provider and sp.status = 'ACTIVE')
      and exists (select 1 from public.sms_provider_sender_ids s where s.provider_code = o.provider and s.sender_id = o.sender_id and s.status = 'ACTIVE')
      and (o.template_code <> 'BALANCE_REMINDER' or exists (select 1 from public.pledges pl where pl.event_member_id = o.event_member_id and pl.status <> 'CANCELLED' and greatest(pl.pledged_amount - public.confirmed_pledge_allocated_amount(pl.id), 0) > 0))
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
    returning o.id, o.tenant_id, o.event_id, o.member_id, o.payment_id, o.receipt_id, o.template_code, o.phone_e164, o.message_body, o.status, o.attempt_count, o.max_attempts, o.sender_id, o.provider
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into result from claimed;
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
      and o.provider is not null
      and o.sender_id is not null
      and exists (select 1 from public.sms_providers sp where sp.code = o.provider and sp.status = 'ACTIVE')
      and exists (select 1 from public.sms_provider_sender_ids s where s.provider_code = o.provider and s.sender_id = o.sender_id and s.status = 'ACTIVE')
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
    returning o.id, o.tenant_id, o.event_id, o.member_id, o.payment_id, o.receipt_id, o.template_code, o.phone_e164, o.message_body, o.status, o.attempt_count, o.max_attempts, o.sender_id, o.provider
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into result from claimed;
  return result;
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
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.view') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb) into result
  from (
    select o.id, o.tenant_id, o.event_id, e.name as event_name, o.member_id, m.full_name as member_name, o.payment_id, o.receipt_id, o.template_code,
      case o.template_code when 'PLEDGE_REQUEST' then 'Pledge Request' when 'PLEDGE_REGISTRATION' then 'Pledge Registration' when 'PAYMENT_CONFIRMATION' then 'Payment Confirmation' when 'BALANCE_REMINDER' then 'Balance Reminder' when 'PLEDGE_COMPLETED' then 'Pledge Completed' else initcap(replace(coalesce(o.template_code, 'Message'), '_', ' ')) end as message_type,
      o.phone_e164, o.sender_id, o.provider, coalesce(p.name, o.provider, 'Unknown') as provider_name, o.message_body, o.character_count, o.max_characters_at_send, o.status, o.attempt_count, o.created_at, o.sent_at, o.delivered_at, o.failed_at, o.last_error_code,
      case when o.template_code = 'PLEDGE_REQUEST' and o.status = 'CANCELLED' and o.last_error_code = 'PLEDGE_ALREADY_REGISTERED' then 'Member has already pledged' else o.last_error_message end as last_error_message,
      o.original_outbox_id, o.batch_id
    from public.sms_outbox o
    left join public.events e on e.id = o.event_id
    left join public.members m on m.id = o.member_id
    left join public.sms_providers p on p.code = o.provider
    where o.tenant_id = p_tenant_id
  ) row_data;
  return result;
end;
$$;

grant execute on function public.normalize_sms_provider_code(text) to authenticated;
grant execute on function public.sms_default_provider_code() to authenticated;
grant execute on function public.sms_provider_default_sender_id(text) to authenticated;
grant execute on function public.validate_sms_provider_sender(text, text) to authenticated;
grant execute on function public.tenant_sms_provider_settings(uuid) to authenticated;
grant execute on function public.tenant_sms_provider_code(uuid) to authenticated;
grant execute on function public.sms_active_providers_json() to authenticated;
grant execute on function public.platform_sms_providers_json() to authenticated;
grant execute on function public.rpc_get_sms_provider_options(uuid) to authenticated;
grant execute on function public.rpc_get_platform_sms_providers() to authenticated;
grant execute on function public.rpc_update_platform_sms_provider(text, text, boolean) to authenticated;
grant execute on function public.rpc_update_platform_sms_sender_id(text, text, text, boolean) to authenticated;
grant execute on function public.rpc_update_sms_settings(uuid, boolean, text, text, text) to authenticated;
grant execute on function public.rpc_claim_sms_outbox(integer) to authenticated;

notify pgrst, 'reload schema';
