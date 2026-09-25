-- RSVP-3A: Invitation Card Engine + QR + Preview + Export.
--
-- This migration only hardens/extends the RSVP-1 template domain
-- (invitation_templates.config_json) so it can drive a personalized visual
-- card. It does not touch event_invitations/invitation_rsvps/rsvp_guests,
-- does not add a template-authoring API (still out of scope), and does not
-- change any existing RPC's parameter list.
--
-- 1. A declarative, whitelisted schema for config_json is defined and
--    enforced with a CHECK constraint (public.validate_invitation_template_config).
--    Only a fixed set of keys/enum values are ever accepted -- there is no
--    way to store HTML/CSS/JS/script/arbitrary-URL content in a template,
--    which is what "template config is untrusted content, must remain
--    declarative" (RSVP-3A security requirement) means in practice here.
-- 2. The existing seed 'Classic' PLATFORM template's config_json (from
--    migration 072: '{"palette": "neutral"}') predates this schema and does
--    not conform to it -- it is rewritten to the new shape *before* the
--    CHECK constraint is added, since ADD CONSTRAINT validates existing
--    rows immediately.
-- 3. Four more PLATFORM templates are seeded, one per remaining required
--    category (Minimal, Elegant, Modern, Traditional) -- five total,
--    within the "4-6 high-quality templates" guidance. All five share the
--    same layout algorithm client-side (one canonical renderer); layoutKey
--    only selects minor stylistic variation, per "use one logical template
--    with responsive layout rules, do not duplicate one template per
--    aspect ratio/style."
-- 4. rpc_list_invitation_templates (migration 074) is extended to also
--    return configJson/isPremium -- an additive change to the JSON body of
--    a function that already returns jsonb, so `create or replace` is safe
--    here (unlike migration 075's parameter-list change, this is not a
--    signature change).

-- ---------------------------------------------------------------------
-- Declarative config_json schema validator.
-- ---------------------------------------------------------------------
--
-- Recommended/enforced shape:
-- {
--   "version": 1,
--   "layoutKey": "classic_elegant",
--   "background": { "type": "solid", "color": "#F8F2EA" }
--     -- or: { "type": "gradient", "colors": ["#F8F2EA", "#EADFCB"] },
--   "colors": { "primary": "#8F1D2C", "secondary": "#D7B56D", "text": "#241A18" },
--   "typography": { "titleStyle": "serif_elegant", "bodyStyle": "ubuntu" },
--   "elements": {
--     "showHost": true, "showGuestName": true, "showEventName": true,
--     "showDate": true, "showTime": true, "showVenue": true,
--     "showAddress": true, "showQr": true, "showRsvpDeadline": true
--   }
-- }
--
-- Every object in this shape only accepts the keys enumerated below; any
-- other key (at any level) makes the whole config invalid. Every leaf value
-- is checked against a fixed type/enum/pattern. There is deliberately no
-- key anywhere that can hold a URL, HTML fragment, or script.

