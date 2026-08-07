import {
  Building2,
  ClipboardList,
  Gauge,
  MessageSquareText,
  Package,
  Receipt,
  Settings,
} from 'lucide-react'
import { NavLink, Outlet } from 'react-router-dom'
import { useSessionStore } from '../stores/session-store'

const platformNav = [
  { to: '/platform', label: 'Overview', icon: Gauge, end: true },
  { to: '/platform/tenants', label: 'Tenants', icon: Building2 },
  { to: '/platform/plans', label: 'Packages', icon: Package },
  { to: '/platform/subscriptions', label: 'Subscriptions', icon: Receipt },
  { to: '/platform/sms', label: 'SMS', icon: MessageSquareText },
  { to: '/platform/audit', label: 'Audit Logs', icon: ClipboardList },
  { to: '/platform/settings', label: 'System Settings', icon: Settings },
]

export function PlatformAppLayout() {
  const session = useSessionStore()
  const canOpenTenantApp = Boolean(session.selectedTenantId || session.userContext?.tenantMemberships.length)

  return (
    <div className="platform-layout">
      <aside className="platform-sidebar">
        <div className="platform-brand">
          <span className="brand-mark">A</span>
          <div>
            <strong>Ahadi Platform</strong>
            <small>Owner console</small>
          </div>
        </div>
        <nav aria-label="Platform navigation">
          {canOpenTenantApp ? (
            <NavLink to={session.selectedTenantId ? '/app' : '/select-tenant'}>
              <Gauge size={18} aria-hidden />
              Tenant App
            </NavLink>
          ) : null}
          {platformNav.map(({ to, label, icon: Icon, end }) => (
            <NavLink key={label} to={to} end={end}>
              <Icon size={18} aria-hidden />
              {label}
            </NavLink>
          ))}
        </nav>
      </aside>
      <main className="platform-main">
        <Outlet />
      </main>
    </div>
  )
}
