import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/026_share_and_event_creation_stabilization.sql', import.meta.url), 'utf8')
const repairMigration = readFileSync(new URL('../../../supabase/migrations/034_repair_event_create_rpc_overload.sql', import.meta.url), 'utf8')
const v2Migration = readFileSync(new URL('../../../supabase/migrations/035_event_create_v2_non_overloaded_rpc.sql', import.meta.url), 'utf8')
const v2AmbiguityFixMigration = readFileSync(new URL('../../../supabase/migrations/036_fix_event_create_v2_ambiguous_columns.sql', import.meta.url), 'utf8')
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
  assert.match(app, /event_slot_usage/)
  assert.match(app, /throw new AppError\('EVENT_LIMIT_REACHED'/)
  assert.match(app, /rpc\('rpc_create_event_v2'/)
  assert.match(app, /normalizeCreateEventInput/)
  assert.match(app, /EVENT_CREATE_PERMISSION_OK/)
  assert.match(app, /EVENT_CREATE_SLOT_CHECK_OK/)
  assert.match(app, /EVENT_CREATE_DB_START/)
  assert.match(app, /shouldUseDirectEventCreateFallback/)
  assert.match(app, /EVENT_CREATE_DB_FAILED_WITH_KNOWN_RPC_AMBIGUITY/)
  assert.match(app, /event-create-v2-ambiguous-column/)
  assert.match(app, /shouldRetryLegacyCreateEvent/)
  assert.match(app, /p_custom_event_type/)
  assert.match(app, /logDatabaseError\(request\.requestId, 'event-create'/)
  assert.match(migration, /pg_advisory_xact_lock\(hashtextextended\(p_tenant_id::text \|\| ':event-create'/)
  assert.match(migration, /EVENT_LIMIT_REACHED/)
  assert.match(migration, /insert into public\.event_user_assignments/)
  assert.match(migration, /write_audit_log\(p_tenant_id, 'event\.created'/)
})

test('event create RPC repair removes stale overload and reloads Supabase schema cache', () => {
  assert.match(repairMigration, /drop function if exists public\.rpc_create_event\(uuid, text, text, date, text, numeric, date\)/)
  assert.match(repairMigration, /p_custom_event_type text default null/)
  assert.match(repairMigration, /grant execute on function public\.rpc_create_event\(uuid, text, text, text, date, text, numeric, date\) to authenticated/)
  assert.match(repairMigration, /notify pgrst, 'reload schema'/)
})

test('event create v2 RPC has one stable signature and supports null optional fields', () => {
  assert.match(v2Migration, /create or replace function public\.rpc_create_event_v2/)
  assert.match(v2Migration, /p_custom_event_type text default null/)
  assert.match(v2Migration, /p_event_date date default null/)
  assert.match(v2Migration, /p_venue text default null/)
  assert.match(v2Migration, /p_target_amount numeric default null/)
  assert.match(v2Migration, /p_pledge_deadline date default null/)
  assert.match(v2Migration, /case when p_event_type = 'OTHER'/)
  assert.match(v2Migration, /insert into public\.event_user_assignments \(tenant_id, event_id, tenant_user_id, access_level, assigned_by\)/)
  assert.match(v2Migration, /'EVENT_CREATED'/)
  assert.match(v2Migration, /notify pgrst, 'reload schema'/)
})

test('event create v2 ambiguity fix avoids column and variable name collisions', () => {
  assert.match(v2AmbiguityFixMigration, /v_event_id uuid/)
  assert.match(v2AmbiguityFixMigration, /v_creator_tenant_user_id uuid/)
  assert.match(v2AmbiguityFixMigration, /returning id into v_event_id/)
  assert.match(v2AmbiguityFixMigration, /select tu\.id into v_creator_tenant_user_id/)
  assert.match(v2AmbiguityFixMigration, /where tu\.tenant_id = p_tenant_id/)
  assert.match(v2AmbiguityFixMigration, /values \(p_tenant_id, v_event_id, v_creator_tenant_user_id, 'MANAGE', auth\.uid\(\)\)/)
  assert.doesNotMatch(v2AmbiguityFixMigration, /declare[\s\S]*\n\s+event_id uuid;/)
})
