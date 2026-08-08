import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/027_reports_batch4.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('batch 4 creates report permission and report RPCs', () => {
  assert.match(migration, /'reports\.view'/)
  for (const rpc of [
    'rpc_get_event_collection_summary',
    'rpc_get_event_pledge_report',
    'rpc_get_event_payment_report',
    'rpc_get_event_outstanding_report',
    'rpc_get_event_payment_method_summary',
    'rpc_get_event_collector_report',
    'rpc_get_member_statement',
  ]) {
    assert.match(migration, new RegExp(`create or replace function public\\.${rpc}`))
    assert.match(migration, new RegExp(`grant execute on function public\\.${rpc}`))
  }
})

test('report RPCs enforce report permission, event access and financial definitions', () => {
  assert.match(migration, /require_event_report_access/)
  assert.match(migration, /has_tenant_permission\(p_tenant_id, p_permission\)/)
  assert.match(migration, /REPORT_ACCESS_DENIED/)
  assert.match(migration, /pay\.status = 'CONFIRMED'/)
  assert.match(migration, /confirmed_pledge_allocated_amount/)
  assert.match(migration, /greatest\(p\.pledged_amount - coalesce\(public\.confirmed_pledge_allocated_amount\(p\.id\), 0\), 0\)/)
  assert.match(migration, /payment_unallocated_amount/)
  assert.match(migration, /coalesce\(p\.due_date, e\.pledge_deadline\)/)
})

test('report API exposes whitelisted report route with pagination and sort args', () => {
  assert.match(app, /reportTypeSchema = z\.enum\(\['summary', 'pledges', 'payments', 'outstanding', 'payment-methods', 'collectors', 'member-statement'\]\)/)
  assert.match(app, /app\.post\('\/api\/v1\/events\/:eventId\/reports\/:reportType'/)
  assert.match(app, /p_page: input\.page/)
  assert.match(app, /p_page_size: input\.pageSize/)
  assert.match(app, /p_sort: input\.sort/)
  assert.match(app, /p_direction: input\.direction/)
})

test('report API falls back to stable financial RPCs when batch 4 RPCs are unavailable', () => {
  assert.match(app, /shouldFallbackToCompatibilityReport/)
  assert.match(app, /buildCompatibilityReport/)
  assert.match(app, /rpc_get_event_financial_summary/)
  assert.match(app, /rpc_list_event_members/)
  assert.match(app, /rpc_list_event_pledges/)
  assert.match(app, /rpc_list_event_payments/)
})
