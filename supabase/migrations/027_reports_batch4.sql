insert into public.permissions (code, name, description) values
('reports.view', 'View reports', 'View event financial reports')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'reports.view'
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER', 'VIEWER')
on conflict do nothing;

create index if not exists payments_event_method_status_idx on public.payments(tenant_id, event_id, payment_method, status);
create index if not exists payments_event_received_by_idx on public.payments(tenant_id, event_id, received_by);
create index if not exists pledges_event_status_due_idx on public.pledges(tenant_id, event_id, status, due_date);

create or replace function public.report_pagination(p_page integer, p_page_size integer, p_total_rows integer)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'page', greatest(coalesce(p_page, 1), 1),
    'pageSize', least(greatest(coalesce(p_page_size, 25), 1), 100),
    'totalRows', coalesce(p_total_rows, 0),
    'totalPages', case when coalesce(p_total_rows, 0) = 0 then 0 else ceil(coalesce(p_total_rows, 0)::numeric / least(greatest(coalesce(p_page_size, 25), 1), 100))::integer end
  );
$$;

create or replace function public.require_event_report_access(p_tenant_id uuid, p_event_id uuid, p_permission text default 'reports.view')
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, p_permission) then
    raise exception 'REPORT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.rpc_get_event_collection_summary(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  event_record public.events%rowtype;
  summary jsonb;
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  summary := public.rpc_get_event_financial_summary(p_tenant_id, p_event_id);
  return jsonb_build_object(
    'data', jsonb_build_array(summary || jsonb_build_object(
      'eventTarget', coalesce(event_record.target_amount, 0)::numeric(18,2),
      'eventName', event_record.name,
      'eventDate', event_record.event_date,
      'collectionRate', case when coalesce((summary ->> 'totalPledged')::numeric, 0) > 0 then round(((summary ->> 'totalAllocatedToPledges')::numeric / (summary ->> 'totalPledged')::numeric) * 100, 2) else 0 end,
      'pledgeCoverageAgainstTarget', case when coalesce(event_record.target_amount, 0) > 0 then round(((summary ->> 'totalPledged')::numeric / event_record.target_amount) * 100, 2) else 0 end
    )),
    'summary', summary,
    'pagination', public.report_pagination(1, 25, 1)
  );
end;
$$;

