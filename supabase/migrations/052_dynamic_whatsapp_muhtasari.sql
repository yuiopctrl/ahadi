alter table public.event_share_settings
add column if not exists whatsapp_summary_rows jsonb,
add column if not exists whatsapp_payment_instructions text,
add column if not exists show_whatsapp_payment_instructions boolean not null default true,
add column if not exists whatsapp_alama_labels jsonb,
add column if not exists show_whatsapp_alama boolean not null default true;

drop trigger if exists event_share_settings_set_updated_at on public.event_share_settings;
create trigger event_share_settings_set_updated_at
before update on public.event_share_settings
for each row execute function public.set_updated_at();

create or replace function public.default_whatsapp_summary_rows()
returns jsonb
language sql
stable
as $$
  select jsonb_build_array(
    jsonb_build_object('label', 'Jumla ya Ahadi', 'valueSource', 'TOTAL_PLEDGED', 'visible', true, 'order', 1),
    jsonb_build_object('label', 'Jumla CASH', 'valueSource', 'CASH_RECEIVED', 'visible', true, 'order', 2)
  );
$$;

create or replace function public.whatsapp_summary_value_sources()
returns jsonb
language sql
stable
as $$
  select jsonb_build_array(
    jsonb_build_object('valueSource', 'TOTAL_PLEDGED', 'label', 'Total Pledged'),
    jsonb_build_object('valueSource', 'TOTAL_RECEIVED', 'label', 'Total Received'),
    jsonb_build_object('valueSource', 'TOTAL_OUTSTANDING', 'label', 'Outstanding'),
    jsonb_build_object('valueSource', 'CASH_RECEIVED', 'label', 'Cash Received'),
    jsonb_build_object('valueSource', 'MOBILE_MONEY_RECEIVED', 'label', 'Mobile Money Received'),
    jsonb_build_object('valueSource', 'M_PESA_RECEIVED', 'label', 'M-Pesa Received'),
    jsonb_build_object('valueSource', 'AIRTEL_MONEY_RECEIVED', 'label', 'Airtel Money Received'),
    jsonb_build_object('valueSource', 'MIX_BY_YAS_RECEIVED', 'label', 'Mix by Yas Received'),
    jsonb_build_object('valueSource', 'HALOPESA_RECEIVED', 'label', 'HaloPesa Received'),
    jsonb_build_object('valueSource', 'BANK_RECEIVED', 'label', 'Bank Received'),
    jsonb_build_object('valueSource', 'CHEQUE_RECEIVED', 'label', 'Cheque Received'),
    jsonb_build_object('valueSource', 'OTHER_RECEIVED', 'label', 'Other Received')
  );
$$;

create or replace function public.default_whatsapp_alama_labels()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'completed', 'Amemaliza',
    'partial', 'Amepunguza',
    'noPledge', 'Hajatoa Ahadi'
  );
$$;

create or replace function public.normalize_whatsapp_alama_labels(p_labels jsonb)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'completed', coalesce(nullif(public.whatsapp_single_line(p_labels ->> 'completed'), ''), 'Amemaliza'),
    'partial', coalesce(nullif(public.whatsapp_single_line(p_labels ->> 'partial'), ''), 'Amepunguza'),
    'noPledge', coalesce(nullif(public.whatsapp_single_line(p_labels ->> 'noPledge'), ''), 'Hajatoa Ahadi')
  );
$$;

create or replace function public.whatsapp_render_alama(p_labels jsonb, p_show boolean)
returns text
language sql
stable
as $$
  select case when coalesce(p_show, true) then
    'Alama:' || E'\n' ||
    '✅✅ -- ' || (public.normalize_whatsapp_alama_labels(p_labels) ->> 'completed') || E'\n' ||
    '☑️ -- ' || (public.normalize_whatsapp_alama_labels(p_labels) ->> 'partial') || E'\n' ||
    '🙏🏿 -- ' || (public.normalize_whatsapp_alama_labels(p_labels) ->> 'noPledge')
  else '' end;
$$;

