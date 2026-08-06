import type { TenantMembershipContext, UserContext } from '@ahadi/types'

export function getSingleActiveMembership(context: UserContext | null): TenantMembershipContext | null {
  const active = context?.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE') ?? []
  return active.length === 1 ? active[0] ?? null : null
}
