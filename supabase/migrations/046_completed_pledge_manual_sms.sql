alter table public.sms_batches
drop constraint if exists sms_batches_batch_type_check;

alter table public.sms_batches
add constraint sms_batches_batch_type_check
check (batch_type in ('BALANCE_REMINDER', 'PLEDGE_REQUEST', 'PLEDGE_COMPLETED'));

create or replace function public.render_completed_pledge_message(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid)
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
  select
    em.id as event_member_id,
    m.full_name,
    m.preferred_language,
    e.name as event_name,
    p.pledged_amount
  into state_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  join public.events e on e.id = em.event_id
  join public.pledges p on p.event_member_id = em.id and p.status = 'PAID'
  where em.tenant_id = p_tenant_id
    and em.event_id = p_event_id
    and em.id = p_event_member_id
  order by p.updated_at desc
  limit 1;

  if not found then
    raise exception 'COMPLETED_PLEDGE_NOT_FOUND' using errcode = '22023';
  end if;

  template_body := public.resolve_sms_template_body(p_tenant_id, 'PLEDGE_COMPLETED', state_record.preferred_language);
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;

  return public.render_sms_template(template_body, jsonb_build_object(
    'member_name', state_record.full_name,
    'pledge_amount', public.format_tzs_sms_amount(state_record.pledged_amount),
    'event_name', state_record.event_name
  ));
end;
$$;

create or replace function public.completed_pledge_ineligibility_reason(p_phone text, p_sms_enabled boolean)
returns text
language sql
immutable
as $$
  select case
    when nullif(btrim(coalesce(p_phone, '')), '') is null then 'NO_PHONE'
    when coalesce(p_sms_enabled, false) = false then 'SMS_DISABLED'
    else null
  end;
$$;

create or replace function public.rpc_list_event_completed_pledge_members(p_tenant_id uuid, p_event_id uuid)
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
      c.name as "category",
      p.id as "pledgeId",
      p.pledged_amount as "pledgedAmount",
      coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as "totalPaid",
      0::numeric(18,2) as "outstandingAmount",
      p.due_date as "dueDate",
      greatest(coalesce(p.updated_at, p.created_at), coalesce(last_payment.last_payment_date, p.created_at)) as "completedAt",
      m.sms_enabled as "smsEnabled",
      last_completed_sms.created_at as "lastCompletedPledgeSmsAt",
      last_completed_sms.status as "lastCompletedPledgeSmsStatus",
      public.completed_pledge_ineligibility_reason(m.phone_e164, m.sms_enabled) as "ineligibleReason",
      case when public.completed_pledge_ineligibility_reason(m.phone_e164, m.sms_enabled) is null then public.render_completed_pledge_message(p_tenant_id, p_event_id, em.id) else null end as "messagePreview"
    from public.event_members em
    join public.members m on m.id = em.member_id
    join public.pledges p on p.event_member_id = em.id and p.status = 'PAID'
    left join public.event_member_categories c on c.id = em.category_id
    left join lateral (
      select max(pay.payment_date) as last_payment_date
      from public.payments pay
      where pay.event_member_id = em.id
        and pay.status = 'CONFIRMED'
    ) last_payment on true
    left join lateral (
      select so.created_at, so.status
      from public.sms_outbox so
      where so.tenant_id = p_tenant_id
        and so.event_id = p_event_id
        and so.event_member_id = em.id
        and so.template_code = 'PLEDGE_COMPLETED'
        and so.status in ('QUEUED', 'PROCESSING', 'SENT', 'DELIVERED')
      order by so.created_at desc
      limit 1
    ) last_completed_sms on true
    where em.tenant_id = p_tenant_id
      and em.event_id = p_event_id
      and em.status = 'ACTIVE'
  ) row_data;

  return result;
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
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;

  select em.id as event_member_id, m.full_name, m.phone_e164
  into member_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = p_event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id;
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;

  if normalized_code = 'PLEDGE_REQUEST' then
    message := public.render_pledge_request_message(p_tenant_id, p_event_id, p_event_member_id);
  elsif normalized_code = 'BALANCE_REMINDER' then
    message := public.render_balance_reminder_message(p_tenant_id, p_event_id, p_event_member_id);
  elsif normalized_code = 'PLEDGE_COMPLETED' then
    message := public.render_completed_pledge_message(p_tenant_id, p_event_id, p_event_member_id);
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
  no_completed_pledge integer := 0;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;

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
  elsif normalized_code = 'PLEDGE_COMPLETED' then
    for row_record in
      select completed.*, public.completed_pledge_ineligibility_reason(completed."phone", completed."smsEnabled") as reason
      from jsonb_to_recordset(public.rpc_list_event_completed_pledge_members(p_tenant_id, p_event_id)) as completed("eventMemberId" uuid, "phone" text, "smsEnabled" boolean)
      join unnest(p_event_member_ids) ids(id) on ids.id = completed."eventMemberId"
    loop
      if row_record.reason = 'NO_PHONE' then no_phone := no_phone + 1;
      elsif row_record.reason = 'SMS_DISABLED' then sms_disabled := sms_disabled + 1;
      else
        eligible_count := eligible_count + 1;
        preview := public.rpc_preview_event_member_sms(p_tenant_id, p_event_id, row_record."eventMemberId", normalized_code);
        if preview ->> 'valid' = 'true' then valid_count := valid_count + 1; else over_count := over_count + 1; end if;
        previews := previews || jsonb_build_array(preview);
      end if;
    end loop;
    no_completed_pledge := selected_count - eligible_count - no_phone - sms_disabled;
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
    'noCompletedPledge', greatest(no_completed_pledge, 0),
    'maxCharacters', public.sms_max_characters(),
    'previews', previews
  );
