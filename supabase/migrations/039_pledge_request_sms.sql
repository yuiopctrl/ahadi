create or replace function public.sms_template_allowed_variables(p_code text)
returns jsonb
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_code, '')))
    when 'PLEDGE_REQUEST' then '["member_name","event_name","event_date","pledge_deadline"]'::jsonb
    when 'PLEDGE_REGISTRATION' then '["member_name","pledge_amount","event_name","due_date"]'::jsonb
    when 'PAYMENT_CONFIRMATION' then '["member_name","payment_amount","payment_method","event_name","balance","receipt_number"]'::jsonb
    when 'BALANCE_REMINDER' then '["member_name","event_name","balance","due_date"]'::jsonb
    when 'PLEDGE_COMPLETED' then '["member_name","pledge_amount","event_name"]'::jsonb
    else '[]'::jsonb
  end;
$$;

insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active, allowed_variables)
values (
  null,
  'PLEDGE_REQUEST',
  'Pledge Request',
  'SMS',
  'Ndugu {{member_name}}, unaombwa kutoa ahadi yako kwa ajili ya {{event_name}}. Tafadhali wasiliana na kamati au weka ahadi yako mapema. Asante kwa ushirikiano wako.',
  'sw',
  true,
  true,
  public.sms_template_allowed_variables('PLEDGE_REQUEST')
)
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
where code in ('PLEDGE_REQUEST', 'PLEDGE_REGISTRATION', 'PAYMENT_CONFIRMATION', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED');

alter table public.sms_batches
drop constraint if exists sms_batches_batch_type_check;
alter table public.sms_batches
add constraint sms_batches_batch_type_check
check (batch_type in ('BALANCE_REMINDER', 'PLEDGE_REQUEST'));

create or replace function public.pledge_request_ineligibility_reason(p_phone text, p_sms_enabled boolean, p_has_pledge boolean, p_recent_sent_at timestamptz, p_cooldown_hours integer)
returns text
language sql
stable
as $$
  select case
    when coalesce(p_has_pledge, false) then 'HAS_PLEDGE'
    when p_phone is null or p_phone !~ '^\+255[67][0-9]{8}$' then 'NO_PHONE'
    when coalesce(p_sms_enabled, false) = false then 'SMS_DISABLED'
    when p_recent_sent_at is not null and p_recent_sent_at > now() - make_interval(hours => greatest(coalesce(p_cooldown_hours, 24), 0)) then 'RECENTLY_SENT'
    else null
  end;
$$;

create or replace function public.event_member_has_active_pledge(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.pledges p
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
      and p.event_member_id = p_event_member_id
      and p.status <> 'CANCELLED'
  );
$$;

create or replace function public.pledge_request_state(p_tenant_id uuid, p_event_id uuid)
returns table (
  event_member_id uuid,
  member_id uuid,
  member_code text,
  full_name text,
  phone text,
  category text,
  sms_enabled boolean,
  event_member_status text,
  event_name text,
  event_date date,
  pledge_deadline date,
  has_pledge boolean,
  last_pledge_request_at timestamptz,
  last_pledge_request_status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    em.id,
    m.id,
    m.member_code,
    m.full_name,
    m.phone_e164,
    c.name,
    coalesce(m.sms_enabled, true),
    em.status,
    e.name,
    e.event_date,
    e.pledge_deadline,
    public.event_member_has_active_pledge(p_tenant_id, p_event_id, em.id),
    (
      select max(o.created_at)
      from public.sms_outbox o
      where o.tenant_id = p_tenant_id
        and o.event_id = p_event_id
        and o.event_member_id = em.id
        and o.template_code = 'PLEDGE_REQUEST'
        and o.status in ('QUEUED', 'PROCESSING', 'SENT', 'DELIVERED')
    ),
    (
      select o.status
      from public.sms_outbox o
      where o.tenant_id = p_tenant_id
        and o.event_id = p_event_id
        and o.event_member_id = em.id
        and o.template_code = 'PLEDGE_REQUEST'
        and o.status <> 'CANCELLED'
      order by o.created_at desc
      limit 1
    ),
    em.created_at
  from public.event_members em
  join public.members m on m.id = em.member_id and m.tenant_id = p_tenant_id and m.status = 'ACTIVE'
  join public.events e on e.id = em.event_id and e.tenant_id = p_tenant_id
  left join public.event_member_categories c on c.id = em.category_id
  where em.tenant_id = p_tenant_id
    and em.event_id = p_event_id
    and em.status = 'ACTIVE';
$$;

create or replace function public.pledge_request_date_text(p_date date)
returns text
language sql
immutable
as $$
  select case when p_date is null then '' else to_char(p_date, 'DD/MM/YYYY') end;
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
  select * into state_record
  from public.pledge_request_state(p_tenant_id, p_event_id)
  where event_member_id = p_event_member_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  template_body := public.resolve_sms_template_body(p_tenant_id, 'PLEDGE_REQUEST', 'sw');
  if template_body is null then
    raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;

  return public.render_sms_template(template_body, jsonb_build_object(
    'member_name', state_record.full_name,
    'event_name', state_record.event_name,
    'event_date', public.pledge_request_date_text(state_record.event_date),
    'pledge_deadline', public.pledge_request_date_text(state_record.pledge_deadline)
  ));
end;
$$;

create or replace function public.rpc_list_event_no_pledge_members(p_tenant_id uuid, p_event_id uuid, p_cooldown_hours integer default 24)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data."fullName"), '[]'::jsonb)
  into result
  from (
    select
      state.event_member_id as "eventMemberId",
      state.member_id as "memberId",
      state.member_code as "memberCode",
      state.full_name as "fullName",
      state.phone as "phone",
      case when state.phone is null then 'No phone' else left(state.phone, 4) || repeat('*', greatest(length(state.phone) - 7, 0)) || right(state.phone, 3) end as "maskedPhone",
      state.category,
      state.sms_enabled as "smsEnabled",
      state.last_pledge_request_at as "lastPledgeRequestAt",
      state.last_pledge_request_status as "lastPledgeRequestStatus",
      state.created_at as "createdAt",
      public.pledge_request_ineligibility_reason(state.phone, state.sms_enabled, state.has_pledge, state.last_pledge_request_at, p_cooldown_hours) as "ineligibleReason",
      case when public.pledge_request_ineligibility_reason(state.phone, state.sms_enabled, state.has_pledge, state.last_pledge_request_at, p_cooldown_hours) is null then public.render_pledge_request_message(p_tenant_id, p_event_id, state.event_member_id) else null end as "messagePreview"
    from public.pledge_request_state(p_tenant_id, p_event_id) state
    where state.has_pledge = false
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_enqueue_pledge_request_sms(
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
  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'TENANT_SMS_DISABLED');
  end if;

  idempotency := coalesce(nullif(btrim(p_idempotency_key), ''), gen_random_uuid()::text);
  if exists (select 1 from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED') then
    select id into outbox_id from public.sms_outbox where idempotency_key = idempotency and status <> 'CANCELLED' limit 1;
    return jsonb_build_object('queued', true, 'template', 'PLEDGE_REQUEST', 'outboxId', outbox_id, 'status', 'QUEUED', 'reason', 'IDEMPOTENT_REPLAY');
  end if;

  select * into state_record
  from public.pledge_request_state(p_tenant_id, p_event_id)
  where event_member_id = p_event_member_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  reason := public.pledge_request_ineligibility_reason(state_record.phone, state_record.sms_enabled, state_record.has_pledge, state_record.last_pledge_request_at, p_cooldown_hours);
  if reason = 'HAS_PLEDGE' then
    return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'HAS_PLEDGE');
  elsif reason = 'NO_PHONE' then
    return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'MEMBER_PHONE_MISSING');
  elsif reason = 'SMS_DISABLED' then
    return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'MEMBER_SMS_DISABLED');
  elsif reason = 'RECENTLY_SENT' then
    return jsonb_build_object('queued', false, 'template', 'PLEDGE_REQUEST', 'reason', 'RECENTLY_SENT', 'lastSentAt', state_record.last_pledge_request_at);
  end if;

  allowance := public.sms_allowance_status(p_tenant_id, 1);
  if allowance ->> 'status' = 'LIMIT_REACHED' then
    raise exception 'SMS_LIMIT_REACHED' using errcode = '22023';
  end if;

  message := public.render_pledge_request_message(p_tenant_id, p_event_id, p_event_member_id);

  insert into public.sms_outbox (
    tenant_id, event_id, member_id, event_member_id, template_code, phone_e164, message_body, status, idempotency_key, original_outbox_id, batch_id, sender_id, provider
  )
  values (
    p_tenant_id, p_event_id, state_record.member_id, p_event_member_id, 'PLEDGE_REQUEST', state_record.phone, message, 'QUEUED', idempotency, p_original_outbox_id, p_batch_id, public.tenant_sms_sender_id(p_tenant_id), coalesce(nullif(current_setting('app.sms_provider', true), ''), 'NEXTSMS')
  )
  returning id into outbox_id;

  return jsonb_build_object('queued', true, 'template', 'PLEDGE_REQUEST', 'outboxId', outbox_id, 'memberId', state_record.member_id, 'status', 'QUEUED');
