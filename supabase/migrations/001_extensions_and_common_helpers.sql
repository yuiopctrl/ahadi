create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create sequence if not exists public.tenant_code_seq start 1;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.normalize_tz_phone(raw_phone text)
returns text
language plpgsql
immutable
as $$
declare
  digits text;
begin
  digits := regexp_replace(coalesce(raw_phone, ''), '[^0-9+]', '', 'g');
  if digits like '+%' then
    digits := '+' || regexp_replace(substr(digits, 2), '[^0-9]', '', 'g');
  else
    digits := regexp_replace(digits, '[^0-9]', '', 'g');
  end if;

  if digits ~ '^\+255[67][0-9]{8}$' then
    return digits;
  elsif digits ~ '^255[67][0-9]{8}$' then
    return '+' || digits;
  elsif digits ~ '^0[67][0-9]{8}$' then
    return '+255' || substr(digits, 2);
  end if;

  raise exception 'INVALID_PHONE' using errcode = '22023';
end;
$$;

create or replace function public.slugify(value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(value, 'tenant')), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function public.generate_tenant_code()
returns text
language sql
as $$
  select 'AHD-' || lpad(nextval('public.tenant_code_seq')::text, 6, '0');
$$;

create or replace function public.generate_unique_tenant_slug(tenant_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  base_slug text;
  candidate text;
  suffix integer := 0;
begin
  base_slug := nullif(public.slugify(tenant_name), '');
  if base_slug is null then
    base_slug := 'tenant';
  end if;

  loop
    candidate := case when suffix = 0 then base_slug else base_slug || '-' || suffix::text end;
    exit when not exists (select 1 from public.tenants where slug = candidate);
    suffix := suffix + 1;
  end loop;

  return candidate;
end;
$$;
