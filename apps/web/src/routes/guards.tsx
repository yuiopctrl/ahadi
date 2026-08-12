import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { ErrorState, LoadingState, PageContainer } from '../components/ui'
import { useSessionStore } from '../stores/session-store'
import { isAccessibleTenantMembership } from '../stores/session-selection'
import { buildPlatformAccessDiagnostic, getPlatformRouteRedirect, getTenantRouteRedirect, hasActivePlatformRole, resolveAuthenticatedDestination } from './access'

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
        <ErrorState title="Platform access is not enabled" message="This account does not have an ACTIVE platform_users row with platform.dashboard.view permission." />
      </PageContainer>
    )
  }
  return <Outlet />
}

export function OnboardingRoute() {
  const session = useSessionStore()
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
    return <Navigate to="/setup-pin" replace />
  }
  if (hasActivePlatformRole(session.userContext)) {
    return <Navigate to="/platform" replace />
  }
  const hasAccessibleTenant = Boolean(session.userContext?.tenantMemberships.some(isAccessibleTenantMembership))
  return session.userContext?.onboardingCompleted && hasAccessibleTenant ? <Navigate to="/select-tenant" replace /> : <Outlet />
}