create or replace function public.normalize_whatsapp_summary_rows(p_rows jsonb)
returns jsonb
language sql
stable
as $$
  with input_rows as (
    select item.value, item.ordinality
    from jsonb_array_elements(
      case when jsonb_typeof(p_rows) = 'array' and jsonb_array_length(p_rows) > 0 then p_rows else public.default_whatsapp_summary_rows() end
    ) with ordinality as item(value, ordinality)
  ),
  normalized as (
    select
      nullif(public.whatsapp_single_line(value ->> 'label'), '') as label,
      upper(public.whatsapp_single_line(value ->> 'valueSource')) as value_source,
      coalesce((value ->> 'visible')::boolean, true) as visible,
      coalesce((value ->> 'order')::integer, ordinality::integer) as row_order,
      ordinality
    from input_rows
  ),
  allowed as (
    select source ->> 'valueSource' as value_source
    from jsonb_array_elements(public.whatsapp_summary_value_sources()) source
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'label', coalesce(n.label, initcap(replace(lower(n.value_source), '_', ' '))),
    'valueSource', n.value_source,
    'visible', n.visible,
    'order', n.row_order
  ) order by n.row_order, n.ordinality), public.default_whatsapp_summary_rows())
  from normalized n
  join allowed a on a.value_source = n.value_source;
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
  ),
  pledge_totals as (
    select
      coalesce(sum(pledged_amount), 0)::numeric(18,2) as total_pledged,
      coalesce(sum(paid_amount), 0)::numeric(18,2) as total_paid,
      coalesce(sum(outstanding_amount), 0)::numeric(18,2) as outstanding,
      count(*) filter (where outstanding_amount <= 0) as paid_count,
      count(*) filter (where outstanding_amount > 0 and paid_amount > 0) as partial_count,
      count(*) filter (where outstanding_amount > 0 and paid_amount <= 0) as pending_count,
      count(*) filter (where outstanding_amount > 0 and effective_due_date is not null and effective_due_date < current_date) as overdue_count
    from pledge_state
  ),
  payment_totals as (
    select
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED'), 0)::numeric(18,2) as total_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'CASH'), 0)::numeric(18,2) as cash_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method in ('M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA')), 0)::numeric(18,2) as mobile_money_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'M_PESA'), 0)::numeric(18,2) as m_pesa_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'AIRTEL_MONEY'), 0)::numeric(18,2) as airtel_money_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'MIX_BY_YAS'), 0)::numeric(18,2) as mix_by_yas_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'HALOPESA'), 0)::numeric(18,2) as halopesa_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'BANK_TRANSFER'), 0)::numeric(18,2) as bank_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'CHEQUE'), 0)::numeric(18,2) as cheque_received,
      coalesce(sum(pay.amount) filter (where pay.status = 'CONFIRMED' and pay.payment_method = 'OTHER'), 0)::numeric(18,2) as other_received
    from public.payments pay
    where pay.tenant_id = p_tenant_id
      and pay.event_id = p_event_id
  )
  select jsonb_build_object(
    'totalPledged', pledge_totals.total_pledged,
    'totalPaid', pledge_totals.total_paid,
    'totalReceived', payment_totals.total_received,
    'totalOutstanding', pledge_totals.outstanding,
    'outstanding', pledge_totals.outstanding,
    'cashReceived', payment_totals.cash_received,
    'mobileMoneyReceived', payment_totals.mobile_money_received,
    'mPesaReceived', payment_totals.m_pesa_received,
    'airtelMoneyReceived', payment_totals.airtel_money_received,
    'mixByYasReceived', payment_totals.mix_by_yas_received,
    'halopesaReceived', payment_totals.halopesa_received,
    'bankReceived', payment_totals.bank_received,
    'chequeReceived', payment_totals.cheque_received,
    'otherReceived', payment_totals.other_received,
    'paidCount', pledge_totals.paid_count,
    'partialCount', pledge_totals.partial_count,
    'pendingCount', pledge_totals.pending_count,
    'overdueCount', pledge_totals.overdue_count
  )
  from pledge_totals cross join payment_totals;
$$;

