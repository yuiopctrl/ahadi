# Subscription Access

Tenant access state is a typed server contract:

- `TRIAL`: tenant is in trial and trial has not expired.
- `ACTIVE`: tenant has a valid active subscription.
- `READ_ONLY`: subscription recently expired and is within the single configured grace period.
- `BLOCKED`: tenant is suspended, cancelled, archived, or beyond grace.

The grace period is centralized in `packages/config` as `SUBSCRIPTION_READ_ONLY_GRACE_DAYS`. API and UI consume the resulting access-state contract rather than reimplementing grace rules in several places.

Plan limits must be enforced on the server. Event creation uses active event count against `max_active_events`; future user invitation and SMS logic will enforce `max_users` and SMS allowance server-side.
