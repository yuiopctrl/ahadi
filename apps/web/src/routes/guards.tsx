import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { LoadingState, PageContainer } from '../components/ui'
import { getSingleActiveMembership, useSessionStore } from '../stores/session-store'

function FullScreenLoading() {
  return (
    <PageContainer narrow>
      <LoadingState title="Restoring session" message="Checking your secure Ahadi session." />
    </PageContainer>
  )
}

function postAuthDestination() {
  return '/verify-otp'
}

export function PublicRoute() {
  const session = useSessionStore()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (!session.session) {
    return <Outlet />
  }
  if (session.lockState.isLocked) {
    return <Navigate to="/setup-pin" replace />
  }
  if (!session.userContext?.onboardingCompleted) {
    return <Navigate to="/onboarding" replace />
  }
  const singleTenant = getSingleActiveMembership(session.userContext)
  if (singleTenant) {
    return <Navigate to="/app" replace />
  }
  if (session.userContext?.tenantMemberships.length) {
    return <Navigate to="/select-tenant" replace />
  }
  return session.userContext?.isPlatformUser ? <Navigate to="/platform" replace /> : <Navigate to="/onboarding" replace />
}

export function AuthenticatedRoute() {
  const session = useSessionStore()
  const location = useLocation()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  return session.session ? <Outlet /> : <Navigate to="/login" replace state={{ from: location, next: postAuthDestination() }} />
}

export function PinUnlockedRoute() {
  const session = useSessionStore()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (!session.session) {
    return <Navigate to="/login" replace />
  }
  return session.lockState.isLocked ? <Navigate to="/setup-pin" replace /> : <Outlet />
}

export function TenantRoute() {
  const session = useSessionStore()
  if (!session.userContext?.onboardingCompleted) {
    return <Navigate to="/onboarding" replace />
  }
  if (!session.selectedTenantId) {
    return <Navigate to="/select-tenant" replace />
  }
  if (!session.selectedTenantContext || session.selectedTenantContext.accessState === 'BLOCKED') {
    return <Navigate to="/select-tenant" replace />
  }
  return <Outlet />
}

export function PlatformOwnerRoute() {
  const session = useSessionStore()
  if (!session.userContext?.isPlatformUser) {
    return <Navigate to="/app" replace />
  }
  return <Outlet />
}

export function OnboardingRoute() {
  const session = useSessionStore()
  if (session.isLoading) {
    return <FullScreenLoading />
  }
  if (!session.session) {
    return <Navigate to="/login" replace />
  }
  if (session.lockState.isLocked) {
    return <Navigate to="/setup-pin" replace />
  }
  return session.userContext?.onboardingCompleted ? <Navigate to="/select-tenant" replace /> : <Outlet />
}
