alter table public.sms_outbox
  add column if not exists character_count integer,
  add column if not exists max_characters_at_send integer;

create or replace function public.sms_max_characters()
returns integer
language sql
immutable
as $$
  select 159;
$$;

create or replace function public.normalize_sms_message_text(p_message text)
returns text
language sql
immutable
as $$
  select btrim(regexp_replace(regexp_replace(coalesce(p_message, ''), E'[\\r\\n]+', ' ', 'g'), '[[:space:]]+', ' ', 'g'));
$$;

create or replace function public.sms_character_count(p_message text)
returns integer
language sql
immutable
as $$
  select char_length(public.normalize_sms_message_text(p_message));
$$;

create or replace function public.validate_sms_outbox_message_size()
returns trigger
language plpgsql
as $$
begin
  new.message_body := public.normalize_sms_message_text(new.message_body);
  new.character_count := public.sms_character_count(new.message_body);
  new.max_characters_at_send := public.sms_max_characters();
  if new.character_count > new.max_characters_at_send then
    raise exception 'SMS_CHARACTER_LIMIT_EXCEEDED' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists sms_outbox_validate_message_size on public.sms_outbox;
create trigger sms_outbox_validate_message_size
before insert or update of message_body on public.sms_outbox
for each row execute function public.validate_sms_outbox_message_size();

update public.sms_outbox
set character_count = public.sms_character_count(message_body),
    max_characters_at_send = public.sms_max_characters()
where character_count is null or max_characters_at_send is null;

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
    'senderId', public.normalize_sms_sender_id(p_sender_id),
    'message', public.normalize_sms_message_text(p_message),
    'characters', public.sms_character_count(p_message),
    'maxCharacters', public.sms_max_characters(),
    'remainingCharacters', public.sms_max_characters() - public.sms_character_count(p_message),
    'valid', public.sms_character_count(p_message) <= public.sms_max_characters(),
    'reason', case when public.sms_character_count(p_message) > public.sms_max_characters() then 'SMS_CHARACTER_LIMIT_EXCEEDED' else null end
  );
$$;

create or replace function public.compact_default_sms_template(p_code text, p_has_due_date boolean default true)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_code, '')))
    when 'PLEDGE_REQUEST' then case when coalesce(p_has_due_date, true)
      then 'Ndugu {{member_name}}, tunaomba uweke ahadi yako kwa ajili ya {{event_name}} kabla ya {{pledge_deadline}}. Asante.'
      else 'Ndugu {{member_name}}, tunaomba uweke ahadi yako kwa ajili ya {{event_name}}. Asante.'
    end
    when 'PLEDGE_REGISTRATION' then case when coalesce(p_has_due_date, true)
      then 'Ndugu {{member_name}}, ahadi yako ya TZS {{pledge_amount}} kwa {{event_name}} imesajiliwa. Mwisho: {{due_date}}. Asante.'
      else 'Ndugu {{member_name}}, ahadi yako ya TZS {{pledge_amount}} kwa {{event_name}} imesajiliwa. Asante.'
    end
    when 'PAYMENT_CONFIRMATION' then 'Ndugu {{member_name}}, tumepokea TZS {{payment_amount}} kupitia {{payment_method}} kwa {{event_name}}. Salio: TZS {{balance}}. Risiti: {{receipt_number}}.'
    when 'BALANCE_REMINDER' then case when coalesce(p_has_due_date, true)
      then 'Ndugu {{member_name}}, salio la ahadi yako kwa {{event_name}} ni TZS {{balance}}. Tafadhali kamilisha kabla ya {{due_date}}.'
      else 'Ndugu {{member_name}}, salio la ahadi yako kwa {{event_name}} ni TZS {{balance}}. Tafadhali kamilisha malipo. Asante.'
    end
    when 'PLEDGE_COMPLETED' then 'Ndugu {{member_name}}, ahadi yako ya TZS {{pledge_amount}} kwa {{event_name}} imekamilika. Tunakushukuru.'
    else ''
  end;
$$;

update public.sms_templates
set body = case code
    when 'PLEDGE_REQUEST' then public.compact_default_sms_template('PLEDGE_REQUEST', true)
    when 'PLEDGE_REGISTRATION' then public.compact_default_sms_template('PLEDGE_REGISTRATION', true)
    when 'PAYMENT_CONFIRMATION' then public.compact_default_sms_template('PAYMENT_CONFIRMATION', true)
    when 'BALANCE_REMINDER' then public.compact_default_sms_template('BALANCE_REMINDER', true)
    when 'PLEDGE_COMPLETED' then public.compact_default_sms_template('PLEDGE_COMPLETED', true)
    else body
  end,
  updated_at = now()
