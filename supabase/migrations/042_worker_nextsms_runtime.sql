grant execute on function public.rpc_claim_sms_outbox(integer) to anon, authenticated;
grant execute on function public.rpc_mark_sms_sent(uuid, text) to anon, authenticated;
grant execute on function public.rpc_mark_sms_failed(uuid, text, text, boolean) to anon, authenticated;

notify pgrst, 'reload schema';
