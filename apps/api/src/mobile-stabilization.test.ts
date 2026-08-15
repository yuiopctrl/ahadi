import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const mobileApi = readFileSync(new URL('../../../apps/mobile/lib/core/networking/api_client.dart', import.meta.url), 'utf8')
const searchMigration = readFileSync(new URL('../../../supabase/migrations/058_mobile_stabilization_search_and_payment_reports.sql', import.meta.url), 'utf8')
const phoneReportMigration = readFileSync(new URL('../../../supabase/migrations/059_mobile_phone_search_reports.sql', import.meta.url), 'utf8')
const shareMigration = readFileSync(new URL('../../../supabase/migrations/052_dynamic_whatsapp_muhtasari.sql', import.meta.url), 'utf8')

test('mobile edit routes use canonical backend methods', () => {
  assert.match(app, /app\.patch\('\/api\/v1\/events\/:eventId'/)
  assert.match(app, /app\.patch\('\/api\/v1\/members\/:memberId'/)
  assert.match(mobileApi, /'\/events\/\$eventId'/)
  assert.match(mobileApi, /'\/members\/\$memberId'/)
})

test('mobile search contract normalizes phone searches consistently', () => {
  assert.match(app, /function compactPhoneSearch/)
  assert.match(app, /matchesNameOrPhoneSearch\(row, query\.search, \['full_name'\], \['phone_e164', 'alternative_phone_e164'\]\)/)
  assert.match(app, /matchesNameOrPhoneSearch\(row, query\.search, \['member_name', 'full_name'\], \['phone_e164', 'alternative_phone_e164'\]\)/)
  assert.match(searchMigration, /compact_phone_search/)
  assert.match(searchMigration, /m\.phone_e164 as "phone"/)
  assert.match(searchMigration, /public\.compact_phone_search\(m\.phone_e164\) like/)
  assert.match(searchMigration, /p\.amount,[\s\S]+pr\.full_name as received_by_name,\n  m\.phone_e164/)
  assert.doesNotMatch(searchMigration, /m\.phone_e164,\n  p\.amount/)
  assert.match(phoneReportMigration, /rpc_get_event_pledge_report/)
  assert.match(phoneReportMigration, /rpc_get_event_outstanding_report/)
  assert.match(phoneReportMigration, /phone_search text := public\.compact_phone_search\(p_search\)/)
  assert.match(phoneReportMigration, /public\.compact_phone_search\(m\.phone_e164\) like/)
})

test('share list supports all mobile formats and keeps canonical section assembly', () => {
  for (const format of ['DETAILED', 'PRIVACY', 'PAYMENT_PROGRESS', 'OUTSTANDING_FOLLOW_UP']) {
    assert.match(app, new RegExp(format))
    assert.match(shareMigration, new RegExp(format))
  }
  assert.match(shareMigration, /array_to_string\(array_remove\(array\[header_block, payment_block, array_to_string\(lines, E'\\n'\), tail_block\], ''\), E'\\n\\n'\)/)
  assert.match(shareMigration, /footer_block :=/)
  assert.match(shareMigration, /alama_block :=/)
  assert.doesNotMatch(shareMigration, /NAMBA YA KUPOKEA MCHANGO/)
})