end;
$$;

create or replace function public.rpc_enqueue_pledge_request_bulk(
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
  v_batch_id uuid;
  member_id uuid;
  single_result jsonb;
  v_queued_count integer := 0;
  no_phone integer := 0;
  sms_disabled integer := 0;
  recently_sent integer := 0;
  has_pledge integer := 0;
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
    raise exception 'PLEDGE_REQUEST_BATCH_EMPTY' using errcode = '22023';
  end if;
  if requested > greatest(coalesce(p_max_batch_size, 100), 1) then
    raise exception 'PLEDGE_REQUEST_BATCH_TOO_LARGE' using errcode = '22023';
  end if;

  select count(*) into invalid_count
  from unnest(p_event_member_ids) ids(id)
  left join public.event_members em on em.id = ids.id and em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE'
  where em.id is null;
  if invalid_count > 0 then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select count(*) into eligible_count
  from public.pledge_request_state(p_tenant_id, p_event_id) state
  join unnest(p_event_member_ids) ids(id) on ids.id = state.event_member_id
  where public.pledge_request_ineligibility_reason(state.phone, state.sms_enabled, state.has_pledge, state.last_pledge_request_at, p_cooldown_hours) is null;

  allowance := public.sms_allowance_status(p_tenant_id, eligible_count);
  if allowance ->> 'status' = 'LIMIT_REACHED' then
    raise exception 'SMS_LIMIT_REACHED' using errcode = '22023';
  end if;
  if allowance ->> 'status' = 'LOW_BALANCE' then
    return jsonb_build_object('requested', requested, 'queued', 0, 'selected', requested, 'eligible', eligible_count, 'allowedBySmsBalance', (allowance ->> 'allowed')::integer, 'skipped', jsonb_build_object('hasPledge', 0, 'noPhone', 0, 'smsDisabled', 0, 'recentlySent', 0), 'smsAllowance', allowance);
  end if;

  insert into public.sms_batches (tenant_id, event_id, batch_type, requested_count, queued_count, skipped_count, created_by, idempotency_key)
  values (p_tenant_id, p_event_id, 'PLEDGE_REQUEST', requested, 0, 0, auth.uid(), p_idempotency_key)
  on conflict (tenant_id, idempotency_key) do update set idempotency_key = excluded.idempotency_key
  returning id into v_batch_id;

  if exists (select 1 from public.sms_outbox where tenant_id = p_tenant_id and batch_id = v_batch_id and template_code = 'PLEDGE_REQUEST' and status <> 'CANCELLED') then
    select count(*) into v_queued_count from public.sms_outbox where tenant_id = p_tenant_id and batch_id = v_batch_id and template_code = 'PLEDGE_REQUEST' and status <> 'CANCELLED';
    return jsonb_build_object('requested', requested, 'queued', v_queued_count, 'selected', requested, 'eligible', v_queued_count, 'allowedBySmsBalance', (allowance ->> 'allowed')::integer, 'skipped', jsonb_build_object('hasPledge', 0, 'noPhone', 0, 'smsDisabled', 0, 'recentlySent', 0), 'batchId', v_batch_id, 'smsAllowance', allowance, 'reason', 'IDEMPOTENT_REPLAY');
  end if;

  for member_id in select unnest(p_event_member_ids) loop
    single_result := public.rpc_enqueue_pledge_request_sms(p_tenant_id, p_event_id, member_id, 'PLEDGE_REQUEST:' || v_batch_id::text || ':' || member_id::text, p_cooldown_hours, null, v_batch_id);
    if single_result ->> 'queued' = 'true' then
      v_queued_count := v_queued_count + 1;
    elsif single_result ->> 'reason' = 'MEMBER_PHONE_MISSING' then
      no_phone := no_phone + 1;
    elsif single_result ->> 'reason' = 'MEMBER_SMS_DISABLED' then
      sms_disabled := sms_disabled + 1;
    elsif single_result ->> 'reason' = 'RECENTLY_SENT' then
      recently_sent := recently_sent + 1;
    elsif single_result ->> 'reason' = 'HAS_PLEDGE' then
      has_pledge := has_pledge + 1;
    end if;
  end loop;

  update public.sms_batches
  set queued_count = v_queued_count,
      skipped_count = requested - v_queued_count,
      metadata = jsonb_build_object('hasPledge', has_pledge, 'noPhone', no_phone, 'smsDisabled', sms_disabled, 'recentlySent', recently_sent)
  where id = v_batch_id;

  return jsonb_build_object(
    'requested', requested,
    'queued', v_queued_count,
    'selected', requested,
    'eligible', eligible_count,
    'allowedBySmsBalance', (allowance ->> 'allowed')::integer,
    'skipped', jsonb_build_object('hasPledge', has_pledge, 'noPhone', no_phone, 'smsDisabled', sms_disabled, 'recentlySent', recently_sent),
    'batchId', v_batch_id,
    'smsAllowance', allowance
  );
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

  update public.sms_outbox o
  set status = 'CANCELLED',
      failed_at = now(),
      processing_started_at = null,
      last_error_code = 'PLEDGE_ALREADY_REGISTERED',
      last_error_message = 'Member has already pledged'
  where o.tenant_id = p_tenant_id
    and o.template_code = 'PLEDGE_REQUEST'
    and o.status in ('QUEUED', 'FAILED')
    and (p_outbox_ids is null or o.id = any(p_outbox_ids))
    and (p_batch_id is null or o.batch_id = p_batch_id)
    and exists (
      select 1
      from public.pledges p
      where p.tenant_id = o.tenant_id
        and p.event_id = o.event_id
        and p.event_member_id = o.event_member_id
        and p.status <> 'CANCELLED'
    );

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
      and (
        o.template_code <> 'PLEDGE_REQUEST'
        or not exists (
          select 1
          from public.pledges pr
          where pr.tenant_id = o.tenant_id
            and pr.event_id = o.event_id
            and pr.event_member_id = o.event_member_id
            and pr.status <> 'CANCELLED'
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
    public.sms_template_detail(p_tenant_id, 'PLEDGE_REQUEST', 'sw'),
    public.sms_template_detail(p_tenant_id, 'PLEDGE_REGISTRATION', 'sw'),
    public.sms_template_detail(p_tenant_id, 'PAYMENT_CONFIRMATION', 'sw'),
    public.sms_template_detail(p_tenant_id, 'BALANCE_REMINDER', 'sw'),
    public.sms_template_detail(p_tenant_id, 'PLEDGE_COMPLETED', 'sw')
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

grant execute on function public.pledge_request_ineligibility_reason(text, boolean, boolean, timestamptz, integer) to authenticated;
grant execute on function public.event_member_has_active_pledge(uuid, uuid, uuid) to authenticated;
grant execute on function public.pledge_request_state(uuid, uuid) to authenticated;
grant execute on function public.pledge_request_date_text(date) to authenticated;
grant execute on function public.render_pledge_request_message(uuid, uuid, uuid) to authenticated;
grant execute on function public.rpc_list_event_no_pledge_members(uuid, uuid, integer) to authenticated;
grant execute on function public.rpc_enqueue_pledge_request_sms(uuid, uuid, uuid, text, integer, uuid, uuid) to authenticated;
grant execute on function public.rpc_enqueue_pledge_request_bulk(uuid, uuid, uuid[], text, integer, integer) to authenticated;

notify pgrst, 'reload schema';
