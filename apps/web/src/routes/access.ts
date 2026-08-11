import type { UserContext } from '@ahadi/types'
import type { SessionLockState } from '../stores/session-store'
import { getSingleActiveMembership, isAccessibleTenantMembership } from '../stores/session-selection'

const requiredPlatformDashboardPermission = 'platform.dashboard.view'
const activePlatformRoles = new Set(['PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR'])

export interface PlatformAccessDiagnostic {
  authenticated: boolean
  pinUnlocked: boolean
  platformUserExists: boolean
  platformUserStatus: string | null
  platformRole: string | null
  platformPermissionsLoaded: boolean
  tenantMembershipCount: number
  attemptedRoute: string
  redirectTarget: string | null
  denialReason: string | null
}

export function hasActivePlatformAccess(context: UserContext | null, permission = requiredPlatformDashboardPermission): boolean {
  return Boolean(context?.isPlatformUser && context.platformStatus === 'ACTIVE' && context.platformPermissions.includes(permission))
}

export function hasActivePlatformRole(context: UserContext | null): boolean {
  return Boolean(context?.isPlatformUser && context.platformStatus === 'ACTIVE' && context.platformRole && activePlatformRoles.has(context.platformRole))
}

export function getPublicRouteRedirect(context: UserContext | null): string {
  const accessibleMemberships = context?.tenantMemberships.filter(isAccessibleTenantMembership) ?? []
  if (hasActivePlatformRole(context)) {
    return '/platform'
  }
  if (!context?.onboardingCompleted) {
    return '/onboarding'
  }
  const singleTenant = getSingleActiveMembership(context)
  if (singleTenant) {
    return '/app'
  }
  if (accessibleMemberships.length) {
    return '/select-tenant'
  }
  return '/onboarding'
}

export function getPostAuthDestination(context: UserContext | null, preferredDestination: string | null): string {
  if ((preferredDestination === '/platform' && hasActivePlatformAccess(context)) || hasActivePlatformRole(context)) {
    return '/platform'
  }
  return getPublicRouteRedirect(context)
}

export function getPlatformRouteDenialReason(context: UserContext | null, permission = requiredPlatformDashboardPermission): string | null {
  if (!context?.isPlatformUser) {
    return 'platform_user_not_found'
  }
  if (context.platformStatus !== 'ACTIVE') {
    return 'platform_user_not_active'
  }
  if (!context.platformPermissions.includes(permission)) {
    return 'platform_permission_missing'
  }
  return null
}

export function getPlatformRouteRedirect(context: UserContext | null, fallback = '/app'): string | null {
  return getPlatformRouteDenialReason(context) ? fallback : null
}

export function getTenantRouteRedirect(context: UserContext | null, selectedTenantId: string | null, selectedTenantBlocked: boolean): string | null {
  if (!context?.onboardingCompleted) {
    return hasActivePlatformRole(context) ? '/platform' : '/onboarding'
  }
  const selectedMembership = context.tenantMemberships.find((membership) => membership.tenantId === selectedTenantId)
  if (!selectedTenantId || selectedTenantBlocked || (selectedMembership && !isAccessibleTenantMembership(selectedMembership))) {
    return '/select-tenant'
  }
  return null
}

export function buildPlatformAccessDiagnostic({
  authenticated,
  lockState,
  context,
  attemptedRoute,
  redirectTarget,
}: {
  authenticated: boolean
  lockState: Pick<SessionLockState, 'isLocked'>
  context: UserContext | null
  attemptedRoute: string
  redirectTarget: string | null
}): PlatformAccessDiagnostic {
  return {
    authenticated,
    pinUnlocked: !lockState.isLocked,
    platformUserExists: context?.platformStatus !== null && context?.platformStatus !== undefined,
    platformUserStatus: context?.platformStatus ?? null,
    platformRole: context?.platformRole ?? null,
    platformPermissionsLoaded: Boolean(context?.platformPermissions.length),
    tenantMembershipCount: context?.tenantMemberships.length ?? 0,
    attemptedRoute,
    redirectTarget,
    denialReason: getPlatformRouteDenialReason(context),
  }
}
