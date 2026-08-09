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

  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);
  if provider_settings.provider_code is null or provider_settings.sender_id is null then
    raise exception 'SMS_PROVIDER_NOT_CONFIGURED' using errcode = '22023';
  end if;

  idempotency := coalesce(nullif(btrim(p_idempotency_key), ''), gen_random_uuid()::text);
  if exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
    select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('queued', true, 'outboxId', outbox_id, 'status', 'QUEUED', 'reason', 'IDEMPOTENT_REPLAY');
  end if;

  select * into state_record
  from public.balance_reminder_financial_state(p_tenant_id, p_event_id)
  where event_member_id = p_event_member_id;
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;

  reason := public.balance_reminder_ineligibility_reason(state_record.phone, state_record.sms_enabled, state_record.outstanding_amount, state_record.last_balance_reminder_at, p_cooldown_hours);
  if reason = 'NO_OUTSTANDING' then return jsonb_build_object('queued', false, 'template', 'BALANCE_REMINDER', 'reason', 'NO_OUTSTANDING_BALANCE', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
  elsif reason = 'NO_PHONE' then return jsonb_build_object('queued', false, 'template', 'BALANCE_REMINDER', 'reason', 'MEMBER_PHONE_MISSING', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
  elsif reason = 'SMS_DISABLED' then return jsonb_build_object('queued', false, 'template', 'BALANCE_REMINDER', 'reason', 'MEMBER_SMS_DISABLED', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
  elsif reason = 'RECENTLY_SENT' then return jsonb_build_object('queued', false, 'template', 'BALANCE_REMINDER', 'reason', 'RECENTLY_SENT', 'lastSentAt', state_record.last_balance_reminder_at, 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
  end if;

  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if allowance ->> 'status' = 'LIMIT_REACHED' then raise exception 'SMS_LIMIT_REACHED' using errcode = '22023'; end if;

  message := public.render_balance_reminder_message(p_tenant_id, p_event_id, p_event_member_id);

  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, original_outbox_id, batch_id, sender_id, provider)
  values (p_tenant_id, p_event_id, state_record.member_id, p_event_member_id, 'BALANCE_REMINDER', state_record.phone, message, 'QUEUED', idempotency, p_original_outbox_id, p_batch_id, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;

  return jsonb_build_object('queued', true, 'template', 'BALANCE_REMINDER', 'outboxId', outbox_id, 'memberId', state_record.member_id, 'status', 'QUEUED', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
end;
$$;

with repair_rows as (
  select o.id, settings.provider_code, settings.sender_id
  from public.sms_outbox o
  cross join lateral public.tenant_sms_provider_settings(o.tenant_id) settings
  where o.template_code = 'BALANCE_REMINDER'
    and o.status in ('QUEUED', 'FAILED')
    and (o.provider is null or btrim(o.provider) = '' or o.sender_id is null or btrim(o.sender_id) = '')
    and exists (select 1 from public.sms_providers sp where sp.code = settings.provider_code and sp.status = 'ACTIVE')
    and exists (select 1 from public.sms_provider_sender_ids s where s.provider_code = settings.provider_code and s.sender_id = settings.sender_id and s.status = 'ACTIVE')
)
update public.sms_outbox o
set provider = repair_rows.provider_code,
    sender_id = repair_rows.sender_id
from repair_rows
where o.id = repair_rows.id;

drop view if exists public.v_balance_reminder_provider_repair_report;
create view public.v_balance_reminder_provider_repair_report
with (security_invoker = true)
as
select
  count(*) filter (where template_code = 'BALANCE_REMINDER' and status in ('QUEUED', 'FAILED')) as pending_balance_reminders,
  count(*) filter (where template_code = 'BALANCE_REMINDER' and status in ('QUEUED', 'FAILED') and provider is not null and sender_id is not null) as provider_ready_balance_reminders,
  count(*) filter (where template_code = 'BALANCE_REMINDER' and status in ('QUEUED', 'FAILED') and (provider is null or sender_id is null)) as missing_provider_balance_reminders
from public.sms_outbox;

grant execute on function public.rpc_enqueue_balance_reminder_sms(uuid, uuid, uuid, text, integer, uuid, uuid) to authenticated;
grant select on public.v_balance_reminder_provider_repair_report to authenticated;
