import assert from 'node:assert/strict'
import test from 'node:test'
import { formatNextSmsPhone, normalizeSmsProviderName, normalizeSmsSenderId, sendNextSms, SmsProviderError } from '../src/index.js'

test('NextSMS sender ids are normalized against the confirmed allowlist', () => {
  assert.equal(normalizeSmsSenderId(' michango '), 'MICHANGO')
  assert.equal(normalizeSmsSenderId('sherehe'), 'SHEREHE')
  assert.equal(normalizeSmsSenderId(null), 'MICHANGO')
  assert.throws(() => normalizeSmsSenderId('AHADI'), /SMS sender id is not allowed/)
})

test('NextSMS phone formatter uses Tanzania canonical provider format', () => {
  assert.equal(formatNextSmsPhone('+255713676401'), '255713676401')
})

test('provider name normalization keeps historical WebBulkSMS as fallback', () => {
  assert.equal(normalizeSmsProviderName('NEXTSMS'), 'NEXTSMS')
  assert.equal(normalizeSmsProviderName('anything-else'), 'WEBBULKSMS')
  assert.equal(normalizeSmsProviderName(undefined), 'WEBBULKSMS')
})

test('NextSMS adapter fails safely until the request body contract is supplied', async () => {
  await assert.rejects(
    () => sendNextSms(
      { to: '+255713676401', message: 'hello', senderId: 'MICHANGO' },
      {
        authorization: 'Basic test',
        baseUrl: 'https://messaging-service.co.tz',
        defaultSenderId: 'MICHANGO',
        singleSmsPath: '/api/sms/v1/text/single',
      },
    ),
    (error: unknown) => error instanceof SmsProviderError && error.providerStatusCode === 'NEXTSMS_REQUEST_BODY_CONTRACT_REQUIRED',
  )
})
