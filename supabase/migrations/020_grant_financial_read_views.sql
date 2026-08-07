grant select on
  public.v_event_members_list,
  public.v_event_pledges_list,
  public.v_event_payments_list,
  public.v_event_outstanding_members,
  public.v_receipt_detail
to authenticated;

grant execute on function public.payment_allocated_amount(uuid) to authenticated;
grant execute on function public.payment_unallocated_amount(uuid) to authenticated;
grant execute on function public.confirmed_pledge_allocated_amount(uuid) to authenticated;
grant execute on function public.calculated_pledge_status(uuid) to authenticated;
