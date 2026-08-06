# Tenant Context

`X-Tenant-ID` is a requested UI context, not authorization proof. The API validates it by loading `rpc_get_tenant_context`, which verifies active tenant membership or platform permission.

If a user has exactly one active tenant membership, the web application may select it automatically after `rpc_get_my_context`. If several active memberships exist, the user must choose a tenant.

Tenant routes require:

- authenticated Supabase session
- PIN unlock
- completed onboarding
- verified selected tenant
- active membership
- non-blocked tenant access state

Tenant IDs supplied in request bodies or query strings must not be used for authorization decisions.
