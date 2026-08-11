import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { canSubmitPin, isCompletePin, normalizePinDigits } from './pin-entry'

const pinEntrySource = readFileSync(new URL('./pin-entry.tsx', import.meta.url), 'utf8')
const authSource = readFileSync(new URL('../pages/auth.tsx', import.meta.url), 'utf8')

test('PIN input remains exactly four numeric digits', () => {
  assert.equal(normalizePinDigits('12a345'), '1234')
  assert.equal(normalizePinDigits('258'), '258')
  assert.equal(isCompletePin('1234'), true)
  assert.equal(isCompletePin('123'), false)
  assert.equal(isCompletePin('12345'), false)
  assert.equal(isCompletePin('12a4'), false)
})

test('PIN can submit only when complete and not already pending', () => {
  assert.equal(canSubmitPin({ pin: '1234', isPending: false, isSubmitting: false }), true)
  assert.equal(canSubmitPin({ pin: '123', isPending: false, isSubmitting: false }), false)
  assert.equal(canSubmitPin({ pin: '1234', confirmPin: '4321', isPending: false, isSubmitting: false }), true)
  assert.equal(canSubmitPin({ pin: '1234', confirmPin: '432', isPending: false, isSubmitting: false }), false)
  assert.equal(canSubmitPin({ pin: '1234', isPending: true, isSubmitting: false }), false)
  assert.equal(canSubmitPin({ pin: '1234', isPending: false, isSubmitting: true }), false)
})

test('shared PIN entry auto-completes on digit four and handles Enter only when complete', () => {
  assert.match(pinEntrySource, /if \(isCompletePin\(normalized\)\) \{\s+onComplete\?\.\(normalized\)/)
  assert.match(pinEntrySource, /event\.key !== 'Enter'/)
  assert.match(pinEntrySource, /if \(!disabled && isCompletePin\(value\)\) \{\s+onEnterComplete\?\.\(\)/)
})

test('PIN page prevents duplicate fourth-digit, Enter, and button submissions', () => {
  assert.match(authSource, /const submittingRef = useRef\(false\)/)
  assert.match(authSource, /submittingRef\.current = true/)
  assert.match(authSource, /canSubmitPin\(\{ pin: nextPin, confirmPin: returningDevice \? undefined : nextConfirmPin, isPending: mutation\.isPending, isSubmitting: submittingRef\.current \}\)/)
  assert.match(authSource, /onComplete=\{\(nextConfirmPin\) => submitPin\(pin, nextConfirmPin\)\}/)
  assert.match(authSource, /onEnterComplete=\{\(\) => submitPin\(\)\}/)
})
