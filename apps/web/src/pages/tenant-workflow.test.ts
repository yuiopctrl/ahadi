import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const tenantPage = readFileSync(new URL('./tenant.tsx', import.meta.url), 'utf8')
const navigation = readFileSync(new URL('../navigation.tsx', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../lib/api.ts', import.meta.url), 'utf8')

test('tenant workflow does not depend on hardcoded demo event ids', () => {
  assert.doesNotMatch(navigation, /event_001/)
  assert.ok(navigation.includes("event ? `/app/events/${event.id}`"))
})

test('financial pages render explicit empty and error states instead of blank lists', () => {
  for (const copy of [
    'No members have been added to this event yet.',
    'No pledges have been recorded yet.',
    'No payments have been recorded yet.',
    'Unable to load members',
    'Unable to load pledges',
    'Unable to load payments',
  ]) {
    assert.match(tenantPage, new RegExp(copy.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  }
  assert.doesNotMatch(tenantPage, /return null/)
})

test('record payment flow uses route event context and stable idempotency per attempt', () => {
  assert.match(tenantPage, /useActiveEventContext\(eventId\)/)
  assert.match(tenantPage, /const \[idempotencyKey, resetIdempotencyKey\] = useState\(\(\) => crypto\.randomUUID\(\)\)/)
  assert.match(tenantPage, /idempotencyKey, pledgeId/)
  assert.doesNotMatch(tenantPage, /idempotencyKey: crypto\.randomUUID\(\)/)
})

test('API client preserves structured errors and bypasses browser cache', () => {
  assert.match(apiClient, /requestId: string \| null/)
  assert.match(apiClient, /cache: 'no-store'/)
  assert.match(apiClient, /Cache-Control', 'no-cache'/)
})
