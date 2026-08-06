-- Placeholder TZS prices are editable and not final approved commercial pricing.
insert into public.subscription_plans (
  code, name, description, currency, price_amount, billing_interval, trial_days,
  max_active_events, max_members, max_users, included_sms, features, display_order
) values
('STARTER', 'Starter', 'One active event for a small organizing committee with limited SMS allocation.', 'TZS', 25000, 'MONTHLY', 14, 1, 250, 5, 250, '{"event_limit":"One active event","support":"Community support"}', 1),
('GROWTH', 'Growth', 'Several active events, more users and members, and a larger SMS allocation.', 'TZS', 75000, 'MONTHLY', 14, 5, 2000, 20, 2500, '{"event_limit":"Several active events","support":"Priority support"}', 2),
('AGENCY', 'Agency', 'Professional event organizer package for many active events and larger teams.', 'TZS', 180000, 'MONTHLY', 14, 25, 10000, 75, 12000, '{"event_limit":"Many active events","support":"Dedicated onboarding"}', 3)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  price_amount = excluded.price_amount,
  billing_interval = excluded.billing_interval,
  trial_days = excluded.trial_days,
  max_active_events = excluded.max_active_events,
  max_members = excluded.max_members,
  max_users = excluded.max_users,
  included_sms = excluded.included_sms,
  features = excluded.features,
  display_order = excluded.display_order,
  is_public = true,
  is_active = true;
