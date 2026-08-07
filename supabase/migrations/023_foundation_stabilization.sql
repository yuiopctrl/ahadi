insert into public.permissions (code, name, description) values
  ('users.view', 'View tenant users', 'View tenant team members and roles'),
  ('users.invite', 'Invite tenant users', 'Invite users into a tenant'),
  ('users.manage_roles', 'Manage tenant user roles', 'Assign tenant-scoped roles'),
  ('users.suspend', 'Suspend tenant users', 'Suspend tenant users')
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('users.view', 'users.invite', 'users.manage_roles', 'users.suspend')
where r.code = 'TENANT_OWNER' and p.code not like 'platform.%'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('users.view', 'users.invite', 'users.manage_roles')
where r.code = 'EVENT_ADMIN' and p.code not like 'platform.%'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'users.view'
where r.code in ('TREASURER', 'COLLECTOR', 'VIEWER') and p.code not like 'platform.%'
on conflict do nothing;

create or replace function public.event_slot_usage(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with current_subscription as (
    select
      coalesce((ts.plan_snapshot ->> 'max_active_events')::integer, sp.max_active_events, 0) as max_slots
    from public.tenant_subscriptions ts
    join public.subscription_plans sp on sp.id = ts.plan_id
    where ts.tenant_id = p_tenant_id
      and ts.status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
    order by ts.created_at desc
    limit 1
  ),
  used as (
    select count(*)::integer as used_slots
    from public.events e
    where e.tenant_id = p_tenant_id
      and e.status in ('DRAFT', 'ACTIVE')
  )
  select jsonb_build_object(
    'usedEventSlots', coalesce((select used_slots from used), 0),
    'maxEventSlots', coalesce((select max_slots from current_subscription), 0),
    'availableEventSlots', greatest(coalesce((select max_slots from current_subscription), 0) - coalesce((select used_slots from used), 0), 0),
    'used_event_slots', coalesce((select used_slots from used), 0),
    'max_event_slots', coalesce((select max_slots from current_subscription), 0),
    'available_event_slots', greatest(coalesce((select max_slots from current_subscription), 0) - coalesce((select used_slots from used), 0), 0)
  );
$$;

create or replace function public.subscription_context_json(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'id', ts.id,
    'status', ts.status,
    'planCode', sp.code,
    'planName', sp.name,
    'trialEndsAt', ts.trial_ends_at,
    'currentPeriodEnd', ts.current_period_end,
    'limits', ts.plan_snapshot || public.event_slot_usage(p_tenant_id)
  )
  from public.tenant_subscriptions ts
  join public.subscription_plans sp on sp.id = ts.plan_id
  where ts.tenant_id = p_tenant_id
    and ts.status in ('TRIAL', 'ACTIVE', 'PAST_DUE', 'SUSPENDED', 'EXPIRED')
  order by ts.created_at desc
  limit 1;
$$;

create or replace function public.event_summary_json(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'code', e.code,
    'name', e.name,
    'eventType', e.event_type,
    'status', e.status,
    'eventDate', e.event_date,
    'pledgeDeadline', e.pledge_deadline,
    'targetAmount', e.target_amount
  ) order by case e.status when 'ACTIVE' then 0 when 'DRAFT' then 1 else 2 end, e.event_date nulls last, e.created_at desc), '[]'::jsonb)
  from public.events e
  where e.tenant_id = p_tenant_id
    and (public.has_tenant_permission(p_tenant_id, 'events.view') or public.can_access_event(e.id));
$$;

