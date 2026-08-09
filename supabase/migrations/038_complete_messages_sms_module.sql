insert into public.permissions (code, name, description) values
('messages.manage_settings', 'Manage message settings', 'Configure tenant SMS sender and enablement')
on conflict (code) do update set name = excluded.name, description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'messages.manage_settings'
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN')
on conflict do nothing;

alter table public.sms_templates
  add column if not exists allowed_variables jsonb not null default '[]'::jsonb;

alter table public.sms_outbox
  add column if not exists sender_id text,
  add column if not exists provider text;

alter table public.tenant_settings
  add column if not exists sms_enabled boolean not null default true,
  add column if not exists sms_sender_id text not null default 'MICHANGO',
  add column if not exists sms_default_language text not null default 'sw';

create or replace function public.sms_allowed_sender_ids()
returns text[]
language sql
immutable
as $$
  select array['MICHANGO', 'SHEREHE', 'KIKAO']::text[];
$$;

create or replace function public.normalize_sms_sender_id(p_sender_id text)
returns text
language plpgsql
immutable
as $$
declare
  normalized text := upper(btrim(coalesce(p_sender_id, 'MICHANGO')));
begin
  if normalized = '' then
    normalized := 'MICHANGO';
  end if;
  if not (normalized = any(public.sms_allowed_sender_ids())) then
    raise exception 'SMS_SENDER_ID_NOT_ALLOWED' using errcode = '22023';
  end if;
  return normalized;
end;
$$;

create or replace function public.sms_template_allowed_variables(p_code text)
returns jsonb
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_code, '')))
    when 'PLEDGE_REGISTRATION' then '["member_name","pledge_amount","event_name","due_date"]'::jsonb
    when 'PAYMENT_CONFIRMATION' then '["member_name","payment_amount","payment_method","event_name","balance","receipt_number"]'::jsonb
    when 'BALANCE_REMINDER' then '["member_name","event_name","balance","due_date"]'::jsonb
    when 'PLEDGE_COMPLETED' then '["member_name","pledge_amount","event_name"]'::jsonb
    else '[]'::jsonb
  end;
$$;

create or replace function public.validate_sms_template_body()
returns trigger
language plpgsql
as $$
declare
  variable_name text;
  allowed jsonb;
begin
  new.code := upper(btrim(new.code));
  new.allowed_variables := public.sms_template_allowed_variables(new.code);
  if jsonb_array_length(new.allowed_variables) = 0 then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  if length(new.body) > 918 or new.body ~ '<[^>]+>' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  for variable_name in
    select distinct match[1]
    from regexp_matches(new.body, '\{\{\s*([a-zA-Z0-9_]+)\s*\}\}', 'g') as match
  loop
    if variable_name in ('password', 'pin', 'otp') or not exists (select 1 from jsonb_array_elements_text(new.allowed_variables) allowed_value(value) where allowed_value.value = variable_name) then
      raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists sms_templates_validate_body on public.sms_templates;
create trigger sms_templates_validate_body
before insert or update on public.sms_templates
for each row execute function public.validate_sms_template_body();

insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active, allowed_variables)
values
(null, 'PLEDGE_REGISTRATION', 'Pledge Registration', 'SMS', 'Ndugu {{member_name}}, ahadi yako ya TZS {{pledge_amount}} kwa ajili ya {{event_name}} imesajiliwa. Tarehe ya mwisho ya malipo ni {{due_date}}. Asante.', 'sw', true, true, public.sms_template_allowed_variables('PLEDGE_REGISTRATION')),
(null, 'PAYMENT_CONFIRMATION', 'Payment Confirmation', 'SMS', 'Ndugu {{member_name}}, tumepokea TZS {{payment_amount}} kupitia {{payment_method}} kwa ajili ya {{event_name}}. Salio la ahadi yako ni TZS {{balance}}. Risiti: {{receipt_number}}.', 'sw', true, true, public.sms_template_allowed_variables('PAYMENT_CONFIRMATION')),
(null, 'BALANCE_REMINDER', 'Balance Reminder', 'SMS', 'Ndugu {{member_name}}, salio la ahadi yako kwa ajili ya {{event_name}} ni TZS {{balance}}. Tafadhali kamilisha kabla ya {{due_date}}.', 'sw', true, true, public.sms_template_allowed_variables('BALANCE_REMINDER')),
(null, 'PLEDGE_COMPLETED', 'Pledge Completed', 'SMS', 'Ndugu {{member_name}}, tumepokea malipo kamili ya ahadi yako ya TZS {{pledge_amount}} kwa ajili ya {{event_name}}. Tunakushukuru.', 'sw', true, true, public.sms_template_allowed_variables('PLEDGE_COMPLETED'))
on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language)
do update set
  name = excluded.name,
  body = excluded.body,
  allowed_variables = excluded.allowed_variables,
  is_system = true,
  is_active = true,
  updated_at = now()
