import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useSessionStore } from '../stores/session-store'

export function PublicRoute() {
  const session = useSessionStore()
  return session.isAuthenticated ? <Navigate to="/app" replace /> : <Outlet />
}

export function AuthenticatedRoute() {
  const session = useSessionStore()
  const location = useLocation()
  return session.isAuthenticated ? <Outlet /> : <Navigate to="/login" replace state={{ from: location }} />
}

export function TenantRoute() {
  const session = useSessionStore()
  if (!session.hasTenantAccess) {
    return <Navigate to="/onboarding" replace />
  }
  return <Outlet />
}

export function PlatformOwnerRoute() {
  const session = useSessionStore()
  return session.isPlatformOwner ? <Outlet /> : <Navigate to="/app" replace />
}

export function OnboardingRoute() {
  const session = useSessionStore()
  if (!session.isAuthenticated) {
    return <Navigate to="/login" replace />
  }
  return session.user?.onboardingComplete ? <Navigate to="/app" replace /> : <Outlet />
}