create or replace function public.rpc_get_my_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with platform_permissions as (
    select array[
      'platform.dashboard.view',
      'platform.tenants.view',
      'platform.tenants.manage',
      'platform.plans.view',
      'platform.plans.manage',
      'platform.subscriptions.manage',
      'platform.sms.view',
      'platform.audit.view',
      'platform.settings.manage'
    ]::text[] as owner_permissions
  )
  select jsonb_build_object(
    'profile', to_jsonb(p),
    'isPlatformUser', pu.id is not null and pu.status = 'ACTIVE',
    'platformRole', case when pu.status = 'ACTIVE' then pu.role else null end,
    'platformStatus', pu.status,
    'platformPermissions', case
      when pu.status <> 'ACTIVE' or pu.id is null then '[]'::jsonb
      when pu.role = 'PLATFORM_OWNER' then to_jsonb(platform_permissions.owner_permissions)
      when pu.role = 'PLATFORM_ADMIN' then '["platform.dashboard.view","platform.tenants.view","platform.tenants.manage","platform.plans.view","platform.plans.manage","platform.subscriptions.manage","platform.sms.view"]'::jsonb
      when pu.role = 'PLATFORM_SUPPORT' then '["platform.dashboard.view","platform.tenants.view","platform.sms.view"]'::jsonb
      when pu.role = 'PLATFORM_AUDITOR' then '["platform.dashboard.view","platform.audit.view"]'::jsonb
      else '[]'::jsonb
    end,
    'onboardingCompleted', p.onboarding_completed_at is not null,
    'tenantMemberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tenantUserId', tu.id,
        'tenantId', t.id,
        'tenantCode', t.code,
        'tenantName', t.name,
        'tenantSlug', t.slug,
        'tenantStatus', t.status,
        'membershipStatus', tu.status,
        'isOwner', tu.is_owner,
        'roles', coalesce((select jsonb_agg(r.code order by r.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id where tur.tenant_user_id = tu.id and r.code not like 'platform.%'), '[]'::jsonb),
        'permissions', coalesce((select jsonb_agg(distinct perm.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id join public.role_permissions rp on rp.role_id = r.id join public.permissions perm on perm.id = rp.permission_id where tur.tenant_user_id = tu.id and perm.code not like 'platform.%'), '[]'::jsonb),
        'subscription', public.subscription_context_json(t.id),
        'accessibleEvents', public.event_summary_json(t.id)
      ) order by t.created_at)
      from public.tenant_users tu
      join public.tenants t on t.id = tu.tenant_id
      where tu.user_id = auth.uid() and tu.status <> 'REMOVED'
    ), '[]'::jsonb)
  )
  from public.profiles p
  left join public.platform_users pu on pu.user_id = p.id
  cross join platform_permissions
  where p.id = auth.uid();
$$;

comment on function public.rpc_get_my_context() is
'Returns tenant and platform context independently. Platform ownership must be bootstrapped manually in public.platform_users after the intended administrator authenticates.';

