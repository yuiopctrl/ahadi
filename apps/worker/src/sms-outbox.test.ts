import assert from 'node:assert/strict'
import test from 'node:test'
import { SmsProviderError } from '@ahadi/sms'
import { ConfiguredSmsOutboxProvider, getNextSmsEndpoint, getNextSmsRuntimeDiagnostics, classifySmsFailure, parseWorkerEnv, processSmsOutboxBatch, type SmsOutboxJob, type SmsOutboxProvider, type SmsOutboxStore } from './index.js'

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
    provider: 'NEXTSMS',
    sender_id: 'MICHANGO',
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
  const logs: unknown[] = []

  assert.equal(await processSmsOutboxBatch(store, provider, 10, { info: (...args) => logs.push(args), warn: () => undefined, error: () => undefined }), 1)
  assert.deepEqual(sent, [{ id: 'outbox_1', providerMessageId: 'msg_123' }])
  assert.ok(logs.some((entry) => Array.isArray(entry) && entry[0] === 'SMS_SEND_START'))
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
  const warnings: unknown[] = []

  assert.equal(await processSmsOutboxBatch(store, provider, 10, { info: () => undefined, warn: (...args) => warnings.push(args), error: () => undefined }), 1)
  assert.deepEqual(failed, [{ code: 'PROVIDER_RETRYABLE_FAILURE', retryable: true }])
  assert.ok(warnings.some((entry) => Array.isArray(entry) && entry[0] === 'SMS_SEND_FAILED'))
})

test('permanent failures are not retried', () => {
  assert.deepEqual(classifySmsFailure(new SmsProviderError('Invalid recipient', 400, 'Invalid phone number')), {
    code: 'PROVIDER_PERMANENT_FAILURE',
    message: 'Invalid recipient',
    retryable: false,
  })
  assert.equal(classifySmsFailure(new SmsProviderError('Unauthorized', 401)).retryable, false)
  assert.equal(classifySmsFailure(new SmsProviderError('SMS_PROVIDER_NOT_SUPPORTED', 400, 'SMS_PROVIDER_NOT_SUPPORTED')).retryable, false)
})

test('worker environment accepts publishable Supabase key and SMS provider configuration', () => {
  const env = parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    SMS_PROVIDER_URL: 'https://sms.example.test/send',
    SMS_USERNAME: 'sms-user',
    SMS_PASSWORD: 'sms-password',
    SMS_SENDER_ID: 'AHADI',
    NEXTSMS_AUTHORIZATION: 'Basic test',
  })

  assert.equal(env.SUPABASE_PUBLISHABLE_KEY, 'publishable-key')
  assert.equal(env.WORKER_POLL_INTERVAL_MS, 30_000)
  assert.equal(env.WORKER_BATCH_SIZE, 10)
})

test('worker environment no longer requires one global SMS provider credential set', () => {
  const env = parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    NEXTSMS_AUTHORIZATION: 'Basic test',
  })
  assert.equal(env.SMS_PROVIDER, 'NEXTSMS')
  assert.equal(env.NEXTSMS_DEFAULT_SENDER_ID, 'MICHANGO')
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

test('worker rejects missing or double-prefixed NEXTSMS authorization', () => {
  assert.throws(() => parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
  }), /NEXTSMS_AUTHORIZATION/)

  assert.throws(() => parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    NEXTSMS_AUTHORIZATION: 'Basic Basic abc',
  }), /NEXTSMS_AUTHORIZATION/)
})

test('worker exposes redacted NextSMS runtime diagnostics', () => {
  const env = parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    NEXTSMS_AUTHORIZATION: 'Basic test',
    NEXTSMS_BASE_URL: 'https://messaging-service.co.tz',
    NEXTSMS_SINGLE_SMS_PATH: '/api/sms/v1/text/single',
    NEXTSMS_DEFAULT_SENDER_ID: 'MICHANGO',
    NEXTSMS_ALLOWED_SENDER_IDS: 'SHEREHE,MICHANGO,KIKAO',
  })
  assert.equal(getNextSmsEndpoint(env), 'https://messaging-service.co.tz/api/sms/v1/text/single')
  assert.deepEqual(getNextSmsRuntimeDiagnostics(env), {
    baseUrlConfigured: true,
    authorizationConfigured: true,
    defaultSenderId: 'MICHANGO',
  })
})

test('configured worker provider routes queued NEXTSMS messages with default sender', async () => {
  const env = parseWorkerEnv({
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
    NEXTSMS_AUTHORIZATION: 'Basic test',
    NEXTSMS_BASE_URL: 'https://messaging-service.co.tz',
    NEXTSMS_SINGLE_SMS_PATH: '/api/sms/v1/text/single',
    NEXTSMS_DEFAULT_SENDER_ID: 'MICHANGO',
    NEXTSMS_ALLOWED_SENDER_IDS: 'SHEREHE,MICHANGO,KIKAO',
  })
  let calledUrl = ''
  let authorization = ''
  let contentType = ''
  let from = ''
  const provider = new ConfiguredSmsOutboxProvider({
    ...env,
    fetchImpl: async (url, init) => {
      calledUrl = String(url)
      const headers = new Headers(init?.headers)
      authorization = headers.get('authorization') ?? ''
      contentType = headers.get('content-type') ?? ''
      from = String((JSON.parse(String(init?.body ?? '{}')) as Record<string, string>)['from'])
      return new Response(JSON.stringify({ status: 'success', message_id: 'next_queued_1' }), { status: 200, headers: { 'content-type': 'application/json' } })
    },
  })

  const result = await provider.send(job())
  assert.equal(calledUrl, 'https://messaging-service.co.tz/api/sms/v1/text/single')
  assert.equal(authorization, 'Basic test')
  assert.equal(contentType, 'application/json')
  assert.equal(from, 'MICHANGO')
  assert.equal(result.providerMessageId, 'next_queued_1')
})
