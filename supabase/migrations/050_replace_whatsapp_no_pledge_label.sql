do $migration$
declare
  function_sql text;
  function_identity regprocedure := 'public.rpc_generate_event_whatsapp_share_preview(uuid, uuid, text, text, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, text, text, integer)'::regprocedure;
begin
  select pg_get_functiondef(function_identity) into function_sql;

  function_sql := replace(function_sql, 'Hakuna ahadi', '🙏🏿');

  execute function_sql;
end;
$migration$;