where sms_templates.tenant_id is null;

update public.sms_templates
set allowed_variables = public.sms_template_allowed_variables(code)
where allowed_variables = '[]'::jsonb or allowed_variables is null;

update public.tenant_settings
set sms_sender_id = public.normalize_sms_sender_id(coalesce(sms_sender_id, sms_sender_name, 'MICHANGO')),
    sms_default_language = case when sms_default_language in ('sw', 'en') then sms_default_language else 'sw' end;

alter table public.tenant_settings
drop constraint if exists tenant_settings_sms_sender_id_allowed;
alter table public.tenant_settings
add constraint tenant_settings_sms_sender_id_allowed
check (sms_sender_id = any(public.sms_allowed_sender_ids()));

alter table public.tenant_settings
drop constraint if exists tenant_settings_sms_default_language_allowed;
alter table public.tenant_settings
add constraint tenant_settings_sms_default_language_allowed
check (sms_default_language in ('sw', 'en'));

update public.sms_outbox
set sender_id = public.normalize_sms_sender_id(coalesce(sender_id, 'MICHANGO')),
    provider = coalesce(nullif(provider, ''), 'WEBBULKSMS');

alter table public.sms_outbox
drop constraint if exists sms_outbox_sender_id_allowed;
alter table public.sms_outbox
add constraint sms_outbox_sender_id_allowed
check (sender_id is null or sender_id = any(public.sms_allowed_sender_ids()));

create unique index if not exists sms_outbox_payment_financial_auto_unique
on public.sms_outbox(payment_id)
where payment_id is not null and template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED') and status <> 'CANCELLED';

create or replace function public.tenant_sms_settings_json(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'smsEnabled', coalesce(ts.sms_enabled, true),
    'senderId', public.normalize_sms_sender_id(coalesce(ts.sms_sender_id, 'MICHANGO')),
    'defaultLanguage', coalesce(nullif(ts.sms_default_language, ''), 'sw'),
    'allowedSenderIds', to_jsonb(public.sms_allowed_sender_ids())
  )
  from public.tenant_settings ts
  where ts.tenant_id = p_tenant_id;
$$;

