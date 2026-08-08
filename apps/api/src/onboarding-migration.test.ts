import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/010_fix_onboarding_rpc.sql', import.meta.url), 'utf8')
const reonboardingMigration = readFileSync(new URL('../../../supabase/migrations/032_allow_reonboarding_after_tenant_reset.sql', import.meta.url), 'utf8')
const apiApp = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('onboarding migration resolves pgcrypto from the installed schema', () => {
  assert.match(migration, /create extension if not exists pgcrypto\s+with schema extensions;/i)
  assert.match(migration, /select namespace\.nspname into pgcrypto_schema/i)
  assert.match(migration, /%1\$I\.digest\(/)
})

test('onboarding migration keeps the RPC signature and fixes idempotency result write', () => {
  assert.match(migration, /create or replace function public\.rpc_complete_tenant_onboarding\(/i)
  assert.match(migration, /p_plan_code text/)
  assert.match(migration, /p_idempotency_key text default null/)
  assert.match(migration, /v_result := jsonb_build_object/i)
  assert.match(migration, /set result = v_result/i)
  assert.doesNotMatch(migration, /set result = result/i)
})

test('onboarding migration fails clearly when tenant owner seed role is missing', () => {
  assert.match(migration, /TENANT_OWNER_ROLE_MISSING/)
  assert.match(migration, /r\.tenant_id is null/)
})

test('API calls onboarding RPC with expected parameter names', () => {
  for (const parameter of ['p_plan_code', 'p_tenant_name', 'p_tenant_phone', 'p_first_event_name', 'p_event_type', 'p_idempotency_key']) {
    assert.match(apiApp, new RegExp(parameter))
  }
})

test('onboarding can run again after tenant data is reset but profile remains', () => {
  assert.match(reonboardingMigration, /profile_record\.onboarding_completed_at is not null and exists/)
  assert.match(reonboardingMigration, /from public\.tenant_users tu/)
  assert.match(reonboardingMigration, /join public\.tenants t on t\.id = tu\.tenant_id/)
  assert.match(reonboardingMigration, /tu\.user_id = caller/)
  assert.match(reonboardingMigration, /ONBOARDING_ALREADY_COMPLETED/)
})
