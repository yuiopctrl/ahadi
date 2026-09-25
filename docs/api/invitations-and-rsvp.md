# Invitations and RSVP API (RSVP-1)

See [`docs/database/invitations-and-rsvp.md`](../database/invitations-and-rsvp.md)
for the domain model, RSVP business rules, public token design, RLS and
permissions. This document covers only the HTTP surface.

## Authenticated routes

All require `requireAuth, loadUserContext, requireTenantContext` (same as
every other tenant-scoped route) and a verified tenant/event permission
(enforced in the RPC layer, not in Node -- see the permissions table in the
database doc).

| Method | Path | RPC |
| --- | --- | --- |
| GET | `/api/v1/events/:eventId/invitation-settings` | `rpc_get_event_invitation_settings` |
| PUT | `/api/v1/events/:eventId/invitation-settings` | `rpc_upsert_event_invitation_settings` |
| GET | `/api/v1/events/:eventId/invitations` | `rpc_list_event_invitations` |
| POST | `/api/v1/events/:eventId/invitations` | `rpc_create_event_invitation` |
| POST | `/api/v1/events/:eventId/invitations/bulk` | `rpc_bulk_create_event_invitations` |
| GET | `/api/v1/events/:eventId/invitations/:invitationId` | `rpc_get_event_invitation_detail` |
| PATCH | `/api/v1/events/:eventId/invitations/:invitationId` | `rpc_update_event_invitation` |
| POST | `/api/v1/events/:eventId/invitations/:invitationId/activate` | `rpc_activate_event_invitation` |
| POST | `/api/v1/events/:eventId/invitations/:invitationId/cancel` | `rpc_cancel_event_invitation` |
| POST | `/api/v1/events/:eventId/invitations/:invitationId/rotate-link` | `rpc_rotate_invitation_public_token` |
| POST | `/api/v1/events/:eventId/invitations/:invitationId/rsvp` | `rpc_record_manual_rsvp` (organizer override) |
| GET | `/api/v1/events/:eventId/rsvp/dashboard` | `rpc_get_event_rsvp_dashboard` |

`GET .../invitations` supports `search`, `status`
(`ALL/DRAFT/ACTIVE/CANCELLED`), `rsvpStatus`
(`ALL/ATTENDING/MAYBE/NOT_ATTENDING/NO_RESPONSE`), `limit`, `offset`, and
returns the same `{ data, pagination: { limit, offset, totalRows, hasMore } }`
envelope already used by contacts/event-members/activity.

**Share link generation is on-demand, not blanket:** only the single-detail
route (`GET .../invitations/:invitationId`) and the rotate-link route attach
a `shareUrl` field (the signed public URL) to the response, built server-side
from the invitation's id + current `publicTokenVersion`. The list route never
returns a raw token.

## Public routes (no Changisha login)

| Method | Path |
| --- | --- |
| GET | `/api/v1/public/invitations/:token` |
| POST | `/api/v1/public/invitations/:token/rsvp` |

Both are rate-limited (`publicInvitationLimiter`, 30 requests/minute/IP) and
carry no auth middleware at all. Node verifies the HMAC signature in
`:token` itself (`verifyInvitationToken`); only on success does it call the
service-role client against the two service-only RPCs.

### `GET /api/v1/public/invitations/:token`

```json
{
  "data": {
    "invitation": { "displayName": "MR. VICTOR PREVER KINABO & FAMILY", "maxGuests": 4 },
    "event": {
      "name": "Jennifer Send Off",
      "message": null,
      "date": "2026-12-01",
      "time": null,
      "venueName": "Garden Hall",
      "venueAddress": null,
      "mapsUrl": null,
      "hostDisplayName": "The Kinabo Family"
    },
    "rsvpSettings": { "enabled": true, "deadline": null, "allowLateRsvp": false, "canRespond": true },
    "rsvp": {
      "response": "ATTENDING",
      "attendingCount": 3,
      "guestNames": ["Victor Kinabo", "Mary Kinabo"],
      "respondedAt": "2026-11-01T10:00:00Z"
    },
    "template": { "layoutKey": "CLASSIC", "config": {} }
  }
}
```

`rsvp` is `null` when no response has been submitted yet. Never present:
`tenantId`, `eventMemberId`, `memberId`, any phone number, pledge/payment
data, balance, internal notes, audit ids, `createdBy`, or permission info.

A valid `GET` also increments the invitation's `view_count` and
`first_viewed_at`/`last_viewed_at` (one `UPDATE` statement, invalid-token
requests are not counted).

### `POST /api/v1/public/invitations/:token/rsvp`

Request:

```json
{ "response": "ATTENDING", "attendingCount": 3, "guestNames": ["Victor Kinabo", "Mary Kinabo"], "note": "Optional" }
```

Response:

```json
{ "data": { "response": "ATTENDING", "attendingCount": 3, "guestNames": [...], "respondedAt": "...", "updated": true } }
```

`updated` is `true` when this call replaced an existing response, `false` on
a first-time submission. Node's Zod schema caps input size defensively
(`attendingCount <= 50`, `guestNames.length <= 50`, `note <= 500` chars) as
abuse protection independent of rate limiting, but the database transaction
remains authoritative for the real business rules (guest limit vs.
`max_guests`, deadline, invitation status).

## Environment variables

- `INVITATION_PUBLIC_TOKEN_SECRET` (required, min 32 chars) -- HMAC secret,
  server-only. Generate with `openssl rand -base64 48`.
- `INVITATION_PUBLIC_APP_BASE_URL` (default `http://localhost:5173/i`) --
  base URL the public link is built against; the API appends
  `/<signed-token>`. Never hard-code a production host in the database.
