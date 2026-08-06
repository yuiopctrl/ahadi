import assert from 'node:assert/strict'
import test from 'node:test'
import { normalizeTanzaniaPhone, requestOtpSchema, setupPinSchema } from '../src/index.js'

test('normalizes supported Tanzania phone formats', () => {
  assert.equal(normalizeTanzaniaPhone('0712345678'), '+255712345678')
  assert.equal(normalizeTanzaniaPhone('0712 345 678'), '+255712345678')
  assert.equal(normalizeTanzaniaPhone('255712345678'), '+255712345678')
  assert.equal(normalizeTanzaniaPhone('+255712345678'), '+255712345678')
})

test('rejects invalid Tanzania phone values', () => {
  assert.throws(() => normalizeTanzaniaPhone('0812345678'), /INVALID_PHONE/)
  assert.equal(requestOtpSchema.safeParse({ phone: '07123' }).success, false)
})

test('rejects weak PIN values', () => {
  assert.equal(setupPinSchema.safeParse({ pin: '1234', confirmPin: '1234' }).success, false)
  assert.equal(setupPinSchema.safeParse({ pin: '2580', confirmPin: '2580' }).success, true)
})
