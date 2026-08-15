export type BillingInterval = 'MONTHLY' | 'QUARTERLY' | 'YEARLY' | 'CUSTOM'
export type TenantStatus = 'TRIAL' | 'ACTIVE' | 'SUSPENDED' | 'EXPIRED' | 'CANCELLED' | 'ARCHIVED'
export type SubscriptionStatus = 'TRIAL' | 'ACTIVE' | 'PAST_DUE' | 'SUSPENDED' | 'CANCELLED' | 'EXPIRED'
export type TenantUserStatus = 'INVITED' | 'ACTIVE' | 'SUSPENDED' | 'REMOVED'
export type ProfileStatus = 'PENDING' | 'ACTIVE' | 'SUSPENDED' | 'DISABLED'
export type EventType = 'WEDDING' | 'SENDOFF' | 'FUNERAL' | 'FUNDRAISER' | 'BIRTHDAY' | 'GRADUATION' | 'RELIGIOUS' | 'OTHER'
export type EventStatus = 'DRAFT' | 'ACTIVE' | 'CLOSED' | 'CANCELLED' | 'ARCHIVED'
export type EventAccessLevel = 'VIEW' | 'COLLECT' | 'MANAGE'
export type PlatformRole = 'PLATFORM_OWNER' | 'PLATFORM_ADMIN' | 'PLATFORM_SUPPORT' | 'PLATFORM_AUDITOR'
export type PlatformUserStatus = 'ACTIVE' | 'SUSPENDED' | 'DISABLED'
export type TenantAccessState = 'ACTIVE' | 'TRIAL' | 'READ_ONLY' | 'BLOCKED'

