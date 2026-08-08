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
