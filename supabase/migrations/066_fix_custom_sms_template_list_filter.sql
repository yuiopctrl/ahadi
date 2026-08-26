-- rpc_list_custom_sms_templates incorrectly returned tenant-specific overrides of
-- built-in template bodies (is_system = false rows that reuse a system template's
-- code, e.g. BALANCE_REMINDER) as if they were genuine custom templates. Exclude
-- any row whose code matches a system template's code.

create or replace function public.rpc_list_custom_sms_templates(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then raise exception 'SESSION_REQUIRED' using errcode = '28000'; end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.send') then raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'; end if;

  select coalesce(jsonb_agg(public.custom_sms_template_json(t) order by t.created_at desc), '[]'::jsonb)
  into result
  from public.sms_templates t
  where t.tenant_id = p_tenant_id
    and t.is_system = false
    and not exists (
      select 1 from public.sms_templates sys
      where sys.code = t.code and sys.is_system = true
    );

  return result;
end;
$$;

notify pgrst, 'reload schema';
