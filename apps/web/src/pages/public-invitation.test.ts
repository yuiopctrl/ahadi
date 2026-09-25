import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const page = readFileSync(new URL('./public-invitation.tsx', import.meta.url), 'utf8')
const routes = readFileSync(new URL('../routes/index.tsx', import.meta.url), 'utf8')
const api = readFileSync(new URL('../lib/api.ts', import.meta.url), 'utf8')

// 23. /i/:token is accessible without login -- registered as a top-level
// route, not nested under PublicRoute/AuthenticatedRoute/any guard (which
// wait on session bootstrap and can redirect).
test('23. /i/:token is registered outside every auth guard', () => {
  const routeIndex = routes.indexOf("{ path: '/i/:token'")
  assert.notStrictEqual(routeIndex, -1, 'the public invitation route must exist')
  // Search for actual usage (`element: <PublicRoute`), not the import
  // statement, which always appears earlier in the file regardless of
  // where the route array itself places things.
  const guardUsageIndex = routes.indexOf('element: <PublicRoute')
  assert.ok(routeIndex < guardUsageIndex, 'the public route must be declared before (outside) the guard tree')
  const routerArrayStart = routes.indexOf('createBrowserRouter([')
  // Only actual JSX usage matters here -- the explanatory comment above the
  // route legitimately names both guards.
  assert.doesNotMatch(routes.slice(routerArrayStart, routeIndex), /element: <(PublicRoute|AuthenticatedRoute)/)
})

test('public API calls for the invitation page never attach a session bearer token', () => {
  const publicInvitationCall = api.slice(api.indexOf('publicInvitation:'), api.indexOf('submitPublicRsvp:'))
  const submitRsvpCall = api.slice(api.indexOf('submitPublicRsvp:'), api.indexOf('submitPublicRsvp:') + 400)
  assert.match(publicInvitationCall, /auth: false/)
  assert.match(submitRsvpCall, /auth: false/)
})

// 24/25. valid invitation renders, and with no RSVP shows the response form.
test('24/25. a loaded invitation with no existing RSVP renders the response form, not the read-only/success view', () => {
  assert.match(page, /rsvpSettings\.canRespond && !data\.rsvp/) // form path is reachable when there's no rsvp yet
  assert.match(page, /existing \? 'Your RSVP' : 'Will you attend\?'/)
})

// 26/27/28. ATTENDING/MAYBE submit a guest count; NOT_ATTENDING forces zero
// and an empty guest list, matching the backend's own business rules.
test('26/27/28. submit payload forces attendingCount 0 and empty guestNames for NOT_ATTENDING', () => {
  const submitBody = page.slice(page.indexOf('async function submit()'), page.indexOf('async function submit()') + 700)
  assert.match(submitBody, /attendingCount: response === 'NOT_ATTENDING' \? 0 : guestCount/)
  assert.match(submitBody, /guestNames: response === 'NOT_ATTENDING' \? \[\] : guestNames\.filter/)
})

test('the response selector offers exactly Attending/Maybe/Not Attending, and guest fields are hidden for NOT_ATTENDING', () => {
  assert.match(page, /\['ATTENDING', 'Yes'\]/)
  assert.match(page, /\['MAYBE', 'Maybe'\]/)
  assert.match(page, /\['NOT_ATTENDING', 'No'\]/)
  assert.match(page, /const showGuestFields = response !== 'NOT_ATTENDING'/)
})

