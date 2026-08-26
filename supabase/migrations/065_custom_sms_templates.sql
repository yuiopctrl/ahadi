-- Custom (tenant-authored) SMS templates and generic bulk send.
-- Plain SMS blast: only {{member_name}} substitution, no pledge/balance business logic.

alter table public.sms_batches
drop constraint if exists sms_batches_batch_type_check;

alter table public.sms_batches
add constraint sms_batches_batch_type_check
check (batch_type in ('BALANCE_REMINDER', 'PLEDGE_REQUEST', 'PLEDGE_COMPLETED', 'CUSTOM'));

create or replace function public.validate_custom_sms_template_body(p_body text)
returns text
language plpgsql
immutable
as $$
declare
  normalized text := btrim(coalesce(p_body, ''));
  rawVariable text;
begin
  if normalized = '' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  if normalized ~ '<[^>]+>' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  for rawVariable in select (regexp_matches(normalized, '\{\{\s*([^{}]+?)\s*\}\}', 'g'))[1] loop
    if lower(regexp_replace(rawVariable, '[^a-zA-Z0-9]+', '_', 'g')) <> 'member_name' then
      raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
    end if;
  end loop;
  return normalized;
end;
$$;

create or replace function public.generate_custom_sms_template_code(p_tenant_id uuid, p_name text, p_language text)
returns text
language plpgsql
as $$
declare
  base_code text := upper(regexp_replace(btrim(coalesce(p_name, '')), '[^a-zA-Z0-9]+', '_', 'g'));
  candidate text;
  suffix text;
begin
  base_code := btrim(base_code, '_');
  if base_code = '' then
    base_code := 'TEMPLATE';
  end if;
  base_code := 'CUSTOM_' || left(base_code, 40);
  candidate := base_code;
  while exists (
    select 1 from public.sms_templates
    where tenant_id = p_tenant_id and code = candidate and language = p_language
  ) loop
    suffix := substr(md5(random()::text), 1, 4);
    candidate := base_code || '_' || suffix;
  end loop;
  return candidate;
end;
$$;

create or replace function public.custom_sms_template_json(p_row public.sms_templates)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_row.id,
    'code', p_row.code,
    'templateCode', p_row.code,
    'name', p_row.name,
    'body', p_row.body,
    'language', p_row.language,
    'maxCharacters', public.sms_max_characters(),
    'templateCharacters', public.sms_character_count(p_row.body),
    'createdAt', p_row.created_at,
    'updatedAt', p_row.updated_at
  );
$$;

create or replace function public.rpc_list_custom_sms_templates(p_tenant_id uuid)
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
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;

  select coalesce(jsonb_agg(public.custom_sms_template_json(t) order by t.created_at desc), '[]'::jsonb)
  into result
  from public.sms_templates t
  where t.tenant_id = p_tenant_id and t.is_system = false;

  return result;
end;
$$;

create or replace function public.rpc_create_custom_sms_template(p_tenant_id uuid, p_name text, p_body text, p_language text default 'sw')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_body text;
  normalized_language text := coalesce(nullif(btrim(p_language), ''), 'sw');
  normalized_code text;
  inserted public.sms_templates%rowtype;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if normalized_name = '' then raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023'; end if;

  normalized_body := public.validate_custom_sms_template_body(p_body);
  normalized_code := public.generate_custom_sms_template_code(p_tenant_id, normalized_name, normalized_language);

  insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active)
  values (p_tenant_id, normalized_code, normalized_name, 'SMS', normalized_body, normalized_language, false, true)
  returning * into inserted;

  return public.custom_sms_template_json(inserted);
end;
$$;

