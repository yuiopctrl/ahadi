import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration073 = readFileSync(
  new URL('../../../supabase/migrations/073_security_hardening_service_role_guards.sql', import.meta.url),
  'utf8',
)
const migration072 = readFileSync(
  new URL('../../../supabase/migrations/072_rsvp1_invitation_domain_foundation.sql', import.meta.url),
  'utf8',
)
const migration009 = readFileSync(
  new URL('../../../supabase/migrations/009_fix_pin_credentials_and_rpc.sql', import.meta.url),
  'utf8',
)
const migration018 = readFileSync(
  new URL('../../../supabase/migrations/018_repair_event_financial_access.sql', import.meta.url),
  'utf8',
)

test('migration 073 adds require_service_role() as the first statement inside rpc_verify_phone_pin, before any phone/PIN logic', () => {
  const start = migration073.indexOf('create or replace function public.rpc_verify_phone_pin(')
  assert.notStrictEqual(start, -1, 'migration 073 must redefine rpc_verify_phone_pin')
  const bodyStart = migration073.indexOf('begin', start)
  const guardIndex = migration073.indexOf('perform public.require_service_role();', bodyStart)
  const phoneLookupIndex = migration073.indexOf('normalized_phone := public.normalize_tz_phone', bodyStart)
  assert.ok(guardIndex !== -1, 'rpc_verify_phone_pin must call require_service_role()')
  assert.ok(phoneLookupIndex !== -1)
  assert.ok(guardIndex < phoneLookupIndex, 'the guard must run before any phone normalization/lookup')
})

test('migration 073 preserves the exact revoke/grant pair rpc_verify_phone_pin already had (defense in depth, not a replacement for it)', () => {
  assert.match(migration073, /revoke all on function public\.rpc_verify_phone_pin\(text, text\) from public;/)
  assert.match(migration073, /grant execute on function public\.rpc_verify_phone_pin\(text, text\) to service_role;/)
})

test('migration 073 does not touch the ordinary authenticated self-service PIN RPCs (rpc_set_my_pin / rpc_verify_my_pin / rpc_has_my_pin / rpc_change_my_pin) -- those must keep working for a normal logged-in user without a service-role guard', () => {
  for (const name of ['rpc_set_my_pin', 'rpc_verify_my_pin', 'rpc_has_my_pin', 'rpc_change_my_pin']) {
    assert.doesNotMatch(migration073, new RegExp(`function public\\.${name}\\(`), `073 must not redefine ${name}`)
  }
  // And confirm (against their real, currently-applied definition) that they
  // already correctly scope to auth.uid() -- this is WHY they don't need the
  // guard, not an assumption.
  const setPinBody = migration009.slice(migration009.indexOf('create or replace function public.rpc_set_my_pin('), migration009.indexOf('$function$;', migration009.indexOf('create or replace function public.rpc_set_my_pin(')))
  assert.match(setPinBody, /auth\.uid\(\)/)
  assert.match(setPinBody, /raise exception using[\s\S]*?SESSION_REQUIRED/)
})

test('migration 073 does not redefine has_event_financial_access or any RSVP-1 RLS policy -- the review concluded no change was needed there', () => {
  assert.doesNotMatch(migration073, /function public\.has_event_financial_access/)
  assert.doesNotMatch(migration073, /create policy/)
  assert.doesNotMatch(migration073, /drop policy/)
})

test('has_event_financial_access is a generic event-scoped permission checker -- p_permission is a caller-supplied parameter, not hardcoded to a financial code, so it does not require pledges/payments permissions for other domains', () => {
  const body = migration018.slice(migration018.indexOf('create or replace function public.has_event_financial_access('), migration018.indexOf('comment on function public.has_event_financial_access'))
  assert.match(body, /p_permission text/)
  assert.doesNotMatch(body, /'pledges\./)
  assert.doesNotMatch(body, /'payments\./)
  assert.match(body, /perm\.code = p_permission/)
})

test('the two RSVP-1 public RPCs still call require_service_role() unchanged after this hardening pass', () => {
  for (const name of ['rpc_get_public_invitation_detail', 'rpc_submit_public_invitation_rsvp']) {
    const start = migration072.indexOf(`function public.${name}(`)
    const end = migration072.indexOf('\n$$;', start)
    const body = migration072.slice(start, end)
    assert.match(body, /perform public\.require_service_role\(\);/)
  }
})

test('require_service_role() is not SECURITY DEFINER and reads a GUC, not current_user -- so it cannot be bypassed by a nested SECURITY DEFINER role change', () => {
  const start = migration072.indexOf('create or replace function public.require_service_role()')
  const end = migration072.indexOf('\n$$;', start)
  const body = migration072.slice(start, end)
  assert.doesNotMatch(body, /security definer/)
  assert.match(body, /current_setting\('request\.jwt\.claim\.role', true\)/)
  assert.doesNotMatch(body, /current_user/)
})
