# Authentication

Supabase OTP is the source of authentication. API endpoints normalize Tanzanian phone numbers before requesting or verifying OTP. The web app and ordinary API authentication use the Supabase publishable key, never a service-role key.

The PIN is only an application unlock mechanism for an already authenticated device. It does not replace Supabase authentication after logout, expired or revoked sessions, new devices, cleared browser storage, or security reset. In those cases, OTP is required again.

PIN hashes live only in `private.user_pin_credentials` and are created with `pgcrypto` `crypt` and `gen_salt`. Public RPCs return only boolean or lockout state.

Platform role assignment is never exposed through onboarding. Bootstrap is manual after the intended owner authenticates:

```sql
insert into public.platform_users (user_id, role, status)
values ('<auth.users.id>', 'PLATFORM_OWNER', 'ACTIVE');
```
