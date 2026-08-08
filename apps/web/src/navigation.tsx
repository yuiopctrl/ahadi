import {
  CalendarDays,
  Clock3,
  CreditCard,
  FileText,
  Gauge,
  Home,
  Menu,
  MessageSquareText,
  PieChart,
  Settings,
  Share2,
  ShieldCheck,
  Users,
  X,
} from 'lucide-react'
import { Link, NavLink } from 'react-router-dom'
import { useMemo, useState } from 'react'
import { EventContextDisplay, TenantSwitcherDisplay } from './components/ui'
import type { EventSummary, TenantMembershipContext } from '@ahadi/types'

const mobileNav = [
  { to: '/app', label: 'Home', icon: Home, end: true },
  { to: '/app/events', label: 'Events', icon: CalendarDays, end: true },
  { to: '/app/members', label: 'Members', icon: Users },
  { to: '/app/payments', label: 'Payments', icon: CreditCard },
]

function overflowNav(event: EventSummary | null, showPlatformLink = false) {
  const eventBase = event ? `/app/events/${event.id}` : '/app/events'
  return [
    ...(showPlatformLink ? [{ to: '/platform', label: 'Platform Console', icon: ShieldCheck }] : []),
    { to: event ? `${eventBase}/pledges` : '/app/events', label: 'Pledges', icon: PieChart },
    { to: event ? `${eventBase}/outstanding` : '/app/events', label: 'Outstanding', icon: Clock3 },
    { to: event ? `${eventBase}/share` : '/app/events', label: 'Share List', icon: Share2 },
    { to: '/app/messages', label: 'Messages', icon: MessageSquareText },
    { to: event ? `${eventBase}/reports` : '/app/reports', label: 'Reports', icon: FileText },
    { to: '/app/users', label: 'Users', icon: Users },
    { to: '/app/settings', label: 'Settings', icon: Settings },
  ]
}

function desktopNav(event: EventSummary | null) {
  const eventBase = event ? `/app/events/${event.id}` : '/app/events'
  return [
    { to: '/app', label: 'Dashboard', icon: Gauge, end: true },
    { to: '/app/events', label: 'Events', icon: CalendarDays, end: true },
    { to: event ? `${eventBase}/members` : '/app/members', label: 'Members', icon: Users },
    { to: event ? `${eventBase}/pledges` : '/app/events', label: 'Pledges', icon: PieChart },
    { to: event ? `${eventBase}/outstanding` : '/app/events', label: 'Outstanding', icon: Clock3 },
    { to: event ? `${eventBase}/share` : '/app/events', label: 'Share List', icon: Share2 },
    { to: event ? `${eventBase}/payments` : '/app/payments', label: 'Payments', icon: CreditCard },
    { to: '/app/messages', label: 'Messages', icon: MessageSquareText },
    { to: '/app/reports', label: 'Reports', icon: PieChart },
    { to: '/app/users', label: 'Users', icon: Users },
    { to: '/app/settings', label: 'Settings', icon: Settings },
  ]
}

export function MobileTopBar({ tenant, event, showPlatformLink = false }: { tenant: TenantMembershipContext | null; event: EventSummary | null; showPlatformLink?: boolean }) {
  return (
    <header className="mobile-topbar">
      <TenantSwitcherDisplay tenant={tenant} />
      <EventContextDisplay event={event} />
      {showPlatformLink ? (
        <Link className="topbar-icon-link" to="/platform" aria-label="Open Platform Console">
          <ShieldCheck size={18} aria-hidden />
        </Link>
      ) : null}
    </header>
  )
}

export function MobileBottomNav({ event, showPlatformLink = false }: { event: EventSummary | null; showPlatformLink?: boolean }) {
  const [open, setOpen] = useState(false)
  const overflowItems = useMemo(() => overflowNav(event, showPlatformLink), [event, showPlatformLink])

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
        {mobileNav.map(({ to, label, icon: Icon, end }) => (
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

export function DesktopSidebar({ tenant, event, showPlatformLink = false }: { tenant: TenantMembershipContext | null; event: EventSummary | null; showPlatformLink?: boolean }) {
  return (
    <aside className="desktop-sidebar">
      <div className="sidebar-brand">
        <span className="brand-mark">A</span>
        <div>
          <strong>Ahadi</strong>
          <small>Pledge collections</small>
        </div>
      </div>
      <TenantSwitcherDisplay tenant={tenant} />
      <EventContextDisplay event={event} />
      <nav aria-label="Tenant navigation">
        {showPlatformLink ? (
          <NavLink to="/platform">
            <ShieldCheck size={18} aria-hidden />
            Platform Console
          </NavLink>
        ) : null}
        {desktopNav(event).map(({ to, label, icon: Icon, end }) => (
          <NavLink key={label} to={to} end={end}>
            <Icon size={18} aria-hidden />
            {label}
          </NavLink>
        ))}
      </nav>
    </aside>
  )
}
