import assert from 'node:assert/strict'
import test from 'node:test'
import { assertSmsCharacterLimit, formatNextSmsPhone, MAX_SMS_CHARACTERS, normalizeSmsMessageText, normalizeSmsProviderName, normalizeSmsSenderId, sendNextSms, SmsProviderError, SmsProviderRegistry, smsCharacterCount } from '../src/index.js'

test('NextSMS sender ids are normalized against the confirmed allowlist', () => {
  assert.equal(normalizeSmsSenderId(' michango '), 'MICHANGO')
  assert.equal(normalizeSmsSenderId('sherehe'), 'SHEREHE')
  assert.equal(normalizeSmsSenderId(null), 'MICHANGO')
  assert.throws(() => normalizeSmsSenderId('AHADI'), /SMS sender id is not allowed/)
})

test('NextSMS phone formatter uses Tanzania canonical provider format', () => {
  assert.equal(formatNextSmsPhone('+255713676401'), '255713676401')
})

test('provider name normalization rejects unsupported providers instead of falling back', () => {
  assert.equal(normalizeSmsProviderName('NEXTSMS'), 'NEXTSMS')
  assert.equal(normalizeSmsProviderName('webbulksms'), 'WEBBULKSMS')
  assert.throws(() => normalizeSmsProviderName('anything-else'), /SMS provider is not supported/)
  assert.throws(() => normalizeSmsProviderName(undefined), /SMS provider is not supported/)
})

test('provider registry routes NEXTSMS without invoking WebBulkSMS credentials', async () => {
  const registry = new SmsProviderRegistry({
    nextSmsAuthorization: 'Basic test',
    nextSmsBaseUrl: 'https://messaging-service.co.tz',
    nextSmsDefaultSenderId: 'MICHANGO',
    nextSmsSingleSmsPath: '/api/sms/v1/text/single',
    fetchImpl: async () => new Response(JSON.stringify({ status: 'success', message_id: 'next_2' }), { status: 200, headers: { 'content-type': 'application/json' } }),
  })
  const result = await registry.sendSingle({ providerCode: 'NEXTSMS', to: '+255713676401', message: 'hello', senderId: 'MICHANGO' })
  assert.equal(result.providerMessageId, 'next_2')
})

test('provider registry preserves WEBBULKSMS routing for tenants that select it', async () => {
  let calledUrl = ''
  const registry = new SmsProviderRegistry({
    webBulkSmsUrl: 'https://webbulk.example.test/send',
    webBulkSmsUsername: 'user',
    webBulkSmsPassword: 'pass',
    webBulkSmsSenderId: 'YUIOP APPS',
    fetchImpl: async (url) => {
      calledUrl = String(url)
      return new Response(JSON.stringify({ status: 'success', message_id: 'web_1' }), { status: 200, headers: { 'content-type': 'application/json' } })
    },
  })
  const result = await registry.sendSingle({ providerCode: 'WEBBULKSMS', to: '+255713676401', message: 'hello', senderId: 'YUIOP APPS' })
  assert.equal(calledUrl, 'https://webbulk.example.test/send')
  assert.equal(result.providerMessageId, 'web_1')
})

test('NextSMS adapter posts the verified single-SMS contract', async () => {
  let calledUrl = ''
  let authorization = ''
  let fields: Record<string, string> = {}
  const result = await sendNextSms(
    { to: '+255713676401', message: 'hello', senderId: 'MICHANGO' },
    {
      authorization: 'Basic test',
      baseUrl: 'https://messaging-service.co.tz',
      defaultSenderId: 'MICHANGO',
      singleSmsPath: '/api/sms/v1/text/single',
      fetchImpl: async (url, init) => {
        calledUrl = String(url)
        authorization = new Headers(init?.headers).get('authorization') ?? ''
        const body = init?.body as FormData
        fields = {
          from: String(body.get('from')),
          to: String(body.get('to')),
          text: String(body.get('text')),
        }
        return new Response(JSON.stringify({ status: 'success', message_id: 'next_1' }), { status: 200, headers: { 'content-type': 'application/json' } })
      },
    },
  )
  assert.equal(calledUrl, 'https://messaging-service.co.tz/api/sms/v1/text/single')
  assert.equal(authorization, 'Basic test')
  assert.deepEqual(fields, { from: 'MICHANGO', to: '255713676401', text: 'hello' })
  assert.equal(result.providerMessageId, 'next_1')
})

test('SMS character limit counts normalized final rendered text', () => {
  assert.equal(MAX_SMS_CHARACTERS, 159)
  assert.equal(smsCharacterCount('x'.repeat(100)), 100)
  assert.equal(smsCharacterCount('x'.repeat(158)), 158)
  assert.equal(smsCharacterCount('x'.repeat(159)), 159)
  assert.equal(assertSmsCharacterLimit(` ${'x'.repeat(159)} `), 'x'.repeat(159))
  assert.throws(() => assertSmsCharacterLimit('x'.repeat(160)), /SMS exceeds/)
  assert.equal(normalizeSmsMessageText('hello\n\n  world'), 'hello world')
})

test('provider guard rejects over-limit SMS before provider HTTP request', async () => {
  await assert.rejects(
    () => sendNextSms(
      { to: '+255713676401', message: 'x'.repeat(160), senderId: 'MICHANGO' },
      {
        authorization: 'Basic test',
        baseUrl: 'https://messaging-service.co.tz',
        defaultSenderId: 'MICHANGO',
        singleSmsPath: '/api/sms/v1/text/single',
      },
    ),
    (error: unknown) => error instanceof SmsProviderError && error.providerStatusCode === 'SMS_CHARACTER_LIMIT_EXCEEDED',
  )
})
