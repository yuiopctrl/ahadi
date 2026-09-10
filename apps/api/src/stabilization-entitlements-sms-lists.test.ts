import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const types = readFileSync(new URL('../../../packages/types/src/index.ts', import.meta.url), 'utf8')
const errors = readFileSync(new URL('./errors.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/070_entitlements_sms_batching_list_ux.sql', import.meta.url), 'utf8')
const writeAccessMigration = readFileSync(
  new URL('../../../supabase/migrations/014_member_pledge_payment_rpcs.sql', import.meta.url),
  'utf8',
)

function fn(name: string): string {
  const start = migration.indexOf(`function public.${name}(`)
  assert.notStrictEqual(start, -1, `migration must define ${name}`)
  const end = migration.indexOf('\n$$;', start)
  assert.notStrictEqual(end, -1, `could not find end of ${name}`)
  return migration.slice(start, end)
}

// --- Issue 1: contact/member entitlement ---

test('tenant_member_usage resolves max_members live from the CURRENT active subscription, never plan_snapshot', () => {
  const body = fn('tenant_member_usage')
  assert.match(body, /join public\.subscription_plans sp on sp\.id = ts\.plan_id/)
  assert.match(body, /where ts\.tenant_id = p_tenant_id\s*\n\s*and ts\.status in \('TRIAL', 'ACTIVE', 'PAST_DUE'\)/)
  assert.match(body, /order by ts\.created_at desc\s*\n\s*limit 1/)
  // Must read the live plan column, not the frozen snapshot copy.
  assert.match(body, /select sp\.max_members/)
  assert.doesNotMatch(body, /plan_snapshot/)
  // Counts Contacts (public.members), never event_members.
  assert.match(body, /from public\.members\s*\n\s*where tenant_id = p_tenant_id and status = 'ACTIVE'/)
})

test('tenant_member_usage treating PAST_DUE as write-eligible matches the existing ensure_tenant_write_access policy', () => {
  // ensure_tenant_write_access (called by both create-contact RPCs before
  // the entitlement check even runs) is the product's existing, singular
  // definition of "can this tenant still write" -- it blocks SUSPENDED,
  // CANCELLED and ARCHIVED outright, and treats EXPIRED as read-only, but
  // deliberately does not block PAST_DUE. tenant_member_usage including
  // PAST_DUE alongside TRIAL/ACTIVE is therefore consistent with existing
  // policy, not a new grace-period decision introduced by this migration.
  const start = writeAccessMigration.indexOf('function public.ensure_tenant_write_access(')
  const end = writeAccessMigration.indexOf('\n$$;', start)
  const body = writeAccessMigration.slice(start, end)
  assert.match(body, /if tenant_status in \('SUSPENDED', 'CANCELLED', 'ARCHIVED'\) then/)
  assert.doesNotMatch(body, /'PAST_DUE'/)
})

test('rpc_create_contact and rpc_create_member_and_attach_to_event both enforce the resolver and raise CONTACT_LIMIT_REACHED', () => {
  for (const name of ['rpc_create_contact', 'rpc_create_member_and_attach_to_event']) {
    const body = fn(name)
    assert.match(body, /v_usage := public\.tenant_member_usage\(p_tenant_id\);/, `${name} must call the shared resolver`)
    assert.match(body, /raise exception 'CONTACT_LIMIT_REACHED'/, `${name} must raise CONTACT_LIMIT_REACHED`)
    // Only enforce when a limit is actually known -- never invent a cap.
    assert.match(body, /\(v_usage ->> 'limit'\) is not null and/)
  }
})

test('rpc_create_contact and rpc_create_member_and_attach_to_event serialize per-tenant on the same advisory lock key before recomputing usage', () => {
  for (const name of ['rpc_create_contact', 'rpc_create_member_and_attach_to_event']) {
    const body = fn(name)
    assert.match(
      body,
      /perform pg_advisory_xact_lock\(hashtextextended\(p_tenant_id::text \|\| ':contact-create', 51\)\);/,
      `${name} must take the per-tenant contact-create advisory lock`,
    )
    // The lock must be acquired BEFORE usage is recomputed, otherwise two
    // concurrent callers could both read a pre-lock snapshot and both pass.
    const lockIndex = body.indexOf("pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':contact-create'")
    const usageIndex = body.indexOf('v_usage := public.tenant_member_usage(p_tenant_id);')
    assert.ok(lockIndex !== -1 && usageIndex !== -1 && lockIndex < usageIndex, `${name} must lock before recomputing usage`)
    // The insert must happen after both the lock and the limit check, i.e.
    // still inside the locked section (the xact lock is held until the
    // function's implicit transaction ends, so ordering here is what
    // actually matters for correctness).
    const limitCheckIndex = body.indexOf("raise exception 'CONTACT_LIMIT_REACHED'")
    const insertIndex = body.indexOf('insert into public.members')
    assert.ok(limitCheckIndex < insertIndex, `${name} must check the limit before inserting`)
  }
  // Both functions must use the IDENTICAL lock key so a concurrent
  // rpc_create_contact and rpc_create_member_and_attach_to_event for the
  // same tenant also serialize against each other, not just against
  // themselves -- they mutate the same tenant-wide public.members count.
  const a = fn('rpc_create_contact')
  const b = fn('rpc_create_member_and_attach_to_event')
  const lockPattern = /hashtextextended\(p_tenant_id::text \|\| ':contact-create', 51\)/
  assert.match(a, lockPattern)
  assert.match(b, lockPattern)
})