create or replace function public.tenant_sms_sender_id(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.normalize_sms_sender_id(coalesce((select sms_sender_id from public.tenant_settings where tenant_id = p_tenant_id), 'MICHANGO'));
$$;

create or replace function public.tenant_sms_enabled(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((select sms_enabled from public.tenant_settings where tenant_id = p_tenant_id), true);
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

create or replace function public.rpc_update_sms_settings(p_tenant_id uuid, p_sms_enabled boolean, p_sender_id text, p_default_language text default 'sw')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_settings') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  update public.tenant_settings
  set sms_enabled = coalesce(p_sms_enabled, true),
      sms_sender_id = public.normalize_sms_sender_id(p_sender_id),
      sms_default_language = case when coalesce(p_default_language, 'sw') in ('sw', 'en') then coalesce(p_default_language, 'sw') else 'sw' end
  where tenant_id = p_tenant_id;
  return public.tenant_sms_settings_json(p_tenant_id);
end;
$$;

create or replace function public.resolve_sms_template_body(p_tenant_id uuid, p_code text, p_language text)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select body
  from public.sms_templates
  where code = upper(btrim(p_code))
    and channel = 'SMS'
    and language = coalesce(nullif(p_language, ''), 'sw')
    and is_active
    and (tenant_id = p_tenant_id or tenant_id is null)
  order by case when tenant_id = p_tenant_id then 0 else 1 end
  limit 1;
$$;

create or replace function public.sms_template_detail(p_tenant_id uuid, p_code text, p_language text default 'sw')
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with selected as (
    select *
    from public.sms_templates
    where code = upper(btrim(p_code))
      and channel = 'SMS'
      and language = coalesce(nullif(p_language, ''), 'sw')
      and is_active
      and (tenant_id = p_tenant_id or tenant_id is null)
    order by case when tenant_id = p_tenant_id then 0 else 1 end
    limit 1
  ),
  system_default as (
    select body
    from public.sms_templates
    where tenant_id is null and code = upper(btrim(p_code)) and language = coalesce(nullif(p_language, ''), 'sw') and is_active
    limit 1
  )
  select jsonb_build_object(
    'code', upper(btrim(p_code)),
    'name', coalesce((select name from selected), initcap(replace(upper(btrim(p_code)), '_', ' '))),
    'language', coalesce(nullif(p_language, ''), 'sw'),
    'body', (select body from selected),
    'systemBody', (select body from system_default),
    'hasTenantOverride', exists(select 1 from selected where tenant_id = p_tenant_id),
    'variables', public.sms_template_allowed_variables(p_code),
    'isActive', exists(select 1 from selected)
  );
$$;

create or replace function public.rpc_list_sms_templates(p_tenant_id uuid)
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
  return jsonb_build_array(
    public.sms_template_detail(p_tenant_id, 'PLEDGE_REGISTRATION', 'sw'),
    public.sms_template_detail(p_tenant_id, 'PAYMENT_CONFIRMATION', 'sw'),
    public.sms_template_detail(p_tenant_id, 'BALANCE_REMINDER', 'sw'),
    public.sms_template_detail(p_tenant_id, 'PLEDGE_COMPLETED', 'sw')
  );
end;
$$;

create or replace function public.rpc_upsert_sms_template(p_tenant_id uuid, p_code text, p_body text, p_language text default 'sw')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  normalized_body text := btrim(coalesce(p_body, ''));
  display_name text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if normalized_body = '' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  display_name := case normalized_code
    when 'PLEDGE_REGISTRATION' then 'Pledge Registration'
    when 'PAYMENT_CONFIRMATION' then 'Payment Confirmation'
    when 'BALANCE_REMINDER' then 'Balance Reminder'
    when 'PLEDGE_COMPLETED' then 'Pledge Completed'
    else null
  end;
  if display_name is null then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active, allowed_variables)
  values (p_tenant_id, normalized_code, display_name, 'SMS', normalized_body, coalesce(nullif(p_language, ''), 'sw'), false, true, public.sms_template_allowed_variables(normalized_code))
  on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language)
  do update set body = excluded.body, is_active = true, allowed_variables = excluded.allowed_variables, updated_at = now();
  return public.sms_template_detail(p_tenant_id, normalized_code, p_language);
end;
$$;

create or replace function public.rpc_reset_sms_template(p_tenant_id uuid, p_code text, p_language text default 'sw')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
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
    and code = normalized_code
    and language = coalesce(nullif(p_language, ''), 'sw');
  return public.sms_template_detail(p_tenant_id, normalized_code, p_language);
end;
$$;

create or replace function public.rpc_get_balance_reminder_template(p_tenant_id uuid)
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
  return public.sms_template_detail(p_tenant_id, 'BALANCE_REMINDER', 'sw');
end;
$$;

