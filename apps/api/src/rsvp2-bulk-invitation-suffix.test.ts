import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/075_rsvp2_bulk_invitation_naming_suffix.sql', import.meta.url), 'utf8')

test('migration 075 drops the old 5-arg rpc_bulk_create_event_invitations signature before creating the new 6-arg one, avoiding the overload-ambiguity trap from migration 071', () => {
  assert.match(migration, /drop function if exists public\.rpc_bulk_create_event_invitations\(uuid, uuid, uuid\[\], integer, uuid\);/)
  const createIndex = migration.indexOf('create or replace function public.rpc_bulk_create_event_invitations(')
  const dropIndex = migration.indexOf('drop function if exists public.rpc_bulk_create_event_invitations')
  assert.ok(dropIndex !== -1 && createIndex !== -1 && dropIndex < createIndex, 'drop must precede create')
})

test('the suffix is applied only to event_invitations.display_name, never to members.full_name', () => {
  const start = migration.indexOf('create or replace function public.rpc_bulk_create_event_invitations(')
  const end = migration.indexOf('\n$$;', start)
  const body = migration.slice(start, end)
  assert.match(body, /clean_suffix text := nullif\(btrim\(coalesce\(p_display_name_suffix, ''\)\), ''\);/)
  assert.match(body, /case when clean_suffix is not null then m\.full_name \|\| ' ' \|\| clean_suffix else m\.full_name end,/)
  assert.doesNotMatch(body, /update public\.members/)
  assert.doesNotMatch(body, /set full_name/)
})

test('GET /api/v1/events/:eventId/invitations/bulk route forwards displayNameSuffix to p_display_name_suffix', () => {
  const start = app.indexOf("app.post('/api/v1/events/:eventId/invitations/bulk'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /p_display_name_suffix: input\.displayNameSuffix \|\| null/)
})
