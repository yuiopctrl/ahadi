import {
  CalendarDays,
  Clock3,
  CreditCard,
  Gauge,
  Home,
  Menu,
  MessageSquareText,
  PieChart,
  Settings,
  ShieldCheck,
  Users,
} from 'lucide-react'
import { Link, NavLink } from 'react-router-dom'
import { EventContextDisplay, TenantSwitcherDisplay } from './components/ui'
import type { EventSummary, TenantMembershipContext } from '@ahadi/types'

const mobileNav = [
  { to: '/app', label: 'Home', icon: Home, end: true },
  { to: '/app/events', label: 'Events', icon: CalendarDays },
  { to: '/app/members', label: 'Members', icon: Users },
  { to: '/app/payments', label: 'Payments', icon: CreditCard },
  { to: '/app/settings', label: 'More', icon: Menu },
]

function desktopNav(event: EventSummary | null) {
  const eventBase = event ? `/app/events/${event.id}` : '/app/events'
  return [
    { to: '/app', label: 'Dashboard', icon: Gauge, end: true },
    { to: '/app/events', label: 'Events', icon: CalendarDays },
    { to: event ? `${eventBase}/members` : '/app/members', label: 'Members', icon: Users },
    { to: event ? `${eventBase}/pledges` : '/app/events', label: 'Pledges', icon: PieChart },
    { to: event ? `${eventBase}/outstanding` : '/app/events', label: 'Outstanding', icon: Clock3 },
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

export function MobileBottomNav() {
  return (
    <nav className="mobile-bottom-nav" aria-label="Tenant mobile navigation">
      {mobileNav.map(({ to, label, icon: Icon, end }) => (
        <NavLink key={label} to={to} end={end}>
          <Icon size={20} aria-hidden />
          <span>{label}</span>
        </NavLink>
      ))}
    </nav>
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