where tenant_id is null
  and code in ('PLEDGE_REQUEST', 'PLEDGE_REGISTRATION', 'PAYMENT_CONFIRMATION', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED');

create or replace function public.sms_template_detail(p_tenant_id uuid, p_code text, p_language text default 'sw')
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_body text;
  system_body text;
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  sample_message text;
begin
  select body into tenant_body from public.sms_templates where tenant_id = p_tenant_id and code = normalized_code and language = coalesce(nullif(p_language, ''), 'sw') and is_active limit 1;
  select body into system_body from public.sms_templates where tenant_id is null and code = normalized_code and language = coalesce(nullif(p_language, ''), 'sw') and is_active limit 1;
  sample_message := public.render_sms_template(coalesce(tenant_body, system_body, ''), jsonb_build_object(
    'member_name', 'Christopher Godfrey Mrema',
    'event_name', 'Harusi ya Christopher na Neema',
    'pledge_amount', '1,500,000',
    'payment_amount', '500,000',
    'payment_method', 'M-Pesa',
    'balance', '1,000,000',
    'due_date', '31/12/2026',
    'pledge_deadline', '31/12/2026',
    'event_date', '31/12/2026',
    'receipt_number', 'RCT-2026-000123'
  ));
  return jsonb_build_object(
    'code', normalized_code,
    'templateCode', normalized_code,
    'language', coalesce(nullif(p_language, ''), 'sw'),
    'body', coalesce(tenant_body, system_body),
    'systemBody', system_body,
    'hasTenantOverride', tenant_body is not null,
    'variables', public.sms_template_allowed_variables(normalized_code),
    'maxCharacters', public.sms_max_characters(),
    'templateCharacters', public.sms_character_count(coalesce(tenant_body, system_body, '')),
    'samplePreview', public.normalize_sms_message_text(sample_message),
    'samplePreviewCharacters', public.sms_character_count(sample_message),
    'samplePreviewValid', public.sms_character_count(sample_message) <= public.sms_max_characters()
  );
end;
$$;

create or replace function public.render_pledge_request_message(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid)
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
  select * into state_record from public.pledge_request_state(p_tenant_id, p_event_id) where event_member_id = p_event_member_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  if state_record.pledge_deadline is null then
    template_body := public.compact_default_sms_template('PLEDGE_REQUEST', false);
  else
    template_body := public.resolve_sms_template_body(p_tenant_id, 'PLEDGE_REQUEST', 'sw');
  end if;
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;
  return public.normalize_sms_message_text(public.render_sms_template(template_body, jsonb_build_object(
    'member_name', state_record.full_name,
    'event_name', state_record.event_name,
    'event_date', public.pledge_request_date_text(state_record.event_date),
    'pledge_deadline', public.pledge_request_date_text(state_record.pledge_deadline)
  )));
end;
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
  select * into state_record from public.balance_reminder_financial_state(p_tenant_id, p_event_id) where event_member_id = p_event_member_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  if state_record.due_date is null then
    template_body := public.compact_default_sms_template('BALANCE_REMINDER', false);
  else
    template_body := public.resolve_sms_template_body(p_tenant_id, 'BALANCE_REMINDER', state_record.preferred_language);
  end if;
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;
  return public.normalize_sms_message_text(public.render_sms_template(template_body, jsonb_build_object(
    'member_name', state_record.full_name,
    'event_name', state_record.event_name,
    'balance', public.format_tzs_sms_amount(state_record.outstanding_amount),
    'due_date', public.pledge_due_date_text(state_record.due_date)
  )));
end;
$$;

create or replace function public.rpc_preview_event_member_sms(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid, p_template_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_template_code, '')));
  member_record record;
  message text;
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
  select em.id as event_member_id, m.full_name, m.phone_e164
  into member_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = p_event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  if normalized_code = 'PLEDGE_REQUEST' then
    message := public.render_pledge_request_message(p_tenant_id, p_event_id, p_event_member_id);
  elsif normalized_code = 'BALANCE_REMINDER' then
    message := public.render_balance_reminder_message(p_tenant_id, p_event_id, p_event_member_id);
  else
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  return public.sms_preview_json(normalized_code, p_event_member_id, member_record.full_name, member_record.phone_e164, public.tenant_sms_sender_id(p_tenant_id), message);
end;
$$;

