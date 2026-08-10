do $migration$
declare
  function_sql text;
  function_identity regprocedure := 'public.rpc_generate_event_whatsapp_share_preview(uuid, uuid, text, text, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, text, text, integer)'::regprocedure;
begin
  select pg_get_functiondef(function_identity) into function_sql;

  function_sql := replace(
    function_sql,
    $needle$and (p.id is not null or (normalized_format = 'PRIVACY' and coalesce(p_include_without_pledges, false)))$needle$,
    $replacement$and (p.id is not null or coalesce(p_include_without_pledges, false))$replacement$
  );

  function_sql := replace(
    function_sql,
    $needle$when 'PAYMENT_PROGRESS' then full_name || ' - ' || public.format_tzs_sms_amount(total_paid) || ' / ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' else '' end$needle$,
    $replacement$when 'PAYMENT_PROGRESS' then full_name || case when pledge_id is null then ' - 🙏🏿' else ' - ' || public.format_tzs_sms_amount(total_paid) || ' / ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' else '' end end$replacement$
  );

  function_sql := replace(
    function_sql,
    $needle$else full_name || ' - ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' - ' || public.format_tzs_sms_amount(total_paid) || ' ☑️' else '' end$needle$,
    $replacement$else full_name || case when pledge_id is null then ' - 🙏🏿' else ' - ' || public.format_tzs_sms_amount(pledged_amount) || case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' - ' || public.format_tzs_sms_amount(total_paid) || ' ☑️' else '' end end$replacement$
  );

  execute function_sql;
end;
$migration$;
