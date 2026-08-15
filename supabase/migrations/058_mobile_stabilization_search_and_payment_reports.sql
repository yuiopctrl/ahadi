create or replace function public.compact_phone_search(p_value text)
returns text
language sql
immutable
as $$
  select case
    when regexp_replace(coalesce(p_value, ''), '\D', '', 'g') like '255%' then substring(regexp_replace(coalesce(p_value, ''), '\D', '', 'g') from 4)
    when regexp_replace(coalesce(p_value, ''), '\D', '', 'g') like '0%' then substring(regexp_replace(coalesce(p_value, ''), '\D', '', 'g') from 2)
    else regexp_replace(coalesce(p_value, ''), '\D', '', 'g')
  end
$$;

create or replace view public.v_event_payments_list
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  p.id as payment_id,
  p.payment_number,
  r.id as receipt_id,
  r.receipt_number,
  p.event_member_id,
  m.full_name as member_name,
  m.phone_e164,
  p.amount,
  public.payment_allocated_amount(p.id)::numeric(18,2) as allocated_amount,
  public.payment_unallocated_amount(p.id)::numeric(18,2) as unallocated_amount,
  p.payment_method,
  p.transaction_reference,
  p.payment_date,
  p.status,
  pr.full_name as received_by_name
from public.payments p
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.receipts r on r.payment_id = p.id
left join public.profiles pr on pr.id = p.received_by;

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
  normalized_search text := lower(btrim(coalesce(p_search, '')));
  phone_search text := public.compact_phone_search(p_search);
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
      pay.event_member_id as "eventMemberId",
      m.full_name as "member",
      m.phone_e164 as "phone",
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
      and (
        normalized_search = ''
        or m.full_name ilike '%' || btrim(p_search) || '%'
        or pay.payment_number ilike '%' || btrim(p_search) || '%'
        or coalesce(r.receipt_number, '') ilike '%' || btrim(p_search) || '%'
        or coalesce(pay.transaction_reference, '') ilike '%' || btrim(p_search) || '%'
        or (phone_search <> '' and public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%')
      )
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
      'grossRecorded', sum("amount"),
      'reversed', sum("amount") filter (where status = 'REVERSED'),
      'netConfirmed', sum("amount") filter (where status = 'CONFIRMED')
    ) from report_rows), '{"grossRecorded":0,"reversed":0,"netConfirmed":0}'::jsonb)
  into total_rows, rows, totals;

  return jsonb_build_object('data', rows, 'summary', totals, 'pagination', public.report_pagination(page_number, size_number, total_rows));
end;
$$;

grant execute on function public.compact_phone_search(text) to authenticated;
grant execute on function public.rpc_get_event_payment_report(uuid, uuid, date, date, text, uuid, text, text, text, text, integer, integer) to authenticated;

notify pgrst, 'reload schema';
