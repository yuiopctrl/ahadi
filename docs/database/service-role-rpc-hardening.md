# Service-role RPC hardening (pre-RSVP-2 security review)

## Background

RSVP-1 discovered, by actually running migrations against a throwaway
Postgres 17 instance and inspecting `pg_proc.proacl`, that
`revoke all on function ... from public; grant execute on function ... to
service_role;` is **not** a sufficient access boundary on its own for a
`SECURITY DEFINER` function meant to be callable only by the backend's
service-role client.

## What `issue_pg_graphql_access` actually does

This Supabase Postgres image ships a built-in event trigger,
`issue_pg_graphql_access`, firing on `ddl_command_end`. Its job is to keep
`pg_graphql`'s auto-generated GraphQL API surface working by automatically
(re-)granting `EXECUTE`/`USAGE` on schema-`public` objects to
`anon`/`authenticated`/`service_role` whenever a DDL event occurs. Because a
`GRANT`/`REVOKE` statement is itself a `ddl_command_end` event, the sequence

```sql
create or replace function public.some_rpc(...) ...;  -- ddl_command_end #1: trigger grants anon/authenticated/service_role
revoke all on function public.some_rpc(...) from public;  -- ddl_command_end #2: trigger re-grants anon/authenticated/service_role
grant execute on function public.some_rpc(...) to service_role;  -- ddl_command_end #3: (redundant) re-grants again
```

leaves `anon` and `authenticated` **still holding a direct grant** on
`some_rpc`, verified by inspecting `pg_proc.proacl` after running exactly
this sequence.

This event trigger is Supabase-managed platform infrastructure, not
something this codebase's migrations installed. **It was not disabled or
dropped** -- there is no strong evidence that doing so is safe (it may be
relied on for legitimate schema-cache/GraphQL behavior elsewhere), and the
task explicitly prefers defense inside the sensitive function itself. That
defense is `public.require_service_role()` (introduced in migration 072,
reused unchanged in 073):

```sql
create or replace function public.require_service_role()
returns void
language plpgsql
stable
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
end;
$$;
```

`request.jwt.claim.role` is the GUC PostgREST itself sets, server-side, from
the already-cryptographically-verified JWT, *before* it does `SET ROLE
<resolved-role>` and hands control to the SQL function. It is:

- **Immune to the event-trigger over-grant** -- it is not a grant at all,
  just a plain per-request GUC read.
- **Immune to `SECURITY DEFINER` privilege elevation** -- unlike
  `current_user` (which becomes the function owner the instant a `SECURITY
  DEFINER` function starts executing, with no window where it reflects the
  original caller), a GUC's value is unaffected by which role is currently
  "acting" for privilege-check purposes. This was proven, not just argued:
  `rpc_get_public_invitation_detail` (migration 072) *is* `SECURITY DEFINER`
  and calls `require_service_role()` from inside its own body, and a
  simulated `anon` PostgREST call to it was still correctly rejected.
- **Not forgeable by an HTTP client.** A real PostgREST client has no
  mechanism to `SET` an arbitrary GUC itself -- it can only call the RPC
  with JSON arguments. `request.jwt.claim.role` is populated exclusively by
  PostgREST from a JWT signed with Supabase's own auth secret (a different
  secret than this codebase's `INVITATION_PUBLIC_TOKEN_SECRET`). The only way
  to make this GUC read `service_role` is to actually present the real
  service-role key, which only the backend holds.

## Audit of every function matching sensitive naming patterns

Searched for every function whose name contains `verify`, `service`,
`admin`, `secret`, `token`, `otp`, `pin`, or `internal`, plus the two RSVP-1
public RPCs, and inspected both grants and bodies (not name alone):

