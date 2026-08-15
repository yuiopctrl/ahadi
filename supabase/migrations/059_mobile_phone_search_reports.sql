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
  normalized_search text := btrim(coalesce(p_search, ''));
  phone_search text := public.compact_phone_search(p_search);
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
      and (
        normalized_search = ''
        or m.full_name ilike '%' || normalized_search || '%'
        or m.member_code ilike '%' || normalized_search || '%'
        or coalesce(m.phone_e164, '') ilike '%' || normalized_search || '%'
        or (phone_search <> '' and public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%')
      )
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
  normalized_search text := btrim(coalesce(p_search, ''));
  phone_search text := public.compact_phone_search(p_search);
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
        normalized_search = ''
        or m.full_name ilike '%' || normalized_search || '%'
        or coalesce(m.phone_e164, '') ilike '%' || normalized_search || '%'
        or (phone_search <> '' and public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%')
      )
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

grant execute on function public.rpc_get_event_pledge_report(uuid, uuid, text, text, date, date, text, text, text, integer, integer) to authenticated;
grant execute on function public.rpc_get_event_outstanding_report(uuid, uuid, text, text, text, text, integer, integer, text) to authenticated;

notify pgrst, 'reload schema';
