import {
  CalendarDays,
  Clock3,
  CreditCard,
  FileText,
  Gauge,
  History,
  Home,
  KeyRound,
  LifeBuoy,
  Menu,
  MessageSquareText,
  PieChart,
  Settings,
  Share2,
  ShieldCheck,
  Users,
  X,
} from 'lucide-react'
import { NavLink } from 'react-router-dom'
import { useMemo, useState } from 'react'
import { EventContextDisplay } from './components/ui'
import type { EventSummary } from '@ahadi/types'
import { useSessionStore } from './stores/session-store'

function mobileNav(event: EventSummary | null) {
  const eventBase = event ? `/app/events/${event.id}` : '/app/events'
  return [
    { to: event ? eventBase : '/app', label: 'Home', icon: Home, end: true },
    { to: '/app/events', label: 'Events', icon: CalendarDays, end: true },
    { to: '/app/contacts', label: 'Contacts', icon: Users },
    { to: event ? `${eventBase}/payments` : '/app/payments', label: 'Payments', icon: CreditCard },
  ]
}

function overflowNav(event: EventSummary | null, showPlatformLink = false, canManageUsers = false, canViewActivity = false) {
  const eventBase = event ? `/app/events/${event.id}` : '/app/events'
  return [
    ...(showPlatformLink ? [{ to: '/platform', label: 'Platform Console', icon: ShieldCheck }] : []),
    { to: event ? `${eventBase}/pledges` : '/app/events', label: 'Pledges', icon: PieChart },
    { to: event ? `${eventBase}/outstanding` : '/app/events', label: 'Outstanding', icon: Clock3 },
    { to: event ? `${eventBase}/share` : '/app/events', label: 'Share List', icon: Share2 },
    { to: event ? `/app/messages?eventId=${event.id}` : '/app/messages', label: 'Messages', icon: MessageSquareText },
    { to: event ? `${eventBase}/reports` : '/app/reports', label: 'Reports', icon: FileText },
    ...(canViewActivity ? [{ to: '/app/activity', label: 'Activity', icon: History }] : []),
    { to: '/app/settings/billing', label: 'Billing', icon: CreditCard },
    ...(canManageUsers ? [{ to: '/app/users', label: 'Users & Roles', icon: Users }] : []),
    { to: '/app/change-pin', label: 'Change PIN', icon: KeyRound },
    { to: '/app/help', label: 'Help', icon: LifeBuoy },
    { to: '/app/settings', label: 'Settings', icon: Settings },
  ]
}

function desktopNav(event: EventSummary | null, canManageUsers = false, canViewActivity = false) {
  const eventBase = event ? `/app/events/${event.id}` : '/app/events'
  return [
    { to: event ? eventBase : '/app', label: 'Dashboard', icon: Gauge, end: true },
    { to: '/app/events', label: 'Events', icon: CalendarDays, end: true },
    { to: '/app/contacts', label: 'Contacts', icon: Users },
    ...(event ? [{ to: `${eventBase}/members`, label: 'Members', icon: Users }] : []),
    { to: event ? `${eventBase}/pledges` : '/app/events', label: 'Pledges', icon: PieChart },
    { to: event ? `${eventBase}/outstanding` : '/app/events', label: 'Outstanding', icon: Clock3 },
    { to: event ? `${eventBase}/share` : '/app/events', label: 'Share List', icon: Share2 },
    { to: event ? `${eventBase}/payments` : '/app/payments', label: 'Payments', icon: CreditCard },
    { to: event ? `/app/messages?eventId=${event.id}` : '/app/messages', label: 'Messages', icon: MessageSquareText },
    { to: event ? `${eventBase}/reports` : '/app/reports', label: 'Reports', icon: PieChart },
    ...(canViewActivity ? [{ to: '/app/activity', label: 'Activity', icon: History }] : []),
    { to: '/app/settings/billing', label: 'Billing', icon: CreditCard },
    ...(canManageUsers ? [{ to: '/app/users', label: 'Users & Roles', icon: Users }] : []),
    { to: '/app/change-pin', label: 'Change PIN', icon: KeyRound },
    { to: '/app/help', label: 'Help', icon: LifeBuoy },
    { to: '/app/settings', label: 'Settings', icon: Settings },
  ]
}

