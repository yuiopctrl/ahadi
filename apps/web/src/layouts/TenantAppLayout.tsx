import { Outlet } from 'react-router-dom'
import { MobileBottomNav, MobileTopBar, DesktopSidebar } from '../navigation'
import { MobileActionBar } from '../components/ui'
import { useSessionStore } from '../stores/session-store'

export function TenantAppLayout() {
  const session = useSessionStore()

  return (
    <div className="tenant-layout">
      <MobileTopBar tenant={session.tenant} event={session.activeEvent} />
      <DesktopSidebar tenant={session.tenant} event={session.activeEvent} />
      <div className="tenant-content-shell">
        <Outlet />
      </div>
      <MobileActionBar />
      <MobileBottomNav />
    </div>
  )
}