create or replace function public.rpc_get_tenant_context(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  allowed boolean;
begin
  allowed := public.is_active_tenant_member(p_tenant_id) or public.has_platform_permission('platform.tenants.view');
  if not allowed then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return (
    select jsonb_build_object(
      'tenant', to_jsonb(t),
      'subscription', public.subscription_context_json(t.id),
      'membership', (
        select jsonb_build_object('id', tu.id, 'status', tu.status, 'isOwner', tu.is_owner)
        from public.tenant_users tu
        where tu.tenant_id = t.id and tu.user_id = auth.uid()
        limit 1
      ),
      'roles', coalesce((select jsonb_agg(r.code order by r.code) from public.tenant_users tu join public.tenant_user_roles tur on tur.tenant_user_id = tu.id join public.roles r on r.id = tur.role_id where tu.tenant_id = t.id and tu.user_id = auth.uid() and r.code not like 'platform.%'), '[]'::jsonb),
      'permissions', coalesce((select jsonb_agg(distinct p.code) from public.tenant_users tu join public.tenant_user_roles tur on tur.tenant_user_id = tu.id join public.roles r on r.id = tur.role_id join public.role_permissions rp on rp.role_id = r.id join public.permissions p on p.id = rp.permission_id where tu.tenant_id = t.id and tu.user_id = auth.uid() and p.code not like 'platform.%'), '[]'::jsonb),
      'events', public.event_summary_json(t.id),
      'accessState', case when t.status in ('ACTIVE', 'TRIAL') then t.status else 'BLOCKED' end
    )
    from public.tenants t
    where t.id = p_tenant_id
  );
end;
$$;

create or replace function public.rpc_create_event(
  p_tenant_id uuid,
  p_name text,
  p_event_type text,
  p_event_date date default null,
  p_venue text default null,
  p_target_amount numeric default null,
  p_pledge_deadline date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  slots jsonb;
  event_code text;
  event_id uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'events.create') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  slots := public.event_slot_usage(p_tenant_id);
  if coalesce((slots ->> 'availableEventSlots')::integer, 0) <= 0 then
    raise exception 'EVENT_LIMIT_REACHED' using errcode = '22023';
  end if;

  event_code := public.next_event_code(p_tenant_id);
  insert into public.events (tenant_id, code, name, event_type, event_date, venue, target_amount, pledge_deadline, status, created_by)
  values (p_tenant_id, event_code, p_name, p_event_type, p_event_date, nullif(p_venue, ''), p_target_amount, p_pledge_deadline, 'ACTIVE', auth.uid())
  returning id into event_id;

  perform public.write_audit_log(p_tenant_id, 'event.created', 'event', event_id, event_id, null, jsonb_build_object('event_code', event_code, 'eventSlotsBefore', slots));

  return jsonb_build_object('event_id', event_id, 'event_code', event_code, 'eventSlotsBefore', slots, 'eventSlotsAfter', public.event_slot_usage(p_tenant_id));
end;
$$;

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
  (p.due_date is not null) as has_custom_due_date
from public.event_members em
join public.events e on e.id = em.event_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED';

create or replace view public.v_event_pledges_list
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  p.id as pledge_id,
  p.event_member_id,
  m.full_name as member_name,
  m.phone_e164,
  c.name as category,
  p.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as total_allocated,
  greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  p.due_date,
  p.status,
  (
    select max(pay.payment_date)
    from public.payments pay
    join public.payment_allocations pa on pa.payment_id = pay.id
    where pa.pledge_id = p.id
      and pay.status = 'CONFIRMED'
  ) as last_payment_date,
  coalesce(p.due_date, e.pledge_deadline) as effective_due_date,
  (p.due_date is not null) as has_custom_due_date
from public.pledges p
join public.events e on e.id = p.event_id
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id;

create or replace view public.v_event_outstanding_members
with (security_invoker = true)
as
select
  p.tenant_id,
  p.event_id,
  m.full_name as member_name,
  m.phone_e164 as phone,
  c.name as category,
  p.pledged_amount,
  coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as paid_amount,
  greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
  p.due_date,
  case when coalesce(p.due_date, e.pledge_deadline) is not null and coalesce(p.due_date, e.pledge_deadline) < current_date and p.status <> 'PAID' then current_date - coalesce(p.due_date, e.pledge_deadline) else 0 end as days_overdue,
  p.status as pledge_status,
  (
    select max(pay.payment_date)
    from public.payments pay
    join public.payment_allocations pa on pa.payment_id = pay.id
    where pa.pledge_id = p.id
      and pay.status = 'CONFIRMED'
  ) as last_payment_date,
  coalesce(p.due_date, e.pledge_deadline) as effective_due_date,
  (p.due_date is not null) as has_custom_due_date
from public.pledges p
join public.events e on e.id = p.event_id
join public.event_members em on em.id = p.event_member_id
join public.members m on m.id = em.member_id
left join public.event_member_categories c on c.id = em.category_id
where p.status in ('PENDING', 'PARTIALLY_PAID', 'OVERDUE');

create or replace function public.rpc_list_event_members(p_tenant_id uuid, p_event_id uuid)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.full_name), '[]'::jsonb)
  into result
  from (
    select *
    from public.v_event_members_list
    where tenant_id = p_tenant_id
      and event_id = p_event_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_list_event_pledges(p_tenant_id uuid, p_event_id uuid)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.effective_due_date asc nulls last, row_data.member_name), '[]'::jsonb)
  into result
  from (
    select *
    from public.v_event_pledges_list
    where tenant_id = p_tenant_id
      and event_id = p_event_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_get_event_member_detail(p_tenant_id uuid, p_event_id uuid, p_event_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  member_record jsonb;
  payments_record jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select to_jsonb(row_data)
  into member_record
  from (
    select *
    from public.v_event_members_list
    where tenant_id = p_tenant_id
      and event_id = p_event_id
      and event_member_id = p_event_member_id
    limit 1
  ) row_data;

  if member_record is null then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.payment_date desc), '[]'::jsonb)
  into payments_record
  from (
    select *
    from public.v_event_payments_list
    where tenant_id = p_tenant_id
      and event_id = p_event_id
      and event_member_id = p_event_member_id
  ) row_data;

  return jsonb_build_object('member', member_record, 'payments', payments_record);
