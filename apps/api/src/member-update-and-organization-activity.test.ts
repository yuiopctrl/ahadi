import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/064_update_member_rpc_and_organization_activity.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

const rpcUpdateMemberBody = migration.match(/create or replace function public\.rpc_update_member[\s\S]+?\nend;\n\$\$;/)?.[0] ?? ''
const rpcActivityBody = migration.match(/create or replace function public\.rpc_list_organization_activity[\s\S]+?\nend;\n\$\$;/)?.[0] ?? ''

test('rpc_update_member is SECURITY DEFINER, authorized, and locks the member row', () => {
  assert.match(rpcUpdateMemberBody, /security definer/)
  assert.match(rpcUpdateMemberBody, /set search_path = pg_catalog, public/)
  assert.match(rpcUpdateMemberBody, /if caller is null then\s*\n\s*raise exception 'SESSION_REQUIRED'/)
  assert.match(rpcUpdateMemberBody, /perform public\.ensure_tenant_write_access\(p_tenant_id\)/)
  assert.match(rpcUpdateMemberBody, /has_tenant_permission\(p_tenant_id, 'members\.update'\)/)
  assert.match(rpcUpdateMemberBody, /raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'/)
  assert.match(rpcUpdateMemberBody, /where id = p_member_id and tenant_id = p_tenant_id\s*\n\s*for update/)
  assert.match(rpcUpdateMemberBody, /raise exception 'MEMBER_NOT_FOUND' using errcode = '22023'/)
})

test('rpc_update_member preserves the null-vs-absent patch distinction for every supported field', () => {
  for (const [patchKey, column] of [
    ['fullName', 'full_name'],
    ['phoneE164', 'phone_e164'],
    ['alternativePhoneE164', 'alternative_phone_e164'],
    ['email', 'email'],
    ['location', 'location'],
    ['notes', 'notes'],
    ['preferredLanguage', 'preferred_language'],
    ['smsEnabled', 'sms_enabled'],
    ['status', 'status'],
  ] as const) {
    const pattern = new RegExp(`${column} = case when p_patch \\? '${patchKey}' then .*? else ${column} end`)
    assert.match(rpcUpdateMemberBody, pattern, `expected ${column} to fall back to its existing value when '${patchKey}' is absent from the patch`)
  }
  // tenant_id must never be assignable from the patch.
  assert.doesNotMatch(rpcUpdateMemberBody, /tenant_id = case when p_patch/)
})

test('rpc_update_member validates full name, preferred language and status before writing', () => {
  assert.match(rpcUpdateMemberBody, /btrim\(coalesce\(p_patch->>'fullName', ''\)\) = ''/)
  assert.match(rpcUpdateMemberBody, /p_patch->>'preferredLanguage' not in \('sw', 'en'\)/)
  assert.match(rpcUpdateMemberBody, /p_patch->>'status' not in \('ACTIVE', 'INACTIVE', 'ARCHIVED'\)/)
})

test('rpc_update_member relies on validate_member_integrity for phone/name normalization instead of duplicating it', () => {
  assert.doesNotMatch(migration, /create or replace function public\.validate_member_integrity/)
  assert.doesNotMatch(migration, /normalize_tz_phone/)
  assert.doesNotMatch(migration, /title_case_person_name/)
})

test('rpc_update_member sets archived_by on archive and leaves reactivation cleanup to the trigger', () => {
  assert.match(rpcUpdateMemberBody, /when p_patch \? 'status' and p_patch->>'status' = 'ARCHIVED' then caller/)
})

test('rpc_update_member maps a unique violation on the update to MEMBER_PHONE_ALREADY_EXISTS', () => {
  assert.match(rpcUpdateMemberBody, /exception\s*\n\s*when unique_violation then\s*\n\s*raise exception 'MEMBER_PHONE_ALREADY_EXISTS' using errcode = '23505'/)
})

test('rpc_update_member audits only meaningful field changes and picks the right action', () => {
  assert.match(rpcUpdateMemberBody, /diff_keys text\[\] := array\[/)
  assert.match(rpcUpdateMemberBody, /\(existing_json -> k\) is distinct from \(updated_json -> k\)/)
  assert.match(rpcUpdateMemberBody, /if old_values <> '\{\}'::jsonb then/)
  assert.match(rpcUpdateMemberBody, /audit_action := 'contact\.archived'/)
  assert.match(rpcUpdateMemberBody, /audit_action := 'contact\.reactivated'/)
  assert.match(rpcUpdateMemberBody, /perform public\.write_audit_log\(p_tenant_id, audit_action, 'member', p_member_id, null, old_values, new_values, null\)/)
  // created_by/updated_at/archived_at/archived_by are internal trigger noise, not user-facing changes.
  assert.doesNotMatch(rpcUpdateMemberBody, /diff_keys[\s\S]{0,400}'created_by'/)
  assert.doesNotMatch(rpcUpdateMemberBody, /diff_keys[\s\S]{0,400}'archived_at'/)
})

test('rpc_update_member grants execute to authenticated only', () => {
  assert.match(migration, /grant execute on function public\.rpc_update_member\(uuid, uuid, jsonb\) to authenticated/)
  assert.match(migration, /revoke all on function public\.rpc_update_member\(uuid, uuid, jsonb\) from public/)
})

test('rpc_list_organization_activity enforces tenant isolation and reuses the existing audit.view permission', () => {
  assert.match(rpcActivityBody, /security definer/)
  assert.match(rpcActivityBody, /if auth\.uid\(\) is null then\s*\n\s*raise exception 'SESSION_REQUIRED'/)
  assert.match(rpcActivityBody, /has_tenant_permission\(p_tenant_id, 'audit\.view'\)/)
  assert.match(rpcActivityBody, /raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501'/)
  assert.match(rpcActivityBody, /where al\.tenant_id = p_tenant_id/g)
  // No new permission table rows are inserted; audit.view already exists (033_repair_core_rbac_seed_data.sql).
  assert.doesNotMatch(migration, /insert into public\.permissions/)
})

test('rpc_list_organization_activity supports server-side pagination and filters', () => {
  assert.match(rpcActivityBody, /safe_limit integer := least\(greatest\(coalesce\(p_limit, 20\), 1\), 100\)/)
  assert.match(rpcActivityBody, /safe_offset integer := greatest\(coalesce\(p_offset, 0\), 0\)/)
  assert.match(rpcActivityBody, /limit safe_limit\s*\n\s*offset safe_offset/)
  for (const filter of [
    'p_action is null or al\\.action = p_action',
    'p_entity_type is null or al\\.entity_type = p_entity_type',
    'p_event_id is null or al\\.event_id = p_event_id',
    'p_actor_user_id is null or al\\.actor_user_id = p_actor_user_id',
    'p_date_from is null or al\\.created_at >= p_date_from',
    'p_date_to is null or al\\.created_at <= p_date_to',
  ]) {
    assert.match(rpcActivityBody, new RegExp(filter))
  }
  assert.match(rpcActivityBody, /'totalRows', total_rows/)
  assert.match(rpcActivityBody, /'hasMore', \(safe_offset \+ safe_limit\) < total_rows/)
})

test('rpc_list_organization_activity enriches rows with actor and event names to avoid N+1 lookups', () => {
  assert.match(rpcActivityBody, /left join public\.profiles pr on pr\.id = al\.actor_user_id/)
  assert.match(rpcActivityBody, /left join public\.events ev on ev\.id = al\.event_id/)
  assert.match(rpcActivityBody, /pr\.full_name as actor_name/)
  assert.match(rpcActivityBody, /ev\.name as event_name/)
})

test('PATCH /api/v1/members/:memberId calls rpc_update_member instead of a direct table update', () => {
  const route = app.match(/app\.patch\('\/api\/v1\/members\/:memberId'[\s\S]+?\n\}\)/)?.[0] ?? ''
  assert.match(route, /client\.rpc\('rpc_update_member', \{/)
  assert.match(route, /p_patch: input/)
  assert.doesNotMatch(route, /client\s*\n?\s*\.from\('members'\)\s*\n?\s*\.update\(/)
  assert.match(route, /logDatabaseError\(/)
  assert.match(route, /MEMBER_PHONE_ALREADY_EXISTS/)
  assert.match(route, /MEMBER_NOT_FOUND/)
})

test('updateMemberSchema exposes the exact patchable contact fields', () => {
  const schema = app.match(/const updateMemberSchema = z\.object\(\{[\s\S]+?\n\}\)/)?.[0] ?? ''
  for (const field of ['fullName', 'phoneE164', 'alternativePhoneE164', 'email', 'location', 'notes', 'preferredLanguage', 'smsEnabled', 'status']) {
    assert.match(schema, new RegExp(`${field}:`))
  }
})

test('GET /api/v1/activity is tenant-scoped and supports pagination and filters', () => {
  assert.match(app, /app\.get\('\/api\/v1\/activity', requireAuth, loadUserContext, requireTenantContext/)
  const route = app.match(/app\.get\('\/api\/v1\/activity'[\s\S]+?\n\}\)/)?.[0] ?? ''
  assert.match(route, /listActivityQuerySchema\.parse\(request\.query\)/)
  assert.match(route, /rpc\('rpc_list_organization_activity', \{/)
  assert.match(route, /p_tenant_id: tenantId/)
  assert.match(route, /p_limit: query\.limit/)
  assert.match(route, /p_offset: query\.offset/)
  assert.match(route, /pagination: jsonRecord\(result\['pagination'\]\)/)
})