create or replace function public.rpc_update_custom_sms_template(p_tenant_id uuid, p_code text, p_name text, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_body text;
  updated public.sms_templates%rowtype;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if normalized_name = '' then raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023'; end if;

  normalized_body := public.validate_custom_sms_template_body(p_body);

  update public.sms_templates
  set name = normalized_name, body = normalized_body, updated_at = now()
  where tenant_id = p_tenant_id and code = normalized_code and is_system = false
  returning * into updated;

  if not found then raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023'; end if;

  return public.custom_sms_template_json(updated);
end;
$$;

create or replace function public.rpc_delete_custom_sms_template(p_tenant_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  deleted_count integer;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;

  delete from public.sms_templates
  where tenant_id = p_tenant_id and code = normalized_code and is_system = false;
  get diagnostics deleted_count = row_count;

  if deleted_count = 0 then raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023'; end if;

  return jsonb_build_object('deleted', true, 'code', normalized_code);
end;
$$;

create or replace function public.custom_sms_ineligibility_reason(p_phone text, p_sms_enabled boolean)
returns text
language sql
stable
as $$
  select case
    when p_phone is null or p_phone !~ '^\+255[67][0-9]{8}$' then 'NO_PHONE'
    when coalesce(p_sms_enabled, true) = false then 'SMS_DISABLED'
    else null
  end;
$$;

create or replace function public.rpc_list_event_all_members(p_tenant_id uuid, p_event_id uuid)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data."fullName"), '[]'::jsonb)
  into result
  from (
    select
      em.id as "eventMemberId",
      m.id as "memberId",
      m.member_code as "memberCode",
      m.full_name as "fullName",
      m.phone_e164 as "phone",
      case when m.phone_e164 is null then 'No phone' else left(m.phone_e164, 4) || repeat('*', greatest(length(m.phone_e164) - 7, 0)) || right(m.phone_e164, 3) end as "maskedPhone",
      m.sms_enabled as "smsEnabled",
      public.custom_sms_ineligibility_reason(m.phone_e164, m.sms_enabled) as "ineligibleReason"
    from public.event_members em
    join public.members m on m.id = em.member_id
    where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE'
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_preview_custom_sms_bulk(p_tenant_id uuid, p_event_id uuid, p_code text, p_event_member_ids uuid[], p_sender_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  template_record public.sms_templates%rowtype;
  effective_sender text;
  previews jsonb := '[]'::jsonb;
  row_record record;
  message text;
  preview jsonb;
  selected_count integer := coalesce(array_length(p_event_member_ids, 1), 0);
  eligible_count integer := 0;
  valid_count integer := 0;
  over_count integer := 0;
  no_phone integer := 0;
  sms_disabled integer := 0;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;

  select * into template_record
  from public.sms_templates
  where tenant_id = p_tenant_id and code = normalized_code and is_system = false;
  if not found then raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023'; end if;

  effective_sender := public.validate_sms_provider_sender(public.tenant_sms_provider_code(p_tenant_id), p_sender_id);

  for row_record in
    select
      em.id as event_member_id,
      m.full_name,
      m.phone_e164,
      public.custom_sms_ineligibility_reason(m.phone_e164, m.sms_enabled) as reason
    from public.event_members em
    join public.members m on m.id = em.member_id
    join unnest(p_event_member_ids) ids(id) on ids.id = em.id
    where em.tenant_id = p_tenant_id and em.event_id = p_event_id
  loop
    if row_record.reason = 'NO_PHONE' then
      no_phone := no_phone + 1;
    elsif row_record.reason = 'SMS_DISABLED' then
      sms_disabled := sms_disabled + 1;
    else
      eligible_count := eligible_count + 1;
      message := public.normalize_sms_message_text(public.render_sms_template(template_record.body, jsonb_build_object('member_name', row_record.full_name)));
      preview := public.sms_preview_json(normalized_code, row_record.event_member_id, row_record.full_name, row_record.phone_e164, effective_sender, message);
      if preview ->> 'valid' = 'true' then valid_count := valid_count + 1; else over_count := over_count + 1; end if;
      previews := previews || jsonb_build_array(preview);
    end if;
  end loop;

  return jsonb_build_object(
    'templateCode', normalized_code,
    'selected', selected_count,
    'eligible', eligible_count,
    'validMessages', valid_count,
    'overCharacterLimit', over_count,
    'noPhone', no_phone,
    'smsDisabled', sms_disabled,
    'recentlySent', 0,
    'hasPledge', 0,
    'maxCharacters', public.sms_max_characters(),
    'previews', previews
  );
end;
$$;

create or replace function public.rpc_enqueue_custom_sms_bulk(p_tenant_id uuid, p_event_id uuid, p_code text, p_event_member_ids uuid[], p_sender_id text, p_idempotency_key text, p_max_batch_size integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  template_record public.sms_templates%rowtype;
  effective_sender text;
  effective_provider text;
  requested integer := coalesce(array_length(p_event_member_ids, 1), 0);
  batch_id uuid;
  row_record record;
  message text;
  idempotency text;
  v_queued_count integer := 0;
  no_phone integer := 0;
  sms_disabled integer := 0;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('requested', requested, 'queued', 0, 'reason', 'TENANT_SMS_DISABLED');
  end if;
  if requested = 0 then raise exception 'CUSTOM_SMS_BATCH_EMPTY' using errcode = '22023'; end if;
  if requested > greatest(coalesce(p_max_batch_size, 100), 1) then raise exception 'CUSTOM_SMS_BATCH_TOO_LARGE' using errcode = '22023'; end if;

  select * into template_record
  from public.sms_templates
  where tenant_id = p_tenant_id and code = normalized_code and is_system = false;
  if not found then raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023'; end if;

  effective_provider := public.tenant_sms_provider_code(p_tenant_id);
  effective_sender := public.validate_sms_provider_sender(effective_provider, p_sender_id);

  insert into public.sms_batches (tenant_id, event_id, batch_type, requested_count, queued_count, skipped_count, created_by, idempotency_key)
  values (p_tenant_id, p_event_id, 'CUSTOM', requested, 0, 0, auth.uid(), p_idempotency_key)
  on conflict (tenant_id, idempotency_key) do update set idempotency_key = excluded.idempotency_key
  returning id into batch_id;

  for row_record in
    select
      em.id as event_member_id,
      m.id as member_id,
      m.full_name,
      m.phone_e164,
      public.custom_sms_ineligibility_reason(m.phone_e164, m.sms_enabled) as reason
    from public.event_members em
    join public.members m on m.id = em.member_id
    join unnest(p_event_member_ids) ids(id) on ids.id = em.id
    where em.tenant_id = p_tenant_id and em.event_id = p_event_id
  loop
    if row_record.reason = 'NO_PHONE' then
      no_phone := no_phone + 1;
    elsif row_record.reason = 'SMS_DISABLED' then
      sms_disabled := sms_disabled + 1;
    else
      message := public.normalize_sms_message_text(public.render_sms_template(template_record.body, jsonb_build_object('member_name', row_record.full_name)));
      idempotency := 'CUSTOM:' || batch_id::text || ':' || row_record.event_member_id::text;
      if not exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
        insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, batch_id, sender_id, provider)
        values (p_tenant_id, p_event_id, row_record.member_id, row_record.event_member_id, normalized_code, row_record.phone_e164, message, 'QUEUED', idempotency, batch_id, effective_sender, effective_provider);
        v_queued_count := v_queued_count + 1;
      end if;
    end if;
  end loop;

  update public.sms_batches
  set queued_count = v_queued_count,
      skipped_count = requested - v_queued_count,
      metadata = jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled)
  where id = batch_id;

  return jsonb_build_object(
    'requested', requested,
    'queued', v_queued_count,
    'skipped', jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled),
    'batchId', batch_id
  );
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
      st.name as template_name,
      o.phone_e164, o.sender_id, o.provider, coalesce(p.name, o.provider, 'Unknown') as provider_name, o.message_body, o.character_count, o.max_characters_at_send, o.status, o.attempt_count, o.created_at, o.sent_at, o.delivered_at, o.failed_at, o.last_error_code,
      case when o.template_code = 'PLEDGE_REQUEST' and o.status = 'CANCELLED' and o.last_error_code = 'PLEDGE_ALREADY_REGISTERED' then 'Member has already pledged' else o.last_error_message end as last_error_message,
      o.original_outbox_id, o.batch_id
    from public.sms_outbox o
    left join public.events e on e.id = o.event_id
    left join public.members m on m.id = o.member_id
    left join public.sms_providers p on p.code = o.provider
    left join lateral (
      select t.name
      from public.sms_templates t
      where t.code = o.template_code and (t.tenant_id = o.tenant_id or t.tenant_id is null)
      order by t.tenant_id nulls last
      limit 1
    ) st on true
    where o.tenant_id = p_tenant_id
  ) row_data;
  return result;
end;
$$;

grant execute on function public.validate_custom_sms_template_body(text) to authenticated;
grant execute on function public.generate_custom_sms_template_code(uuid, text, text) to authenticated;
grant execute on function public.custom_sms_template_json(public.sms_templates) to authenticated;
grant execute on function public.rpc_list_custom_sms_templates(uuid) to authenticated;
grant execute on function public.rpc_create_custom_sms_template(uuid, text, text, text) to authenticated;
grant execute on function public.rpc_update_custom_sms_template(uuid, text, text, text) to authenticated;
grant execute on function public.rpc_delete_custom_sms_template(uuid, text) to authenticated;
grant execute on function public.custom_sms_ineligibility_reason(text, boolean) to authenticated;
grant execute on function public.rpc_list_event_all_members(uuid, uuid) to authenticated;
grant execute on function public.rpc_preview_custom_sms_bulk(uuid, uuid, text, uuid[], text) to authenticated;
grant execute on function public.rpc_enqueue_custom_sms_bulk(uuid, uuid, text, uuid[], text, text, integer) to authenticated;

notify pgrst, 'reload schema';
