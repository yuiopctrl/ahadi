-- 064_update_member_rpc_and_organization_activity
-- PATCH /api/v1/members/:memberId currently fails because the API already
-- calls public.rpc_update_member (see apps/api/src/app.ts) but that RPC was
-- never created in the database. Replace the old direct
-- `members` table UPDATE approach with an authoritative SECURITY DEFINER
-- RPC, and add server-side organization activity (audit_logs) listing so
-- tenant owners can see what changed.

-- ============================================================
-- PART 1: rpc_update_member
-- ============================================================

create or replace function public.rpc_update_member(
  p_tenant_id uuid,
  p_member_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  existing public.members%rowtype;
  updated public.members%rowtype;
  existing_json jsonb;
  updated_json jsonb;
  diff_keys text[] := array[
    'full_name', 'phone_e164', 'alternative_phone_e164', 'email',
    'location', 'notes', 'preferred_language', 'sms_enabled', 'status'
  ];
  k text;
  old_values jsonb := '{}'::jsonb;
  new_values jsonb := '{}'::jsonb;
  audit_action text := 'contact.updated';
begin
  if caller is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  perform public.ensure_tenant_write_access(p_tenant_id);

  if not public.has_tenant_permission(p_tenant_id, 'members.update') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into existing
  from public.members
  where id = p_member_id and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  if p_patch ? 'fullName' and btrim(coalesce(p_patch->>'fullName', '')) = '' then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  if p_patch ? 'preferredLanguage' and p_patch->>'preferredLanguage' not in ('sw', 'en') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  if p_patch ? 'status' and p_patch->>'status' not in ('ACTIVE', 'INACTIVE', 'ARCHIVED') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  begin
    update public.members set
      full_name = case when p_patch ? 'fullName' then p_patch->>'fullName' else full_name end,
      phone_e164 = case when p_patch ? 'phoneE164' then p_patch->>'phoneE164' else phone_e164 end,
      alternative_phone_e164 = case when p_patch ? 'alternativePhoneE164' then p_patch->>'alternativePhoneE164' else alternative_phone_e164 end,
      email = case when p_patch ? 'email' then p_patch->>'email' else email end,
      location = case when p_patch ? 'location' then p_patch->>'location' else location end,
      notes = case when p_patch ? 'notes' then p_patch->>'notes' else notes end,
      preferred_language = case when p_patch ? 'preferredLanguage' then p_patch->>'preferredLanguage' else preferred_language end,
      sms_enabled = case when p_patch ? 'smsEnabled' then (p_patch->>'smsEnabled')::boolean else sms_enabled end,
      status = case when p_patch ? 'status' then p_patch->>'status' else status end,
      archived_by = case
        when p_patch ? 'status' and p_patch->>'status' = 'ARCHIVED' then caller
        else archived_by
      end
    where id = p_member_id and tenant_id = p_tenant_id
    returning * into updated;
  exception
    when unique_violation then
      raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505';
  end;

  existing_json := to_jsonb(existing);
  updated_json := to_jsonb(updated);

  foreach k in array diff_keys loop
    if (existing_json -> k) is distinct from (updated_json -> k) then
      old_values := old_values || jsonb_build_object(k, existing_json -> k);
      new_values := new_values || jsonb_build_object(k, updated_json -> k);
    end if;
  end loop;

  if existing.status is distinct from updated.status then
    if existing.status <> 'ARCHIVED' and updated.status = 'ARCHIVED' then
      audit_action := 'contact.archived';
    elsif existing.status = 'ARCHIVED' and updated.status <> 'ARCHIVED' then
      audit_action := 'contact.reactivated';
    end if;
  end if;

  if old_values <> '{}'::jsonb then
    perform public.write_audit_log(p_tenant_id, audit_action, 'member', p_member_id, null, old_values, new_values, null);
  end if;

  return to_jsonb(updated);
end;
$$;

grant execute on function public.rpc_update_member(uuid, uuid, jsonb) to authenticated;
revoke all on function public.rpc_update_member(uuid, uuid, jsonb) from public;

-- ============================================================
-- PART 2: organization activity (audit_logs) listing
-- ============================================================
-- Tenant-facing activity uses the existing 'audit.view' permission (already
-- granted to TENANT_OWNER via the wildcard tenant-owner role_permissions
-- seed in 033_repair_core_rbac_seed_data.sql). No new permission is needed.

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
      al.id,
      al.created_at,
      al.action,
      al.entity_type,
      al.entity_id,
      al.event_id,
      ev.name as event_name,
      al.actor_user_id,
      pr.full_name as actor_name,
      al.old_values,
      al.new_values,
      al.reason
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

grant execute on function public.rpc_list_organization_activity(uuid, integer, integer, text, text, text, uuid, uuid, timestamptz, timestamptz) to authenticated;
revoke all on function public.rpc_list_organization_activity(uuid, integer, integer, text, text, text, uuid, uuid, timestamptz, timestamptz) from public;
