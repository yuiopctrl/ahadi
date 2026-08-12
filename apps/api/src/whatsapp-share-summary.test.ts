import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/052_dynamic_whatsapp_muhtasari.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const tenantPage = readFileSync(new URL('../../../apps/web/src/pages/tenant.tsx', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../../../apps/web/src/lib/api.ts', import.meta.url), 'utf8')
const presentationRpc = migration.slice(
  migration.indexOf('create or replace function public.rpc_update_event_whatsapp_share_presentation_settings'),
  migration.indexOf('drop function if exists public.rpc_generate_event_whatsapp_share_preview'),
)

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

test('payment instructions are saved per event and rendered above the member list with line breaks preserved', () => {
  assert.match(migration, /add column if not exists whatsapp_payment_instructions text/)
  assert.match(migration, /show_whatsapp_payment_instructions boolean not null default true/)
  assert.match(migration, /where tenant_id = p_tenant_id and event_id = p_event_id/)
  assert.match(migration, /paymentInstructions/)
  assert.match(migration, /public\.whatsapp_plain_text\(p_payment_instructions\)/)
  assert.match(migration, /full_text := array_to_string\(array_remove\(array\[header_block, payment_block, array_to_string\(lines, E'\\n'\), tail_block\]/)
  assert.doesNotMatch(migration, /\*MALIPO\*/)
})

test('payment instructions can be hidden without falling back to mobile or bank text', () => {
  assert.match(migration, /effective_show_payment_instructions := coalesce/)
  assert.match(migration, /if effective_show_payment_instructions then[\s\S]+payment_block := effective_payment_instructions/)
  assert.match(tenantPage, /Show Payment Instructions/)
  assert.match(tenantPage, /setShowPaymentInstructions\(event\.target\.checked\)/)
})

test('Alama defaults, editable labels, hide toggle and reset are event presentation only', () => {
  assert.match(migration, /default_whatsapp_alama_labels/)
  assert.match(migration, /'completed', 'Amemaliza'/)
  assert.match(migration, /'partial', 'Amepunguza'/)
  assert.match(migration, /'noPledge', 'Hajatoa Ahadi'/)
  assert.match(migration, /show_whatsapp_alama boolean not null default true/)
  assert.match(migration, /whatsapp_render_alama/)
  assert.match(migration, /Alama:/)
  assert.match(tenantPage, /Reset Alama to Default/)
  assert.match(tenantPage, /updateAlamaLabel\('completed'/)
  assert.match(tenantPage, /Show Alama/)
})

test('custom Alama labels do not alter status symbol logic', () => {
  assert.match(migration, /when 'PRIVACY' then full_name \|\| case current_status when 'PAID' then ' ✅✅' when 'PARTIAL' then ' ☑️' when 'NO_PLEDGE' then ' 🙏🏿'/)
  assert.match(migration, /when 'PAYMENT_PROGRESS' then full_name \|\| case when pledge_id is null then ' - 🙏🏿'/)
  assert.match(migration, /else full_name \|\| case when pledge_id is null then ' - 🙏🏿'/)
  assert.doesNotMatch(migration, /current_status[\s\S]+completed[\s\S]+partial[\s\S]+noPledge/)
})

test('all event users can save presentation settings while tenant isolation remains enforced', () => {
  assert.match(migration, /rpc_update_event_whatsapp_share_presentation_settings/)
  assert.match(presentationRpc, /if not found or not public\.can_access_event\(p_event_id\) then/)
  assert.doesNotMatch(presentationRpc, /shares\.whatsapp\.financial/)
  assert.match(app, /whatsapp-presentation-settings/)
  assert.match(apiClient, /saveWhatsappSharePresentationSettings/)
  assert.match(tenantPage, /canFinancial[\s\S]+api\.saveWhatsappShareSettings[\s\S]+api\.saveWhatsappSharePresentationSettings/)
})

test('presentation settings write updated_by updated_at and audit entries', () => {
  assert.match(migration, /updated_by = excluded\.updated_by/)
  assert.match(migration, /event_share_settings_set_updated_at/)
  assert.match(migration, /write_audit_log\([\s\S]+share\.whatsapp\.payment_instructions\.updated/)
  assert.match(migration, /Updated Share List payment instructions/)
  assert.match(migration, /write_audit_log\([\s\S]+share\.whatsapp\.alama\.updated/)
  assert.match(migration, /Updated Share List Alama/)
})

test('preview and final server output use the same RPC payload and avoid duplicate Alama or Muhtasari sections', () => {
  assert.match(app, /p_show_payment_instructions: input\.showPaymentInstructions/)
  assert.match(app, /p_payment_instructions: input\.paymentInstructions \?\? null/)
  assert.match(app, /p_show_alama: input\.showAlama/)
  assert.match(app, /p_alama_labels: input\.alamaLabels \?\? null/)
  assert.match(tenantPage, /\.\.\.presentationPayload/)
  assert.equal((migration.match(/whatsapp_render_financial_summary\(summary, effective_summary_rows\)/g) ?? []).length, 1)
  assert.equal((migration.match(/whatsapp_render_alama\(effective_alama_labels, effective_show_alama\)/g) ?? []).length, 1)
})
