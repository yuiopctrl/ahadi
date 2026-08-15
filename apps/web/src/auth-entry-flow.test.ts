import { readFileSync } from 'node:fs'
import test from 'node:test'
import assert from 'node:assert/strict'

const authPage = readFileSync(new URL('./pages/auth.tsx', import.meta.url), 'utf8')
const api = readFileSync(new URL('./lib/api.ts', import.meta.url), 'utf8')
const access = readFileSync(new URL('./routes/access.ts', import.meta.url), 'utf8')
const layout = readFileSync(new URL('./layouts/TenantAppLayout.tsx', import.meta.url), 'utf8')

test('login keeps PIN login while exposing create account entry copy', () => {
  assert.match(authPage, /Phone number/)
  assert.match(authPage, /Forgot PIN\?/)
  assert.match(authPage, /New to Ahadi\?/)
  assert.match(authPage, /Create Account/)
})

test('create account flow checks account state before OTP and routes to profile then invitations', () => {
  assert.match(api, /accountState:/)
  assert.match(authPage, /api\.accountState\(normalized\)/)
  assert.match(authPage, /localStorage\.setItem\(postAuthDestinationKey, '\/register\/profile'\)/)
  assert.match(authPage, /navigate\(context\?\.pendingInvitations\?\.length \? '\/invitations' : '\/organizations\/new'/)
})

test('pending invitations route before organization creation and banner existing tenant access', () => {
  assert.match(access, /context\?\.pendingInvitations\?\.length/)
  assert.match(access, /return '\/organizations\/new'/)
  assert.match(layout, /pendingInvitations\.length/)
  assert.match(layout, /navigate\('\/invitations'\)/)
})
