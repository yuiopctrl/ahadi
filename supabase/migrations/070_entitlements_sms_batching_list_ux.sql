-- Stabilization batch: entitlements + SMS batching + list UX + audit detail.
--
-- Part 1 (Issue 1): Contact/member capacity was never actually enforced
-- anywhere in the codebase -- not in rpc_create_contact, not in
-- rpc_create_member_and_attach_to_event, not in the API layer, not in the
-- client. subscription_plans.max_members was only ever stored/displayed.
-- This adds the missing enforcement, reading the tenant's CURRENT active
-- subscription joined LIVE to subscription_plans (never plan_snapshot,
-- which is a point-in-time copy) so an upgrade takes effect immediately on
-- the very next write, with no caching layer to invalidate.
--
-- Part 2 (Issue 3): rpc_list_event_members took no sort/filter/pagination
-- parameters at all -- the whole event's member list was fetched in one
-- shot and every screen sorted/filtered client-side over that one page.
-- Extended additively with search/pledgeStatus/phoneStatus/sort/direction/
-- limit/offset, mirroring rpc_list_organization_activity's pagination
-- response shape.
--
-- Part 3 (Issue 2): rpc_enqueue_custom_sms_bulk had no entitlement check at
-- all (unlike its sibling bulk-SMS RPCs, which all call
-- sms_allowance_status). The only recipient-count guard was a hard
-- p_max_batch_size cap defaulting to 100 -- and the API route passed
-- env.BALANCE_REMINDER_MAX_BATCH_SIZE for it, a constant that belongs to a
-- different feature and is reused (see apps/api/src/app.ts) across three
-- unrelated bulk-SMS routes. Fixed by: raising the batch-size default so a
-- single call can carry a realistic campaign, and adding the real balance
-- check other bulk-SMS RPCs already have, returning (not raising, matching
-- the existing LOW_BALANCE precedent) a clear SMS_BALANCE_INSUFFICIENT
-- reason with available/requested counts the client can render directly.
--
-- Part 4 (Issue 5): rpc_list_organization_activity already resolves
-- actor_name and event_name server-side, but not a generic entity display
-- name -- added for the entity types this table actually records.
--
-- Part 5 (pre-deploy concurrency hardening): the check-then-write sequences
-- in Parts 1b and 3 are each read-then-conditionally-insert under
-- read-committed isolation, so two concurrent calls for the same tenant
-- could each read a usage/balance snapshot taken before either one wrote,
-- and both pass. Both sequences now take a per-tenant pg_advisory_xact_lock
-- (this migration's own convention, already used elsewhere for
-- event-create -- see hashtextextended(p_tenant_id::text || ':event-create',
-- 32) in migrations 026/034/035/036) before recomputing usage/balance, so
-- the second concurrent call blocks until the first commits and then sees
-- the first call's effect.

-- ---------------------------------------------------------------------
-- Part 1a: authoritative member/contact usage resolver
-- ---------------------------------------------------------------------