end;
$$;

create or replace function public.rpc_enqueue_completed_pledge_sms(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid, p_idempotency_key text, p_batch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  member_record public.members%rowtype;
  pledge_record public.pledges%rowtype;
  message text;
  outbox_id uuid;
  idempotency text;
  allowance jsonb;
  provider_settings record;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.tenant_sms_enabled(p_tenant_id) then return jsonb_build_object('queued', false, 'template', 'PLEDGE_COMPLETED', 'reason', 'TENANT_SMS_DISABLED'); end if;

  idempotency := coalesce(nullif(btrim(p_idempotency_key), ''), gen_random_uuid()::text);
  if exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
    select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('queued', true, 'template', 'PLEDGE_COMPLETED', 'outboxId', outbox_id, 'status', 'QUEUED', 'reason', 'IDEMPOTENT_REPLAY');
  end if;

  select m.* into member_record
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = p_event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE';
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;

  select * into pledge_record
  from public.pledges
  where tenant_id = p_tenant_id and event_id = p_event_id and event_member_id = p_event_member_id and status = 'PAID'
  order by updated_at desc
  limit 1;
  if not found then return jsonb_build_object('queued', false, 'template', 'PLEDGE_COMPLETED', 'reason', 'NO_COMPLETED_PLEDGE'); end if;
  if member_record.phone_e164 is null then return jsonb_build_object('queued', false, 'template', 'PLEDGE_COMPLETED', 'reason', 'MEMBER_PHONE_MISSING'); end if;
  if coalesce(member_record.sms_enabled, true) = false then return jsonb_build_object('queued', false, 'template', 'PLEDGE_COMPLETED', 'reason', 'MEMBER_SMS_DISABLED'); end if;

  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if allowance ->> 'status' = 'LIMIT_REACHED' then raise exception 'SMS_LIMIT_REACHED' using errcode = '22023'; end if;

  message := public.render_completed_pledge_message(p_tenant_id, p_event_id, p_event_member_id);
  select * into provider_settings from public.tenant_sms_provider_settings(p_tenant_id);
  insert into public.sms_outbox (tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, batch_id, sender_id, provider)
  values (p_tenant_id, p_event_id, member_record.id, p_event_member_id, 'PLEDGE_COMPLETED', member_record.phone_e164, message, 'QUEUED', idempotency, p_batch_id, provider_settings.sender_id, provider_settings.provider_code)
  returning id into outbox_id;

  return jsonb_build_object('queued', true, 'template', 'PLEDGE_COMPLETED', 'outboxId', outbox_id, 'memberId', member_record.id, 'status', 'QUEUED', 'provider', provider_settings.provider_code, 'senderId', provider_settings.sender_id);
end;
$$;

create or replace function public.rpc_enqueue_completed_pledge_bulk(p_tenant_id uuid, p_event_id uuid, p_event_member_ids uuid[], p_idempotency_key text, p_max_batch_size integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  requested integer;
  eligible_count integer;
  batch_id uuid;
  member_id uuid;
  single_result jsonb;
  v_queued_count integer := 0;
  no_phone integer := 0;
  sms_disabled integer := 0;
  no_completed_pledge integer := 0;
  allowance jsonb;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;

  requested := coalesce(array_length(p_event_member_ids, 1), 0);
  if requested = 0 then raise exception 'COMPLETED_PLEDGE_BATCH_EMPTY' using errcode = '22023'; end if;
  if requested > greatest(coalesce(p_max_batch_size, 100), 1) then raise exception 'COMPLETED_PLEDGE_BATCH_TOO_LARGE' using errcode = '22023'; end if;

  select count(*) into eligible_count
  from jsonb_to_recordset(public.rpc_list_event_completed_pledge_members(p_tenant_id, p_event_id)) as completed("eventMemberId" uuid, "ineligibleReason" text)
  join unnest(p_event_member_ids) ids(id) on ids.id = completed."eventMemberId"
  where completed."ineligibleReason" is null;

  allowance := public.sms_allowance_status(p_tenant_id, eligible_count);
  if allowance ->> 'status' = 'LIMIT_REACHED' then raise exception 'SMS_LIMIT_REACHED' using errcode = '22023'; end if;
  if allowance ->> 'status' = 'LOW_BALANCE' then
    return jsonb_build_object('requested', requested, 'queued', 0, 'skipped', jsonb_build_object('noPhone', 0, 'smsDisabled', 0, 'noCompletedPledge', 0), 'smsAllowance', allowance);
  end if;

  insert into public.sms_batches (tenant_id, event_id, batch_type, requested_count, queued_count, skipped_count, created_by, idempotency_key)
  values (p_tenant_id, p_event_id, 'PLEDGE_COMPLETED', requested, 0, 0, auth.uid(), p_idempotency_key)
  on conflict (tenant_id, idempotency_key) do update set idempotency_key = excluded.idempotency_key
  returning id into batch_id;

  for member_id in select unnest(p_event_member_ids) loop
    single_result := public.rpc_enqueue_completed_pledge_sms(p_tenant_id, p_event_id, member_id, 'PLEDGE_COMPLETED:' || batch_id::text || ':' || member_id::text, batch_id);
    if single_result ->> 'queued' = 'true' then v_queued_count := v_queued_count + 1;
    elsif single_result ->> 'reason' = 'MEMBER_PHONE_MISSING' then no_phone := no_phone + 1;
    elsif single_result ->> 'reason' = 'MEMBER_SMS_DISABLED' then sms_disabled := sms_disabled + 1;
    elsif single_result ->> 'reason' = 'NO_COMPLETED_PLEDGE' then no_completed_pledge := no_completed_pledge + 1;
    end if;
  end loop;

  update public.sms_batches
  set queued_count = v_queued_count,
      skipped_count = requested - v_queued_count,
      metadata = jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled, 'noCompletedPledge', no_completed_pledge)
  where id = batch_id;

  return jsonb_build_object(
    'requested', requested,
    'queued', v_queued_count,
    'skipped', jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled, 'noCompletedPledge', no_completed_pledge),
    'batchId', batch_id,
    'smsAllowance', allowance
  );
end;
$$;

grant execute on function public.render_completed_pledge_message(uuid, uuid, uuid) to authenticated;
grant execute on function public.completed_pledge_ineligibility_reason(text, boolean) to authenticated;
grant execute on function public.rpc_list_event_completed_pledge_members(uuid, uuid) to authenticated;
grant execute on function public.rpc_preview_event_member_sms(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.rpc_preview_event_member_sms_bulk(uuid, uuid, uuid[], text, integer) to authenticated;
grant execute on function public.rpc_enqueue_completed_pledge_sms(uuid, uuid, uuid, text, uuid) to authenticated;
grant execute on function public.rpc_enqueue_completed_pledge_bulk(uuid, uuid, uuid[], text, integer) to authenticated;
