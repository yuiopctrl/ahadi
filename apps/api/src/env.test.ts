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

test('missing SMS_USERNAME fails environment validation', () => {
  const { SMS_USERNAME: _removed, ...input } = validEnv
  void _removed
  assert.throws(() => parseApiEnv(input), /SMS_USERNAME/)
})

test('missing SMS_PASSWORD fails environment validation', () => {
  const { SMS_PASSWORD: _removed, ...input } = validEnv
  void _removed
  assert.throws(() => parseApiEnv(input), /SMS_PASSWORD/)
})

test('missing SMS_SENDER_ID fails environment validation', () => {
  const { SMS_SENDER_ID: _removed, ...input } = validEnv
  void _removed
  assert.throws(() => parseApiEnv(input), /SMS_SENDER_ID/)
})
