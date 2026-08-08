create or replace function public.rpc_claim_tenant_sms_outbox(
  p_tenant_id uuid,
  p_batch_size integer default 10,
  p_outbox_ids uuid[] default null,
  p_batch_id uuid default null
)
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
    returning o.id, o.tenant_id, o.event_id, o.member_id, o.payment_id, o.receipt_id, o.template_code, o.phone_e164, o.message_body, o.status, o.attempt_count, o.max_attempts
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb)
  into result
  from claimed;

  return result;
end;
$$;

grant execute on function public.rpc_claim_tenant_sms_outbox(uuid, integer, uuid[], uuid) to authenticated;
