import { SUBSCRIPTION_READ_ONLY_GRACE_DAYS } from '@ahadi/config'
import type { SubscriptionSummary, TenantAccessState, TenantStatus } from '@ahadi/types'

export function calculateTenantAccessState(
  tenantStatus: TenantStatus,
  subscription: SubscriptionSummary | null,
  now = new Date(),
): TenantAccessState {
  if (['SUSPENDED', 'CANCELLED', 'ARCHIVED'].includes(tenantStatus)) {
    return 'BLOCKED'
  }

  if (tenantStatus === 'TRIAL' && subscription?.status === 'TRIAL') {
    if (!subscription.trialEndsAt || new Date(subscription.trialEndsAt) >= now) {
      return 'TRIAL'
    }
  }

  if (tenantStatus === 'ACTIVE' && subscription?.status === 'ACTIVE') {
    if (!subscription.currentPeriodEnd || new Date(subscription.currentPeriodEnd) >= now) {
      return 'ACTIVE'
    }
  }

  const expiry = subscription?.currentPeriodEnd ?? subscription?.trialEndsAt
  if (expiry) {
    const readOnlyUntil = new Date(expiry)
    readOnlyUntil.setDate(readOnlyUntil.getDate() + SUBSCRIPTION_READ_ONLY_GRACE_DAYS)
    if (readOnlyUntil >= now) {
      return 'READ_ONLY'
    }
  }

  return 'BLOCKED'
}