interface TenantNavProps {
  event: EventSummary | null
  events?: EventSummary[]
  showPlatformLink?: boolean
  onEventChange?: (eventId: string) => void
}

export function MobileBottomNav({ event, showPlatformLink = false }: { event: EventSummary | null; showPlatformLink?: boolean }) {
  const [open, setOpen] = useState(false)
  const session = useSessionStore()
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const canManageUsers = permissions.has('users.invite') || permissions.has('users.manage_roles') || permissions.has('users.suspend')
  const canViewActivity = permissions.has('audit.view') || Boolean(session.selectedTenantContext?.membership?.isOwner)
  const primaryItems = useMemo(() => mobileNav(event), [event])
  const overflowItems = useMemo(() => overflowNav(event, showPlatformLink, canManageUsers, canViewActivity), [canManageUsers, canViewActivity, event, showPlatformLink])

  return (
    <>
      {open ? <button className="mobile-more-backdrop" type="button" aria-label="Close menu" onClick={() => setOpen(false)} /> : null}
      {open ? (
        <section id="mobile-more-menu" className="mobile-more-menu" aria-label="More navigation">
          <div className="mobile-more-header">
            <strong>More</strong>
            <button type="button" aria-label="Close menu" onClick={() => setOpen(false)}><X size={18} aria-hidden /></button>
          </div>
          <div className="mobile-more-grid">
            {overflowItems.map(({ to, label, icon: Icon }) => (
              <NavLink key={label} to={to} onClick={() => setOpen(false)}>
                <Icon size={19} aria-hidden />
                <span>{label}</span>
              </NavLink>
            ))}
          </div>
        </section>
      ) : null}
      <nav className="mobile-bottom-nav" aria-label="Tenant mobile navigation">
        {primaryItems.map(({ to, label, icon: Icon, end }) => (
          <NavLink key={label} to={to} end={end} onClick={() => setOpen(false)}>
            <Icon size={20} aria-hidden />
            <span>{label}</span>
          </NavLink>
        ))}
        <button className={open ? 'active' : ''} type="button" aria-expanded={open} aria-controls="mobile-more-menu" onClick={() => setOpen((value) => !value)}>
          <Menu size={20} aria-hidden />
          <span>More</span>
        </button>
      </nav>
    </>
  )
}

export function DesktopSidebar({ event, events = [], showPlatformLink = false, onEventChange }: TenantNavProps) {
  const session = useSessionStore()
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const canManageUsers = permissions.has('users.invite') || permissions.has('users.manage_roles') || permissions.has('users.suspend')
  const canViewActivity = permissions.has('audit.view') || Boolean(session.selectedTenantContext?.membership?.isOwner)
  const items = useMemo(() => desktopNav(event, canManageUsers, canViewActivity), [canManageUsers, canViewActivity, event])
  return (
    <aside className="desktop-sidebar">
      <div className="sidebar-brand">
        <img className="brand-icon" src="/brand/app_icon.png" alt="" aria-hidden="true" />
        <div>
          <img className="brand-wordmark" src="/brand/wordmark.png" alt="Changisha" />
          <small>Pledge collections</small>
        </div>
      </div>
      <EventContextDisplay event={event} events={events} onEventChange={onEventChange} />
      <nav aria-label="Tenant navigation">
        {showPlatformLink ? (
          <NavLink to="/platform">
            <ShieldCheck size={18} aria-hidden />
            Platform Console
          </NavLink>
        ) : null}
        {items.map(({ to, label, icon: Icon, end }) => (
          <NavLink key={label} to={to} end={end}>
            <Icon size={18} aria-hidden />
            {label}
          </NavLink>
        ))}
      </nav>
    </aside>
  )
}
