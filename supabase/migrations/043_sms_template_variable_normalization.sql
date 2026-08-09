create or replace function public.normalize_sms_template_variable_name(p_variable text)
returns text
language sql
immutable
as $$
  select regexp_replace(regexp_replace(lower(btrim(coalesce(p_variable, ''))), '[^a-z0-9]+', '_', 'g'), '^_+|_+$', '', 'g');
$$;

create or replace function public.validate_sms_template_body()
returns trigger
language plpgsql
as $$
declare
  variable_name text;
  normalized_variable text;
  allowed jsonb;
begin
  new.code := upper(btrim(new.code));
  new.body := btrim(new.body);
  new.allowed_variables := public.sms_template_allowed_variables(new.code);
  if jsonb_array_length(new.allowed_variables) = 0 then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  if length(new.body) > 918 or new.body ~ '<[^>]+>' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  for variable_name in
    select distinct match[1]
    from regexp_matches(new.body, '\{\{\s*([^{}]+?)\s*\}\}', 'g') as match
  loop
    normalized_variable := public.normalize_sms_template_variable_name(variable_name);
    if normalized_variable in ('password', 'pin', 'otp') or not exists (
      select 1
      from jsonb_array_elements_text(new.allowed_variables) allowed_value(value)
      where allowed_value.value = normalized_variable
         or replace(allowed_value.value, '_', '') = replace(normalized_variable, '_', '')
    ) then
      raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$$;

grant execute on function public.normalize_sms_template_variable_name(text) to authenticated;

create or replace function public.rpc_upsert_sms_template(p_tenant_id uuid, p_code text, p_body text, p_language text default 'sw')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  normalized_body text := btrim(coalesce(p_body, ''));
  display_name text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'messages.manage_templates') then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if normalized_body = '' then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  display_name := case normalized_code
    when 'PLEDGE_REQUEST' then 'Pledge Request'
    when 'PLEDGE_REGISTRATION' then 'Pledge Registration'
    when 'PAYMENT_CONFIRMATION' then 'Payment Confirmation'
    when 'BALANCE_REMINDER' then 'Balance Reminder'
    when 'PLEDGE_COMPLETED' then 'Pledge Completed'
    else null
  end;
  if display_name is null then
    raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  insert into public.sms_templates (tenant_id, code, name, channel, body, language, is_system, is_active, allowed_variables)
  values (p_tenant_id, normalized_code, display_name, 'SMS', normalized_body, coalesce(nullif(p_language, ''), 'sw'), false, true, public.sms_template_allowed_variables(normalized_code))
  on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, language)
  do update set body = excluded.body, name = excluded.name, is_active = true, allowed_variables = excluded.allowed_variables, updated_at = now();
  return public.sms_template_detail(p_tenant_id, normalized_code, coalesce(nullif(p_language, ''), 'sw'));
end;
$$;

grant execute on function public.rpc_upsert_sms_template(uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
