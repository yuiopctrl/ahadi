insert into public.permissions (code, name, description) values
('platform.beta.view', 'View beta rollout', 'View beta rollout operations'),
('platform.beta.manage', 'Manage beta rollout', 'Manage registration policy and beta invitations'),
('platform.support.view', 'View support desk', 'View support tickets and safe tenant support context'),
('platform.support.manage', 'Manage support desk', 'Assign tickets and update support workflow'),
('platform.feedback.view', 'View product feedback', 'View beta product feedback'),
('platform.features.view', 'View feature flags', 'View feature flag configuration'),
('platform.features.manage', 'Manage feature flags', 'Manage global and tenant feature flag overrides'),
('platform.system_errors.view', 'View system errors', 'View first-party operational error reports'),
('platform.support_session.start', 'Start support session', 'Start controlled read-only support sessions')
on conflict (code) do update set name = excluded.name, description = excluded.description;

alter table public.tenants
  add column if not exists lifecycle_tag text not null default 'BETA' check (lifecycle_tag in ('BETA', 'PILOT', 'INTERNAL', 'PRODUCTION')),
  add column if not exists commercial_status text not null default 'TRIAL' check (commercial_status in ('LEAD', 'TRIAL', 'CUSTOMER', 'CHURNED')),
  add column if not exists operational_notice text;

create table if not exists public.platform_settings (
  id boolean primary key default true check (id),
  registration_mode text not null default 'OPEN' check (registration_mode in ('OPEN', 'INVITE_ONLY', 'PAUSED')),
  beta_mode_enabled boolean not null default true,
  default_trial_days integer not null default 14 check (default_trial_days >= 0),
  max_trial_extension_days integer not null default 90 check (max_trial_extension_days > 0),
  support_email text,
  support_phone text,
  maintenance_notice text,
  maintenance_mode text not null default 'OFF' check (maintenance_mode in ('OFF', 'READ_ONLY')),
  minimum_supported_web_version text,
  release_channel text not null default 'BETA' check (release_channel in ('BETA', 'STABLE')),
  web_version text not null default '0.9.0-beta',
  api_version text not null default '0.9.0-beta',
  worker_version text not null default '0.9.0-beta',
  build_commit text,
  build_time timestamptz,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.platform_settings (id) values (true) on conflict (id) do nothing;

create trigger platform_settings_set_updated_at
before update on public.platform_settings
for each row execute function public.set_updated_at();

create table if not exists public.beta_invitations (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  display_code_suffix text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'USED', 'REVOKED', 'EXPIRED')),
  intended_name text,
  intended_phone_e164 text check (intended_phone_e164 is null or intended_phone_e164 ~ '^\+255[67][0-9]{8}$'),
  intended_email text,
  plan_id uuid references public.subscription_plans(id),
  trial_days_override integer check (trial_days_override is null or trial_days_override >= 0),
  max_uses integer not null default 1 check (max_uses > 0),
  use_count integer not null default 0 check (use_count >= 0),
  expires_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists beta_invitations_status_idx on public.beta_invitations(status);
create index if not exists beta_invitations_expires_idx on public.beta_invitations(expires_at);

create trigger beta_invitations_set_updated_at
before update on public.beta_invitations
for each row execute function public.set_updated_at();

