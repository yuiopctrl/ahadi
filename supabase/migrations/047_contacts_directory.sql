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
    p_tenant_id,
    contact_code,
    p_full_name,
    normalized_phone,
    normalized_alt_phone,
    nullif(btrim(coalesce(p_email, '')), ''),
    nullif(btrim(coalesce(p_location, '')), ''),
    p_notes,
    coalesce(p_sms_enabled, true) and normalized_phone is not null,
    caller
  )
  returning id into contact_id;

  perform public.write_audit_log(p_tenant_id, 'contact.created', 'member', contact_id, null, null, jsonb_build_object('member_code', contact_code));

  return jsonb_build_object('member_id', contact_id, 'member_code', contact_code);
end;
$$;

create or replace function public.rpc_list_contacts(p_tenant_id uuid)
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
  if not public.has_tenant_permission(p_tenant_id, 'members.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.full_name), '[]'::jsonb)
  into result
  from (
    select
      m.id as member_id,
      m.member_code,
      m.full_name,
      m.phone_e164,
      m.alternative_phone_e164,
      m.email,
      m.location,
      m.notes,
      m.sms_enabled,
      m.status,
      m.created_at,
      m.updated_at,
      count(em.id) filter (where em.status = 'ACTIVE')::integer as event_count,
      max(e.event_date) filter (where em.status = 'ACTIVE') as latest_event_date
    from public.members m
    left join public.event_members em on em.member_id = m.id and em.tenant_id = p_tenant_id
    left join public.events e on e.id = em.event_id and e.tenant_id = p_tenant_id
    where m.tenant_id = p_tenant_id
    group by m.id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_list_contacts_available_for_event(p_tenant_id uuid, p_event_id uuid)
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
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'members.assign_event', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.full_name), '[]'::jsonb)
  into result
  from (
    select
      m.id as member_id,
      m.member_code,
      m.full_name,
      m.phone_e164,
      m.location,
      m.sms_enabled,
      m.status,
      count(other_em.id) filter (where other_em.status = 'ACTIVE' and other_em.event_id <> p_event_id)::integer as other_event_count
    from public.members m
    left join public.event_members current_em on current_em.member_id = m.id and current_em.event_id = p_event_id and current_em.status = 'ACTIVE'
    left join public.event_members other_em on other_em.member_id = m.id and other_em.tenant_id = p_tenant_id
    where m.tenant_id = p_tenant_id
      and m.status <> 'ARCHIVED'
      and current_em.id is null
    group by m.id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_get_contact_detail(p_tenant_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  contact jsonb;
  events jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'members.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select to_jsonb(m)
  into contact
  from public.members m
  where m.tenant_id = p_tenant_id
    and m.id = p_member_id;

  if contact is null then
    raise exception 'MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.event_date desc nulls last, row_data.event_name), '[]'::jsonb)
  into events
  from (
    select
      em.id as event_member_id,
      e.id as event_id,
      e.name as event_name,
      e.event_type,
      e.event_date,
      em.status as participation_status,
      c.name as category,
      p.id as pledge_id,
      p.status as pledge_status,
      coalesce(p.pledged_amount, 0)::numeric(18,2) as pledged_amount,
      coalesce(public.confirmed_pledge_allocated_amount(p.id), 0)::numeric(18,2) as paid_amount,
      greatest(coalesce(p.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount
    from public.event_members em
    join public.events e on e.id = em.event_id and e.tenant_id = p_tenant_id
    left join public.event_member_categories c on c.id = em.category_id
    left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED'
    where em.tenant_id = p_tenant_id
      and em.member_id = p_member_id
  ) row_data;

  return jsonb_build_object('contact', contact, 'events', events);
end;
$$;

grant execute on function public.rpc_create_contact(uuid, text, text, text, text, text, text, boolean) to authenticated;
grant execute on function public.rpc_list_contacts(uuid) to authenticated;
grant execute on function public.rpc_list_contacts_available_for_event(uuid, uuid) to authenticated;
grant execute on function public.rpc_get_contact_detail(uuid, uuid) to authenticated;
