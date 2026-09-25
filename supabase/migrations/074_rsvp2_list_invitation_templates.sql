-- RSVP-2: the only backend gap found while building the invitation
-- management UI. RSVP-1 (migration 072) lets an invitation reference a
-- template and seeds one PLATFORM template, but never exposed a read
-- endpoint for the authenticated organizer UI to discover which active
-- templates exist to offer as a picker (in bulk-create, single-create, and
-- invitation settings). This is the smallest additive change that fills
-- that gap -- one new read-only RPC, no changes to any RSVP-1 table,
-- constraint, RLS policy, or existing RPC signature/response shape.

create or replace function public.rpc_list_invitation_templates(p_tenant_id uuid)
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
  if not public.has_tenant_permission(p_tenant_id, 'invitation.view') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'name', t.name,
      'layoutKey', t.layout_key,
      'scope', t.scope,
      'category', t.category
    ) order by t.scope, t.name)
    from public.invitation_templates t
    where t.is_active
      and (t.scope = 'PLATFORM' or (t.scope = 'TENANT' and t.tenant_id = p_tenant_id))
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.rpc_list_invitation_templates(uuid) to authenticated;

notify pgrst, 'reload schema';
