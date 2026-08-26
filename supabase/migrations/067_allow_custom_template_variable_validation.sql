-- The sms_templates_validate_body trigger (043_sms_template_variable_normalization.sql)
-- rejects any row whose code has no entry in sms_template_allowed_variables(), which is
-- every genuinely custom (CUSTOM_-prefixed) template code. Special-case those codes to
-- only allow {{member_name}}, instead of unconditionally rejecting them.

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
  if new.code like 'CUSTOM\_%' escape '\' then
    new.allowed_variables := '["member_name"]'::jsonb;
  else
    new.allowed_variables := public.sms_template_allowed_variables(new.code);
    if jsonb_array_length(new.allowed_variables) = 0 then
      raise exception 'SMS_TEMPLATE_INVALID' using errcode = '22023';
    end if;
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

notify pgrst, 'reload schema';
