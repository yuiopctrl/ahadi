import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migrations = ['011_members_and_event_members.sql', '012_pledges_and_history.sql', '013_payments_allocations_and_receipts.sql', '014_member_pledge_payment_rpcs.sql', '015_financial_views.sql', '016_financial_permissions_and_rls.sql', '018_repair_event_financial_access.sql', '019_stabilize_financial_summary_shape.sql', '020_grant_financial_read_views.sql', '021_financial_list_rpcs.sql', '022_payment_confirmation_sms_outbox.sql', '029_tenant_sms_outbox_processing.sql', '044_member_detail_profile_columns.sql']
  .map((file) => readFileSync(new URL(`../../../supabase/migrations/${file}`, import.meta.url), 'utf8'))
  .join('\n')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('financial migrations create core workflow tables and append-only records', () => {
  for (const table of ['members', 'event_members', 'pledges', 'pledge_history', 'payments', 'payment_allocations', 'receipts', 'payment_reversals']) {
    assert.match(migrations, new RegExp(`create table public\\.${table}`, 'i'))
    assert.match(migrations, new RegExp(`alter table public\\.${table} enable row level security`, 'i'))
  }
  assert.match(migrations, /numeric\(18,2\)/i)
  assert.match(migrations, /prevent_financial_delete/i)
  assert.match(migrations, /FINANCIAL_HISTORY_APPEND_ONLY/)
})

test('financial migrations use tenant counters and do not SELECT MAX for member or payment numbers', () => {
  assert.match(migrations, /tenant_financial_counters/)
  assert.match(migrations, /next_member_number = next_member_number \+ 1/)
  assert.match(migrations, /next_payment_number = next_payment_number \+ 1/)
  assert.match(migrations, /next_receipt_number = next_receipt_number \+ 1/)
  assert.doesNotMatch(migrations, /max\(member_code\)|max\(payment_number\)|max\(receipt_number\)/i)
})

test('financial RPCs cover member, pledge, payment, reversal and summary workflows', () => {
  for (const rpc of ['rpc_create_member_and_attach_to_event', 'rpc_attach_existing_member_to_event', 'rpc_create_or_update_pledge', 'rpc_record_installment_payment', 'rpc_reverse_payment', 'rpc_get_event_financial_summary', 'rpc_list_event_members', 'rpc_list_event_pledges', 'rpc_list_event_payments']) {
    assert.match(migrations, new RegExp(`create or replace function public\\.${rpc}`, 'i'))
    assert.match(app, new RegExp(rpc))
  }
  assert.match(migrations, /auth\.uid\(\)/)
  assert.match(migrations, /least\(p_amount, outstanding\)/)
  assert.match(migrations, /PAYMENT_ALREADY_REVERSED/)
})

test('financial access repair backfills permissions and allows event viewers to load read summaries', () => {
  assert.match(migrations, /018_repair_event_financial_access/)
  assert.match(migrations, /where r\.code = 'TENANT_OWNER' and p\.code not like 'platform\.%'/)
  assert.match(migrations, /public\.has_tenant_permission\(p_tenant_id, 'events\.view'\)/)
  assert.match(migrations, /p_min_assignment_level = 'VIEW'/)
  assert.match(migrations, /p_min_assignment_level = 'COLLECT' and eua\.access_level in \('COLLECT', 'MANAGE'\)/)
  assert.match(migrations, /p_min_assignment_level = 'MANAGE' and eua\.access_level = 'MANAGE'/)
})

