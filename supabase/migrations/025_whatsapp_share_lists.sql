insert into public.permissions (code, name, description) values
('shares.whatsapp.view', 'View WhatsApp share lists', 'Generate privacy-friendly event contributor lists for sharing'),
('shares.whatsapp.financial', 'View financial WhatsApp share lists', 'Generate contributor lists that include pledged, paid, or outstanding amounts')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('shares.whatsapp.view', 'shares.whatsapp.financial')
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER', 'COLLECTOR')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'shares.whatsapp.view'
where r.code = 'VIEWER'
on conflict do nothing;

create table if not exists public.event_share_settings (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  event_id uuid primary key references public.events(id) on delete cascade,
  whatsapp_header_text text,
  whatsapp_footer_text text,
  include_event_name boolean not null default true,
  include_event_date boolean not null default false,
  include_event_payment_instructions boolean not null default false,
  include_mobile_money_instructions boolean not null default false,
  include_bank_instructions boolean not null default false,
  default_list_format text not null default 'DETAILED' check (default_list_format in ('DETAILED', 'PRIVACY', 'PAYMENT_PROGRESS', 'OUTSTANDING_FOLLOW_UP')),
  default_sort text not null default 'ORIGINAL' check (default_sort in ('ORIGINAL', 'NAME_ASC', 'PLEDGED_DESC', 'PAID_FIRST', 'OUTSTANDING_FIRST')),
  default_include_summary boolean not null default true,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, event_id)
);

create index if not exists event_share_settings_tenant_idx on public.event_share_settings(tenant_id);

drop trigger if exists event_share_settings_set_updated_at on public.event_share_settings;
create trigger event_share_settings_set_updated_at
before update on public.event_share_settings
for each row execute function public.set_updated_at();

alter table public.event_share_settings enable row level security;

drop policy if exists event_share_settings_select on public.event_share_settings;
create policy event_share_settings_select on public.event_share_settings
for select using (public.has_tenant_permission(tenant_id, 'shares.whatsapp.view'));

drop policy if exists event_share_settings_manage on public.event_share_settings;
create policy event_share_settings_manage on public.event_share_settings
for all using (public.has_tenant_permission(tenant_id, 'shares.whatsapp.financial'))
with check (public.has_tenant_permission(tenant_id, 'shares.whatsapp.financial'));

create or replace function public.whatsapp_single_line(p_text text)
returns text
language sql
stable
as $$
  select btrim(regexp_replace(regexp_replace(coalesce(p_text, ''), '[[:cntrl:]]+', ' ', 'g'), '\s+', ' ', 'g'));
$$;

create or replace function public.whatsapp_plain_text(p_text text)
returns text
language sql
stable
as $$
  select btrim(regexp_replace(replace(replace(regexp_replace(coalesce(p_text, ''), '<[^>]*>', '', 'g'), chr(13), chr(10)), chr(9), ' '), chr(10) || '{3,}', chr(10) || chr(10), 'g'));
$$;

create or replace function public.default_whatsapp_header(p_event_type text, p_event_name text)
returns text
language sql
stable
as $$
  select case upper(coalesce(p_event_type, 'OTHER'))
    when 'WEDDING' then '*AHADI ZA HARUSI YA ' || upper(public.whatsapp_single_line(p_event_name)) || '*'
    when 'SENDOFF' then '*AHADI ZA SENDOFF YA ' || upper(public.whatsapp_single_line(p_event_name)) || '*'
    else '*ORODHA YA AHADI - ' || upper(public.whatsapp_single_line(p_event_name)) || '*'
  end;
$$;

