insert into public.permissions (code, name, description) values
('reports.export', 'Export reports', 'Export event financial reports')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'reports.export'
where r.code in ('TENANT_OWNER', 'EVENT_ADMIN', 'TREASURER')
on conflict do nothing;

grant execute on function public.write_audit_log(uuid, text, text, uuid, uuid, jsonb, jsonb, text) to authenticated;
