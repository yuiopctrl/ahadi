import assert from 'node:assert/strict'
import test from 'node:test'
import type { UserContext } from '@ahadi/types'
import { buildPlatformAccessDiagnostic, getPlatformRouteDenialReason, getPlatformRouteRedirect, getPostAuthDestination, getPublicRouteRedirect, getTenantRouteRedirect, hasActivePlatformAccess, hasActivePlatformRole } from './access'

function context(overrides: Partial<UserContext> = {}): UserContext {
  return {
    profile: null,
    isPlatformUser: false,
    platformRole: null,
    platformStatus: null,
    platformPermissions: [],
    onboardingCompleted: true,
    tenantMemberships: [],
    ...overrides,
  }
}

function activePlatformOwner(overrides: Partial<UserContext> = {}): UserContext {
  return context({
    isPlatformUser: true,
    platformRole: 'PLATFORM_OWNER',
    platformStatus: 'ACTIVE',
    platformPermissions: ['platform.dashboard.view', 'platform.tenants.view'],
    ...overrides,
  })
}

function activePlatformRole(role: NonNullable<UserContext['platformRole']>): UserContext {
  return context({
    isPlatformUser: true,
    platformRole: role,
    platformStatus: 'ACTIVE',
    platformPermissions: ['platform.dashboard.view'],
    onboardingCompleted: false,
    tenantMemberships: [],
  })
}

function tenantMembership() {
  return {
    tenantUserId: 'tu_1',
    tenantId: 'tenant_1',
    tenantCode: 'AHD-000001',
    tenantName: 'Tenant One',
    tenantSlug: 'tenant-one',
    tenantStatus: 'ACTIVE' as const,
    membershipStatus: 'ACTIVE' as const,
    isOwner: true,
    roles: ['TENANT_OWNER'],
    permissions: ['tenant.view', 'events.view'],
    subscription: null,
    accessibleEvents: [],
  }
}

test('normal tenant owner cannot open platform routes', () => {
  const tenantOwner = context({ tenantMemberships: [tenantMembership()] })
  assert.equal(hasActivePlatformAccess(tenantOwner), false)
  assert.equal(getPlatformRouteDenialReason(tenantOwner), 'platform_user_not_found')
  assert.equal(getPlatformRouteRedirect(tenantOwner), '/app')
})

test('active platform owner can open platform without tenant membership or selected tenant', () => {
  const owner = activePlatformOwner({ onboardingCompleted: false, tenantMemberships: [] })
  assert.equal(hasActivePlatformRole(owner), true)
  assert.equal(hasActivePlatformAccess(owner), true)
  assert.equal(getPublicRouteRedirect(owner), '/platform')
  assert.equal(getTenantRouteRedirect(owner, null, true), '/platform')
  assert.equal(getPlatformRouteRedirect(owner), null)
})

test('dual platform and tenant owner can access both app contexts', () => {
  const dualRole = activePlatformOwner({ tenantMemberships: [tenantMembership()] })
  assert.equal(getPlatformRouteRedirect(dualRole), null)
  assert.equal(getTenantRouteRedirect(dualRole, 'tenant_1', false), null)
  assert.equal(getPublicRouteRedirect(dualRole), '/platform')
  assert.equal(getPostAuthDestination(dualRole, '/platform'), '/platform')
  assert.equal(getPostAuthDestination(dualRole, null), '/platform')
})

test('active platform roles bypass onboarding after authentication', () => {
  for (const role of ['PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR'] as const) {
    const platformUser = activePlatformRole(role)
    assert.equal(hasActivePlatformRole(platformUser), true)
    assert.equal(getPostAuthDestination(platformUser, null), '/platform')
    assert.equal(getPublicRouteRedirect(platformUser), '/platform')
    assert.notEqual(getPostAuthDestination(platformUser, null), '/onboarding')
  }
})

test('tenant-only unfinished registration still uses onboarding', () => {
  const tenantOnly = context({ onboardingCompleted: false, tenantMemberships: [] })
  assert.equal(hasActivePlatformRole(tenantOnly), false)
  assert.equal(getPostAuthDestination(tenantOnly, '/onboarding'), '/onboarding')
})

test('platform route guard depends on platform status and permissions, not tenant permissions', () => {
  const platformOnly = activePlatformOwner({ tenantMemberships: [] })
  assert.equal(getPlatformRouteDenialReason(platformOnly), null)
  assert.equal(getPlatformRouteDenialReason(activePlatformOwner({ platformPermissions: [] })), 'platform_permission_missing')
  assert.equal(getPlatformRouteDenialReason(activePlatformOwner({ isPlatformUser: false, platformStatus: 'SUSPENDED' })), 'platform_user_not_found')
  assert.equal(getPlatformRouteDenialReason(activePlatformOwner({ platformStatus: 'SUSPENDED', platformPermissions: ['platform.dashboard.view'] })), 'platform_user_not_active')
})

test('platform diagnostic is safe and reports redirect reason', () => {
  const diagnostic = buildPlatformAccessDiagnostic({
    authenticated: true,
    lockState: { isLocked: false },
    context: context({ tenantMemberships: [tenantMembership()] }),
    attemptedRoute: '/platform',
    redirectTarget: '/app',
  })
  assert.deepEqual(diagnostic, {
    authenticated: true,
    pinUnlocked: true,
    platformUserExists: false,
    platformUserStatus: null,
    platformRole: null,
    platformPermissionsLoaded: false,
    tenantMembershipCount: 1,
    attemptedRoute: '/platform',
    redirectTarget: '/app',
    denialReason: 'platform_user_not_found',
  })
})
