import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/038_complete_messages_sms_module.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../../web/src/lib/api.ts', import.meta.url), 'utf8')
const tenantPage = readFileSync(new URL('../../web/src/pages/tenant.tsx', import.meta.url), 'utf8')
const smsPackage = readFileSync(new URL('../../../packages/sms/src/index.ts', import.meta.url), 'utf8')

test('messages SMS module seeds the four required business templates and validates variables', () => {
  for (const code of ['PLEDGE_REGISTRATION', 'PAYMENT_CONFIRMATION', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED']) {
    assert.match(migration, new RegExp(code))
  }
  for (const variable of ['member_name', 'pledge_amount', 'payment_amount', 'payment_method', 'event_name', 'balance', 'receipt_number', 'due_date']) {
    assert.match(migration, new RegExp(variable))
  }
  assert.match(migration, /validate_sms_template_body/)
  assert.match(migration, /password', 'pin', 'otp/)
  assert.match(migration, /SMS_SENDER_ID_NOT_ALLOWED/)
})

test('automatic pledge and payment SMS enqueue rules are server-side and idempotent', () => {
  assert.match(migration, /rpc_enqueue_pledge_registration_sms/)
  assert.match(migration, /PLEDGE_REGISTRATION:' \|\| pledge_record\.id/)
  assert.match(migration, /template_code := case when outstanding <= 0 then 'PLEDGE_COMPLETED' else 'PAYMENT_CONFIRMATION' end/)
  assert.match(migration, /sms_outbox_payment_financial_auto_unique/)
  assert.match(app, /enqueueAndAttemptPledgeRegistrationSms/)
  assert.match(app, /rpc_enqueue_payment_confirmation_sms/)
})

test('message settings, templates and retry routes are exposed to the web client', () => {
  for (const route of ['/api/v1/messages/settings', '/api/v1/messages/templates', '/api/v1/messages/templates/:code', '/api/v1/messages/:outboxId/retry']) {
    assert.match(app, new RegExp(route.replaceAll('/', '\\/').replace(':code', ':code').replace(':outboxId', ':outboxId')))
  }
  for (const method of ['smsSettings', 'saveSmsSettings', 'smsTemplates', 'saveSmsTemplate', 'resetSmsTemplate', 'retrySms']) {
    assert.match(apiClient, new RegExp(method))
  }
  assert.match(tenantPage, /PLEDGE_REGISTRATION/)
  assert.match(tenantPage, /SmsTemplateManager/)
  assert.match(tenantPage, /RetrySmsButton/)
})

test('NextSMS provider boundary is configured without inventing request body fields', () => {
  assert.match(smsPackage, /defaultNextSmsBaseUrl = 'https:\/\/messaging-service\.co\.tz'/)
  assert.match(smsPackage, /defaultNextSmsSingleSmsPath = '\/api\/sms\/v1\/text\/single'/)
  assert.match(smsPackage, /nextSmsAllowedSenderIds = \['SHEREHE', 'MICHANGO', 'KIKAO'\]/)
  assert.match(smsPackage, /NEXTSMS_REQUEST_BODY_CONTRACT_REQUIRED/)
})
