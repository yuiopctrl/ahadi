# Invitations and RSVPs (RSVP-1)

## Domain model

```
Contact (public.members, org-wide)
  -> Event Member (public.event_members, a Contact attached to one Event)
    -> Invitation (public.event_invitations, one per Event Member per Event)
      -> RSVP (public.invitation_rsvps, the CURRENT response for that Invitation)
```

An invitation never requires a pledge. This domain (migration `072`) has zero
references to `public.pledges` or `public.payments`.

**Invitation status is not delivery status, and delivery status is not RSVP
status.** `event_invitations.status` is one of `DRAFT`, `ACTIVE`, `CANCELLED`
only -- never `SENT`, `VIEWED` or `RESPONDED`. Those are tracked separately:
delivery attempts in `invitation_deliveries`, view activity as
`first_viewed_at`/`last_viewed_at`/`view_count` on the invitation row, and the
guest's answer in `invitation_rsvps`.

**No RSVP row = No Response.** There is no `PENDING` RSVP row. An `ACTIVE`
invitation with no matching row in `invitation_rsvps` has simply not been
answered yet.

## Tables

- `invitation_templates` -- `PLATFORM` (tenant_id null) or `TENANT`-scoped
  card templates. RSVP-1 seeds one `PLATFORM` template (`CLASSIC`) and ships
  no template-authoring API; an invitation only needs to reference a valid,
  active template to activate.
- `event_invitation_settings` -- one row per Event. Holds only
  invitation-specific presentation fields and intentional overrides
  (`venue_name_override`, `rsvp_deadline`, `default_max_guests`, ...).
  `public.events` already owns name/date/venue; when no override is set the
  public read falls back to the real Event fields. `events` has no
  time-of-day or address/maps columns at all, so `event_time_display`,
  `venue_address_override` and `maps_url` are the sole source for those, not
  true overrides.
