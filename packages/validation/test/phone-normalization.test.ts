import assert from 'node:assert/strict'
import test from 'node:test'
import { normalizeTanzaniaPhone, onboardingPayloadSchema, requestOtpSchema, setupPinSchema } from '../src/index.js'

test('normalizes supported Tanzania phone formats', () => {
  assert.equal(normalizeTanzaniaPhone('0712345678'), '+255712345678')
  assert.equal(normalizeTanzaniaPhone('0712 345 678'), '+255712345678')
  assert.equal(normalizeTanzaniaPhone('712345678'), '+255712345678')
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

test('accepts onboarding optional fields as null', () => {
  const parsed = onboardingPayloadSchema.safeParse({
    planCode: 'starter',
    tenantName: 'Family Committee',
    tenantPhone: '0712345678',
    tenantEmail: null,
    adminFullName: 'Test Admin',
    adminEmail: null,
    preferredLanguage: 'sw',
    firstEventName: 'First Event',
    eventType: 'WEDDING',
    customEventType: null,
    eventDate: null,
    venue: null,
    targetAmount: null,
    pledgeDeadline: null,
    idempotencyKey: '00000000-0000-4000-8000-000000000000',
  })

  assert.equal(parsed.success, true)
  if (parsed.success) {
    assert.equal(parsed.data.planCode, 'STARTER')
    assert.equal(parsed.data.tenantPhone, '+255712345678')
    assert.equal(parsed.data.tenantEmail, null)
    assert.equal(parsed.data.adminEmail, null)
    assert.equal(parsed.data.customEventType, null)
    assert.equal(parsed.data.eventDate, null)
    assert.equal(parsed.data.venue, null)
    assert.equal(parsed.data.pledgeDeadline, null)
  }
})
