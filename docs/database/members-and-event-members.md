# Members And Event Members

`members` are tenant-level contributor records. `event_members` attach those contributors to a specific event and preserve history when removed.

Member codes use the tenant-scoped `tenant_financial_counters` row and are generated as `MBR-000001`, avoiding `SELECT MAX(...)`. Phone numbers are normalized to Tanzanian E.164 when present, and active duplicate phones are rejected within the same tenant.

Event membership validates tenant, event, member and category alignment through database triggers and controlled RPCs. Removed event members remain in history; financial records are not deleted.