create or replace function public.validate_invitation_template_config(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  hex_pattern text := '^#[0-9A-Fa-f]{6}$';
  allowed_top text[] := array['version', 'layoutKey', 'background', 'colors', 'typography', 'elements'];
  allowed_background_keys text[] := array['type', 'color', 'colors'];
  allowed_color_keys text[] := array['primary', 'secondary', 'text'];
  allowed_typography_keys text[] := array['titleStyle', 'bodyStyle'];
  allowed_element_keys text[] := array[
    'showHost', 'showGuestName', 'showEventName', 'showDate', 'showTime',
    'showVenue', 'showAddress', 'showQr', 'showRsvpDeadline'
  ];
  allowed_title_styles text[] := array['serif_elegant', 'sans_modern', 'condensed_bold', 'script_traditional', 'minimal_light'];
  allowed_body_styles text[] := array['ubuntu', 'condensed', 'mono'];
  k text;
  background_node jsonb;
  colors_node jsonb;
  typography_node jsonb;
  elements_node jsonb;
  background_type text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then
    return false;
  end if;

  for k in select jsonb_object_keys(p_config) loop
    if not (k = any(allowed_top)) then
      return false;
    end if;
  end loop;

  if p_config ? 'version' and (jsonb_typeof(p_config->'version') <> 'number' or (p_config->>'version') <> '1') then
    return false;
  end if;
  if p_config ? 'layoutKey' and (jsonb_typeof(p_config->'layoutKey') <> 'string' or btrim(p_config->>'layoutKey') = '') then
    return false;
  end if;

  if p_config ? 'background' then
    background_node := p_config->'background';
    if jsonb_typeof(background_node) <> 'object' then
      return false;
    end if;
    for k in select jsonb_object_keys(background_node) loop
      if not (k = any(allowed_background_keys)) then
        return false;
      end if;
    end loop;
    if not (background_node ? 'type') or jsonb_typeof(background_node->'type') <> 'string' then
      return false;
    end if;
    background_type := background_node->>'type';
    if background_type not in ('solid', 'gradient') then
      return false;
    end if;
    if background_type = 'solid' then
      if not (background_node ? 'color') or (background_node->>'color') !~ hex_pattern then
        return false;
      end if;
    else
      if not (background_node ? 'colors') or jsonb_typeof(background_node->'colors') <> 'array'
        or jsonb_array_length(background_node->'colors') < 2 then
        return false;
      end if;
      if exists (select 1 from jsonb_array_elements_text(background_node->'colors') v where v !~ hex_pattern) then
        return false;
      end if;
    end if;
  end if;

  if p_config ? 'colors' then
    colors_node := p_config->'colors';
    if jsonb_typeof(colors_node) <> 'object' then
      return false;
    end if;
    for k in select jsonb_object_keys(colors_node) loop
      if not (k = any(allowed_color_keys)) then
        return false;
      end if;
    end loop;
    if exists (select 1 from jsonb_each_text(colors_node) e where e.value !~ hex_pattern) then
      return false;
    end if;
  end if;

  if p_config ? 'typography' then
    typography_node := p_config->'typography';
    if jsonb_typeof(typography_node) <> 'object' then
      return false;
    end if;
    for k in select jsonb_object_keys(typography_node) loop
      if not (k = any(allowed_typography_keys)) then
        return false;
      end if;
    end loop;
    if typography_node ? 'titleStyle' and not (typography_node->>'titleStyle' = any(allowed_title_styles)) then
      return false;
    end if;
    if typography_node ? 'bodyStyle' and not (typography_node->>'bodyStyle' = any(allowed_body_styles)) then
      return false;
    end if;
  end if;

  if p_config ? 'elements' then
    elements_node := p_config->'elements';
    if jsonb_typeof(elements_node) <> 'object' then
      return false;
    end if;
    for k in select jsonb_object_keys(elements_node) loop
      if not (k = any(allowed_element_keys)) then
        return false;
      end if;
    end loop;
    if exists (select 1 from jsonb_each(elements_node) e where jsonb_typeof(e.value) <> 'boolean') then
      return false;
    end if;
  end if;

  return true;
end;
$$;

-- Rewrite the pre-existing seed row to the new schema before the CHECK
-- constraint below is added (ADD CONSTRAINT validates existing rows
-- immediately, and the old '{"palette": "neutral"}' shape does not
-- conform).
update public.invitation_templates
set config_json = jsonb_build_object(
  'version', 1,
  'layoutKey', 'CLASSIC',
  'background', jsonb_build_object('type', 'solid', 'color', '#F8F2EA'),
  'colors', jsonb_build_object('primary', '#8F1D2C', 'secondary', '#D7B56D', 'text', '#241A18'),
  'typography', jsonb_build_object('titleStyle', 'serif_elegant', 'bodyStyle', 'ubuntu'),
  'elements', jsonb_build_object(
    'showHost', true, 'showGuestName', true, 'showEventName', true, 'showDate', true, 'showTime', true,
    'showVenue', true, 'showAddress', true, 'showQr', true, 'showRsvpDeadline', true
  )
),
category = 'Classic'
where scope = 'PLATFORM' and layout_key = 'CLASSIC' and tenant_id is null;

alter table public.invitation_templates
  add constraint invitation_templates_config_json_valid
  check (public.validate_invitation_template_config(config_json));

-- Four more PLATFORM templates, one per remaining required category.
insert into public.invitation_templates (scope, tenant_id, name, category, layout_key, config_json, is_active, is_premium)
values
  (
    'PLATFORM', null, 'Minimal Light', 'Minimal', 'MINIMAL_LIGHT',
    jsonb_build_object(
      'version', 1, 'layoutKey', 'MINIMAL_LIGHT',
      'background', jsonb_build_object('type', 'solid', 'color', '#FFFFFF'),
      'colors', jsonb_build_object('primary', '#2B2B2B', 'secondary', '#9C9C9C', 'text', '#1A1A1A'),
      'typography', jsonb_build_object('titleStyle', 'minimal_light', 'bodyStyle', 'ubuntu'),
      'elements', jsonb_build_object(
        'showHost', true, 'showGuestName', true, 'showEventName', true, 'showDate', true, 'showTime', true,
        'showVenue', true, 'showAddress', false, 'showQr', true, 'showRsvpDeadline', true
      )
    ),
    true, false
  ),
  (
    'PLATFORM', null, 'Elegant Burgundy', 'Elegant', 'ELEGANT_BURGUNDY',
    jsonb_build_object(
      'version', 1, 'layoutKey', 'ELEGANT_BURGUNDY',
      'background', jsonb_build_object('type', 'solid', 'color', '#F8F2EA'),
      'colors', jsonb_build_object('primary', '#6F1722', 'secondary', '#D7B56D', 'text', '#241A18'),
      'typography', jsonb_build_object('titleStyle', 'serif_elegant', 'bodyStyle', 'condensed'),
      'elements', jsonb_build_object(
        'showHost', true, 'showGuestName', true, 'showEventName', true, 'showDate', true, 'showTime', true,
        'showVenue', true, 'showAddress', true, 'showQr', true, 'showRsvpDeadline', true
      )
    ),
    true, true
  ),
  (
    'PLATFORM', null, 'Modern Bold', 'Modern', 'MODERN_BOLD',
    jsonb_build_object(
      'version', 1, 'layoutKey', 'MODERN_BOLD',
      'background', jsonb_build_object('type', 'solid', 'color', '#101820'),
      'colors', jsonb_build_object('primary', '#F2C14E', 'secondary', '#FFFFFF', 'text', '#FFFFFF'),
      'typography', jsonb_build_object('titleStyle', 'sans_modern', 'bodyStyle', 'mono'),
      'elements', jsonb_build_object(
        'showHost', true, 'showGuestName', true, 'showEventName', true, 'showDate', true, 'showTime', true,
        'showVenue', true, 'showAddress', true, 'showQr', true, 'showRsvpDeadline', true
      )
    ),
    true, false
  ),
  (
    'PLATFORM', null, 'Traditional Kitenge', 'Traditional', 'TRADITIONAL_KITENGE',
    jsonb_build_object(
      'version', 1, 'layoutKey', 'TRADITIONAL_KITENGE',
      'background', jsonb_build_object('type', 'solid', 'color', '#FCEEDD'),
      'colors', jsonb_build_object('primary', '#B5482A', 'secondary', '#2F6E4F', 'text', '#3A2A1E'),
      'typography', jsonb_build_object('titleStyle', 'script_traditional', 'bodyStyle', 'condensed'),
      'elements', jsonb_build_object(
        'showHost', true, 'showGuestName', true, 'showEventName', true, 'showDate', true, 'showTime', true,
        'showVenue', true, 'showAddress', true, 'showQr', true, 'showRsvpDeadline', true
      )
    ),
    true, false
  )
on conflict do nothing;

-- Extend the RSVP-2 template list RPC with configJson/isPremium so the
-- Template Gallery can render a real thumbnail (client-side, same renderer
-- as the export) and show the premium badge -- purely additive to the JSON
-- body, no parameter list change, so create-or-replace is safe.
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
      'category', t.category,
      'isPremium', t.is_premium,
      'configJson', t.config_json
    ) order by t.scope, t.name)
    from public.invitation_templates t
    where t.is_active
      and (t.scope = 'PLATFORM' or (t.scope = 'TENANT' and t.tenant_id = p_tenant_id))
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.rpc_list_invitation_templates(uuid) to authenticated;

notify pgrst, 'reload schema';
