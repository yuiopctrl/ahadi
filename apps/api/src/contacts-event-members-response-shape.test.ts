import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { expectPaginatedListResponse, jsonArray, jsonRecord } from './app.js'
import { AppError } from './errors.js'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const migration071 = readFileSync(
  new URL('../../../supabase/migrations/071_drop_obsolete_contacts_and_event_members_overloads.sql', import.meta.url),
  'utf8',
)

// --- Regression: production returned {"data":[]} for a tenant with 290
// ACTIVE contacts because the whole RPC result -- now a jsonb envelope
// object, not a bare array -- was being run through Array.isArray-style
// coalescing that treats "not an array" as "empty", silently. These tests
// feed the exact realistic shape rpc_list_contacts / rpc_list_event_members
// actually return in production and assert the row/pagination data survives.

test('a realistic rpc_list_contacts envelope (290 contacts) is preserved end to end, not collapsed to empty', () => {
  const realisticRpcResult = {
    data: [
      { member_id: 'a1111111-1111-1111-1111-111111111111', full_name: 'Victor Kinabo', phone_e164: '+255712345678' },
    ],
    pagination: { limit: 20, offset: 0, totalRows: 290, hasMore: true },
    usage: { used: 290, limit: 500, available: 210 },
  }

  const result = expectPaginatedListResponse(realisticRpcResult, 'req-1', 'CONTACTS_LIST', ['usage'])
  const responseBody = {
    data: jsonArray(result['data']),
    pagination: jsonRecord(result['pagination']),
    usage: jsonRecord(result['usage']),
  }

  assert.equal(responseBody.data.length, 1)
  assert.equal(responseBody.data[0]?.['full_name'], 'Victor Kinabo')
  assert.equal(responseBody.pagination['totalRows'], 290)
  assert.equal(responseBody.usage['used'], 290)
  assert.equal(responseBody.usage['limit'], 500)
  assert.notDeepEqual(responseBody, { data: [] })
})

test('a realistic rpc_list_event_members envelope preserves rows, pagination and filter-relevant fields', () => {
  const realisticRpcResult = {
    data: [
      {
        event_member_id: 'em-1',
        full_name: 'Jane Contact',
        phone_e164: '+255712345678',
        pledged_amount: 100000,
        total_allocated: 40000,
        outstanding_amount: 60000,
        pledge_status: 'PARTIALLY_PAID',
      },
    ],
    pagination: { limit: 10, offset: 0, totalRows: 1, hasMore: false },
  }

  const result = expectPaginatedListResponse(realisticRpcResult, 'req-2', 'EVENT_MEMBERS_LIST')
  const responseBody = {
    data: jsonArray(result['data']),
    pagination: jsonRecord(result['pagination']),
  }

  assert.equal(responseBody.data.length, 1)
  assert.equal(responseBody.data[0]?.['outstanding_amount'], 60000)
  assert.equal(responseBody.pagination['totalRows'], 1)
})

test('expectPaginatedListResponse throws a diagnostic AppError instead of silently returning an empty list when the RPC result is a bare array (legacy shape resurfacing)', () => {
  const legacyBareArrayResult = [
    { member_id: 'a1111111-1111-1111-1111-111111111111', full_name: 'Victor Kinabo' },
  ]
  assert.throws(
    () => expectPaginatedListResponse(legacyBareArrayResult, 'req-3', 'CONTACTS_LIST', ['usage']),
    (error: unknown) => {
      assert.ok(error instanceof AppError)
      assert.equal(error.code, 'INTERNAL_ERROR')
      assert.equal(error.status, 500)
      assert.equal(error.category, 'CONTACTS_LIST_MALFORMED_RESPONSE')
      return true
    },
  )
})

test('expectPaginatedListResponse throws when pagination is missing or a required object field (usage) is missing', () => {
  assert.throws(() => expectPaginatedListResponse({ data: [] }, 'req-4', 'CONTACTS_LIST', ['usage']))
  assert.throws(() => expectPaginatedListResponse({ data: [], pagination: {} }, 'req-5', 'CONTACTS_LIST', ['usage']))
  assert.throws(() => expectPaginatedListResponse(null, 'req-6', 'CONTACTS_LIST'))
  assert.throws(() => expectPaginatedListResponse('unexpected string', 'req-7', 'CONTACTS_LIST'))
  // Valid without a required-keys list (event-members has no `usage` field).
  assert.doesNotThrow(() => expectPaginatedListResponse({ data: [], pagination: {} }, 'req-8', 'EVENT_MEMBERS_LIST'))
})

// --- Route wiring: both routes must validate the envelope AND log the raw
// DB/PostgREST error (code/details/hint) before it's discarded by
// throwFinancialDatabaseError's fallback to a generic INTERNAL_ERROR.

test('GET /api/v1/contacts logs the raw database error and validates the RPC envelope before responding', () => {
  const start = app.indexOf("app.get('/api/v1/contacts'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /logDatabaseError\(request\.requestId, 'contacts-list', error, \{ tenantId \}\)/)
  assert.match(routeBody, /throwFinancialDatabaseError\(error, 'CONTACTS_LIST_FAILED'\)/)
  assert.match(routeBody, /expectPaginatedListResponse\(data, request\.requestId, 'CONTACTS_LIST', \['usage'\]\)/)
})

test('GET /api/v1/events/:eventId/members logs the raw database error and validates the RPC envelope before responding', () => {
  const start = app.indexOf("app.get('/api/v1/events/:eventId/members'")
  const end = app.indexOf('\n})', start)
  const routeBody = app.slice(start, end)
  assert.match(routeBody, /logDatabaseError\(request\.requestId, 'event-members-list', error, \{ tenantId, eventId \}\)/)
  assert.match(routeBody, /throwFinancialDatabaseError\(error, 'EVENT_MEMBERS_LIST_FAILED'\)/)
  assert.match(routeBody, /expectPaginatedListResponse\(data, request\.requestId, 'EVENT_MEMBERS_LIST'\)/)
})

// --- Migration 071: drop the ambiguous legacy overloads, keep the new ones.

test('migration 071 drops the legacy rpc_list_contacts(uuid) and rpc_list_event_members(uuid, uuid) overloads only', () => {
  assert.match(migration071, /drop function if exists public\.rpc_list_contacts\(uuid\);/)
  assert.match(migration071, /drop function if exists public\.rpc_list_event_members\(uuid, uuid\);/)
  assert.match(migration071, /notify pgrst, 'reload schema';/)
  // Must not touch the new 4-arg / 9-arg signatures introduced in 070 -- only
  // check the actual `drop function` statements, since the explanatory
  // header comment above them legitimately mentions the new signatures.
  const dropStatements = migration071.slice(migration071.indexOf('drop function'), migration071.indexOf("notify pgrst"))
  assert.doesNotMatch(dropStatements, /rpc_list_contacts\(uuid, text, integer, integer\)/)
  assert.doesNotMatch(dropStatements, /rpc_list_event_members\(uuid, uuid, text/)
})
