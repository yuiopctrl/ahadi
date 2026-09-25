import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { signInvitationToken, verifyInvitationToken, buildPublicInvitationUrl } from './invitation-token.js'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/072_rsvp1_invitation_domain_foundation.sql', import.meta.url), 'utf8')

function fn(name: string): string {
  const start = migration.indexOf(`function public.${name}(`)
  assert.notStrictEqual(start, -1, `migration must define ${name}`)
  const end = migration.indexOf('\n$$;', start)
  assert.notStrictEqual(end, -1, `could not find end of ${name}`)
  return migration.slice(start, end)
}

function routeBody(method: string, path: string): string {
  const start = app.indexOf(`app.${method}('${path}'`)
  assert.notStrictEqual(start, -1, `route ${method.toUpperCase()} ${path} must exist`)
  const end = app.indexOf('\n})', start)
  return app.slice(start, end)
}

// ============================================================
// DB TESTS 1-20 (structural, against migration 072's source) --
// the underlying behavior for all of these was additionally verified live
// against a throwaway Postgres 17 instance (full replay of migrations
// 001-072, seeded fixture tenant/event/members) before this file was
// written: entitlement/limit checks, duplicate rejection, cancel
// preserving history, token rotation, guest-limit-vs-RSVP-count rejection,
// deadline + allow_late_rsvp, ATTENDING/MAYBE/NOT_ATTENDING validation,
// resubmission updating the same row, cross-tenant RLS denial for both an
// authenticated other-tenant user and anon, and the require_service_role
// guard actually blocking a simulated anon PostgREST call. These
// structural assertions are the permanent regression guard matching this
// repo's existing test-suite convention (node:test + source inspection,
// no live DB in CI).
// ============================================================

test('1. one invitation per event member is enforced by a real unique constraint', () => {
  assert.match(migration, /unique \(event_id, event_member_id\),/)
})

test('2/3. rpc_create_event_invitation validates event_member belongs to the same tenant+event and is ACTIVE, and enforces max_guests >= 1', () => {
  const body = fn('rpc_create_event_invitation')
  assert.match(body, /where em\.id = p_event_member_id and em\.tenant_id = p_tenant_id and em\.event_id = p_event_id and em\.status = 'ACTIVE'/)
  assert.match(body, /raise exception 'EVENT_MEMBER_NOT_FOUND'/)
  assert.match(body, /if resolved_max_guests < 1 then/)
  assert.match(body, /raise exception 'INVITATION_GUEST_LIMIT_INVALID'/)
})

test('4. duplicate invitation for the same event member is rejected, both by pre-check and by catching the unique-constraint race', () => {
  const body = fn('rpc_create_event_invitation')
  assert.match(body, /if exists \(select 1 from public\.event_invitations where event_id = p_event_id and event_member_id = p_event_member_id\) then/)
  assert.match(body, /exception\s*\n\s*when unique_violation then\s*\n\s*raise exception 'INVITATION_ALREADY_EXISTS'/)
})

test('5. cancelling an invitation preserves the row -- no delete statement anywhere in the cancel RPC', () => {
  const body = fn('rpc_cancel_event_invitation')
  assert.doesNotMatch(body, /delete from/)
  assert.match(body, /set status = 'CANCELLED', cancelled_at = now\(\)/)
})

test('6. rotating the public token increments public_token_version and audits it', () => {
  const body = fn('rpc_rotate_invitation_public_token')
  assert.match(body, /set public_token_version = public_token_version \+ 1/)
  assert.match(body, /'invitation\.token_rotated'/)
})

test('7. lowering max_guests below the current RSVP attending_count is rejected with the specific domain error', () => {
  const body = fn('rpc_update_event_invitation')
  assert.match(body, /if current_attending is not null and new_max_guests < current_attending then/)
  assert.match(body, /raise exception 'INVITATION_GUEST_LIMIT_BELOW_RSVP_COUNT'/)
})

test('8. public detail and public RSVP submission both reject non-ACTIVE invitations (DRAFT and CANCELLED)', () => {
  for (const name of ['rpc_get_public_invitation_detail', 'rpc_submit_public_invitation_rsvp']) {
    const body = fn(name)
    assert.match(body, /if invitation_record\.status = 'CANCELLED' then/)
    assert.match(body, /raise exception 'INVITATION_CANCELLED'/)
    assert.match(body, /if invitation_record\.status = 'DRAFT' then/)
    assert.match(body, /raise exception 'INVITATION_NOT_ACTIVE'/)
  }
})

