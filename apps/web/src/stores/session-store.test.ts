import assert from 'node:assert/strict'
import test from 'node:test'
import type { UserContext } from '@ahadi/types'
import { getSingleActiveMembership } from './session-selection'

function contextWithMemberships(count: number): UserContext {
  return {
    profile: null,
    isPlatformUser: false,
    platformRole: null,
    onboardingCompleted: true,
    tenantMemberships: Array.from({ length: count }, (_, index) => ({
      tenantUserId: `tu_${index}`,
      tenantId: `tenant_${index}`,
      tenantCode: `AHD-${String(index).padStart(6, '0')}`,
      tenantName: `Tenant ${index}`,
      tenantSlug: `tenant-${index}`,
      tenantStatus: 'ACTIVE',
      membershipStatus: 'ACTIVE',
      isOwner: index === 0,
      roles: ['TENANT_OWNER'],
      permissions: ['events.view'],
      subscription: null,
      accessibleEvents: [],
    })),
  }
}

test('single active tenant can be selected automatically', () => {
  assert.equal(getSingleActiveMembership(contextWithMemberships(1))?.tenantId, 'tenant_0')
})

test('several active tenants require explicit selection', () => {
  assert.equal(getSingleActiveMembership(contextWithMemberships(2)), null)
})