create or replace function public.tenant_member_usage(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with current_subscription as (
    select sp.max_members
    from public.tenant_subscriptions ts
    join public.subscription_plans sp on sp.id = ts.plan_id
    where ts.tenant_id = p_tenant_id
      and ts.status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
    order by ts.created_at desc
    limit 1
  ),
  member_count as (
    select count(*)::integer as used
    from public.members
    where tenant_id = p_tenant_id and status = 'ACTIVE'
  )
  select jsonb_build_object(
    'used', (select used from member_count),
    'limit', (select max_members from current_subscription),
    'available', case
      when (select max_members from current_subscription) is null then null
      else greatest((select max_members from current_subscription) - (select used from member_count), 0)
    end
  );
$$;

grant execute on function public.tenant_member_usage(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Part 1b: enforce the limit at the only two places contacts are created
-- ---------------------------------------------------------------------

create or replace function public.rpc_create_contact(
  p_tenant_id uuid,
  p_full_name text,
  p_phone text default null,
  p_alternative_phone text default null,
  p_email text default null,
  p_location text default null,
  p_notes text default null,
  p_sms_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  normalized_phone text;
  normalized_alt_phone text;
  contact_id uuid;
  contact_code text;
  v_usage jsonb;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_tenant_permission(p_tenant_id, 'members.create') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if btrim(coalesce(p_full_name, '')) = '' then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  -- Serialize capacity-changing contact creation per tenant so two
  -- concurrent inserts can't both observe used < limit and both proceed.
  -- Held for the rest of this transaction; recompute usage only AFTER
  -- acquiring it, so the count below is guaranteed fresh relative to any
  -- other create-contact transaction for this same tenant. Shared with
  -- rpc_create_member_and_attach_to_event (same lock key) since both
  -- mutate the same tenant-wide public.members count.
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':contact-create', 51));

  v_usage := public.tenant_member_usage(p_tenant_id);
  if (v_usage ->> 'limit') is not null and (v_usage ->> 'used')::integer >= (v_usage ->> 'limit')::integer then
    raise exception 'CONTACT_LIMIT_REACHED' using errcode = '22023';
  end if;

  normalized_phone := case when p_phone is null or btrim(p_phone) = '' then null else public.normalize_tz_phone(p_phone) end;
  normalized_alt_phone := case when p_alternative_phone is null or btrim(p_alternative_phone) = '' then null else public.normalize_tz_phone(p_alternative_phone) end;

  if normalized_phone is not null and exists (
    select 1
    from public.members
    where tenant_id = p_tenant_id
      and phone_e164 = normalized_phone
      and status = 'ACTIVE'
  ) then
    raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505';
  end if;

  contact_code := public.next_member_code(p_tenant_id);
  insert into public.members (tenant_id, member_code, full_name, phone_e164, alternative_phone_e164, email, location, notes, sms_enabled, created_by)
  values (
    p_tenant_id, contact_code, p_full_name, normalized_phone, normalized_alt_phone,
    nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_location, '')), ''),
    p_notes, coalesce(p_sms_enabled, true) and normalized_phone is not null, caller
  )
  returning id into contact_id;

  perform public.write_audit_log(p_tenant_id, 'contact.created', 'member', contact_id, null, null, jsonb_build_object('member_code', contact_code));

  return jsonb_build_object('member_id', contact_id, 'member_code', contact_code);
end;
$$;

create or replace function public.rpc_create_member_and_attach_to_event(
  p_tenant_id uuid, p_event_id uuid, p_full_name text, p_phone text default null,
  p_alternative_phone text default null, p_email text default null, p_location text default null,
  p_category_id uuid default null, p_notes text default null, p_sms_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  normalized_phone text;
  normalized_alt_phone text;
  member_id uuid;
  event_member_id uuid;
  member_code text;
  v_usage jsonb;
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if btrim(coalesce(p_full_name, '')) = '' then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  -- This RPC creates a brand-new Contact (public.members) as well as
  -- attaching it to the event, so the same organization-wide capacity
  -- check applies here as in rpc_create_contact -- including the same
  -- per-tenant advisory lock (same key), so a concurrent rpc_create_contact
  -- and rpc_create_member_and_attach_to_event for the same tenant also
  -- serialize against each other, not just against themselves.
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':contact-create', 51));

  v_usage := public.tenant_member_usage(p_tenant_id);
  if (v_usage ->> 'limit') is not null and (v_usage ->> 'used')::integer >= (v_usage ->> 'limit')::integer then
    raise exception 'CONTACT_LIMIT_REACHED' using errcode = '22023';
  end if;

  normalized_phone := case when p_phone is null or btrim(p_phone) = '' then null else public.normalize_tz_phone(p_phone) end;
  normalized_alt_phone := case when p_alternative_phone is null or btrim(p_alternative_phone) = '' then null else public.normalize_tz_phone(p_alternative_phone) end;

  if normalized_phone is not null and exists (
    select 1 from public.members
    where tenant_id = p_tenant_id and phone_e164 = normalized_phone and status = 'ACTIVE'
  ) then
    raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505';
  end if;

  member_code := public.next_member_code(p_tenant_id);
  insert into public.members (tenant_id, member_code, full_name, phone_e164, alternative_phone_e164, email, location, notes, sms_enabled, created_by)
  values (p_tenant_id, member_code, p_full_name, normalized_phone, normalized_alt_phone, nullif(btrim(coalesce(p_email, '')), ''), nullif(btrim(coalesce(p_location, '')), ''), p_notes, coalesce(p_sms_enabled, true), caller)
  returning id into member_id;

  insert into public.event_members (tenant_id, event_id, member_id, category_id, notes, created_by)
  values (p_tenant_id, p_event_id, member_id, p_category_id, p_notes, caller)
  returning id into event_member_id;

  perform public.write_audit_log(p_tenant_id, 'member.created', 'member', member_id, p_event_id, null, jsonb_build_object('member_code', member_code));
  perform public.write_audit_log(p_tenant_id, 'event_member.attached', 'event_member', event_member_id, p_event_id, null, jsonb_build_object('member_id', member_id));

  return jsonb_build_object('member_id', member_id, 'event_member_id', event_member_id, 'member_code', member_code);