export type ApiErrorCode =
  | 'INVALID_INPUT'
  | 'INVALID_PHONE'
  | 'OTP_REQUEST_FAILED'
  | 'INVALID_OTP'
  | 'SESSION_REQUIRED'
  | 'PIN_REQUIRED'
  | 'PIN_TOO_WEAK'
  | 'PIN_INVALID'
  | 'PIN_LOCKED'
  | 'AUTH_CONFIGURATION_REQUIRED'
  | 'TENANT_ACCESS_DENIED'
  | 'PLATFORM_ACCESS_DENIED'
  | 'PERMISSION_DENIED'
  | 'ONBOARDING_ALREADY_COMPLETED'
  | 'REGISTRATION_PAUSED'
  | 'INVITATION_REQUIRED'
  | 'INVITATION_INVALID'
  | 'INVITATION_ALREADY_PENDING'
  | 'FEATURE_DISABLED'
  | 'PLAN_NOT_AVAILABLE'
  | 'SUBSCRIPTION_INACTIVE'
  | 'USER_ALREADY_IN_TENANT'
  | 'USER_NOT_FOUND'
  | 'ROLE_NOT_FOUND'
  | 'LAST_OWNER_REQUIRED'
  | 'OWNER_ROLE_REQUIRES_OWNER'
  | 'MEMBER_NOT_FOUND'
  | 'MEMBER_PHONE_ALREADY_EXISTS'
  | 'MEMBER_ALREADY_IN_EVENT'
  | 'EVENT_MEMBER_NOT_FOUND'
  | 'EVENT_MEMBER_REMOVED'
  | 'CATEGORY_NOT_FOUND'
  | 'PLEDGE_NOT_FOUND'
  | 'PLEDGE_ALREADY_EXISTS'
  | 'PLEDGE_AMOUNT_INVALID'
  | 'PLEDGE_BELOW_PAID_AMOUNT'
  | 'PLEDGE_CANCELLED'
  | 'PLEDGE_REQUIRED_FOR_PAYMENT'
  | 'PAYMENT_NOT_FOUND'
  | 'PAYMENT_AMOUNT_INVALID'
  | 'PAYMENT_REFERENCE_DUPLICATE'
  | 'PAYMENT_ALREADY_REVERSED'
  | 'PAYMENT_REVERSAL_REASON_REQUIRED'
  | 'PAYMENT_IDEMPOTENCY_CONFLICT'
  | 'EVENT_NOT_ACTIVE'
  | 'EVENT_ACCESS_DENIED'
  | 'EVENT_LIMIT_REACHED'
  | 'INVALID_EVENT_TYPE'
  | 'INVALID_EVENT_DATE'
  | 'INVALID_TARGET_AMOUNT'
  | 'RECEIPT_NOT_FOUND'
  | 'SUBSCRIPTION_READ_ONLY'
  | 'SUBSCRIPTION_BLOCKED'
  | 'RATE_LIMITED'
  | 'INVALID_WEBHOOK_SIGNATURE'
  | 'INVALID_SMS_HOOK_PAYLOAD'
  | 'SMS_PROVIDER_FAILED'
  | 'BALANCE_REMINDER_NOT_ELIGIBLE'
  | 'NO_OUTSTANDING_BALANCE'
  | 'MEMBER_PHONE_MISSING'
  | 'MEMBER_SMS_DISABLED'
  | 'BALANCE_REMINDER_RECENTLY_SENT'
  | 'SMS_LIMIT_REACHED'
  | 'SMS_TEMPLATE_NOT_FOUND'
  | 'SMS_TEMPLATE_INVALID'
  | 'REMINDER_BATCH_TOO_LARGE'
  | 'REMINDER_BATCH_EMPTY'
  | 'SHARE_WHATSAPP_ACCESS_DENIED'
  | 'SHARE_WHATSAPP_FINANCIAL_REQUIRED'
  | 'SHARE_SETTINGS_ACCESS_DENIED'
  | 'REPORT_ACCESS_DENIED'
  | 'REPORT_EXPORT_NOT_ALLOWED'
  | 'REPORT_FORMAT_NOT_SUPPORTED'
  | 'REPORT_EXPORT_TOO_LARGE'
  | 'REPORT_EXPORT_FAILED'
  | 'MEMBER_STATEMENT_NOT_FOUND'
  | 'INVALID_EXPORT_FILTER'
  | 'EXPORT_PERMISSION_DENIED'
  | 'PAYMENT_GATEWAY_DISABLED'
  | 'PAYMENT_PROVIDER_UNAVAILABLE'
  | 'PAYMENT_INTENT_NOT_FOUND'
  | 'PAYMENT_INTENT_EXPIRED'
  | 'PAYMENT_INTENT_ALREADY_COMPLETED'
  | 'INVOICE_NOT_PAYABLE'
  | 'PAYMENT_AMOUNT_MISMATCH'
  | 'PAYMENT_CURRENCY_MISMATCH'
  | 'PAYMENT_WEBHOOK_INVALID'
  | 'PAYMENT_WEBHOOK_DUPLICATE'
  | 'PAYMENT_TRANSACTION_UNKNOWN'
  | 'PAYMENT_ALREADY_PROCESSED'
  | 'PAYMENT_REVERSAL_ALREADY_PROCESSED'
  | 'PAYMENT_RECONCILIATION_REQUIRED'
  | 'INTERNAL_ERROR'

export interface SubscriptionPlan {
  id: string
  code: string
  name: string
  description: string
  currency: string
  priceAmount: number
  billingInterval: BillingInterval
  trialDays: number
  maxActiveEvents: number
  maxMembers: number
  maxUsers: number
  includedSms: number
  features: Record<string, unknown>
  isPublic: boolean
  isActive: boolean
  displayOrder: number
}

export interface Tenant {
  id: string
  code: string
  slug: string
  name: string
  legalName: string | null
  phoneE164: string
  email: string | null
  countryCode: 'TZ'
  timezone: 'Africa/Dar_es_Salaam'
  currency: 'TZS'
  status: TenantStatus
}

export interface TenantSettings {
  tenantId: string
  receiptPrefix: string
  smsSenderName: string | null
  defaultEventType: EventType | null
  defaultPledgeDeadlineDays: number | null
  logoUrl: string | null
  primaryColor: string | null
}

export interface TenantSubscription {
  id: string
  tenantId: string
  planId: string
  status: SubscriptionStatus
  startsAt: string
  trialEndsAt: string | null
  currentPeriodStart: string
  currentPeriodEnd: string | null
  planSnapshot: Record<string, unknown>
}

