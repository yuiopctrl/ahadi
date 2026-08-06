# Multi-Tenancy

Ahadi isolates tenants at the database boundary. Every tenant-owned record carries `tenant_id`, and RLS policies validate that `auth.uid()` belongs to an active `tenant_users` membership before data is returned.

Tenant codes use a sequence-backed readable format such as `AHD-000001`. Event codes are generated per tenant while holding an advisory transaction lock.

Platform users are separate from tenant users. A platform support user can view platform operational information through platform permissions but is not automatically a tenant member and does not receive tenant financial access.

Tenant-specific custom roles are supported by allowing `roles.tenant_id` to be non-null. Built-in tenant roles are system role rows and are not duplicated per tenant.