test('CONTACT_LIMIT_REACHED is wired consistently through types, errors.ts and knownDatabaseCodes', () => {
  assert.match(types, /\| 'CONTACT_LIMIT_REACHED'/)
  assert.match(errors, /CONTACT_LIMIT_REACHED: \d+,/)
  const knownStart = app.indexOf('= [', app.indexOf('const knownDatabaseCodes')) + 3
  const knownBlock = app.slice(knownStart, app.indexOf('\n]', knownStart))
  assert.match(knownBlock, /'CONTACT_LIMIT_REACHED'/)
})

test('rpc_list_contacts paginates server-side, returns totalRows and the usage resolver, and preserves compact-phone search', () => {
  const body = fn('rpc_list_contacts')
  assert.match(body, /p_search text default null,\s*\n\s*p_limit integer default 20,\s*\n\s*p_offset integer default 0/)
  assert.match(body, /'totalRows', total_rows/)
  assert.match(body, /'usage', public\.tenant_member_usage\(p_tenant_id\)/)
  assert.match(body, /public\.compact_phone_search\(m\.phone_e164\) like '%' \|\| phone_search \|\| '%'/)
})

test('GET /api/v1/contacts forwards search/limit/offset to the RPC and returns data+pagination+usage instead of in-memory slicing', () => {
  const start = app.indexOf("app.get('/api/v1/contacts'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /p_search: query\.search \|\| null/)
  assert.match(routeBody, /p_limit: query\.limit/)
  assert.match(routeBody, /p_offset: query\.offset/)
  assert.match(routeBody, /pagination: jsonRecord\(result\['pagination'\]\)/)
  assert.match(routeBody, /usage: jsonRecord\(result\['usage'\]\)/)
  assert.doesNotMatch(routeBody, /rows\.slice\(/)
})

// --- Issue 3: event members sort/filter/pagination ---

test('rpc_list_event_members supports search, pledge/phone filters, sort+direction and pagination, applied server-side', () => {
  const body = fn('rpc_list_event_members')
  for (const filter of ['ALL', 'HAS_PLEDGE', 'NO_PLEDGE', 'FULLY_PAID', 'PARTIALLY_PAID', 'UNPAID']) {
    assert.match(body, new RegExp(`'${filter}'`), `pledge filter ${filter} must be supported`)
  }
  for (const filter of ['HAS_PHONE', 'NO_PHONE']) {
    assert.match(body, new RegExp(`'${filter}'`), `phone filter ${filter} must be supported`)
  }
  for (const sortKey of ['NAME', 'CREATED', 'PLEDGE_AMOUNT', 'OUTSTANDING']) {
    assert.match(body, new RegExp(`'${sortKey}'`), `sort key ${sortKey} must be supported`)
  }
  assert.match(body, /'totalRows', total_rows/)
  // Filtering must be evaluated in SQL against the full event dataset, not
  // just whatever page is returned.
  assert.match(body, /select count\(\*\)\s*\n\s*into total_rows\s*\n\s*from public\.v_event_members_list/)
})

test('v_event_members_list additively exposes event_member_created_at for the Newest/Oldest sort', () => {
  assert.match(migration, /em\.created_at as event_member_created_at/)
})

test('GET /api/v1/events/:eventId/members accepts sort/filter/pagination query params and forwards them to the RPC', () => {
  const start = app.indexOf("app.get('/api/v1/events/:eventId/members'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /p_pledge_status: query\.pledgeStatus/)
  assert.match(routeBody, /p_phone_status: query\.phoneStatus/)
  assert.match(routeBody, /p_sort: query\.sort/)
  assert.match(routeBody, /p_direction: query\.direction/)
  assert.match(routeBody, /pagination: jsonRecord\(result\['pagination'\]\)/)
})

// --- Issue 2: SMS balance vs. provider/batch-size cap ---

test('rpc_enqueue_custom_sms_bulk now checks real SMS balance via sms_allowance_status, distinct from the batch-size cap', () => {
  const body = fn('rpc_enqueue_custom_sms_bulk')
  assert.match(body, /v_allowance := public\.sms_allowance_status\(p_tenant_id, eligible_count\);/)
  assert.match(body, /'reason', 'SMS_BALANCE_INSUFFICIENT'/)
  // The balance check must never be confused with (or block on) the
  // request-size sanity ceiling.
  assert.match(body, /raise exception 'CUSTOM_SMS_BATCH_TOO_LARGE'/)
  assert.match(body, /p_max_batch_size integer default 2000/)
  // Balance shortfall is returned as data (matching the existing
  // LOW_BALANCE precedent in sibling bulk-SMS RPCs), not raised as an
  // exception that would discard the available/requested counts.
  const allowanceCheckIndex = body.indexOf('v_allowance :=')
  const returnAfterCheck = body.slice(allowanceCheckIndex, allowanceCheckIndex + 400)
  assert.match(returnAfterCheck, /return jsonb_build_object\(/)
})

test('rpc_enqueue_custom_sms_bulk serializes the balance-check-then-enqueue sequence per tenant on its own advisory lock key', () => {
  const body = fn('rpc_enqueue_custom_sms_bulk')
  assert.match(
    body,
    /perform pg_advisory_xact_lock\(hashtextextended\(p_tenant_id::text \|\| ':custom-sms-send', 52\)\);/,
    'rpc_enqueue_custom_sms_bulk must take the per-tenant custom-sms-send advisory lock',
  )
  // The lock must be acquired before the eligibility count / balance check
  // / outbox inserts -- i.e. before any of the data the balance decision
  // depends on is read -- otherwise two concurrent sends for the same
  // tenant could both pass sms_allowance_status against the same
  // pre-insert balance and jointly oversubscribe it.
  const lockIndex = body.indexOf("pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':custom-sms-send'")
  const eligibleCountIndex = body.indexOf('into no_phone, sms_disabled, eligible_count')
  const allowanceIndex = body.indexOf('v_allowance := public.sms_allowance_status(')
  const insertIndex = body.indexOf('insert into public.sms_outbox')
  assert.ok(lockIndex !== -1, 'lock must be present')
  assert.ok(lockIndex < eligibleCountIndex, 'lock must precede the eligibility count')
  assert.ok(lockIndex < allowanceIndex, 'lock must precede the balance check')
  assert.ok(lockIndex < insertIndex, 'lock must precede the outbox insert loop')
  // Uses a distinct lock key from the contact-creation lock -- these are
  // unrelated resources and must not serialize against each other.
  assert.doesNotMatch(body, /:contact-create/)
})

test('rpc_preview_custom_sms_bulk surfaces smsAllowance so the UI can show available balance before sending', () => {
  const body = fn('rpc_preview_custom_sms_bulk')
  assert.match(body, /'smsAllowance', case when eligible_count > 0 then public\.sms_allowance_status\(p_tenant_id, eligible_count\) else null end/)
})

test('custom SMS bulk send route uses its own batch-size constant, not the balance-reminder env var', () => {
  const start = app.indexOf("app.post('/api/v1/events/:eventId/messages/custom/bulk'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /p_max_batch_size: CUSTOM_SMS_MAX_BATCH_SIZE/)
  assert.doesNotMatch(routeBody, /p_max_batch_size: env\.BALANCE_REMINDER_MAX_BATCH_SIZE/)
  assert.match(app, /const CUSTOM_SMS_MAX_BATCH_SIZE = \d+/)
})

// --- Issue 5: activity entity display names ---

test('rpc_list_organization_activity resolves entity_display_name server-side for the entity types it records (no client N+1)', () => {
  const body = fn('rpc_list_organization_activity')
  assert.match(body, /entity_display_name/)
  for (const entityType of ['member', 'event_member', 'event', 'pledge', 'payment', 'tenant_user']) {
    assert.match(body, new RegExp(`when '${entityType}' then`), `entity_display_name must resolve '${entityType}'`)
  }
  // actor_name and event_name resolution (pre-existing) must remain intact.
  assert.match(body, /pr\.full_name as actor_name/)
  assert.match(body, /ev\.name as event_name/)
  // request_id is additive so the client can show it as secondary
  // "Technical Details", never as the primary description.
  assert.match(body, /al\.request_id/)
})
