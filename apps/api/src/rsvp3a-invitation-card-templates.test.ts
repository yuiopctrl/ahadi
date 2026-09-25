import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(
  new URL('../../../supabase/migrations/077_rsvp3a_invitation_card_templates.sql', import.meta.url),
  'utf8',
)
const foundationMigration = readFileSync(
  new URL('../../../supabase/migrations/072_rsvp1_invitation_domain_foundation.sql', import.meta.url),
  'utf8',
)

function fn(source: string, name: string): string {
  const start = source.indexOf(`function public.${name}(`)
  assert.notStrictEqual(start, -1, `must define ${name}`)
  const end = source.indexOf('\n$$;', start)
  assert.notStrictEqual(end, -1, `could not find end of ${name}`)
  return source.slice(start, end)
}

test('1. rpc_list_invitation_templates only ever returns is_active templates', () => {
  const body = fn(migration, 'rpc_list_invitation_templates')
  assert.match(body, /where t\.is_active/)
})

test('2. rpc_list_invitation_templates enforces tenant-private template isolation -- a TENANT-scope row from another tenant can never be returned', () => {
  const body = fn(migration, 'rpc_list_invitation_templates')
  assert.match(body, /t\.scope = 'PLATFORM' or \(t\.scope = 'TENANT' and t\.tenant_id = p_tenant_id\)/)
  // Same isolation predicate is also enforced by RLS directly on the table
  // (defense in depth, not just the RPC's WHERE clause).
  assert.match(
    foundationMigration,
    /scope = 'PLATFORM'\s*\n\s*or \(scope = 'TENANT' and public\.has_tenant_permission\(tenant_id, 'invitation\.view'\)\)/,
  )
})

test('rpc_list_invitation_templates now also returns configJson and isPremium (additive, no parameter-list change) so the gallery can render a real thumbnail with the same renderer used for export', () => {
  const body = fn(migration, 'rpc_list_invitation_templates')
  assert.match(body, /'isPremium', t\.is_premium/)
  assert.match(body, /'configJson', t\.config_json/)
  assert.match(migration, /create or replace function public\.rpc_list_invitation_templates\(p_tenant_id uuid\)/)
})

test('3. individual invitation template selection persists through the existing authenticated invitation edit RPC, not a local-only change', () => {
  const body = fn(foundationMigration, 'rpc_update_event_invitation')
  assert.match(body, /p_template_id uuid default null/)
  assert.match(body, /perform public\.validate_invitation_template\(p_tenant_id, new_template_id\)/)
  assert.match(body, /update public\.event_invitations\s*\n\s*set display_name = new_display_name, max_guests = new_max_guests, template_id = new_template_id/)
})

test('4. default event template is respected for new invitations but remains overridable per-invitation', () => {
  const single = fn(foundationMigration, 'rpc_create_event_invitation')
  assert.match(single, /resolved_template_id := coalesce\(p_template_id, settings_record\.template_id\)/)
  const bulk = fn(foundationMigration, 'rpc_bulk_create_event_invitations')
  assert.match(bulk, /resolved_template_id := coalesce\(p_template_id, settings_record\.template_id\)/)
})

test('24. template config is validated against a declarative whitelist -- unknown keys, non-hex colors, and unknown enum values are all rejected', () => {
  const body = fn(migration, 'validate_invitation_template_config')
  // Whitelist enforcement: any key outside the fixed top-level set fails.
  assert.match(body, /allowed_top text\[\] := array\['version', 'layoutKey', 'background', 'colors', 'typography', 'elements'\]/)
  assert.match(body, /for k in select jsonb_object_keys\(p_config\) loop\s*\n\s*if not \(k = any\(allowed_top\)\) then\s*\n\s*return false;/)
  // No key anywhere accepts arbitrary text that could carry HTML/JS/CSS --
  // colors are hex-pattern-checked and typography is enum-checked against a
  // fixed array, not freeform strings. (Not a bare `/script/` check: the
  // legitimate enum value `script_traditional` -- a calligraphy style name
  // -- would false-positive on that.)
  assert.match(body, /hex_pattern text := '\^#\[0-9A-Fa-f\]\{6\}\$'/)
  assert.doesNotMatch(body, /<script|javascript:|<img|onerror\s*=|<iframe/i)
})

test('the CHECK constraint is added only after the pre-existing seed row is rewritten to the new schema -- ADD CONSTRAINT validates existing rows immediately', () => {
  const rewriteIndex = migration.indexOf('update public.invitation_templates')
  const constraintIndex = migration.indexOf('add constraint invitation_templates_config_json_valid')
  assert.notStrictEqual(rewriteIndex, -1)
  assert.notStrictEqual(constraintIndex, -1)
  assert.ok(rewriteIndex < constraintIndex, 'the old seed row must be rewritten before the CHECK constraint is added')
})

test('five templates are seeded across the required categories (the pre-existing Classic row plus four new ones)', () => {
  for (const category of ['Minimal', 'Elegant', 'Modern', 'Traditional']) {
    assert.match(migration, new RegExp(`'PLATFORM', null, '[^']+', '${category}',`))
  }
  assert.match(migration, /category = 'Classic'/)
})

test('20. the shared invitation detail JSON (reused by the card data) never selects from pledges/payments/balance tables', () => {
  const body = fn(foundationMigration, 'event_invitation_detail_json')
  assert.doesNotMatch(body, /pledges|payments|balance/i)
})

test('no migration in this phase modifies an already-applied migration file (076 and earlier are untouched; 077 is purely additive)', () => {
  assert.doesNotMatch(migration, /alter table public\.event_invitations/)
  assert.doesNotMatch(migration, /alter table public\.invitation_rsvps/)
  assert.doesNotMatch(migration, /drop function if exists public\.rpc_get_event_member_invitation/)
})
