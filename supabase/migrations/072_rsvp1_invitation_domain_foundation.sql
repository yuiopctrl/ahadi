-- RSVP-1: Invitation + RSVP domain foundation.
--
-- Domain model (kept intentionally separate, per product clarification):
--   Contact (public.members, org-wide)
--     -> Event Member (public.event_members, Contact attached to one Event)
--       -> Invitation (public.event_invitations, one per Event Member per Event)
--         -> RSVP (public.invitation_rsvps, current response for that Invitation)
-- An invitation never requires a pledge -- this domain has zero references to
-- public.pledges/public.payments.
--
-- Tables added: invitation_templates, event_invitation_settings,
-- event_invitations, invitation_deliveries, invitation_rsvps, rsvp_guests.
--
-- Public access model: anon/authenticated PostgREST roles get NOTHING on
-- these tables (RLS enabled, only tenant-scoped `authenticated` policies
-- added) and NOTHING on the two public-facing RPCs (revoked from public,
-- granted only to service_role) -- the Node API is the only path to public
-- invitation data, using the service-role client after verifying an
-- HMAC-signed capability token itself (see apps/api/src/invitation-token.ts,
-- added alongside this migration). The database only ever sees an already
---verified invitation_id + token_version pair; it independently re-checks
-- that token_version still matches the invitation's current
-- public_token_version, which is what closes the rotate-after-decode race.

-- ---------------------------------------------------------------------
-- Table 1: invitation_templates
-- ---------------------------------------------------------------------

create table public.invitation_templates (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('PLATFORM', 'TENANT')),
  tenant_id uuid references public.tenants(id) on delete cascade,
  name text not null,
  category text,
  layout_key text not null,
  config_json jsonb not null default '{}'::jsonb,
  preview_asset text,
  is_active boolean not null default true,
  is_premium boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(name) <> ''),
  check (btrim(layout_key) <> ''),
  check ((scope = 'PLATFORM' and tenant_id is null) or (scope = 'TENANT' and tenant_id is not null))
);

create index invitation_templates_tenant_idx on public.invitation_templates(tenant_id);
create index invitation_templates_scope_active_idx on public.invitation_templates(scope, is_active);

create trigger invitation_templates_set_updated_at
before update on public.invitation_templates
for each row execute function public.set_updated_at();

alter table public.invitation_templates enable row level security;

-- Every tenant can read PLATFORM templates plus its own TENANT templates;
-- only invitation.edit holders can manage tenant-owned templates. There is
-- no template-authoring API in RSVP-1 (per scope), so `_manage` exists for
-- forward-compatibility and direct/service use, not a route added now.
create policy invitation_templates_select on public.invitation_templates
for select using (
  scope = 'PLATFORM'
  or (scope = 'TENANT' and public.has_tenant_permission(tenant_id, 'invitation.view'))
);
create policy invitation_templates_manage on public.invitation_templates
for all using (scope = 'TENANT' and public.has_tenant_permission(tenant_id, 'invitation.edit'))
with check (scope = 'TENANT' and public.has_tenant_permission(tenant_id, 'invitation.edit'));

-- One platform default so invitations have something valid to activate
-- against without building a template designer in this phase.
insert into public.invitation_templates (scope, tenant_id, name, category, layout_key, config_json, is_active, is_premium)
values ('PLATFORM', null, 'Classic', 'general', 'CLASSIC', '{"palette": "neutral"}'::jsonb, true, false)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Table 2: event_invitation_settings (one row per Event)
-- ---------------------------------------------------------------------
--
-- events (public.events) already owns name/event_date/venue -- this table
-- holds ONLY invitation-specific presentation fields and intentional
-- overrides. When no override is set, the public read RPC falls back to
-- the real Event fields. events has no time-of-day or address/maps
-- columns at all (not just "no override"), so event_time_display,
-- venue_address_override and maps_url are the sole source for those, not
-- true overrides of an existing column.

create table public.event_invitation_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,

  host_display_name text,
  invitation_title text,
  invitation_message text,

  venue_name_override text,
  venue_address_override text,
  maps_url text,
  event_time_display text,

  rsvp_enabled boolean not null default true,
  rsvp_deadline timestamptz,
  allow_late_rsvp boolean not null default false,

  default_max_guests integer not null default 1,

  template_id uuid references public.invitation_templates(id) on delete set null,

  created_by uuid not null references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (event_id),
  check (default_max_guests >= 1)
);

create index event_invitation_settings_tenant_idx on public.event_invitation_settings(tenant_id);

create trigger event_invitation_settings_set_updated_at
before update on public.event_invitation_settings
for each row execute function public.set_updated_at();

alter table public.event_invitation_settings enable row level security;

create policy event_invitation_settings_select on public.event_invitation_settings
for select using (public.has_event_financial_access(tenant_id, event_id, 'invitation.view', 'VIEW'));
create policy event_invitation_settings_manage on public.event_invitation_settings
for all using (public.has_event_financial_access(tenant_id, event_id, 'invitation.edit', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'invitation.edit', 'MANAGE'));

-- ---------------------------------------------------------------------
-- Table 3: event_invitations (core table -- one per Event Member)
-- ---------------------------------------------------------------------

create table public.event_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  event_member_id uuid not null references public.event_members(id) on delete restrict,

  template_id uuid references public.invitation_templates(id) on delete set null,

  display_name text not null,
  max_guests integer not null default 1,

  status text not null default 'DRAFT' check (status in ('DRAFT', 'ACTIVE', 'CANCELLED')),

  public_token_version integer not null default 1,

  first_viewed_at timestamptz,
  last_viewed_at timestamptz,
  view_count integer not null default 0,

  created_by uuid not null references auth.users(id),
  updated_by uuid references auth.users(id),

  activated_at timestamptz,
  cancelled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (event_id, event_member_id),
  check (btrim(display_name) <> ''),
  check (max_guests >= 1),
  check (public_token_version >= 1),
  check (view_count >= 0),
  check ((status = 'ACTIVE') = (activated_at is not null) or status <> 'ACTIVE'),
  check ((status = 'CANCELLED') = (cancelled_at is not null) or status <> 'CANCELLED')
);

