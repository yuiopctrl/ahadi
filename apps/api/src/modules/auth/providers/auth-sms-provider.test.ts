import assert from 'node:assert/strict'
import test from 'node:test'
import { formatWebBulkSmsPhone, parseSmsProviderResponse, sanitizeProviderReason, sendAuthenticationSms, SmsProviderError } from './auth-sms-provider.js'

const providerOptions = {
  providerUrl: 'https://sms.example.test/send',
  username: 'fake-user',
  password: 'fake-password',
  senderId: 'YUIOP APPS',
  timeoutMs: 10_000,
}

const smsInput = {
  to: '+255712345678',
  message: '123456 ni namba yako ya uthibitisho ya Ahadi. Usimpe mtu mwingine.',
}

test('provider receives configured username, password, sender, phone and message', async () => {
  let capturedBody: Record<string, unknown> = {}
  let capturedAuthorizationHeader: string | null = null
  const fetchImpl: typeof fetch = async (_input, init) => {
    assert.equal(init?.method, 'POST')
    capturedAuthorizationHeader = new Headers(init?.headers).get('authorization')
    assert.equal(new Headers(init?.headers).get('content-type'), 'application/json')
    assert.equal(new Headers(init?.headers).get('accept'), 'application/json')
    assert.equal(typeof init?.body, 'string')
    capturedBody = JSON.parse(String(init.body))
    return new Response(JSON.stringify({ success: true, message_id: 'msg_test' }), { status: 200 })
  }

  const result = await sendAuthenticationSms(smsInput, { ...providerOptions, fetchImpl })

  assert.deepEqual(capturedBody, {
    username: 'fake-user',
    password: 'fake-password',
    senderId: 'YUIOP APPS',
    phoneNumbers: ['255712345678'],
    message: smsInput.message,
  })
  assert.equal('sender_id' in capturedBody, false)
  assert.equal('recipient' in capturedBody, false)
  assert.equal('destination' in capturedBody, false)
  assert.equal(capturedAuthorizationHeader, null)
  assert.deepEqual(result, { accepted: true, providerHttpStatus: 200, providerMessageId: 'msg_test', providerStatusCode: null, safeReason: null })
})

test('WebBulkSMS phone formatter removes only the E.164 plus', () => {
  assert.equal(formatWebBulkSmsPhone('+255713676401'), '255713676401')
  assert.equal(formatWebBulkSmsPhone('255713676401'), '255713676401')
  assert.equal(formatWebBulkSmsPhone('0713676401'), '255713676401')
})

test('one recipient produces a phoneNumbers array containing one string', async () => {
  let capturedBody: Record<string, unknown> = {}
  const fetchImpl: typeof fetch = async (_input, init) => {
    capturedBody = JSON.parse(String(init?.body))
    return new Response(JSON.stringify({ success: true }), { status: 200 })
  }

  await sendAuthenticationSms({ ...smsInput, to: '+255713676401' }, { ...providerOptions, fetchImpl })

  assert.deepEqual(capturedBody['phoneNumbers'], ['255713676401'])
  assert.equal(Array.isArray(capturedBody['phoneNumbers']), true)
})

test('provider credentials and OTP are never written to logs', async () => {
  const originalError = console.error
  const originalInfo = console.info
  const originalWarn = console.warn
  const entries: string[] = []
  const capture = (...data: unknown[]) => {
    entries.push(JSON.stringify(data))
  }
  console.error = capture
  console.info = capture
  console.warn = capture
  try {
    const fetchImpl: typeof fetch = async () => new Response(JSON.stringify({ success: true, message_id: 'msg_test' }), { status: 200 })
    await sendAuthenticationSms(smsInput, { ...providerOptions, fetchImpl })
  } finally {
    console.error = originalError
    console.info = originalInfo
    console.warn = originalWarn
  }

  const logs = entries.join('\n')
  assert.doesNotMatch(logs, /fake-user/)
  assert.doesNotMatch(logs, /fake-password/)
  assert.doesNotMatch(logs, /123456/)
  assert.doesNotMatch(logs, /\+255712345678/)
  assert.doesNotMatch(logs, /255712345678/)
  assert.match(logs, /2557\*{5}678/)
})

test('provider rejection throws a typed error', async () => {
  const fetchImpl: typeof fetch = async () => new Response(JSON.stringify({ success: false, message: 'Rejected' }), { status: 200 })

  await assert.rejects(() => sendAuthenticationSms(smsInput, { ...providerOptions, fetchImpl }), SmsProviderError)
})

test('provider HTTP 200 with failure status is treated as failure', async () => {
  const fetchImpl: typeof fetch = async () => new Response(JSON.stringify({ status: 'failed', message_id: null }), { status: 200 })

  await assert.rejects(() => sendAuthenticationSms(smsInput, { ...providerOptions, fetchImpl }), SmsProviderError)
})

test('provider non-2xx response is treated as failure', async () => {
  const fetchImpl: typeof fetch = async () => new Response(JSON.stringify({ success: false }), { status: 401 })

  await assert.rejects(() => sendAuthenticationSms(smsInput, { ...providerOptions, fetchImpl }), SmsProviderError)
})

test('provider rejection exposes sanitized internal reason', async () => {
  const fetchImpl: typeof fetch = async () => new Response(JSON.stringify({ message: 'Sender ID is not approved for your account' }), { status: 400 })

  await assert.rejects(
    () => sendAuthenticationSms(smsInput, { ...providerOptions, fetchImpl }),
    (error: unknown) =>
      error instanceof SmsProviderError &&
      error.status === 400 &&
      error.providerReason === 'Sender ID is not approved for your account',
  )
})

test('provider response parser accepts known success shapes', () => {
  assert.deepEqual(parseSmsProviderResponse(JSON.stringify({ status: 'success', message_id: 'abc' })), { accepted: true, providerMessageId: 'abc', providerStatusCode: 'success', safeReason: null })
  assert.deepEqual(parseSmsProviderResponse('1701|abc'), { accepted: true, providerMessageId: null, providerStatusCode: '1701', safeReason: null })
  assert.deepEqual(parseSmsProviderResponse(JSON.stringify({ message: 'Sent sms successfully' })), { accepted: true, providerMessageId: null, providerStatusCode: null, safeReason: null })
})

test('provider reason sanitizer masks phone-like values', () => {
  assert.equal(sanitizeProviderReason(JSON.stringify({ message: 'Invalid recipient +255712345678' })), 'Invalid recipient <redacted-phone>')
})