create or replace function public.rpc_upsert_balance_reminder_template(p_tenant_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return public.rpc_upsert_sms_template(p_tenant_id, 'BALANCE_REMINDER', p_body, 'sw');
end;
$$;

create or replace function public.rpc_reset_balance_reminder_template(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return public.rpc_reset_sms_template(p_tenant_id, 'BALANCE_REMINDER', 'sw');
end;
$$;

create or replace function public.pledge_due_date_text(p_due_date date)
returns text
language sql
immutable
as $$
  select case when p_due_date is null then '' else to_char(p_due_date, 'DD/MM/YYYY') end;
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
  if state_record.due_date is null then
    template_body := 'Ndugu {{member_name}}, salio la ahadi yako kwa ajili ya {{event_name}} ni TZS {{balance}}. Tafadhali kamilisha malipo yako.';
  else
    template_body := public.resolve_sms_template_body(p_tenant_id, 'BALANCE_REMINDER', state_record.preferred_language);
  end if;
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;
  return public.render_sms_template(template_body, jsonb_build_object(
    'member_name', state_record.full_name,
    'event_name', state_record.event_name,
    'balance', public.format_tzs_sms_amount(state_record.outstanding_amount),
    'due_date', public.pledge_due_date_text(state_record.due_date)
  ));
end;
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
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED', 'template', 'PLEDGE_REGISTRATION');
  end if;
  select * into pledge_record from public.pledges where id = p_pledge_id and tenant_id = p_tenant_id and event_id = p_event_id;
  if not found then
    raise exception 'PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;
  select m.* into member_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = pledge_record.event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  if member_record.phone_e164 is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'NO_PHONE', 'template', 'PLEDGE_REGISTRATION');
  end if;
  if coalesce(member_record.sms_enabled, true) = false then
    return jsonb_build_object('smsQueued', false, 'reason', 'SMS_DISABLED', 'template', 'PLEDGE_REGISTRATION');
  end if;
  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  effective_due_date := coalesce(pledge_record.due_date, event_record.pledge_deadline);
  idempotency := 'PLEDGE_REGISTRATION:' || pledge_record.id::text;
  select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
  if found then
    return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', 'PLEDGE_REGISTRATION');
  end if;
  if effective_due_date is null then
    template_body := 'Ndugu {{member_name}}, ahadi yako ya TZS {{pledge_amount}} kwa ajili ya {{event_name}} imesajiliwa. Asante.';
  else
    template_body := public.resolve_sms_template_body(p_tenant_id, 'PLEDGE_REGISTRATION', member_record.preferred_language);
  end if;
  if template_body is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'TEMPLATE_NOT_FOUND', 'template', 'PLEDGE_REGISTRATION');
  end if;
  message := public.render_sms_template(template_body, jsonb_build_object(
    'member_name', member_record.full_name,
    'pledge_amount', public.format_tzs_sms_amount(pledge_record.pledged_amount),
    'event_name', event_record.name,
    'due_date', public.pledge_due_date_text(effective_due_date)
  ));
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, sender_id, provider)
  values (p_tenant_id, p_event_id, member_record.id, pledge_record.event_member_id, 'PLEDGE_REGISTRATION', member_record.phone_e164, message, 'QUEUED', idempotency, public.tenant_sms_sender_id(p_tenant_id), coalesce(nullif(current_setting('app.sms_provider', true), ''), 'NEXTSMS'))
  returning id into outbox_id;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'template', 'PLEDGE_REGISTRATION');
exception
  when unique_violation then
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
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  select * into payment_record from public.payments where id = p_payment_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;
  if not public.has_event_financial_access(payment_record.tenant_id, payment_record.event_id, 'payments.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if payment_record.status = 'REVERSED' then
    return jsonb_build_object('smsQueued', false, 'reason', 'PAYMENT_REVERSED');
  end if;
  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED');
  end if;
  select m.* into member_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = payment_record.event_member_id and em.tenant_id = p_tenant_id and em.event_id = payment_record.event_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  if member_record.phone_e164 is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'NO_PHONE');
  end if;
  if coalesce(member_record.sms_enabled, true) = false then
    return jsonb_build_object('smsQueued', false, 'reason', 'SMS_DISABLED');
  end if;
  select * into event_record from public.events where id = payment_record.event_id and tenant_id = p_tenant_id;
  select * into receipt_record from public.receipts where payment_id = payment_record.id and tenant_id = p_tenant_id;
  if receipt_record.id is null then
    raise exception 'RECEIPT_NOT_FOUND' using errcode = '22023';
  end if;
  select p.* into pledge_record
  from public.payment_allocations pa
  join public.pledges p on p.id = pa.pledge_id
  where pa.payment_id = payment_record.id
  order by pa.created_at desc
  limit 1;
  outstanding := coalesce((
    select sum(greatest(pl.pledged_amount - public.confirmed_pledge_allocated_amount(pl.id), 0))
    from public.pledges pl
    where pl.event_member_id = payment_record.event_member_id and pl.status <> 'CANCELLED'
  ), 0)::numeric(18,2);
  template_code := case when outstanding <= 0 then 'PLEDGE_COMPLETED' else 'PAYMENT_CONFIRMATION' end;
  idempotency := template_code || ':' || payment_record.id::text;
  select id into outbox_id
  from public.sms_outbox
  where payment_id = payment_record.id
    and template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED')
    and status <> 'CANCELLED'
  limit 1;
  if found then
    return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', template_code);
  end if;
  template_body := public.resolve_sms_template_body(p_tenant_id, template_code, member_record.preferred_language);
  if template_body is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'TEMPLATE_NOT_FOUND', 'template', template_code);
  end if;
  message := public.render_sms_template(template_body, jsonb_build_object(
    'member_name', member_record.full_name,
    'payment_amount', public.format_tzs_sms_amount(payment_record.amount),
    'payment_method', public.payment_method_sms_name(payment_record.payment_method),
    'event_name', event_record.name,
    'balance', public.format_tzs_sms_amount(outstanding),
    'receipt_number', receipt_record.receipt_number,
    'pledge_amount', public.format_tzs_sms_amount(coalesce(pledge_record.pledged_amount, payment_record.amount))
  ));
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, payment_id, receipt_id, template_code, phone_e164, message_body, status, idempotency_key, sender_id, provider)
  values (p_tenant_id, payment_record.event_id, member_record.id, payment_record.event_member_id, payment_record.id, receipt_record.id, template_code, member_record.phone_e164, message, 'QUEUED', idempotency, public.tenant_sms_sender_id(p_tenant_id), coalesce(nullif(current_setting('app.sms_provider', true), ''), 'NEXTSMS'))
  returning id into outbox_id;
  return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'template', template_code);
