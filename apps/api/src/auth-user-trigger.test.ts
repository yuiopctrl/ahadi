import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const migration = readFileSync(fileURLToPath(new URL('../../../supabase/migrations/003_profiles_and_rbac.sql', import.meta.url)), 'utf8')
const triggerFunction = migration.slice(migration.indexOf('create or replace function public.handle_new_auth_user()'), migration.indexOf('drop trigger if exists on_auth_user_created'))

test('auth user profile trigger is phone-only safe', () => {
  assert.match(triggerFunction, /create or replace function public\.handle_new_auth_user\(\)/)
  assert.match(triggerFunction, /security definer/i)
  assert.match(triggerFunction, /set search_path = public, auth/i)
  assert.match(triggerFunction, /coalesce\(new\.phone, new\.raw_user_meta_data ->> 'phone', ''\)/)
  assert.match(triggerFunction, /new\.email/)
  assert.doesNotMatch(triggerFunction, /tenant_id.*not null/i)
  assert.doesNotMatch(triggerFunction, /raw_user_meta_data ->> 'tenant_id'/i)
})
