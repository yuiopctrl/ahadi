import type { TenantMembershipContext, UserContext } from '@ahadi/types'

export function isAccessibleTenantMembership(membership: TenantMembershipContext): boolean {
  return membership.membershipStatus === 'ACTIVE' && (membership.tenantStatus === 'ACTIVE' || membership.tenantStatus === 'TRIAL')
}

export function getSingleActiveMembership(context: UserContext | null): TenantMembershipContext | null {
  const active = context?.tenantMemberships.filter(isAccessibleTenantMembership) ?? []
  return active.length === 1 ? active[0] ?? null : null
}