create or replace function public.rpc_get_event_pledge_report(
  p_tenant_id uuid,
  p_event_id uuid,
  p_status text default 'ALL',
  p_category text default null,
  p_due_from date default null,
  p_due_to date default null,
  p_search text default '',
  p_sort text default 'MEMBER',
  p_direction text default 'ASC',
  p_page integer default 1,
  p_page_size integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_status text := upper(coalesce(p_status, 'ALL'));
  normalized_sort text := upper(coalesce(p_sort, 'MEMBER'));
  normalized_direction text := upper(coalesce(p_direction, 'ASC'));
  page_number integer := greatest(coalesce(p_page, 1), 1);
  size_number integer := least(greatest(coalesce(p_page_size, 25), 1), 100);
  total_rows integer;
  rows jsonb;
  totals jsonb;
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  if normalized_status not in ('ALL', 'PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE') or normalized_sort not in ('MEMBER', 'PLEDGED', 'PAID', 'OUTSTANDING', 'DUE_DATE') or normalized_direction not in ('ASC', 'DESC') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  with report_rows as (
    select
      p.id as "pledgeId",
      em.id as "eventMemberId",
      m.id as "memberId",
      m.full_name as "member",
      m.member_code as "memberCode",
      m.phone_e164 as "phone",
      c.name as "category",
      p.pledged_amount::numeric(18,2) as "pledged",
      coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as "paid",
      greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as "outstanding",
      coalesce(p.due_date, e.pledge_deadline) as "effectiveDueDate",
      public.calculated_pledge_status(p.id) as "status",
      (select max(pay.payment_date) from public.payments pay join public.payment_allocations pa on pa.payment_id = pay.id where pa.pledge_id = p.id and pay.status = 'CONFIRMED') as "lastPayment"
    from public.pledges p
    join public.events e on e.id = p.event_id
    join public.event_members em on em.id = p.event_member_id
    join public.members m on m.id = em.member_id
    left join public.event_member_categories c on c.id = em.category_id
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
      and p.status <> 'CANCELLED'
      and em.status = 'ACTIVE'
      and (normalized_status = 'ALL' or public.calculated_pledge_status(p.id) = normalized_status)
      and (p_category is null or coalesce(c.name, '') = p_category)
      and (p_due_from is null or coalesce(p.due_date, e.pledge_deadline) >= p_due_from)
      and (p_due_to is null or coalesce(p.due_date, e.pledge_deadline) <= p_due_to)
      and (coalesce(nullif(btrim(p_search), ''), '') = '' or m.full_name ilike '%' || btrim(p_search) || '%' or m.member_code ilike '%' || btrim(p_search) || '%' or coalesce(m.phone_e164, '') ilike '%' || btrim(p_search) || '%')
  ),
  counted as (select count(*)::integer as total from report_rows),
  paged as (
    select *
    from report_rows
    order by
      case when normalized_sort = 'MEMBER' and normalized_direction = 'ASC' then "member" end asc nulls last,
      case when normalized_sort = 'MEMBER' and normalized_direction = 'DESC' then "member" end desc nulls last,
      case when normalized_sort = 'PLEDGED' and normalized_direction = 'ASC' then "pledged" end asc nulls last,
      case when normalized_sort = 'PLEDGED' and normalized_direction = 'DESC' then "pledged" end desc nulls last,
      case when normalized_sort = 'PAID' and normalized_direction = 'ASC' then "paid" end asc nulls last,
      case when normalized_sort = 'PAID' and normalized_direction = 'DESC' then "paid" end desc nulls last,
      case when normalized_sort = 'OUTSTANDING' and normalized_direction = 'ASC' then "outstanding" end asc nulls last,
      case when normalized_sort = 'OUTSTANDING' and normalized_direction = 'DESC' then "outstanding" end desc nulls last,
      case when normalized_sort = 'DUE_DATE' and normalized_direction = 'ASC' then "effectiveDueDate" end asc nulls last,
      case when normalized_sort = 'DUE_DATE' and normalized_direction = 'DESC' then "effectiveDueDate" end desc nulls last,
      "member" asc
    limit size_number offset ((page_number - 1) * size_number)
  )
  select
    (select total from counted),
    coalesce((select jsonb_agg(to_jsonb(paged)) from paged), '[]'::jsonb),
    coalesce((select jsonb_build_object('pledgeCount', count(*), 'totalPledged', sum("pledged"), 'totalPaid', sum("paid"), 'totalOutstanding', sum("outstanding")) from report_rows), '{"pledgeCount":0,"totalPledged":0,"totalPaid":0,"totalOutstanding":0}'::jsonb)
  into total_rows, rows, totals;

  return jsonb_build_object('data', rows, 'summary', totals, 'pagination', public.report_pagination(page_number, size_number, total_rows));
end;
$$;

create or replace function public.rpc_get_event_payment_report(
  p_tenant_id uuid,
  p_event_id uuid,
  p_date_from date default null,
  p_date_to date default null,
  p_payment_method text default 'ALL',
  p_collector uuid default null,
  p_status text default 'ALL',
  p_search text default '',
  p_sort text default 'DATE',
  p_direction text default 'DESC',
  p_page integer default 1,
  p_page_size integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_tz text := coalesce((select timezone from public.tenants where id = p_tenant_id), 'Africa/Dar_es_Salaam');
  normalized_method text := upper(coalesce(p_payment_method, 'ALL'));
  normalized_status text := upper(coalesce(p_status, 'ALL'));
  normalized_sort text := upper(coalesce(p_sort, 'DATE'));
  normalized_direction text := upper(coalesce(p_direction, 'DESC'));
  page_number integer := greatest(coalesce(p_page, 1), 1);
  size_number integer := least(greatest(coalesce(p_page_size, 25), 1), 100);
  total_rows integer;
  rows jsonb;
  totals jsonb;
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  if normalized_method not in ('ALL', 'CASH', 'M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA', 'BANK_TRANSFER', 'CHEQUE', 'OTHER') or normalized_status not in ('ALL', 'CONFIRMED', 'REVERSED', 'CANCELLED') or normalized_sort not in ('DATE', 'AMOUNT', 'MEMBER') or normalized_direction not in ('ASC', 'DESC') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  with report_rows as (
    select
      pay.id as "paymentId",
      pay.payment_date as "date",
      pay.payment_number as "paymentNumber",
      r.receipt_number as "receiptNumber",
      m.full_name as "member",
      pay.amount::numeric(18,2) as "amount",
      public.payment_allocated_amount(pay.id)::numeric(18,2) as "allocatedAmount",
      public.payment_unallocated_amount(pay.id)::numeric(18,2) as "unallocatedAmount",
      pay.payment_method as "paymentMethod",
      pay.transaction_reference as "transactionReference",
      receiver.full_name as "receivedBy",
      receiver.id as "receivedById",
      pay.status
    from public.payments pay
    join public.event_members em on em.id = pay.event_member_id
    join public.members m on m.id = em.member_id
    left join public.receipts r on r.payment_id = pay.id
    left join public.profiles receiver on receiver.id = pay.received_by
    where pay.tenant_id = p_tenant_id
      and pay.event_id = p_event_id
      and (p_date_from is null or (pay.payment_date at time zone tenant_tz)::date >= p_date_from)
      and (p_date_to is null or (pay.payment_date at time zone tenant_tz)::date <= p_date_to)
      and (normalized_method = 'ALL' or pay.payment_method = normalized_method)
      and (p_collector is null or pay.received_by = p_collector)
      and (normalized_status = 'ALL' or pay.status = normalized_status)
      and (coalesce(nullif(btrim(p_search), ''), '') = '' or m.full_name ilike '%' || btrim(p_search) || '%' or pay.payment_number ilike '%' || btrim(p_search) || '%' or coalesce(r.receipt_number, '') ilike '%' || btrim(p_search) || '%' or coalesce(pay.transaction_reference, '') ilike '%' || btrim(p_search) || '%')
  ),
  counted as (select count(*)::integer as total from report_rows),
  paged as (
    select * from report_rows
    order by
      case when normalized_sort = 'DATE' and normalized_direction = 'ASC' then "date" end asc nulls last,
      case when normalized_sort = 'DATE' and normalized_direction = 'DESC' then "date" end desc nulls last,
      case when normalized_sort = 'AMOUNT' and normalized_direction = 'ASC' then "amount" end asc nulls last,
      case when normalized_sort = 'AMOUNT' and normalized_direction = 'DESC' then "amount" end desc nulls last,
      case when normalized_sort = 'MEMBER' and normalized_direction = 'ASC' then "member" end asc nulls last,
      case when normalized_sort = 'MEMBER' and normalized_direction = 'DESC' then "member" end desc nulls last,
      "date" desc
    limit size_number offset ((page_number - 1) * size_number)
  )
  select
    (select total from counted),
    coalesce((select jsonb_agg(to_jsonb(paged)) from paged), '[]'::jsonb),
    coalesce((select jsonb_build_object(
      'grossRecorded', coalesce(sum("amount"), 0),
      'reversed', coalesce(sum("amount") filter (where status = 'REVERSED'), 0),
      'netConfirmed', coalesce(sum("amount") filter (where status = 'CONFIRMED'), 0)
    ) from report_rows), '{"grossRecorded":0,"reversed":0,"netConfirmed":0}'::jsonb)
  into total_rows, rows, totals;
  return jsonb_build_object('data', rows, 'summary', totals, 'pagination', public.report_pagination(page_number, size_number, total_rows));
end;
$$;

create or replace function public.rpc_get_event_outstanding_report(
  p_tenant_id uuid,
  p_event_id uuid,
  p_filter text default 'ALL',
  p_category text default null,
  p_sort text default 'OUTSTANDING',
  p_direction text default 'DESC',
  p_page integer default 1,
  p_page_size integer default 25
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

create or replace function public.rpc_get_event_payment_method_summary(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rows jsonb;
  total_net numeric(18,2);
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  select coalesce(sum(amount), 0)::numeric(18,2) into total_net from public.payments where tenant_id = p_tenant_id and event_id = p_event_id and status = 'CONFIRMED';
  with methods(method) as (
    values ('CASH'), ('M_PESA'), ('AIRTEL_MONEY'), ('MIX_BY_YAS'), ('HALOPESA'), ('BANK_TRANSFER'), ('CHEQUE'), ('OTHER')
  ),
  grouped as (
    select
      methods.method as "paymentMethod",
      count(pay.id) filter (where pay.status is not null) as "paymentCount",
      coalesce(sum(pay.amount), 0)::numeric(18,2) as "grossAmount",
      coalesce(sum(pay.amount) filter (where pay.status = 'REVERSED'), 0)::numeric(18,2) as "reversedAmount",
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED'), 0)::numeric(18,2) as "netConfirmedAmount"
    from methods
    left join public.payments pay on pay.payment_method = methods.method and pay.tenant_id = p_tenant_id and pay.event_id = p_event_id
    group by methods.method
  )
  select coalesce(jsonb_agg(to_jsonb(grouped) || jsonb_build_object('percentage', case when total_net > 0 then round(("netConfirmedAmount" / total_net) * 100, 2) else 0 end) order by "paymentMethod"), '[]'::jsonb)
  into rows
  from grouped;
  return jsonb_build_object('data', rows, 'summary', jsonb_build_object('netConfirmed', total_net), 'pagination', public.report_pagination(1, 100, 8));
end;
$$;

create or replace function public.rpc_get_event_collector_report(p_tenant_id uuid, p_event_id uuid, p_date_from date default null, p_date_to date default null, p_collector uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_tz text := coalesce((select timezone from public.tenants where id = p_tenant_id), 'Africa/Dar_es_Salaam');
  rows jsonb;
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  with grouped as (
    select
      pay.received_by as "collectorId",
      coalesce(receiver.full_name, 'Unknown') as "collectorName",
      count(pay.id) as "paymentCount",
      coalesce(sum(pay.amount), 0)::numeric(18,2) as "grossRecorded",
      coalesce(sum(pay.amount) filter (where pay.status = 'REVERSED'), 0)::numeric(18,2) as "reversed",
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED'), 0)::numeric(18,2) as "netCollected",
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'CASH'), 0)::numeric(18,2) as "cash",
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method in ('M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA')), 0)::numeric(18,2) as "mobileMoney",
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'BANK_TRANSFER'), 0)::numeric(18,2) as "bank",
      max(pay.payment_date) as "lastPaymentTime"
    from public.payments pay
    left join public.profiles receiver on receiver.id = pay.received_by
    where pay.tenant_id = p_tenant_id
      and pay.event_id = p_event_id
      and (p_date_from is null or (pay.payment_date at time zone tenant_tz)::date >= p_date_from)
      and (p_date_to is null or (pay.payment_date at time zone tenant_tz)::date <= p_date_to)
      and (p_collector is null or pay.received_by = p_collector)
    group by pay.received_by, receiver.full_name
  )
  select coalesce(jsonb_agg(to_jsonb(grouped) order by "netCollected" desc), '[]'::jsonb)
  into rows
  from grouped;
  return jsonb_build_object('data', rows, 'summary', coalesce((select jsonb_build_object('collectorCount', count(*), 'netCollected', sum("netCollected"), 'grossRecorded', sum("grossRecorded")) from jsonb_to_recordset(rows) as x("netCollected" numeric, "grossRecorded" numeric)), '{"collectorCount":0,"netCollected":0,"grossRecorded":0}'::jsonb), 'pagination', public.report_pagination(1, 100, jsonb_array_length(rows)));