// 29/30. an existing RSVP pre-fills the form and offers Change RSVP when
// still editable.
test('29/30. an existing RSVP pre-fills response/guestCount/guestNames, and "Change RSVP" re-enters edit mode', () => {
  const loadBody = page.slice(page.indexOf('function load()'), page.indexOf('useEffect(load'))
  assert.match(loadBody, /setResponse\(payload\.rsvp\.response\)/)
  assert.match(loadBody, /setGuestCount\(payload\.rsvp\.attendingCount \|\| 1\)/)
  assert.match(loadBody, /setGuestNames\(payload\.rsvp\.guestNames/)
  assert.match(page, /Change RSVP/)
  assert.match(page, /onClick=\{onEdit\}/)
})

// 31. closed RSVP (deadline passed, late RSVP not allowed) with an existing
// response shows it read-only instead of an editable form.
test('31. a closed RSVP with an existing response renders read-only, not an editable form', () => {
  assert.match(page, /const showReadOnly = !!data\.rsvp && !rsvpSettings\.canRespond && !editing/)
  assert.match(page, /showReadOnly \? \(\s*<ExistingRsvpReadOnly/)
  assert.match(page, /can no longer be changed/)
})

// 32/33. invalid token and cancelled invitation both render the SAME
// generic message -- distinguishing them would let an attacker probing
// tokens learn whether a link was ever valid.
test('32/33. invalid/expired token and a cancelled invitation map to the same generic "not available" message', () => {
  const fnBody = page.slice(page.indexOf('function unavailableReasonFrom'), page.indexOf('export function PublicInvitationPage'))
  assert.match(fnBody, /return 'This invitation is not available\.'/)
  // Only INVITATION_NOT_ACTIVE (a draft, not yet sent) gets a distinct,
  // still-generic "not yet available" message; cancelled/invalid/rotated
  // all fall through to the identical default string above.
  assert.doesNotMatch(fnBody, /INVITATION_CANCELLED/)
  assert.doesNotMatch(fnBody, /INVITATION_TOKEN_INVALID/)
  assert.doesNotMatch(fnBody, /INVITATION_TOKEN_EXPIRED_OR_ROTATED/)
})

test('the page never renders a raw PGRST/Postgres code or an internal id anywhere in its source', () => {
  assert.doesNotMatch(page, /PGRST\d/)
  assert.doesNotMatch(page, /entity_id|audit_id|request_id/)
})

// 34. the public page's own data contract and JSX never reference
// tenant/member/financial/internal fields -- only what the public API is
// documented to return.
test('34. the page never references tenant/member/financial/internal fields', () => {
  for (const forbidden of ['tenantId', 'eventMemberId', 'memberId', 'phone', 'pledge', 'payment', 'createdBy', 'auditId', 'publicTokenVersion']) {
    assert.doesNotMatch(page, new RegExp(forbidden, 'i'), `public-invitation.tsx must not reference ${forbidden}`)
  }
})

// 35. mobile-first responsive structure: a constrained max width with
// responsive padding breakpoints, not a fixed desktop-only layout.
test('35. the page shell is mobile-first responsive (constrained width, responsive padding, no fixed pixel width)', () => {
  assert.match(page, /max-w-md/)
  assert.match(page, /sm:py-14/)
  assert.doesNotMatch(page, /width:\s*\d+px/)
})

// 36. the "Get Directions" maps button only renders when mapsUrl exists,
// both on the main page and in the success summary.
test('36. Get Directions only renders when event.mapsUrl is present', () => {
  const occurrences = [...page.matchAll(/event\.mapsUrl && \(/g)]
  assert.ok(occurrences.length >= 1, 'at least one maps-conditional render')
  const getDirectionsCount = [...page.matchAll(/Get Directions/g)].length
  const mapsGuardCount = [...page.matchAll(/\{event\.mapsUrl && \(/g)].length
  assert.equal(getDirectionsCount, mapsGuardCount, 'every "Get Directions" button must be behind an event.mapsUrl guard')
})

test('submit-time domain errors (RSVP_DISABLED, RSVP_DEADLINE_PASSED, guest count/name errors) get guest-friendly messages, not raw codes', () => {
  const fnBody = page.slice(page.indexOf('function publicRsvpErrorMessage'), page.indexOf('function PublicShell'))
  assert.match(fnBody, /case 'RSVP_DISABLED':/)
  assert.match(fnBody, /case 'RSVP_DEADLINE_PASSED':/)
  assert.match(fnBody, /case 'RSVP_GUEST_COUNT_INVALID':/)
  assert.match(fnBody, /case 'RSVP_GUEST_NAMES_EXCEED_COUNT':/)
})
