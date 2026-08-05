import { useMemo } from 'react'
import type { SessionState, SessionStore } from '../types/auth'

const mockSession: SessionState = {
  status: 'authenticated',
  user: {
    id: 'user_001',
    phone: '+255 712 345 678',
    name: 'Asha Mrema',
    role: 'tenant_admin',
    tenantId: 'tenant_001',
    onboardingComplete: true,
  },
  tenant: {
    id: 'tenant_001',
    name: 'Mrema Family Committee',
    planName: 'Community',
  },
  activeEvent: {
    id: 'event_001',
    name: 'Neema & Baraka Wedding',
    type: 'wedding',
  },
}

export function useSessionStore(): SessionStore {
  return useMemo(
    () => ({
      ...mockSession,
      isAuthenticated: mockSession.status === 'authenticated',
      isPlatformOwner: mockSession.user?.role === 'platform_owner',
      hasTenantAccess: Boolean(mockSession.user?.tenantId),
    }),
    [],
  )
}
