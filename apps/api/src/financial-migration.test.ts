import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migrations = ['011_members_and_event_members.sql', '012_pledges_and_history.sql', '013_payments_allocations_and_receipts.sql', '014_member_pledge_payment_rpcs.sql', '015_financial_views.sql', '016_financial_permissions_and_rls.sql']
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
  for (const rpc of ['rpc_create_member_and_attach_to_event', 'rpc_attach_existing_member_to_event', 'rpc_create_or_update_pledge', 'rpc_record_installment_payment', 'rpc_reverse_payment', 'rpc_get_event_financial_summary']) {
    assert.match(migrations, new RegExp(`create or replace function public\\.${rpc}`, 'i'))
    assert.match(app, new RegExp(rpc))
  }
  assert.match(migrations, /auth\.uid\(\)/)
  assert.match(migrations, /least\(p_amount, outstanding\)/)
  assert.match(migrations, /PAYMENT_ALREADY_REVERSED/)
})

test('financial read models and API routes are present', () => {
  for (const view of ['v_event_members_list', 'v_event_pledges_list', 'v_event_payments_list', 'v_event_outstanding_members', 'v_receipt_detail']) {
    assert.match(migrations, new RegExp(`view public\\.${view}`, 'i'))
  }
  for (const route of ['/api/v1/events/:eventId/members', '/api/v1/events/:eventId/pledges', '/api/v1/events/:eventId/payments', '/api/v1/receipts/:receiptId']) {
    assert.match(app, new RegExp(route.replace(/[/:]/g, (match) => `\\${match}`)))
  }
})
