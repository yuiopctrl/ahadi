import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = [
  readFileSync(new URL('../../../supabase/migrations/038_complete_messages_sms_module.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('../../../supabase/migrations/039_pledge_request_sms.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('../../../supabase/migrations/040_strict_sms_preview_character_limit.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('../../../supabase/migrations/041_sms_provider_selection.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('../../../supabase/migrations/042_worker_nextsms_runtime.sql', import.meta.url), 'utf8'),
].join('\n')
const smsProviderSelectionMigration = readFileSync(new URL('../../../supabase/migrations/041_sms_provider_selection.sql', import.meta.url), 'utf8')
const workerNextSmsRuntimeMigration = readFileSync(new URL('../../../supabase/migrations/042_worker_nextsms_runtime.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../../web/src/lib/api.ts', import.meta.url), 'utf8')
const tenantPage = readFileSync(new URL('../../web/src/pages/tenant.tsx', import.meta.url), 'utf8')
const smsPackage = readFileSync(new URL('../../../packages/sms/src/index.ts', import.meta.url), 'utf8')

test('messages SMS module seeds the required business templates and validates variables', () => {
  for (const code of ['PLEDGE_REQUEST', 'PLEDGE_REGISTRATION', 'PAYMENT_CONFIRMATION', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED']) {
    assert.match(migration, new RegExp(code))
  }
  for (const variable of ['member_name', 'pledge_amount', 'payment_amount', 'payment_method', 'event_name', 'balance', 'receipt_number', 'due_date', 'event_date', 'pledge_deadline']) {
    assert.match(migration, new RegExp(variable))
  }
  assert.match(migration, /validate_sms_template_body/)
  assert.match(migration, /password', 'pin', 'otp/)
  assert.match(migration, /SMS_SENDER_ID_NOT_ALLOWED/)
})

test('pledge request SMS is separate from outstanding balance reminders', () => {
  assert.match(migration, /rpc_list_event_no_pledge_members/)
  assert.match(migration, /not exists|has_pledge = false/i)
  assert.match(migration, /rpc_enqueue_pledge_request_bulk/)
  assert.match(migration, /PLEDGE_ALREADY_REGISTERED/)
  assert.match(app, /\/api\/v1\/events\/:eventId\/messages\/no-pledge-members/)
  assert.match(app, /\/api\/v1\/events\/:eventId\/messages\/pledge-request\/bulk/)
  assert.match(apiClient, /eventNoPledgeMembers/)
  assert.match(tenantPage, /Members Without Pledge/)
})

test('automatic pledge and payment SMS enqueue rules are server-side and idempotent', () => {
  assert.match(migration, /rpc_enqueue_pledge_registration_sms/)
  assert.match(migration, /PLEDGE_REGISTRATION:' \|\| pledge_record\.id/)
  assert.match(migration, /template_code := case when outstanding <= 0 then 'PLEDGE_COMPLETED' else 'PAYMENT_CONFIRMATION' end/)
  assert.match(migration, /sms_outbox_payment_financial_auto_unique/)
  assert.match(app, /enqueuePledgeRegistrationSms/)
  assert.match(app, /rpc_enqueue_payment_confirmation_sms/)
  assert.doesNotMatch(app, /sendAttempt/)
})

test('message settings, templates and retry routes are exposed to the web client', () => {
  for (const route of ['/api/v1/messages/settings', '/api/v1/messages/templates', '/api/v1/messages/templates/:code', '/api/v1/messages/:outboxId/retry']) {
    assert.match(app, new RegExp(route.replaceAll('/', '\\/').replace(':code', ':code').replace(':outboxId', ':outboxId')))
  }
  for (const method of ['smsSettings', 'saveSmsSettings', 'smsTemplates', 'saveSmsTemplate', 'resetSmsTemplate', 'retrySms']) {
    assert.match(apiClient, new RegExp(method))
  }
  assert.match(tenantPage, /PLEDGE_REQUEST/)
  assert.match(tenantPage, /SmsTemplateManager/)
  assert.match(tenantPage, /RetrySmsButton/)
})

test('NextSMS provider boundary posts the verified provider request body', () => {
  assert.match(smsPackage, /defaultNextSmsBaseUrl = 'https:\/\/messaging-service\.co\.tz'/)
  assert.match(smsPackage, /defaultNextSmsSingleSmsPath = '\/api\/sms\/v1\/text\/single'/)
  assert.match(smsPackage, /nextSmsAllowedSenderIds = \['SHEREHE', 'MICHANGO', 'KIKAO'\]/)
  assert.match(smsPackage, /from: senderId/)
  assert.match(smsPackage, /to: providerPhoneNumber/)
  assert.match(smsPackage, /text: normalizedMessage/)
  assert.match(smsPackage, /'Content-Type': 'application\/json'/)
})

test('strict SMS preview and character-limit validation are server-side', () => {
  assert.match(migration, /sms_max_characters\(\)[\s\S]*select 159/)
  assert.match(migration, /character_count integer/)
  assert.match(migration, /max_characters_at_send integer/)
  assert.match(migration, /rpc_preview_event_member_sms/)
  assert.match(migration, /rpc_preview_event_member_sms_bulk/)
  assert.match(migration, /SMS_CHARACTER_LIMIT_EXCEEDED/)
  assert.match(app, /\/api\/v1\/events\/:eventId\/messages\/preview/)
  assert.match(app, /previewIsValid/)
  assert.match(apiClient, /smsBulkPreview/)
  assert.match(tenantPage, /SmsCharacterCounter/)
})

test('tenant SMS provider selection is persisted and worker routing does not fallback to WebBulkSMS', () => {
  assert.match(migration, /create table if not exists public\.sms_providers/)
  assert.match(migration, /create table if not exists public\.sms_provider_sender_ids/)
  assert.match(migration, /\('NEXTSMS', 'NextSMS', 'ACTIVE', true\)/)
  assert.match(migration, /\('WEBBULKSMS', 'WebBulkSMS', 'ACTIVE', false\)/)
  assert.match(migration, /sms_provider_code text/)
  assert.match(migration, /tenant_sms_provider_settings/)
  assert.match(migration, /validate_sms_provider_sender/)
  assert.match(migration, /TENANT_SMS_PROVIDER_CHANGED/)
  assert.match(migration, /provider_settings\.provider_code/)
  assert.doesNotMatch(smsProviderSelectionMigration, /coalesce\(o\.provider, 'WEBBULKSMS'\)/)
  assert.match(app, /\/api\/v1\/settings\/messages\/providers/)
  assert.match(app, /\/api\/v1\/platform\/sms\/providers/)
  assert.match(app, /p_provider_code: input\.provider/)
  assert.match(apiClient, /smsProviderOptions/)
  assert.match(apiClient, /platformSmsProviders/)
  assert.match(tenantPage, /SMS Provider/)
  assert.match(smsPackage, /class SmsProviderRegistry/)
  assert.match(smsPackage, /SMS_PROVIDER_NOT_SUPPORTED/)
})

test('worker runtime can claim queued SMS and diagnose safe outbox state with publishable key', () => {
  assert.match(workerNextSmsRuntimeMigration, /grant execute on function public\.rpc_claim_sms_outbox\(integer\) to anon, authenticated/)
  assert.match(workerNextSmsRuntimeMigration, /grant execute on function public\.rpc_mark_sms_sent\(uuid, text\) to anon, authenticated/)
  assert.match(workerNextSmsRuntimeMigration, /grant execute on function public\.rpc_mark_sms_failed\(uuid, text, text, boolean\) to anon, authenticated/)
  assert.match(workerNextSmsRuntimeMigration, /rpc_sms_worker_diagnostics/)
  assert.match(workerNextSmsRuntimeMigration, /claimableCount/)
  assert.match(workerNextSmsRuntimeMigration, /blockedCounts/)
  assert.match(workerNextSmsRuntimeMigration, /staleProcessing/)
  assert.match(workerNextSmsRuntimeMigration, /provider/)
  assert.match(workerNextSmsRuntimeMigration, /sender_id/)
})
