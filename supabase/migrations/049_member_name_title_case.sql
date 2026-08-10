create or replace function public.title_case_person_name(p_name text)
returns text
language sql
immutable
as $$
  select initcap(lower(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g')));
$$;

create or replace function public.validate_member_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' and new.tenant_id <> old.tenant_id then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;

  new.full_name := public.title_case_person_name(new.full_name);
  new.email := nullif(btrim(coalesce(new.email, '')), '');
  new.phone_e164 := case when new.phone_e164 is null or btrim(new.phone_e164) = '' then null else public.normalize_tz_phone(new.phone_e164) end;
  new.alternative_phone_e164 := case when new.alternative_phone_e164 is null or btrim(new.alternative_phone_e164) = '' then null else public.normalize_tz_phone(new.alternative_phone_e164) end;

  if new.status = 'ARCHIVED' and new.archived_at is null then
    new.archived_at := now();
  end if;
  if new.status <> 'ARCHIVED' then
    new.archived_at := null;
    new.archived_by := null;
  end if;

  return new;
exception
  when unique_violation then
    raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505';
end;
$$;

update public.members
set full_name = public.title_case_person_name(full_name)
where full_name is distinct from public.title_case_person_name(full_name);

grant execute on function public.title_case_person_name(text) to authenticated;