create or replace function public.whatsapp_share_summary(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with pledge_state as (
    select
      p.id,
      p.pledged_amount,
      least(coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), p.pledged_amount)::numeric(18,2) as paid_amount,
      greatest(p.pledged_amount - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
      coalesce(p.due_date, e.pledge_deadline) as effective_due_date
    from public.pledges p
    join public.events e on e.id = p.event_id
    join public.event_members em on em.id = p.event_member_id
    where p.tenant_id = p_tenant_id
      and p.event_id = p_event_id
      and p.status <> 'CANCELLED'
      and em.status = 'ACTIVE'
  )
  select jsonb_build_object(
    'totalPledged', coalesce(sum(pledged_amount), 0)::numeric(18,2),
    'totalPaid', coalesce(sum(paid_amount), 0)::numeric(18,2),
    'outstanding', coalesce(sum(outstanding_amount), 0)::numeric(18,2),
    'paidCount', count(*) filter (where outstanding_amount <= 0),
    'partialCount', count(*) filter (where outstanding_amount > 0 and paid_amount > 0),
    'pendingCount', count(*) filter (where outstanding_amount > 0 and paid_amount <= 0),
    'overdueCount', count(*) filter (where outstanding_amount > 0 and effective_due_date is not null and effective_due_date < current_date)
  )
  from pledge_state;
$$;

create or replace function public.rpc_get_event_whatsapp_share_settings(p_tenant_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  event_record public.events%rowtype;
  settings_record public.event_share_settings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found or not public.can_access_event(p_event_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'shares.whatsapp.view') then
    raise exception 'SHARE_WHATSAPP_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into settings_record from public.event_share_settings where tenant_id = p_tenant_id and event_id = p_event_id;

  return jsonb_build_object(
    'headerText', settings_record.whatsapp_header_text,
    'footerText', settings_record.whatsapp_footer_text,
    'defaultHeaderText', public.default_whatsapp_header(event_record.event_type, event_record.name),
    'includeEventName', coalesce(settings_record.include_event_name, true),
    'includeEventDate', coalesce(settings_record.include_event_date, false),
    'includeEventPaymentInstructions', coalesce(settings_record.include_event_payment_instructions, false),
    'includeMobileMoneyInstructions', coalesce(settings_record.include_mobile_money_instructions, false),
    'includeBankInstructions', coalesce(settings_record.include_bank_instructions, false),
    'defaultListFormat', coalesce(settings_record.default_list_format, 'DETAILED'),
    'defaultSort', coalesce(settings_record.default_sort, 'ORIGINAL'),
    'defaultIncludeSummary', coalesce(settings_record.default_include_summary, true),
    'canUseFinancialFormats', public.has_tenant_permission(p_tenant_id, 'shares.whatsapp.financial')
  );
end;
$$;

create or replace function public.rpc_update_event_whatsapp_share_settings(
  p_tenant_id uuid,
  p_event_id uuid,
  p_header_text text default null,
  p_footer_text text default null,
  p_include_event_name boolean default true,
  p_include_event_date boolean default false,
  p_include_event_payment_instructions boolean default false,
  p_include_mobile_money_instructions boolean default false,
  p_include_bank_instructions boolean default false,
  p_default_list_format text default 'DETAILED',
  p_default_sort text default 'ORIGINAL',
  p_default_include_summary boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_format text := upper(coalesce(p_default_list_format, 'DETAILED'));
  normalized_sort text := upper(coalesce(p_default_sort, 'ORIGINAL'));
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform 1 from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found or not public.can_access_event(p_event_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'shares.whatsapp.financial') then
    raise exception 'SHARE_SETTINGS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if normalized_format not in ('DETAILED', 'PRIVACY', 'PAYMENT_PROGRESS', 'OUTSTANDING_FOLLOW_UP') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if normalized_sort not in ('ORIGINAL', 'NAME_ASC', 'PLEDGED_DESC', 'PAID_FIRST', 'OUTSTANDING_FIRST') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  insert into public.event_share_settings (
    tenant_id,
    event_id,
    whatsapp_header_text,
    whatsapp_footer_text,
    include_event_name,
    include_event_date,
    include_event_payment_instructions,
    include_mobile_money_instructions,
    include_bank_instructions,
    default_list_format,
    default_sort,
    default_include_summary,
    updated_by
  )
  values (
    p_tenant_id,
    p_event_id,
    nullif(public.whatsapp_plain_text(p_header_text), ''),
    nullif(public.whatsapp_plain_text(p_footer_text), ''),
    coalesce(p_include_event_name, true),
    coalesce(p_include_event_date, false),
    coalesce(p_include_event_payment_instructions, false),
    coalesce(p_include_mobile_money_instructions, false),
    coalesce(p_include_bank_instructions, false),
    normalized_format,
    normalized_sort,
    coalesce(p_default_include_summary, true),
    auth.uid()
  )
  on conflict (event_id) do update
  set whatsapp_header_text = excluded.whatsapp_header_text,
      whatsapp_footer_text = excluded.whatsapp_footer_text,
      include_event_name = excluded.include_event_name,
      include_event_date = excluded.include_event_date,
      include_event_payment_instructions = excluded.include_event_payment_instructions,
      include_mobile_money_instructions = excluded.include_mobile_money_instructions,
      include_bank_instructions = excluded.include_bank_instructions,
      default_list_format = excluded.default_list_format,
      default_sort = excluded.default_sort,
      default_include_summary = excluded.default_include_summary,
      updated_by = excluded.updated_by;

  return public.rpc_get_event_whatsapp_share_settings(p_tenant_id, p_event_id);
end;
$$;

create or replace function public.rpc_generate_event_whatsapp_share_preview(
  p_tenant_id uuid,
  p_event_id uuid,
  p_format text default 'DETAILED',
  p_status_filter text default 'ALL',
  p_category_id uuid default null,
  p_sort text default 'ORIGINAL',
  p_include_summary boolean default null,
  p_include_event_date boolean default null,
  p_include_event_payment_instructions boolean default null,
  p_include_mobile_money_instructions boolean default null,
  p_include_bank_instructions boolean default null,
  p_include_without_pledges boolean default false,
  p_phone_filter text default 'ALL',
  p_search text default '',
  p_safe_char_limit integer default 3500
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  event_record public.events%rowtype;
  settings_record public.event_share_settings%rowtype;
  tenant_settings_record public.tenant_settings%rowtype;
  normalized_format text := upper(coalesce(p_format, 'DETAILED'));
  normalized_status text := upper(coalesce(p_status_filter, 'ALL'));
  normalized_sort text := upper(coalesce(p_sort, 'ORIGINAL'));
  normalized_phone_filter text := upper(coalesce(p_phone_filter, 'ALL'));
  can_financial boolean;
  effective_include_summary boolean;
  effective_include_event_date boolean;
  effective_include_event_payment boolean;
  effective_include_mobile_money boolean;
  effective_include_bank boolean;
  header_block text;
  summary_block text := '';
  payment_block text := '';
  footer_block text := '';
  tail_block text := '';
  lines text[] := array[]::text[];
  current_lines text[] := array[]::text[];
  part_texts text[] := array[]::text[];
  candidate_lines text[];
  candidate_text text;
  full_text text;
  summary jsonb;
  member_count integer := 0;
  safe_limit integer := greatest(coalesce(p_safe_char_limit, 3500), 1000);
  line text;
  total_parts integer;
  parts jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  select * into event_record from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found or not public.can_access_event(p_event_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.has_tenant_permission(p_tenant_id, 'shares.whatsapp.view') then
    raise exception 'SHARE_WHATSAPP_ACCESS_DENIED' using errcode = '42501';
  end if;

  can_financial := public.has_tenant_permission(p_tenant_id, 'shares.whatsapp.financial');
  if normalized_format not in ('DETAILED', 'PRIVACY', 'PAYMENT_PROGRESS', 'OUTSTANDING_FOLLOW_UP') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if normalized_status not in ('ALL', 'PAID', 'PARTIAL', 'UNPAID', 'OVERDUE') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if normalized_sort not in ('ORIGINAL', 'NAME_ASC', 'PLEDGED_DESC', 'PAID_FIRST', 'OUTSTANDING_FIRST') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if normalized_phone_filter not in ('ALL', 'WITH_PHONE', 'WITHOUT_PHONE') then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;
  if normalized_format <> 'PRIVACY' and not can_financial then
    raise exception 'SHARE_WHATSAPP_FINANCIAL_REQUIRED' using errcode = '42501';
  end if;
  if normalized_format = 'OUTSTANDING_FOLLOW_UP' and not public.has_tenant_permission(p_tenant_id, 'pledges.view') then
    raise exception 'SHARE_WHATSAPP_FINANCIAL_REQUIRED' using errcode = '42501';
  end if;

  select * into settings_record from public.event_share_settings where tenant_id = p_tenant_id and event_id = p_event_id;
  select * into tenant_settings_record from public.tenant_settings where tenant_id = p_tenant_id;

  effective_include_summary := coalesce(p_include_summary, case when normalized_format = 'PRIVACY' then false else coalesce(settings_record.default_include_summary, true) end);
  effective_include_event_date := coalesce(p_include_event_date, coalesce(settings_record.include_event_date, false));
  effective_include_event_payment := coalesce(p_include_event_payment_instructions, coalesce(settings_record.include_event_payment_instructions, false));
  effective_include_mobile_money := coalesce(p_include_mobile_money_instructions, coalesce(settings_record.include_mobile_money_instructions, false));
  effective_include_bank := coalesce(p_include_bank_instructions, coalesce(settings_record.include_bank_instructions, false));

  header_block := coalesce(nullif(public.whatsapp_plain_text(settings_record.whatsapp_header_text), ''), public.default_whatsapp_header(event_record.event_type, event_record.name));
  if effective_include_event_date and event_record.event_date is not null then
    header_block := header_block || E'\n' || to_char(event_record.event_date, 'DD Mon YYYY');
  end if;

  summary := public.whatsapp_share_summary(p_tenant_id, p_event_id);

  with source as (
    select
      em.id as event_member_id,
      m.id as member_id,
      m.member_code,
      public.whatsapp_single_line(m.full_name) as full_name,
      m.phone_e164,
      c.id as category_id,
      c.name as category,
      em.status as event_member_status,
      em.created_at as event_member_created_at,
      p.id as pledge_id,
      p.pledged_amount::numeric(18,2) as pledged_amount,
      least(coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), coalesce(p.pledged_amount, 0))::numeric(18,2) as total_paid,
      greatest(coalesce(p.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0)::numeric(18,2) as outstanding_amount,
      p.status as pledge_status,
      coalesce(p.due_date, event_record.pledge_deadline) as effective_due_date,
      case
        when p.id is null then 'NO_PLEDGE'
        when greatest(coalesce(p.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0) <= 0 then 'PAID'
        when coalesce(public.confirmed_pledge_allocated_amount(p.id), 0) > 0 then 'PARTIAL'
        else 'PENDING'
      end as current_status,
      case
        when p.id is not null
         and greatest(coalesce(p.pledged_amount, 0) - coalesce(public.confirmed_pledge_allocated_amount(p.id), 0), 0) > 0
         and coalesce(p.due_date, event_record.pledge_deadline) is not null
         and coalesce(p.due_date, event_record.pledge_deadline) < current_date
        then true else false
      end as is_overdue
    from public.event_members em
    join public.members m on m.id = em.member_id
    left join public.event_member_categories c on c.id = em.category_id
    left join public.pledges p on p.event_member_id = em.id and p.status <> 'CANCELLED'
    where em.tenant_id = p_tenant_id
      and em.event_id = p_event_id
      and em.status = 'ACTIVE'
      and m.status <> 'ARCHIVED'
      and (p.id is not null or (normalized_format = 'PRIVACY' and coalesce(p_include_without_pledges, false)))
      and (p_category_id is null or em.category_id = p_category_id)
      and (
        coalesce(nullif(public.whatsapp_single_line(p_search), ''), '') = ''
        or public.whatsapp_single_line(m.full_name) ilike '%' || public.whatsapp_single_line(p_search) || '%'
        or m.member_code ilike '%' || public.whatsapp_single_line(p_search) || '%'
        or coalesce(c.name, '') ilike '%' || public.whatsapp_single_line(p_search) || '%'
      )
      and (
        normalized_phone_filter = 'ALL'
        or (normalized_phone_filter = 'WITH_PHONE' and m.phone_e164 is not null)
        or (normalized_phone_filter = 'WITHOUT_PHONE' and m.phone_e164 is null)
      )
  ),
  filtered as (
    select *
    from source
    where normalized_status = 'ALL'
       or (normalized_status = 'PAID' and current_status = 'PAID')
       or (normalized_status = 'PARTIAL' and current_status = 'PARTIAL')
       or (normalized_status = 'UNPAID' and current_status = 'PENDING')
       or (normalized_status = 'OVERDUE' and is_overdue)
  ),
  rendered as (
    select
      *,
      case normalized_format
        when 'PRIVACY' then full_name || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' else '' end
        when 'PAYMENT_PROGRESS' then full_name || ' - ' || public.format_tzs_sms_amount(total_paid) || ' / ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' else '' end
        when 'OUTSTANDING_FOLLOW_UP' then full_name || ' - Salio ' || public.format_tzs_sms_amount(outstanding_amount)
        else full_name || ' - ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' - ' || public.format_tzs_sms_amount(total_paid) || ' ☑️' else '' end
      end as rendered_line
    from filtered
    where normalized_format <> 'OUTSTANDING_FOLLOW_UP' or outstanding_amount > 0
  ),
  ordered as (
    select
      *,
      row_number() over (
        order by
          case when normalized_sort = 'PAID_FIRST' then case current_status when 'PAID' then 0 when 'PARTIAL' then 1 else 2 end end asc nulls last,
          case when normalized_sort = 'OUTSTANDING_FIRST' then outstanding_amount end desc nulls last,
          case when normalized_sort = 'PLEDGED_DESC' then pledged_amount end desc nulls last,
          case when normalized_sort = 'NAME_ASC' then full_name end asc nulls last,
          event_member_created_at asc,
          full_name asc,
          event_member_id asc
      ) as display_number
    from rendered
  )
  select
    coalesce(array_agg(display_number::text || '. ' || rendered_line order by display_number), array[]::text[]),
    count(*)::integer
  into lines, member_count
  from ordered;

  if effective_include_summary then
    if normalized_format = 'PRIVACY' then
      summary_block := '*MUHTASARI*' || E'\n' ||
        'Waliokamilisha: ' || coalesce(summary ->> 'paidCount', '0') || E'\n' ||
        'Waliolipa sehemu: ' || coalesce(summary ->> 'partialCount', '0') || E'\n' ||
        'Wanaosubiri: ' || coalesce(summary ->> 'pendingCount', '0');
    else
      summary_block := '*MUHTASARI*' || E'\n' ||
        'Jumla ya Ahadi: TZS ' || public.format_tzs_sms_amount((summary ->> 'totalPledged')::numeric) || E'\n' ||
        'Jumla Iliyopokelewa: TZS ' || public.format_tzs_sms_amount((summary ->> 'totalPaid')::numeric) || E'\n' ||
        'Salio: TZS ' || public.format_tzs_sms_amount((summary ->> 'outstanding')::numeric);
    end if;
  end if;

  if effective_include_event_payment and nullif(public.whatsapp_plain_text(event_record.payment_instructions), '') is not null then
    payment_block := concat_ws(E'\n', payment_block, public.whatsapp_plain_text(event_record.payment_instructions));
  end if;
  if effective_include_mobile_money and nullif(public.whatsapp_plain_text(tenant_settings_record.mobile_money_instructions), '') is not null then
    payment_block := concat_ws(E'\n', payment_block, public.whatsapp_plain_text(tenant_settings_record.mobile_money_instructions));
  end if;
  if effective_include_bank and nullif(public.whatsapp_plain_text(tenant_settings_record.bank_payment_instructions), '') is not null then
    payment_block := concat_ws(E'\n', payment_block, public.whatsapp_plain_text(tenant_settings_record.bank_payment_instructions));
  end if;
  if nullif(payment_block, '') is not null then
    payment_block := '*MALIPO*' || E'\n\n' || payment_block;
  end if;

  footer_block := coalesce(nullif(public.whatsapp_plain_text(settings_record.whatsapp_footer_text), ''), '');
  tail_block := array_to_string(array_remove(array[summary_block, payment_block, footer_block], ''), E'\n\n');
  full_text := array_to_string(array_remove(array[header_block, array_to_string(lines, E'\n'), tail_block], ''), E'\n\n');

  if length(full_text) <= safe_limit then
    part_texts := array[full_text];
  else
    foreach line in array lines loop
      candidate_lines := current_lines || line;
      candidate_text := array_to_string(array_remove(array[header_block, array_to_string(candidate_lines, E'\n')], ''), E'\n\n');
      if array_length(current_lines, 1) is not null and length(candidate_text) > safe_limit then
        part_texts := part_texts || array_to_string(array_remove(array[header_block, array_to_string(current_lines, E'\n')], ''), E'\n\n');
        current_lines := array[line];
      else
        current_lines := candidate_lines;
      end if;
    end loop;
    if array_length(current_lines, 1) is not null then
      part_texts := part_texts || array_to_string(array_remove(array[header_block, array_to_string(current_lines, E'\n'), tail_block], ''), E'\n\n');
    elsif tail_block <> '' then
      part_texts := part_texts || array_to_string(array_remove(array[header_block, tail_block], ''), E'\n\n');
    end if;
  end if;

  total_parts := coalesce(array_length(part_texts, 1), 0);
  for idx in 1..total_parts loop
    parts := parts || jsonb_build_array(jsonb_build_object(
      'part', idx,
      'totalParts', total_parts,
      'text', case when total_parts > 1 then 'PART ' || idx::text || '/' || total_parts::text || E'\n' || part_texts[idx] else part_texts[idx] end
    ));
  end loop;

  return jsonb_build_object(
    'text', full_text,
    'memberCount', member_count,
    'format', normalized_format,
    'statusFilter', normalized_status,
    'sort', normalized_sort,
    'summary', summary,
    'isLong', length(full_text) > safe_limit,
    'safeCharLimit', safe_limit,
    'textLength', length(full_text),
    'parts', parts,
    'settings', jsonb_build_object(
      'headerText', settings_record.whatsapp_header_text,
      'footerText', settings_record.whatsapp_footer_text,
      'defaultHeaderText', public.default_whatsapp_header(event_record.event_type, event_record.name),
      'includeEventDate', effective_include_event_date,
      'includeEventPaymentInstructions', effective_include_event_payment,
      'includeMobileMoneyInstructions', effective_include_mobile_money,
      'includeBankInstructions', effective_include_bank,
      'defaultListFormat', coalesce(settings_record.default_list_format, 'DETAILED'),
      'defaultSort', coalesce(settings_record.default_sort, 'ORIGINAL'),
      'defaultIncludeSummary', coalesce(settings_record.default_include_summary, true),
      'canUseFinancialFormats', can_financial
    ),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.display_order, c.name)
      from public.event_member_categories c
      where c.tenant_id = p_tenant_id and c.event_id = p_event_id and c.is_active
    ), '[]'::jsonb)
  );
end;
$$;

grant select on public.event_share_settings to authenticated;
grant execute on function public.whatsapp_single_line(text) to authenticated;
grant execute on function public.whatsapp_plain_text(text) to authenticated;
grant execute on function public.default_whatsapp_header(text, text) to authenticated;
grant execute on function public.whatsapp_share_summary(uuid, uuid) to authenticated;
grant execute on function public.rpc_get_event_whatsapp_share_settings(uuid, uuid) to authenticated;
grant execute on function public.rpc_update_event_whatsapp_share_settings(uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, text, text, boolean) to authenticated;
grant execute on function public.rpc_generate_event_whatsapp_share_preview(uuid, uuid, text, text, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, text, text, integer) to authenticated;
