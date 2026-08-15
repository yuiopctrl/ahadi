import { useEffect } from 'react'
import { Outlet, useLocation, useMatch, useNavigate } from 'react-router-dom'
import { MobileBottomNav, DesktopSidebar } from '../navigation'
import { useSessionStore } from '../stores/session-store'
import { hasActivePlatformAccess } from '../routes/access'
import { UnifiedTenantHeader } from '../components/tenant-header'

export function TenantAppLayout() {
  const session = useSessionStore()
  const { selectedEventId, selectEvent } = session
  const location = useLocation()
  const navigate = useNavigate()
  const nestedEventRouteMatch = useMatch('/app/events/:eventId/*')
  const eventDetailRouteMatch = useMatch('/app/events/:eventId')
  const eventRouteMatch = nestedEventRouteMatch ?? eventDetailRouteMatch
  const routeEventId = eventRouteMatch?.params.eventId
  const tenant = session.userContext?.tenantMemberships.find((membership) => membership.tenantId === session.selectedTenantId) ?? null
  const memberships = session.userContext?.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE' && (membership.tenantStatus === 'ACTIVE' || membership.tenantStatus === 'TRIAL')) ?? []
  const pendingInvitations = session.userContext?.pendingInvitations ?? []
  const events = session.selectedTenantContext?.events ?? tenant?.accessibleEvents ?? []
  const fallbackEvent = events[0] ?? null
  const storedEvent = selectedEventId ? events.find((candidate) => candidate.id === selectedEventId) ?? null : null
  const routeEvent = routeEventId ? events.find((candidate) => candidate.id === routeEventId) ?? null : null
  const event = routeEvent ?? storedEvent ?? fallbackEvent

  useEffect(() => {
    if (routeEvent?.id && routeEvent.id !== selectedEventId) {
      selectEvent(routeEvent.id)
    }
  }, [routeEvent?.id, selectEvent, selectedEventId])

  function handleEventChange(eventId: string) {
    selectEvent(eventId)
    if (routeEventId) {
      navigate(`${location.pathname.replace(`/app/events/${routeEventId}`, `/app/events/${eventId}`)}${location.search}`, { replace: false })
      return
    }
    if (location.pathname === '/app/messages') {
      navigate(`/app/messages?eventId=${eventId}`, { replace: true })
    }
  }

  async function handleTenantChange(tenantId: string) {
    await session.selectTenant(tenantId)
    navigate('/app', { replace: false })
  }

  function handleCreateTenant() {
    navigate('/organizations/new')
  }

  async function handleLogout() {
    await session.signOut()
    navigate('/login', { replace: true })
  }

  return (
    <div className="tenant-layout">
      <DesktopSidebar event={event} events={events} onEventChange={handleEventChange} showPlatformLink={hasActivePlatformAccess(session.userContext)} />
      <div className="tenant-content-shell">
        <UnifiedTenantHeader
          tenant={tenant}
          memberships={memberships}
          selectedTenantId={session.selectedTenantId}
          event={event}
          userContext={session.userContext}
          sessionUser={session.session?.user ?? null}
          onTenantChange={(tenantId) => void handleTenantChange(tenantId)}
          onCreateTenant={handleCreateTenant}
          onLogout={() => void handleLogout()}
        />
        {pendingInvitations.length ? (
          <button className="notice-banner" type="button" onClick={() => navigate('/invitations')}>
            {pendingInvitations.length === 1
              ? `Invitation from ${pendingInvitations[0]?.tenantName ?? 'an organization'}`
              : `${pendingInvitations.length} organization invitations`}
          </button>
        ) : null}
        <Outlet />
      </div>
      <MobileBottomNav event={event} showPlatformLink={hasActivePlatformAccess(session.userContext)} />
    </div>
  )
}
