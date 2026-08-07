# Platform Owner Access

Platform ownership is a manual bootstrap operation after the intended administrator has authenticated at least once. It is not created by tenant registration, tenant onboarding, or any public API route.

Find the intended authenticated user. Confirm the person manually before using the UUID:

```sql
select
  p.id,
  p.full_name,
  p.phone_e164
from public.profiles p
where p.phone_e164 = '<OWNER_PHONE_E164>'
order by p.created_at desc;
```

If the phone number is uncertain, inspect recent authenticated profiles first and verify out-of-band before copying a UUID.

```sql
select
  p.id,
  p.full_name,
  p.phone_e164,
  p.created_at
from public.profiles p
order by p.created_at desc
limit 20;
```

Check whether a known authenticated user is already a platform user:

```sql
select
  pu.user_id,
  pu.role,
  pu.status,
  p.full_name,
  p.phone_e164
from public.platform_users pu
left join public.profiles p
  on p.id = pu.user_id
where pu.user_id = '<AUTH_USER_UUID>';
```

Bootstrap or repair the intended owner explicitly:

```sql
insert into public.platform_users (
  user_id,
  role,
  status,
  created_at,
  updated_at
)
values (
  '<AUTH_USER_UUID>',
  'PLATFORM_OWNER',
  'ACTIVE',
  now(),
  now()
)
on conflict (user_id)
do update set
  role = excluded.role,
  status = excluded.status,
  updated_at = now();
```

`public.rpc_get_my_context()` returns platform context independently from tenant membership. A platform owner can also be a tenant owner, and a platform-only user with no tenant membership can open `/platform`.
