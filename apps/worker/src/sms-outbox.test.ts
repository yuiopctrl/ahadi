import assert from 'node:assert/strict'
import test from 'node:test'
import { SmsProviderError } from '@ahadi/sms'
import { classifySmsFailure, parseWorkerEnv, processSmsOutboxBatch, type SmsOutboxJob, type SmsOutboxProvider, type SmsOutboxStore } from './index.js'

function job(overrides: Partial<SmsOutboxJob> = {}): SmsOutboxJob {
  return {
    id: 'outbox_1',
    tenant_id: 'tenant_1',
    event_id: 'event_1',
    member_id: 'member_1',
    payment_id: 'payment_1',
    receipt_id: 'receipt_1',
    template_code: 'PAYMENT_CONFIRMATION',
    phone_e164: '+255713676401',
    message_body: 'Payment received',
    status: 'PROCESSING',
    attempt_count: 1,
    max_attempts: 3,
    ...overrides,
  }
}

test('worker marks provider success as sent and stores message id', async () => {
  const sent: Array<{ id: string; providerMessageId: string | null }> = []
  const store: SmsOutboxStore = {
    claim: async () => [job()],
    markSent: async (id, providerMessageId) => { sent.push({ id, providerMessageId }) },
    markFailed: async () => assert.fail('markFailed should not be called'),
  }
  const provider: SmsOutboxProvider = {
    send: async () => ({ accepted: true, providerHttpStatus: 200, providerMessageId: 'msg_123', providerStatusCode: 'success', safeReason: null }),
  }

  assert.equal(await processSmsOutboxBatch(store, provider, 10), 1)
  assert.deepEqual(sent, [{ id: 'outbox_1', providerMessageId: 'msg_123' }])
})

test('worker schedules retryable provider failures', async () => {
  const failed: Array<{ code: string; retryable: boolean }> = []
  const store: SmsOutboxStore = {
    claim: async () => [job()],
    markSent: async () => assert.fail('markSent should not be called'),
    markFailed: async (_id, code, _message, retryable) => { failed.push({ code, retryable }) },
  }
  const provider: SmsOutboxProvider = {
    send: async () => {
      throw new SmsProviderError('SMS provider rejected message', 500)
    },
  }

  assert.equal(await processSmsOutboxBatch(store, provider, 10), 1)
  assert.deepEqual(failed, [{ code: 'PROVIDER_RETRYABLE_FAILURE', retryable: true }])
})

test('permanent failures are not retried', () => {
  assert.deepEqual(classifySmsFailure(new SmsProviderError('Invalid recipient', 400, 'Invalid phone number')), {
    code: 'PROVIDER_PERMANENT_FAILURE',
    message: 'Invalid recipient',
    retryable: false,
  })
  assert.equal(classifySmsFailure(new SmsProviderError('Unauthorized', 401)).retryable, false)
  assert.equal(classifySmsFailure(new SmsProviderError('NEXTSMS_REQUEST_BODY_CONTRACT_REQUIRED', 400, 'NEXTSMS_REQUEST_BODY_CONTRACT_REQUIRED')).retryable, false)
})

test('worker environment accepts publishable Supabase key and SMS provider configuration', () => {
  const env = parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    SMS_PROVIDER_URL: 'https://sms.example.test/send',
    SMS_USERNAME: 'sms-user',
    SMS_PASSWORD: 'sms-password',
    SMS_SENDER_ID: 'AHADI',
  })

  assert.equal(env.SUPABASE_PUBLISHABLE_KEY, 'publishable-key')
  assert.equal(env.WORKER_POLL_INTERVAL_MS, 30_000)
  assert.equal(env.WORKER_BATCH_SIZE, 10)
})

test('worker environment error points to SMS env file locations', () => {
  assert.throws(() => parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
  }), /SMS_PROVIDER=NEXTSMS.*apps\/api\/\.env or apps\/worker\/\.env/)
})

test('worker environment accepts NEXTSMS without legacy WebBulkSMS credentials', () => {
  const env = parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    SMS_PROVIDER: 'NEXTSMS',
    NEXTSMS_AUTHORIZATION: 'Basic test',
  })

  assert.equal(env.SMS_PROVIDER, 'NEXTSMS')
  assert.equal(env.NEXTSMS_BASE_URL, 'https://messaging-service.co.tz')
})