exception
  when unique_violation then
    select id into outbox_id from public.sms_outbox where payment_id = p_payment_id and template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED') and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('smsQueued', true, 'outboxId', outbox_id, 'reason', 'ALREADY_QUEUED', 'template', template_code);
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
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
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
      and (
        o.template_code <> 'BALANCE_REMINDER'
        or exists (
          select 1
          from public.pledges pl
          where pl.event_member_id = o.event_member_id
            and pl.status <> 'CANCELLED'
            and greatest(pl.pledged_amount - public.confirmed_pledge_allocated_amount(pl.id), 0) > 0
        )
      )
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
    returning o.id, o.tenant_id, o.event_id, o.member_id, o.payment_id, o.receipt_id, o.template_code, o.phone_e164, o.message_body, o.status, o.attempt_count, o.max_attempts, o.sender_id, coalesce(o.provider, 'WEBBULKSMS') as provider
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
      case o.template_code
        when 'PLEDGE_REGISTRATION' then 'Pledge Registration'
        when 'PAYMENT_CONFIRMATION' then 'Payment Confirmation'
        when 'BALANCE_REMINDER' then 'Balance Reminder'
        when 'PLEDGE_COMPLETED' then 'Pledge Completed'
        else initcap(replace(coalesce(o.template_code, 'Message'), '_', ' '))
      end as message_type,
      o.phone_e164,
      o.sender_id,
      coalesce(o.provider, 'WEBBULKSMS') as provider,
      o.message_body,
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

create or replace function public.rpc_resend_failed_sms(p_tenant_id uuid, p_outbox_id uuid, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  original_record public.sms_outbox%rowtype;
  outbox_id uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  select * into original_record from public.sms_outbox where id = p_outbox_id and tenant_id = p_tenant_id and status = 'FAILED';
  if not found then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, payment_id, receipt_id, template_code, phone_e164, message_body, status, idempotency_key, original_outbox_id, batch_id, sender_id, provider)
  values (p_tenant_id, original_record.event_id, original_record.member_id, original_record.event_member_id, null, original_record.receipt_id, original_record.template_code, original_record.phone_e164, original_record.message_body, 'QUEUED', p_idempotency_key, original_record.id, original_record.batch_id, original_record.sender_id, original_record.provider)
  returning id into outbox_id;
  return jsonb_build_object('queued', true, 'outboxId', outbox_id, 'template', original_record.template_code);
end;
$$;

grant execute on function public.sms_allowed_sender_ids() to authenticated;
grant execute on function public.normalize_sms_sender_id(text) to authenticated;
grant execute on function public.sms_template_allowed_variables(text) to authenticated;
grant execute on function public.tenant_sms_settings_json(uuid) to authenticated;
grant execute on function public.tenant_sms_sender_id(uuid) to authenticated;
grant execute on function public.tenant_sms_enabled(uuid) to authenticated;
grant execute on function public.rpc_get_sms_settings(uuid) to authenticated;
grant execute on function public.rpc_update_sms_settings(uuid, boolean, text, text) to authenticated;
grant execute on function public.sms_template_detail(uuid, text, text) to authenticated;
grant execute on function public.rpc_list_sms_templates(uuid) to authenticated;
grant execute on function public.rpc_upsert_sms_template(uuid, text, text, text) to authenticated;
grant execute on function public.rpc_reset_sms_template(uuid, text, text) to authenticated;
grant execute on function public.rpc_enqueue_pledge_registration_sms(uuid, uuid, uuid) to authenticated;
grant execute on function public.rpc_claim_tenant_sms_outbox(uuid, integer, uuid[], uuid) to authenticated;
grant execute on function public.rpc_resend_failed_sms(uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
