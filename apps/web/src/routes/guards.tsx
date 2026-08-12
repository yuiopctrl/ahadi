import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { ErrorState, LoadingState, PageContainer } from '../components/ui'
import { useSessionStore } from '../stores/session-store'
import { isAccessibleTenantMembership } from '../stores/session-selection'
import { buildPlatformAccessDiagnostic, getPlatformRouteDenialReason, getPlatformRouteRedirect, getTenantRouteRedirect, hasActivePlatformRole, resolveAuthenticatedDestination } from './access'

function FullScreenLoading() {
  return (
    <PageContainer narrow>
      <LoadingState title="Restoring session" message="Checking your secure Ahadi session." />
    </PageContainer>
  )
}

function FullScreenBootstrapError({ message }: { message: string | null }) {
  return (
    <PageContainer narrow>
      <ErrorState title="Unable to restore session" message={message ?? 'Please refresh or sign in again.'} />
    </PageContainer>
  )
}

function postAuthDestination() {
  return '/verify-otp'
}

function platformAccessMessage(reason: string | null) {
  if (reason === 'platform_user_not_found') {
    return 'This authenticated account does not have a platform_users record. Create or fix that row for this user before opening the platform console.'
  }
  if (reason === 'platform_user_not_active') {
    return 'This account has a platform user record, but it is not ACTIVE.'
  }
  if (reason === 'platform_permission_missing') {
    return 'This account has an active platform role, but it is missing the required platform.dashboard.view permission.'
  }
  return 'This account is not allowed to open the platform console.'
}

export function PublicRoute() {
  const session = useSessionStore()
  const location = useLocation()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (session.bootstrapState === 'ERROR') {
    return <FullScreenBootstrapError message={session.bootstrapError} />
  }
  if (!session.session) {
    return <Outlet />
  }
  if (session.lockState.isLocked) {
    const postAuthDestination = location.pathname.startsWith('/platform') ? '/platform' : null
    return <Navigate to="/setup-pin" replace state={postAuthDestination ? { postAuthDestination } : undefined} />
  }
  return <Navigate to={resolveAuthenticatedDestination({ context: session.userContext, requestedPath: location.pathname })} replace />
}

export function AuthenticatedRoute() {
  const session = useSessionStore()
  const location = useLocation()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (session.bootstrapState === 'ERROR') {
    return <FullScreenBootstrapError message={session.bootstrapError} />
  }
  if (session.session) {
    return <Outlet />
  }
  const isPlatformRoute = location.pathname === '/platform' || location.pathname.startsWith('/platform/')
  return <Navigate to={isPlatformRoute ? '/platform/login' : '/login'} replace state={{ from: location, next: postAuthDestination() }} />
}

export function PinUnlockedRoute() {
  const session = useSessionStore()
  const location = useLocation()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (session.bootstrapState === 'ERROR') {
    return <FullScreenBootstrapError message={session.bootstrapError} />
  }
  if (!session.session) {
    return <Navigate to="/login" replace />
  }
  if (session.lockState.isLocked) {
    const postAuthDestination = location.pathname.startsWith('/platform') ? location.pathname : null
    return <Navigate to="/setup-pin" replace state={postAuthDestination ? { postAuthDestination } : undefined} />
  }
  return <Outlet />
}

export function TenantRoute() {
  const session = useSessionStore()
  if (session.bootstrapState === 'ERROR') {
    return <FullScreenBootstrapError message={session.bootstrapError} />
  }
  const redirectTarget = getTenantRouteRedirect(
    session.userContext,
    session.selectedTenantId,
    !session.selectedTenantContext || session.selectedTenantContext.accessState === 'BLOCKED',
  )
  if (redirectTarget) {
    return <Navigate to={redirectTarget} replace />
  }
  return <Outlet />
}

export function PlatformGuard() {
  const session = useSessionStore()
  const location = useLocation()
  if (session.bootstrapState === 'ERROR') {
    return <FullScreenBootstrapError message={session.bootstrapError} />
  }
  const denialReason = getPlatformRouteDenialReason(session.userContext)
  const redirectTarget = getPlatformRouteRedirect(session.userContext)
  if (import.meta.env.DEV) {
    console.info('Ahadi platform access diagnostic', buildPlatformAccessDiagnostic({
      authenticated: Boolean(session.session),
      lockState: session.lockState,
      context: session.userContext,
      attemptedRoute: location.pathname,
      redirectTarget,
    }))
  }
  if (redirectTarget) {
    return (
      <PageContainer narrow>
        <ErrorState title="Platform access is not enabled" message={platformAccessMessage(denialReason)} />
      </PageContainer>
    )
  }
  return <Outlet />
}

export function OnboardingRoute() {
  const session = useSessionStore()
  const location = useLocation()
  const normalizedPath = location.pathname.replace(/\/+$/, '')
  const isAdditionalOrganizationFlow = normalizedPath === '/organizations/new'
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (session.bootstrapState === 'ERROR') {
    return <FullScreenBootstrapError message={session.bootstrapError} />
  }
  if (!session.session) {
    return <Navigate to="/login" replace state={{ from: location }} />
  }
  if (session.lockState.isLocked) {
    return <Navigate to="/setup-pin" replace state={{ postAuthDestination: normalizedPath || location.pathname }} />
  }
  if (!isAdditionalOrganizationFlow && hasActivePlatformRole(session.userContext)) {
    return <Navigate to="/platform" replace />
  }
  const hasAccessibleTenant = Boolean(session.userContext?.tenantMemberships.some(isAccessibleTenantMembership))
  return !isAdditionalOrganizationFlow && session.userContext?.onboardingCompleted && hasAccessibleTenant ? <Navigate to="/select-tenant" replace /> : <Outlet />
}