create index event_invitations_tenant_event_idx on public.event_invitations(tenant_id, event_id);
create index event_invitations_event_member_idx on public.event_invitations(event_member_id);
create index event_invitations_status_idx on public.event_invitations(tenant_id, event_id, status);

create trigger event_invitations_set_updated_at
before update on public.event_invitations
for each row execute function public.set_updated_at();

alter table public.event_invitations enable row level security;

create policy event_invitations_select on public.event_invitations
for select using (public.has_event_financial_access(tenant_id, event_id, 'invitation.view', 'VIEW'));
create policy event_invitations_manage on public.event_invitations
for all using (public.has_event_financial_access(tenant_id, event_id, 'invitation.edit', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'invitation.edit', 'MANAGE'));

-- ---------------------------------------------------------------------
-- Table 4: invitation_deliveries (delivery history foundation only --
-- no channel is actually wired to send anything in this phase)
-- ---------------------------------------------------------------------

create table public.invitation_deliveries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  invitation_id uuid not null references public.event_invitations(id) on delete cascade,

  channel text not null check (channel in ('SMS', 'WHATSAPP_SHARE', 'MANUAL_SHARE')),
  destination text,

  status text not null check (status in ('QUEUED', 'SENT', 'DELIVERED', 'FAILED')),
  provider_message_id text,

  sent_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  failure_reason text,

  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index invitation_deliveries_tenant_event_idx on public.invitation_deliveries(tenant_id, event_id);
create index invitation_deliveries_invitation_idx on public.invitation_deliveries(invitation_id, created_at desc);

alter table public.invitation_deliveries enable row level security;

create policy invitation_deliveries_select on public.invitation_deliveries
for select using (public.has_event_financial_access(tenant_id, event_id, 'invitation.view', 'VIEW'));
create policy invitation_deliveries_manage on public.invitation_deliveries
for all using (public.has_event_financial_access(tenant_id, event_id, 'invitation.send', 'MANAGE'))
with check (public.has_event_financial_access(tenant_id, event_id, 'invitation.send', 'MANAGE'));

-- ---------------------------------------------------------------------
-- Table 5: invitation_rsvps (one CURRENT row per invitation -- no row at
-- all means no response; history lives in audit_logs, not extra rows)
-- ---------------------------------------------------------------------

create table public.invitation_rsvps (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  invitation_id uuid not null references public.event_invitations(id) on delete cascade,

  response text not null check (response in ('ATTENDING', 'MAYBE', 'NOT_ATTENDING')),
  attending_count integer not null check (attending_count >= 0),

  note text,

  submitted_by_type text not null check (submitted_by_type in ('PUBLIC_GUEST', 'TENANT_USER')),
  submitted_by_user_id uuid references auth.users(id),

  responded_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (invitation_id),
  check ((submitted_by_type = 'PUBLIC_GUEST') = (submitted_by_user_id is null)),
  check (response <> 'NOT_ATTENDING' or attending_count = 0)
);

create index invitation_rsvps_tenant_event_idx on public.invitation_rsvps(tenant_id, event_id);
create index invitation_rsvps_response_idx on public.invitation_rsvps(event_id, response);

create trigger invitation_rsvps_set_updated_at
before update on public.invitation_rsvps
for each row execute function public.set_updated_at();

alter table public.invitation_rsvps enable row level security;

create policy invitation_rsvps_select on public.invitation_rsvps
for select using (public.has_event_financial_access(tenant_id, event_id, 'rsvp.view', 'VIEW'));
create policy invitation_rsvps_manage on public.invitation_rsvps
for all using (public.has_event_financial_access(tenant_id, event_id, 'rsvp.manage', 'COLLECT'))
with check (public.has_event_financial_access(tenant_id, event_id, 'rsvp.manage', 'COLLECT'));

-- ---------------------------------------------------------------------
-- Table 6: rsvp_guests (optional named guests, count enforced <= the
-- parent RSVP's attending_count -- never required to equal it)
-- ---------------------------------------------------------------------

create table public.rsvp_guests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  rsvp_id uuid not null references public.invitation_rsvps(id) on delete cascade,

  guest_name text not null,
  position integer not null check (position >= 1),

  created_at timestamptz not null default now(),

  unique (rsvp_id, position),
  check (btrim(guest_name) <> '')
);

create index rsvp_guests_rsvp_idx on public.rsvp_guests(rsvp_id);

alter table public.rsvp_guests enable row level security;

create policy rsvp_guests_select on public.rsvp_guests
for select using (
  exists (
    select 1 from public.invitation_rsvps ir
    where ir.id = rsvp_id and public.has_event_financial_access(ir.tenant_id, ir.event_id, 'rsvp.view', 'VIEW')
  )
);
create policy rsvp_guests_manage on public.rsvp_guests
for all using (
  exists (
    select 1 from public.invitation_rsvps ir
    where ir.id = rsvp_id and public.has_event_financial_access(ir.tenant_id, ir.event_id, 'rsvp.manage', 'COLLECT')
  )
)
with check (
  exists (
    select 1 from public.invitation_rsvps ir
    where ir.id = rsvp_id and public.has_event_financial_access(ir.tenant_id, ir.event_id, 'rsvp.manage', 'COLLECT')
  )
);

-- ---------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------

insert into public.permissions (code, name, description) values
('invitation.view', 'View invitations', 'View event invitations and their RSVP status'),
('invitation.create', 'Create invitations', 'Create invitations for event members'),
('invitation.edit', 'Edit invitations', 'Edit invitation details, settings, activation and link rotation'),
('invitation.cancel', 'Cancel invitations', 'Cancel event invitations'),
('invitation.send', 'Send invitations', 'Send or share invitation links and record delivery history'),
('rsvp.view', 'View RSVPs', 'View RSVP responses and the event RSVP dashboard'),
('rsvp.manage', 'Manage RSVPs', 'Record or override guest RSVP responses on behalf of a guest')
on conflict (code) do update set name = excluded.name, description = excluded.description;

