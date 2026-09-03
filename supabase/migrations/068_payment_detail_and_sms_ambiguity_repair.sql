-- Stabilization mini-batch 2: payment detail 500 + SMS template_code ambiguity.
--
-- Root cause 1 (PAYMENT_DETAIL_FAILED / 500):
--   GET /api/v1/events/:eventId/payments/:paymentId queried the
--   security_invoker view v_event_payments_list directly via PostgREST
--   `.single()`, with no explicit authorization at the API layer (relying
--   entirely on RLS to filter rows) and no logging of the underlying
--   Postgres/PostgREST error before it was mapped to a generic 500 by
--   throwFinancialDatabaseError. Any row-shape mismatch (0 or >1 rows) is
--   turned by PostgREST's single-row contract into an error that doesn't
--   match any of our known domain codes, so it silently becomes
--   INTERNAL_ERROR/500 with the original diagnostic details discarded.
--   Fixed by adding an authoritative SECURITY DEFINER RPC
--   (rpc_get_payment_detail) that performs its own explicit tenant/event/
--   payment validation (matching every other financial RPC in this
--   codebase), returns a single normalized JSON object in one round trip,
--   and raises a specific PAYMENT_NOT_FOUND/EVENT_ACCESS_DENIED error
--   instead of an ambiguous empty result.
--
-- Root cause 2 (42702 "column reference template_code is ambiguous"):
--   rpc_enqueue_payment_confirmation_sms (latest definition: migration 057)
--   declares a PL/pgSQL variable named `template_code` and later runs
--   `select id from public.sms_outbox where ... and template_code in (...)`
--   twice (the idempotency lookup, and again in the unique_violation
--   handler) without qualifying the column, which Postgres refuses to
--   resolve. Fixed by renaming every local scalar variable with a v_
--   prefix and qualifying every table column referenced anywhere in the
--   function body, so no future column addition can reintroduce the same
--   class of bug.

-- ---------------------------------------------------------------------
-- Part 1: authoritative payment detail RPC
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_payment_detail(
  p_tenant_id uuid,
  p_event_id uuid,
  p_payment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.events ev where ev.id = p_event_id and ev.tenant_id = p_tenant_id
  ) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select to_jsonb(row_data)
  into v_result
  from (
    select
      p.tenant_id,
      p.event_id,
      e.name as event_name,
      p.id as payment_id,
      p.payment_number,
      p.amount,
      public.payment_allocated_amount(p.id)::numeric(18,2) as allocated_amount,
      public.payment_unallocated_amount(p.id)::numeric(18,2) as unallocated_amount,
      p.payment_method,
      p.transaction_reference,
      p.provider_name,
      p.payment_date,
      p.notes,
      p.status,
      p.event_member_id,
      m.id as member_id,
      m.full_name as member_name,
      m.phone_e164,
      r.id as receipt_id,
      r.receipt_number,
      case when p.status = 'REVERSED' then 'REVERSED' else 'ISSUED' end as receipt_status,
      pl.id as pledge_id,
      pl.pledged_amount,
      coalesce(public.confirmed_pledge_allocated_amount(pl.id), 0)::numeric(18,2) as pledge_total_paid,
      greatest(coalesce(pl.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(pl.id), 0), 0)::numeric(18,2) as pledge_outstanding,
      case when pl.id is not null then public.calculated_pledge_status(pl.id) else null end as pledge_status,
      p.received_by,
      collector.full_name as received_by_name,
      rev.reversed_at,
      rev.reversed_by,
      reverser.full_name as reversed_by_name,
      rev.reason as reversal_reason,
      case when rev.payment_id is not null then 'REVERSED' else null end as reversal_status
    from public.payments p
    join public.events e on e.id = p.event_id
    join public.event_members em on em.id = p.event_member_id
    join public.members m on m.id = em.member_id
    left join public.receipts r on r.payment_id = p.id
    left join public.payment_allocations pa on pa.payment_id = p.id
    left join public.pledges pl on pl.id = pa.pledge_id
    left join public.profiles collector on collector.id = p.received_by
    left join public.payment_reversals rev on rev.payment_id = p.id
    left join public.profiles reverser on reverser.id = rev.reversed_by
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
      and p.id = p_payment_id
    order by pa.created_at asc nulls last
    limit 1
  ) row_data;

  if v_result is null then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;

  return v_result;
end;
$$;

