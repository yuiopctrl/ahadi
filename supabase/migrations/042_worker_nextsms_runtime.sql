grant execute on function public.rpc_claim_sms_outbox(integer) to anon, authenticated;
grant execute on function public.rpc_mark_sms_sent(uuid, text) to anon, authenticated;
grant execute on function public.rpc_mark_sms_failed(uuid, text, text, boolean) to anon, authenticated;

create or replace function public.rpc_claim_sms_outbox(p_batch_size integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  update public.sms_outbox o
  set status = 'QUEUED',
      processing_started_at = null,
      next_attempt_at = now(),
      last_error_code = 'PROCESSING_TIMEOUT',
      last_error_message = 'Worker did not finish processing this SMS; it was returned to the queue.'
  where o.status = 'PROCESSING'
    and o.processing_started_at is not null
    and o.processing_started_at < now() - interval '5 minutes'
    and o.attempt_count < o.max_attempts;

  with candidates as (
    select o.id
    from public.sms_outbox o
    left join public.payments p on p.id = o.payment_id
    where o.status in ('QUEUED', 'FAILED')
      and o.next_attempt_at <= now()
      and o.attempt_count < o.max_attempts
      and (o.payment_id is null or p.status <> 'REVERSED')
      and o.provider is not null
      and o.sender_id is not null
      and exists (select 1 from public.sms_providers sp where sp.code = o.provider and sp.status = 'ACTIVE')
      and exists (select 1 from public.sms_provider_sender_ids s where s.provider_code = o.provider and s.sender_id = o.sender_id and s.status = 'ACTIVE')
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
    returning o.id, o.tenant_id, o.event_id, o.member_id, o.payment_id, o.receipt_id, o.template_code, o.phone_e164, o.message_body, o.status, o.attempt_count, o.max_attempts, o.sender_id, o.provider
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into result from claimed;
  return result;
end;
$$;

grant execute on function public.rpc_claim_sms_outbox(integer) to anon, authenticated;

create or replace function public.rpc_sms_worker_diagnostics(p_limit integer default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'statusCounts', coalesce((
      select jsonb_object_agg(status_counts.status, status_counts.total)
      from (
        select o.status, count(*)::integer as total
        from public.sms_outbox o
        group by o.status
      ) status_counts
    ), '{}'::jsonb),
    'claimableCount', (
      select count(*)::integer
      from public.sms_outbox o
      left join public.payments p on p.id = o.payment_id
      where o.status in ('QUEUED', 'FAILED')
        and o.next_attempt_at <= now()
        and o.attempt_count < o.max_attempts
        and (o.payment_id is null or p.status <> 'REVERSED')
        and o.provider is not null
        and o.sender_id is not null
        and exists (select 1 from public.sms_providers sp where sp.code = o.provider and sp.status = 'ACTIVE')
        and exists (select 1 from public.sms_provider_sender_ids s where s.provider_code = o.provider and s.sender_id = o.sender_id and s.status = 'ACTIVE')
    ),
    'blockedCounts', jsonb_build_object(
      'missingProvider', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status in ('QUEUED', 'FAILED') and o.provider is null
      ),
      'missingSenderId', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status in ('QUEUED', 'FAILED') and o.sender_id is null
      ),
      'inactiveProvider', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status in ('QUEUED', 'FAILED')
          and o.provider is not null
          and not exists (select 1 from public.sms_providers sp where sp.code = o.provider and sp.status = 'ACTIVE')
      ),
      'inactiveSenderId', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status in ('QUEUED', 'FAILED')
          and o.provider is not null
          and o.sender_id is not null
          and exists (select 1 from public.sms_providers sp where sp.code = o.provider and sp.status = 'ACTIVE')
          and not exists (select 1 from public.sms_provider_sender_ids s where s.provider_code = o.provider and s.sender_id = o.sender_id and s.status = 'ACTIVE')
      ),
      'retryScheduledForFuture', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status in ('QUEUED', 'FAILED') and o.next_attempt_at > now()
      ),
      'maxAttemptsReached', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status in ('QUEUED', 'FAILED') and o.attempt_count >= o.max_attempts
      ),
      'processingNow', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status = 'PROCESSING'
      ),
      'staleProcessing', (
        select count(*)::integer
        from public.sms_outbox o
        where o.status = 'PROCESSING'
          and o.processing_started_at is not null
          and o.processing_started_at < now() - interval '5 minutes'
      )
    ),
    'latest', coalesce((
      select jsonb_agg(to_jsonb(latest_rows) order by latest_rows.created_at desc)
      from (
        select
          o.provider,
          o.sender_id,
          o.status,
          o.attempt_count,
          o.last_error_code,
          o.last_error_message,
          o.created_at
        from public.sms_outbox o
        order by o.created_at desc
        limit greatest(1, least(coalesce(p_limit, 10), 50))
      ) latest_rows
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

grant execute on function public.rpc_sms_worker_diagnostics(integer) to anon, authenticated;

notify pgrst, 'reload schema';