create or replace function public.whatsapp_summary_value(p_summary jsonb, p_source text)
returns numeric
language sql
stable
as $$
  select case upper(coalesce(p_source, ''))
    when 'TOTAL_PLEDGED' then coalesce((p_summary ->> 'totalPledged')::numeric, 0)
    when 'TOTAL_RECEIVED' then coalesce((p_summary ->> 'totalReceived')::numeric, 0)
    when 'TOTAL_OUTSTANDING' then coalesce((p_summary ->> 'totalOutstanding')::numeric, 0)
    when 'CASH_RECEIVED' then coalesce((p_summary ->> 'cashReceived')::numeric, 0)
    when 'MOBILE_MONEY_RECEIVED' then coalesce((p_summary ->> 'mobileMoneyReceived')::numeric, 0)
    when 'M_PESA_RECEIVED' then coalesce((p_summary ->> 'mPesaReceived')::numeric, 0)
    when 'AIRTEL_MONEY_RECEIVED' then coalesce((p_summary ->> 'airtelMoneyReceived')::numeric, 0)
    when 'MIX_BY_YAS_RECEIVED' then coalesce((p_summary ->> 'mixByYasReceived')::numeric, 0)
    when 'HALOPESA_RECEIVED' then coalesce((p_summary ->> 'halopesaReceived')::numeric, 0)
    when 'BANK_RECEIVED' then coalesce((p_summary ->> 'bankReceived')::numeric, 0)
    when 'CHEQUE_RECEIVED' then coalesce((p_summary ->> 'chequeReceived')::numeric, 0)
    when 'OTHER_RECEIVED' then coalesce((p_summary ->> 'otherReceived')::numeric, 0)
    else 0
  end;
$$;

create or replace function public.whatsapp_render_financial_summary(p_summary jsonb, p_rows jsonb)
returns text
language sql
stable
as $$
  with rows as (
    select
      item.value ->> 'label' as label,
      item.value ->> 'valueSource' as value_source,
      (item.value ->> 'visible')::boolean as visible,
      (item.value ->> 'order')::integer as row_order,
      ordinality
    from jsonb_array_elements(public.normalize_whatsapp_summary_rows(p_rows)) with ordinality as item(value, ordinality)
  )
  select coalesce(
    '*MUHTASARI*' || E'\n' || string_agg(label || ': TZS ' || public.format_tzs_sms_amount(public.whatsapp_summary_value(p_summary, value_source)), E'\n' order by row_order, ordinality),
    ''
  )
  from rows
  where visible;
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
    'showPaymentInstructions', coalesce(settings_record.show_whatsapp_payment_instructions, true),
    'paymentInstructions', coalesce(settings_record.whatsapp_payment_instructions, public.whatsapp_plain_text(event_record.payment_instructions), ''),
    'defaultPaymentInstructions', public.whatsapp_plain_text(event_record.payment_instructions),
    'showAlama', coalesce(settings_record.show_whatsapp_alama, true),
    'alamaLabels', public.normalize_whatsapp_alama_labels(settings_record.whatsapp_alama_labels),
    'defaultAlamaLabels', public.default_whatsapp_alama_labels(),
    'defaultListFormat', coalesce(settings_record.default_list_format, 'DETAILED'),
    'defaultSort', coalesce(settings_record.default_sort, 'ORIGINAL'),
    'defaultIncludeSummary', coalesce(settings_record.default_include_summary, true),
    'summaryRows', public.normalize_whatsapp_summary_rows(settings_record.whatsapp_summary_rows),
    'defaultSummaryRows', public.default_whatsapp_summary_rows(),
    'availableSummarySources', public.whatsapp_summary_value_sources(),
    'canUseFinancialFormats', public.has_tenant_permission(p_tenant_id, 'shares.whatsapp.financial')
  );
end;
$$;