create table if not exists public.beta_invitation_uses (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.beta_invitations(id) on delete cascade,
  tenant_id uuid references public.tenants(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  used_at timestamptz not null default now(),
  unique (invitation_id, tenant_id)
);

create table if not exists public.product_events (
  id bigint generated always as identity primary key,
  correlation_id text,
  user_id uuid references auth.users(id) on delete set null,
  tenant_id uuid references public.tenants(id) on delete set null,
  event_name text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (event_name = upper(event_name))
);

create index if not exists product_events_event_created_idx on public.product_events(event_name, created_at desc);
create index if not exists product_events_tenant_created_idx on public.product_events(tenant_id, created_at desc);

create sequence if not exists public.support_ticket_number_seq start 1;

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  ticket_number text not null unique default ('SUP-' || lpad(nextval('public.support_ticket_number_seq')::text, 6, '0')),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  category text not null check (category in ('LOGIN', 'MEMBERS', 'PLEDGES', 'PAYMENTS', 'SMS', 'REPORTS', 'SUBSCRIPTION', 'OTHER')),
  subject text not null check (btrim(subject) <> ''),
  description text not null check (btrim(description) <> ''),
  status text not null default 'OPEN' check (status in ('OPEN', 'IN_PROGRESS', 'WAITING_CUSTOMER', 'RESOLVED', 'CLOSED')),
  priority text not null default 'NORMAL' check (priority in ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
  assigned_platform_user_id uuid references public.platform_users(id) on delete set null,
  app_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists support_requests_tenant_created_idx on public.support_requests(tenant_id, created_at desc);
create index if not exists support_requests_status_idx on public.support_requests(status);

create trigger support_requests_set_updated_at
before update on public.support_requests
for each row execute function public.set_updated_at();

create table if not exists public.support_request_notes (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.support_requests(id) on delete cascade,
  author_user_id uuid references auth.users(id) on delete set null,
  author_platform_user_id uuid references public.platform_users(id) on delete set null,
  visibility text not null default 'TENANT_VISIBLE' check (visibility in ('INTERNAL', 'TENANT_VISIBLE')),
  body text not null check (btrim(body) <> ''),
  created_at timestamptz not null default now()
);

create index if not exists support_request_notes_request_created_idx on public.support_request_notes(request_id, created_at);

create table if not exists public.product_feedback (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  category text not null check (category in ('SUGGESTION', 'PROBLEM', 'USABILITY', 'OTHER')),
  message text not null check (btrim(message) <> ''),
  page text,
  status text not null default 'NEW' check (status in ('NEW', 'REVIEWED', 'PLANNED', 'CLOSED')),
  app_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger product_feedback_set_updated_at
before update on public.product_feedback
for each row execute function public.set_updated_at();

create table if not exists public.feature_flags (
  key text primary key check (key ~ '^[a-z0-9_]+$'),
  description text not null,
  enabled_globally boolean not null default true,
  beta_only boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.feature_flags (key, description, enabled_globally, beta_only) values
('balance_reminders', 'Balance reminder SMS workflows', true, false),
('whatsapp_lists', 'WhatsApp share lists', true, false),
('report_exports', 'Report exports', true, false),
('member_statement_pdf', 'Member statement PDF exports', true, false),
('support_requests', 'Tenant support requests', true, false)
on conflict (key) do nothing;

create trigger feature_flags_set_updated_at
before update on public.feature_flags
for each row execute function public.set_updated_at();

create table if not exists public.tenant_feature_flags (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  feature_key text not null references public.feature_flags(key) on delete cascade,
  override text not null default 'INHERIT' check (override in ('INHERIT', 'ENABLED', 'DISABLED')),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, feature_key)
);

create trigger tenant_feature_flags_set_updated_at
before update on public.tenant_feature_flags
for each row execute function public.set_updated_at();

create table if not exists public.frontend_error_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  error_code text,
  request_id text,
  route text,
  component text,
  app_version text,
  browser_summary text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists frontend_error_reports_created_idx on public.frontend_error_reports(created_at desc);
create index if not exists frontend_error_reports_error_code_idx on public.frontend_error_reports(error_code);

create table if not exists public.beta_notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  severity text not null default 'INFO' check (severity in ('INFO', 'WARNING', 'MAINTENANCE')),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger beta_notices_set_updated_at
before update on public.beta_notices
for each row execute function public.set_updated_at();

create table if not exists public.support_access_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  platform_user_id uuid not null references public.platform_users(id) on delete cascade,
  requested_reason text not null check (btrim(requested_reason) <> ''),
  scope text not null check (scope in ('TENANT_CONFIGURATION', 'EVENT_CONFIGURATION', 'FINANCIAL_READ_ONLY')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'EXPIRED', 'REVOKED')),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists support_access_sessions_tenant_status_idx on public.support_access_sessions(tenant_id, status);

alter table public.platform_settings enable row level security;
alter table public.beta_invitations enable row level security;
alter table public.beta_invitation_uses enable row level security;
alter table public.product_events enable row level security;
alter table public.support_requests enable row level security;
alter table public.support_request_notes enable row level security;
alter table public.product_feedback enable row level security;
alter table public.feature_flags enable row level security;
alter table public.tenant_feature_flags enable row level security;
alter table public.frontend_error_reports enable row level security;
alter table public.beta_notices enable row level security;
alter table public.support_access_sessions enable row level security;

create or replace function public.has_platform_permission(permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.platform_users pu
    where pu.user_id = auth.uid()
      and pu.status = 'ACTIVE'
      and (
        pu.role = 'PLATFORM_OWNER'
        or (pu.role = 'PLATFORM_ADMIN' and permission_code in (
          'platform.dashboard.view','platform.tenants.view','platform.tenants.manage','platform.plans.view','platform.plans.manage','platform.subscriptions.manage','platform.sms.view',
          'platform.beta.view','platform.beta.manage','platform.support.view','platform.support.manage','platform.feedback.view','platform.features.view','platform.features.manage','platform.system_errors.view','platform.support_session.start'
        ))
        or (pu.role = 'PLATFORM_SUPPORT' and permission_code in ('platform.dashboard.view','platform.tenants.view','platform.sms.view','platform.support.view','platform.support.manage','platform.feedback.view','platform.system_errors.view','platform.support_session.start'))
        or (pu.role = 'PLATFORM_AUDITOR' and permission_code in ('platform.dashboard.view','platform.audit.view','platform.system_errors.view'))
      )
  );
$$;

create or replace function public.beta_invitation_hash(p_code text)
returns text
language sql
immutable
as $$
  select encode(digest(upper(btrim(coalesce(p_code, ''))), 'sha256'), 'hex');
$$;

create or replace function public.safe_app_context(p_context jsonb)
returns jsonb
language sql
stable
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'route', left(coalesce(p_context ->> 'route', ''), 240),
    'appVersion', left(coalesce(p_context ->> 'appVersion', ''), 80),
    'webVersion', left(coalesce(p_context ->> 'webVersion', ''), 80),
    'browser', left(coalesce(p_context ->> 'browser', ''), 180),
    'platform', left(coalesce(p_context ->> 'platform', ''), 120),
    'requestId', left(coalesce(p_context ->> 'requestId', ''), 80)
  ));
$$;

create or replace function public.has_feature(p_tenant_id uuid, p_feature_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when override_row.override = 'ENABLED' then true
      when override_row.override = 'DISABLED' then false
      when flag.key is null then false
      when flag.beta_only then flag.enabled_globally and tenant_row.lifecycle_tag in ('BETA', 'PILOT', 'INTERNAL')
      else flag.enabled_globally
    end
    from public.feature_flags flag
    left join public.tenant_feature_flags override_row on override_row.tenant_id = p_tenant_id and override_row.feature_key = flag.key
    left join public.tenants tenant_row on tenant_row.id = p_tenant_id
    where flag.key = p_feature_key
  ), false);
