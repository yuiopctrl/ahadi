import assert from 'node:assert/strict'
import test from 'node:test'
import { setupPinSchema } from '@ahadi/validation'
import {
  classifyPinSetupDatabaseError,
  classifyPinSetupValidationError,
  getSafePinDatabaseErrorDetails,
} from './pin-errors.js'

test('weak setup PIN maps to PIN_TOO_WEAK', () => {
  const parsed = setupPinSchema.safeParse({ pin: '1234', confirmPin: '1234' })
  assert.equal(parsed.success, false)
  if (!parsed.success) {
    assert.deepEqual(classifyPinSetupValidationError(parsed.error), {
      code: 'PIN_TOO_WEAK',
      message: 'PIN_TOO_WEAK',
      status: 400,
    })
  }
})

test('invalid setup PIN length maps to PIN_INVALID', () => {
  const parsed = setupPinSchema.safeParse({ pin: '258', confirmPin: '258' })
  assert.equal(parsed.success, false)
  if (!parsed.success) {
    assert.deepEqual(classifyPinSetupValidationError(parsed.error), {
      code: 'PIN_INVALID',
      message: 'PIN_INVALID',
      status: 400,
    })
  }
})

test('PIN database error classification covers expected infrastructure failures', () => {
  assert.equal(classifyPinSetupDatabaseError({ code: 'PGRST202', message: 'function not found' }, true).category, 'PIN_RPC_NOT_FOUND')
  assert.equal(classifyPinSetupDatabaseError({ code: '42883', message: 'function gen_salt(text) does not exist' }, true).category, 'PIN_HASH_FUNCTION_UNAVAILABLE')
  assert.equal(classifyPinSetupDatabaseError({ code: '42P01', message: 'relation private.user_pin_credentials does not exist' }, true).category, 'PIN_STORAGE_TABLE_MISSING')
  assert.equal(classifyPinSetupDatabaseError({ code: '42501', message: 'permission denied for schema private' }, true).category, 'PIN_DATABASE_PERMISSION_DENIED')
  assert.equal(classifyPinSetupDatabaseError({ code: '42501', message: 'SESSION_REQUIRED' }, true).code, 'SESSION_REQUIRED')
})

test('known PIN database validation failures are not converted to INTERNAL_ERROR', () => {
  assert.equal(classifyPinSetupDatabaseError({ code: '22023', message: 'PIN_TOO_WEAK' }, true).code, 'PIN_TOO_WEAK')
  assert.equal(classifyPinSetupDatabaseError({ code: '22023', message: 'PIN_INVALID' }, true).code, 'PIN_INVALID')
})

test('safe PIN database log details redact PIN-like values and tokens', () => {
  const details = getSafePinDatabaseErrorDetails('request-1', 'set-pin', {
    code: '42883',
    details: 'failed while handling value 2580',
    hint: 'Bearer abc.def.ghi access_token=secret',
    message: 'function gen_salt failed for 2580',
    name: 'PostgrestError',
  })
  const serialized = JSON.stringify(details)
  assert.doesNotMatch(serialized, /2580/)
  assert.doesNotMatch(serialized, /abc\.def\.ghi/)
  assert.doesNotMatch(serialized, /secret/)
  assert.match(serialized, /rpc_set_my_pin/)
})