drop function if exists public.rpc_update_event_whatsapp_share_settings(uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, text, text, boolean);
drop function if exists public.rpc_update_event_whatsapp_share_settings(uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, text, text, boolean, jsonb);

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
  p_default_include_summary boolean default true,
  p_summary_rows jsonb default null,
  p_show_payment_instructions boolean default true,
  p_payment_instructions text default null,
  p_show_alama boolean default true,
  p_alama_labels jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_format text := upper(coalesce(p_default_list_format, 'DETAILED'));
  normalized_sort text := upper(coalesce(p_default_sort, 'ORIGINAL'));
  normalized_summary_rows jsonb := public.normalize_whatsapp_summary_rows(p_summary_rows);
  normalized_alama_labels jsonb := public.normalize_whatsapp_alama_labels(p_alama_labels);
  normalized_payment_instructions text := nullif(public.whatsapp_plain_text(p_payment_instructions), '');
  settings_before public.event_share_settings%rowtype;
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

  select * into settings_before from public.event_share_settings where tenant_id = p_tenant_id and event_id = p_event_id;

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
    whatsapp_summary_rows,
    show_whatsapp_payment_instructions,
    whatsapp_payment_instructions,
    show_whatsapp_alama,
    whatsapp_alama_labels,
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
    normalized_summary_rows,
    coalesce(p_show_payment_instructions, true),
    normalized_payment_instructions,
    coalesce(p_show_alama, true),
    normalized_alama_labels,
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
      whatsapp_summary_rows = excluded.whatsapp_summary_rows,
      show_whatsapp_payment_instructions = excluded.show_whatsapp_payment_instructions,
      whatsapp_payment_instructions = excluded.whatsapp_payment_instructions,
      show_whatsapp_alama = excluded.show_whatsapp_alama,
      whatsapp_alama_labels = excluded.whatsapp_alama_labels,
      updated_by = excluded.updated_by;

  if coalesce(settings_before.show_whatsapp_payment_instructions, true) is distinct from coalesce(p_show_payment_instructions, true)
     or coalesce(settings_before.whatsapp_payment_instructions, '') is distinct from coalesce(normalized_payment_instructions, '') then
    perform public.write_audit_log(
      p_tenant_id,
      'share.whatsapp.payment_instructions.updated',
      'event_share_settings',
      p_event_id,
      p_event_id,
      jsonb_build_object('showPaymentInstructions', coalesce(settings_before.show_whatsapp_payment_instructions, true), 'paymentInstructions', settings_before.whatsapp_payment_instructions),
      jsonb_build_object('showPaymentInstructions', coalesce(p_show_payment_instructions, true), 'paymentInstructions', normalized_payment_instructions),
      'Updated Share List payment instructions'
    );
  end if;

  if coalesce(settings_before.show_whatsapp_alama, true) is distinct from coalesce(p_show_alama, true)
     or public.normalize_whatsapp_alama_labels(settings_before.whatsapp_alama_labels) is distinct from normalized_alama_labels then
    perform public.write_audit_log(
      p_tenant_id,
      'share.whatsapp.alama.updated',
      'event_share_settings',
      p_event_id,
      p_event_id,
      jsonb_build_object('showAlama', coalesce(settings_before.show_whatsapp_alama, true), 'alamaLabels', public.normalize_whatsapp_alama_labels(settings_before.whatsapp_alama_labels)),
      jsonb_build_object('showAlama', coalesce(p_show_alama, true), 'alamaLabels', normalized_alama_labels),
      'Updated Share List Alama'
    );
  end if;

  return public.rpc_get_event_whatsapp_share_settings(p_tenant_id, p_event_id);
end;
$$;