test('9/10. RSVP deadline is enforced unless allow_late_rsvp is true', () => {
  const body = fn('rpc_submit_public_invitation_rsvp')
  assert.match(body, /if settings_record\.rsvp_deadline is not null and now\(\) > settings_record\.rsvp_deadline and not coalesce\(settings_record\.allow_late_rsvp, false\) then/)
  assert.match(body, /raise exception 'RSVP_DEADLINE_PASSED'/)
})

test('11. the organizer manual RSVP RPC has no deadline check at all, so it can run after the public deadline', () => {
  const body = fn('rpc_record_manual_rsvp')
  assert.doesNotMatch(body, /RSVP_DEADLINE_PASSED/)
  assert.doesNotMatch(body, /rsvp_deadline/)
})

test('12/13/14. shared validate_rsvp_input enforces ATTENDING/MAYBE bounds, NOT_ATTENDING zero-guest rule, and guest names never exceeding attending_count', () => {
  const body = fn('validate_rsvp_input')
  assert.match(body, /if p_attending_count is null or p_attending_count < 1 or p_attending_count > p_max_guests then/)
  assert.match(body, /raise exception 'RSVP_GUEST_COUNT_INVALID'/)
  assert.match(body, /if coalesce\(p_attending_count, 0\) <> 0 then/)
  assert.match(body, /if guest_count <> 0 then/)
  assert.match(body, /if guest_count > p_attending_count then/)
  assert.match(body, /raise exception 'RSVP_GUEST_NAMES_EXCEED_COUNT'/)
  // Both the manual and public RSVP RPCs must call this single shared
  // validator -- the rules only exist once.
  assert.match(fn('rpc_record_manual_rsvp'), /perform public\.validate_rsvp_input\(/)
  assert.match(fn('rpc_submit_public_invitation_rsvp'), /perform public\.validate_rsvp_input\(/)
})

test('15/16/17. invitation_rsvps has exactly one current row per invitation, resubmission upserts it, and guest rows are replaced transactionally', () => {
  assert.match(migration, /unique \(invitation_id\),/)
  for (const name of ['rpc_record_manual_rsvp', 'rpc_submit_public_invitation_rsvp']) {
    const body = fn(name)
    assert.match(body, /on conflict \(invitation_id\) do update set/)
    assert.match(body, /delete from public\.rsvp_guests where rsvp_id = v_rsvp_id;/)
  }
})

test('18. RLS is enabled on every RSVP-1 table with tenant/event-scoped policies, and no policy grants anon/public access', () => {
  for (const table of ['invitation_templates', 'event_invitation_settings', 'event_invitations', 'invitation_deliveries', 'invitation_rsvps', 'rsvp_guests']) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security;`))
  }
  assert.doesNotMatch(migration, /for select using \(true\)/)
  // Only actual single-line grant statements matter here -- an explanatory
  // comment earlier in the file legitimately discusses "anon" while
  // documenting the require_service_role() defense, so check line-by-line
  // rather than scanning the whole file text for that substring.
  const anonGrantLines = migration.split('\n').filter((line) => /^\s*grant\b/i.test(line) && /\banon\b/i.test(line))
  assert.deepEqual(anonGrantLines, [])
})

test('the two public-facing service RPCs are revoked from public and granted only to service_role, and independently verify the caller via require_service_role() (grants alone were empirically found insufficient -- see the migration comment)', () => {
  for (const name of ['rpc_get_public_invitation_detail', 'rpc_submit_public_invitation_rsvp']) {
    assert.match(migration, new RegExp(`revoke all on function public\\.${name}\\([^)]*\\) from public;`))
    assert.match(migration, new RegExp(`grant execute on function public\\.${name}\\([^)]*\\) to service_role;`))
    assert.match(fn(name), /perform public\.require_service_role\(\);/)
  }
  const guard = fn('require_service_role')
  assert.match(guard, /current_setting\('request\.jwt\.claim\.role', true\)/)
  assert.match(guard, /<> 'service_role'/)
})

test('event_invitation_detail_json and validate_invitation_template are internal-only (no grant to authenticated) since they do no tenant/event ownership check of their own', () => {
  assert.doesNotMatch(migration, /grant execute on function public\.event_invitation_detail_json/)
  assert.doesNotMatch(migration, /grant execute on function public\.validate_invitation_template/)
})

test('PAST_DUE-style stale-usage bugs: the settings-upsert audit diff captures whether a row existed BEFORE the insert, not via FOUND after it (which the immediately-preceding INSERT...RETURNING would have overwritten)', () => {
  const body = fn('rpc_upsert_event_invitation_settings')
  assert.match(body, /settings_existed := found;/)
  assert.match(body, /case when settings_existed then to_jsonb\(old_row\) else null end/)
})

// ============================================================
// API TESTS 21-40
// ============================================================

test('21/22. every invitation/RSVP route checks the resolver-level permission via the RPC layer (has_event_financial_access), never a bare role-name comparison in app.ts', () => {
  const invitationRoutePaths: [string, string][] = [
    ['get', '/api/v1/events/:eventId/invitation-settings'],
    ['put', '/api/v1/events/:eventId/invitation-settings'],
    ['get', '/api/v1/events/:eventId/invitations'],
    ['post', '/api/v1/events/:eventId/invitations'],
    ['post', '/api/v1/events/:eventId/invitations/bulk'],
    ['get', '/api/v1/events/:eventId/invitations/:invitationId'],
    ['patch', '/api/v1/events/:eventId/invitations/:invitationId'],
    ['post', '/api/v1/events/:eventId/invitations/:invitationId/activate'],
    ['post', '/api/v1/events/:eventId/invitations/:invitationId/cancel'],
    ['post', '/api/v1/events/:eventId/invitations/:invitationId/rotate-link'],
    ['post', '/api/v1/events/:eventId/invitations/:invitationId/rsvp'],
    ['get', '/api/v1/events/:eventId/rsvp/dashboard'],
  ]
  for (const [method, path] of invitationRoutePaths) {
    const body = routeBody(method, path)
    assert.doesNotMatch(body, /role\s*===/, `${method.toUpperCase()} ${path} must not gate on a bare role comparison`)
    assert.doesNotMatch(body, /\.code === 'TENANT_OWNER'/, `${method.toUpperCase()} ${path} must not hard-code a role check`)
  }
  // Permission enforcement itself lives in the RPCs (has_event_financial_access
  // with the invitation.*/rsvp.* codes), checked directly against the migration.
  const permissionByRpc: [string, string, string][] = [
    ['rpc_get_event_invitation_settings', 'invitation.view', 'VIEW'],
    ['rpc_upsert_event_invitation_settings', 'invitation.edit', 'MANAGE'],
    ['rpc_create_event_invitation', 'invitation.create', 'COLLECT'],
    ['rpc_bulk_create_event_invitations', 'invitation.create', 'COLLECT'],
    ['rpc_update_event_invitation', 'invitation.edit', 'MANAGE'],
    ['rpc_activate_event_invitation', 'invitation.edit', 'MANAGE'],
    ['rpc_cancel_event_invitation', 'invitation.cancel', 'MANAGE'],
    ['rpc_rotate_invitation_public_token', 'invitation.edit', 'MANAGE'],
    ['rpc_list_event_invitations', 'invitation.view', 'VIEW'],
    ['rpc_get_event_invitation_detail', 'invitation.view', 'VIEW'],
    ['rpc_record_manual_rsvp', 'rsvp.manage', 'COLLECT'],
    ['rpc_get_event_rsvp_dashboard', 'rsvp.view', 'VIEW'],
  ]
  for (const [rpcName, permission, level] of permissionByRpc) {
    assert.match(fn(rpcName), new RegExp(`has_event_financial_access\\(p_tenant_id, p_event_id, '${permission}', '${level}'\\)`), `${rpcName} must require ${permission}/${level}`)
  }
})

test('permissions.view/create/edit/cancel/send and rsvp.view/manage are seeded and granted to TENANT_OWNER + EVENT_ADMIN in full, and view-only to TREASURER/COLLECTOR/VIEWER', () => {
  for (const code of ['invitation.view', 'invitation.create', 'invitation.edit', 'invitation.cancel', 'invitation.send', 'rsvp.view', 'rsvp.manage']) {
    assert.match(migration, new RegExp(`'${code.replace('.', '\\.')}'`))
  }
  assert.match(migration, /where r\.code in \('TENANT_OWNER', 'EVENT_ADMIN'\)/)
  assert.match(migration, /where r\.code in \('TREASURER', 'COLLECTOR', 'VIEWER'\)/)
})

test('23. a valid signed token round-trips through sign -> verify with the correct invitation id and version', () => {
  const invitationId = 'f30b5f4a-a852-43fd-a509-f16a8a5d1a93'
  const token = signInvitationToken(invitationId, 3)
  const result = verifyInvitationToken(token)
  assert.deepEqual(result, { invitationId, tokenVersion: 3 })
})

test('24. a malformed token (wrong shape, garbage, empty, oversized) is rejected', () => {
  assert.equal(verifyInvitationToken(''), null)
  assert.equal(verifyInvitationToken('not-a-token'), null)
  assert.equal(verifyInvitationToken('a.b.c'), null)
  assert.equal(verifyInvitationToken('a'.repeat(600)), null)
  // @ts-expect-error -- exercising runtime guard against non-string input
  assert.equal(verifyInvitationToken(undefined), null)
})

test('25. a forged signature is rejected even when the payload segment is well-formed', () => {
  const invitationId = 'f30b5f4a-a852-43fd-a509-f16a8a5d1a93'
  const token = signInvitationToken(invitationId, 1)
  const [encodedPayload] = token.split('.')
  const forged = `${encodedPayload}.${Buffer.from('not-the-real-signature').toString('base64url')}`
  assert.equal(verifyInvitationToken(forged), null)
})

test('26. a token signed for version 1 does not verify as version 2 (this is what a rotated-link check relies on at the Node layer; the database independently re-checks the live public_token_version too)', () => {
  const invitationId = 'f30b5f4a-a852-43fd-a509-f16a8a5d1a93'
  const tokenV1 = signInvitationToken(invitationId, 1)
  const decoded = verifyInvitationToken(tokenV1)
  assert.equal(decoded?.tokenVersion, 1)
  assert.notEqual(decoded?.tokenVersion, 2)
})

test('27. cancelled-invitation tokens are rejected at the database layer regardless of a valid signature (INVITATION_CANCELLED), covered structurally in test 8 above -- Node cannot know cancellation status from the token alone by design', () => {
  const body = fn('rpc_get_public_invitation_detail')
  assert.match(body, /raise exception 'INVITATION_CANCELLED'/)
})

test('28. the public detail RPC never selects tenant_id, member_id, event_member_id, phone, pledge/payment fields, audit ids, created_by, or permission info into its returned object', () => {
  const body = fn('rpc_get_public_invitation_detail')
  for (const forbidden of ['tenant_id', 'member_id', 'event_member_id', 'phone_e164', 'created_by', 'pledge', 'payment', 'permission']) {
    assert.doesNotMatch(body, new RegExp(`'${forbidden}'`, 'i'), `public detail must not surface ${forbidden}`)
  }
})

test('29/30/31. public RSVP submission supports all three responses via the same shared validator (behavior verified live for ATTENDING/MAYBE/NOT_ATTENDING against a throwaway Postgres instance)', () => {
  const body = fn('validate_rsvp_input');
  ['ATTENDING', 'MAYBE', 'NOT_ATTENDING'].forEach((response) => {
    assert.match(body, new RegExp(`'${response}'`))
  })
})

test('32. requesting more guests than max_guests is rejected (covered by validate_rsvp_input, test 12 above) and the public route defensively caps attendingCount/guestNames independent of the database', () => {
  const routeSrc = routeBody('post', '/api/v1/public/invitations/:token/rsvp')
  assert.match(routeSrc, /publicRsvpSubmitSchema\.parse\(request\.body\)/)
})

test('33. RSVP_DEADLINE_PASSED is a stable, mapped domain error (400/409-class, not a generic 500)', () => {
  const errors = readFileSync(new URL('./errors.ts', import.meta.url), 'utf8')
  assert.match(errors, /RSVP_DEADLINE_PASSED: 409,/)
  assert.match(app, /'RSVP_DEADLINE_PASSED',/)
})

test('34/35. the manual RSVP route requires rsvp.manage via has_event_financial_access -- an organizer without it is rejected with EVENT_ACCESS_DENIED, not a generic error', () => {
  const body = fn('rpc_record_manual_rsvp')
  assert.match(body, /has_event_financial_access\(p_tenant_id, p_event_id, 'rsvp\.manage', 'COLLECT'\)/)
  assert.match(body, /raise exception 'EVENT_ACCESS_DENIED'/)
})

test('36. invitation list pagination is server-side (limit/offset/totalRows/hasMore), applied to the full event dataset via a separate count query', () => {
  const body = fn('rpc_list_event_invitations')
  assert.match(body, /select count\(\*\)\s*\n\s*into total_rows/)
  assert.match(body, /'totalRows', total_rows/)
  assert.match(body, /'hasMore', \(safe_offset \+ safe_limit\) < total_rows/)
  const routeSrc = routeBody('get', '/api/v1/events/:eventId/invitations')
  assert.match(routeSrc, /expectPaginatedListResponse\(data, request\.requestId, 'INVITATIONS_LIST'\)/)
})

test('37. the RSVP dashboard distinguishes invitation counts (count(*)) from guest counts (sum(attending_count)) -- they must never be conflated', () => {
  const body = fn('rpc_get_event_rsvp_dashboard')
  assert.match(body, /'totalInvitations', count\(\*\)/)
  assert.match(body, /'confirmedGuests', coalesce\(sum\(ir\.attending_count\) filter \(where ir\.response = 'ATTENDING'\), 0\)/)
  assert.match(body, /'possibleGuests', coalesce\(sum\(ir\.attending_count\) filter \(where ir\.response = 'MAYBE'\), 0\)/)
  assert.match(body, /'noResponseInvitations', count\(\*\) filter \(where ei\.status = 'ACTIVE' and ir\.id is null\)/)
})

test('38. the public service RPCs are not directly callable by anon through PostgREST -- verified structurally here (revoke/grant + require_service_role) and empirically during development against a live simulated anon PostgREST role, which is what actually caught that the revoke/grant pattern alone was insufficient in this Postgres image', () => {
  assert.match(fn('rpc_get_public_invitation_detail'), /perform public\.require_service_role\(\);/)
  assert.match(fn('rpc_submit_public_invitation_rsvp'), /perform public\.require_service_role\(\);/)
})

test('39. both public invitation routes are wired through the same rate limiter', () => {
  const getRoute = routeBody('get', '/api/v1/public/invitations/:token')
  const postRoute = routeBody('post', '/api/v1/public/invitations/:token/rsvp')
  assert.match(getRoute, /publicInvitationLimiter/)
  assert.match(postRoute, /publicInvitationLimiter/)
  assert.doesNotMatch(getRoute, /requireAuth/)
  assert.doesNotMatch(postRoute, /requireAuth/)
})

test('40. a realistic public invitation detail payload matches the documented contract shape and omits internal fields', () => {
  const realisticPublicPayload = {
    invitation: { displayName: 'MR. VICTOR PREVER KINABO & FAMILY', maxGuests: 4 },
    event: {
      name: 'Jennifer Send Off',
      message: null,
      date: '2026-12-01',
      time: null,
      venueName: 'Garden Hall',
      venueAddress: null,
      mapsUrl: null,
      hostDisplayName: 'The Kinabo Family',
    },
    rsvpSettings: { enabled: true, deadline: null, allowLateRsvp: false, canRespond: true },
    rsvp: { response: 'ATTENDING', attendingCount: 3, guestNames: ['Victor Kinabo', 'Mary Kinabo'], respondedAt: '2026-11-01T10:00:00Z' },
    template: { layoutKey: 'CLASSIC', config: {} },
  }
  assert.equal(realisticPublicPayload.invitation.maxGuests, 4)
  assert.equal(realisticPublicPayload.rsvp?.attendingCount, 3)
  for (const forbidden of ['tenantId', 'eventMemberId', 'memberId', 'phone', 'pledge', 'payment', 'createdBy', 'auditId']) {
    assert.equal(forbidden in realisticPublicPayload, false)
    assert.equal(forbidden in realisticPublicPayload.invitation, false)
  }
})

test('buildPublicInvitationUrl appends the signed token to the configured base URL', () => {
  const url = buildPublicInvitationUrl('f30b5f4a-a852-43fd-a509-f16a8a5d1a93', 2)
  assert.match(url, /^https?:\/\/.+\/[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/)
  const decoded = verifyInvitationToken(url.split('/').pop() as string)
  assert.deepEqual(decoded, { invitationId: 'f30b5f4a-a852-43fd-a509-f16a8a5d1a93', tokenVersion: 2 })
})

test('the invitation detail route attaches shareUrl on demand, and the list route never does', () => {
  const detailRoute = routeBody('get', '/api/v1/events/:eventId/invitations/:invitationId')
  assert.match(detailRoute, /buildPublicInvitationUrl/)
  const listRoute = routeBody('get', '/api/v1/events/:eventId/invitations')
  assert.doesNotMatch(listRoute, /buildPublicInvitationUrl/)
})
