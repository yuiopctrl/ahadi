import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/052_dynamic_whatsapp_muhtasari.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const tenantPage = readFileSync(new URL('../../../apps/web/src/pages/tenant.tsx', import.meta.url), 'utf8')

test('dynamic Muhtasari default is total pledged plus cash received', () => {
  assert.match(migration, /default_whatsapp_summary_rows/)
  assert.match(migration, /'Jumla ya Ahadi'[\s\S]+'TOTAL_PLEDGED'/)
  assert.match(migration, /'Jumla CASH'[\s\S]+'CASH_RECEIVED'/)
})

test('cash Muhtasari total uses confirmed cash payments and excludes reversed payments', () => {
  assert.match(migration, /cash_received/)
  assert.match(migration, /pay\.status = 'CONFIRMED' and pay\.payment_method = 'CASH'/)
  assert.doesNotMatch(migration, /pay\.status in \('CONFIRMED', 'REVERSED'\).*CASH/s)
})

test('supported Muhtasari value sources match Ahadi payment methods', () => {
  for (const source of ['TOTAL_PLEDGED', 'TOTAL_RECEIVED', 'TOTAL_OUTSTANDING', 'CASH_RECEIVED', 'MOBILE_MONEY_RECEIVED', 'M_PESA_RECEIVED', 'AIRTEL_MONEY_RECEIVED', 'MIX_BY_YAS_RECEIVED', 'HALOPESA_RECEIVED', 'BANK_RECEIVED', 'CHEQUE_RECEIVED', 'OTHER_RECEIVED']) {
    assert.match(migration, new RegExp(source))
    assert.match(app, new RegExp(source))
  }
})

test('custom labels, visibility and row order are stored as event scoped JSON settings', () => {
  assert.match(migration, /add column if not exists whatsapp_summary_rows jsonb/)
  assert.match(migration, /normalize_whatsapp_summary_rows/)
  assert.match(migration, /'label'/)
  assert.match(migration, /'valueSource'/)
  assert.match(migration, /'visible'/)
  assert.match(migration, /'order'/)
  assert.match(migration, /where tenant_id = p_tenant_id and event_id = p_event_id/)
  assert.match(migration, /whatsapp_summary_rows = excluded\.whatsapp_summary_rows/)
})

test('server preview renders configured financial Muhtasari and leaves privacy financial amounts hidden', () => {
  assert.match(migration, /whatsapp_render_financial_summary\(summary, effective_summary_rows\)/)
  assert.match(migration, /if normalized_format = 'PRIVACY' then[\s\S]+Waliokamilisha/)
  assert.doesNotMatch(migration, /if normalized_format = 'PRIVACY' then[\s\S]+format_tzs_sms_amount/s)
})

test('API and UI pass summary rows for save and live preview without browser financial calculations', () => {
  assert.match(app, /summaryRows: z\.array\(whatsappSummaryRowSchema\)/)
  assert.match(app, /p_summary_rows: input\.summaryRows \?\? null/)
  assert.match(tenantPage, /summaryRows: effectiveSummaryRows/)
  assert.match(tenantPage, /function resetSummaryRows/)
  assert.match(tenantPage, /Reset to Default/)
  assert.match(tenantPage, /Value Source/)
  assert.doesNotMatch(tenantPage, /cashReceived\s*=|totalPledged\s*=/)
})
