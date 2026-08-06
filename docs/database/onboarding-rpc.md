# Onboarding RPC

`rpc_complete_tenant_onboarding` is an atomic SECURITY DEFINER transaction path. It requires `auth.uid()`, locks on caller plus idempotency key, validates the profile and selected public plan, creates the tenant, settings, subscription, owner membership, owner role assignment, first event, event assignment, profile onboarding marker, and audit entries.

The RPC returns tenant, subscription, and event identifiers. If a matching idempotency key has already completed, it returns the prior result instead of creating duplicates. If any step fails, PostgreSQL rolls back the full transaction.

The caller cannot choose tenant status, subscription status or expiry, role, tenant owner user id, or platform role.
