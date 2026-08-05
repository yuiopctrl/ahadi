export type UserRole = 'tenant_admin' | 'collector' | 'member' | 'platform_owner'

export type SessionStatus = 'loading' | 'authenticated' | 'anonymous'

export interface AuthUser {
  id: string
  phone: string
  name: string
  role: UserRole
  tenantId?: string
  onboardingComplete: boolean
}

export interface TenantSummary {
  id: string
  name: string
  planName: string
}

export interface EventSummary {
  id: string
  name: string
  type: 'wedding' | 'sendoff' | 'funeral' | 'fundraiser' | 'community'
}

export interface SessionState {
  status: SessionStatus
  user: AuthUser | null
  tenant: TenantSummary | null
  activeEvent: EventSummary | null
}

export interface SessionStore extends SessionState {
  isAuthenticated: boolean
  isPlatformOwner: boolean
  hasTenantAccess: boolean
}