$$;

create or replace function public.rpc_get_rollout_settings_public()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'registrationMode', registration_mode,
    'betaModeEnabled', beta_mode_enabled,
    'supportEmail', support_email,
    'supportPhone', support_phone,
    'maintenanceNotice', maintenance_notice,
    'maintenanceMode', maintenance_mode,
    'minimumSupportedWebVersion', minimum_supported_web_version,
    'releaseChannel', release_channel,
    'webVersion', web_version
  )
  from public.platform_settings
  where id = true;
$$;

create or replace function public.rpc_validate_beta_invitation(p_code text, p_phone_e164 text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  invite public.beta_invitations%rowtype;
begin
  select * into invite
  from public.beta_invitations
  where code_hash = public.beta_invitation_hash(p_code);

  if not found then
    return jsonb_build_object('valid', false, 'reason', 'INVITATION_NOT_FOUND');
  end if;
  if invite.status <> 'ACTIVE' then
    return jsonb_build_object('valid', false, 'reason', 'INVITATION_' || invite.status);
  end if;
  if invite.expires_at is not null and invite.expires_at <= now() then
    return jsonb_build_object('valid', false, 'reason', 'INVITATION_EXPIRED');
  end if;
  if invite.use_count >= invite.max_uses then
    return jsonb_build_object('valid', false, 'reason', 'INVITATION_USED');
  end if;
  if invite.intended_phone_e164 is not null and p_phone_e164 is not null and invite.intended_phone_e164 <> p_phone_e164 then
    return jsonb_build_object('valid', false, 'reason', 'INVITATION_PHONE_MISMATCH');
  end if;

  return jsonb_build_object(
    'valid', true,
    'invitationId', invite.id,
    'displayCodeSuffix', invite.display_code_suffix,
    'planId', invite.plan_id,
    'trialDaysOverride', invite.trial_days_override,
    'expiresAt', invite.expires_at
  );
end;
$$;

create or replace function public.rpc_consume_beta_invitation(p_code text, p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invite public.beta_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;

  select * into invite
  from public.beta_invitations
  where code_hash = public.beta_invitation_hash(p_code)
  for update;

  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = '22023';
  end if;
  if invite.status <> 'ACTIVE' and not exists (select 1 from public.beta_invitation_uses where invitation_id = invite.id and tenant_id = p_tenant_id) then
    raise exception 'INVITATION_NOT_ACTIVE' using errcode = '22023';
  end if;

  insert into public.beta_invitation_uses (invitation_id, tenant_id, user_id)
  values (invite.id, p_tenant_id, auth.uid())
  on conflict (invitation_id, tenant_id) do nothing;

  update public.beta_invitations
  set use_count = least(max_uses, use_count + 1),
      status = case when least(max_uses, use_count + 1) >= max_uses then 'USED' else status end
  where id = invite.id;

  update public.tenants
  set lifecycle_tag = 'BETA',
      commercial_status = 'TRIAL'
  where id = p_tenant_id;

  perform public.write_audit_log(p_tenant_id, 'BETA_INVITATION_CONSUMED', 'beta_invitation', invite.id, null, null, jsonb_build_object('tenantId', p_tenant_id), null);
  return jsonb_build_object('consumed', true, 'invitationId', invite.id);
end;
$$;

create or replace function public.rpc_create_beta_invitation(
  p_code text,
  p_intended_name text default null,
  p_intended_phone_e164 text default null,
  p_intended_email text default null,
  p_plan_id uuid default null,
  p_trial_days_override integer default null,
  p_max_uses integer default 1,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invite public.beta_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_platform_permission('platform.beta.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  insert into public.beta_invitations (
    code_hash, display_code_suffix, intended_name, intended_phone_e164, intended_email, plan_id, trial_days_override, max_uses, expires_at, created_by
  )
  values (
    public.beta_invitation_hash(p_code),
    right(upper(btrim(p_code)), 6),
    nullif(btrim(coalesce(p_intended_name, '')), ''),
    case when p_intended_phone_e164 is null or btrim(p_intended_phone_e164) = '' then null else public.normalize_tz_phone(p_intended_phone_e164) end,
    nullif(btrim(coalesce(p_intended_email, '')), ''),
    p_plan_id,
    p_trial_days_override,
    greatest(coalesce(p_max_uses, 1), 1),
    p_expires_at,
    auth.uid()
  )
  returning * into invite;

  return jsonb_build_object('id', invite.id, 'code', p_code, 'displayCodeSuffix', invite.display_code_suffix, 'status', invite.status, 'expiresAt', invite.expires_at);
end;
$$;

create or replace function public.rpc_revoke_beta_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_platform_permission('platform.beta.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  update public.beta_invitations
  set status = 'REVOKED'
  where id = p_invitation_id and status = 'ACTIVE';
  return jsonb_build_object('revoked', true);
end;
$$;

create or replace function public.rpc_update_rollout_settings(
  p_registration_mode text,
  p_beta_mode_enabled boolean default null,
  p_default_trial_days integer default null,
  p_support_email text default null,
  p_support_phone text default null,
  p_maintenance_notice text default null,
  p_maintenance_mode text default null,
  p_minimum_supported_web_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings public.platform_settings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_platform_permission('platform.beta.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_registration_mode not in ('OPEN', 'INVITE_ONLY', 'PAUSED') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  update public.platform_settings
  set registration_mode = p_registration_mode,
      beta_mode_enabled = coalesce(p_beta_mode_enabled, beta_mode_enabled),
      default_trial_days = coalesce(p_default_trial_days, default_trial_days),
      support_email = p_support_email,
      support_phone = p_support_phone,
      maintenance_notice = p_maintenance_notice,
      maintenance_mode = coalesce(p_maintenance_mode, maintenance_mode),
      minimum_supported_web_version = p_minimum_supported_web_version,
      updated_by = auth.uid()
  where id = true
  returning * into settings;

  perform public.write_audit_log(null, 'PLATFORM_ROLLOUT_SETTINGS_UPDATED', 'platform_settings', null, null, null, to_jsonb(settings), null);
  return public.rpc_get_rollout_settings_public();
end;
$$;

create or replace function public.rpc_create_support_request(
  p_tenant_id uuid,
  p_category text,
  p_subject text,
  p_description text,
  p_event_id uuid default null,
  p_contact_preference text default null,
  p_app_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_record public.support_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_feature(p_tenant_id, 'support_requests') then
    raise exception 'FEATURE_DISABLED' using errcode = '42501';
  end if;

  insert into public.support_requests (tenant_id, user_id, event_id, category, subject, description, app_context)
  values (p_tenant_id, auth.uid(), p_event_id, p_category, left(p_subject, 160), left(p_description, 4000), public.safe_app_context(coalesce(p_app_context, '{}'::jsonb) || jsonb_build_object('contactPreference', left(coalesce(p_contact_preference, ''), 80))))
  returning * into request_record;

  perform public.write_audit_log(p_tenant_id, 'SUPPORT_REQUEST_CREATED', 'support_request', request_record.id, p_event_id, null, jsonb_build_object('ticketNumber', request_record.ticket_number, 'category', request_record.category), null);
  return to_jsonb(request_record);
end;
$$;

create or replace function public.rpc_list_my_support_requests(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  from (
    select id, ticket_number, category, subject, status, priority, event_id, created_at, updated_at, resolved_at
    from public.support_requests
    where tenant_id = p_tenant_id
      and public.is_active_tenant_member(p_tenant_id)
  ) row_data;
$$;

create or replace function public.rpc_list_platform_support_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if not public.has_platform_permission('platform.support.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select sr.id, sr.ticket_number, sr.category, sr.subject, sr.status, sr.priority, sr.created_at, sr.updated_at,
      t.id as tenant_id, t.code as tenant_code, t.name as tenant_name,
      p.full_name as reporter_name, p.phone_e164 as reporter_phone
    from public.support_requests sr
    join public.tenants t on t.id = sr.tenant_id
    left join public.profiles p on p.id = sr.user_id
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_update_support_request(p_request_id uuid, p_status text default null, p_priority text default null, p_assigned_platform_user_id uuid default null, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_record public.support_requests%rowtype;
  platform_id uuid;
begin
  if not public.has_platform_permission('platform.support.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  select id into platform_id from public.platform_users where user_id = auth.uid() and status = 'ACTIVE' limit 1;
  update public.support_requests
  set status = coalesce(p_status, status),
      priority = coalesce(p_priority, priority),
      assigned_platform_user_id = coalesce(p_assigned_platform_user_id, assigned_platform_user_id),
      resolved_at = case when coalesce(p_status, status) in ('RESOLVED', 'CLOSED') then now() else resolved_at end
  where id = p_request_id
  returning * into request_record;

  if btrim(coalesce(p_note, '')) <> '' then
    insert into public.support_request_notes (request_id, author_user_id, author_platform_user_id, visibility, body)
    values (p_request_id, auth.uid(), platform_id, 'TENANT_VISIBLE', left(p_note, 4000));
  end if;

  return to_jsonb(request_record);
end;
$$;

create or replace function public.rpc_create_feedback(p_tenant_id uuid, p_category text, p_message text, p_event_id uuid default null, p_page text default null, p_app_context jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  feedback_record public.product_feedback%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  insert into public.product_feedback (tenant_id, user_id, event_id, category, message, page, app_context)
  values (p_tenant_id, auth.uid(), p_event_id, p_category, left(p_message, 4000), left(coalesce(p_page, ''), 240), public.safe_app_context(coalesce(p_app_context, '{}'::jsonb)))
  returning * into feedback_record;
  return to_jsonb(feedback_record);
end;
$$;

create or replace function public.rpc_list_platform_feedback()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if not public.has_platform_permission('platform.feedback.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into result
  from (
    select pf.id, pf.category, pf.message, pf.page, pf.status, pf.created_at, t.code as tenant_code, t.name as tenant_name, p.full_name as user_name
    from public.product_feedback pf
    left join public.tenants t on t.id = pf.tenant_id
    left join public.profiles p on p.id = pf.user_id
  ) row_data;
  return result;
end;
$$;

create or replace function public.rpc_report_frontend_error(p_tenant_id uuid default null, p_error_code text default null, p_request_id text default null, p_route text default null, p_component text default null, p_app_version text default null, p_browser_summary text default null, p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  error_id uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if p_tenant_id is not null and not public.is_tenant_member(p_tenant_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  insert into public.frontend_error_reports (tenant_id, user_id, error_code, request_id, route, component, app_version, browser_summary, metadata)
  values (p_tenant_id, auth.uid(), left(coalesce(p_error_code, ''), 120), left(coalesce(p_request_id, ''), 80), left(coalesce(p_route, ''), 240), left(coalesce(p_component, ''), 120), left(coalesce(p_app_version, ''), 80), left(coalesce(p_browser_summary, ''), 240), public.safe_app_context(coalesce(p_metadata, '{}'::jsonb)))
  returning id into error_id;
  return jsonb_build_object('id', error_id);
end;
$$;

create or replace function public.rpc_list_platform_errors()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if not public.has_platform_permission('platform.system_errors.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.last_seen_at desc), '[]'::jsonb)
  into result
  from (
    select coalesce(error_code, 'UNKNOWN') as error_code, coalesce(route, 'unknown') as route, count(*)::integer as occurrences, max(created_at) as last_seen_at
    from public.frontend_error_reports
    where created_at >= now() - interval '14 days'
    group by coalesce(error_code, 'UNKNOWN'), coalesce(route, 'unknown')
  ) row_data;
  return result;
end;
$$;

create or replace function public.rpc_list_feature_flags(p_tenant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if p_tenant_id is null then
    if not public.has_platform_permission('platform.features.view') then
      raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
    end if;
  elsif not (public.is_active_tenant_member(p_tenant_id) or public.has_platform_permission('platform.features.view')) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.key), '[]'::jsonb)
  into result
  from (
    select ff.key, ff.description, ff.enabled_globally, ff.beta_only, tff.tenant_id, coalesce(tff.override, 'INHERIT') as override,
      case when p_tenant_id is null then ff.enabled_globally else public.has_feature(p_tenant_id, ff.key) end as enabled
    from public.feature_flags ff
    left join public.tenant_feature_flags tff on p_tenant_id is not null and tff.tenant_id = p_tenant_id and tff.feature_key = ff.key
  ) row_data;
  return result;
end;
$$;

create or replace function public.rpc_set_feature_flag(p_feature_key text, p_enabled_globally boolean, p_beta_only boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.has_platform_permission('platform.features.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  update public.feature_flags
  set enabled_globally = p_enabled_globally,
      beta_only = coalesce(p_beta_only, beta_only)
  where key = p_feature_key;
  return public.rpc_list_feature_flags(null);
end;
$$;

create or replace function public.rpc_set_tenant_feature_flag(p_tenant_id uuid, p_feature_key text, p_override text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.has_platform_permission('platform.features.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  insert into public.tenant_feature_flags (tenant_id, feature_key, override, updated_by)
  values (p_tenant_id, p_feature_key, p_override, auth.uid())
  on conflict (tenant_id, feature_key) do update set override = excluded.override, updated_by = excluded.updated_by;
  return public.rpc_list_feature_flags(p_tenant_id);
end;
$$;

create or replace function public.rpc_extend_tenant_trial(p_tenant_id uuid, p_days integer, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings public.platform_settings%rowtype;
  sub public.tenant_subscriptions%rowtype;
  previous_end timestamptz;
  new_end timestamptz;
begin
  if not public.has_platform_permission('platform.subscriptions.manage') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_days <= 0 then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  select * into settings from public.platform_settings where id = true;
  if p_days > settings.max_trial_extension_days then
    raise exception 'TRIAL_EXTENSION_TOO_LARGE' using errcode = '22023';
  end if;
  select * into sub
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id and status in ('TRIAL', 'ACTIVE', 'PAST_DUE')
  order by created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = '22023';
  end if;
  previous_end := sub.trial_ends_at;
  new_end := coalesce(greatest(sub.trial_ends_at, now()), now()) + make_interval(days => p_days);
  update public.tenant_subscriptions set trial_ends_at = new_end, status = 'TRIAL' where id = sub.id;
  update public.tenants set status = 'TRIAL', commercial_status = 'TRIAL' where id = p_tenant_id and status <> 'SUSPENDED';
  perform public.write_audit_log(p_tenant_id, 'TENANT_TRIAL_EXTENDED', 'tenant_subscription', sub.id, null, jsonb_build_object('trialEndsAt', previous_end), jsonb_build_object('trialEndsAt', new_end, 'days', p_days), p_reason);
  return jsonb_build_object('tenantId', p_tenant_id, 'previousTrialEnd', previous_end, 'newTrialEnd', new_end);
end;
$$;

create or replace function public.rpc_start_support_access_session(p_tenant_id uuid, p_scope text, p_reason text, p_minutes integer default 15)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  platform_id uuid;
  session_record public.support_access_sessions%rowtype;
begin
  if not public.has_platform_permission('platform.support_session.start') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;
  select id into platform_id from public.platform_users where user_id = auth.uid() and status = 'ACTIVE' limit 1;
  insert into public.support_access_sessions (tenant_id, platform_user_id, scope, requested_reason, expires_at)
  values (p_tenant_id, platform_id, p_scope, p_reason, now() + make_interval(mins => least(greatest(coalesce(p_minutes, 15), 1), 60)))
  returning * into session_record;
  perform public.write_audit_log(p_tenant_id, 'SUPPORT_SESSION_STARTED', 'support_access_session', session_record.id, null, null, jsonb_build_object('scope', p_scope, 'expiresAt', session_record.expires_at), p_reason);
  return to_jsonb(session_record);
end;
$$;

create or replace function public.tenant_health_state(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with tenant_row as (
    select * from public.tenants where id = p_tenant_id
  ), sub as (
    select ts.*, sp.max_active_events, sp.max_members, sp.max_users, sp.included_sms
    from public.tenant_subscriptions ts
    join public.subscription_plans sp on sp.id = ts.plan_id
    where ts.tenant_id = p_tenant_id
    order by ts.created_at desc
    limit 1
  ), signals as (
    select
      (select count(*) from public.sms_outbox where tenant_id = p_tenant_id and status = 'FAILED')::integer as failed_sms,
      (select count(*) from public.events where tenant_id = p_tenant_id and status in ('DRAFT', 'ACTIVE'))::integer as active_events,
      (select count(*) from public.members where tenant_id = p_tenant_id and status = 'ACTIVE')::integer as members,
      (select count(*) from public.tenant_users where tenant_id = p_tenant_id and status = 'ACTIVE')::integer as users,
      (select max(created_at) from public.audit_logs where tenant_id = p_tenant_id) as last_activity_at
  )
  select jsonb_build_object(
    'state', case
      when tenant_row.status in ('SUSPENDED', 'CANCELLED', 'ARCHIVED') then 'BLOCKED'
      when signals.failed_sms > 0 or signals.active_events = 0 or (sub.trial_ends_at is not null and sub.trial_ends_at < now()) then 'ATTENTION'
      else 'HEALTHY'
    end,
    'warning', case
      when tenant_row.status in ('SUSPENDED', 'CANCELLED', 'ARCHIVED') then 'Tenant access is blocked'
      when signals.failed_sms > 0 then 'Failed SMS backlog exists'
      when signals.active_events = 0 then 'No active event'
      when sub.trial_ends_at is not null and sub.trial_ends_at < now() then 'Trial has ended'
      else null
    end,
    'failedSmsBacklog', signals.failed_sms,
    'activeEvents', signals.active_events,
    'members', signals.members,
    'users', signals.users,
    'lastActivityAt', signals.last_activity_at
  )
  from tenant_row
  cross join signals
  left join sub on true;
$$;

create or replace function public.tenant_activation_milestones(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'tenantCreated', exists(select 1 from public.tenants where id = p_tenant_id),
    'eventCreated', exists(select 1 from public.events where tenant_id = p_tenant_id),
    'memberCreated', exists(select 1 from public.members where tenant_id = p_tenant_id),
    'pledgeRecorded', exists(select 1 from public.pledges where tenant_id = p_tenant_id),
    'paymentRecorded', exists(select 1 from public.payments where tenant_id = p_tenant_id),
    'receiptGenerated', exists(select 1 from public.receipts where tenant_id = p_tenant_id),
    'smsSent', exists(select 1 from public.sms_outbox where tenant_id = p_tenant_id and status in ('SENT', 'DELIVERED')),
    'reportViewedOrExported', exists(select 1 from public.product_events where tenant_id = p_tenant_id and event_name in ('REPORT_VIEWED', 'REPORT_EXPORTED'))
  );
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
      t.id, t.code, t.name, t.phone_e164, t.email, t.status, t.lifecycle_tag, t.commercial_status, t.operational_notice, t.created_at,
      sp.code as plan_code, sp.name as plan_name, ts.status as subscription_status, ts.trial_ends_at, ts.current_period_end,
      greatest(ceil(extract(epoch from (ts.trial_ends_at - now())) / 86400), 0)::integer as trial_days_remaining,
      (select count(*)::integer from public.events e where e.tenant_id = t.id and e.status in ('DRAFT', 'ACTIVE')) as active_event_count,
      (select count(*)::integer from public.members m where m.tenant_id = t.id and m.status = 'ACTIVE') as member_count,
      (select count(*)::integer from public.tenant_users tu where tu.tenant_id = t.id and tu.status = 'ACTIVE') as user_count,
      (select count(*)::integer from public.sms_outbox so where so.tenant_id = t.id and so.status in ('SENT', 'DELIVERED')) as sms_sent_count,
      (select count(*)::integer from public.sms_outbox so where so.tenant_id = t.id and so.status = 'FAILED') as failed_sms_count,
      owner_profile.full_name as owner_name, owner_profile.phone_e164 as owner_phone, owner_profile.email as owner_email,
      public.tenant_health_state(t.id) ->> 'state' as health,
      public.tenant_health_state(t.id) ->> 'warning' as health_warning,
      public.tenant_health_state(t.id) ->> 'lastActivityAt' as last_activity_at
    from public.tenants t
    left join lateral (select * from public.tenant_subscriptions current_ts where current_ts.tenant_id = t.id order by current_ts.created_at desc limit 1) ts on true
    left join public.subscription_plans sp on sp.id = ts.plan_id
    left join lateral (
      select p.*
      from public.tenant_users owner_tu
      join public.profiles p on p.id = owner_tu.user_id
      where owner_tu.tenant_id = t.id and owner_tu.status = 'ACTIVE' and owner_tu.is_owner = true
      order by owner_tu.created_at
      limit 1
    ) owner_profile on true
  ) row_data;

  return result;
end;
$$;

create or replace function public.rpc_get_platform_tenant_detail(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if not public.has_platform_permission('platform.tenants.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'tenant', to_jsonb(t),
    'subscription', to_jsonb(ts) || jsonb_build_object('planCode', sp.code, 'planName', sp.name),
    'owner', to_jsonb(owner_profile),
    'health', public.tenant_health_state(p_tenant_id),
    'activation', public.tenant_activation_milestones(p_tenant_id),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'status', e.status, 'eventDate', e.event_date) order by e.created_at desc) from public.events e where e.tenant_id = p_tenant_id), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object('id', tu.id, 'status', tu.status, 'isOwner', tu.is_owner, 'fullName', p.full_name, 'phone', p.phone_e164) order by tu.created_at) from public.tenant_users tu join public.profiles p on p.id = tu.user_id where tu.tenant_id = p_tenant_id), '[]'::jsonb),
    'supportRequests', coalesce((select jsonb_agg(to_jsonb(sr) order by sr.created_at desc) from public.support_requests sr where sr.tenant_id = p_tenant_id), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('action', al.action, 'entityType', al.entity_type, 'reason', al.reason, 'createdAt', al.created_at) order by al.created_at desc) from public.audit_logs al where al.tenant_id = p_tenant_id limit 50), '[]'::jsonb)
  )
  into result
  from public.tenants t
  left join lateral (select * from public.tenant_subscriptions where tenant_id = t.id order by created_at desc limit 1) ts on true
  left join public.subscription_plans sp on sp.id = ts.plan_id
  left join lateral (
    select p.full_name, p.phone_e164, p.email
    from public.tenant_users owner_tu
    join public.profiles p on p.id = owner_tu.user_id
    where owner_tu.tenant_id = t.id and owner_tu.status = 'ACTIVE' and owner_tu.is_owner = true
    order by owner_tu.created_at
    limit 1
  ) owner_profile on true
  where t.id = p_tenant_id;
  return result;
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
    'betaTenants', (select count(*) from public.tenants where lifecycle_tag in ('BETA', 'PILOT')),
    'totalEvents', (select count(*) from public.events),
    'subscriptionsExpiringSoon', (select count(*) from public.tenant_subscriptions where status in ('TRIAL', 'ACTIVE') and coalesce(trial_ends_at, current_period_end) is not null and coalesce(trial_ends_at, current_period_end) <= now() + interval '14 days'),
    'openSupportRequests', (select count(*) from public.support_requests where status in ('OPEN', 'IN_PROGRESS', 'WAITING_CUSTOMER')),
    'failedSmsBacklog', (select count(*) from public.sms_outbox where status = 'FAILED'),
    'recentSystemErrors', (select count(*) from public.frontend_error_reports where created_at >= now() - interval '24 hours')
  );
end;
$$;

create or replace function public.rpc_get_platform_beta_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  settings jsonb;
begin
  if not public.has_platform_permission('platform.beta.view') then
    raise exception 'PLATFORM_ACCESS_DENIED' using errcode = '42501';
  end if;
  settings := public.rpc_get_rollout_settings_public();
  return jsonb_build_object(
    'settings', settings,
    'invitations', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'suffix', display_code_suffix, 'status', status, 'intendedName', intended_name, 'intendedPhone', intended_phone_e164, 'maxUses', max_uses, 'useCount', use_count, 'expiresAt', expires_at, 'createdAt', created_at) order by created_at desc) from public.beta_invitations limit 100), '[]'::jsonb),
    'recentRegistrations', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name, 'status', t.status, 'createdAt', t.created_at, 'health', public.tenant_health_state(t.id) ->> 'state') order by t.created_at desc) from public.tenants t where t.created_at >= now() - interval '30 days' limit 25), '[]'::jsonb),
    'onboardingFunnel', coalesce((select jsonb_object_agg(event_name, count) from (select event_name, count(*)::integer from public.product_events where event_name in ('REGISTRATION_STARTED','OTP_VERIFIED','PIN_CONFIGURED','PACKAGE_SELECTED','ORGANIZATION_COMPLETED','ADMIN_PROFILE_COMPLETED','FIRST_EVENT_COMPLETED','TENANT_CREATED','ONBOARDING_COMPLETED') and created_at >= now() - interval '30 days' group by event_name) f), '{}'::jsonb),
    'health', jsonb_build_object('attentionTenants', (select count(*) from public.tenants t where public.tenant_health_state(t.id) ->> 'state' = 'ATTENTION'), 'blockedTenants', (select count(*) from public.tenants t where public.tenant_health_state(t.id) ->> 'state' = 'BLOCKED'), 'failedSmsBacklog', (select count(*) from public.sms_outbox where status = 'FAILED'), 'openSupportRequests', (select count(*) from public.support_requests where status in ('OPEN','IN_PROGRESS','WAITING_CUSTOMER'))),
    'feedback', coalesce((select jsonb_agg(jsonb_build_object('id', pf.id, 'category', pf.category, 'message', left(pf.message, 180), 'status', pf.status, 'tenantName', t.name, 'createdAt', pf.created_at) order by pf.created_at desc) from public.product_feedback pf left join public.tenants t on t.id = pf.tenant_id limit 20), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rpc_track_product_event(p_event_name text, p_tenant_id uuid default null, p_correlation_id text default null, p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  event_id bigint;
begin
  if auth.uid() is not null and p_tenant_id is not null and not public.is_tenant_member(p_tenant_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  insert into public.product_events (event_name, tenant_id, user_id, correlation_id, metadata)
  values (upper(btrim(p_event_name)), p_tenant_id, auth.uid(), left(coalesce(p_correlation_id, ''), 120), coalesce(p_metadata, '{}'::jsonb) - 'otp' - 'pin' - 'password' - 'accessToken' - 'smsPassword')
  returning id into event_id;
  return jsonb_build_object('id', event_id);
end;
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
      'platform.dashboard.view','platform.tenants.view','platform.tenants.manage','platform.plans.view','platform.plans.manage','platform.subscriptions.manage','platform.sms.view','platform.audit.view','platform.settings.manage',
      'platform.beta.view','platform.beta.manage','platform.support.view','platform.support.manage','platform.feedback.view','platform.features.view','platform.features.manage','platform.system_errors.view','platform.support_session.start'
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
      when pu.role = 'PLATFORM_ADMIN' then '["platform.dashboard.view","platform.tenants.view","platform.tenants.manage","platform.plans.view","platform.plans.manage","platform.subscriptions.manage","platform.sms.view","platform.beta.view","platform.beta.manage","platform.support.view","platform.support.manage","platform.feedback.view","platform.features.view","platform.features.manage","platform.system_errors.view"]'::jsonb
      when pu.role = 'PLATFORM_SUPPORT' then '["platform.dashboard.view","platform.tenants.view","platform.sms.view","platform.support.view","platform.support.manage","platform.feedback.view","platform.system_errors.view"]'::jsonb
      when pu.role = 'PLATFORM_AUDITOR' then '["platform.dashboard.view","platform.audit.view","platform.system_errors.view"]'::jsonb
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

drop policy if exists platform_settings_platform_select on public.platform_settings;
create policy platform_settings_platform_select on public.platform_settings for select using (public.is_platform_user());
drop policy if exists beta_invitations_platform_select on public.beta_invitations;
create policy beta_invitations_platform_select on public.beta_invitations for select using (public.has_platform_permission('platform.beta.view'));
drop policy if exists support_requests_tenant_or_platform_select on public.support_requests;
create policy support_requests_tenant_or_platform_select on public.support_requests for select using (public.is_active_tenant_member(tenant_id) or public.has_platform_permission('platform.support.view'));
drop policy if exists support_request_notes_visibility_select on public.support_request_notes;
create policy support_request_notes_visibility_select on public.support_request_notes for select using (
  exists (select 1 from public.support_requests sr where sr.id = request_id and (public.has_platform_permission('platform.support.view') or (visibility = 'TENANT_VISIBLE' and public.is_active_tenant_member(sr.tenant_id))))
);
drop policy if exists product_feedback_platform_select on public.product_feedback;
create policy product_feedback_platform_select on public.product_feedback for select using (public.has_platform_permission('platform.feedback.view'));
drop policy if exists feature_flags_select on public.feature_flags;
create policy feature_flags_select on public.feature_flags for select using (true);
drop policy if exists tenant_feature_flags_select on public.tenant_feature_flags;
create policy tenant_feature_flags_select on public.tenant_feature_flags for select using (public.is_active_tenant_member(tenant_id) or public.has_platform_permission('platform.features.view'));
drop policy if exists frontend_error_reports_platform_select on public.frontend_error_reports;
create policy frontend_error_reports_platform_select on public.frontend_error_reports for select using (public.has_platform_permission('platform.system_errors.view'));
drop policy if exists beta_notices_select on public.beta_notices;
create policy beta_notices_select on public.beta_notices for select using (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now()));
drop policy if exists support_access_sessions_platform_select on public.support_access_sessions;
create policy support_access_sessions_platform_select on public.support_access_sessions for select using (public.has_platform_permission('platform.support.view'));

grant execute on function public.beta_invitation_hash(text) to authenticated, anon;
grant execute on function public.rpc_get_rollout_settings_public() to authenticated, anon;
grant execute on function public.rpc_validate_beta_invitation(text, text) to authenticated, anon;
grant execute on function public.rpc_consume_beta_invitation(text, uuid) to authenticated;
grant execute on function public.rpc_create_beta_invitation(text, text, text, text, uuid, integer, integer, timestamptz) to authenticated;
grant execute on function public.rpc_revoke_beta_invitation(uuid) to authenticated;
grant execute on function public.rpc_update_rollout_settings(text, boolean, integer, text, text, text, text, text) to authenticated;
grant execute on function public.rpc_get_platform_beta_dashboard() to authenticated;
grant execute on function public.rpc_get_platform_tenant_detail(uuid) to authenticated;
grant execute on function public.rpc_extend_tenant_trial(uuid, integer, text) to authenticated;
grant execute on function public.rpc_create_support_request(uuid, text, text, text, uuid, text, jsonb) to authenticated;
grant execute on function public.rpc_list_my_support_requests(uuid) to authenticated;
grant execute on function public.rpc_list_platform_support_requests() to authenticated;
grant execute on function public.rpc_update_support_request(uuid, text, text, uuid, text) to authenticated;
grant execute on function public.rpc_create_feedback(uuid, text, text, uuid, text, jsonb) to authenticated;
grant execute on function public.rpc_list_platform_feedback() to authenticated;
grant execute on function public.rpc_report_frontend_error(uuid, text, text, text, text, text, text, jsonb) to authenticated;
grant execute on function public.rpc_list_platform_errors() to authenticated;
grant execute on function public.rpc_list_feature_flags(uuid) to authenticated;
grant execute on function public.rpc_set_feature_flag(text, boolean, boolean) to authenticated;
grant execute on function public.rpc_set_tenant_feature_flag(uuid, text, text) to authenticated;
grant execute on function public.has_feature(uuid, text) to authenticated;
grant execute on function public.rpc_start_support_access_session(uuid, text, text, integer) to authenticated;
grant execute on function public.rpc_track_product_event(text, uuid, text, jsonb) to authenticated, anon;
