import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/026_share_and_event_creation_stabilization.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('share preview access uses event financial access and active pledged members', () => {
  assert.match(migration, /rpc_generate_event_whatsapp_share_preview/)
  assert.match(migration, /has_event_financial_access\(p_tenant_id, p_event_id, 'members\.view', 'VIEW'\)/)
  assert.doesNotMatch(migration, /not found or not public\.can_access_event\(p_event_id\)/)
  assert.match(migration, /left join public\.pledges p on p\.event_member_id = em\.id and p\.status <> 'CANCELLED'/)
  assert.match(migration, /em\.status = 'ACTIVE'/)
  assert.match(migration, /p\.id is not null/)
  assert.doesNotMatch(migration, /phone_e164 is not null[\s\S]+normalized_format = 'DETAILED'/)
})

test('event usage uses draft and active slots with snapshot entitlement diagnostics', () => {
  assert.match(migration, /e\.status in \('DRAFT', 'ACTIVE'\)/)
  assert.match(migration, /planCurrentMaxActiveEvents/)
  assert.match(migration, /subscriptionSnapshotMaxActiveEvents/)
  assert.match(migration, /effectiveMaxActiveEvents/)
  assert.match(migration, /'eventUsage', public\.event_slot_usage\(p_tenant_id\)/)
})

test('event create route is server-authorized and uses create RPC', () => {
  assert.match(app, /app\.post\('\/api\/v1\/events', requireAuth, loadUserContext, requireTenantContext/)
  assert.match(app, /request\.tenantContext\?\.accessState === 'READ_ONLY'/)
  assert.match(app, /rpc\('rpc_create_event'/)
  assert.match(migration, /pg_advisory_xact_lock\(hashtextextended\(p_tenant_id::text \|\| ':event-create'/)
  assert.match(migration, /EVENT_LIMIT_REACHED/)
  assert.match(migration, /insert into public\.event_user_assignments/)
  assert.match(migration, /write_audit_log\(p_tenant_id, 'event\.created'/)
})