test('financial summary returns zero-safe totals with stable allocated field names', () => {
  assert.match(migrations, /019_stabilize_financial_summary_shape/)
  assert.match(migrations, /'totalAllocated', allocated_total/)
  assert.match(migrations, /'totalAllocatedToPledges', allocated_total/)
  assert.match(migrations, /coalesce\(\(select sum\(amount\) from public\.payments/)
  assert.match(migrations, /coalesce\(\(select sum\(pledged_amount\) from public\.pledges/)
})

test('financial read models and API routes are present', () => {
  for (const view of ['v_event_members_list', 'v_event_pledges_list', 'v_event_payments_list', 'v_event_outstanding_members', 'v_receipt_detail']) {
    assert.match(migrations, new RegExp(`view public\\.${view}`, 'i'))
  }
  for (const column of ['m.notes', 'm.preferred_language', 'm.status as member_status']) {
    assert.match(migrations, new RegExp(column.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  }
  for (const route of ['/api/v1/events/:eventId/members', '/api/v1/events/:eventId/pledges', '/api/v1/events/:eventId/payments', '/api/v1/receipts/:receiptId']) {
    assert.match(app, new RegExp(route.replace(/[/:]/g, (match) => `\\${match}`)))
  }
})

test('financial read views and balance helpers are granted to authenticated clients', () => {
  for (const view of ['v_event_members_list', 'v_event_pledges_list', 'v_event_payments_list', 'v_event_outstanding_members', 'v_receipt_detail']) {
    assert.match(migrations, new RegExp(`public\\.${view}`))
  }
  for (const fn of ['payment_allocated_amount', 'payment_unallocated_amount', 'confirmed_pledge_allocated_amount', 'calculated_pledge_status']) {
    assert.match(migrations, new RegExp(`grant execute on function public\\.${fn}\\(uuid\\) to authenticated`))
  }
  for (const fn of ['rpc_list_event_members', 'rpc_list_event_pledges', 'rpc_list_event_payments']) {
    assert.match(migrations, new RegExp(`grant execute on function public\\.${fn}\\(uuid, uuid\\) to authenticated`))
  }
})

test('payment confirmation SMS uses outbox tables and idempotent enqueue RPC', () => {
  for (const table of ['sms_templates', 'sms_outbox']) {
    assert.match(migrations, new RegExp(`create table if not exists public\\.${table}`, 'i'))
    assert.match(migrations, new RegExp(`alter table public\\.${table} enable row level security`, 'i'))
  }
  assert.match(migrations, /'PAYMENT_CONFIRMATION'/)
  assert.match(migrations, /PAYMENT_CONFIRMATION:' \|\| payment_record\.id::text/)
  assert.match(migrations, /sms_outbox_idempotency_active_unique/)
  assert.match(migrations, /sms_outbox_payment_confirmation_unique/)
  assert.match(migrations, /member_record\.phone_e164 is null[\s\S]+NO_PHONE/)
  assert.match(migrations, /member_record\.sms_enabled = false[\s\S]+SMS_DISABLED/)
  assert.match(migrations, /rpc_claim_sms_outbox[\s\S]+for update of o skip locked/i)
  assert.match(app, /rpc_enqueue_payment_confirmation_sms/)
  assert.doesNotMatch(app, /record_installment_payment[\s\S]+sendAuthenticationSms/)
})

test('tenant queued SMS is queued by the API and processed by the worker', () => {
  assert.match(migrations, /rpc_claim_tenant_sms_outbox/)
  assert.match(migrations, /public\.has_tenant_permission\(p_tenant_id, 'messages\.send'\)/)
  assert.match(migrations, /o\.tenant_id = p_tenant_id/)
  assert.match(migrations, /p_outbox_ids is null or o\.id = any\(p_outbox_ids\)/)
  assert.match(migrations, /p_batch_id is null or o\.batch_id = p_batch_id/)
  assert.match(migrations, /for update of o skip locked/i)
  assert.match(migrations, /grant execute on function public\.rpc_claim_tenant_sms_outbox\(uuid, integer, uuid\[\], uuid\) to authenticated/)
  assert.match(app, /\/api\/v1\/messages\/process-queued/)
  assert.match(app, /\/api\/v1\/messages\/worker-diagnostics/)
  assert.match(app, /rpc_sms_worker_diagnostics/)
  assert.match(app, /processing: 'WORKER'/)
  assert.doesNotMatch(app, /attemptTenantQueuedSms/)
  assert.doesNotMatch(app, /sendTenantQueuedSms/)
  assert.doesNotMatch(app, /sendAttempt/)
})
