import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const middleware = readFileSync(new URL('./middleware.ts', import.meta.url), 'utf8')
const normalization = readFileSync(new URL('./context-normalization.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/060_user_full_name_and_tenant_invitation_sms.sql', import.meta.url), 'utf8')

test('authenticated context normalizes profile names and phone fields for /me consumers', () => {
  assert.match(middleware, /normalizeUserContext\(data\)/)
  assert.match(normalization, /fullName: stringValue\(profile, 'fullName', 'full_name'\)/)
  assert.match(normalization, /phoneE164: stringValue\(profile, 'phoneE164', 'phone_e164'\)/)
  assert.match(normalization, /onboardingCompletedAt: nullableStringValue\(profile, 'onboardingCompletedAt', 'onboarding_completed_at'\)/)
  assert.match(normalization, /pendingInvitations:/)
})

test('auth context loading does not auto-accept pending invitations', () => {
  assert.doesNotMatch(middleware, /rpc_accept_my_tenant_invitations/)
})

test('onboarding persists adminFullName into the shared profile row without overwriting existing names', () => {
  const route = app.slice(
    app.indexOf("app.post('/api/v1/onboarding/complete'"),
    app.indexOf("app.get('/api/v1/me'"),
  )
  assert.match(route, /select\('full_name'\)/)
  assert.match(route, /!String\(profile\?\.full_name \?\? ''\)\.trim\(\)/)
  assert.match(route, /update\(\{ full_name: input\.adminFullName \}\)/)
})

test('tenant invitation migration queues SMS through the shared outbox architecture', () => {
  assert.match(migration, /'TENANT_INVITATION'/)
  assert.match(migration, /create or replace function public\.rpc_enqueue_tenant_invitation_sms/)
  assert.match(migration, /public\.tenant_sms_enabled\(p_tenant_id\)/)
  assert.match(migration, /public\.sms_allowance_status\(p_tenant_id, 1\)/)
  assert.match(migration, /public\.tenant_sms_provider_settings\(p_tenant_id\)/)
  assert.match(migration, /insert into public\.sms_outbox/)
  assert.match(migration, /public\.sms_character_count\(message\) > public\.sms_max_characters\(\)/)
})

test('invitation acceptance backfills blank profile names from pending invitations only', () => {
  const acceptFunction = migration.slice(
    migration.indexOf('create or replace function public.rpc_accept_my_tenant_invitations'),
    migration.indexOf('create or replace function public.rpc_get_my_context'),
  )
  assert.match(acceptFunction, /btrim\(coalesce\(profile_record\.full_name, ''\)\) = ''/)
  assert.match(acceptFunction, /btrim\(coalesce\(invitation_record\.full_name, ''\)\) <> ''/)
  assert.match(acceptFunction, /set full_name = btrim\(invitation_record\.full_name\)/)
})

test('tenant invitation resend queues a fresh bounded SMS attempt instead of duplicating invitations', () => {
  const resendFunction = migration.slice(
    migration.indexOf('create or replace function public.rpc_resend_tenant_invitation'),
    migration.indexOf('create or replace function public.rpc_accept_my_tenant_invitations'),
  )
  assert.match(resendFunction, /where id = p_invitation_id/)
  assert.match(resendFunction, /and status = 'INVITED'/)
  assert.match(resendFunction, /TENANT_INVITATION:RESEND:/)
  assert.match(resendFunction, /to_char\(now\(\), 'YYYYMMDDHH24MI'\)/)
  assert.match(resendFunction, /'smsQueued'/)
})
