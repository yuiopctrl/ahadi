import { CalendarDays, CheckCircle2, Clock3, LogOut, Menu, Settings, ShieldCheck, Target, User } from 'lucide-react'
import { useState } from 'react'
import { Link, NavLink } from 'react-router-dom'
import type { EventSummary, TenantMembershipContext, UserContext } from '@ahadi/types'
import { TenantSwitcherDisplay } from './ui'

function eventDate(value: string | null | undefined) {
  if (!value) return 'Not set'
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(value))
}

function moneyText(value: number | null | undefined) {
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(value ?? 0)
}

function initialsFor(context: UserContext | null) {
  const name = context?.profile?.fullName?.trim()
  if (name) {
    const initials = name.split(/\s+/).map((part) => part[0]).join('').slice(0, 2)
    return initials.toUpperCase()
  }
  return 'A'
}

function displayNameFor(context: UserContext | null) {
  return context?.profile?.fullName?.trim() || context?.profile?.phoneE164 || 'Ahadi user'
}

function roleFor(context: UserContext | null, tenant: TenantMembershipContext | null) {
  return context?.platformRole ?? tenant?.roles[0] ?? 'Member'
}

function EventMetadata({ event }: { event: EventSummary | null }) {
  return (
    <div className="unified-header-metrics" aria-label="Current event details">
      <span><CalendarDays size={15} aria-hidden /><small>Date</small><strong>{eventDate(event?.eventDate)}</strong></span>
      <span><Clock3 size={15} aria-hidden /><small>Deadline</small><strong>{eventDate(event?.pledgeDeadline)}</strong></span>
      <span><Target size={15} aria-hidden /><small>Target</small><strong>{moneyText(event?.targetAmount)}</strong></span>
      <span><CheckCircle2 size={15} aria-hidden /><small>Status</small><strong>{event?.status ?? 'Not set'}</strong></span>
    </div>
  )
}

function EventNavigation({ event, compact = false }: { event: EventSummary | null; compact?: boolean }) {
  if (!event) return null
  const eventBase = `/app/events/${event.id}`
  return (
    <nav className={compact ? 'unified-header-event-nav compact' : 'unified-header-event-nav'} aria-label="Current event navigation">
      <NavLink to={eventBase} end>Dashboard</NavLink>
      <NavLink to={`${eventBase}/members`}>Members</NavLink>
      <NavLink to={`${eventBase}/reports`}>Reports</NavLink>
    </nav>
  )
}

export function UnifiedTenantHeader({
  tenant,
  memberships,
  selectedTenantId,
  event,
  userContext,
  showPlatformLink,
  onTenantChange,
  onCreateTenant,
  onLogout,
}: {
  tenant: TenantMembershipContext | null
  memberships: TenantMembershipContext[]
  selectedTenantId: string | null
  event: EventSummary | null
  userContext: UserContext | null
  showPlatformLink: boolean
  onTenantChange: (tenantId: string) => void
  onCreateTenant: () => void
  onLogout: () => void
}) {
  const [accountOpen, setAccountOpen] = useState(false)
  const [eventDetailsOpen, setEventDetailsOpen] = useState(false)
  const [eventNavOpen, setEventNavOpen] = useState(false)
  const name = displayNameFor(userContext)
  const role = roleFor(userContext, tenant)

  function closeMenus() {
    setAccountOpen(false)
    setEventDetailsOpen(false)
    setEventNavOpen(false)
  }

  return (
    <header className="unified-tenant-header" onKeyDown={(eventKey) => {
      if (eventKey.key === 'Escape') closeMenus()
    }}>
      <div className="unified-header-tenant">
        <TenantSwitcherDisplay tenant={tenant} memberships={memberships} selectedTenantId={selectedTenantId} onSelect={onTenantChange} onCreate={onCreateTenant} />
      </div>

      <div className="unified-header-event">
        <div className="unified-header-event-title">
          <span>Current Event</span>
          <strong>{event?.name ?? 'No active event'}</strong>
          <small>{event ? `${event.eventType.replaceAll('_', ' ')} · ${event.code}` : 'Select or create an event'}</small>
        </div>
        <EventMetadata event={event} />
        <button className="unified-header-details-button" type="button" aria-expanded={eventDetailsOpen} onClick={() => setEventDetailsOpen((value) => !value)}>
          Details
        </button>
      </div>

      <div className="unified-header-actions">
        <EventNavigation event={event} />
        {event ? (
          <div className="unified-header-event-menu">
            <button type="button" aria-label="Open event navigation" aria-expanded={eventNavOpen} onClick={() => setEventNavOpen((value) => !value)}>
              <Menu size={18} aria-hidden />
            </button>
            {eventNavOpen ? <EventNavigation event={event} compact /> : null}
          </div>
        ) : null}
        <div className="account-menu">
          <button className="account-menu-trigger" type="button" aria-label="Open account menu" aria-expanded={accountOpen} onClick={() => setAccountOpen((value) => !value)}>
            <span className="account-avatar">{initialsFor(userContext)}</span>
            <span className="account-copy">
              <strong>{name}</strong>
              <small>{role}</small>
            </span>
          </button>
          {accountOpen ? (
            <>
              <button className="account-menu-backdrop" type="button" aria-label="Close account menu" onClick={() => setAccountOpen(false)} />
              <div className="account-menu-popover" role="menu" aria-label="Account">
                <Link to="/app/settings" role="menuitem" onClick={() => setAccountOpen(false)}><User size={17} aria-hidden /> My Profile</Link>
                <Link to="/app/settings" role="menuitem" onClick={() => setAccountOpen(false)}><Settings size={17} aria-hidden /> Account Settings</Link>
                {showPlatformLink ? <Link to="/platform" role="menuitem" onClick={() => setAccountOpen(false)}><ShieldCheck size={17} aria-hidden /> Platform Console</Link> : null}
                <button type="button" role="menuitem" onClick={() => {
                  setAccountOpen(false)
                  onLogout()
                }}>
                  <LogOut size={17} aria-hidden />
                  Logout
                </button>
              </div>
            </>
          ) : null}
        </div>
      </div>

      {eventDetailsOpen ? (
        <div className="unified-header-mobile-details">
          <EventMetadata event={event} />
        </div>
      ) : null}
    </header>
  )
}
