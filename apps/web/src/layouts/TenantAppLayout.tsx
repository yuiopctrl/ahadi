import { useEffect } from 'react'
import { CalendarDays, CheckCircle2, Clock3, Target } from 'lucide-react'
import { Link, Outlet, useLocation, useMatch, useNavigate } from 'react-router-dom'
import { MobileBottomNav, MobileTopBar, DesktopSidebar } from '../navigation'
import { useSessionStore } from '../stores/session-store'
import { hasActivePlatformAccess } from '../routes/access'
import type { EventSummary } from '@ahadi/types'

function eventDate(value: string | null | undefined) {
  if (!value) return 'Not set'
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(value))
}

function moneyText(value: number | null | undefined) {
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(value ?? 0)
}

function EventSnapshotBar({ event }: { event: EventSummary | null }) {
  if (!event) return null
  const eventBase = `/app/events/${event.id}`

  return (
    <section className="event-snapshot-bar" aria-label="Active event snapshot">
      <div className="event-snapshot-main">
        <span className="event-snapshot-kicker">Current Event</span>
        <strong>{event.name}</strong>
        <span>{event.eventType.replaceAll('_', ' ')} · {event.code}</span>
      </div>
      <div className="event-snapshot-metrics">
        <span><CalendarDays size={16} aria-hidden /><small>Date</small><strong>{eventDate(event.eventDate)}</strong></span>
        <span><Clock3 size={16} aria-hidden /><small>Deadline</small><strong>{eventDate(event.pledgeDeadline)}</strong></span>
        <span><Target size={16} aria-hidden /><small>Target</small><strong>{moneyText(event.targetAmount)}</strong></span>
        <span><CheckCircle2 size={16} aria-hidden /><small>Status</small><strong>{event.status}</strong></span>
      </div>
      <div className="event-snapshot-actions">
        <Link to={eventBase}>Dashboard</Link>
        <Link to={`${eventBase}/members`}>Members</Link>
        <Link to={`${eventBase}/reports`}>Reports</Link>
      </div>
    </section>
  )
}

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

  return (
    <div className="tenant-layout">
      <MobileTopBar tenant={tenant} event={event} showPlatformLink={hasActivePlatformAccess(session.userContext)} />
      <DesktopSidebar tenant={tenant} event={event} events={events} onEventChange={handleEventChange} showPlatformLink={hasActivePlatformAccess(session.userContext)} />
      <div className="tenant-content-shell">
        <EventSnapshotBar event={event} />
        <Outlet />
      </div>
      <MobileBottomNav event={event} showPlatformLink={hasActivePlatformAccess(session.userContext)} />
    </div>
  )
}