end;
$$;

-- ---------------------------------------------------------------------
-- Part 1c: rpc_list_contacts -- add real server-side pagination + total
-- count + the same usage resolver, so the Contacts screen can show an
-- authoritative "287 / 500" without a second round trip.
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_contacts(
  p_tenant_id uuid,
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
  search_text text := nullif(btrim(coalesce(p_search, '')), '');
  phone_search text := nullif(public.compact_phone_search(coalesce(p_search, '')), '');
  total_rows bigint;
  rows_json jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'members.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select count(*)
  into total_rows
  from public.members m
  where m.tenant_id = p_tenant_id
    and (
      search_text is null
      or m.full_name ilike '%' || search_text || '%'
      or (phone_search is not null and (
        public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%'
        or public.compact_phone_search(m.alternative_phone_e164) like '%' || phone_search || '%'
      ))
    );

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.full_name), '[]'::jsonb)
  into rows_json
  from (
    select
      m.id as member_id, m.member_code, m.full_name, m.phone_e164, m.alternative_phone_e164,
      m.email, m.location, m.notes, m.sms_enabled, m.status, m.created_at, m.updated_at,
      count(em.id) filter (where em.status = 'ACTIVE')::integer as event_count,
      max(e.event_date) filter (where em.status = 'ACTIVE') as latest_event_date
    from public.members m
    left join public.event_members em on em.member_id = m.id and em.tenant_id = p_tenant_id
    left join public.events e on e.id = em.event_id and e.tenant_id = p_tenant_id
    where m.tenant_id = p_tenant_id
      and (
        search_text is null
        or m.full_name ilike '%' || search_text || '%'
        or (phone_search is not null and (
          public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%'
          or public.compact_phone_search(m.alternative_phone_e164) like '%' || phone_search || '%'
        ))
      )
    group by m.id
    order by m.full_name
    limit safe_limit
    offset safe_offset
  ) row_data;

  return jsonb_build_object(
    'data', rows_json,
    'pagination', jsonb_build_object(
      'limit', safe_limit,
      'offset', safe_offset,
      'totalRows', total_rows,
      'hasMore', (safe_offset + safe_limit) < total_rows
    ),
    'usage', public.tenant_member_usage(p_tenant_id)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Part 2a: extend v_event_members_list with created_at, needed for the
-- Newest/Oldest sort option. `create or replace view` can only append a
-- new column at the end of the select list -- inserting it in the middle
-- renames every column after it by ordinal position and Postgres rejects
-- that (42P16) -- so event_member_created_at is added last, referenced by
-- name everywhere it's used.
-- ---------------------------------------------------------------------

create or replace view public.v_event_members_list
with (security_invoker = true)
as
select
  em.tenant_id,
  em.event_id,
  em.id as event_member_id,
  m.id as member_id,
  m.member_code,
  m.full_name,
  m.phone_e164,
  c.name as category,
  em.status as event_member_status,
  p.id as pledge_id,
  p.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as total_allocated,
  greatest(coalesce(p.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  p.status as pledge_status,
  (
    select max(pay.payment_date)
    from public.payments pay
    where pay.event_member_id = em.id
      and pay.status = 'CONFIRMED'
  ) as last_payment_date,
  m.alternative_phone_e164,
  m.email,
  m.location,
  m.sms_enabled,
  p.due_date,
  coalesce(p.due_date, e.pledge_deadline) as effective_due_date,
  (p.due_date is not null) as has_custom_due_date,
  m.notes,
  m.preferred_language,
  m.status as member_status,
  em.created_at as event_member_created_at
from public.event_members em
join public.events e on e.id = em.event_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED';

grant select on public.v_event_members_list to authenticated;

-- ---------------------------------------------------------------------
-- Part 2b: rpc_list_event_members -- additive search/filter/sort/
-- pagination, applied server-side over the full event dataset.
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_event_members(
  p_tenant_id uuid,
  p_event_id uuid,
  p_search text default null,
  p_pledge_status text default 'ALL',
  p_phone_status text default 'ALL',
  p_sort text default 'NAME',
  p_direction text default 'ASC',
  p_limit integer default null,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
  safe_limit integer := case when p_limit is null then null else least(greatest(p_limit, 1), 500) end;
  search_text text := nullif(btrim(coalesce(p_search, '')), '');
  phone_search text := nullif(public.compact_phone_search(coalesce(p_search, '')), '');
  pledge_filter text := upper(coalesce(nullif(btrim(p_pledge_status), ''), 'ALL'));
  phone_filter text := upper(coalesce(nullif(btrim(p_phone_status), ''), 'ALL'));
  sort_key text := upper(coalesce(nullif(btrim(p_sort), ''), 'NAME'));
  sort_dir text := case when upper(coalesce(p_direction, 'ASC')) = 'DESC' then 'DESC' else 'ASC' end;
  total_rows bigint;
  rows_json jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if pledge_filter not in ('ALL', 'HAS_PLEDGE', 'NO_PLEDGE', 'FULLY_PAID', 'PARTIALLY_PAID', 'UNPAID') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if phone_filter not in ('ALL', 'HAS_PHONE', 'NO_PHONE') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if sort_key not in ('NAME', 'CREATED', 'PLEDGE_AMOUNT', 'OUTSTANDING') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  select count(*)
  into total_rows
  from public.v_event_members_list v
  where v.tenant_id = p_tenant_id
    and v.event_id = p_event_id
    and (search_text is null or v.full_name ilike '%' || search_text || '%' or (phone_search is not null and public.compact_phone_search(v.phone_e164) like '%' || phone_search || '%'))
    and (
      pledge_filter = 'ALL'
      or (pledge_filter = 'HAS_PLEDGE' and v.pledge_id is not null)
      or (pledge_filter = 'NO_PLEDGE' and v.pledge_id is null)
      or (pledge_filter = 'FULLY_PAID' and v.pledge_id is not null and v.outstanding_amount <= 0)
      or (pledge_filter = 'PARTIALLY_PAID' and v.pledge_id is not null and v.outstanding_amount > 0 and v.total_allocated > 0)
      or (pledge_filter = 'UNPAID' and v.pledge_id is not null and v.total_allocated = 0)
    )
    and (
      phone_filter = 'ALL'
      or (phone_filter = 'HAS_PHONE' and v.phone_e164 is not null)
      or (phone_filter = 'NO_PHONE' and v.phone_e164 is null)
    );

  select coalesce(jsonb_agg(to_jsonb(row_data)), '[]'::jsonb)
  into rows_json
  from (
    select *
    from public.v_event_members_list v
    where v.tenant_id = p_tenant_id
      and v.event_id = p_event_id
      and (search_text is null or v.full_name ilike '%' || search_text || '%' or (phone_search is not null and public.compact_phone_search(v.phone_e164) like '%' || phone_search || '%'))
      and (
        pledge_filter = 'ALL'
        or (pledge_filter = 'HAS_PLEDGE' and v.pledge_id is not null)
        or (pledge_filter = 'NO_PLEDGE' and v.pledge_id is null)
        or (pledge_filter = 'FULLY_PAID' and v.pledge_id is not null and v.outstanding_amount <= 0)
        or (pledge_filter = 'PARTIALLY_PAID' and v.pledge_id is not null and v.outstanding_amount > 0 and v.total_allocated > 0)
        or (pledge_filter = 'UNPAID' and v.pledge_id is not null and v.total_allocated = 0)
      )
      and (
        phone_filter = 'ALL'
        or (phone_filter = 'HAS_PHONE' and v.phone_e164 is not null)
        or (phone_filter = 'NO_PHONE' and v.phone_e164 is null)
      )
    order by
      case when sort_key = 'NAME' and sort_dir = 'ASC' then v.full_name end asc,
      case when sort_key = 'NAME' and sort_dir = 'DESC' then v.full_name end desc,
      case when sort_key = 'CREATED' and sort_dir = 'ASC' then v.event_member_created_at end asc,
      case when sort_key = 'CREATED' and sort_dir = 'DESC' then v.event_member_created_at end desc,
      case when sort_key = 'PLEDGE_AMOUNT' and sort_dir = 'ASC' then v.pledged_amount end asc,
      case when sort_key = 'PLEDGE_AMOUNT' and sort_dir = 'DESC' then v.pledged_amount end desc,
      case when sort_key = 'OUTSTANDING' and sort_dir = 'ASC' then v.outstanding_amount end asc,
      case when sort_key = 'OUTSTANDING' and sort_dir = 'DESC' then v.outstanding_amount end desc,
      v.full_name asc
    limit coalesce(safe_limit, 100000)
    offset safe_offset
  ) row_data;

  return jsonb_build_object(
    'data', rows_json,
    'pagination', jsonb_build_object(
      'limit', safe_limit,
      'offset', safe_offset,
      'totalRows', total_rows,
      'hasMore', case when safe_limit is null then false else (safe_offset + safe_limit) < total_rows end
    )
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Part 3: rpc_enqueue_custom_sms_bulk -- real balance check (previously
-- entirely absent for this RPC, unlike its siblings) and a much larger
-- batch-size ceiling so one call can carry a realistic campaign instead
-- of forcing the client to split it into unrelated requests.
-- ---------------------------------------------------------------------

create or replace function public.rpc_enqueue_custom_sms_bulk(
  p_tenant_id uuid, p_event_id uuid, p_code text, p_event_member_ids uuid[], p_sender_id text,
  p_idempotency_key text, p_max_batch_size integer default 2000
)
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
  eligible_count integer := 0;
  v_allowance jsonb;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;
  if not public.tenant_sms_enabled(p_tenant_id) then
    return jsonb_build_object('requested', requested, 'queued', 0, 'reason', 'TENANT_SMS_DISABLED');
  end if;
  if requested = 0 then raise exception 'CUSTOM_SMS_BATCH_EMPTY' using errcode = '22023'; end if;
  if requested > greatest(coalesce(p_max_batch_size, 2000), 1) then raise exception 'CUSTOM_SMS_BATCH_TOO_LARGE' using errcode = '22023'; end if;

  select * into template_record
  from public.sms_templates
  where tenant_id = p_tenant_id and code = normalized_code and is_system = false;
  if not found then raise exception 'SMS_TEMPLATE_NOT_FOUND' using errcode = '22023'; end if;

  -- Serialize the balance-check-then-enqueue sequence per tenant so two
  -- concurrent bulk sends can't both pass sms_allowance_status against the
  -- same pre-insert balance and jointly oversubscribe it. Held for the
  -- rest of this transaction (through the outbox inserts below), so the
  -- next concurrent call for this tenant blocks until this one commits
  -- and only then evaluates the balance -- by which point this call's
  -- sms_outbox rows are already visible to it.
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':custom-sms-send', 52));

  -- Count how many of the requested recipients would actually be
  -- eligible (have a phone, SMS enabled) BEFORE touching the SMS
  -- balance/entitlement, so the balance check reflects real send volume,
  -- not the raw selection size.
  select
    count(*) filter (where public.custom_sms_ineligibility_reason(m.phone_e164, m.sms_enabled) = 'NO_PHONE'),
    count(*) filter (where public.custom_sms_ineligibility_reason(m.phone_e164, m.sms_enabled) = 'SMS_DISABLED'),
    count(*) filter (where public.custom_sms_ineligibility_reason(m.phone_e164, m.sms_enabled) is null)
  into no_phone, sms_disabled, eligible_count
  from public.event_members em
  join public.members m on m.id = em.member_id
  join unnest(p_event_member_ids) ids(id) on ids.id = em.id
  where em.tenant_id = p_tenant_id and em.event_id = p_event_id;

  if eligible_count > 0 then
    v_allowance := public.sms_allowance_status(p_tenant_id, eligible_count);
    if v_allowance ->> 'status' in ('LIMIT_REACHED', 'LOW_BALANCE') then
      return jsonb_build_object(
        'requested', requested,
        'queued', 0,
        'skipped', jsonb_build_object('noPhone', no_phone, 'smsDisabled', sms_disabled),
        'smsAllowance', v_allowance,
        'reason', 'SMS_BALANCE_INSUFFICIENT'
      );
    end if;
  end if;

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
    if row_record.reason = 'NO_PHONE' or row_record.reason = 'SMS_DISABLED' then
      continue;
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

-- ---------------------------------------------------------------------
-- Part 3b: rpc_preview_custom_sms_bulk -- surface the same allowance info
-- before the user confirms, so the UI can show available balance and
-- estimated SMS units up front.
-- ---------------------------------------------------------------------

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
    'previews', previews,
    'smsAllowance', case when eligible_count > 0 then public.sms_allowance_status(p_tenant_id, eligible_count) else null end
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Part 4: rpc_list_organization_activity -- add entity_display_name for
-- the entity types this table actually records, resolved server-side in
-- the same query (no N+1). old_values/new_values remain untouched and
-- authoritative; this is purely an additive read-model convenience.
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_organization_activity(
  p_tenant_id uuid,
  p_limit integer default 20,
  p_offset integer default 0,
  p_search text default null,
  p_action text default null,
  p_entity_type text default null,
  p_event_id uuid default null,
  p_actor_user_id uuid default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  safe_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
  search_text text := nullif(btrim(coalesce(p_search, '')), '');
  total_rows bigint;
  rows_json jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  if not public.has_tenant_permission(p_tenant_id, 'audit.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select count(*)
  into total_rows
  from public.audit_logs al
  left join public.profiles pr on pr.id = al.actor_user_id
  left join public.events ev on ev.id = al.event_id
  where al.tenant_id = p_tenant_id
    and (p_action is null or al.action = p_action)
    and (p_entity_type is null or al.entity_type = p_entity_type)
    and (p_event_id is null or al.event_id = p_event_id)
    and (p_actor_user_id is null or al.actor_user_id = p_actor_user_id)
    and (p_date_from is null or al.created_at >= p_date_from)
    and (p_date_to is null or al.created_at <= p_date_to)
    and (
      search_text is null
      or al.action ilike '%' || search_text || '%'
      or al.entity_type ilike '%' || search_text || '%'
      or coalesce(pr.full_name, '') ilike '%' || search_text || '%'
      or coalesce(ev.name, '') ilike '%' || search_text || '%'
    );

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into rows_json
  from (
    select
      al.id, al.created_at, al.action, al.entity_type, al.entity_id, al.event_id,
      ev.name as event_name, al.actor_user_id, pr.full_name as actor_name,
      al.old_values, al.new_values, al.reason, al.request_id,
      case al.entity_type
        when 'member' then (select mm.full_name from public.members mm where mm.id = al.entity_id)
        when 'event_member' then (
          select mm.full_name from public.event_members emm join public.members mm on mm.id = emm.member_id where emm.id = al.entity_id
        )
        when 'event' then coalesce(ev.name, (select ee.name from public.events ee where ee.id = al.entity_id))
        when 'pledge' then (
          select mm.full_name from public.pledges pl join public.event_members emm on emm.id = pl.event_member_id join public.members mm on mm.id = emm.member_id where pl.id = al.entity_id
        )
        when 'payment' then (
          select mm.full_name from public.payments py join public.event_members emm on emm.id = py.event_member_id join public.members mm on mm.id = emm.member_id where py.id = al.entity_id
        )
        when 'tenant_user' then (
          select p2.full_name from public.tenant_users tu join public.profiles p2 on p2.id = tu.user_id where tu.id = al.entity_id
        )
        else null
      end as entity_display_name
    from public.audit_logs al
    left join public.profiles pr on pr.id = al.actor_user_id
    left join public.events ev on ev.id = al.event_id
    where al.tenant_id = p_tenant_id
      and (p_action is null or al.action = p_action)
      and (p_entity_type is null or al.entity_type = p_entity_type)
      and (p_event_id is null or al.event_id = p_event_id)
      and (p_actor_user_id is null or al.actor_user_id = p_actor_user_id)
      and (p_date_from is null or al.created_at >= p_date_from)
      and (p_date_to is null or al.created_at <= p_date_to)
      and (
        search_text is null
        or al.action ilike '%' || search_text || '%'
        or al.entity_type ilike '%' || search_text || '%'
        or coalesce(pr.full_name, '') ilike '%' || search_text || '%'
        or coalesce(ev.name, '') ilike '%' || search_text || '%'
      )
    order by al.created_at desc
    limit safe_limit
    offset safe_offset
  ) row_data;

  return jsonb_build_object(
    'data', rows_json,
    'pagination', jsonb_build_object(
      'limit', safe_limit,
      'offset', safe_offset,
      'totalRows', total_rows,
      'hasMore', (safe_offset + safe_limit) < total_rows
    )
  );
end;
$$;

notify pgrst, 'reload schema';
