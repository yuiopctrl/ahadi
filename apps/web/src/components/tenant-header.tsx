import { CalendarDays, CheckCircle2, Clock3, KeyRound, LogOut, Target, User } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import type { User as SupabaseUser } from '@supabase/supabase-js'
import type { EventSummary, TenantMembershipContext, UserContext } from '@ahadi/types'
import { TenantSwitcherDisplay } from './ui'

function eventDate(value: string | null | undefined) {
  if (!value) return 'Not set'
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(value))
}

function moneyText(value: number | null | undefined) {
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(value ?? 0)
}

function metadataName(user: SupabaseUser | null, key: string) {
  const value = user?.user_metadata?.[key] ?? user?.app_metadata?.[key]
  return typeof value === 'string' ? value.trim() : ''
}

function resolveDisplayName(context: UserContext | null, user: SupabaseUser | null) {
  const fullName = context?.profile?.fullName?.trim() || metadataName(user, 'full_name')
  const displayName = metadataName(user, 'display_name') || metadataName(user, 'displayName') || metadataName(user, 'name')
  return fullName || displayName || context?.profile?.email || user?.email || context?.profile?.phoneE164 || user?.phone || 'User'
}

function initialsFor(name: string) {
  const parts = name.match(/[A-Za-z0-9]+/g) ?? []
  const first = parts[0] ?? ''
  const second = parts[1] ?? ''
  const initials = second ? `${first[0] ?? ''}${second[0] ?? ''}` : first.slice(0, 2)
  return (initials || 'U').toUpperCase()
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

export function UnifiedTenantHeader({
  tenant,
  memberships,
  selectedTenantId,
  event,
  userContext,
  sessionUser,
  onTenantChange,
  onCreateTenant,
  onLogout,
}: {
  tenant: TenantMembershipContext | null
  memberships: TenantMembershipContext[]
  selectedTenantId: string | null
  event: EventSummary | null
  userContext: UserContext | null
  sessionUser: SupabaseUser | null
  onTenantChange: (tenantId: string) => void
  onCreateTenant: () => void
  onLogout: () => void
}) {
  const [accountOpen, setAccountOpen] = useState(false)
  const [eventDetailsOpen, setEventDetailsOpen] = useState(false)
  const name = resolveDisplayName(userContext, sessionUser)

  function closeMenus() {
    setAccountOpen(false)
    setEventDetailsOpen(false)
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
        <div className="account-menu">
          <button className="account-menu-trigger" type="button" aria-label="Open account menu" aria-expanded={accountOpen} onClick={() => setAccountOpen((value) => !value)}>
            <span className="account-avatar">{initialsFor(name)}</span>
            <span className="account-copy">
              <strong>{name}</strong>
            </span>
          </button>
          {accountOpen ? (
            <>
              <button className="account-menu-backdrop" type="button" aria-label="Close account menu" onClick={() => setAccountOpen(false)} />
              <div className="account-menu-popover" role="menu" aria-label="Account">
                <Link to="/app/settings" role="menuitem" onClick={() => setAccountOpen(false)}><User size={17} aria-hidden /> My Profile</Link>
                <Link to="/app/change-pin" role="menuitem" onClick={() => setAccountOpen(false)}><KeyRound size={17} aria-hidden /> Change PIN</Link>
                <button type="button" role="menuitem" onClick={() => {
                  setAccountOpen(false)
                  onLogout()
                }}>
                  <LogOut size={17} aria-hidden />
                  Sign Out
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
