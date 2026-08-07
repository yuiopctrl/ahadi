import type { UserContext } from '@ahadi/types'
import type { SessionLockState } from '../stores/session-store'
import { getSingleActiveMembership } from '../stores/session-selection'

const requiredPlatformDashboardPermission = 'platform.dashboard.view'

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

export function getPublicRouteRedirect(context: UserContext | null): string {
  if (hasActivePlatformAccess(context) && !context?.tenantMemberships.length) {
    return '/platform'
  }
  if (!context?.onboardingCompleted) {
    return '/onboarding'
  }
  const singleTenant = getSingleActiveMembership(context)
  if (singleTenant) {
    return '/app'
  }
  if (context?.tenantMemberships.length) {
    return '/select-tenant'
  }
  return hasActivePlatformAccess(context) ? '/platform' : '/onboarding'
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
    return hasActivePlatformAccess(context) ? '/platform' : '/onboarding'
  }
  if (!selectedTenantId || selectedTenantBlocked) {
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
