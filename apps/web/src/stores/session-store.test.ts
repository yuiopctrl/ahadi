import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import type { UserContext } from '@ahadi/types'
import { getSingleActiveMembership } from './session-selection'

const sessionStore = readFileSync(new URL('./session-store.tsx', import.meta.url), 'utf8')

function contextWithMemberships(count: number): UserContext {
  return {
    profile: null,
    isPlatformUser: false,
    platformRole: null,
    platformStatus: null,
    platformPermissions: [],
    onboardingCompleted: true,
    pendingInvitations: [],
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

test('session bootstrap separates auth restoration, access resolution, tenant restoration and errors', () => {
  assert.match(sessionStore, /export type BootstrapState =[\s\S]+'INITIALIZING'[\s\S]+'RESTORING_SESSION'[\s\S]+'RESOLVING_ACCESS'[\s\S]+'READY'[\s\S]+'UNAUTHENTICATED'[\s\S]+'ERROR'/)
  assert.match(sessionStore, /export type AuthStatus = 'INITIALIZING' \| 'AUTHENTICATED' \| 'UNAUTHENTICATED' \| 'ERROR'/)
  assert.match(sessionStore, /export type AccessState = \{[\s\S]+platform:[\s\S]+tenant:/)
  assert.match(sessionStore, /authStatusForBootstrap/)
  assert.match(sessionStore, /accessStateForBootstrap/)
  assert.match(sessionStore, /setBootstrapState\('RESTORING_SESSION'\)/)
  assert.match(sessionStore, /setBootstrapState\('RESOLVING_ACCESS'\)/)
  assert.match(sessionStore, /setBootstrapState\('READY'\)/)
  assert.match(sessionStore, /setBootstrapState\('UNAUTHENTICATED'\)/)
  assert.match(sessionStore, /setBootstrapState\('ERROR'\)/)
  assert.match(sessionStore, /restoreTenantSelection/)
  assert.match(sessionStore, /!hasActivePlatformIdentity\(context\) && activeMemberships\.length === 1/)
  assert.match(sessionStore, /isExpiredSessionError\(error\)[\s\S]+supabase\.auth\.signOut\(\)/)
})

test('session bootstrap never persists offline or backend availability state', () => {
  assert.doesNotMatch(sessionStore, /isOffline|networkStatus|backendUnavailable|lastNetworkFailure/)
  assert.doesNotMatch(sessionStore, /localStorage\.setItem\([^)]*OFFLINE|sessionStorage\.setItem\([^)]*OFFLINE/)
})
