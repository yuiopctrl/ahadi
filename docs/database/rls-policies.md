# RLS Policies

RLS is enabled on all public application tables. Policies use helper functions that derive identity from `auth.uid()` rather than trusting browser-supplied user or tenant identifiers.

Helpers include:

- `is_platform_user()`
- `has_platform_permission(permission_code text)`
- `is_tenant_member(tenant_uuid uuid)`
- `is_active_tenant_member(tenant_uuid uuid)`
- `has_tenant_permission(tenant_uuid uuid, permission_code text)`
- `can_access_event(event_uuid uuid)`
- `can_manage_event(event_uuid uuid)`

Audit logs are append-only for tenant users. Tenant users with `audit.view` can select logs for their tenant; platform auditors can select platform audit data. No tenant update or delete policies are defined.
