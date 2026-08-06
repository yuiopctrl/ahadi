create table public.audit_logs (
  id bigint generated always as identity primary key,
  tenant_id uuid references public.tenants(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_platform_user_id uuid references public.platform_users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  event_id uuid references public.events(id) on delete set null,
  old_values jsonb,
  new_values jsonb,
  reason text,
  request_id text,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index audit_logs_tenant_created_idx on public.audit_logs(tenant_id, created_at desc);
create index audit_logs_actor_created_idx on public.audit_logs(actor_user_id, created_at desc);
create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id);
create index audit_logs_action_idx on public.audit_logs(action);
create index audit_logs_event_id_idx on public.audit_logs(event_id);

create or replace function public.write_audit_log(
  p_tenant_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_event_id uuid default null,
  p_old_values jsonb default null,
  p_new_values jsonb default null,
  p_reason text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_id bigint;
  platform_id uuid;
begin
  select id into platform_id
  from public.platform_users
  where user_id = auth.uid() and status = 'ACTIVE'
  limit 1;

  insert into public.audit_logs (
    tenant_id,
    actor_user_id,
    actor_platform_user_id,
    action,
    entity_type,
    entity_id,
    event_id,
    old_values,
    new_values,
    reason
  )
  values (
    p_tenant_id,
    auth.uid(),
    platform_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_event_id,
    p_old_values,
    p_new_values,
    p_reason
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;
