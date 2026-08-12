import type { UserContext } from '@ahadi/types'
import type { SessionLockState } from '../stores/session-store'
import { getSingleActiveMembership, isAccessibleTenantMembership } from '../stores/session-selection'

const requiredPlatformDashboardPermission = 'platform.dashboard.view'
const activePlatformRoles = new Set(['PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR'])
const platformRolePermissions: Record<string, string[]> = {
  PLATFORM_ADMIN: [
    'platform.dashboard.view',
    'platform.tenants.view',
    'platform.tenants.manage',
    'platform.plans.view',
    'platform.plans.manage',
    'platform.subscriptions.manage',
    'platform.sms.view',
    'platform.beta.view',
    'platform.beta.manage',
    'platform.support.view',
    'platform.support.manage',
    'platform.feedback.view',
    'platform.features.view',
    'platform.features.manage',
    'platform.system_errors.view',
  ],
  PLATFORM_SUPPORT: [
    'platform.dashboard.view',
    'platform.tenants.view',
    'platform.sms.view',
    'platform.support.view',
    'platform.support.manage',
    'platform.feedback.view',
    'platform.system_errors.view',
  ],
  PLATFORM_AUDITOR: ['platform.dashboard.view', 'platform.audit.view', 'platform.system_errors.view'],
}
export type RequestedAppContext = 'platform' | 'tenant' | 'default'
export type AppContext = 'TENANT' | 'PLATFORM'

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
  if (!hasActivePlatformRole(context)) {
    return false
  }
  if (context?.platformPermissions.includes(permission)) {
    return true
  }
  if (context?.platformRole === 'PLATFORM_OWNER' && permission.startsWith('platform.')) {
    return true
  }
  return Boolean(context?.platformRole && platformRolePermissions[context.platformRole]?.includes(permission))
}

export function hasActivePlatformRole(context: UserContext | null): boolean {
  return Boolean(context?.platformStatus === 'ACTIVE' && context.platformRole && activePlatformRoles.has(context.platformRole))
}

function tenantDestination(context: UserContext | null): string {
  const accessibleMemberships = context?.tenantMemberships.filter(isAccessibleTenantMembership) ?? []
  if (!context?.onboardingCompleted && accessibleMemberships.length) {
    return '/onboarding'
  }
  const singleTenant = getSingleActiveMembership(context)
  if (singleTenant) {
    return '/app'
  }
  if (accessibleMemberships.length) {
    return '/select-tenant'
  }
  return '/select-tenant'
}

export function hasTenantWorkspaceAccess(context: UserContext | null): boolean {
  return Boolean(context?.tenantMemberships.some(isAccessibleTenantMembership))
}

export function hasDualWorkspaceAccess(context: UserContext | null): boolean {
  return hasActivePlatformAccess(context) && hasTenantWorkspaceAccess(context)
}

function inferRequestedContext(path: string | null | undefined): RequestedAppContext {
  if (!path) return 'default'
  if (path === '/platform' || path.startsWith('/platform/')) return 'platform'
  if (path === '/app' || path.startsWith('/app/') || path === '/onboarding' || path === '/register') return 'tenant'
  return 'default'
}

function platformDestination(path: string | null | undefined): string {
  if (path && path.startsWith('/platform') && path !== '/platform/login') {
    return path
  }
  return '/platform'
}

export function resolveAuthenticatedDestination({
  context,
  requestedPath = null,
  requestedContext,
}: {
  context: UserContext | null
  requestedPath?: string | null
  requestedContext?: RequestedAppContext
}): string {
  const appContext = requestedContext ?? inferRequestedContext(requestedPath)
  if (appContext === 'platform') {
    return platformDestination(requestedPath)
  }
  if (requestedPath === '/onboarding') {
    return '/onboarding'
  }
  if (appContext === 'tenant') {
    return tenantDestination(context)
  }
  if (hasDualWorkspaceAccess(context)) {
    return '/choose-workspace'
  }
  if (hasActivePlatformAccess(context)) {
    return '/platform'
  }
  return tenantDestination(context)
}

export function getPublicRouteRedirect(context: UserContext | null): string {
  return resolveAuthenticatedDestination({ context, requestedContext: 'default' })
}

export function getPostAuthDestination(context: UserContext | null, preferredDestination: string | null): string {
  return resolveAuthenticatedDestination({ context, requestedPath: preferredDestination })
}

export function getPlatformRouteDenialReason(context: UserContext | null, permission = requiredPlatformDashboardPermission): string | null {
  if (!context?.platformRole && !context?.isPlatformUser) {
    return 'platform_user_not_found'
  }
  if (context.platformStatus !== 'ACTIVE') {
    return 'platform_user_not_active'
  }
  if (!hasActivePlatformAccess(context, permission)) {
    return 'platform_permission_missing'
  }
  return null
}

export function getPlatformRouteRedirect(context: UserContext | null, fallback = '/app'): string | null {
  return getPlatformRouteDenialReason(context) ? fallback : null
}

export function getTenantRouteRedirect(context: UserContext | null, selectedTenantId: string | null, selectedTenantBlocked: boolean): string | null {
  const accessibleMemberships = context?.tenantMemberships.filter(isAccessibleTenantMembership) ?? []
  if (!context?.onboardingCompleted && accessibleMemberships.length) {
    return hasActivePlatformRole(context) ? '/platform' : '/onboarding'
  }
  if (!accessibleMemberships.length) {
    return hasActivePlatformRole(context) ? '/platform' : '/select-tenant'
  }
  const selectedMembership = context?.tenantMemberships.find((membership) => membership.tenantId === selectedTenantId)
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