end;
$$;

create or replace function public.rpc_get_member_statement(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid default null, p_search text default '')
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  selected_member uuid := p_event_member_id;
  member_info jsonb;
  pledge_info jsonb;
  transactions jsonb;
  summary jsonb;
  candidates jsonb;
begin
  perform public.require_event_report_access(p_tenant_id, p_event_id);
  select coalesce(jsonb_agg(jsonb_build_object('eventMemberId', em.id, 'name', m.full_name, 'memberCode', m.member_code, 'phone', m.phone_e164) order by m.full_name), '[]'::jsonb)
  into candidates
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.tenant_id = p_tenant_id
    and em.event_id = p_event_id
    and em.status = 'ACTIVE'
    and (coalesce(nullif(btrim(p_search), ''), '') = '' or m.full_name ilike '%' || btrim(p_search) || '%' or m.member_code ilike '%' || btrim(p_search) || '%' or coalesce(m.phone_e164, '') ilike '%' || btrim(p_search) || '%');

  if selected_member is null then
    selected_member := (candidates -> 0 ->> 'eventMemberId')::uuid;
  end if;
  if selected_member is null then
    return jsonb_build_object('data', '[]'::jsonb, 'members', candidates, 'summary', '{}'::jsonb, 'pagination', public.report_pagination(1, 25, 0));
  end if;

  select jsonb_build_object('eventMemberId', em.id, 'memberId', m.id, 'name', m.full_name, 'phone', m.phone_e164, 'memberCode', m.member_code, 'category', c.name)
  into member_info
  from public.event_members em
  join public.members m on m.id = em.member_id
  left join public.event_member_categories c on c.id = em.category_id
  where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.id = selected_member and em.status = 'ACTIVE';

  select jsonb_build_object('pledgeId', p.id, 'pledgedAmount', p.pledged_amount, 'effectiveDueDate', coalesce(p.due_date, e.pledge_deadline), 'status', public.calculated_pledge_status(p.id))
  into pledge_info
  from public.pledges p
  join public.events e on e.id = p.event_id
  where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.event_member_id = selected_member and p.status <> 'CANCELLED'
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data."date"), '[]'::jsonb)
  into transactions
  from (
    select pay.payment_date as "date", 'PAYMENT' as "type", r.receipt_number as "receipt", pay.payment_method as "method", pay.amount as "amount", pay.status
    from public.payments pay
    left join public.receipts r on r.payment_id = pay.id
    where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.event_member_id = selected_member
  ) row_data;

  summary := jsonb_build_object(
    'member', member_info,
    'pledge', pledge_info,
    'totalPledged', coalesce((pledge_info ->> 'pledgedAmount')::numeric, 0),
    'totalConfirmedPaid', coalesce((select sum(pay.amount) from public.payments pay where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.event_member_id = selected_member and pay.status = 'CONFIRMED'), 0)::numeric(18,2),
    'outstanding', coalesce((select greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0) from public.pledges p where p.event_member_id = selected_member and p.status <> 'CANCELLED' limit 1), 0)::numeric(18,2),
    'unallocatedCredit', coalesce((select sum(public.payment_unallocated_amount(pay.id)) from public.payments pay where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.event_member_id = selected_member and pay.status = 'CONFIRMED'), 0)::numeric(18,2)
  );
  return jsonb_build_object('data', transactions, 'members', candidates, 'summary', summary, 'pagination', public.report_pagination(1, 100, jsonb_array_length(transactions)));
end;
$$;

grant execute on function public.report_pagination(integer, integer, integer) to authenticated;
grant execute on function public.require_event_report_access(uuid, uuid, text) to authenticated;
grant execute on function public.rpc_get_event_collection_summary(uuid, uuid) to authenticated;
grant execute on function public.rpc_get_event_pledge_report(uuid, uuid, text, text, date, date, text, text, text, integer, integer) to authenticated;
grant execute on function public.rpc_get_event_payment_report(uuid, uuid, date, date, text, uuid, text, text, text, text, integer, integer) to authenticated;
grant execute on function public.rpc_get_event_outstanding_report(uuid, uuid, text, text, text, text, integer, integer) to authenticated;
grant execute on function public.rpc_get_event_payment_method_summary(uuid, uuid) to authenticated;
grant execute on function public.rpc_get_event_collector_report(uuid, uuid, date, date, uuid) to authenticated;
grant execute on function public.rpc_get_member_statement(uuid, uuid, uuid, text) to authenticated;