end;
$$;

create or replace function public.rpc_get_receipt_detail(p_tenant_id uuid, p_receipt_id uuid)
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

  select to_jsonb(row_data)
  into result
  from (
    select
      r.tenant_id,
      r.event_id,
      r.id as receipt_id,
      r.receipt_number,
      r.issued_at,
      t.name as tenant_name,
      ts.logo_url as tenant_logo_url,
      e.name as event_name,
      e.event_date,
      m.full_name as member_name,
      m.phone_e164 as member_phone,
      p.id as payment_id,
      p.payment_number,
      p.amount as payment_amount,
      public.payment_allocated_amount(p.id)::numeric(18,2) as allocated_amount,
      public.payment_unallocated_amount(p.id)::numeric(18,2) as unallocated_excess,
      p.payment_method,
      p.transaction_reference,
      p.provider_name,
      p.payment_date,
      p.status as payment_status,
      pl.id as pledge_id,
      pl.pledged_amount,
      coalesce(public.confirmed_pledge_allocated_amount(pl.id), 0)::numeric(18,2) as total_paid_toward_pledge,
      greatest(coalesce(pl.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(pl.id), 0), 0)::numeric(18,2) as outstanding_amount,
      receiver.full_name as received_by,
      rev.reason as reversal_reason,
      rev.reversed_at,
      (
        select to_jsonb(sms_row)
        from (
          select status, last_error_code, last_error_message, sent_at, delivered_at, failed_at
          from public.sms_outbox so
          where so.tenant_id = r.tenant_id
            and so.receipt_id = r.id
            and so.template_code = 'PAYMENT_CONFIRMATION'
          order by so.created_at desc
          limit 1
        ) sms_row
      ) as "smsConfirmation"
    from public.receipts r
    join public.payments p on p.id = r.payment_id
    join public.tenants t on t.id = r.tenant_id
    left join public.tenant_settings ts on ts.tenant_id = r.tenant_id
    join public.events e on e.id = r.event_id
    join public.event_members em on em.id = p.event_member_id
    join public.members m on m.id = em.member_id
    left join public.payment_allocations pa on pa.payment_id = p.id
    left join public.pledges pl on pl.id = pa.pledge_id
    left join public.profiles receiver on receiver.id = p.received_by
    left join public.payment_reversals rev on rev.payment_id = p.id
    where r.tenant_id = p_tenant_id
      and r.id = p_receipt_id
      and public.has_event_financial_access(r.tenant_id, r.event_id, 'receipts.view', 'VIEW')
    order by pa.created_at asc nulls last
    limit 1
  ) row_data;

  if result is null then
    raise exception 'RECEIPT_NOT_FOUND' using errcode = '22023';
  end if;

  return result;
end;
$$;

