import assert from 'node:assert/strict'
import test from 'node:test'
import { mapUnknownError } from './errors.js'

test('maps Supabase/PostgREST plain-object errors by database message', () => {
  const error = mapUnknownError({
    code: '22023',
    message: 'EVENT_LIMIT_REACHED',
    details: null,
    hint: null,
  })

  assert.equal(error.code, 'EVENT_LIMIT_REACHED')
  assert.equal(error.status, 409)
})

test('maps database messages from details and hints, not only Error instances', () => {
  const error = mapUnknownError({
    code: '42501',
    message: 'permission denied',
    details: 'TENANT_ACCESS_DENIED',
  })

  assert.equal(error.code, 'TENANT_ACCESS_DENIED')
  assert.equal(error.status, 403)
})

test('maps raw Postgres permission errors to PERMISSION_DENIED', () => {
  const error = mapUnknownError({
    code: '42501',
    message: 'permission denied for table events',
  })

  assert.equal(error.code, 'PERMISSION_DENIED')
  assert.equal(error.status, 403)
})

test('maps event check constraints to event-specific validation errors', () => {
  assert.equal(mapUnknownError({ code: '23514', message: 'violates check constraint "events_event_type_check"' }).code, 'INVALID_EVENT_TYPE')
  assert.equal(mapUnknownError({ code: '23514', message: 'violates check constraint "events_target_amount_check"' }).code, 'INVALID_TARGET_AMOUNT')
})