create or replace function public.rpc_update_event_whatsapp_share_presentation_settings(
  p_tenant_id uuid,
  p_event_id uuid,
  p_show_payment_instructions boolean default true,
  p_payment_instructions text default null,
  p_show_alama boolean default true,
  p_alama_labels jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_alama_labels jsonb := public.normalize_whatsapp_alama_labels(p_alama_labels);
  normalized_payment_instructions text := nullif(public.whatsapp_plain_text(p_payment_instructions), '');
  settings_before public.event_share_settings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_REQUIRED' using errcode = '28000';
  end if;
  perform 1 from public.events where id = p_event_id and tenant_id = p_tenant_id;
  if not found or not public.can_access_event(p_event_id) then
    raise exception 'EVENT_ACCESS_DENIED' using errcode = '42501';
  end if;

  select * into settings_before from public.event_share_settings where tenant_id = p_tenant_id and event_id = p_event_id;

  insert into public.event_share_settings (
    tenant_id,
    event_id,
    show_whatsapp_payment_instructions,
    whatsapp_payment_instructions,
    show_whatsapp_alama,
    whatsapp_alama_labels,
    updated_by
  )
  values (
    p_tenant_id,
    p_event_id,
    coalesce(p_show_payment_instructions, true),
    normalized_payment_instructions,
    coalesce(p_show_alama, true),
    normalized_alama_labels,
    auth.uid()
  )
  on conflict (event_id) do update
  set show_whatsapp_payment_instructions = excluded.show_whatsapp_payment_instructions,
      whatsapp_payment_instructions = excluded.whatsapp_payment_instructions,
      show_whatsapp_alama = excluded.show_whatsapp_alama,
      whatsapp_alama_labels = excluded.whatsapp_alama_labels,
      updated_by = excluded.updated_by;

  if coalesce(settings_before.show_whatsapp_payment_instructions, true) is distinct from coalesce(p_show_payment_instructions, true)
     or coalesce(settings_before.whatsapp_payment_instructions, '') is distinct from coalesce(normalized_payment_instructions, '') then
    perform public.write_audit_log(
      p_tenant_id,
      'share.whatsapp.payment_instructions.updated',
      'event_share_settings',
      p_event_id,
      p_event_id,
      jsonb_build_object('showPaymentInstructions', coalesce(settings_before.show_whatsapp_payment_instructions, true), 'paymentInstructions', settings_before.whatsapp_payment_instructions),
      jsonb_build_object('showPaymentInstructions', coalesce(p_show_payment_instructions, true), 'paymentInstructions', normalized_payment_instructions),
      'Updated Share List payment instructions'
    );
  end if;

  if coalesce(settings_before.show_whatsapp_alama, true) is distinct from coalesce(p_show_alama, true)
     or public.normalize_whatsapp_alama_labels(settings_before.whatsapp_alama_labels) is distinct from normalized_alama_labels then
    perform public.write_audit_log(
      p_tenant_id,
      'share.whatsapp.alama.updated',
      'event_share_settings',
      p_event_id,
      p_event_id,
      jsonb_build_object('showAlama', coalesce(settings_before.show_whatsapp_alama, true), 'alamaLabels', public.normalize_whatsapp_alama_labels(settings_before.whatsapp_alama_labels)),
      jsonb_build_object('showAlama', coalesce(p_show_alama, true), 'alamaLabels', normalized_alama_labels),
      'Updated Share List Alama'
    );
  end if;

  return public.rpc_get_event_whatsapp_share_settings(p_tenant_id, p_event_id);
end;
$$;

drop function if exists public.rpc_generate_event_whatsapp_share_preview(uuid, uuid, text, text, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, text, text, integer);
drop function if exists public.rpc_generate_event_whatsapp_share_preview(uuid, uuid, text, text, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, text, text, integer, jsonb);

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
  p_safe_char_limit integer default 3500,
  p_summary_rows jsonb default null,
  p_show_payment_instructions boolean default null,
  p_payment_instructions text default null,
  p_show_alama boolean default null,
  p_alama_labels jsonb default null
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
  effective_summary_rows jsonb;
  effective_show_payment_instructions boolean;
  effective_payment_instructions text;
  effective_show_alama boolean;
  effective_alama_labels jsonb;
  header_block text;
  summary_block text := '';
  payment_block text := '';
  alama_block text := '';
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
  effective_summary_rows := public.normalize_whatsapp_summary_rows(coalesce(p_summary_rows, settings_record.whatsapp_summary_rows));
  effective_show_payment_instructions := coalesce(p_show_payment_instructions, coalesce(settings_record.show_whatsapp_payment_instructions, true));
  effective_payment_instructions := case
    when p_payment_instructions is not null then nullif(public.whatsapp_plain_text(p_payment_instructions), '')
    else coalesce(nullif(settings_record.whatsapp_payment_instructions, ''), nullif(public.whatsapp_plain_text(event_record.payment_instructions), ''))
  end;
  effective_show_alama := coalesce(p_show_alama, coalesce(settings_record.show_whatsapp_alama, true));
  effective_alama_labels := public.normalize_whatsapp_alama_labels(coalesce(p_alama_labels, settings_record.whatsapp_alama_labels));

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
      and (p.id is not null or coalesce(p_include_without_pledges, false))
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
        when 'PRIVACY' then full_name || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' when 'NO_PLEDGE' then ' 🙏🏿' else '' end
        when 'PAYMENT_PROGRESS' then full_name || case when pledge_id is null then ' - 🙏🏿' else ' - ' || public.format_tzs_sms_amount(total_paid) || ' / ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' else '' end end
        when 'OUTSTANDING_FOLLOW_UP' then full_name || ' - Salio ' || public.format_tzs_sms_amount(outstanding_amount)
        else full_name || case when pledge_id is null then ' - 🙏🏿' else ' - ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' - ' || public.format_tzs_sms_amount(total_paid) || ' ☑️' else '' end end
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
      summary_block := public.whatsapp_render_financial_summary(summary, effective_summary_rows);
    end if;
  end if;

  if effective_show_payment_instructions then
    if effective_payment_instructions is not null then
      payment_block := effective_payment_instructions;
    elsif effective_include_event_payment and nullif(public.whatsapp_plain_text(event_record.payment_instructions), '') is not null then
      payment_block := concat_ws(E'\n', payment_block, public.whatsapp_plain_text(event_record.payment_instructions));
    end if;
    if payment_block = '' and effective_include_mobile_money and nullif(public.whatsapp_plain_text(tenant_settings_record.mobile_money_instructions), '') is not null then
      payment_block := concat_ws(E'\n', payment_block, public.whatsapp_plain_text(tenant_settings_record.mobile_money_instructions));
    end if;
    if payment_block = '' and effective_include_bank and nullif(public.whatsapp_plain_text(tenant_settings_record.bank_payment_instructions), '') is not null then
      payment_block := concat_ws(E'\n', payment_block, public.whatsapp_plain_text(tenant_settings_record.bank_payment_instructions));
    end if;
  end if;

  alama_block := public.whatsapp_render_alama(effective_alama_labels, effective_show_alama);

  footer_block := coalesce(nullif(public.whatsapp_plain_text(settings_record.whatsapp_footer_text), ''), '');
  tail_block := array_to_string(array_remove(array[summary_block, alama_block, footer_block], ''), E'\n\n');
  full_text := array_to_string(array_remove(array[header_block, payment_block, array_to_string(lines, E'\n'), tail_block], ''), E'\n\n');

  if length(full_text) <= safe_limit then
    part_texts := array[full_text];
  else
    foreach line in array lines loop
      candidate_lines := current_lines || line;
      candidate_text := array_to_string(array_remove(array[header_block, payment_block, array_to_string(candidate_lines, E'\n')], ''), E'\n\n');
      if array_length(current_lines, 1) is not null and length(candidate_text) > safe_limit then
        part_texts := part_texts || array_to_string(array_remove(array[header_block, payment_block, array_to_string(current_lines, E'\n')], ''), E'\n\n');
        current_lines := array[line];
      else
        current_lines := candidate_lines;
      end if;
    end loop;
    if array_length(current_lines, 1) is not null then
      part_texts := part_texts || array_to_string(array_remove(array[header_block, payment_block, array_to_string(current_lines, E'\n'), tail_block], ''), E'\n\n');
    elsif tail_block <> '' then
      part_texts := part_texts || array_to_string(array_remove(array[header_block, payment_block, tail_block], ''), E'\n\n');
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
    'summaryRows', effective_summary_rows,
    'availableSummarySources', public.whatsapp_summary_value_sources(),
    'showPaymentInstructions', effective_show_payment_instructions,
    'paymentInstructions', coalesce(effective_payment_instructions, ''),
    'showAlama', effective_show_alama,
    'alamaLabels', effective_alama_labels,
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
      'showPaymentInstructions', effective_show_payment_instructions,
      'paymentInstructions', coalesce(effective_payment_instructions, ''),
      'defaultPaymentInstructions', public.whatsapp_plain_text(event_record.payment_instructions),
      'showAlama', effective_show_alama,
      'alamaLabels', effective_alama_labels,
      'defaultAlamaLabels', public.default_whatsapp_alama_labels(),
      'defaultListFormat', coalesce(settings_record.default_list_format, 'DETAILED'),
      'defaultSort', coalesce(settings_record.default_sort, 'ORIGINAL'),
      'defaultIncludeSummary', coalesce(settings_record.default_include_summary, true),
      'summaryRows', effective_summary_rows,
      'availableSummarySources', public.whatsapp_summary_value_sources(),
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

grant execute on function public.default_whatsapp_summary_rows() to authenticated;
grant execute on function public.whatsapp_summary_value_sources() to authenticated;
grant execute on function public.default_whatsapp_alama_labels() to authenticated;
grant execute on function public.normalize_whatsapp_alama_labels(jsonb) to authenticated;
grant execute on function public.whatsapp_render_alama(jsonb, boolean) to authenticated;
grant execute on function public.normalize_whatsapp_summary_rows(jsonb) to authenticated;
grant execute on function public.whatsapp_summary_value(jsonb, text) to authenticated;
grant execute on function public.whatsapp_render_financial_summary(jsonb, jsonb) to authenticated;
grant execute on function public.whatsapp_share_summary(uuid, uuid) to authenticated;
grant execute on function public.rpc_get_event_whatsapp_share_settings(uuid, uuid) to authenticated;
grant execute on function public.rpc_update_event_whatsapp_share_settings(uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, text, text, boolean, jsonb, boolean, text, boolean, jsonb) to authenticated;
grant execute on function public.rpc_update_event_whatsapp_share_presentation_settings(uuid, uuid, boolean, text, boolean, jsonb) to authenticated;
grant execute on function public.rpc_generate_event_whatsapp_share_preview(uuid, uuid, text, text, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, text, text, integer, jsonb, boolean, text, boolean, jsonb) to authenticated;