| Function | Grant | In-function guard before this pass | Verdict |
| --- | --- | --- | --- |
| `rpc_verify_phone_pin(text, text)` | `service_role` only | **none** -- relied purely on revoke/grant | **Real gap, genuinely exploitable.** No `auth.uid()` check is possible (it *is* the pre-authentication login step), so nothing else in the function stopped a direct anon/authenticated PostgREST call from brute-forcing any phone number's 4-digit PIN outside Node's rate limiter. **Fixed** in migration 073 by adding `perform public.require_service_role();` as its first statement. |
| `rpc_set_my_pin(text)` | `authenticated` | `auth.uid()` required, scoped to caller's own row | Ordinary authenticated self-service RPC. Unchanged -- it must keep working for a normal logged-in user. |
| `rpc_verify_my_pin(text)` | `authenticated` | `auth.uid()` required, scoped to caller's own row | Same as above. Unchanged. |
| `rpc_has_my_pin()` | `authenticated` | `auth.uid()` implicit in the query | Same as above. Unchanged. |
| `rpc_change_my_pin(text, text)` | `authenticated` | `auth.uid()` required | Same as above. Unchanged. |
| `is_weak_pin(text)` | (helper, no grant) | pure validation, no data access | Harmless regardless of exposure. Unchanged. |
| `rpc_get_public_invitation_detail` / `rpc_submit_public_invitation_rsvp` | `service_role` only | `require_service_role()` (added in RSVP-1) | Already hardened. Re-verified live in this pass, unchanged. |
| `rpc_complete_tenant_onboarding`, `rpc_invite_tenant_user`, `rpc_resend_tenant_invitation`, `rpc_accept_my_tenant_invitations`, `rpc_get_my_context`, `rpc_upsert_sms_template`, `rpc_enqueue_tenant_invitation_sms`, `rpc_list_tenant_users`, `rpc_update_tenant_user_role`, `rpc_set_tenant_user_status`, `rpc_update_member`, `rpc_list_organization_activity`, `rpc_rotate_invitation_public_token` | `authenticated` | `auth.uid()` + tenant/event permission checks | Ordinary tenant-authenticated RPCs, correctly granted to `authenticated` (not `service_role`). Out of scope for this guard by design -- adding `require_service_role()` to these would break normal login-based usage entirely. |

**Conclusion: exactly one function in the whole schema was genuinely
exposed and relying only on grants -- `rpc_verify_phone_pin`.** Every other
`service_role`-granted function (the two RSVP-1 public RPCs) already had the
guard. Every `authenticated`-granted function correctly depends on
`auth.uid()` and tenant/event permissions instead, and was deliberately left
untouched.

## `has_event_financial_access` review

Inspected the function body (migration 018). Despite its name, it is
**generic**: `p_permission` is a caller-supplied parameter, not hardcoded to
a pledge/payment code. It already backed non-financial permission checks
before RSVP-1 existed (e.g. `rpc_create_member_and_attach_to_event` calls it
with `'members.create'`). Passing `'invitation.view'`/`'rsvp.manage'`/etc.
follows the exact same established pattern -- it does not require the caller
to hold any `pledges.*`/`payments.*` permission, and does not make RSVP
authority depend on financial authority. **No replacement helper was
introduced.** This conclusion was proven live, not just argued from reading
the SQL -- see the verification section below.

## Live verification (throwaway Postgres 17, full replay of migrations 001-073)

All of the following were executed against a real database, not inferred
from source text:

1. `rpc_verify_phone_pin` called as `anon` and as `authenticated` (both with
   `request.jwt.claim.role` set to match, simulating real PostgREST
   behavior) -> both rejected with `TENANT_ACCESS_DENIED` before any phone
   lookup occurs.
2. `rpc_verify_phone_pin` called as `service_role` -> passes the guard and
   proceeds into its normal logic (returns `NO_VERIFIED_ACCOUNT` for a
   nonexistent phone, i.e. reaches real business logic instead of being
   rejected at the door).
3. `rpc_get_public_invitation_detail` / `rpc_submit_public_invitation_rsvp`
   re-verified: `anon` and `authenticated` rejected, `service_role` succeeds
   -- unchanged from RSVP-1, confirmed still correct after this migration.
4. An ordinary tenant-authenticated RPC (`rpc_create_contact`) still
   succeeds for a real `authenticated` tenant owner with the right
   permission -- proving the hardening pass did not collaterally break
   normal authenticated RPCs.
5. Cross-tenant invitation access: an `authenticated` user from a second,
   unrelated tenant calling `rpc_list_event_invitations` for the first
   tenant's event -> `EVENT_ACCESS_DENIED`; direct `SELECT` against
   `event_invitations`/`invitation_rsvps` as that user -> 0 rows via RLS.
6. A **custom tenant role** was created holding only `invitation.view` and
   `rsvp.manage` (no `pledges.*`, no `payments.*`, no `members.*`) and
   assigned to a test user via `event_user_assignments` at `COLLECT` level.
   That user successfully called `rpc_list_event_invitations` and
   `rpc_record_manual_rsvp` for the event they were assigned to.
7. A second custom tenant role was created holding only `pledges.create` and
   `payments.create` (financial permissions, no `rsvp.manage`) and assigned
   the same way. That user's call to `rpc_record_manual_rsvp` was rejected
   with `EVENT_ACCESS_DENIED` -- financial permission alone does not grant
   RSVP write authority.

Both 6 and 7 directly satisfy the request to prove
`has_event_financial_access` is semantically correct for this domain without
redesigning it.

## Was RSVP RLS changed?

No. The RLS policies added in migration 072 (`has_tenant_permission` /
`has_event_financial_access` against `invitation.*`/`rsvp.*`) were reviewed
and proven correct by the live tests above, not modified.