create or replace function public.rpc_get_event_financial_summary(p_tenant_id uuid, p_event_id uuid)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'payments.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'pledges.view', 'VIEW')
     and not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'memberCount', (select count(*) from public.event_members em where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE'),
    'membersWithPledges', (select count(*) from public.pledges p join public.event_members em on em.id = p.event_member_id where p.tenant_id = p_tenant_id and p.event_id = p_event_id and em.status = 'ACTIVE' and p.status <> 'CANCELLED'),
    'membersWithoutPledges', (select count(*) from public.event_members em where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE' and not exists (select 1 from public.pledges p where p.event_member_id = em.id and p.status <> 'CANCELLED')),
    'totalPledged', (select coalesce(sum(p.pledged_amount), 0)::numeric(18,2) from public.pledges p where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status <> 'CANCELLED'),
    'totalAllocated', (select coalesce(sum(pa.allocated_amount), 0)::numeric(18,2) from public.payment_allocations pa join public.payments pay on pay.id = pa.payment_id where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.status = 'CONFIRMED'),
    'totalAllocatedToPledges', (select coalesce(sum(pa.allocated_amount), 0)::numeric(18,2) from public.payment_allocations pa join public.payments pay on pay.id = pa.payment_id where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.status = 'CONFIRMED'),
    'totalReceived', (select coalesce(sum(pay.amount), 0)::numeric(18,2) from public.payments pay where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.status = 'CONFIRMED'),
    'totalUnallocated', (select coalesce(sum(public.payment_unallocated_amount(pay.id)), 0)::numeric(18,2) from public.payments pay where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.status = 'CONFIRMED'),
    'totalOutstanding', (select coalesce(sum(greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)), 0)::numeric(18,2) from public.pledges p where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status <> 'CANCELLED'),
    'fullyPaidCount', (select count(*) from public.pledges p where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status = 'PAID'),
    'partiallyPaidCount', (select count(*) from public.pledges p where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status = 'PARTIALLY_PAID'),
    'unpaidCount', (select count(*) from public.pledges p where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status = 'PENDING'),
    'overdueCount', (select count(*) from public.pledges p join public.events e on e.id = p.event_id where p.tenant_id = p_tenant_id and p.event_id = p_event_id and p.status in ('PENDING', 'PARTIALLY_PAID', 'OVERDUE') and coalesce(p.due_date, e.pledge_deadline) is not null and coalesce(p.due_date, e.pledge_deadline) < current_date),
    'paymentsToday', (select coalesce(sum(pay.amount), 0)::numeric(18,2) from public.payments pay where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.status = 'CONFIRMED' and pay.payment_date::date = current_date),
    'lastPaymentAt', (select max(pay.payment_date) from public.payments pay where pay.tenant_id = p_tenant_id and pay.event_id = p_event_id and pay.status = 'CONFIRMED')
  );
end;
$$;

create or replace function public.rpc_list_tenant_users(p_tenant_id uuid)
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
  if not public.has_tenant_permission(p_tenant_id, 'users.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.joined_at desc nulls last, row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      tu.id as tenant_user_id,
      tu.user_id,
      p.full_name,
      p.phone_e164,
      p.email,
      tu.status,
      tu.is_owner,
      tu.joined_at,
      tu.created_at,
      coalesce((select jsonb_agg(r.code order by r.code) from public.tenant_user_roles tur join public.roles r on r.id = tur.role_id where tur.tenant_user_id = tu.id and r.code not like 'platform.%'), '[]'::jsonb) as roles,
      coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'accessLevel', eua.access_level) order by e.name) from public.event_user_assignments eua join public.events e on e.id = eua.event_id where eua.tenant_user_id = tu.id), '[]'::jsonb) as assigned_events
    from public.tenant_users tu
    join public.profiles p on p.id = tu.user_id
    where tu.tenant_id = p_tenant_id
      and tu.status <> 'REMOVED'
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_get_tenant_settings_summary(p_tenant_id uuid)
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
  if not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return (
    select jsonb_build_object(
      'organization', jsonb_build_object(
        'name', t.name,
        'code', t.code,
        'phoneE164', t.phone_e164,
        'email', t.email,
        'countryCode', t.country_code,
        'timezone', t.timezone,
        'currency', t.currency,
        'status', t.status
      ),
      'receipts', jsonb_build_object(
        'receiptPrefix', ts.receipt_prefix,
        'logoUrl', ts.logo_url,
        'primaryColor', ts.primary_color
      ),
      'payments', jsonb_build_object(
        'mobileMoneyInstructions', ts.mobile_money_instructions,
        'bankPaymentInstructions', ts.bank_payment_instructions
      ),
      'notifications', jsonb_build_object(
        'smsSenderName', ts.sms_sender_name,
        'paymentConfirmations', true
      ),
      'subscription', public.subscription_context_json(t.id),
      'security', jsonb_build_object(
        'pinRequired', true,
        'roles', coalesce((select jsonb_agg(distinct r.code) from public.tenant_users tu join public.tenant_user_roles tur on tur.tenant_user_id = tu.id join public.roles r on r.id = tur.role_id where tu.tenant_id = t.id and r.code not like 'platform.%'), '[]'::jsonb)
      ),
      'counts', jsonb_build_object(
        'activeUsers', public.active_user_count(t.id),
        'activeEvents', public.active_event_count(t.id),
        'members', public.member_count(t.id)
      )
    )
    from public.tenants t
    left join public.tenant_settings ts on ts.tenant_id = t.id
    where t.id = p_tenant_id
  );
