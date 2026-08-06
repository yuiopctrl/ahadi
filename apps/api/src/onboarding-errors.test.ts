import assert from 'node:assert/strict'
import test from 'node:test'
import { classifyOnboardingDatabaseError, getSafeOnboardingDatabaseErrorDetails } from './onboarding-errors.js'

test('known onboarding RPC validation failures map to application errors', () => {
  assert.equal(classifyOnboardingDatabaseError({ code: '22023', message: 'PLAN_NOT_AVAILABLE' }, true).code, 'PLAN_NOT_AVAILABLE')
  assert.equal(classifyOnboardingDatabaseError({ code: '23505', message: 'ONBOARDING_ALREADY_COMPLETED' }, true).code, 'ONBOARDING_ALREADY_COMPLETED')
  assert.equal(classifyOnboardingDatabaseError({ code: '28000', message: 'SESSION_REQUIRED' }, true).code, 'SESSION_REQUIRED')
})

test('onboarding infrastructure database failures are classified safely', () => {
  assert.equal(classifyOnboardingDatabaseError({ code: 'PGRST202', message: 'function not found' }, true).category, 'ONBOARDING_RPC_NOT_FOUND')
  assert.equal(classifyOnboardingDatabaseError({ code: '42883', message: 'function digest(text, unknown) does not exist' }, true).category, 'ONBOARDING_CRYPTO_FUNCTION_UNAVAILABLE')
  assert.equal(classifyOnboardingDatabaseError({ code: '42702', message: 'column reference "result" is ambiguous' }, true).category, 'ONBOARDING_IDEMPOTENCY_RESULT_WRITE_FAILED')
  assert.equal(classifyOnboardingDatabaseError({ code: '23503', message: 'TENANT_OWNER_ROLE_MISSING' }, true).category, 'ONBOARDING_TENANT_OWNER_ROLE_MISSING')
})

test('safe onboarding database log details redact phones and tokens', () => {
  const details = getSafeOnboardingDatabaseErrorDetails('request-1', 'onboarding-complete', {
    code: '42883',
    details: 'failed for +255713676401 and 92000000',
    hint: 'Bearer abc.def.ghi access_token=secret',
    message: 'function digest failed for +255713676401',
    name: 'PostgrestError',
  })
  const serialized = JSON.stringify(details)
  assert.doesNotMatch(serialized, /\+255713676401/)
  assert.doesNotMatch(serialized, /abc\.def\.ghi/)
  assert.doesNotMatch(serialized, /secret/)
  assert.match(serialized, /rpc_complete_tenant_onboarding/)
})
