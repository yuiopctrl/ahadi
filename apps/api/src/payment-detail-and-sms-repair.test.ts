import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

// Stabilization mini-batch 2 (payment detail 500 + SMS template_code ambiguity).
//
// This repo's existing test suite (financial-migration.test.ts,
// messages-sms-module.test.ts, etc.) is static/structural: it asserts
// against the migration SQL and app.ts route source rather than running a
// live Postgres/Supabase instance, because none is wired into `pnpm test`
// for this package. These tests follow the same convention.

const repair = readFileSync(new URL('../../../supabase/migrations/068_payment_detail_and_sms_ambiguity_repair.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

// --- PAYMENT DETAIL ---

test('1. payment detail route calls the authoritative RPC instead of querying the view directly', () => {
  const routeMatch = app.match(/app\.get\('\/api\/v1\/events\/:eventId\/payments\/:paymentId'[\s\S]*?\n\}\)/)
  assert.ok(routeMatch, 'payment detail route not found')
  const route = routeMatch![0]
  assert.match(route, /rpc_get_payment_detail/)
  assert.doesNotMatch(route, /v_event_payments_list/)
  assert.doesNotMatch(route, /\.single\(\)/)
})

test('2. payment detail RPC returns member id, name and phone', () => {
  assert.match(repair, /m\.id as member_id/)
  assert.match(repair, /m\.full_name as member_name/)
  assert.match(repair, /m\.phone_e164/)
})

test('3. payment detail RPC returns receipt id, number and a derived status', () => {
  assert.match(repair, /r\.id as receipt_id/)
  assert.match(repair, /r\.receipt_number/)
  assert.match(repair, /as receipt_status/)
})

test('4. payment detail RPC returns pledge amount, paid and outstanding figures', () => {
  assert.match(repair, /pl\.id as pledge_id/)
  assert.match(repair, /pl\.pledged_amount/)
  assert.match(repair, /pledge_total_paid/)
  assert.match(repair, /pledge_outstanding/)
  assert.match(repair, /calculated_pledge_status\(pl\.id\)/)
})

test('5. payment detail RPC scopes every lookup by tenant, event and payment id together', () => {
  const fn = repair.match(/create or replace function public\.rpc_get_payment_detail[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  assert.match(fn![0], /where p\.tenant_id = p_tenant_id\s*\n\s*and p\.event_id = p_event_id\s*\n\s*and p\.id = p_payment_id/)
})

test('6. wrong eventId for a valid paymentId is rejected before rows are returned', () => {
  const fn = repair.match(/create or replace function public\.rpc_get_payment_detail[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  // p_event_id is required to match public.events.tenant_id AND is the join
  // key used in the payments WHERE clause, so a payment from a different
  // event can never satisfy the query regardless of paymentId validity.
  assert.match(fn![0], /from public\.events ev where ev\.id = p_event_id and ev\.tenant_id = p_tenant_id/)
  assert.match(fn![0], /has_event_financial_access\(p_tenant_id, p_event_id, 'payments\.view', 'VIEW'\)/)
})

test('7. missing payment raises PAYMENT_NOT_FOUND instead of a generic failure', () => {
  const fn = repair.match(/create or replace function public\.rpc_get_payment_detail[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  assert.match(fn![0], /if v_result is null then\s*\n\s*raise exception 'PAYMENT_NOT_FOUND'/)
  assert.match(app, /knownDatabaseCodes[\s\S]*?'PAYMENT_NOT_FOUND'/)
})

test('8. reversed payment detail includes reversal status, reason, timestamp and reverser', () => {
  assert.match(repair, /left join public\.payment_reversals rev on rev\.payment_id = p\.id/)
  assert.match(repair, /rev\.reversed_at/)
  assert.match(repair, /rev\.reversed_by/)
  assert.match(repair, /rev\.reason as reversal_reason/)
  assert.match(repair, /as reversal_status/)
})

test('9. payment detail is a single round trip with no N+1 client requests', () => {
  const routeMatch = app.match(/app\.get\('\/api\/v1\/events\/:eventId\/payments\/:paymentId'[\s\S]*?\n\}\)/)
  assert.ok(routeMatch)
  const route = routeMatch![0]
  const rpcCalls = route.match(/client\.rpc\(/g) ?? []
  const fromCalls = route.match(/client\.from\(/g) ?? []
  assert.equal(rpcCalls.length, 1)
  assert.equal(fromCalls.length, 0)
})

test('tenant isolation: payment detail authorization is re-derived from p_tenant_id/p_event_id, never trusts the row alone', () => {
  const fn = repair.match(/create or replace function public\.rpc_get_payment_detail[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  assert.match(fn![0], /auth\.uid\(\) is null/)
  assert.match(fn![0], /SESSION_REQUIRED/)
  // Every join target that could leak cross-tenant data is scoped through
  // p.tenant_id / p_tenant_id, not merely matched by the row's own id.
  assert.match(fn![0], /p\.tenant_id = p_tenant_id/)
})

test('payment detail errors are logged with provider diagnostics before mapping to a public error', () => {
  const routeMatch = app.match(/app\.get\('\/api\/v1\/events\/:eventId\/payments\/:paymentId'[\s\S]*?\n\}\)/)
  assert.ok(routeMatch)
  const route = routeMatch![0]
  assert.match(route, /logDatabaseError\(request\.requestId, 'payment-detail', error, \{ tenantId, eventId, paymentId \}\)/)
  assert.match(route, /throwFinancialDatabaseError\(error, 'PAYMENT_DETAIL_FAILED'\)/)
})

// --- SMS template_code AMBIGUITY ---

test('10. partial payment (pledge still outstanding) selects PAYMENT_CONFIRMATION', () => {
  assert.match(repair, /v_template_code := case\s*\n\s*when v_pledge\.id is not null and v_outstanding <= 0 then 'PLEDGE_COMPLETED'\s*\n\s*else 'PAYMENT_CONFIRMATION'/)
})

test('11. final payment that clears the pledge selects PLEDGE_COMPLETED', () => {
  assert.match(repair, /when v_pledge\.id is not null and v_outstanding <= 0 then 'PLEDGE_COMPLETED'/)
})

test('12. a payment can only ever pick one of the two templates, never both', () => {
  // A single case/when-else assignment feeding a single INSERT means it is
  // structurally impossible to enqueue both codes for one payment. The
  // partial unique index below is the DB-level backstop for the same rule.
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  const insertCount = (fn![0].match(/insert into public\.sms_outbox/g) ?? []).length
  assert.equal(insertCount, 1)
  const migration038 = readFileSync(new URL('../../../supabase/migrations/038_complete_messages_sms_module.sql', import.meta.url), 'utf8')
  assert.match(migration038, /sms_outbox_payment_financial_auto_unique[\s\S]*?template_code in \('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED'\)/)
})

test('13. template_code column references are qualified, fixing the 42702 ambiguity', () => {
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  const body = fn![0]
  // The PL/pgSQL variable is renamed so it can never collide with the
  // sms_outbox.template_code column.
  assert.match(body, /v_template_code text;/)
  // Both places that filter sms_outbox by template_code (the idempotency
  // lookup and the unique_violation fallback) now qualify the column with
  // the table alias instead of leaving it bare.
  const qualifiedOccurrences = body.match(/so\.template_code in \('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED'\)/g) ?? []
  assert.equal(qualifiedOccurrences.length, 2)
  // The exact ambiguous form that triggered production's 42702 must be gone.
  assert.doesNotMatch(body, /(?<!so\.)\btemplate_code in \('PAYMENT_CONFIRMATION', 'PLEDGE_COMPLETED'\)/)
})

test('audit: every local scalar variable in the SMS function is v_-prefixed and every table column is alias-qualified', () => {
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  const body = fn![0]
  for (const name of ['payment', 'member', 'event', 'receipt', 'pledge', 'template_code', 'template_body', 'message', 'outbox_id', 'idempotency_key', 'outstanding', 'provider_settings']) {
    assert.match(body, new RegExp(`v_${name}\\b`), `expected v_${name} to be declared`)
  }
  assert.match(body, /public\.payments where public\.payments\.id = p_payment_id and public\.payments\.tenant_id = p_tenant_id/)
  assert.match(body, /public\.events where public\.events\.id = v_payment\.event_id and public\.events\.tenant_id = p_tenant_id/)
  assert.match(body, /public\.receipts where public\.receipts\.payment_id = v_payment\.id and public\.receipts\.tenant_id = p_tenant_id/)
})

test('14. disabled tenant SMS returns a safe non-failure result instead of raising', () => {
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  assert.match(fn![0], /if not public\.tenant_sms_enabled\(p_tenant_id\) then\s*\n\s*return jsonb_build_object\('smsQueued', false, 'reason', 'TENANT_SMS_DISABLED'\)/)
})

test('15. missing member phone returns a safe non-failure result instead of raising', () => {
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  assert.match(fn![0], /if v_member\.phone_e164 is null then\s*\n\s*return jsonb_build_object\('smsQueued', false, 'reason', 'NO_PHONE'\)/)
})

test('16. member sms_enabled = false is respected', () => {
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  assert.match(fn![0], /if coalesce\(v_member\.sms_enabled, true\) = false then\s*\n\s*return jsonb_build_object\('smsQueued', false, 'reason', 'SMS_DISABLED'\)/)
})

test('17. repeated enqueue is idempotent via lookup and a unique_violation fallback', () => {
  const fn = repair.match(/create or replace function public\.rpc_enqueue_payment_confirmation_sms[\s\S]*?\nend;\n\$\$;/)
  assert.ok(fn)
  const body = fn![0]
  assert.match(body, /reason', 'ALREADY_QUEUED'/)
  assert.match(body, /exception when unique_violation then/)
  const alreadyQueuedCount = (body.match(/'ALREADY_QUEUED'/g) ?? []).length
  assert.equal(alreadyQueuedCount, 2, 'expected the idempotency lookup and the unique_violation handler both to short-circuit to ALREADY_QUEUED')
})

test('18. the API route enqueues SMS after the finance transaction commits and never rolls it back on SMS failure', () => {
  const routeMatch = app.match(/app\.post\('\/api\/v1\/events\/:eventId\/payments'[\s\S]*?\n\}\)/)
  assert.ok(routeMatch)
  const route = routeMatch![0]
  const paymentRpcIndex = route.indexOf("rpc_record_installment_payment")
  const enqueueRpcIndex = route.indexOf("rpc_enqueue_payment_confirmation_sms")
  assert.ok(paymentRpcIndex >= 0 && enqueueRpcIndex > paymentRpcIndex, 'payment must be recorded before SMS is ever attempted')
  assert.match(route, /if \(enqueue\.error\) \{/)
  assert.match(route, /notification = \{ smsQueued: false, reason: smsEnqueueFailureReason\(enqueue\.error\) \}/)
  // The 201 response (and therefore the already-committed payment RPC
  // result) is returned unconditionally after the enqueue attempt -- SMS
  // failure never throws/rolls back the request.
  assert.match(route, /response\.status\(201\)\.json\(\{ data: \{ \.\.\.payment, notification \} \}\)/)
  assert.match(route, /logDatabaseError\(request\.requestId, 'payment-confirmation-sms', enqueue\.error, \{/)
})

test('historical imports: no trigger auto-enqueues SMS on payment insert', () => {
  const paymentsTableMigrations = [
    readFileSync(new URL('../../../supabase/migrations/013_payments_allocations_and_receipts.sql', import.meta.url), 'utf8'),
  ].join('\n')
  assert.doesNotMatch(paymentsTableMigrations, /create trigger[\s\S]*?on public\.payments[\s\S]*?enqueue/i)
  assert.doesNotMatch(repair, /create trigger/i)
  // SMS enqueue stays an explicit, application-triggered RPC call.
  assert.match(app, /rpc_enqueue_payment_confirmation_sms/)
})

test('payment detail RPC is granted to authenticated clients and reloads PostgREST schema cache', () => {
  assert.match(repair, /grant execute on function public\.rpc_get_payment_detail\(uuid, uuid, uuid\) to authenticated;/)
  assert.match(repair, /grant execute on function public\.rpc_enqueue_payment_confirmation_sms\(uuid, uuid\) to authenticated;/)
  assert.match(repair, /notify pgrst, 'reload schema';/)
})
