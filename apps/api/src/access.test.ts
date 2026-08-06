import assert from 'node:assert/strict'
import test from 'node:test'
import type { SubscriptionSummary } from '@ahadi/types'
import { calculateTenantAccessState } from './access.js'

const activeSubscription: SubscriptionSummary = {
  id: 'sub_1',
  status: 'ACTIVE',
  planCode: 'STARTER',
  planName: 'Starter',
  trialEndsAt: null,
  currentPeriodEnd: new Date(Date.now() + 86_400_000).toISOString(),
  limits: {},
}

test('active subscription produces ACTIVE access', () => {
  assert.equal(calculateTenantAccessState('ACTIVE', activeSubscription), 'ACTIVE')
})

test('expired subscription is read only during grace', () => {
  const subscription = { ...activeSubscription, currentPeriodEnd: new Date(Date.now() - 86_400_000).toISOString() }
  assert.equal(calculateTenantAccessState('ACTIVE', subscription), 'READ_ONLY')
})

test('suspended tenant is blocked', () => {
  assert.equal(calculateTenantAccessState('SUSPENDED', activeSubscription), 'BLOCKED')
})
