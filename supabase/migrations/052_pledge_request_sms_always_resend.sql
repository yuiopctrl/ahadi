create or replace function public.pledge_request_ineligibility_reason(
  p_phone text,
  p_sms_enabled boolean,
  p_has_pledge boolean,
  p_recent_sent_at timestamptz,
  p_cooldown_hours integer
)
returns text
language sql
stable
as $$
  select case
    when coalesce(p_has_pledge, false) then 'HAS_PLEDGE'
    when p_phone is null or p_phone !~ '^\+255[67][0-9]{8}$' then 'NO_PHONE'
    when coalesce(p_sms_enabled, false) = false then 'SMS_DISABLED'
    else null
  end;
$$;

comment on function public.pledge_request_ineligibility_reason(text, boolean, boolean, timestamptz, integer)
is 'Pledge request SMS can be sent again immediately. p_recent_sent_at and p_cooldown_hours are retained for API compatibility but do not block sending.';

grant execute on function public.pledge_request_ineligibility_reason(text, boolean, boolean, timestamptz, integer) to authenticated;

notify pgrst, 'reload schema';
