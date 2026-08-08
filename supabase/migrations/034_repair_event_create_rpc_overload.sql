drop function if exists public.rpc_create_event(uuid, text, text, date, text, numeric, date);

create or replace function public.rpc_create_event(
  p_tenant_id uuid,
  p_name text,
  p_event_type text,
  p_custom_event_type text default null,
  p_event_date date default null,
  p_venue text default null,
  p_target_amount numeric default null,
  p_pledge_deadline date default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  tenant_record public.tenants%rowtype;
  subscription_record public.tenant_subscriptions%rowtype;
  slots jsonb;
  event_code text;
  event_id uuid;
  creator_tenant_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'events.create') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':event-create', 32));

  select * into tenant_record from public.tenants where id = p_tenant_id for update;
  if not found or tenant_record.status not in ('TRIAL', 'ACTIVE') then
    raise exception 'SUBSCRIPTION_INACTIVE' using errcode = '22023';
  end if;

  select * into subscription_record
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id
    and status in ('TRIAL', 'ACTIVE')
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'SUBSCRIPTION_INACTIVE' using errcode = '22023';
  end if;
  if subscription_record.current_period_end is not null and subscription_record.current_period_end < now() then
    raise exception 'SUBSCRIPTION_READ_ONLY' using errcode = '22023';
  end if;

  slots := public.event_slot_usage(p_tenant_id);
  if coalesce((slots ->> 'available')::integer, coalesce((slots ->> 'availableEventSlots')::integer, 0)) <= 0 then
    raise exception 'EVENT_LIMIT_REACHED' using errcode = '22023';
  end if;

  if p_event_type = 'OTHER' and nullif(btrim(coalesce(p_custom_event_type, '')), '') is null then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  event_code := public.next_event_code(p_tenant_id);
  insert into public.events (tenant_id, code, name, event_type, custom_event_type, event_date, venue, target_amount, pledge_deadline, status, created_by)
  values (p_tenant_id, event_code, btrim(p_name), p_event_type, nullif(btrim(coalesce(p_custom_event_type, '')), ''), p_event_date, nullif(btrim(coalesce(p_venue, '')), ''), p_target_amount, p_pledge_deadline, 'ACTIVE', auth.uid())
  returning id into event_id;

  select id into creator_tenant_user_id
  from public.tenant_users
  where tenant_id = p_tenant_id
    and user_id = auth.uid()
    and status = 'ACTIVE'
  limit 1;

  if creator_tenant_user_id is not null then
    insert into public.event_user_assignments (tenant_id, event_id, tenant_user_id, access_level, assigned_by)
    values (p_tenant_id, event_id, creator_tenant_user_id, 'MANAGE', auth.uid())
    on conflict (event_id, tenant_user_id) do update
    set access_level = 'MANAGE',
        assigned_by = excluded.assigned_by;
  end if;

  perform public.write_audit_log(p_tenant_id, 'event.created', 'event', event_id, event_id, null, jsonb_build_object('event_code', event_code, 'eventSlotsBefore', slots));

  return jsonb_build_object(
    'id', event_id,
    'event_id', event_id,
    'eventId', event_id,
    'code', event_code,
    'event_code', event_code,
    'name', btrim(p_name),
    'eventType', p_event_type,
    'eventDate', p_event_date,
    'status', 'ACTIVE',
    'eventSlotsBefore', slots,
    'eventSlotsAfter', public.event_slot_usage(p_tenant_id)
  );
end;
$$;

grant execute on function public.rpc_create_event(uuid, text, text, text, date, text, numeric, date) to authenticated;

notify pgrst, 'reload schema';
