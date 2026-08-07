import { Outlet } from 'react-router-dom'
import { MobileBottomNav, MobileTopBar, DesktopSidebar } from '../navigation'
import { MobileActionBar } from '../components/ui'
import { useSessionStore } from '../stores/session-store'
import { hasActivePlatformAccess } from '../routes/access'

export function TenantAppLayout() {
  const session = useSessionStore()
  const tenant = session.userContext?.tenantMemberships.find((membership) => membership.tenantId === session.selectedTenantId) ?? null
  const event = session.selectedTenantContext?.events[0] ?? tenant?.accessibleEvents[0] ?? null

  return (
    <div className="tenant-layout">
      <MobileTopBar tenant={tenant} event={event} />
      <DesktopSidebar tenant={tenant} event={event} showPlatformLink={hasActivePlatformAccess(session.userContext)} />
      <div className="tenant-content-shell">
        <Outlet />
      </div>
      <MobileActionBar />
      <MobileBottomNav />
    </div>
  )
}
