-- RSVP-2 identity hardening: Event Member Detail was resolving "does this
-- event member have an invitation?" by searching the paginated invitation
-- list by Contact/member full_name (client-side, apps/mobile). That is not
-- an acceptable identity lookup -- two Contacts can share a full_name,
-- names can change, invitation display_name can diverge from the Contact's
-- name entirely, the list is paginated, and a textual search can return
-- more than one candidate row. Worst case: Member Detail could show a
-- different person's invitation.
--
-- This is the smallest additive RPC to replace that: an exact lookup keyed
-- by (tenant_id, event_id, event_member_id) only, no name/text involved
-- anywhere in the query. RSVP-1's rpc_list_event_invitations has no
-- event_member_id filter parameter and is a paginated list RPC -- not an
-- appropriate shape for "look up exactly one row's invitation, or null".
-- event_invitation_detail_json (migration 072) already builds the full
-- detail payload, reused here as-is.

create or replace function public.rpc_get_event_member_invitation(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  found_invitation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.event_members em
    where em.id = p_event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id
  ) then
    raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  select ei.id into found_invitation_id
  from public.event_invitations ei
  where ei.tenant_id = p_tenant_id
    and ei.event_id = p_event_id
    and ei.event_member_id = p_event_member_id;

  if found_invitation_id is null then
    return null;
  end if;

  return public.event_invitation_detail_json(found_invitation_id);
end;
$$;

grant execute on function public.rpc_get_event_member_invitation(uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
