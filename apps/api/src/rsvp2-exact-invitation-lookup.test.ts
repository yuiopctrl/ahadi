import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/076_rsvp2_exact_event_member_invitation_lookup.sql', import.meta.url), 'utf8')

function fn(name: string): string {
  const start = migration.indexOf(`function public.${name}(`)
  assert.notStrictEqual(start, -1, `migration must define ${name}`)
  const end = migration.indexOf('\n$$;', start)
  assert.notStrictEqual(end, -1, `could not find end of ${name}`)
  return migration.slice(start, end)
}

test('rpc_get_event_member_invitation is an exact (tenant_id, event_id, event_member_id) lookup -- no name/text comparison anywhere in the query', () => {
  const body = fn('rpc_get_event_member_invitation')
  assert.match(body, /where ei\.tenant_id = p_tenant_id\s*\n\s*and ei\.event_id = p_event_id\s*\n\s*and ei\.event_member_id = p_event_member_id/)
  assert.doesNotMatch(body, /full_name/)
  assert.doesNotMatch(body, /ilike/)
  assert.doesNotMatch(body, /display_name/)
})

test('rpc_get_event_member_invitation requires invitation.view and validates the event_member belongs to the same tenant+event before looking up an invitation', () => {
  const body = fn('rpc_get_event_member_invitation')
  assert.match(body, /has_event_financial_access\(p_tenant_id, p_event_id, 'invitation\.view', 'VIEW'\)/)
  assert.match(body, /where em\.id = p_event_member_id and em\.tenant_id = p_tenant_id and em\.event_id = p_event_id/)
  assert.match(body, /raise exception 'EVENT_MEMBER_NOT_FOUND'/)
})

test('rpc_get_event_member_invitation returns null (not an error, not an empty object) when no invitation exists, and reuses event_invitation_detail_json rather than re-selecting fields itself (no N+1 field duplication)', () => {
  const body = fn('rpc_get_event_member_invitation')
  assert.match(body, /if found_invitation_id is null then\s*\n\s*return null;/)
  assert.match(body, /return public\.event_invitation_detail_json\(found_invitation_id\);/)
})

test('GET /api/v1/events/:eventId/members/:eventMemberId/invitation exists, is exact-id-only (no search/name query params), and always returns { data } even when null', () => {
  const start = app.indexOf("app.get('/api/v1/events/:eventId/members/:eventMemberId/invitation'")
  assert.notStrictEqual(start, -1, 'the exact invitation-lookup route must exist')
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /rpc_get_event_member_invitation/)
  assert.match(routeBody, /p_event_member_id: eventMemberId/)
  assert.match(routeBody, /data: data \?\? null/)
  assert.doesNotMatch(routeBody, /query\.search|p_search/)
})