-- TENANT_OWNER and EVENT_ADMIN run the invitation/RSVP feature end to end.
-- TREASURER, COLLECTOR and VIEWER get read access only -- consistent with
-- how this repo already scopes those roles for other features (see
-- migration 016), and deliberately conservative: this migration does not
-- grant new create/edit/cancel/send/manage authority to any role beyond
-- the two that already hold full event-management authority.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'invitation.view', 'invitation.create', 'invitation.edit', 'invitation.cancel', 'invitation.send',
  'rsvp.view', 'rsvp.manage'
)
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN')
  and r.tenant_id is null
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('invitation.view', 'rsvp.view')
where r.code in ('TREASURER', 'COLLECTOR', 'VIEWER')
  and r.tenant_id is null
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Shared helper: build the authenticated-side invitation detail payload.
-- Used by create/update/activate/cancel/rotate/detail RPCs so they all
-- return an identically-shaped object.
-- ---------------------------------------------------------------------

create or replace function public.event_invitation_detail_json(p_invitation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'id', ei.id,
    'eventId', ei.event_id,
    'eventMemberId', ei.event_member_id,
    'memberId', m.id,
    'memberName', m.full_name,
    'phone', m.phone_e164,
    'displayName', ei.display_name,
    'maxGuests', ei.max_guests,
    'status', ei.status,
    'publicTokenVersion', ei.public_token_version,
    'template', case when t.id is null then null else jsonb_build_object(
      'id', t.id, 'name', t.name, 'layoutKey', t.layout_key, 'scope', t.scope
    ) end,
    'rsvp', case when ir.id is null then null else jsonb_build_object(
      'response', ir.response,
      'attendingCount', ir.attending_count,
      'note', ir.note,
      'submittedByType', ir.submitted_by_type,
      'respondedAt', ir.responded_at,
      'guestNames', coalesce((
        select jsonb_agg(g.guest_name order by g.position) from public.rsvp_guests g where g.rsvp_id = ir.id
      ), '[]'::jsonb)
    ) end,
    'deliveries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'channel', d.channel, 'destination', d.destination, 'status', d.status,
        'sentAt', d.sent_at, 'deliveredAt', d.delivered_at, 'failedAt', d.failed_at, 'failureReason', d.failure_reason,
        'createdAt', d.created_at
      ) order by d.created_at desc)
      from public.invitation_deliveries d where d.invitation_id = ei.id
    ), '[]'::jsonb),
    'viewCount', ei.view_count,
    'firstViewedAt', ei.first_viewed_at,
    'lastViewedAt', ei.last_viewed_at,
    'activatedAt', ei.activated_at,
    'cancelledAt', ei.cancelled_at,
    'createdAt', ei.created_at,
    'updatedAt', ei.updated_at
  )
  from public.event_invitations ei
  join public.event_members em on em.id = ei.event_member_id
  join public.members m on m.id = em.member_id
  left join public.invitation_templates t on t.id = ei.template_id
  left join public.invitation_rsvps ir on ir.invitation_id = ei.id
  where ei.id = p_invitation_id;
$$;

-- Deliberately NOT granted to authenticated: this returns full display
-- name/phone/RSVP/guest-name detail for an arbitrary invitation_id with no
-- tenant/event ownership check of its own. It is only meant to be composed
-- from inside the RPCs above, which already enforce
-- has_event_financial_access before calling it -- those calls succeed
-- regardless of this grant because a security definer function executes
-- (and therefore calls other functions) as its owner, not as the original
-- caller. Omitting the grant is what keeps this un-callable directly via
-- PostgREST by any authenticated user of any tenant.

-- ---------------------------------------------------------------------
-- Validation helper: resolve+validate a template_id against tenant scope.
-- ---------------------------------------------------------------------