end;
$$;

create or replace function public.rpc_get_platform_dashboard()
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
  if not public.has_platform_permission('platform.dashboard.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'totalTenants', (select count(*) from public.tenants),
    'trialTenants', (select count(*) from public.tenants where status = 'TRIAL'),
    'activeTenants', (select count(*) from public.tenants where status = 'ACTIVE'),
    'suspendedTenants', (select count(*) from public.tenants where status = 'SUSPENDED'),
    'totalEvents', (select count(*) from public.events),
    'subscriptionsExpiringSoon', (select count(*) from public.tenant_subscriptions where status in ('TRIAL', 'ACTIVE') and current_period_end is not null and current_period_end <= now() + interval '14 days')
  );
end;
$$;

create or replace function public.rpc_list_platform_tenants()
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
  if not public.has_platform_permission('platform.tenants.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      t.id,
      t.code,
      t.name,
      t.phone_e164,
      t.email,
      t.status,
      t.created_at,
      sp.code as plan_code,
      sp.name as plan_name,
      ts.status as subscription_status,
      ts.trial_ends_at,
      ts.current_period_end,
      (select count(*)::integer from public.events e where e.tenant_id = t.id and e.status in ('DRAFT', 'ACTIVE')) as active_event_count
    from public.tenants t
    left join lateral (
      select *
      from public.tenant_subscriptions current_ts
      where current_ts.tenant_id = t.id
      order by current_ts.created_at desc
      limit 1
    ) ts on true
    left join public.subscription_plans sp on sp.id = ts.plan_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_list_platform_plans()
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
  if not public.has_platform_permission('platform.plans.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.display_order, row_data.price_amount), '[]'::jsonb)
  into result
  from (
    select
      id,
      code,
      name,
      currency,
      price_amount,
      billing_interval,
      max_active_events,
      max_users,
      max_members,
      included_sms,
      is_active,
      is_public,
      display_order
    from public.subscription_plans
  ) row_data;

  return result;
end;
$$;

grant execute on function public.event_slot_usage(uuid) to authenticated;
grant execute on function public.subscription_context_json(uuid) to authenticated;
grant execute on function public.event_summary_json(uuid) to authenticated;
grant execute on function public.rpc_get_event_member_detail(uuid, uuid, uuid) to authenticated;
grant execute on function public.rpc_get_receipt_detail(uuid, uuid) to authenticated;
grant execute on function public.rpc_list_tenant_users(uuid) to authenticated;
grant execute on function public.rpc_get_tenant_settings_summary(uuid) to authenticated;
grant execute on function public.rpc_get_platform_dashboard() to authenticated;
grant execute on function public.rpc_list_platform_tenants() to authenticated;
grant execute on function public.rpc_list_platform_plans() to authenticated;
