import assert from 'node:assert/strict'
import test from 'node:test'
import { parseApiEnv } from './env.js'

const validEnv = {
  NODE_ENV: 'test',
  PORT: '4000',
  WEB_URL: 'http://localhost:5173',
  TRUST_PROXY_HOPS: '1',
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
  SEND_SMS_HOOK_SECRET: 'v1,whsec_dGVzdA==',
  SMS_PROVIDER_URL: 'https://sms.example.test/send',
  SMS_USERNAME: 'test-user',
  SMS_PASSWORD: 'test-password',
  SMS_SENDER_ID: 'AHADI',
}

test('SMS_API_KEY is no longer required', () => {
  const parsed = parseApiEnv(validEnv)
  assert.equal(parsed.SMS_USERNAME, 'test-user')
  assert.equal('SMS_API_KEY' in parsed, false)
})

test('missing SMS_USERNAME no longer blocks API boot', () => {
  const { SMS_USERNAME: _removed, ...input } = validEnv
  void _removed
  const parsed = parseApiEnv(input)
  assert.equal(parsed.SMS_USERNAME, undefined)
})

test('missing SMS_PASSWORD no longer blocks API boot', () => {
  const { SMS_PASSWORD: _removed, ...input } = validEnv
  void _removed
  const parsed = parseApiEnv(input)
  assert.equal(parsed.SMS_PASSWORD, undefined)
})

test('NEXTSMS mode does not require legacy WebBulkSMS credentials', () => {
  const parsed = parseApiEnv({
    NODE_ENV: 'test',
    PORT: '4000',
    WEB_URL: 'http://localhost:5173',
    TRUST_PROXY_HOPS: '1',
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    SEND_SMS_HOOK_SECRET: 'v1,whsec_dGVzdA==',
    SMS_PROVIDER: 'NEXTSMS',
    NEXTSMS_AUTHORIZATION: 'Basic test',
  })

  assert.equal(parsed.SMS_PROVIDER, 'NEXTSMS')
  assert.equal(parsed.NEXTSMS_BASE_URL, 'https://messaging-service.co.tz')
  assert.equal(parsed.NEXTSMS_DEFAULT_SENDER_ID, 'MICHANGO')
})

test('NEXTSMS authorization no longer blocks API boot', () => {
  const parsed = parseApiEnv({
    NODE_ENV: 'test',
    PORT: '4000',
    WEB_URL: 'http://localhost:5173',
    TRUST_PROXY_HOPS: '1',
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    SEND_SMS_HOOK_SECRET: 'v1,whsec_dGVzdA==',
    SMS_PROVIDER: 'NEXTSMS',
  })
  assert.equal(parsed.SMS_PROVIDER, 'NEXTSMS')
  assert.equal(parsed.NEXTSMS_AUTHORIZATION, undefined)
})
