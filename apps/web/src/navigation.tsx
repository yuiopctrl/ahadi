import {
  CalendarDays,
  CreditCard,
  Gauge,
  Home,
  Menu,
  MessageSquareText,
  PieChart,
  Settings,
  Users,
} from 'lucide-react'
import { NavLink } from 'react-router-dom'
import { EventContextDisplay, TenantSwitcherDisplay } from './components/ui'
import type { EventSummary, TenantSummary } from './types/auth'

const mobileNav = [
  { to: '/app', label: 'Home', icon: Home, end: true },
  { to: '/app/events', label: 'Events', icon: CalendarDays },
  { to: '/app/members', label: 'Members', icon: Users },
  { to: '/app/payments', label: 'Payments', icon: CreditCard },
  { to: '/app/settings', label: 'More', icon: Menu },
]

const desktopNav = [
  { to: '/app', label: 'Dashboard', icon: Gauge, end: true },
  { to: '/app/events', label: 'Events', icon: CalendarDays },
  { to: '/app/members', label: 'Members', icon: Users },
  { to: '/app/events/event_001/pledges', label: 'Pledges', icon: PieChart },
  { to: '/app/payments', label: 'Payments', icon: CreditCard },
  { to: '/app/messages', label: 'Messages', icon: MessageSquareText },
  { to: '/app/reports', label: 'Reports', icon: PieChart },
  { to: '/app/settings', label: 'Users', icon: Users },
  { to: '/app/settings', label: 'Settings', icon: Settings },
]

export function MobileTopBar({ tenant, event }: { tenant: TenantSummary | null; event: EventSummary | null }) {
  return (
    <header className="mobile-topbar">
      <TenantSwitcherDisplay tenant={tenant} />
      <EventContextDisplay event={event} />
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

export function DesktopSidebar({ tenant, event }: { tenant: TenantSummary | null; event: EventSummary | null }) {
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
        {desktopNav.map(({ to, label, icon: Icon, end }) => (
          <NavLink key={label} to={to} end={end}>
            <Icon size={18} aria-hidden />
            {label}
          </NavLink>
        ))}
      </nav>
    </aside>
  )
}
