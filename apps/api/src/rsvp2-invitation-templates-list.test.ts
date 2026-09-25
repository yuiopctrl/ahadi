import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/074_rsvp2_list_invitation_templates.sql', import.meta.url), 'utf8')

test('rpc_list_invitation_templates requires auth + invitation.view and returns only active PLATFORM or this-tenant TENANT templates', () => {
  const start = migration.indexOf('function public.rpc_list_invitation_templates(')
  const end = migration.indexOf('\n$$;', start)
  const body = migration.slice(start, end)
  assert.match(body, /raise exception 'SESSION_REQUIRED'/)
  assert.match(body, /has_tenant_permission\(p_tenant_id, 'invitation\.view'\)/)
  assert.match(body, /where t\.is_active/)
  assert.match(body, /t\.scope = 'PLATFORM' or \(t\.scope = 'TENANT' and t\.tenant_id = p_tenant_id\)/)
})

test('GET /api/v1/invitation-templates is tenant-scoped (not event-scoped) and wraps rows in { data }', () => {
  const start = app.indexOf("app.get('/api/v1/invitation-templates'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /rpc_list_invitation_templates/)
  assert.match(routeBody, /p_tenant_id: tenantId/)
  assert.match(routeBody, /data: jsonArray\(data\)/)
  assert.match(routeBody, /logDatabaseError\(request\.requestId, 'invitation-templates-list', error, \{ tenantId \}\)/)
})

test('migration 074 does not touch 072/073 tables, policies, or existing function signatures', () => {
  assert.doesNotMatch(migration, /create table/)
  assert.doesNotMatch(migration, /create policy/)
  assert.doesNotMatch(migration, /alter table/)
})
