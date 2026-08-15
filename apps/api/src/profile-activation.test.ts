import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const activationMigration = readFileSync(new URL('../../../supabase/migrations/062_activate_profile_on_pin_setup.sql', import.meta.url), 'utf8')
const invitationMigration = readFileSync(new URL('../../../supabase/migrations/061_auth_entry_pending_invitations.sql', import.meta.url), 'utf8')
const apiApp = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('PIN setup activates the authenticated verified phone profile', () => {
  assert.match(activationMigration, /create or replace function public\.rpc_set_my_pin\(p_pin text\)/i)
  assert.match(activationMigration, /from auth\.users auth_user[\s\S]+auth_user\.id = v_user_id[\s\S]+auth_user\.phone_confirmed_at is not null/i)
  assert.match(activationMigration, /v_normalized_phone := public\.normalize_tz_phone\(v_auth_phone\)/i)
  assert.match(activationMigration, /insert into public\.profiles \(id, full_name, phone_e164, email, status\)/i)
  assert.match(activationMigration, /values \(v_user_id, coalesce\(v_metadata_name, ''\), v_normalized_phone, v_email, 'ACTIVE'\)/i)
  assert.match(activationMigration, /when public\.profiles\.status in \('DISABLED', 'SUSPENDED'\) then public\.profiles\.status[\s\S]+else 'ACTIVE'/i)
  assert.match(apiApp, /client\.rpc\('rpc_set_my_pin', \{ p_pin: input\.pin \}\)/)
})

test('pending invitation lookup remains active-profile scoped', () => {
  assert.match(invitationMigration, /from public\.profiles[\s\S]+where id = caller[\s\S]+and status = 'ACTIVE'/i)
  assert.match(invitationMigration, /ti\.phone_e164 = profile_record\.phone_e164/)
})

test('existing broken pending profiles are repaired only with verified phone and PIN credential', () => {
  assert.match(activationMigration, /update public\.profiles profile[\s\S]+set status = 'ACTIVE'/i)
  assert.match(activationMigration, /profile\.status = 'PENDING'/i)
  assert.match(activationMigration, /auth_user\.phone_confirmed_at is not null/i)
  assert.match(activationMigration, /regexp_replace\(coalesce\(auth_user\.phone, ''\), '\\D', '', 'g'\) = regexp_replace\(profile\.phone_e164, '\\D', '', 'g'\)/i)
  assert.match(activationMigration, /from private\.user_pin_credentials credential[\s\S]+credential\.user_id = profile\.id/i)
  assert.doesNotMatch(activationMigration, /where profile\.status = 'PENDING';/i)
})