- `event_invitations` -- the core table. `unique (event_id, event_member_id)`
  enforces exactly one invitation per Event Member per Event; a cancelled
  invitation is never deleted, only marked `CANCELLED`. Also carries
  `public_token_version` (see [Public token design](#public-token-design))
  and lightweight view tracking (`view_count`, `first_viewed_at`,
  `last_viewed_at`).
- `invitation_deliveries` -- delivery history foundation only.
  `channel in ('SMS', 'WHATSAPP_SHARE', 'MANUAL_SHARE')`,
  `status in ('QUEUED', 'SENT', 'DELIVERED', 'FAILED')`. Nothing in RSVP-1
  actually sends anything; this table exists so a later phase has somewhere
  to record delivery attempts without a schema change.
- `invitation_rsvps` -- `unique (invitation_id)`: exactly one CURRENT row per
  invitation. A resubmission `UPDATE`s this same row (`on conflict
  (invitation_id) do update`); history lives in `audit_logs`, not extra rows.
  `submitted_by_type` is `PUBLIC_GUEST` (`submitted_by_user_id` must be null)
  or `TENANT_USER` (`submitted_by_user_id` required).
- `rsvp_guests` -- optional named guests for a response, replaced wholesale
  (delete + reinsert) on every RSVP write, in the same transaction as the
  RSVP upsert. `unique (rsvp_id, position)`. The count of named guests may be
  less than `attending_count`; it can never exceed it.

## RSVP business rules

Enforced identically for both the manual (organizer) and public (guest) RSVP
paths via one shared function, `validate_rsvp_input`:

- `ATTENDING` / `MAYBE`: `1 <= attending_count <= invitation.max_guests`.
- `NOT_ATTENDING`: `attending_count` must be `0` and `guest_names` must be
  empty.
- Guest names, when present, must never outnumber `attending_count`.

General gating, checked in `rpc_submit_public_invitation_rsvp` only (the
manual RPC intentionally skips all of it except the CANCELLED check, so an
organizer can record a walk-in RSVP regardless of activation state or
deadline):

- Invitation must not be `CANCELLED` (checked by both paths).
- For the public path only: invitation must be `ACTIVE` (not `DRAFT`), the
  event's RSVP settings must have `rsvp_enabled = true`, and if
  `rsvp_deadline` has passed, submission is blocked unless
  `allow_late_rsvp = true`.

## Public token design

Public invitation links carry a **stateless, HMAC-signed capability token**,
generated and verified entirely in Node (`apps/api/src/invitation-token.ts`)
-- nothing about the token itself is stored in the database, only the plain
integer `event_invitations.public_token_version`.

```
payload = "<invitationId>.<tokenVersion>"
token   = base64url(payload) + "." + base64url(HMAC-SHA256(secret, payload))
```

- Secret: `INVITATION_PUBLIC_TOKEN_SECRET` (server-only env var, never sent to
  Flutter/web/public clients).
- Verification uses `crypto.timingSafeEqual` for the signature comparison.
- **Rotation**: `rpc_rotate_invitation_public_token` increments
  `public_token_version`. Every previously issued token immediately fails
  verification against the new stored version -- no token blocklist needed.
- **Closing the rotate-after-decode race**: Node verifying the HMAC signature
  only proves "the holder of this string once had a version-N capability for
  this invitation." The two service-only RPCs
  (`rpc_get_public_invitation_detail`, `rpc_submit_public_invitation_rsvp`)
  independently re-check `p_token_version` against the invitation's *live*
  `public_token_version` inside the same transaction, so a link rotated after
  Node decoded an old token still fails at the database.
- A `CANCELLED` invitation's token is rejected (`INVITATION_CANCELLED`)
  regardless of whether the signature/version check passes.

### Token payload privacy (reviewed, unchanged by design)

The signed payload (`invitationId.tokenVersion`) is **readable** by whoever
holds the token -- `base64url` is an encoding, not encryption, and the HMAC
signature authenticates the payload without hiding it. This is deliberate,
not an oversight:

- The invitation UUID is **not treated as a secret**. It is a random,
  unguessable v4 UUID, but even if an attacker somehow learned one, that
  alone grants nothing.
- **Possession of the invitation UUID alone grants no access.** Every public
  route requires a valid HMAC signature over `invitationId.tokenVersion`,
  computed with a server-only secret (`INVITATION_PUBLIC_TOKEN_SECRET`) the
  client never sees. An attacker who only has the UUID (no signature) cannot
  construct a token that verifies.
- **A valid HMAC signature is required** for every public read/write --
  verified with `crypto.timingSafeEqual` in Node before the database is ever
  called.
- **Token rotation invalidates every previously issued signature** via the
  version check: rotating bumps `public_token_version`, and both service-only
  RPCs reject any token whose embedded version no longer matches the live
  row, regardless of whether the signature itself still verifies correctly
  against the secret.

No redesign was needed or made -- a signed-but-readable payload is the normal,
correct shape for this kind of capability token (comparable to a JWT), and
nothing in this scheme depends on the payload being confidential.

## Service-only RPCs and their access control

`rpc_get_public_invitation_detail` and `rpc_submit_public_invitation_rsvp`
are the only two functions the public API routes call, always via the
server-only service-role Supabase client (`supabaseAdmin`), never the
per-request user client. Both:

- `revoke all on function ... from public; grant execute ... to service_role;`
  (the pattern already established by `rpc_verify_phone_pin`, migration 055).
- **Additionally** call `public.require_service_role()` as their first
  statement, which checks the PostgREST-resolved role via the
  `request.jwt.claim.role` GUC and raises `TENANT_ACCESS_DENIED` if it is not
  `service_role`.

The second check exists because the first, on its own, was empirically found
**not sufficient**: this Supabase Postgres image runs a built-in
`issue_pg_graphql_access` event trigger (`ddl_command_end`) that
automatically re-grants `EXECUTE` on every function in `public` to
`anon`/`authenticated` -- including right after an explicit `REVOKE`, since a
`REVOKE` is itself a `ddl_command_end` event. This was caught by actually
running the migration against a throwaway Postgres 17 instance and
inspecting the resulting `pg_proc.proacl`, not by reading the SQL, and it
appears to affect the pre-existing `rpc_verify_phone_pin` the same way (flagged
here, not fixed there -- out of this phase's scope). `require_service_role()`
reads a GUC PostgREST sets from the JWT before doing `SET ROLE`, which is
unaffected both by `SECURITY DEFINER`'s privilege elevation (unlike
`current_user`) and by the event trigger (it is not a grant at all).

Two smaller internal helpers, `event_invitation_detail_json` and
`validate_invitation_template`, are deliberately **not** granted to
`authenticated` at all, because they do no tenant/event ownership check of
their own -- they only exist to be composed from inside RPCs that already
checked `has_event_financial_access`. Omitting the grant makes them
uncallable directly via PostgREST while still working when called
internally (a `security definer` function executes -- and therefore calls
other functions -- as its owner, not the original caller).

## RLS

All six tables have RLS enabled with tenant/event-scoped `authenticated`
policies only (`has_tenant_permission` / `has_event_financial_access`
against `invitation.*` / `rsvp.*`). No policy grants `anon` anything. Public
access goes only through the two service-only RPCs above.

## Permissions

`invitation.view`, `invitation.create`, `invitation.edit`,
`invitation.cancel`, `invitation.send`, `rsvp.view`, `rsvp.manage`.

`TENANT_OWNER` and `EVENT_ADMIN` get all seven. `TREASURER`, `COLLECTOR` and
`VIEWER` get `invitation.view` + `rsvp.view` only -- deliberately
conservative, matching how those roles are already scoped for other
features (migration 016), and granting no new create/edit/cancel/send/manage
authority beyond the two roles that already hold full event-management
authority.

Event-scoped RPC permission checks (`has_event_financial_access(tenant_id,
event_id, permission, min_assignment_level)`):

| RPC | permission | level |
| --- | --- | --- |
| `rpc_get_event_invitation_settings` / `rpc_list_event_invitations` / `rpc_get_event_invitation_detail` | `invitation.view` | `VIEW` |
| `rpc_upsert_event_invitation_settings` / `rpc_update_event_invitation` / `rpc_activate_event_invitation` / `rpc_rotate_invitation_public_token` | `invitation.edit` | `MANAGE` |
| `rpc_create_event_invitation` / `rpc_bulk_create_event_invitations` | `invitation.create` | `COLLECT` |
| `rpc_cancel_event_invitation` | `invitation.cancel` | `MANAGE` |
| `rpc_record_manual_rsvp` | `rsvp.manage` | `COLLECT` |
| `rpc_get_event_rsvp_dashboard` | `rsvp.view` | `VIEW` |

## Audit

`invitation.created`, `invitation.updated`, `invitation.activated`,
`invitation.cancelled`, `invitation.token_rotated`, `rsvp.submitted`,
`rsvp.updated`, `rsvp.overridden` are all written via the existing
`write_audit_log`. For `PUBLIC_GUEST` submissions, `actor_user_id` is `null`
automatically (`auth.uid()` is null under the service-role connection used
for public routes). A manual organizer RSVP is always audited as
`rsvp.overridden` (an organizer manually recording/overriding a response,
whether or not one already existed); a public resubmission is audited as
`rsvp.updated`; a public first-time submission as `rsvp.submitted`.

Plain `GET` views of a public invitation are **not** audited (that would
flood Organization Activity) -- they only update `view_count` /
`first_viewed_at` / `last_viewed_at` on the invitation row itself.

## Domain errors

`INVITATION_ALREADY_EXISTS` (409), `INVITATION_NOT_FOUND` (404),
`INVITATION_CANCELLED` (409), `INVITATION_NOT_ACTIVE` (409),
`INVITATION_GUEST_LIMIT_INVALID` (400),
`INVITATION_GUEST_LIMIT_BELOW_RSVP_COUNT` (409),
`INVITATION_TOKEN_INVALID` (401), `INVITATION_TOKEN_EXPIRED_OR_ROTATED` (401),
`INVITATION_TEMPLATE_NOT_FOUND` (404), `RSVP_DISABLED` (409),
`RSVP_DEADLINE_PASSED` (409), `RSVP_GUEST_COUNT_INVALID` (400),
`RSVP_GUEST_NAMES_EXCEED_COUNT` (400).

## Concurrency

No advisory locks were needed for this phase. Every write path relies on
existing Postgres primitives that already provide the required guarantee:

- Duplicate invitation creation: the `unique (event_id, event_member_id)`
  constraint, backed by an explicit pre-check plus a `when unique_violation`
  handler around the insert (same pattern as `MEMBER_PHONE_ALREADY_EXISTS`
  elsewhere in this codebase).
- RSVP upsert / guest replacement: `insert ... on conflict (invitation_id) do
  update`, with the guest-row delete+insert in the same transaction.
- Token rotation vs. a concurrent RSVP submission: `select ... for update` on
  the invitation row inside `rpc_submit_public_invitation_rsvp` naturally
  serializes against a concurrent `rpc_rotate_invitation_public_token`
  `UPDATE` on the same row -- whichever commits first is what the other sees.

## Later integration points (deferred to RSVP-2+)

- Flutter invitation UI, card designer, image generation, QR rendering.
- Actually sending anything through `invitation_deliveries` (SMS/WhatsApp) --
  the table and channel/status enums exist, nothing writes to them yet.
- Table/seat allocation, meal preferences, transport/accommodation,
  event-day check-in.
- WhatsApp Business API integration.
- Template authoring UI (beyond the one seeded `PLATFORM` template).