export interface TenantUser {
  id: string
  tenantId: string
  userId: string
  status: TenantUserStatus
  isOwner: boolean
  joinedAt: string | null
}

export interface TenantRole {
  id: string
  tenantId: string | null
  code: string
  name: string
  scope: 'SYSTEM' | 'TENANT'
  isSystem: boolean
}

export interface Permission {
  id: string
  code: string
  name: string
}

export interface Event {
  id: string
  tenantId: string
  code: string
  name: string
  eventType: EventType
  customEventType: string | null
  eventDate: string | null
  venue: string | null
  targetAmount: number | null
  pledgeDeadline: string | null
  status: EventStatus
}

export interface EventAssignment {
  id: string
  tenantId: string
  eventId: string
  tenantUserId: string
  accessLevel: EventAccessLevel
}

export interface PlatformUser {
  id: string
  userId: string
  role: PlatformRole
  status: 'ACTIVE' | 'SUSPENDED' | 'DISABLED'
}

export interface UserProfile {
  id: string
  fullName: string
  phoneE164: string
  email: string | null
  avatarUrl: string | null
  status: ProfileStatus
  preferredLanguage: 'sw' | 'en'
  onboardingCompletedAt: string | null
}

export interface SubscriptionSummary {
  id: string
  status: SubscriptionStatus
  planCode: string
  planName: string
  trialEndsAt: string | null
  currentPeriodEnd: string | null
  limits: Record<string, unknown>
  eventUsage?: {
    used: number
    limit: number
    available: number
    planCurrentMaxActiveEvents?: number
    subscriptionSnapshotMaxActiveEvents?: number
    effectiveMaxActiveEvents?: number
  }
}

export interface EventSummary {
  id: string
  code: string
  name: string
  eventType: EventType
  status: EventStatus
  eventDate: string | null
  pledgeDeadline: string | null
  targetAmount?: number | null
}

export interface TenantMembershipContext {
  tenantUserId: string
  tenantId: string
  tenantCode: string
  tenantName: string
  tenantSlug: string
  tenantStatus: TenantStatus
  membershipStatus: TenantUserStatus
  isOwner: boolean
  roles: string[]
  permissions: string[]
  subscription: SubscriptionSummary | null
  accessibleEvents: EventSummary[]
}

export interface TenantInvitationContext {
  invitationId: string
  tenantId: string
  tenantName: string
  tenantCode: string
  fullName: string
  phoneE164: string
  email: string | null
  roleCode: string
  status: 'INVITED'
  invitedAt: string
  lastSentAt: string | null
}

export interface UserContext {
  profile: UserProfile | null
  isPlatformUser: boolean
  platformRole: PlatformRole | null
  platformStatus: PlatformUserStatus | null
  platformPermissions: string[]
  onboardingCompleted: boolean
  tenantMemberships: TenantMembershipContext[]
  pendingInvitations: TenantInvitationContext[]
}

export interface TenantContext {
  tenant: Tenant
  subscription: SubscriptionSummary | null
  membership: Pick<TenantUser, 'id' | 'status' | 'isOwner'> | null
  roles: string[]
  permissions: string[]
  events: EventSummary[]
  accessState: TenantAccessState
}

export interface OnboardingPayload {
  planCode: string
  onboardingIntent?: 'FIRST_TENANT' | 'CREATE_ADDITIONAL_TENANT'
  tenantName: string
  tenantPhone: string
  tenantEmail?: string | null
  adminFullName: string
  adminEmail?: string | null
  preferredLanguage: 'sw' | 'en'
  firstEventName: string
  eventType: EventType
  customEventType?: string | null
  eventDate?: string | null
  venue?: string | null
  targetAmount?: number | null
  pledgeDeadline?: string | null
  betaInvitationCode?: string | null
  idempotencyKey: string
}

export interface OnboardingResult {
  tenantId: string
  tenantCode: string
  tenantSlug: string
  subscriptionId: string
  eventId: string
  eventCode: string
}

export interface PinVerificationResult {
  ok: boolean
  lockedUntil: string | null
  remainingAttempts?: number
}
