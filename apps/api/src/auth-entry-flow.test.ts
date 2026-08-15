import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/061_auth_entry_pending_invitations.sql', import.meta.url), 'utf8')
const webAuth = readFileSync(new URL('../../web/src/pages/auth.tsx', import.meta.url), 'utf8')
const webRoutes = readFileSync(new URL('../../web/src/routes/index.tsx', import.meta.url), 'utf8')

test('create account checks verified account state before requesting OTP', () => {
  assert.match(app, /app\.post\('\/api\/v1\/auth\/account-state'/)
  assert.match(webAuth, /api\.accountState\(normalized\)/)
  assert.match(webAuth, /existingVerifiedAccount/)
  assert.match(webAuth, /api\.requestOtp\(normalized\)/)
})

test('registration routes separate account profile, invitations and organization creation', () => {
  assert.match(webRoutes, /path: '\/register\/profile'/)
  assert.match(webRoutes, /path: '\/invitations'/)
  assert.match(webRoutes, /path: '\/organizations\/new'/)
  assert.match(webRoutes, /Complete Profile/)
  assert.match(webAuth, /Join Organization/)
  assert.match(webAuth, /Create Organization/)
})

test('pending invitations are visible and accepted by authenticated verified phone only', () => {
  assert.match(migration, /create or replace function public\.rpc_list_my_tenant_invitations/)
  assert.match(migration, /normalized_phone text := public\.normalize_tz_phone\(p_phone_e164\)/)
  assert.match(migration, /elsif digits ~ '\^\[67\]\[0-9\]\{8\}\$'/)
  assert.match(migration, /ti\.phone_e164 = profile_record\.phone_e164/)
  assert.match(migration, /create or replace function public\.rpc_accept_tenant_invitation/)
  assert.match(migration, /invitation_record\.phone_e164 <> profile_record\.phone_e164/)
  assert.match(migration, /raise exception 'INVITATION_INVALID'/)
  assert.match(migration, /'pendingInvitations', public\.rpc_list_my_tenant_invitations\(\)/)
})
