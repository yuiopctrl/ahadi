create or replace function public.rpc_get_event_outstanding_report(
  p_tenant_id uuid,
  p_event_id uuid,
  p_filter text default 'ALL',
  p_category text default null,
  p_sort text default 'OUTSTANDING',
  p_direction text default 'DESC',
  p_page integer default 1,
  p_page_size integer default 25,
  p_search text default ''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_filter text := upper(coalesce(p_filter, 'ALL'));
  normalized_sort text := upper(coalesce(p_sort, 'OUTSTANDING'));
  normalized_direction text := upper(coalesce(p_direction, 'DESC'));
  normalized_search text := lower(btrim(coalesce(p_search, '')));
  page_number integer := greatest(coalesce(p_page, 1), 1);
  size_number integer := least(greatest(coalesce(p_page_size, 25), 1), 100);
  total_rows integer;
  rows jsonb;
  totals jsonb;
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  if normalized_filter not in ('ALL', 'OVERDUE', 'DUE_SOON', 'PARTIAL', 'UNPAID') or normalized_sort not in ('OUTSTANDING', 'DAYS_OVERDUE', 'DUE_DATE', 'MEMBER') or normalized_direction not in ('ASC', 'DESC') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  with report_rows as (
    select
      p.id as "pledgeId",
      em.id as "eventMemberId",
      m.full_name as "member",
      m.phone_e164 as "phone",
      c.name as "category",
      p.pledged_amount::numeric(18,2) as "pledged",
      coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as "paid",
      greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as "outstanding",
      coalesce(p.due_date, e.pledge_deadline) as "effectiveDueDate",
      case when coalesce(p.due_date, e.pledge_deadline) is not null and coalesce(p.due_date, e.pledge_deadline) < current_date then current_date - coalesce(p.due_date, e.pledge_deadline) else 0 end as "daysOverdue",
      public.calculated_pledge_status(p.id) as "status",
      (select max(pay.payment_date) from public.payments pay join public.payment_allocations pa on pa.payment_id = pay.id where pa.pledge_id = p.id and pay.status = 'CONFIRMED') as "lastPayment",
      (select max(so.created_at) from public.sms_outbox so where so.tenant_id = p_tenant_id and so.event_id = p_event_id and so.event_member_id = em.id and so.template_code = 'BALANCE_REMINDER' and so.status in ('SENT', 'DELIVERED', 'QUEUED', 'PROCESSING')) as "lastReminder"
    from public.pledges p
    join public.events e on e.id = p.event_id
    join public.event_members em on em.id = p.event_member_id
    join public.members m on m.id = em.member_id
    left join public.event_member_categories c on c.id = em.category_id
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
      and p.status <> 'CANCELLED'
      and em.status = 'ACTIVE'
      and greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0) > 0
      and (p_category is null or coalesce(c.name, '') = p_category)
      and (normalized_search = '' or lower(coalesce(m.full_name, '') || ' ' || coalesce(m.phone_e164, '')) like '%' || normalized_search || '%')
      and (
        normalized_filter = 'ALL'
        or (normalized_filter = 'OVERDUE' and coalesce(p.due_date, e.pledge_deadline) is not null and coalesce(p.due_date, e.pledge_deadline) < current_date)
        or (normalized_filter = 'DUE_SOON' and coalesce(p.due_date, e.pledge_deadline) between current_date and current_date + interval '7 days')
        or (normalized_filter = 'PARTIAL' and public.confirmed_pledge_allocated_amount(p.id) > 0)
        or (normalized_filter = 'UNPAID' and public.confirmed_pledge_allocated_amount(p.id) = 0)
      )
  ),
  counted as (select count(*)::integer as total from report_rows),
  paged as (
    select * from report_rows
    order by
      case when normalized_sort = 'OUTSTANDING' and normalized_direction = 'ASC' then "outstanding" end asc nulls last,
      case when normalized_sort = 'OUTSTANDING' and normalized_direction = 'DESC' then "outstanding" end desc nulls last,
      case when normalized_sort = 'DAYS_OVERDUE' and normalized_direction = 'ASC' then "daysOverdue" end asc nulls last,
      case when normalized_sort = 'DAYS_OVERDUE' and normalized_direction = 'DESC' then "daysOverdue" end desc nulls last,
      case when normalized_sort = 'DUE_DATE' and normalized_direction = 'ASC' then "effectiveDueDate" end asc nulls last,
      case when normalized_sort = 'DUE_DATE' and normalized_direction = 'DESC' then "effectiveDueDate" end desc nulls last,
      case when normalized_sort = 'MEMBER' and normalized_direction = 'ASC' then "member" end asc nulls last,
      case when normalized_sort = 'MEMBER' and normalized_direction = 'DESC' then "member" end desc nulls last,
      "outstanding" desc
    limit size_number offset ((page_number - 1) * size_number)
  )
  select
    (select total from counted),
    coalesce((select jsonb_agg(to_jsonb(paged)) from paged), '[]'::jsonb),
    coalesce((select jsonb_build_object('totalOutstanding', sum("outstanding"), 'outstandingMembers', count(*), 'overdueMembers', count(*) filter (where "daysOverdue" > 0)) from report_rows), '{"totalOutstanding":0,"outstandingMembers":0,"overdueMembers":0}'::jsonb)
  into total_rows, rows, totals;
  return jsonb_build_object('data', rows, 'summary', totals, 'pagination', public.report_pagination(page_number, size_number, total_rows));
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
  select p.* into pledge_record
  from public.payment_allocations pa
  join public.pledges p on p.id = pa.pledge_id
  where pa.payment_id = payment_record.id and pa.tenant_id = p_tenant_id
  order by pa.created_at
  limit 1;
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

grant execute on function public.rpc_get_event_outstanding_report(uuid, uuid, text, text, text, text, integer, integer, text) to authenticated;
grant execute on function public.rpc_enqueue_payment_confirmation_sms(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