create or replace function public.rpc_preview_event_member_sms_bulk(p_tenant_id uuid, p_event_id uuid, p_event_member_ids uuid[], p_template_code text, p_cooldown_hours integer default 24)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_template_code, '')));
  previews jsonb := '[]'::jsonb;
  row_record record;
  preview jsonb;
  selected_count integer := coalesce(array_length(p_event_member_ids, 1), 0);
  eligible_count integer := 0;
  valid_count integer := 0;
  over_count integer := 0;
  no_phone integer := 0;
  sms_disabled integer := 0;
  recently_sent integer := 0;
  has_pledge integer := 0;
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

  if normalized_code = 'PLEDGE_REQUEST' then
    for row_record in
      select state.*, public.pledge_request_ineligibility_reason(state.phone, state.sms_enabled, state.has_pledge, state.last_pledge_request_at, p_cooldown_hours) as reason
      from public.pledge_request_state(p_tenant_id, p_event_id) state
      join unnest(p_event_member_ids) ids(id) on ids.id = state.event_member_id
    loop
      if row_record.reason = 'NO_PHONE' then no_phone := no_phone + 1;
      elsif row_record.reason = 'SMS_DISABLED' then sms_disabled := sms_disabled + 1;
      elsif row_record.reason = 'RECENTLY_SENT' then recently_sent := recently_sent + 1;
      elsif row_record.reason = 'HAS_PLEDGE' then has_pledge := has_pledge + 1;
      else
        eligible_count := eligible_count + 1;
        preview := public.rpc_preview_event_member_sms(p_tenant_id, p_event_id, row_record.event_member_id, normalized_code);
        if preview ->> 'valid' = 'true' then valid_count := valid_count + 1; else over_count := over_count + 1; end if;
        previews := previews || jsonb_build_array(preview);
      end if;
    end loop;
  elsif normalized_code = 'BALANCE_REMINDER' then
    for row_record in
      select state.*, public.balance_reminder_ineligibility_reason(state.phone, state.sms_enabled, state.outstanding_amount, state.last_balance_reminder_at, p_cooldown_hours) as reason
      from public.balance_reminder_financial_state(p_tenant_id, p_event_id) state
      join unnest(p_event_member_ids) ids(id) on ids.id = state.event_member_id
    loop
      if row_record.reason = 'NO_PHONE' then no_phone := no_phone + 1;
      elsif row_record.reason = 'SMS_DISABLED' then sms_disabled := sms_disabled + 1;
      elsif row_record.reason = 'RECENTLY_SENT' then recently_sent := recently_sent + 1;
      else
        eligible_count := eligible_count + 1;
        preview := public.rpc_preview_event_member_sms(p_tenant_id, p_event_id, row_record.event_member_id, normalized_code);
        if preview ->> 'valid' = 'true' then valid_count := valid_count + 1; else over_count := over_count + 1; end if;
        previews := previews || jsonb_build_array(preview);
      end if;
    end loop;
  else
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'templateCode', normalized_code,
    'selected', selected_count,
    'eligible', eligible_count,
    'validMessages', valid_count,
    'overCharacterLimit', over_count,
    'noPhone', no_phone,
    'smsDisabled', sms_disabled,
    'recentlySent', recently_sent,
    'hasPledge', has_pledge,
    'maxCharacters', public.sms_max_characters(),
    'previews', previews
  );
end;
$$;

grant execute on function public.sms_max_characters() to authenticated;
grant execute on function public.normalize_sms_message_text(text) to authenticated;
grant execute on function public.sms_character_count(text) to authenticated;
grant execute on function public.sms_preview_json(text, uuid, text, text, text, text) to authenticated;
grant execute on function public.compact_default_sms_template(text, boolean) to authenticated;
grant execute on function public.rpc_preview_event_member_sms(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.rpc_preview_event_member_sms_bulk(uuid, uuid, uuid[], text, integer) to authenticated;

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
        when 'PLEDGE_REQUEST' then 'Pledge Request'
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
      o.character_count,
      o.max_characters_at_send,
      o.status,
      o.attempt_count,
      o.created_at,
      o.sent_at,
      o.delivered_at,
      o.failed_at,
      o.last_error_code,
      case when o.template_code = 'PLEDGE_REQUEST' and o.status = 'CANCELLED' and o.last_error_code = 'PLEDGE_ALREADY_REGISTERED' then 'Member has already pledged' else o.last_error_message end as last_error_message,
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

notify pgrst, 'reload schema';