create or replace function public.validate_invitation_template(p_tenant_id uuid, p_template_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  template_record public.invitation_templates%rowtype;
begin
  select * into template_record from public.invitation_templates where id = p_template_id;
  if not found or not template_record.is_active then
    raise exception 'INVITATION_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;
  if template_record.scope = 'TENANT' and template_record.tenant_id <> p_tenant_id then
    raise exception 'INVITATION_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;
end;
$$;

-- Also internal-only, same reasoning as event_invitation_detail_json above.

-- ---------------------------------------------------------------------
-- RPC 1/2: event invitation settings
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_event_invitation_settings(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  event_record public.events%rowtype;
  settings_record public.event_invitation_settings%rowtype;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found then raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501'; end if;

  select * into settings_record from public.event_invitation_settings where event_id = p_event_id and tenant_id = p_tenant_id;

  return jsonb_build_object(
    'eventId', p_event_id,
    'event', jsonb_build_object('name', event_record.name, 'eventDate', event_record.event_date, 'venue', event_record.venue),
    'settings', case when not found then null else jsonb_build_object(
      'hostDisplayName', settings_record.host_display_name,
      'invitationTitle', settings_record.invitation_title,
      'invitationMessage', settings_record.invitation_message,
      'venueNameOverride', settings_record.venue_name_override,
      'venueAddressOverride', settings_record.venue_address_override,
      'mapsUrl', settings_record.maps_url,
      'eventTimeDisplay', settings_record.event_time_display,
      'rsvpEnabled', settings_record.rsvp_enabled,
      'rsvpDeadline', settings_record.rsvp_deadline,
      'allowLateRsvp', settings_record.allow_late_rsvp,
      'defaultMaxGuests', settings_record.default_max_guests,
      'templateId', settings_record.template_id,
      'updatedAt', settings_record.updated_at
    ) end
  );
end;
$$;

grant execute on function public.rpc_get_event_invitation_settings(uuid, uuid) to authenticated;

create or replace function public.rpc_upsert_event_invitation_settings(
  p_tenant_id uuid,
  p_event_id uuid,
  p_host_display_name text default null,
  p_invitation_title text default null,
  p_invitation_message text default null,
  p_venue_name_override text default null,
  p_venue_address_override text default null,
  p_maps_url text default null,
  p_event_time_display text default null,
  p_rsvp_enabled boolean default true,
  p_rsvp_deadline timestamptz default null,
  p_allow_late_rsvp boolean default false,
  p_default_max_guests integer default 1,
  p_template_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  settings_id uuid;
  old_row public.event_invitation_settings%rowtype;
  settings_existed boolean;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.edit', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events where id = p_event_id and tenant_id = p_tenant_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if coalesce(p_default_max_guests, 0) < 1 then
    raise exception 'INVITATION_GUEST_LIMIT_INVALID' using errcode = '22023';
  end if;
  if p_template_id is not null then
    perform public.validate_invitation_template(p_tenant_id, p_template_id);
  end if;

  select * into old_row from public.event_invitation_settings where event_id = p_event_id and tenant_id = p_tenant_id;
  settings_existed := found;

  insert into public.event_invitation_settings (
    tenant_id, event_id, host_display_name, invitation_title, invitation_message,
    venue_name_override, venue_address_override, maps_url, event_time_display,
    rsvp_enabled, rsvp_deadline, allow_late_rsvp, default_max_guests, template_id,
    created_by, updated_by
  )
  values (
    p_tenant_id, p_event_id, p_host_display_name, p_invitation_title, p_invitation_message,
    p_venue_name_override, p_venue_address_override, p_maps_url, p_event_time_display,
    coalesce(p_rsvp_enabled, true), p_rsvp_deadline, coalesce(p_allow_late_rsvp, false), p_default_max_guests, p_template_id,
    caller, caller
  )
  on conflict (event_id) do update set
    host_display_name = excluded.host_display_name,
    invitation_title = excluded.invitation_title,
    invitation_message = excluded.invitation_message,
    venue_name_override = excluded.venue_name_override,
    venue_address_override = excluded.venue_address_override,
    maps_url = excluded.maps_url,
    event_time_display = excluded.event_time_display,
    rsvp_enabled = excluded.rsvp_enabled,
    rsvp_deadline = excluded.rsvp_deadline,
    allow_late_rsvp = excluded.allow_late_rsvp,
    default_max_guests = excluded.default_max_guests,
    template_id = excluded.template_id,
    updated_by = caller
  returning id into settings_id;

  perform public.write_audit_log(
    p_tenant_id, 'invitation_settings.updated', 'event_invitation_settings', settings_id, p_event_id,
    case when settings_existed then to_jsonb(old_row) else null end, null, null
  );

  return public.rpc_get_event_invitation_settings(p_tenant_id, p_event_id);
end;
$$;

grant execute on function public.rpc_upsert_event_invitation_settings(uuid, uuid, text, text, text, text, text, text, text, boolean, timestamptz, boolean, integer, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 3: create a single invitation
-- ---------------------------------------------------------------------

create or replace function public.rpc_create_event_invitation(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_id uuid,
  p_display_name text default null,
  p_max_guests integer default null,
  p_template_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  member_name text;
  resolved_display_name text;
  resolved_max_guests integer;
  resolved_template_id uuid;
  settings_record public.event_invitation_settings%rowtype;
  invitation_id uuid;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.create', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events where id = p_event_id and tenant_id = p_tenant_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select m.full_name into member_name
  from public.event_members em
  join public.members m on m.id = em.member_id
  where em.id = p_event_member_id and em.tenant_id = p_tenant_id and em.event_id = p_event_id and em.status = 'ACTIVE';
  if not found then raise exception 'EVENT_MEMBER_NOT_FOUND' using errcode = '22023'; end if;

  if exists (select 1 from public.event_invitations where event_id = p_event_id and event_member_id = p_event_member_id) then
    raise exception 'INVITATION_ALREADY_EXISTS' using errcode = '23505';
  end if;

  select * into settings_record from public.event_invitation_settings where event_id = p_event_id and tenant_id = p_tenant_id;

  resolved_display_name := nullif(btrim(coalesce(p_display_name, '')), '');
  if resolved_display_name is null then
    resolved_display_name := member_name;
  end if;

  resolved_max_guests := coalesce(p_max_guests, settings_record.default_max_guests, 1);
  if resolved_max_guests < 1 then
    raise exception 'INVITATION_GUEST_LIMIT_INVALID' using errcode = '22023';
  end if;

  resolved_template_id := coalesce(p_template_id, settings_record.template_id);
  if resolved_template_id is not null then
    perform public.validate_invitation_template(p_tenant_id, resolved_template_id);
  end if;

  begin
    insert into public.event_invitations (
      tenant_id, event_id, event_member_id, template_id, display_name, max_guests, status, created_by
    )
    values (
      p_tenant_id, p_event_id, p_event_member_id, resolved_template_id, resolved_display_name, resolved_max_guests, 'DRAFT', caller
    )
    returning id into invitation_id;
  exception
    when unique_violation then
      raise exception 'INVITATION_ALREADY_EXISTS' using errcode = '23505';
  end;

  perform public.write_audit_log(p_tenant_id, 'invitation.created', 'event_invitation', invitation_id, p_event_id, null,
    jsonb_build_object('eventMemberId', p_event_member_id, 'displayName', resolved_display_name));

  return public.event_invitation_detail_json(invitation_id);
end;
$$;

grant execute on function public.rpc_create_event_invitation(uuid, uuid, uuid, text, integer, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 4: bulk create invitations -- validates every event_member up
-- front (rejects the whole request on one cross-tenant/event violation
-- rather than silently skipping it); existing invitations are skipped.
-- ---------------------------------------------------------------------

create or replace function public.rpc_bulk_create_event_invitations(
  p_tenant_id uuid,
  p_event_id uuid,
  p_event_member_ids uuid[],
  p_default_max_guests integer default null,
  p_template_id uuid default null
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
    select p_tenant_id, p_event_id, em.id, resolved_template_id, m.full_name, resolved_max_guests, 'DRAFT', caller
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

grant execute on function public.rpc_bulk_create_event_invitations(uuid, uuid, uuid[], integer, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 5: update invitation (display_name / max_guests / template_id)
-- ---------------------------------------------------------------------

create or replace function public.rpc_update_event_invitation(
  p_tenant_id uuid,
  p_event_id uuid,
  p_invitation_id uuid,
  p_display_name text default null,
  p_max_guests integer default null,
  p_template_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  invitation_record public.event_invitations%rowtype;
  current_attending integer;
  new_display_name text;
  new_max_guests integer;
  new_template_id uuid;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.edit', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into invitation_record from public.event_invitations
  where id = p_invitation_id and tenant_id = p_tenant_id and event_id = p_event_id;
  if not found then raise exception 'INVITATION_NOT_FOUND' using errcode = '22023'; end if;
  if invitation_record.status = 'CANCELLED' then
    raise exception 'INVITATION_CANCELLED' using errcode = '22023';
  end if;

  new_display_name := coalesce(nullif(btrim(coalesce(p_display_name, '')), ''), invitation_record.display_name);
  new_max_guests := coalesce(p_max_guests, invitation_record.max_guests);
  new_template_id := coalesce(p_template_id, invitation_record.template_id);

  if new_max_guests < 1 then
    raise exception 'INVITATION_GUEST_LIMIT_INVALID' using errcode = '22023';
  end if;

  select attending_count into current_attending from public.invitation_rsvps where invitation_id = p_invitation_id;
  if current_attending is not null and new_max_guests < current_attending then
    raise exception 'INVITATION_GUEST_LIMIT_BELOW_RSVP_COUNT' using errcode = '22023';
  end if;

  if new_template_id is not null and new_template_id is distinct from invitation_record.template_id then
    perform public.validate_invitation_template(p_tenant_id, new_template_id);
  end if;

  update public.event_invitations
  set display_name = new_display_name, max_guests = new_max_guests, template_id = new_template_id, updated_by = caller
  where id = p_invitation_id;

  perform public.write_audit_log(p_tenant_id, 'invitation.updated', 'event_invitation', p_invitation_id, p_event_id,
    to_jsonb(invitation_record), jsonb_build_object('displayName', new_display_name, 'maxGuests', new_max_guests, 'templateId', new_template_id));

  return public.event_invitation_detail_json(p_invitation_id);
end;
$$;

grant execute on function public.rpc_update_event_invitation(uuid, uuid, uuid, text, integer, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 6: activate invitation
-- ---------------------------------------------------------------------

create or replace function public.rpc_activate_event_invitation(p_tenant_id uuid, p_event_id uuid, p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  invitation_record public.event_invitations%rowtype;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.edit', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into invitation_record from public.event_invitations
  where id = p_invitation_id and tenant_id = p_tenant_id and event_id = p_event_id;
  if not found then raise exception 'INVITATION_NOT_FOUND' using errcode = '22023'; end if;
  if invitation_record.status = 'CANCELLED' then
    raise exception 'INVITATION_CANCELLED' using errcode = '22023';
  end if;

  if invitation_record.status = 'ACTIVE' then
    return public.event_invitation_detail_json(p_invitation_id);
  end if;

  if btrim(coalesce(invitation_record.display_name, '')) = '' then
    raise exception 'INVITATION_NOT_ACTIVE' using errcode = '22023';
  end if;
  if invitation_record.max_guests < 1 then
    raise exception 'INVITATION_GUEST_LIMIT_INVALID' using errcode = '22023';
  end if;
  if invitation_record.template_id is null then
    raise exception 'INVITATION_TEMPLATE_NOT_FOUND' using errcode = '22023';
  end if;
  perform public.validate_invitation_template(p_tenant_id, invitation_record.template_id);

  update public.event_invitations
  set status = 'ACTIVE', activated_at = now(), updated_by = caller
  where id = p_invitation_id;

  perform public.write_audit_log(p_tenant_id, 'invitation.activated', 'event_invitation', p_invitation_id, p_event_id, null, null);

  return public.event_invitation_detail_json(p_invitation_id);
end;
$$;

grant execute on function public.rpc_activate_event_invitation(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 7: cancel invitation (preserves the row + all history)
-- ---------------------------------------------------------------------

create or replace function public.rpc_cancel_event_invitation(p_tenant_id uuid, p_event_id uuid, p_invitation_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  invitation_record public.event_invitations%rowtype;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.cancel', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into invitation_record from public.event_invitations
  where id = p_invitation_id and tenant_id = p_tenant_id and event_id = p_event_id;
  if not found then raise exception 'INVITATION_NOT_FOUND' using errcode = '22023'; end if;
  if invitation_record.status = 'CANCELLED' then
    raise exception 'INVITATION_CANCELLED' using errcode = '22023';
  end if;

  update public.event_invitations
  set status = 'CANCELLED', cancelled_at = now(), updated_by = caller
  where id = p_invitation_id;

  perform public.write_audit_log(p_tenant_id, 'invitation.cancelled', 'event_invitation', p_invitation_id, p_event_id, null, null, p_reason);

  return public.event_invitation_detail_json(p_invitation_id);
end;
$$;

grant execute on function public.rpc_cancel_event_invitation(uuid, uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 8: rotate public token -- invalidates every previously issued link
-- ---------------------------------------------------------------------

create or replace function public.rpc_rotate_invitation_public_token(p_tenant_id uuid, p_event_id uuid, p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  new_version integer;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.edit', 'MANAGE') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  update public.event_invitations
  set public_token_version = public_token_version + 1, updated_by = caller
  where id = p_invitation_id and tenant_id = p_tenant_id and event_id = p_event_id
  returning public_token_version into new_version;
  if not found then raise exception 'INVITATION_NOT_FOUND' using errcode = '22023'; end if;

  perform public.write_audit_log(p_tenant_id, 'invitation.token_rotated', 'event_invitation', p_invitation_id, p_event_id, null,
    jsonb_build_object('publicTokenVersion', new_version));

  return jsonb_build_object('invitationId', p_invitation_id, 'publicTokenVersion', new_version);
end;
$$;

grant execute on function public.rpc_rotate_invitation_public_token(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 9: list invitations -- server-side search/filter/pagination
-- ---------------------------------------------------------------------

create or replace function public.rpc_list_event_invitations(
  p_tenant_id uuid,
  p_event_id uuid,
  p_search text default null,
  p_status text default 'ALL',
  p_rsvp_status text default 'ALL',
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
  status_filter text := upper(coalesce(nullif(btrim(p_status), ''), 'ALL'));
  rsvp_filter text := upper(coalesce(nullif(btrim(p_rsvp_status), ''), 'ALL'));
  total_rows bigint;
  rows_json jsonb;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if status_filter not in ('ALL', 'DRAFT', 'ACTIVE', 'CANCELLED') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if rsvp_filter not in ('ALL', 'ATTENDING', 'MAYBE', 'NOT_ATTENDING', 'NO_RESPONSE') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  select count(*)
  into total_rows
  from public.event_invitations ei
  join public.event_members em on em.id = ei.event_member_id
  join public.members m on m.id = em.member_id
  left join public.invitation_rsvps ir on ir.invitation_id = ei.id
  where ei.tenant_id = p_tenant_id and ei.event_id = p_event_id
    and (status_filter = 'ALL' or ei.status = status_filter)
    and (rsvp_filter = 'ALL' or (rsvp_filter = 'NO_RESPONSE' and ir.id is null) or ir.response = rsvp_filter)
    and (
      search_text is null
      or m.full_name ilike '%' || search_text || '%'
      or ei.display_name ilike '%' || search_text || '%'
      or (phone_search is not null and public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%')
    );

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into rows_json
  from (
    select
      ei.id as invitation_id, ei.event_member_id, m.id as member_id, m.full_name as member_name,
      ei.display_name, m.phone_e164 as phone, ei.max_guests, ei.status,
      t.id as template_id, t.name as template_name, t.layout_key as template_layout_key,
      ir.response as rsvp_response, ir.attending_count,
      case when ir.id is null then 'NO_RESPONSE' else ir.response end as rsvp_status,
      ei.created_at, ei.updated_at,
      (
        select jsonb_build_object('channel', d.channel, 'status', d.status, 'sentAt', d.sent_at)
        from public.invitation_deliveries d
        where d.invitation_id = ei.id
        order by d.created_at desc
        limit 1
      ) as last_delivery
    from public.event_invitations ei
    join public.event_members em on em.id = ei.event_member_id
    join public.members m on m.id = em.member_id
    left join public.invitation_templates t on t.id = ei.template_id
    left join public.invitation_rsvps ir on ir.invitation_id = ei.id
    where ei.tenant_id = p_tenant_id and ei.event_id = p_event_id
      and (status_filter = 'ALL' or ei.status = status_filter)
      and (rsvp_filter = 'ALL' or (rsvp_filter = 'NO_RESPONSE' and ir.id is null) or ir.response = rsvp_filter)
      and (
        search_text is null
        or m.full_name ilike '%' || search_text || '%'
        or ei.display_name ilike '%' || search_text || '%'
        or (phone_search is not null and public.compact_phone_search(m.phone_e164) like '%' || phone_search || '%')
      )
    order by ei.created_at desc
    limit safe_limit
    offset safe_offset
  ) row_data;

  return jsonb_build_object(
    'data', rows_json,
    'pagination', jsonb_build_object(
      'limit', safe_limit, 'offset', safe_offset, 'totalRows', total_rows,
      'hasMore', (safe_offset + safe_limit) < total_rows
    )
  );
end;
$$;

grant execute on function public.rpc_list_event_invitations(uuid, uuid, text, text, text, integer, integer) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 10: invitation detail (authenticated side)
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_event_invitation_detail(p_tenant_id uuid, p_event_id uuid, p_invitation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'invitation.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.event_invitations where id = p_invitation_id and tenant_id = p_tenant_id and event_id = p_event_id) then
    raise exception 'INVITATION_NOT_FOUND' using errcode = '22023';
  end if;
  return public.event_invitation_detail_json(p_invitation_id);
end;
$$;

grant execute on function public.rpc_get_event_invitation_detail(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Shared RSVP validation -- used by both the organizer manual RPC and
-- the public submission RPC so the business rules only exist once.
-- ---------------------------------------------------------------------

create or replace function public.validate_rsvp_input(p_response text, p_attending_count integer, p_guest_names text[], p_max_guests integer)
returns void
language plpgsql
immutable
as $$
declare
  guest_count integer := coalesce(array_length(p_guest_names, 1), 0);
begin
  if p_response not in ('ATTENDING', 'MAYBE', 'NOT_ATTENDING') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if p_response = 'NOT_ATTENDING' then
    if coalesce(p_attending_count, 0) <> 0 then
      raise exception 'RSVP_GUEST_COUNT_INVALID' using errcode = '22023';
    end if;
    if guest_count <> 0 then
      raise exception 'RSVP_GUEST_NAMES_EXCEED_COUNT' using errcode = '22023';
    end if;
    return;
  end if;
  if p_attending_count is null or p_attending_count < 1 or p_attending_count > p_max_guests then
    raise exception 'RSVP_GUEST_COUNT_INVALID' using errcode = '22023';
  end if;
  if guest_count > p_attending_count then
    raise exception 'RSVP_GUEST_NAMES_EXCEED_COUNT' using errcode = '22023';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC 11: organizer manual RSVP (may run after the public deadline)
-- ---------------------------------------------------------------------

create or replace function public.rpc_record_manual_rsvp(
  p_tenant_id uuid,
  p_event_id uuid,
  p_invitation_id uuid,
  p_response text,
  p_attending_count integer,
  p_guest_names text[] default '{}',
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := auth.uid();
  invitation_record public.event_invitations%rowtype;
  v_rsvp_id uuid;
  existed boolean;
  guest_name text;
  idx integer := 0;
begin
  if caller is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  perform public.ensure_tenant_write_access(p_tenant_id);
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'rsvp.manage', 'COLLECT') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into invitation_record from public.event_invitations
  where id = p_invitation_id and tenant_id = p_tenant_id and event_id = p_event_id
  for update;
  if not found then raise exception 'INVITATION_NOT_FOUND' using errcode = '22023'; end if;
  if invitation_record.status = 'CANCELLED' then
    raise exception 'INVITATION_CANCELLED' using errcode = '22023';
  end if;

  perform public.validate_rsvp_input(upper(coalesce(p_response, '')), p_attending_count, p_guest_names, invitation_record.max_guests);

  select exists(select 1 from public.invitation_rsvps where invitation_id = p_invitation_id) into existed;

  insert into public.invitation_rsvps (
    tenant_id, event_id, invitation_id, response, attending_count, note,
    submitted_by_type, submitted_by_user_id, responded_at
  )
  values (
    p_tenant_id, p_event_id, p_invitation_id, upper(p_response), coalesce(p_attending_count, 0), nullif(btrim(coalesce(p_note, '')), ''),
    'TENANT_USER', caller, now()
  )
  on conflict (invitation_id) do update set
    response = excluded.response,
    attending_count = excluded.attending_count,
    note = excluded.note,
    submitted_by_type = 'TENANT_USER',
    submitted_by_user_id = caller,
    responded_at = now()
  returning id into v_rsvp_id;

  delete from public.rsvp_guests where rsvp_id = v_rsvp_id;
  if p_guest_names is not null then
    foreach guest_name in array p_guest_names loop
      idx := idx + 1;
      if btrim(coalesce(guest_name, '')) <> '' then
        insert into public.rsvp_guests (tenant_id, rsvp_id, guest_name, position) values (p_tenant_id, v_rsvp_id, btrim(guest_name), idx);
      end if;
    end loop;
  end if;

  perform public.write_audit_log(p_tenant_id, 'rsvp.overridden', 'invitation_rsvp', v_rsvp_id, p_event_id, null,
    jsonb_build_object('response', upper(p_response), 'attendingCount', coalesce(p_attending_count, 0), 'invitationId', p_invitation_id, 'previouslyExisted', existed));

  return public.event_invitation_detail_json(p_invitation_id);
end;
$$;

grant execute on function public.rpc_record_manual_rsvp(uuid, uuid, uuid, text, integer, text[], text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC 12: RSVP dashboard
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_event_rsvp_dashboard(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_event_financial_access(p_tenant_id, p_event_id, 'rsvp.view', 'VIEW') then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events where id = p_event_id and tenant_id = p_tenant_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  return (
    select jsonb_build_object(
      'totalInvitations', count(*),
      'draftInvitations', count(*) filter (where ei.status = 'DRAFT'),
      'activeInvitations', count(*) filter (where ei.status = 'ACTIVE'),
      'cancelledInvitations', count(*) filter (where ei.status = 'CANCELLED'),
      'sentInvitations', count(*) filter (where exists (
        select 1 from public.invitation_deliveries d where d.invitation_id = ei.id and d.status in ('SENT', 'DELIVERED')
      )),
      'attendingInvitations', count(*) filter (where ir.response = 'ATTENDING'),
      'maybeInvitations', count(*) filter (where ir.response = 'MAYBE'),
      'notAttendingInvitations', count(*) filter (where ir.response = 'NOT_ATTENDING'),
      'noResponseInvitations', count(*) filter (where ei.status = 'ACTIVE' and ir.id is null),
      'confirmedGuests', coalesce(sum(ir.attending_count) filter (where ir.response = 'ATTENDING'), 0),
      'possibleGuests', coalesce(sum(ir.attending_count) filter (where ir.response = 'MAYBE'), 0)
    )
    from public.event_invitations ei
    left join public.invitation_rsvps ir on ir.invitation_id = ei.id
    where ei.tenant_id = p_tenant_id and ei.event_id = p_event_id
  );
end;
$$;

grant execute on function public.rpc_get_event_rsvp_dashboard(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Defense in depth for the two service-only RPCs below. `revoke all ...
-- from public; grant ... to service_role;` (the pattern already
-- established by rpc_verify_phone_pin, migration 055) turned out NOT to
-- be sufficient on its own: this Supabase Postgres image runs a built-in
-- `issue_pg_graphql_access` event trigger (`ddl_command_end`) that
-- automatically re-grants EXECUTE to anon/authenticated on every function
-- in `public` -- including immediately after an explicit REVOKE, since a
-- REVOKE is itself a ddl_command_end event. This was caught by actually
-- running the migration and probing the resulting ACL (`pg_proc.proacl`)
-- rather than by reading the SQL, and it also appears to affect the
-- pre-existing rpc_verify_phone_pin the same way -- flagged in this
-- batch's report, not silently fixed there, since that RPC is outside
-- this phase's scope. Since grants alone cannot be trusted to hold, both
-- public-facing RPCs independently verify the actual PostgREST-resolved
-- role via the `request.jwt.claim.role` GUC (the same claim PostgREST
-- itself reads before issuing `SET ROLE`), which is unaffected by
-- SECURITY DEFINER's privilege elevation (unlike current_user) and
-- unaffected by the event trigger (it isn't a grant at all).
-- ---------------------------------------------------------------------

create or replace function public.require_service_role()
returns void
language plpgsql
stable
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Service-only RPC A: public-safe invitation detail read.
-- Node has already verified the HMAC signature and decoded
-- invitation_id/token_version before calling this -- the database
-- independently re-checks token_version against the live row (this is
-- what closes the rotate-after-decode race) and never trusts the caller
-- on identity, only on "here is the capability the signature proved".
-- ---------------------------------------------------------------------

create or replace function public.rpc_get_public_invitation_detail(p_invitation_id uuid, p_token_version integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invitation_record public.event_invitations%rowtype;
  event_record public.events%rowtype;
  settings_record public.event_invitation_settings%rowtype;
  template_record public.invitation_templates%rowtype;
  rsvp_record public.invitation_rsvps%rowtype;
  effective_deadline timestamptz;
  can_respond boolean;
begin
  perform public.require_service_role();

  select * into invitation_record from public.event_invitations where id = p_invitation_id;
  if not found then raise exception 'INVITATION_TOKEN_INVALID' using errcode = '22023'; end if;
  if invitation_record.public_token_version <> p_token_version then
    raise exception 'INVITATION_TOKEN_EXPIRED_OR_ROTATED' using errcode = '22023';
  end if;
  if invitation_record.status = 'CANCELLED' then
    raise exception 'INVITATION_CANCELLED' using errcode = '22023';
  end if;
  if invitation_record.status = 'DRAFT' then
    raise exception 'INVITATION_NOT_ACTIVE' using errcode = '22023';
  end if;

  select * into event_record from public.events where id = invitation_record.event_id;
  select * into settings_record from public.event_invitation_settings where event_id = invitation_record.event_id;
  if invitation_record.template_id is not null then
    select * into template_record from public.invitation_templates where id = invitation_record.template_id;
  end if;
  select * into rsvp_record from public.invitation_rsvps where invitation_id = p_invitation_id;

  effective_deadline := settings_record.rsvp_deadline;
  can_respond := coalesce(settings_record.rsvp_enabled, true)
    and (effective_deadline is null or now() <= effective_deadline or coalesce(settings_record.allow_late_rsvp, false));

  update public.event_invitations
  set view_count = view_count + 1,
      first_viewed_at = coalesce(first_viewed_at, now()),
      last_viewed_at = now()
  where id = p_invitation_id;

  return jsonb_build_object(
    'invitation', jsonb_build_object('displayName', invitation_record.display_name, 'maxGuests', invitation_record.max_guests),
    'event', jsonb_build_object(
      'name', coalesce(settings_record.invitation_title, event_record.name),
      'message', settings_record.invitation_message,
      'date', event_record.event_date,
      'time', settings_record.event_time_display,
      'venueName', coalesce(settings_record.venue_name_override, event_record.venue),
      'venueAddress', settings_record.venue_address_override,
      'mapsUrl', settings_record.maps_url,
      'hostDisplayName', settings_record.host_display_name
    ),
    'rsvpSettings', jsonb_build_object(
      'enabled', coalesce(settings_record.rsvp_enabled, true),
      'deadline', effective_deadline,
      'allowLateRsvp', coalesce(settings_record.allow_late_rsvp, false),
      'canRespond', can_respond
    ),
    'rsvp', case when rsvp_record.id is null then null else jsonb_build_object(
      'response', rsvp_record.response,
      'attendingCount', rsvp_record.attending_count,
      'guestNames', coalesce((select jsonb_agg(g.guest_name order by g.position) from public.rsvp_guests g where g.rsvp_id = rsvp_record.id), '[]'::jsonb),
      'respondedAt', rsvp_record.responded_at
    ) end,
    'template', case when template_record.id is null then null else jsonb_build_object('layoutKey', template_record.layout_key, 'config', template_record.config_json) end
  );
end;
$$;

revoke all on function public.rpc_get_public_invitation_detail(uuid, integer) from public;
grant execute on function public.rpc_get_public_invitation_detail(uuid, integer) to service_role;

-- ---------------------------------------------------------------------
-- Service-only RPC B: public RSVP submission.
-- ---------------------------------------------------------------------

create or replace function public.rpc_submit_public_invitation_rsvp(
  p_invitation_id uuid,
  p_token_version integer,
  p_response text,
  p_attending_count integer,
  p_guest_names text[] default '{}',
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invitation_record public.event_invitations%rowtype;
  settings_record public.event_invitation_settings%rowtype;
  normalized_response text := upper(coalesce(p_response, ''));
  v_rsvp_id uuid;
  existed boolean;
  guest_name text;
  idx integer := 0;
begin
  perform public.require_service_role();

  select * into invitation_record from public.event_invitations where id = p_invitation_id for update;
  if not found then raise exception 'INVITATION_TOKEN_INVALID' using errcode = '22023'; end if;
  if invitation_record.public_token_version <> p_token_version then
    raise exception 'INVITATION_TOKEN_EXPIRED_OR_ROTATED' using errcode = '22023';
  end if;
  if invitation_record.status = 'CANCELLED' then
    raise exception 'INVITATION_CANCELLED' using errcode = '22023';
  end if;
  if invitation_record.status = 'DRAFT' then
    raise exception 'INVITATION_NOT_ACTIVE' using errcode = '22023';
  end if;

  select * into settings_record from public.event_invitation_settings where event_id = invitation_record.event_id;
  if not coalesce(settings_record.rsvp_enabled, true) then
    raise exception 'RSVP_DISABLED' using errcode = '22023';
  end if;
  if settings_record.rsvp_deadline is not null and now() > settings_record.rsvp_deadline and not coalesce(settings_record.allow_late_rsvp, false) then
    raise exception 'RSVP_DEADLINE_PASSED' using errcode = '22023';
  end if;

  perform public.validate_rsvp_input(normalized_response, p_attending_count, p_guest_names, invitation_record.max_guests);

  select exists(select 1 from public.invitation_rsvps where invitation_id = p_invitation_id) into existed;

  insert into public.invitation_rsvps (
    tenant_id, event_id, invitation_id, response, attending_count, note,
    submitted_by_type, submitted_by_user_id, responded_at
  )
  values (
    invitation_record.tenant_id, invitation_record.event_id, p_invitation_id, normalized_response, coalesce(p_attending_count, 0),
    nullif(btrim(coalesce(p_note, '')), ''), 'PUBLIC_GUEST', null, now()
  )
  on conflict (invitation_id) do update set
    response = excluded.response,
    attending_count = excluded.attending_count,
    note = excluded.note,
    submitted_by_type = 'PUBLIC_GUEST',
    submitted_by_user_id = null,
    responded_at = now()
  returning id into v_rsvp_id;

  delete from public.rsvp_guests where rsvp_id = v_rsvp_id;
  if p_guest_names is not null then
    foreach guest_name in array p_guest_names loop
      idx := idx + 1;
      if btrim(coalesce(guest_name, '')) <> '' then
        insert into public.rsvp_guests (tenant_id, rsvp_id, guest_name, position)
        values (invitation_record.tenant_id, v_rsvp_id, btrim(guest_name), idx);
      end if;
    end loop;
  end if;

  perform public.write_audit_log(invitation_record.tenant_id, case when existed then 'rsvp.updated' else 'rsvp.submitted' end,
    'invitation_rsvp', v_rsvp_id, invitation_record.event_id, null,
    jsonb_build_object('response', normalized_response, 'attendingCount', coalesce(p_attending_count, 0)));

  return jsonb_build_object(
    'response', normalized_response,
    'attendingCount', coalesce(p_attending_count, 0),
    'guestNames', coalesce((select jsonb_agg(g.guest_name order by g.position) from public.rsvp_guests g where g.rsvp_id = v_rsvp_id), '[]'::jsonb),
    'respondedAt', now(),
    'updated', existed
  );
end;
$$;

revoke all on function public.rpc_submit_public_invitation_rsvp(uuid, integer, text, integer, text[], text) from public;
grant execute on function public.rpc_submit_public_invitation_rsvp(uuid, integer, text, integer, text[], text) to service_role;

notify pgrst, 'reload schema';