grant execute on function public.rpc_get_payment_detail(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Part 2: fix ambiguous template_code references
-- ---------------------------------------------------------------------

create or replace function public.rpc_enqueue_payment_confirmation_sms(p_tenant_id uuid, p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_payment public.payments%rowtype;
  v_member public.members%rowtype;
  v_event public.events%rowtype;
  v_receipt public.receipts%rowtype;
  v_pledge public.pledges%rowtype;
  v_template_code text;
  v_template_body text;
  v_message text;
  v_outbox_id uuid;
  v_idempotency_key text;
  v_outstanding numeric(18,2);
  v_provider_settings record;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into v_payment from public.payments where public.payments.id = p_payment_id and public.payments.tenant_id = p_tenant_id;
  if not found then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = '22023';
  end if;

  if not public.has_event_financial_access(v_payment.tenant_id, v_payment.event_id, 'payments.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  if v_payment.status = 'REVERSED' then
    return jsonb_build_object('smsQueued', false, 'reason', 'PAYMENT_REVERSED');
  end if;

  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED');
  end if;

  select m.* into v_member
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = v_payment.event_member_id
    and em.tenant_id = p_tenant_id
    and em.event_id = v_payment.event_id;
  if not found then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  if v_member.phone_e164 is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'NO_PHONE');
  end if;
  if coalesce(v_member.sms_enabled, true) = false then
    return jsonb_build_object('smsQueued', false, 'reason', 'SMS_DISABLED');
  end if;

  select * into v_event from public.events where public.events.id = v_payment.event_id and public.events.tenant_id = p_tenant_id;
  select * into v_receipt from public.receipts where public.receipts.payment_id = v_payment.id and public.receipts.tenant_id = p_tenant_id;

  select p.* into v_pledge
  from public.payment_allocations pa
  join public.pledges p on p.id = pa.pledge_id
  where pa.payment_id = v_payment.id and pa.tenant_id = p_tenant_id
  order by pa.created_at
  limit 1;

  v_outstanding := case
    when v_pledge.id is not null then greatest(v_pledge.pledged_amount - public.confirmed_pledge_allocated_amount(v_pledge.id), 0)
    else 0
  end;
  v_template_code := case
    when v_pledge.id is not null and v_outstanding <= 0 then 'PLEDGE_COMPLETED'
    else 'PAYMENT_CONFIRMATION'
  end;
  v_idempotency_key := v_template_code || ':' || v_payment.id::text;

  select so.id into v_outbox_id
  from public.sms_outbox so
  where so.payment_id = p_payment_id
    and so.template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED')
    and so.status <> 'CANCELLED'
  limit 1;
  if found then
    return jsonb_build_object('smsQueued', true, 'outboxId', v_outbox_id, 'reason', 'ALREADY_QUEUED', 'template', v_template_code);
  end if;

  v_template_body := public.resolve_sms_template_body(p_tenant_id, v_template_code, v_member.preferred_language);
  if v_template_body is null then
    return jsonb_build_object('smsQueued', false, 'reason', 'TEMPLATE_NOT_FOUND', 'template', v_template_code);
  end if;

  v_message := public.render_sms_template(
    v_template_body,
    jsonb_build_object(
      'member_name', v_member.full_name,
      'payment_amount', public.format_tzs_sms_amount(v_payment.amount),
      'payment_method', public.payment_method_sms_name(v_payment.payment_method),
      'event_name', v_event.name,
      'balance', public.format_tzs_sms_amount(v_outstanding),
      'receipt_number', v_receipt.receipt_number,
      'pledge_amount', public.format_tzs_sms_amount(coalesce(v_pledge.pledged_amount, v_payment.amount))
    )
  );

  select * into v_provider_settings from public.tenant_sms_provider_settings(p_tenant_id);

  insert into public.sms_outbox (
    tenant_id, event_id, member_id, event_member_id, payment_id, receipt_id,
    template_code, phone_e164, message_body, status, idempotency_key, sender_id, provider
  )
  values (
    p_tenant_id, v_payment.event_id, v_member.id, v_payment.event_member_id, v_payment.id, v_receipt.id,
    v_template_code, v_member.phone_e164, v_message, 'QUEUED', v_idempotency_key, v_provider_settings.sender_id, v_provider_settings.provider_code
  )
  returning id into v_outbox_id;

  return jsonb_build_object('smsQueued', true, 'outboxId', v_outbox_id, 'template', v_template_code, 'provider', v_provider_settings.provider_code, 'senderId', v_provider_settings.sender_id);
exception when unique_violation then
  select so.id into v_outbox_id
  from public.sms_outbox so
  where so.payment_id = p_payment_id
    and so.template_code in ('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED')
    and so.status <> 'CANCELLED'
  limit 1;
  return jsonb_build_object('smsQueued', true, 'outboxId', v_outbox_id, 'reason', 'ALREADY_QUEUED', 'template', v_template_code);
end;
$$;

grant execute on function public.rpc_enqueue_payment_confirmation_sms(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
