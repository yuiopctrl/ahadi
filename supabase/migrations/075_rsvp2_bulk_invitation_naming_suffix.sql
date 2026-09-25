-- RSVP-2: the bulk-create invitation UI offers a naming choice ("Use member
-- name" vs. "Member name & Family"), which must only change
-- event_invitations.display_name -- never public.members.full_name. The
-- single-create RPC already supports an explicit p_display_name override
-- the client can compute itself, but rpc_bulk_create_event_invitations
-- (migration 072) always used the Contact's bare full_name with no way to
-- apply a suffix across the whole batch, and bulk creation is explicitly
-- required to stay a single transactional call (no per-row HTTP loop from
-- Flutter). This is the smallest additive change: one new, optional,
-- trailing parameter.
--
-- Adding a parameter changes the function's signature, so `create or
-- replace function` on the same 5-argument list would not update the
-- existing function in place -- it would create a second, overloaded
-- 6-argument function alongside it, reintroducing the exact overload
-- ambiguity already found and fixed for rpc_list_contacts/
-- rpc_list_event_members (migration 071). The old 5-argument signature is
-- therefore dropped explicitly in this same migration before the new one
-- is created.

drop function if exists public.rpc_bulk_create_event_invitations(uuid, uuid, uuid[], integer, uuid);

create or replace function public.rpc_bulk_create_event_invitations(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_ids uuid[],
  p_default_max_guests integer default null,
  p_template_id uuid default null,
  p_display_name_suffix text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  requested integer := coalesce(array_length(p_event_member_ids, 1), 0);
  valid_count integer;
  settings_record public.event_invitation_settings%rowtype;
  resolved_max_guests integer;
  resolved_template_id uuid;
  clean_suffix text := nullif(btrim(coalesce(p_display_name_suffix, '')), '');
  created_ids uuid[];
  created_count integer;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events where id = p_event_id and tenant_id = p_tenant_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if requested = 0 then
    return jsonb_build_object('requested', 0, 'created', 0, 'alreadyExisted', 0, 'createdInvitationIds', '[]'::jsonb);
  end if;

  select count(distinct em.id) into valid_count
  from public.event_members em
  join unnest(p_event_member_ids) ids(id) on ids.id = em.id
  where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE';
  if valid_count <> requested then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select * into settings_record from public.event_invitation_settings where event_id = p_event_id and tenant_id = p_tenant_id;
  resolved_max_guests := coalesce(p_default_max_guests, settings_record.default_max_guests, 1);
  if resolved_max_guests < 1 then
    raise exception 'INVITATION_GUEST_LIMIT_INVALID' using errcode = '22023';
  end if;
  resolved_template_id := coalesce(p_template_id, settings_record.template_id);
  if resolved_template_id is not null then
    perform public.validate_invitation_template(p_tenant_id, resolved_template_id);
  end if;

  with inserted as (
    insert into public.event_invitations (tenant_id, event_id, event_member_id, template_id, display_name, max_guests, status, created_by)
    select
      p_tenant_id, p_event_id, em.id, resolved_template_id,
      case when clean_suffix is not null then m.full_name || ' ' || clean_suffix else m.full_name end,
      resolved_max_guests, 'DRAFT', caller
    from unnest(p_event_member_ids) ids(id)
    join public.event_members em on em.id = ids.id
    join public.members m on m.id = em.member_id
    where em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE'
    on conflict (event_id, event_member_id) do nothing
    returning id, event_member_id
  )
  select array_agg(id), count(*) into created_ids, created_count from inserted;

  created_ids := coalesce(created_ids, '{}'::uuid[]);
  created_count := coalesce(created_count, 0);

  if created_count > 0 then
    perform public.write_audit_log(p_tenant_id, 'invitation.created', 'event_invitation', unnest_id, p_event_id, null,
      jsonb_build_object('bulk', true))
    from unnest(created_ids) as unnest_id;
  end if;

  return jsonb_build_object(
    'requested', requested,
    'created', created_count,
    'alreadyExisted', requested - created_count,
    'createdInvitationIds', to_jsonb(created_ids)
  );
end;
$$;

grant execute on function public.rpc_bulk_create_event_invitations(uuid, uuid, uuid[], integer, uuid, text) to authenticated;

notify pgrst, 'reload schema';
