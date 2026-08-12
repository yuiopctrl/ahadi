import cors from 'cors'
import express from 'express'
import rateLimit from 'express-rate-limit'
import helmet from 'helmet'
import morgan from 'morgan'
import { createHash, randomBytes } from 'node:crypto'
import { z, ZodError } from 'zod'
import type { ApiErrorCode } from '@ahadi/types'
import {
  onboardingPayloadSchema,
  requestOtpSchema,
  setupPinSchema,
  tenantContextHeaderSchema,
  verifyOtpSchema,
  verifyPinSchema,
} from '@ahadi/validation'
import { logOtpDiagnostic, maskPhoneForLog } from './diagnostics.js'
import { env } from './env.js'
import { AppError, errorHandler } from './errors.js'
import { sendSmsHookHandler } from './modules/auth/hooks/send-sms-hook.controller.js'
import { getBillingGateway, listBillingGatewayCapabilities } from './modules/billing/gateways/gateway.registry.js'
import { confirmParsedGatewayPayment, confirmParsedGatewayReversal, createSubscriptionPaymentIntent } from './modules/billing/gateways/gateway.service.js'
import { classifyOnboardingDatabaseError, getSafeOnboardingDatabaseErrorDetails } from './onboarding-errors.js'
import { classifyPinSetupDatabaseError, classifyPinSetupValidationError, getSafePinDatabaseErrorDetails } from './pin-errors.js'
import {
  createExportDocument,
  exportRows,
  reportExportTitle,
  safeFileSlug,
  supportedExportFormats,
  type ReportExportFormat,
} from './report-exports.js'
import { createUserSupabase, supabasePublic } from './supabase.js'
import { loadUserContext, requestIdMiddleware, requireAuth, requirePlatformPermission, requireTenantContext } from './middleware.js'

export const app = express()
app.disable('etag')

interface SubscriptionPlanRow {
  billing_interval: string
  code: string
  currency: string
  description: string
  display_order: number
  features: Record<string, unknown>
  id: string
  included_sms: number
  is_public: boolean
  is_active: boolean
  max_active_events: number
  max_members: number
  max_users: number
  name: string
  price_amount: number | string
  trial_days: number
}

function toSubscriptionPlan(row: SubscriptionPlanRow) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    description: row.description,
    currency: row.currency,
    priceAmount: Number(row.price_amount),
    billingInterval: row.billing_interval,
    trialDays: row.trial_days,
    maxActiveEvents: row.max_active_events,
    maxMembers: row.max_members,
    maxUsers: row.max_users,
    includedSms: row.included_sms,
    features: row.features,
    isPublic: row.is_public,
    isActive: row.is_active,
    displayOrder: row.display_order,
  }
}

app.set('trust proxy', env.TRUST_PROXY_HOPS)

const strictLimiter = rateLimit({
  windowMs: 60_000,
  limit: 5,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (request, response) => {
    response.status(429).json({
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many attempts. Try again shortly.',
        requestId: request.requestId,
      },
    })
  },
})

const sendSmsHookLimiter = rateLimit({
  windowMs: 60_000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (_request, response) => {
    response.status(429).json({
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many attempts. Try again shortly.',
      },
    })
  },
})

const paymentIntentLimiter = rateLimit({
  windowMs: 60_000,
  limit: 12,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (request, response) => {
    response.status(429).json({
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many payment attempts. Try again shortly.',
        requestId: request.requestId,
      },
    })
  },
})

function getProviderStatus(error: unknown): number | null {
  if (typeof error === 'object' && error !== null && 'status' in error && typeof error.status === 'number') {
    return error.status
  }
  return null
}

function getProviderCode(error: unknown): string | null {
  if (typeof error === 'object' && error !== null && 'code' in error && typeof error.code === 'string') {
    return error.code
  }
  return null
}

function getProviderName(error: unknown): string | null {
  if (typeof error === 'object' && error !== null && 'name' in error && typeof error.name === 'string') {
    return error.name
  }
  return null
}

function getSafeProviderMessage(error: unknown): string | null {
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') {
    return error.message.replace(/[+0-9][0-9\s().-]{6,}/g, '<redacted-phone>').slice(0, 160)
  }
  return null
}

function isRetryableSupabaseError(error: unknown): boolean {
  const name = getProviderName(error)
  return name === 'AuthRetryableFetchError'
}

function classifySupabaseOtpError(error: unknown): { category: string; stage: Parameters<typeof logOtpDiagnostic>[1] } {
  const code = getProviderCode(error)
  const status = getProviderStatus(error)
  const message = getSafeProviderMessage(error)?.toLowerCase() ?? ''
  const name = getProviderName(error)

  if (code === 'phone_provider_disabled' || message.includes('phone provider')) {
    return { category: 'PHONE_PROVIDER_DISABLED', stage: 'SUPABASE_PHONE_PROVIDER_DISABLED' }
  }
  if (code === 'over_sms_send_rate_limit' || status === 429) {
    return { category: 'RATE_LIMITED', stage: 'SUPABASE_RATE_LIMITED' }
  }
  if (name === 'AuthRetryableFetchError' || status === 500 || message.includes('hook')) {
    return { category: 'SMS_HOOK_UNREACHABLE', stage: 'SUPABASE_HOOK_FAILED' }
  }
  return { category: 'UNKNOWN_SUPABASE_AUTH_ERROR', stage: 'SUPABASE_AUTH_UNKNOWN_ERROR' }
}

function logProviderError(requestId: string, operation: string, error: unknown) {
  if (typeof error === 'object' && error !== null) {
    const details = error as { name?: unknown; message?: unknown; status?: unknown; code?: unknown }
    console.error('Supabase auth provider error', {
      requestId,
      operation,
      name: typeof details.name === 'string' ? details.name : undefined,
      status: typeof details.status === 'number' ? details.status : undefined,
      code: typeof details.code === 'string' ? details.code : undefined,
      message: typeof details.message === 'string' ? details.message : undefined,
    })
    return
  }
  console.error('Supabase auth provider error', { requestId, operation })
}

function logValidationError(requestId: string, operation: string, error: ZodError) {
  if (env.NODE_ENV !== 'development') {
    return
  }
  console.error('Request validation error', {
    requestId,
    operation,
    issues: error.issues.map((issue) => ({
      path: issue.path.join('.'),
      code: issue.code,
      message: issue.message,
    })),
  })
}

function healthPayload() {
  return {
    ok: true,
    status: 'ok',
    service: 'ahadi-api',
    ...(env.NODE_ENV === 'development'
      ? {
          pid: process.pid,
          uptimeSeconds: Math.floor(process.uptime()),
          environment: env.NODE_ENV,
        }
      : {}),
  }
}

function requestTraceMiddleware(request: express.Request, response: express.Response, next: express.NextFunction) {
  if (env.NODE_ENV !== 'development') {
    next()
    return
  }
  const start = performance.now()
  const path = request.originalUrl.split('?')[0] ?? request.originalUrl
  console.info('HTTP_REQUEST_STARTED', {
    requestId: request.requestId,
    pid: process.pid,
    method: request.method,
    path,
  })
  response.on('finish', () => {
    console.info('HTTP_REQUEST_COMPLETED', {
      requestId: request.requestId,
      pid: process.pid,
      method: request.method,
      path,
      status: response.statusCode,
      durationMs: Math.round(performance.now() - start),
    })
  })
  next()
}

const uuidParamSchema = z.string().uuid()
const optionalTextSchema = z.string().trim().max(500).optional().nullable()
const optionalShortTextSchema = z.string().trim().max(160).optional().nullable()
const moneySchema = z.coerce.number().finite().positive().max(999_999_999_999.99)

const createMemberSchema = z.object({
  fullName: z.string().trim().min(2).max(160),
  phone: z.string().trim().optional().nullable(),
  alternativePhone: z.string().trim().optional().nullable(),
  email: z.string().trim().email().optional().nullable().or(z.literal('')),
  location: optionalShortTextSchema,
  categoryId: z.string().uuid().optional().nullable(),
  notes: optionalTextSchema,
  smsEnabled: z.boolean().optional(),
  initialPledgeAmount: z.coerce.number().finite().positive().optional().nullable(),
  initialPledgeDueDate: z.string().date().optional().nullable(),
})

const createContactSchema = createMemberSchema.omit({
  categoryId: true,
  initialPledgeAmount: true,
  initialPledgeDueDate: true,
})

const attachMemberSchema = z.object({
  memberId: z.string().uuid(),
  categoryId: z.string().uuid().optional().nullable(),
  notes: optionalTextSchema,
})

const upsertPledgeSchema = z.object({
  eventMemberId: z.string().uuid(),
  amount: moneySchema,
  dueDate: z.string().date().optional().nullable(),
  notes: optionalTextSchema,
  changeReason: optionalTextSchema,
})

const patchPledgeSchema = upsertPledgeSchema.extend({
  eventMemberId: z.string().uuid().optional(),
})

const cancelPledgeSchema = z.object({
  reason: z.string().trim().min(1).max(500),
})

const removeEventMemberSchema = z.object({
  reason: z.string().trim().min(1).max(500).optional(),
})

const recordPaymentSchema = z.object({
  eventMemberId: z.string().uuid(),
  amount: moneySchema,
  paymentMethod: z.enum(['CASH', 'M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA', 'BANK_TRANSFER', 'CHEQUE', 'OTHER']),
  paymentDate: z.string().datetime({ offset: true }).optional().nullable(),
  transactionReference: optionalShortTextSchema,
  providerName: optionalShortTextSchema,
  notes: optionalTextSchema,
  pledgeId: z.string().uuid().optional().nullable(),
  idempotencyKey: z.string().uuid(),
})

const reversePaymentSchema = z.object({
  reason: z.string().trim().min(1).max(500),
  idempotencyKey: z.string().uuid(),
})

const createEventSchema = z.object({
  name: z.string().trim().min(2).max(160),
  eventType: z.enum(['WEDDING', 'SENDOFF', 'FUNERAL', 'FUNDRAISER', 'BIRTHDAY', 'GRADUATION', 'RELIGIOUS', 'OTHER']),
  customEventType: optionalShortTextSchema,
  eventDate: z.string().date().optional().nullable(),
  venue: optionalShortTextSchema,
  targetAmount: z.coerce.number().finite().positive().max(999_999_999_999.99).optional().nullable(),
  pledgeDeadline: z.string().date().optional().nullable(),
}).superRefine((value, context) => {
  if (value.eventType === 'OTHER' && !value.customEventType) {
    context.addIssue({ code: 'custom', path: ['customEventType'], message: 'Custom event type is required' })
  }
})

const createSubscriptionPaymentIntentSchema = z.object({
  provider: z.enum(['TEST', 'NMB']).default('TEST'),
  paymentMethod: z.enum(['MOBILE_MONEY', 'CONTROL_NUMBER']).default('MOBILE_MONEY'),
  idempotencyKey: z.string().uuid(),
  returnUrl: z.string().url().optional().nullable(),
})

const balanceReminderSchema = z.object({
  eventMemberId: z.string().uuid(),
  idempotencyKey: z.string().uuid(),
})

const pledgeRequestSchema = z.object({
  eventMemberId: z.string().uuid(),
  idempotencyKey: z.string().uuid(),
})

const bulkBalanceReminderSchema = z.object({
  eventMemberIds: z.array(z.string().uuid()).min(1),
  idempotencyKey: z.string().uuid(),
})

const bulkPledgeRequestSchema = z.object({
  eventMemberIds: z.array(z.string().uuid()).min(1),
  idempotencyKey: z.string().uuid(),
})

const bulkCompletedPledgeSchema = z.object({
  eventMemberIds: z.array(z.string().uuid()).min(1),
  idempotencyKey: z.string().uuid(),
})

const smsManualTemplateCodeSchema = z.enum(['PLEDGE_REQUEST', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED'])

const smsPreviewSchema = z.object({
  templateCode: smsManualTemplateCodeSchema,
  eventMemberId: z.string().uuid(),
})

const smsBulkPreviewSchema = z.object({
  templateCode: smsManualTemplateCodeSchema,
  eventMemberIds: z.array(z.string().uuid()).min(1),
})

const templateBodySchema = z.object({
  body: z.string().trim().min(1).max(918),
})

const smsTemplateCodeSchema = z.enum(['PLEDGE_REQUEST', 'PLEDGE_REGISTRATION', 'PAYMENT_CONFIRMATION', 'BALANCE_REMINDER', 'PLEDGE_COMPLETED'])
type SmsTemplateCode = z.infer<typeof smsTemplateCodeSchema>

const smsTemplateAllowedVariablesByCode: Record<SmsTemplateCode, string[]> = {
  PLEDGE_REQUEST: ['member_name', 'event_name', 'event_date', 'pledge_deadline'],
  PLEDGE_REGISTRATION: ['member_name', 'pledge_amount', 'event_name', 'due_date'],
  PAYMENT_CONFIRMATION: ['member_name', 'payment_amount', 'payment_method', 'event_name', 'balance', 'receipt_number'],
  BALANCE_REMINDER: ['member_name', 'event_name', 'balance', 'due_date'],
  PLEDGE_COMPLETED: ['member_name', 'pledge_amount', 'event_name'],
}

const sensitiveSmsTemplateVariables = new Set(['otp', 'pin', 'password'])

const smsTemplateSaveSchema = templateBodySchema.extend({
  language: z.enum(['sw', 'en']).default('sw'),
})

const smsSettingsSchema = z.object({
  smsEnabled: z.boolean(),
  provider: z.enum(['NEXTSMS', 'WEBBULKSMS']),
  senderId: z.string().trim().min(1).max(40),
  defaultLanguage: z.enum(['sw', 'en']).default('sw'),
})

const platformSmsProviderUpdateSchema = z.object({
  status: z.enum(['ACTIVE', 'DISABLED']).optional(),
  isDefault: z.boolean().optional(),
})

const platformSmsSenderUpdateSchema = z.object({
  status: z.enum(['ACTIVE', 'DISABLED']).optional(),
  isDefault: z.boolean().optional(),
})

const resendBalanceReminderSchema = z.object({
  idempotencyKey: z.string().uuid(),
})

const processQueuedSmsSchema = z.object({
  batchSize: z.coerce.number().int().positive().max(50).optional(),
})

const rolloutSettingsSchema = z.object({
  registrationMode: z.enum(['OPEN', 'INVITE_ONLY', 'PAUSED']),
  betaModeEnabled: z.boolean().optional(),
  defaultTrialDays: z.coerce.number().int().nonnegative().optional(),
  supportEmail: optionalShortTextSchema,
  supportPhone: optionalShortTextSchema,
  maintenanceNotice: optionalTextSchema,
  maintenanceMode: z.enum(['OFF', 'READ_ONLY']).optional(),
  minimumSupportedWebVersion: optionalShortTextSchema,
})

const betaInvitationCreateSchema = z.object({
  intendedName: optionalShortTextSchema,
  intendedPhone: z.string().trim().optional().nullable(),
  intendedEmail: optionalShortTextSchema,
  planId: z.string().uuid().optional().nullable(),
  trialDaysOverride: z.coerce.number().int().nonnegative().optional().nullable(),
  maxUses: z.coerce.number().int().positive().max(100).optional(),
  expiresAt: z.string().datetime({ offset: true }).optional().nullable(),
})

const supportRequestSchema = z.object({
  category: z.enum(['LOGIN', 'MEMBERS', 'PLEDGES', 'PAYMENTS', 'SMS', 'REPORTS', 'SUBSCRIPTION', 'OTHER']),
  subject: z.string().trim().min(3).max(160),
  description: z.string().trim().min(10).max(4000),
  eventId: z.string().uuid().optional().nullable(),
  contactPreference: optionalShortTextSchema,
  appContext: z.record(z.string(), z.unknown()).optional(),
})

const supportRequestUpdateSchema = z.object({
  status: z.enum(['OPEN', 'IN_PROGRESS', 'WAITING_CUSTOMER', 'RESOLVED', 'CLOSED']).optional().nullable(),
  priority: z.enum(['LOW', 'NORMAL', 'HIGH', 'URGENT']).optional().nullable(),
  assignedTo: z.string().uuid().optional().nullable(),
  note: optionalTextSchema,
})

const supportAccessSessionSchema = z.object({
  reason: z.string().trim().min(5).max(500),
  durationMinutes: z.coerce.number().int().positive().max(240).optional(),
})

const feedbackSchema = z.object({
  category: z.enum(['SUGGESTION', 'PROBLEM', 'USABILITY', 'OTHER']),
  message: z.string().trim().min(3).max(4000),
  eventId: z.string().uuid().optional().nullable(),
  page: optionalShortTextSchema,
  appContext: z.record(z.string(), z.unknown()).optional(),
})

const frontendErrorReportSchema = z.object({
  tenantId: z.string().uuid().optional().nullable(),
  errorCode: optionalShortTextSchema,
  requestId: optionalShortTextSchema,
  route: optionalShortTextSchema,
  component: optionalShortTextSchema,
  appVersion: optionalShortTextSchema,
  browserSummary: optionalShortTextSchema,
  metadata: z.record(z.string(), z.unknown()).optional(),
})

const tenantTrialExtensionSchema = z.object({
  days: z.coerce.number().int().positive().max(90),
  reason: z.string().trim().min(3).max(500),
})

const featureFlagSchema = z.object({
  enabledGlobally: z.boolean(),
  betaOnly: z.boolean().optional(),
})

const tenantFeatureOverrideSchema = z.object({
  tenantId: z.string().uuid(),
  override: z.enum(['INHERIT', 'ENABLED', 'DISABLED']),
})

const whatsappShareFormatSchema = z.enum(['DETAILED', 'PRIVACY', 'PAYMENT_PROGRESS', 'OUTSTANDING_FOLLOW_UP'])
const whatsappShareSortSchema = z.enum(['ORIGINAL', 'NAME_ASC', 'PLEDGED_DESC', 'PAID_FIRST', 'OUTSTANDING_FIRST'])
const whatsappShareStatusSchema = z.enum(['ALL', 'PAID', 'PARTIAL', 'UNPAID', 'OVERDUE'])
const whatsappPhoneFilterSchema = z.enum(['ALL', 'WITH_PHONE', 'WITHOUT_PHONE'])
const whatsappSummaryValueSourceSchema = z.enum([
  'TOTAL_PLEDGED',
  'TOTAL_RECEIVED',
  'TOTAL_OUTSTANDING',
  'CASH_RECEIVED',
  'MOBILE_MONEY_RECEIVED',
  'M_PESA_RECEIVED',
  'AIRTEL_MONEY_RECEIVED',
  'MIX_BY_YAS_RECEIVED',
  'HALOPESA_RECEIVED',
  'BANK_RECEIVED',
  'CHEQUE_RECEIVED',
  'OTHER_RECEIVED',
])
const whatsappSummaryRowSchema = z.object({
  label: z.string().trim().min(1).max(80),
  valueSource: whatsappSummaryValueSourceSchema,
  visible: z.boolean().default(true),
  order: z.coerce.number().int().min(1).max(50),
})

const whatsappSharePreviewSchema = z.object({
  format: whatsappShareFormatSchema.default('DETAILED'),
  statusFilter: whatsappShareStatusSchema.default('ALL'),
  categoryId: z.string().uuid().optional().nullable(),
  sort: whatsappShareSortSchema.default('ORIGINAL'),
  includeSummary: z.boolean().optional().nullable(),
  includeEventDate: z.boolean().optional().nullable(),
  includeEventPaymentInstructions: z.boolean().optional().nullable(),
  includeMobileMoneyInstructions: z.boolean().optional().nullable(),
  includeBankInstructions: z.boolean().optional().nullable(),
  includeWithoutPledges: z.boolean().optional().default(false),
  phoneFilter: whatsappPhoneFilterSchema.default('ALL'),
  search: z.string().trim().max(120).optional().default(''),
  summaryRows: z.array(whatsappSummaryRowSchema).max(12).optional().nullable(),
})

const whatsappShareSettingsSchema = z.object({
  headerText: z.string().trim().max(500).optional().nullable(),
  footerText: z.string().trim().max(500).optional().nullable(),
  includeEventName: z.boolean().optional().default(true),
  includeEventDate: z.boolean().optional().default(false),
  includeEventPaymentInstructions: z.boolean().optional().default(false),
  includeMobileMoneyInstructions: z.boolean().optional().default(false),
  includeBankInstructions: z.boolean().optional().default(false),
  defaultListFormat: whatsappShareFormatSchema.default('DETAILED'),
  defaultSort: whatsappShareSortSchema.default('ORIGINAL'),
  defaultIncludeSummary: z.boolean().optional().default(true),
  summaryRows: z.array(whatsappSummaryRowSchema).max(12).optional().nullable(),
})

const reportTypeSchema = z.enum(['summary', 'pledges', 'payments', 'outstanding', 'payment-methods', 'collectors', 'member-statement'])
const reportRequestSchema = z.object({
  page: z.coerce.number().int().positive().optional().default(1),
  pageSize: z.coerce.number().int().positive().max(100).optional().default(25),
  status: z.string().trim().optional().default('ALL'),
  category: z.string().trim().optional().nullable(),
  dueFrom: z.string().date().optional().nullable(),
  dueTo: z.string().date().optional().nullable(),
  dateFrom: z.string().date().optional().nullable(),
  dateTo: z.string().date().optional().nullable(),
  paymentMethod: z.string().trim().optional().default('ALL'),
  collectorId: z.string().uuid().optional().nullable(),
  filter: z.string().trim().optional().default('ALL'),
  search: z.string().trim().max(120).optional().default(''),
  sort: z.string().trim().optional().default('DATE'),
  direction: z.enum(['ASC', 'DESC']).optional().default('DESC'),
  eventMemberId: z.string().uuid().optional().nullable(),
})
type ReportRequest = z.infer<typeof reportRequestSchema>
type ReportType = z.infer<typeof reportTypeSchema>
const reportExportFormatSchema = z.enum(['CSV', 'XLSX', 'PDF', 'PRINT'])
const reportExportRequestSchema = z.object({
  format: reportExportFormatSchema,
  filters: reportRequestSchema.partial().optional().default({}),
  sort: z.object({
    field: z.string().trim().optional(),
    direction: z.enum(['ASC', 'DESC']).optional(),
  }).optional().default({}),
})
const exportLimits: Record<ReportExportFormat, number> = {
  CSV: 10_000,
  XLSX: 10_000,
  PDF: 2_000,
  PRINT: 2_000,
}

const updateMemberSchema = z.object({
  fullName: z.string().trim().min(2).max(160).optional(),
  phoneE164: z.string().trim().optional().nullable(),
  alternativePhoneE164: z.string().trim().optional().nullable(),
  email: z.string().trim().email().optional().nullable().or(z.literal('')),
  location: optionalShortTextSchema,
  notes: optionalTextSchema,
  preferredLanguage: z.enum(['sw', 'en']).optional(),
  smsEnabled: z.boolean().optional(),
  status: z.enum(['ACTIVE', 'INACTIVE', 'ARCHIVED']).optional(),
})

const knownDatabaseCodes: ApiErrorCode[] = [
  'INVALID_INPUT',
  'SESSION_REQUIRED',
  'TENANT_ACCESS_DENIED',
  'PLATFORM_ACCESS_DENIED',
  'PERMISSION_DENIED',
  'BALANCE_REMINDER_NOT_ELIGIBLE',
  'NO_OUTSTANDING_BALANCE',
  'MEMBER_PHONE_MISSING',
  'MEMBER_SMS_DISABLED',
  'BALANCE_REMINDER_RECENTLY_SENT',
  'SMS_LIMIT_REACHED',
  'SMS_TEMPLATE_NOT_FOUND',
  'SMS_TEMPLATE_INVALID',
  'REMINDER_BATCH_TOO_LARGE',
  'REMINDER_BATCH_EMPTY',
  'SHARE_WHATSAPP_ACCESS_DENIED',
  'SHARE_WHATSAPP_FINANCIAL_REQUIRED',
  'SHARE_SETTINGS_ACCESS_DENIED',
  'REPORT_ACCESS_DENIED',
  'REPORT_EXPORT_NOT_ALLOWED',
  'REPORT_FORMAT_NOT_SUPPORTED',
  'REPORT_EXPORT_TOO_LARGE',
  'REPORT_EXPORT_FAILED',
  'MEMBER_STATEMENT_NOT_FOUND',
  'INVALID_EXPORT_FILTER',
  'EXPORT_PERMISSION_DENIED',
  'MEMBER_NOT_FOUND',
  'MEMBER_PHONE_ALREADY_EXISTS',
  'MEMBER_ALREADY_IN_EVENT',
  'EVENT_MEMBER_NOT_FOUND',
  'EVENT_MEMBER_REMOVED',
  'CATEGORY_NOT_FOUND',
  'PLEDGE_NOT_FOUND',
  'PLEDGE_ALREADY_EXISTS',
  'PLEDGE_AMOUNT_INVALID',
  'PLEDGE_BELOW_PAID_AMOUNT',
  'PLEDGE_CANCELLED',
  'PLEDGE_REQUIRED_FOR_PAYMENT',
  'PAYMENT_NOT_FOUND',
  'PAYMENT_AMOUNT_INVALID',
  'PAYMENT_REFERENCE_DUPLICATE',
  'PAYMENT_ALREADY_REVERSED',
  'PAYMENT_REVERSAL_REASON_REQUIRED',
  'PAYMENT_IDEMPOTENCY_CONFLICT',
  'EVENT_NOT_ACTIVE',
  'EVENT_ACCESS_DENIED',
  'EVENT_LIMIT_REACHED',
  'INVALID_EVENT_TYPE',
  'INVALID_EVENT_DATE',
  'INVALID_TARGET_AMOUNT',
  'RECEIPT_NOT_FOUND',
  'SUBSCRIPTION_INACTIVE',
  'SUBSCRIPTION_READ_ONLY',
  'SUBSCRIPTION_BLOCKED',
  'PAYMENT_GATEWAY_DISABLED',
  'PAYMENT_PROVIDER_UNAVAILABLE',
  'PAYMENT_INTENT_NOT_FOUND',
  'PAYMENT_INTENT_EXPIRED',
  'PAYMENT_INTENT_ALREADY_COMPLETED',
  'INVOICE_NOT_PAYABLE',
  'PAYMENT_AMOUNT_MISMATCH',
  'PAYMENT_CURRENCY_MISMATCH',
  'PAYMENT_WEBHOOK_INVALID',
  'PAYMENT_WEBHOOK_DUPLICATE',
  'PAYMENT_TRANSACTION_UNKNOWN',
  'PAYMENT_ALREADY_PROCESSED',
  'PAYMENT_REVERSAL_ALREADY_PROCESSED',
  'PAYMENT_RECONCILIATION_REQUIRED',
]

const developmentWebOrigins = new Set([
  env.WEB_URL,
  'http://localhost:5173',
  'http://127.0.0.1:5173',
  'http://localhost:5174',
  'http://127.0.0.1:5174',
])
const productionWebOrigins = new Set([
  env.WEB_URL,
  'https://ahadi.yuiop.work',
])

const corsOrigin: cors.CorsOptions['origin'] =
  env.NODE_ENV === 'development'
    ? (origin, callback) => {
        if (!origin || developmentWebOrigins.has(origin)) {
          callback(null, origin ?? true)
          return
        }
        callback(new Error('CORS_ORIGIN_DENIED'))
      }
    : (origin, callback) => {
        if (!origin || productionWebOrigins.has(origin)) {
          callback(null, origin ?? true)
          return
        }
        callback(new Error('CORS_ORIGIN_DENIED'))
      }

function databaseMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') {
    const details = 'details' in error && typeof error.details === 'string' ? error.details : ''
    const hint = 'hint' in error && typeof error.hint === 'string' ? error.hint : ''
    const code = 'code' in error && typeof error.code === 'string' ? error.code : ''
    return [error.message, details, hint, code].filter(Boolean).join(' ')
  }
  return ''
}

function safeDatabaseMessage(error: unknown): string {
  return databaseMessage(error)
    .replace(/[+0-9][0-9\s().-]{6,}/g, '<redacted-phone>')
    .slice(0, 220)
}

function logDatabaseError(requestId: string, operation: string, error: unknown, context: Record<string, unknown> = {}) {
  const code = typeof error === 'object' && error !== null && 'code' in error && typeof error.code === 'string' ? error.code : undefined
  console.error('Database operation failed', {
    requestId,
    operation,
    ...context,
    ...(code ? { providerCode: code } : {}),
    safeMessage: safeDatabaseMessage(error),
  })
}

function throwFinancialDatabaseError(error: unknown, fallbackCategory: string): never {
  const message = databaseMessage(error).toUpperCase()
  const matchedCode = knownDatabaseCodes.find((code) => message.includes(code))
  if (matchedCode) {
    throw new AppError(matchedCode)
  }
  throw new AppError('INTERNAL_ERROR', 'Unexpected application error', 500, fallbackCategory)
}

function tenantIdFromRequest(request: express.Request): string {
  const tenantId = request.tenantContext?.tenant.id
  if (!tenantId) {
    throw new AppError('TENANT_ACCESS_DENIED', 'A verified tenant context is required')
  }
  return tenantId
}

function jsonArray(data: unknown): Record<string, unknown>[] {
  return Array.isArray(data) ? data as Record<string, unknown>[] : []
}

function jsonRecord(data: unknown): Record<string, unknown> {
  return typeof data === 'object' && data !== null && !Array.isArray(data) ? data as Record<string, unknown> : {}
}

function errorCode(error: unknown): string | null {
  return typeof error === 'object' && error !== null && 'code' in error && typeof error.code === 'string' ? error.code : null
}

function isMissingBillingFoundationError(error: unknown): boolean {
  const code = errorCode(error)
  const message = databaseMessage(error).toLowerCase()
  return (
    code === '42P01' ||
    code === 'PGRST200' ||
    code === 'PGRST202' ||
    code === 'PGRST205' ||
    message.includes('subscription_invoices') ||
    message.includes('subscription_invoice_items') ||
    message.includes('subscription_payments') ||
    message.includes('subscription_payment_intents') ||
    message.includes('subscription_gateway_settings')
  )
}

async function optionalBillingRows(
  request: express.Request,
  operation: string,
  query: PromiseLike<{ data: unknown; error: unknown }>,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await query
  if (!error) {
    return jsonArray(data)
  }
  logDatabaseError(request.requestId, operation, error)
  if (isMissingBillingFoundationError(error)) {
    return []
  }
  throwFinancialDatabaseError(error, operation.toUpperCase())
}

function stringField(row: Record<string, unknown>, key: string, fallback = ''): string {
  const value = row[key]
  return typeof value === 'string' ? value : fallback
}

function numberField(row: Record<string, unknown>, key: string): number {
  const value = row[key]
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : 0
  }
  return 0
}

function availableEventSlots(value: unknown): number | null {
  const usage = jsonRecord(value)
  for (const key of ['available', 'availableEventSlots', 'available_event_slots']) {
    if (usage[key] !== undefined && usage[key] !== null) {
      return numberField(usage, key)
    }
  }
  return null
}

function eventSlotNumber(usage: Record<string, unknown>, keys: string[]): number | null {
  for (const key of keys) {
    if (usage[key] !== undefined && usage[key] !== null) {
      return numberField(usage, key)
    }
  }
  return null
}

function eventSlotSummary(value: unknown) {
  const usage = jsonRecord(value)
  return {
    usedEventSlots: eventSlotNumber(usage, ['used', 'usedEventSlots', 'used_event_slots']),
    maxEventSlots: eventSlotNumber(usage, ['limit', 'maxEventSlots', 'max_event_slots']),
    availableEventSlots: eventSlotNumber(usage, ['available', 'availableEventSlots', 'available_event_slots']),
    currentPlanLimit: eventSlotNumber(usage, ['planCurrentMaxActiveEvents']),
    snapshotLimit: eventSlotNumber(usage, ['subscriptionSnapshotMaxActiveEvents']),
    effectiveLimit: eventSlotNumber(usage, ['effectiveMaxActiveEvents', 'limit', 'maxEventSlots', 'max_event_slots']),
  }
}

type CreateEventInput = z.infer<typeof createEventSchema>

function nullableTrimmed(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? ''
  return trimmed ? trimmed : null
}

function normalizeCreateEventInput(input: CreateEventInput) {
  return {
    name: input.name.trim(),
    eventType: input.eventType,
    customEventType: input.eventType === 'OTHER' ? nullableTrimmed(input.customEventType) : null,
    eventDate: input.eventDate ?? null,
    pledgeDeadline: input.pledgeDeadline ?? null,
    targetAmount: input.targetAmount ?? null,
    venue: nullableTrimmed(input.venue),
  }
}

function logEventCreateStage(request: express.Request, stage: string, details: Record<string, unknown> = {}) {
  if (env.NODE_ENV !== 'development') {
    return
  }
  console.info('Event create diagnostic', {
    requestId: request.requestId,
    stage,
    tenantId: request.tenantContext?.tenant.id,
    userId: request.auth?.user.id,
    tenantAccessState: request.tenantContext?.accessState,
    subscriptionStatus: request.tenantContext?.subscription?.status ?? null,
    ...details,
  })
}

function shouldRetryLegacyCreateEvent(error: unknown): boolean {
  const message = databaseMessage(error).toLowerCase()
  return message.includes('rpc_create_event') && (message.includes('p_custom_event_type') || message.includes('schema cache') || message.includes('pgrst202') || message.includes('pgrst203'))
}

function shouldRetryV2CreateEvent(error: unknown): boolean {
  const message = databaseMessage(error).toLowerCase()
  return message.includes('rpc_create_event_v2') && (message.includes('schema cache') || message.includes('pgrst202') || message.includes('could not find'))
}

function shouldUseDirectEventCreateFallback(error: unknown): boolean {
  const message = databaseMessage(error).toLowerCase()
  return message.includes('42702') && message.includes('event_id') && message.includes('ambiguous')
}

async function createEventWithDirectFallback(
  client: ReturnType<typeof createUserSupabase>,
  request: express.Request,
  tenantId: string,
  input: ReturnType<typeof normalizeCreateEventInput>,
  slotSummary: ReturnType<typeof eventSlotSummary> | null,
) {
  const userId = request.auth?.user.id
  if (!userId) {
    throw new AppError('SESSION_REQUIRED')
  }
  logEventCreateStage(request, 'EVENT_CREATE_DIRECT_FALLBACK_START', slotSummary ?? {})
  const codeResult = await client.rpc('next_event_code', { p_tenant_id: tenantId })
  if (codeResult.error) {
    logDatabaseError(request.requestId, 'event-create-direct-code', codeResult.error, {
      tenantId,
      userId,
      stage: 'EVENT_CREATE_DIRECT_CODE_FAILED',
      ...(slotSummary ?? {}),
    })
    throwFinancialDatabaseError(codeResult.error, 'EVENT_CREATE_FAILED')
  }
  const eventCode = typeof codeResult.data === 'string' && codeResult.data.trim() ? codeResult.data : null
  if (!eventCode) {
    throw new AppError('INTERNAL_ERROR', 'Event code generation failed', 500, 'EVENT_CREATE_FAILED')
  }

  const insertResult = await client
    .from('events')
    .insert({
      tenant_id: tenantId,
      code: eventCode,
      name: input.name,
      event_type: input.eventType,
      custom_event_type: input.customEventType,
      event_date: input.eventDate,
      pledge_deadline: input.pledgeDeadline,
      target_amount: input.targetAmount,
      venue: input.venue,
      status: 'ACTIVE',
      created_by: userId,
    })
    .select('id, code, name, event_type, custom_event_type, event_date, pledge_deadline, target_amount, venue, status')
    .single()
  if (insertResult.error) {
    logDatabaseError(request.requestId, 'event-create-direct-insert', insertResult.error, {
      tenantId,
      userId,
      stage: 'EVENT_CREATE_DIRECT_INSERT_FAILED',
      ...(slotSummary ?? {}),
    })
    throwFinancialDatabaseError(insertResult.error, 'EVENT_CREATE_FAILED')
  }

  const row = jsonRecord(insertResult.data)
  const createdEventId = stringField(row, 'id')
  if (!createdEventId) {
    throw new AppError('INTERNAL_ERROR', 'Event insert did not return an event id', 500, 'EVENT_CREATE_FAILED')
  }

  const tenantUserResult = await client
    .from('tenant_users')
    .select('id')
    .eq('tenant_id', tenantId)
    .eq('user_id', userId)
    .eq('status', 'ACTIVE')
    .maybeSingle()
  const tenantUserId = tenantUserResult.error ? null : stringField(jsonRecord(tenantUserResult.data), 'id')
  if (tenantUserResult.error) {
    logDatabaseError(request.requestId, 'event-create-direct-tenant-user', tenantUserResult.error, {
      tenantId,
      userId,
      eventId: createdEventId,
      stage: 'EVENT_CREATE_DIRECT_ASSIGNMENT_SKIPPED',
    })
  }
  if (tenantUserId) {
    const assignmentResult = await client
      .from('event_user_assignments')
      .upsert({
        tenant_id: tenantId,
        event_id: createdEventId,
        tenant_user_id: tenantUserId,
        access_level: 'MANAGE',
        assigned_by: userId,
      }, { onConflict: 'event_id,tenant_user_id' })
    if (assignmentResult.error) {
      logDatabaseError(request.requestId, 'event-create-direct-assignment', assignmentResult.error, {
        tenantId,
        userId,
        eventId: createdEventId,
        stage: 'EVENT_CREATE_DIRECT_ASSIGNMENT_FAILED',
      })
    } else {
      logEventCreateStage(request, 'EVENT_CREATE_ASSIGNMENT_SUCCESS', { eventId: createdEventId })
    }
  }

  const auditResult = await client.rpc('write_audit_log', {
    p_tenant_id: tenantId,
    p_action: 'EVENT_CREATED',
    p_entity_type: 'event',
    p_entity_id: createdEventId,
    p_event_id: createdEventId,
    p_old_values: null,
    p_new_values: { event_code: eventCode, eventSlotsBefore: slotSummary },
    p_reason: null,
  })
  if (auditResult.error) {
    logDatabaseError(request.requestId, 'event-create-direct-audit', auditResult.error, {
      tenantId,
      userId,
      eventId: createdEventId,
      stage: 'EVENT_CREATE_DIRECT_AUDIT_FAILED',
    })
  } else {
    logEventCreateStage(request, 'EVENT_CREATE_AUDIT_SUCCESS', { eventId: createdEventId })
  }

  const slotsAfter = await client.rpc('event_slot_usage', { p_tenant_id: tenantId })
  const eventSlotsAfter = slotsAfter.error ? null : eventSlotSummary(slotsAfter.data)
  return {
    id: createdEventId,
    event_id: createdEventId,
    eventId: createdEventId,
    code: eventCode,
    event_code: eventCode,
    name: stringField(row, 'name', input.name),
    eventType: stringField(row, 'event_type', input.eventType),
    customEventType: row['custom_event_type'] ?? null,
    eventDate: row['event_date'] ?? null,
    pledgeDeadline: row['pledge_deadline'] ?? null,
    targetAmount: row['target_amount'] ?? null,
    venue: row['venue'] ?? null,
    status: stringField(row, 'status', 'ACTIVE'),
    eventSlotsBefore: slotSummary,
    eventSlotsAfter,
  }
}

function dateField(row: Record<string, unknown>, key: string): string {
  const value = row[key]
  return typeof value === 'string' ? value.slice(0, 10) : ''
}

function matchesReportSearch(row: Record<string, unknown>, input: ReportRequest, keys: string[]): boolean {
  const needle = input.search.trim().toLowerCase()
  if (!needle) return true
  return keys.some((key) => String(row[key] ?? '').toLowerCase().includes(needle))
}

function compareReportValues(left: unknown, right: unknown, direction: 'ASC' | 'DESC') {
  const modifier = direction === 'ASC' ? 1 : -1
  if (typeof left === 'number' || typeof right === 'number') {
    return (Number(left ?? 0) - Number(right ?? 0)) * modifier
  }
  return String(left ?? '').localeCompare(String(right ?? '')) * modifier
}

function paginateReportRows(rows: Record<string, unknown>[], page: number, pageSize: number) {
  const safePage = Math.max(page, 1)
  const safePageSize = Math.min(Math.max(pageSize, 1), 100)
  const totalRows = rows.length
  return {
    data: rows.slice((safePage - 1) * safePageSize, safePage * safePageSize),
    pagination: {
      page: safePage,
      pageSize: safePageSize,
      totalRows,
      totalPages: totalRows === 0 ? 0 : Math.ceil(totalRows / safePageSize),
    },
  }
}

function reportPagination(page: number, pageSize: number, totalRows: number) {
  const safePage = Math.max(page, 1)
  const safePageSize = Math.min(Math.max(pageSize, 1), 100)
  return {
    page: safePage,
    pageSize: safePageSize,
    totalRows,
    totalPages: totalRows === 0 ? 0 : Math.ceil(totalRows / safePageSize),
  }
}

function normalizePledgeReportRows(pledges: Record<string, unknown>[]) {
  return pledges.map((pledge) => ({
    pledgeId: stringField(pledge, 'pledge_id'),
    eventMemberId: stringField(pledge, 'event_member_id'),
    member: stringField(pledge, 'member_name'),
    phone: stringField(pledge, 'phone_e164'),
    category: stringField(pledge, 'category'),
    pledged: numberField(pledge, 'pledged_amount'),
    paid: numberField(pledge, 'total_allocated'),
    outstanding: numberField(pledge, 'outstanding_amount'),
    dueDate: pledge['due_date'] ?? null,
    effectiveDueDate: pledge['effective_due_date'] ?? pledge['due_date'] ?? null,
    status: stringField(pledge, 'status', stringField(pledge, 'pledge_status')),
    lastPayment: pledge['last_payment_date'] ?? null,
  }))
}

function normalizePaymentReportRows(payments: Record<string, unknown>[]) {
  return payments.map((payment) => ({
    paymentId: stringField(payment, 'payment_id'),
    date: payment['payment_date'] ?? null,
    paymentNumber: stringField(payment, 'payment_number'),
    receiptNumber: stringField(payment, 'receipt_number'),
    eventMemberId: stringField(payment, 'event_member_id'),
    member: stringField(payment, 'member_name'),
    amount: numberField(payment, 'amount'),
    allocatedAmount: numberField(payment, 'allocated_amount'),
    unallocatedAmount: numberField(payment, 'unallocated_amount'),
    paymentMethod: stringField(payment, 'payment_method'),
    transactionReference: stringField(payment, 'transaction_reference'),
    receivedBy: stringField(payment, 'received_by_name', 'Unknown'),
    status: stringField(payment, 'status'),
  }))
}

function daysOverdue(effectiveDueDate: unknown) {
  if (typeof effectiveDueDate !== 'string' || !effectiveDueDate) return 0
  const due = new Date(`${effectiveDueDate.slice(0, 10)}T00:00:00.000Z`)
  if (Number.isNaN(due.getTime())) return 0
  const today = new Date()
  const todayUtc = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate())
  return Math.max(0, Math.floor((todayUtc - due.getTime()) / 86_400_000))
}

function shouldFallbackToCompatibilityReport(error: unknown) {
  const message = databaseMessage(error).toLowerCase()
  if (message.includes('session_required') || message.includes('access_denied') || message.includes('invalid_input')) {
    return false
  }
  return message.includes('schema cache') || message.includes('could not find') || message.includes('function') || message.includes('does not exist') || message.includes('report_get_failed') || message.length > 0
}

async function rpcJsonArray(client: ReturnType<typeof createUserSupabase>, name: string, args: Record<string, unknown>, fallbackCategory: string) {
  const { data, error } = await client.rpc(name, args)
  if (error) {
    throwFinancialDatabaseError(error, fallbackCategory)
  }
  return jsonArray(data)
}

async function rpcJsonRecord(client: ReturnType<typeof createUserSupabase>, name: string, args: Record<string, unknown>, fallbackCategory: string) {
  const { data, error } = await client.rpc(name, args)
  if (error) {
    throwFinancialDatabaseError(error, fallbackCategory)
  }
  return jsonRecord(data)
}

async function buildCompatibilityReport(client: ReturnType<typeof createUserSupabase>, tenantId: string, eventId: string, reportType: ReportType, input: ReportRequest) {
  const rpcArgs = { p_tenant_id: tenantId, p_event_id: eventId }
  const summary = await rpcJsonRecord(client, 'rpc_get_event_financial_summary', rpcArgs, 'REPORT_COMPAT_SUMMARY_FAILED')
  const members = await rpcJsonArray(client, 'rpc_list_event_members', rpcArgs, 'REPORT_COMPAT_MEMBERS_FAILED')
  const pledges = await rpcJsonArray(client, 'rpc_list_event_pledges', rpcArgs, 'REPORT_COMPAT_PLEDGES_FAILED')
  const payments = await rpcJsonArray(client, 'rpc_list_event_payments', rpcArgs, 'REPORT_COMPAT_PAYMENTS_FAILED')
  const normalizedPledges = normalizePledgeReportRows(pledges)
  const normalizedPayments = normalizePaymentReportRows(payments)

  if (reportType === 'summary') {
    const totalPledged = numberField(summary, 'totalPledged')
    const totalAllocated = numberField(summary, 'totalAllocatedToPledges')
    const enrichedSummary = {
      ...summary,
      totalReceived: summary['totalReceived'] ?? summary['totalConfirmedPayments'] ?? 0,
      collectionRate: totalPledged > 0 ? Math.round((totalAllocated / totalPledged) * 10_000) / 100 : 0,
      pledgeCoverageAgainstTarget: numberField(summary, 'eventTarget') > 0 ? Math.round((totalPledged / numberField(summary, 'eventTarget')) * 10_000) / 100 : 0,
    }
    return { data: [enrichedSummary], summary: enrichedSummary, pagination: reportPagination(1, 25, 1) }
  }

  if (reportType === 'pledges') {
    const sortKeys: Record<string, string> = { MEMBER: 'member', PLEDGED: 'pledged', PAID: 'paid', OUTSTANDING: 'outstanding', DUE_DATE: 'effectiveDueDate' }
    const filtered = normalizedPledges
      .filter((row) => input.status === 'ALL' || row.status === input.status)
      .filter((row) => !input.category || row.category === input.category)
      .filter((row) => !input.dueFrom || String(row.effectiveDueDate ?? '') >= input.dueFrom!)
      .filter((row) => !input.dueTo || String(row.effectiveDueDate ?? '') <= input.dueTo!)
      .filter((row) => matchesReportSearch(row, input, ['member', 'memberCode', 'phone']))
      .sort((a, b) => compareReportValues(a[sortKeys[input.sort] as keyof typeof a], b[sortKeys[input.sort] as keyof typeof b], input.direction))
    const paged = paginateReportRows(filtered, input.page, input.pageSize)
    return {
      data: paged.data,
      summary: {
        pledgeCount: filtered.length,
        totalPledged: filtered.reduce((sum, row) => sum + numberField(row, 'pledged'), 0),
        totalPaid: filtered.reduce((sum, row) => sum + numberField(row, 'paid'), 0),
        totalOutstanding: filtered.reduce((sum, row) => sum + numberField(row, 'outstanding'), 0),
      },
      pagination: paged.pagination,
    }
  }

  if (reportType === 'payments') {
    const sortKeys: Record<string, string> = { DATE: 'date', AMOUNT: 'amount', MEMBER: 'member' }
    const filtered = normalizedPayments
      .filter((row) => input.status === 'ALL' || row.status === input.status)
      .filter((row) => input.paymentMethod === 'ALL' || row.paymentMethod === input.paymentMethod)
      .filter((row) => !input.dateFrom || dateField(row, 'date') >= input.dateFrom!)
      .filter((row) => !input.dateTo || dateField(row, 'date') <= input.dateTo!)
      .filter((row) => matchesReportSearch(row, input, ['member', 'paymentNumber', 'receiptNumber', 'transactionReference']))
      .sort((a, b) => compareReportValues(a[sortKeys[input.sort] as keyof typeof a], b[sortKeys[input.sort] as keyof typeof b], input.direction))
    const paged = paginateReportRows(filtered, input.page, input.pageSize)
    return {
      data: paged.data,
      summary: {
        grossRecorded: filtered.reduce((sum, row) => sum + numberField(row, 'amount'), 0),
        reversed: filtered.filter((row) => row.status === 'REVERSED').reduce((sum, row) => sum + numberField(row, 'amount'), 0),
        netConfirmed: filtered.filter((row) => row.status === 'CONFIRMED').reduce((sum, row) => sum + numberField(row, 'amount'), 0),
      },
      pagination: paged.pagination,
    }
  }

  if (reportType === 'outstanding') {
    const sortKeys: Record<string, string> = { OUTSTANDING: 'outstanding', DAYS_OVERDUE: 'daysOverdue', DUE_DATE: 'effectiveDueDate', MEMBER: 'member' }
    const filtered = normalizedPledges
      .map((row) => ({ ...row, daysOverdue: daysOverdue(row.effectiveDueDate) }))
      .filter((row) => row.outstanding > 0)
      .filter((row) => !input.category || row.category === input.category)
      .filter((row) => input.filter === 'ALL' || (input.filter === 'OVERDUE' && row.daysOverdue > 0) || (input.filter === 'DUE_SOON' && row.daysOverdue === 0 && !!row.effectiveDueDate) || (input.filter === 'PARTIAL' && row.paid > 0) || (input.filter === 'UNPAID' && row.paid === 0))
      .sort((a, b) => compareReportValues(a[sortKeys[input.sort] as keyof typeof a], b[sortKeys[input.sort] as keyof typeof b], input.direction))
    const paged = paginateReportRows(filtered, input.page, input.pageSize)
    return {
      data: paged.data,
      summary: {
        totalOutstanding: filtered.reduce((sum, row) => sum + row.outstanding, 0),
        outstandingMembers: filtered.length,
        overdueMembers: filtered.filter((row) => row.daysOverdue > 0).length,
      },
      pagination: paged.pagination,
    }
  }

  if (reportType === 'payment-methods') {
    const methods = ['CASH', 'M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA', 'BANK_TRANSFER', 'CHEQUE', 'OTHER']
    const netConfirmedTotal = normalizedPayments.filter((row) => row.status === 'CONFIRMED').reduce((sum, row) => sum + row.amount, 0)
    const rows = methods.map((method) => {
      const methodPayments = normalizedPayments.filter((payment) => payment.paymentMethod === method)
      const netConfirmedAmount = methodPayments.filter((payment) => payment.status === 'CONFIRMED').reduce((sum, payment) => sum + payment.amount, 0)
      return {
        paymentMethod: method,
        paymentCount: methodPayments.length,
        grossAmount: methodPayments.reduce((sum, payment) => sum + payment.amount, 0),
        reversedAmount: methodPayments.filter((payment) => payment.status === 'REVERSED').reduce((sum, payment) => sum + payment.amount, 0),
        netConfirmedAmount,
        percentage: netConfirmedTotal > 0 ? Math.round((netConfirmedAmount / netConfirmedTotal) * 10_000) / 100 : 0,
      }
    })
    return { data: rows, summary: { netConfirmed: netConfirmedTotal }, pagination: reportPagination(1, 100, rows.length) }
  }

  if (reportType === 'collectors') {
    const filteredPayments = normalizedPayments
      .filter((row) => !input.dateFrom || dateField(row, 'date') >= input.dateFrom!)
      .filter((row) => !input.dateTo || dateField(row, 'date') <= input.dateTo!)
    const grouped = new Map<string, Record<string, unknown>>()
    for (const payment of filteredPayments) {
      const key = payment.receivedBy || 'Unknown'
      const current = grouped.get(key) ?? { collectorName: key, paymentCount: 0, grossRecorded: 0, reversed: 0, netCollected: 0, cash: 0, mobileMoney: 0, bank: 0, lastPaymentTime: null }
      current['paymentCount'] = numberField(current, 'paymentCount') + 1
      current['grossRecorded'] = numberField(current, 'grossRecorded') + payment.amount
      if (payment.status === 'REVERSED') current['reversed'] = numberField(current, 'reversed') + payment.amount
      if (payment.status === 'CONFIRMED') {
        current['netCollected'] = numberField(current, 'netCollected') + payment.amount
        if (payment.paymentMethod === 'CASH') current['cash'] = numberField(current, 'cash') + payment.amount
        if (['M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA'].includes(payment.paymentMethod)) current['mobileMoney'] = numberField(current, 'mobileMoney') + payment.amount
        if (payment.paymentMethod === 'BANK_TRANSFER') current['bank'] = numberField(current, 'bank') + payment.amount
      }
      if (!current['lastPaymentTime'] || String(payment.date ?? '') > String(current['lastPaymentTime'])) current['lastPaymentTime'] = payment.date
      grouped.set(key, current)
    }
    const rows = [...grouped.values()].sort((a, b) => compareReportValues(a['netCollected'], b['netCollected'], 'DESC'))
    return {
      data: rows,
      summary: {
        collectorCount: rows.length,
        netCollected: rows.reduce((sum, row) => sum + numberField(row, 'netCollected'), 0),
        grossRecorded: rows.reduce((sum, row) => sum + numberField(row, 'grossRecorded'), 0),
      },
      pagination: reportPagination(1, 100, rows.length),
    }
  }

  const memberCandidates = members
    .filter((member) => matchesReportSearch(member, input, ['full_name', 'member_code', 'phone_e164']))
    .map((member) => ({ eventMemberId: stringField(member, 'event_member_id'), name: stringField(member, 'full_name'), memberCode: stringField(member, 'member_code'), phone: stringField(member, 'phone_e164') }))
  const selectedMemberId = input.eventMemberId || memberCandidates[0]?.eventMemberId || ''
  const member = memberCandidates.find((candidate) => candidate.eventMemberId === selectedMemberId) ?? memberCandidates[0] ?? {}
  const pledge = normalizedPledges.find((row) => row.eventMemberId === selectedMemberId)
  const transactions = normalizedPayments
    .filter((payment) => payment.eventMemberId === selectedMemberId)
    .map((payment) => ({ date: payment.date, type: 'PAYMENT', receipt: payment.receiptNumber, method: payment.paymentMethod, amount: payment.amount, status: payment.status }))
    .sort((a, b) => compareReportValues(a.date, b.date, 'ASC'))
  return {
    data: transactions,
    members: memberCandidates,
    summary: {
      member,
      pledge: pledge ?? null,
      totalPledged: pledge?.pledged ?? 0,
      totalConfirmedPaid: normalizedPayments.filter((payment) => payment.eventMemberId === selectedMemberId && payment.status === 'CONFIRMED').reduce((sum, payment) => sum + payment.amount, 0),
      outstanding: pledge?.outstanding ?? 0,
      unallocatedCredit: normalizedPayments.filter((payment) => payment.eventMemberId === selectedMemberId && payment.status === 'CONFIRMED').reduce((sum, payment) => sum + payment.unallocatedAmount, 0),
    },
    pagination: reportPagination(1, 100, transactions.length),
  }
}

async function getEventReportResult(client: ReturnType<typeof createUserSupabase>, tenantId: string, eventId: string, reportType: ReportType, input: ReportRequest, requestId?: string) {
  const rpcArgs = { p_tenant_id: tenantId, p_event_id: eventId }
  const calls = {
    summary: () => client.rpc('rpc_get_event_collection_summary', rpcArgs),
    pledges: () => client.rpc('rpc_get_event_pledge_report', {
      ...rpcArgs,
      p_status: input.status,
      p_category: input.category || null,
      p_due_from: input.dueFrom || null,
      p_due_to: input.dueTo || null,
      p_search: input.search,
      p_sort: input.sort || 'MEMBER',
      p_direction: input.direction,
      p_page: input.page,
      p_page_size: input.pageSize,
    }),
    payments: () => client.rpc('rpc_get_event_payment_report', {
      ...rpcArgs,
      p_date_from: input.dateFrom || null,
      p_date_to: input.dateTo || null,
      p_payment_method: input.paymentMethod,
      p_collector: input.collectorId || null,
      p_status: input.status,
      p_search: input.search,
      p_sort: input.sort,
      p_direction: input.direction,
      p_page: input.page,
      p_page_size: input.pageSize,
    }),
    outstanding: () => client.rpc('rpc_get_event_outstanding_report', {
      ...rpcArgs,
      p_filter: input.filter,
      p_category: input.category || null,
      p_sort: input.sort || 'OUTSTANDING',
      p_direction: input.direction,
      p_page: input.page,
      p_page_size: input.pageSize,
    }),
    'payment-methods': () => client.rpc('rpc_get_event_payment_method_summary', rpcArgs),
    collectors: () => client.rpc('rpc_get_event_collector_report', {
      ...rpcArgs,
      p_date_from: input.dateFrom || null,
      p_date_to: input.dateTo || null,
      p_collector: input.collectorId || null,
    }),
    'member-statement': () => client.rpc('rpc_get_member_statement', {
      ...rpcArgs,
      p_event_member_id: input.eventMemberId || null,
      p_search: input.search,
    }),
  }
  const { data, error } = await calls[reportType]()
  if (error) {
    console.error('Report RPC failed', {
      requestId,
      tenantId,
      eventId,
      reportType,
      safeMessage: databaseMessage(error).slice(0, 200),
    })
    if (shouldFallbackToCompatibilityReport(error)) {
      return buildCompatibilityReport(client, tenantId, eventId, reportType, input)
    }
    throwFinancialDatabaseError(error, 'REPORT_GET_FAILED')
  }
  return jsonRecord(data)
}

function notificationFromEnqueue(data: unknown): Record<string, unknown> {
  const notification = jsonRecord(data)
  return Object.keys(notification).length ? notification : { smsQueued: false, reason: 'ENQUEUE_FAILED' }
}

function smsEnqueueFailureReason(error: unknown) {
  return databaseMessage(error).includes('SMS_CHARACTER_LIMIT_EXCEEDED') ? 'SMS_CHARACTER_LIMIT_EXCEEDED' : 'ENQUEUE_FAILED'
}

function parseSmsTemplateCodeParam(value: unknown): z.infer<typeof smsTemplateCodeSchema> {
  return smsTemplateCodeSchema.parse(String(value ?? '').trim().toUpperCase().replaceAll('-', '_'))
}

function normalizeSmsTemplateVariableName(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '')
}

function smsTemplateVariableAliases(code: SmsTemplateCode): Record<string, string> {
  const shared = {
    event: 'event_name',
    eventname: 'event_name',
    event_name: 'event_name',
    member: 'member_name',
    membername: 'member_name',
    member_name: 'member_name',
    name: 'member_name',
  }
  if (code === 'PAYMENT_CONFIRMATION') {
    return {
      ...shared,
      amount: 'payment_amount',
      balance: 'balance',
      outstanding: 'balance',
      payment: 'payment_amount',
      paymentamount: 'payment_amount',
      payment_amount: 'payment_amount',
      paymentmethod: 'payment_method',
      payment_method: 'payment_method',
      receipt: 'receipt_number',
      receiptno: 'receipt_number',
      receiptnumber: 'receipt_number',
      receipt_number: 'receipt_number',
    }
  }
  if (code === 'PLEDGE_REQUEST') {
    return {
      ...shared,
      deadline: 'pledge_deadline',
      eventdate: 'event_date',
      event_date: 'event_date',
      pledgedate: 'pledge_deadline',
      pledgedeadline: 'pledge_deadline',
      pledge_deadline: 'pledge_deadline',
    }
  }
  return {
    ...shared,
    amount: 'pledge_amount',
    balance: 'balance',
    due: 'due_date',
    duedate: 'due_date',
    due_date: 'due_date',
    outstanding: 'balance',
    pledge: 'pledge_amount',
    pledgeamount: 'pledge_amount',
    pledge_amount: 'pledge_amount',
  }
}

function normalizeSmsTemplateBody(code: SmsTemplateCode, body: string): string {
  if (/<[^>]+>/.test(body)) {
    throw new AppError('SMS_TEMPLATE_INVALID', 'SMS templates cannot contain HTML.')
  }
  const allowedVariables = smsTemplateAllowedVariablesByCode[code]
  const allowed = new Set(allowedVariables)
  const aliases = smsTemplateVariableAliases(code)
  const normalized = body.replace(/\{\{\s*([^{}]+?)\s*\}\}/g, (_match, rawVariable: string) => {
    const normalizedName = normalizeSmsTemplateVariableName(rawVariable)
    const compactName = normalizedName.replaceAll('_', '')
    const allowedVariable = aliases[normalizedName] ?? aliases[compactName] ?? allowedVariables.find((variable) => variable === normalizedName || variable.replaceAll('_', '') === compactName)
    if (!allowedVariable || !allowed.has(allowedVariable) || sensitiveSmsTemplateVariables.has(normalizedName) || sensitiveSmsTemplateVariables.has(compactName)) {
      throw new AppError('SMS_TEMPLATE_INVALID', `Unsupported SMS template variable: ${rawVariable.trim()}`)
    }
    return `{{${allowedVariable}}}`
  }).trim()
  if (normalized.length > 918) {
    throw new AppError('SMS_TEMPLATE_INVALID', 'SMS template is too long.')
  }
  return normalized
}

async function enqueuePledgeRegistrationSms(client: ReturnType<typeof createUserSupabase>, tenantId: string, eventId: string, pledgeId: string, requestId: string): Promise<Record<string, unknown>> {
  const enqueue = await client.rpc('rpc_enqueue_pledge_registration_sms', {
    p_tenant_id: tenantId,
    p_event_id: eventId,
    p_pledge_id: pledgeId,
  })
  if (enqueue.error) {
    console.error('Pledge registration SMS enqueue failed', {
      requestId,
      tenantId,
      eventId,
      pledgeId,
      safeMessage: databaseMessage(enqueue.error).slice(0, 160),
    })
    return { smsQueued: false, reason: smsEnqueueFailureReason(enqueue.error), template: 'PLEDGE_REGISTRATION' }
  }
  return notificationFromEnqueue(enqueue.data)
}

function previewIsValid(data: Record<string, unknown>): boolean {
  return data['valid'] === true
}

function validPreviewEventMemberIds(data: unknown): string[] {
  const record = jsonRecord(data)
  return jsonArray(record['previews'])
    .filter((preview) => preview['valid'] === true)
    .map((preview) => jsonRecord(preview['member'])['eventMemberId'])
    .filter((value): value is string => typeof value === 'string')
}

function generateBetaInvitationCode() {
  return `AHADI-BETA-${randomBytes(4).toString('base64url').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6)}`
}

function appContext(body: Record<string, unknown> | undefined) {
  return body ?? {}
}

async function ensureTenantFeatureEnabled(client: ReturnType<typeof createUserSupabase>, tenantId: string, featureKey: string) {
  const { data, error } = await client.rpc('has_feature', { p_tenant_id: tenantId, p_feature_key: featureKey })
  if (error) {
    throwFinancialDatabaseError(error, 'FEATURE_LOOKUP_FAILED')
  }
  if (data !== true) {
    throw new AppError('FEATURE_DISABLED', `${featureKey} is not enabled for this tenant`)
  }
}

function requireReportExportPermission(request: express.Request) {
  const permissions = new Set(request.tenantContext?.permissions ?? [])
  if (!permissions.has('reports.export') && !request.tenantContext?.membership?.isOwner) {
    throw new AppError('EXPORT_PERMISSION_DENIED', 'Report export permission is required')
  }
}

function exportRequestToReportInput(body: z.infer<typeof reportExportRequestSchema>) {
  return reportRequestSchema.parse({
    ...body.filters,
    ...(body.sort.field ? { sort: body.sort.field } : {}),
    ...(body.sort.direction ? { direction: body.sort.direction } : {}),
  })
}

function exportFilename(eventName: string, reportType: ReportType, extension: string, memberName?: string) {
  const today = new Date().toISOString().slice(0, 10)
  const eventSlug = safeFileSlug(eventName)
  const reportSlug = reportType === 'member-statement' ? `${safeFileSlug(memberName ?? 'member')}_statement` : safeFileSlug(reportType)
  return `ahadi_${eventSlug}_${reportSlug}_${today}.${extension}`
}

function exportMetadata(filtersApplied: ReportRequest, rowCount: number) {
  const redactedFilters = { ...filtersApplied, search: filtersApplied.search ? '<redacted-search>' : '' }
  return {
    filtersApplied: redactedFilters,
    rowCount,
  }
}

async function writeReportExportAudit(client: ReturnType<typeof createUserSupabase>, tenantId: string, eventId: string, reportType: ReportType, format: ReportExportFormat, rowCount: number, memberId?: string | null) {
  await client.rpc('write_audit_log', {
    p_tenant_id: tenantId,
    p_action: reportType === 'member-statement' ? 'MEMBER_STATEMENT_EXPORTED' : 'REPORT_EXPORTED',
    p_entity_type: 'report',
    p_entity_id: memberId || null,
    p_event_id: eventId,
    p_old_values: null,
    p_new_values: {
      reportType,
      format,
      rowCount,
    },
    p_reason: null,
  })
  await client.rpc('rpc_track_product_event', { p_event_name: 'REPORT_EXPORTED', p_tenant_id: tenantId, p_metadata: { eventId, reportType, format, rowCount, memberId: memberId ?? null } })
}

async function handleReportExport(request: express.Request, response: express.Response, reportType: ReportType, memberId?: string | null) {
  const tenantId = tenantIdFromRequest(request)
  const eventId = uuidParamSchema.parse(request.params['eventId'])
  requireReportExportPermission(request)
  const exportRequest = reportExportRequestSchema.parse(request.body ?? {})
  const supported = supportedExportFormats(reportType)
  if (!supported.includes(exportRequest.format)) {
    throw new AppError('REPORT_FORMAT_NOT_SUPPORTED', `${exportRequest.format} is not supported for ${reportExportTitle(reportType)}`)
  }
  const client = createUserSupabase(request.auth?.accessToken ?? '')
  await ensureTenantFeatureEnabled(client, tenantId, reportType === 'member-statement' ? 'member_statement_pdf' : 'report_exports')
  const limit = exportLimits[exportRequest.format]
  const reportInput = {
    ...exportRequestToReportInput(exportRequest),
    ...(memberId ? { eventMemberId: memberId } : {}),
    page: 1,
    pageSize: limit,
  }
  const report = await getEventReportResult(client, tenantId, eventId, reportType, reportInput, request.requestId)
  const rowCount = exportRows(report).length
  const totalRows = Number(jsonRecord(report['pagination'])['totalRows'] ?? rowCount)
  if (totalRows > limit) {
    throw new AppError('REPORT_EXPORT_TOO_LARGE', `Export has ${totalRows} rows. Narrow filters and try again.`, 413, JSON.stringify({ limit, filteredRows: totalRows }))
  }
  const event = request.tenantContext?.events.find((candidate) => candidate.id === eventId)
  const summary = jsonRecord(report['summary'])
  const member = jsonRecord(summary['member'])
  if (reportType === 'member-statement' && memberId && !Object.keys(member).length) {
    throw new AppError('MEMBER_STATEMENT_NOT_FOUND', 'Member statement was not found')
  }
  const document = createExportDocument({
    eventName: event?.name ?? 'Event',
    filtersApplied: reportInput,
    format: exportRequest.format,
    generatedAt: new Date(),
    generatedBy: request.auth?.context?.profile?.fullName ?? request.auth?.user.phone ?? 'Ahadi user',
    report,
    reportType,
    tenantName: request.tenantContext?.tenant.name ?? 'Ahadi',
  })
  const filename = exportFilename(event?.name ?? 'event', reportType, document.extension, typeof member['name'] === 'string' ? member['name'] : undefined)
  await writeReportExportAudit(client, tenantId, eventId, reportType, exportRequest.format, rowCount, memberId)
  response.setHeader('Content-Type', document.contentType)
  response.setHeader('Content-Disposition', `attachment; filename="${filename}"`)
  response.setHeader('X-Ahadi-Export-Metadata', JSON.stringify(exportMetadata(reportInput, rowCount)))
  response.send(document.body)
}

app.use(helmet())
app.use(requestIdMiddleware)
app.use(requestTraceMiddleware)
app.post('/auth/hooks/send-sms', sendSmsHookLimiter, express.raw({ type: 'application/json', limit: '64kb' }), sendSmsHookHandler)
app.post('/api/v1/webhooks/billing/test', express.raw({ type: 'application/json', limit: '128kb' }), async (request, response, next) => {
  try {
    const gateway = getBillingGateway('TEST')
    const rawBody = Buffer.isBuffer(request.body) ? request.body : Buffer.from('')
    const signature = request.header('X-Ahadi-Test-Signature') ?? null
    const signatureValid = await gateway.verifyWebhook({ rawBody, signature })
    const payloadHash = createHash('sha256').update(rawBody).digest('hex')
    if (!signatureValid) {
      console.warn('Billing webhook rejected', { requestId: request.requestId, provider: 'TEST', payloadHash })
      throw new AppError('PAYMENT_WEBHOOK_INVALID')
    }
    const parsed = await gateway.parseWebhook(rawBody)
    const result = jsonRecord(await (parsed.status === 'REVERSED' ? confirmParsedGatewayReversal(supabasePublic, parsed) : confirmParsedGatewayPayment(supabasePublic, parsed)))
    const resultCode = typeof result['code'] === 'string' ? result['code'] : null
    if (resultCode && knownDatabaseCodes.includes(resultCode as ApiErrorCode)) {
      throw new AppError(resultCode as ApiErrorCode)
    }
    response.json({ ok: true, data: result })
  } catch (error) {
    next(error)
  }
})
app.use(
  cors({
    origin: corsOrigin,
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Tenant-ID', 'X-Request-ID', 'Cache-Control', 'Pragma'],
  }),
)
app.use(express.json({ limit: '1mb' }))
app.use('/api/v1', (_request, response, next) => {
  response.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  response.setHeader('Pragma', 'no-cache')
  response.setHeader('Expires', '0')
  response.setHeader('Surrogate-Control', 'no-store')
  next()
})
app.use(
  morgan(env.NODE_ENV === 'production' ? 'combined' : 'dev', {
    skip: (request) => request.path.startsWith('/api/v1/auth/verify'),
  }),
)

app.get('/health', (_request, response) => {
  response.json(healthPayload())
})

app.get('/api/v1/health', (_request, response) => {
  response.json(healthPayload())
})

if (env.NODE_ENV === 'development') {
  app.get('/api/v1/dev/auth-sms-status', (_request, response) => {
    const rawHookSecret = env.SEND_SMS_HOOK_SECRET.trim()
    response.json({
      phoneProviderConfigurationPresent: Boolean(env.SUPABASE_URL && env.supabasePublishableKey),
      hookSecretConfigured: Boolean(rawHookSecret),
      hookSecretFormatValid: rawHookSecret.startsWith('v1,whsec_') || rawHookSecret.startsWith('whsec_'),
      smsProviderUrlConfigured: Boolean(env.SMS_PROVIDER_URL),
      smsUsernameConfigured: Boolean(env.SMS_USERNAME),
      smsPasswordConfigured: Boolean(env.SMS_PASSWORD),
      smsSenderIdConfigured: Boolean(env.SMS_SENDER_ID),
      trustProxyHops: env.TRUST_PROXY_HOPS,
    })
  })
}

app.post('/api/v1/auth/request-otp', strictLimiter, async (request, response, next) => {
  try {
    logOtpDiagnostic(console, 'OTP_REQUEST_RECEIVED', { requestId: request.requestId, route: '/api/v1/auth/request-otp' })
    const parsedInput = requestOtpSchema.safeParse(request.body)
    if (!parsedInput.success) {
      logOtpDiagnostic(console, 'PHONE_VALIDATION_FAILED', { requestId: request.requestId })
      throw new AppError('INVALID_INPUT', 'Request validation failed', 400)
    }
    const input = parsedInput.data
    logOtpDiagnostic(console, 'PHONE_NORMALIZED', { requestId: request.requestId, phone: maskPhoneForLog(input.phone) })
    logOtpDiagnostic(console, 'SUPABASE_OTP_REQUEST_STARTED', { requestId: request.requestId, phone: maskPhoneForLog(input.phone) })
    const { error } = await supabasePublic.auth.signInWithOtp({
      phone: input.phone,
      options: {
        channel: 'sms',
      },
    })
    if (error) {
      logProviderError(request.requestId, 'request-otp', error)
      const classification = classifySupabaseOtpError(error)
      logOtpDiagnostic(console, classification.stage, {
        requestId: request.requestId,
        providerName: getProviderName(error),
        providerStatus: getProviderStatus(error),
        providerCode: getProviderCode(error),
        retryable: isRetryableSupabaseError(error),
        safeMessage: getSafeProviderMessage(error),
      })
      if (getProviderStatus(error) === 429) {
        throw new AppError('RATE_LIMITED', 'Too many attempts. Try again shortly.', 429, classification.category)
      }
      throw new AppError('OTP_REQUEST_FAILED', 'Unable to send verification code. Check Supabase phone auth and SMS provider configuration.', 502, classification.category)
    }
    logOtpDiagnostic(console, 'SUPABASE_OTP_REQUEST_COMPLETED', { requestId: request.requestId, phone: maskPhoneForLog(input.phone) })
    response.json({ ok: true })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/auth/verify-otp', strictLimiter, async (request, response, next) => {
  try {
    const input = verifyOtpSchema.parse(request.body)
    const { data, error } = await supabasePublic.auth.verifyOtp({
      phone: input.phone,
      token: input.token,
      type: 'sms',
    })
    if (error || !data.session) {
      throw new AppError('INVALID_OTP')
    }
    response.json({ session: data.session, user: data.user })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/auth/set-pin', requireAuth, async (request, response, next) => {
  try {
    const parsedInput = setupPinSchema.safeParse(request.body)
    if (!parsedInput.success) {
      const classification = classifyPinSetupValidationError(parsedInput.error)
      throw new AppError(classification.code, classification.message, classification.status, classification.category)
    }
    const input = parsedInput.data
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_set_my_pin', { p_pin: input.pin })
    if (error) {
      if (env.NODE_ENV === 'development') {
        console.error('PIN database error', getSafePinDatabaseErrorDetails(request.requestId, 'set-pin', error))
      }
      const classification = classifyPinSetupDatabaseError(error, Boolean(request.auth?.user))
      throw new AppError(classification.code, classification.message, classification.status, classification.category)
    }
    response.json(data)
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/auth/verify-pin', strictLimiter, requireAuth, async (request, response, next) => {
  try {
    const input = verifyPinSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_verify_my_pin', { p_pin: input.pin })
    if (error) {
      throw error
    }
    response.json(data)
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/auth/has-pin', requireAuth, async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_has_my_pin')
    if (error) {
      throw error
    }
    response.json({ hasPin: Boolean(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/auth/logout', requireAuth, async (_request, response) => {
  response.json({ ok: true })
})

app.get('/api/v1/plans', async (_request, response, next) => {
  try {
    const { data, error } = await supabasePublic
      .from('subscription_plans')
      .select('*')
      .eq('is_active', true)
      .eq('is_public', true)
      .order('display_order')
    if (error) {
      throw error
    }
    response.json({ data: (data ?? []).map((plan) => toSubscriptionPlan(plan as SubscriptionPlanRow)) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/rollout-settings', async (_request, response, next) => {
  try {
    const { data, error } = await supabasePublic.rpc('rpc_get_rollout_settings_public')
    if (error) {
      throw error
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/version', async (_request, response, next) => {
  try {
    const { data, error } = await supabasePublic.rpc('rpc_get_rollout_settings_public')
    if (error) {
      throw error
    }
    const settings = jsonRecord(data)
    response.json({
      data: {
        appVersion: env.APP_VERSION,
        webVersion: settings['webVersion'] ?? env.APP_VERSION,
        apiVersion: settings['apiVersion'] ?? env.APP_VERSION,
        releaseChannel: settings['releaseChannel'] ?? 'BETA',
        minimumSupportedWebVersion: settings['minimumSupportedWebVersion'] ?? null,
      },
    })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/onboarding/complete', requireAuth, async (request, response, next) => {
  try {
    const parsedInput = onboardingPayloadSchema.safeParse(request.body)
    if (!parsedInput.success) {
      logValidationError(request.requestId, 'onboarding-complete', parsedInput.error)
      throw new AppError('INVALID_INPUT', 'Request validation failed', 400)
    }
    const input = parsedInput.data
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const rollout = await supabasePublic.rpc('rpc_get_rollout_settings_public')
    if (rollout.error) {
      throw rollout.error
    }
    const rolloutSettings = jsonRecord(rollout.data)
    const registrationMode = String(rolloutSettings['registrationMode'] ?? 'OPEN')
    if (registrationMode === 'PAUSED') {
      throw new AppError('REGISTRATION_PAUSED', 'New workspace registration is temporarily paused', 503)
    }
    if (registrationMode === 'INVITE_ONLY') {
      if (!input.betaInvitationCode) {
        throw new AppError('INVITATION_REQUIRED', 'A beta invitation code is required', 403)
      }
      const validated = await supabasePublic.rpc('rpc_validate_beta_invitation', {
        p_code: input.betaInvitationCode,
        p_phone_e164: request.auth?.user?.phone ?? null,
      })
      if (validated.error) {
        throw validated.error
      }
      const validation = jsonRecord(validated.data)
      if (validation['valid'] !== true) {
        throw new AppError('INVITATION_INVALID', String(validation['reason'] ?? 'Invitation code is invalid'), 403)
      }
    }
    const { data, error } = await client.rpc('rpc_complete_tenant_onboarding', {
      p_plan_code: input.planCode,
      p_tenant_name: input.tenantName,
      p_tenant_phone: input.tenantPhone,
      p_first_event_name: input.firstEventName,
      p_event_type: input.eventType,
      p_idempotency_key: input.idempotencyKey,
      ...(input.tenantEmail ? { p_tenant_email: input.tenantEmail } : {}),
      ...(input.eventDate ? { p_event_date: input.eventDate } : {}),
      ...(input.venue ? { p_venue: input.venue } : {}),
      ...(input.targetAmount !== null && input.targetAmount !== undefined ? { p_target_amount: input.targetAmount } : {}),
      ...(input.pledgeDeadline ? { p_pledge_deadline: input.pledgeDeadline } : {}),
    })
    if (error) {
      if (env.NODE_ENV === 'development') {
        console.error('Onboarding database error', getSafeOnboardingDatabaseErrorDetails(request.requestId, 'onboarding-complete', error))
      }
      const classification = classifyOnboardingDatabaseError(error, Boolean(request.auth?.user))
      throw new AppError(classification.code, classification.message, classification.status, classification.category)
    }
    const resultRecord = jsonRecord(data)
    const tenantId = typeof resultRecord['tenant_id'] === 'string' ? resultRecord['tenant_id'] : typeof resultRecord['tenantId'] === 'string' ? resultRecord['tenantId'] : null
    if (input.betaInvitationCode && tenantId) {
      const consume = await client.rpc('rpc_consume_beta_invitation', { p_code: input.betaInvitationCode, p_tenant_id: tenantId })
      if (consume.error) {
        console.error('Beta invitation consume failed', {
          requestId: request.requestId,
          tenantId,
          safeMessage: databaseMessage(consume.error).slice(0, 160),
        })
      }
    }
    if (tenantId) {
      await client.rpc('rpc_track_product_event', { p_event_name: 'TENANT_CREATED', p_tenant_id: tenantId, p_metadata: { source: 'onboarding' } })
      await client.rpc('rpc_track_product_event', { p_event_name: 'ONBOARDING_COMPLETED', p_tenant_id: tenantId, p_metadata: { source: 'onboarding' } })
    }
    response.json(data)
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/me', requireAuth, loadUserContext, (request, response) => {
  response.json({ data: request.auth?.context })
})

app.get('/api/v1/tenant-context', requireAuth, loadUserContext, requireTenantContext, (request, response) => {
  response.json({ data: request.tenantContext })
})

app.get('/api/v1/billing/summary', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const [invoices, payments, pendingIntents, gatewaySettings] = await Promise.all([
      optionalBillingRows(request, 'subscription-billing-invoices-list', client.from('subscription_invoices').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false })),
      optionalBillingRows(request, 'subscription-billing-payments-list', client.from('subscription_payments').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false })),
      optionalBillingRows(
        request,
        'subscription-billing-payment-intents-list',
        client.from('subscription_payment_intents').select('*').eq('tenant_id', tenantId).in('status', ['CREATED', 'PENDING', 'PROCESSING']).order('created_at', { ascending: false }),
      ),
      optionalBillingRows(request, 'subscription-gateway-settings-list', client.from('subscription_gateway_settings').select('*').order('provider', { ascending: true })),
    ])
    response.json({
      data: {
        subscription: request.tenantContext?.subscription ?? null,
        invoices,
        payments,
        pendingIntents,
        gateways: gatewaySettings.length ? gatewaySettings : listBillingGatewayCapabilities(),
      },
    })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/billing/invoices/:invoiceId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const invoiceId = uuidParamSchema.parse(request.params['invoiceId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client
      .from('subscription_invoices')
      .select('*')
      .eq('tenant_id', tenantId)
      .eq('id', invoiceId)
      .maybeSingle()
    if (error) {
      logDatabaseError(request.requestId, 'subscription-invoice-read', error, { tenantId, invoiceId })
      if (isMissingBillingFoundationError(error)) {
        throw new AppError('INVOICE_NOT_PAYABLE', 'Subscription billing tables are not available')
      }
      throwFinancialDatabaseError(error, 'SUBSCRIPTION_INVOICE_READ_FAILED')
    }
    const invoice = jsonRecord(data)
    if (!Object.keys(invoice).length) {
      throw new AppError('INVOICE_NOT_PAYABLE', 'Subscription invoice was not found')
    }
    const items = await optionalBillingRows(
      request,
      'subscription-invoice-items-list',
      client.from('subscription_invoice_items').select('*').eq('tenant_id', tenantId).eq('invoice_id', invoiceId).order('created_at', { ascending: true }),
    )
    response.json({ data: { ...invoice, subscription_invoice_items: items } })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/billing/invoices/:invoiceId/payment-intents', paymentIntentLimiter, requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const permissions = new Set(request.tenantContext?.permissions ?? [])
    if (!request.tenantContext?.membership?.isOwner && !permissions.has('tenant.subscription.manage')) {
      throw new AppError('PERMISSION_DENIED', 'Only tenant owners can initiate subscription payments')
    }
    const invoiceId = uuidParamSchema.parse(request.params['invoiceId'])
    const input = createSubscriptionPaymentIntentSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const profile = request.auth?.context?.profile
    const result = await createSubscriptionPaymentIntent(client, {
      tenantId,
      invoiceId,
      provider: input.provider,
      paymentMethod: input.paymentMethod,
      customerName: profile?.fullName || request.tenantContext?.tenant.name || 'Ahadi tenant',
      customerPhone: profile?.phoneE164 || request.tenantContext?.tenant.phoneE164 || '',
      customerEmail: profile?.email || request.tenantContext?.tenant.email || null,
      returnUrl: input.returnUrl ?? null,
      idempotencyKey: input.idempotencyKey,
    })
    response.status(201).json({ data: jsonRecord(result) })
  } catch (error) {
    if (isMissingBillingFoundationError(error)) {
      next(new AppError('PAYMENT_PROVIDER_UNAVAILABLE', 'Subscription billing migration is not available'))
      return
    }
    next(error)
  }
})

app.get('/api/v1/billing/payment-intents/:intentId', paymentIntentLimiter, requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const intentId = uuidParamSchema.parse(request.params['intentId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client
      .from('subscription_payment_intents')
      .select('*')
      .eq('tenant_id', tenantId)
      .eq('id', intentId)
      .maybeSingle()
    if (error) {
      logDatabaseError(request.requestId, 'subscription-payment-intent-read', error, { tenantId, intentId })
      if (isMissingBillingFoundationError(error)) {
        throw new AppError('PAYMENT_INTENT_NOT_FOUND')
      }
      throwFinancialDatabaseError(error, 'PAYMENT_INTENT_READ_FAILED')
    }
    const intent = jsonRecord(data)
    if (!Object.keys(intent).length) {
      throw new AppError('PAYMENT_INTENT_NOT_FOUND')
    }
    const invoiceId = stringField(intent, 'invoice_id')
    const invoiceRows = invoiceId
      ? await optionalBillingRows(request, 'subscription-payment-intent-invoice-read', client.from('subscription_invoices').select('id, invoice_number, status').eq('tenant_id', tenantId).eq('id', invoiceId).limit(1))
      : []
    const invoice = invoiceRows[0] ?? {}
    const expiresAt = typeof intent['expires_at'] === 'string' ? intent['expires_at'] : null
    const computedStatus = ['PENDING', 'PROCESSING'].includes(stringField(intent, 'status')) && expiresAt && new Date(expiresAt).getTime() < Date.now()
      ? 'EXPIRED'
      : stringField(intent, 'status', 'PENDING')
    response.json({
      data: {
        ...intent,
        tenantId: intent['tenant_id'],
        invoiceId: intent['invoice_id'],
        invoiceNumber: invoice['invoice_number'],
        status: computedStatus,
        amount: intent['requested_amount'],
        currency: intent['currency'],
        checkoutUrl: intent['checkout_url'],
        controlNumber: intent['control_number'],
        paymentInstructions: jsonRecord(intent['metadata'])['paymentInstructions'] ?? null,
        expiresAt: intent['expires_at'],
        lastCheckedAt: new Date().toISOString(),
        invoiceStatus: invoice['status'] ?? null,
      },
    })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/features', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_feature_flags', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'FEATURES_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/support', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'support_requests')
    const { data, error } = await client.rpc('rpc_list_my_support_requests', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'SUPPORT_REQUESTS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/support', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const input = supportRequestSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'support_requests')
    const { data, error } = await client.rpc('rpc_create_support_request', {
      p_app_context: appContext(input.appContext),
      p_category: input.category,
      p_contact_preference: input.contactPreference ?? null,
      p_description: input.description,
      p_event_id: input.eventId ?? null,
      p_subject: input.subject,
      p_tenant_id: tenantId,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SUPPORT_REQUEST_CREATE_FAILED')
    }
    response.status(201).json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/feedback', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const input = feedbackSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_create_feedback', {
      p_app_context: appContext(input.appContext),
      p_category: input.category,
      p_event_id: input.eventId ?? null,
      p_message: input.message,
      p_page: input.page ?? null,
      p_tenant_id: tenantId,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'FEEDBACK_CREATE_FAILED')
    }
    response.status(201).json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/errors/report', requireAuth, loadUserContext, async (request, response, next) => {
  try {
    const input = frontendErrorReportSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_report_frontend_error', {
      p_app_version: input.appVersion ?? null,
      p_browser_summary: input.browserSummary ?? null,
      p_component: input.component ?? null,
      p_error_code: input.errorCode ?? null,
      p_metadata: appContext(input.metadata),
      p_request_id: input.requestId ?? null,
      p_route: input.route ?? null,
      p_tenant_id: input.tenantId ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'FRONTEND_ERROR_REPORT_FAILED')
    }
    response.status(201).json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    logEventCreateStage(request, 'EVENT_CREATE_START')
    logEventCreateStage(request, 'EVENT_CREATE_AUTH_OK')
    logEventCreateStage(request, 'EVENT_CREATE_TENANT_OK')
    const permissions = new Set(request.tenantContext?.permissions ?? [])
    if (!permissions.has('events.create') && !request.tenantContext?.membership?.isOwner) {
      throw new AppError('PERMISSION_DENIED', 'Missing permission: events.create')
    }
    logEventCreateStage(request, 'EVENT_CREATE_PERMISSION_OK')
    if (request.tenantContext?.accessState === 'READ_ONLY') {
      throw new AppError('SUBSCRIPTION_READ_ONLY', 'Subscription is read-only')
    }
    logEventCreateStage(request, 'EVENT_CREATE_SUBSCRIPTION_OK')
    const parsedInput = createEventSchema.safeParse(request.body)
    if (!parsedInput.success) {
      logValidationError(request.requestId, 'event-create', parsedInput.error)
      throw parsedInput.error
    }
    const input = normalizeCreateEventInput(parsedInput.data)
    logEventCreateStage(request, 'EVENT_CREATE_VALIDATION_OK', {
      eventType: input.eventType,
      optionalFieldsNull: {
        customEventType: input.customEventType === null,
        eventDate: input.eventDate === null,
        pledgeDeadline: input.pledgeDeadline === null,
        targetAmount: input.targetAmount === null,
        venue: input.venue === null,
      },
    })
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const slotCheck = await client.rpc('event_slot_usage', { p_tenant_id: tenantId })
    let slotSummary: ReturnType<typeof eventSlotSummary> | null = null
    if (slotCheck.error) {
      logDatabaseError(request.requestId, 'event-slot-usage-precheck', slotCheck.error, {
        tenantId,
        userId: request.auth?.user.id,
        stage: 'EVENT_CREATE_SLOT_CHECK_FAILED',
      })
    } else {
      slotSummary = eventSlotSummary(slotCheck.data)
      logEventCreateStage(request, 'EVENT_CREATE_SLOT_CHECK_OK', slotSummary)
      const available = slotSummary.availableEventSlots ?? availableEventSlots(slotCheck.data)
      if (available !== null && available <= 0) {
        throw new AppError('EVENT_LIMIT_REACHED', 'Your current package has no available active event slots')
      }
    }
    const rpcInput = {
      p_tenant_id: tenantId,
      p_name: input.name,
      p_event_type: input.eventType,
      p_custom_event_type: input.customEventType,
      p_event_date: input.eventDate,
      p_venue: input.venue,
      p_target_amount: input.targetAmount,
      p_pledge_deadline: input.pledgeDeadline,
    }
    logEventCreateStage(request, 'EVENT_CREATE_DB_START', {
      eventType: input.eventType,
      hasCustomEventType: Boolean(input.customEventType),
      hasEventDate: Boolean(input.eventDate),
      hasPledgeDeadline: Boolean(input.pledgeDeadline),
      hasTargetAmount: input.targetAmount !== null,
      hasVenue: Boolean(input.venue),
      ...(slotSummary ?? {}),
    })
    let { data, error } = await client.rpc('rpc_create_event_v2', rpcInput)
    if (error && shouldRetryV2CreateEvent(error)) {
      logDatabaseError(request.requestId, 'event-create-v2-schema-cache', error, {
        tenantId,
        userId: request.auth?.user.id,
        stage: 'EVENT_CREATE_DB_START',
      })
      const current = await client.rpc('rpc_create_event', rpcInput)
      data = current.data
      error = current.error
    }
    if (error && shouldUseDirectEventCreateFallback(error)) {
      logDatabaseError(request.requestId, 'event-create-v2-ambiguous-column', error, {
        tenantId,
        userId: request.auth?.user.id,
        stage: 'EVENT_CREATE_DB_FAILED_WITH_KNOWN_RPC_AMBIGUITY',
        ...(slotSummary ?? {}),
      })
      data = await createEventWithDirectFallback(client, request, tenantId, input, slotSummary)
      error = null
    }
    if (error && shouldRetryLegacyCreateEvent(error)) {
      const legacy = await client.rpc('rpc_create_event', {
        p_tenant_id: tenantId,
        p_name: input.name,
        p_event_type: input.eventType,
        p_event_date: input.eventDate,
        p_venue: input.venue,
        p_target_amount: input.targetAmount,
        p_pledge_deadline: input.pledgeDeadline,
      })
      data = legacy.data
      error = legacy.error
    }
    if (error && shouldUseDirectEventCreateFallback(error)) {
      logDatabaseError(request.requestId, 'event-create-legacy-ambiguous-column', error, {
        tenantId,
        userId: request.auth?.user.id,
        stage: 'EVENT_CREATE_DB_FAILED_WITH_KNOWN_RPC_AMBIGUITY',
        ...(slotSummary ?? {}),
      })
      data = await createEventWithDirectFallback(client, request, tenantId, input, slotSummary)
      error = null
    }
    if (error) {
      logDatabaseError(request.requestId, 'event-create', error, {
        tenantId,
        userId: request.auth?.user.id,
        stage: 'EVENT_CREATE_FAILED',
        ...(slotSummary ?? {}),
      })
      throwFinancialDatabaseError(error, 'EVENT_CREATE_FAILED')
    }
    logEventCreateStage(request, 'EVENT_CREATE_DB_SUCCESS', {
      eventId: stringField(jsonRecord(data), 'eventId', stringField(jsonRecord(data), 'id')),
      eventCode: stringField(jsonRecord(data), 'code', stringField(jsonRecord(data), 'event_code')),
    })
    logEventCreateStage(request, 'EVENT_CREATE_ASSIGNMENT_SUCCESS')
    logEventCreateStage(request, 'EVENT_CREATE_AUDIT_SUCCESS')
    logEventCreateStage(request, 'EVENT_CREATE_COMPLETE', {
      eventId: stringField(jsonRecord(data), 'eventId', stringField(jsonRecord(data), 'id')),
      eventCode: stringField(jsonRecord(data), 'code', stringField(jsonRecord(data), 'event_code')),
    })
    response.status(201).json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/dashboard', requireAuth, loadUserContext, requirePlatformPermission('platform.dashboard.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_platform_dashboard')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_DASHBOARD_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/tenants', requireAuth, loadUserContext, requirePlatformPermission('platform.tenants.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_platform_tenants')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_TENANTS_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/tenants/:tenantId', requireAuth, loadUserContext, requirePlatformPermission('platform.tenants.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const tenantId = tenantContextHeaderSchema.shape.tenantId.parse(request.params['tenantId'])
    const { data, error } = await client.rpc('rpc_get_platform_tenant_detail', { p_tenant_id: tenantId })
    if (error) {
      throw error
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/platform/tenants/:tenantId/trial/extend', requireAuth, loadUserContext, requirePlatformPermission('platform.subscriptions.manage'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const tenantId = tenantContextHeaderSchema.shape.tenantId.parse(request.params['tenantId'])
    const input = tenantTrialExtensionSchema.parse(request.body)
    const { data, error } = await client.rpc('rpc_extend_tenant_trial', { p_tenant_id: tenantId, p_days: input.days, p_reason: input.reason })
    if (error) {
      throwFinancialDatabaseError(error, 'SUBSCRIPTION_INACTIVE')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/platform/tenants/:tenantId/support-session', requireAuth, loadUserContext, requirePlatformPermission('platform.support_session.start'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const tenantId = tenantContextHeaderSchema.shape.tenantId.parse(request.params['tenantId'])
    const input = supportAccessSessionSchema.parse(request.body)
    const { data, error } = await client.rpc('rpc_start_support_access_session', {
      p_minutes: input.durationMinutes ?? 60,
      p_reason: input.reason,
      p_scope: 'TENANT_CONFIGURATION',
      p_tenant_id: tenantId,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SUPPORT_ACCESS_SESSION_FAILED')
    }
    response.status(201).json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/plans', requireAuth, loadUserContext, requirePlatformPermission('platform.plans.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_platform_plans')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_PLANS_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/billing/gateways', requireAuth, loadUserContext, requirePlatformPermission('platform.gateway.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_platform_gateway_settings')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_GATEWAYS_FAILED')
    }
    const databaseCapabilities = Array.isArray(data) ? data : []
    response.json({
      data: {
        configuredProvider: env.GATEWAY_PROVIDER,
        environment: env.GATEWAY_ENVIRONMENT,
        adapters: listBillingGatewayCapabilities(),
        databaseCapabilities,
      },
    })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/billing/reconciliation', requireAuth, loadUserContext, requirePlatformPermission('platform.reconciliation.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_platform_gateway_reconciliation')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_RECONCILIATION_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/sms/providers', requireAuth, loadUserContext, requirePlatformPermission('platform.sms.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_platform_sms_providers')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_SMS_PROVIDERS_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.patch('/api/v1/platform/sms/providers/:providerCode', requireAuth, loadUserContext, requirePlatformPermission('platform.sms.manage'), async (request, response, next) => {
  try {
    const providerCode = String(request.params['providerCode'] ?? '').trim().toUpperCase()
    const input = platformSmsProviderUpdateSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_update_platform_sms_provider', {
      p_provider_code: providerCode,
      p_status: input.status ?? null,
      p_is_default: input.isDefault ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_SMS_PROVIDER_UPDATE_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.patch('/api/v1/platform/sms/providers/:providerCode/sender-ids/:senderId', requireAuth, loadUserContext, requirePlatformPermission('platform.sms.manage'), async (request, response, next) => {
  try {
    const providerCode = String(request.params['providerCode'] ?? '').trim().toUpperCase()
    const senderId = String(request.params['senderId'] ?? '').trim().toUpperCase()
    const input = platformSmsSenderUpdateSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_update_platform_sms_sender_id', {
      p_provider_code: providerCode,
      p_sender_id: senderId,
      p_status: input.status ?? null,
      p_is_default: input.isDefault ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_SMS_SENDER_UPDATE_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/beta', requireAuth, loadUserContext, requirePlatformPermission('platform.beta.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_platform_beta_dashboard')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.put('/api/v1/platform/beta/settings', requireAuth, loadUserContext, requirePlatformPermission('platform.beta.manage'), async (request, response, next) => {
  try {
    const input = rolloutSettingsSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_update_rollout_settings', {
      p_beta_mode_enabled: input.betaModeEnabled ?? null,
      p_default_trial_days: input.defaultTrialDays ?? null,
      p_maintenance_mode: input.maintenanceMode ?? null,
      p_maintenance_notice: input.maintenanceNotice ?? null,
      p_minimum_supported_web_version: input.minimumSupportedWebVersion ?? null,
      p_registration_mode: input.registrationMode,
      p_support_email: input.supportEmail ?? null,
      p_support_phone: input.supportPhone ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/platform/beta/invitations', requireAuth, loadUserContext, requirePlatformPermission('platform.beta.manage'), async (request, response, next) => {
  try {
    const input = betaInvitationCreateSchema.parse(request.body)
    const code = generateBetaInvitationCode()
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_create_beta_invitation', {
      p_code: code,
      p_expires_at: input.expiresAt ?? null,
      p_intended_email: input.intendedEmail ?? null,
      p_intended_name: input.intendedName ?? null,
      p_intended_phone_e164: input.intendedPhone ?? null,
      p_max_uses: input.maxUses ?? 1,
      p_plan_id: input.planId ?? null,
      p_trial_days_override: input.trialDaysOverride ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.status(201).json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/platform/beta/invitations/:invitationId/revoke', requireAuth, loadUserContext, requirePlatformPermission('platform.beta.manage'), async (request, response, next) => {
  try {
    const invitationId = uuidParamSchema.parse(request.params['invitationId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_revoke_beta_invitation', { p_invitation_id: invitationId })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/support', requireAuth, loadUserContext, requirePlatformPermission('platform.support.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_platform_support_requests')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/platform/support/:supportRequestId', requireAuth, loadUserContext, requirePlatformPermission('platform.support.manage'), async (request, response, next) => {
  try {
    const supportRequestId = uuidParamSchema.parse(request.params['supportRequestId'])
    const input = supportRequestUpdateSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_update_support_request', {
      p_assigned_platform_user_id: input.assignedTo ?? null,
      p_note: input.note ?? null,
      p_priority: input.priority ?? null,
      p_request_id: supportRequestId,
      p_status: input.status ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SUPPORT_REQUEST_UPDATE_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/feedback', requireAuth, loadUserContext, requirePlatformPermission('platform.feedback.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_platform_feedback')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/features', requireAuth, loadUserContext, requirePlatformPermission('platform.features.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_feature_flags')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.put('/api/v1/platform/features/:featureKey', requireAuth, loadUserContext, requirePlatformPermission('platform.features.manage'), async (request, response, next) => {
  try {
    const input = featureFlagSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_set_feature_flag', { p_beta_only: input.betaOnly ?? null, p_enabled_globally: input.enabledGlobally, p_feature_key: request.params['featureKey'] })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.put('/api/v1/platform/features/:featureKey/tenants', requireAuth, loadUserContext, requirePlatformPermission('platform.features.manage'), async (request, response, next) => {
  try {
    const input = tenantFeatureOverrideSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_set_tenant_feature_flag', { p_feature_key: request.params['featureKey'], p_override: input.override, p_tenant_id: input.tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/system/errors', requireAuth, loadUserContext, requirePlatformPermission('platform.system_errors.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_platform_errors')
    if (error) {
      throwFinancialDatabaseError(error, 'PLATFORM_ACCESS_DENIED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/financial-summary', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_event_financial_summary', { p_tenant_id: tenantId, p_event_id: eventId })
    if (error) {
      throwFinancialDatabaseError(error, 'EVENT_FINANCIAL_SUMMARY_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/reports/:reportType', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const reportType = reportTypeSchema.parse(request.params['reportType'])
    const input = reportRequestSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const data = await getEventReportResult(client, tenantId, eventId, reportType, input, request.requestId)
    await client.rpc('rpc_track_product_event', { p_event_name: 'REPORT_VIEWED', p_tenant_id: tenantId, p_metadata: { eventId, reportType } })
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/reports/member-statement/:eventMemberId/export', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const eventMemberId = uuidParamSchema.parse(request.params['eventMemberId'])
    await handleReportExport(request, response, 'member-statement', eventMemberId)
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/reports/:reportType/export', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const reportType = reportTypeSchema.parse(request.params['reportType'])
    await handleReportExport(request, response, reportType)
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/users', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_tenant_users', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'TENANT_USERS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/settings-summary', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_tenant_settings_summary', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'TENANT_SETTINGS_SUMMARY_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/members', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_event_members', { p_tenant_id: tenantId, p_event_id: eventId })
    if (error) {
      throwFinancialDatabaseError(error, 'EVENT_MEMBERS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/contacts', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_contacts', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'CONTACTS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/contacts', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const input = createContactSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_create_contact', {
      p_tenant_id: tenantId,
      p_full_name: input.fullName,
      p_phone: input.phone || null,
      p_alternative_phone: input.alternativePhone || null,
      p_email: input.email || null,
      p_location: input.location || null,
      p_notes: input.notes || null,
      p_sms_enabled: input.smsEnabled ?? true,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'CREATE_CONTACT_FAILED')
    }
    response.status(201).json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/contacts/:memberId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const memberId = uuidParamSchema.parse(request.params['memberId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_contact_detail', { p_tenant_id: tenantId, p_member_id: memberId })
    if (error) {
      throwFinancialDatabaseError(error, 'CONTACT_DETAIL_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/members', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = createMemberSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_create_member_and_attach_to_event', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_full_name: input.fullName,
      p_phone: input.phone || null,
      p_alternative_phone: input.alternativePhone || null,
      p_email: input.email || null,
      p_location: input.location || null,
      p_category_id: input.categoryId || null,
      p_notes: input.notes || null,
      p_sms_enabled: input.smsEnabled ?? true,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'CREATE_MEMBER_FAILED')
    }
    if (input.initialPledgeAmount && typeof data === 'object' && data !== null && 'event_member_id' in data && typeof data.event_member_id === 'string') {
      const pledgeResult = await client.rpc('rpc_create_or_update_pledge', {
        p_tenant_id: tenantId,
        p_event_id: eventId,
        p_event_member_id: data.event_member_id,
        p_amount: input.initialPledgeAmount,
        p_due_date: input.initialPledgeDueDate || null,
        p_notes: input.notes || null,
        p_change_reason: null,
      })
      if (pledgeResult.error) {
        throwFinancialDatabaseError(pledgeResult.error, 'CREATE_INITIAL_PLEDGE_FAILED')
      }
      const pledge = jsonRecord(pledgeResult.data)
      const notification = typeof pledge['pledge_id'] === 'string'
        ? await enqueuePledgeRegistrationSms(client, tenantId, eventId, pledge['pledge_id'], request.requestId)
        : { smsQueued: false, reason: 'PLEDGE_ID_MISSING', template: 'PLEDGE_REGISTRATION' }
      response.status(201).json({ data: { ...data, pledge, notification } })
      return
    }
    response.status(201).json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/contacts/available', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_contacts_available_for_event', { p_tenant_id: tenantId, p_event_id: eventId })
    if (error) {
      throwFinancialDatabaseError(error, 'EVENT_AVAILABLE_CONTACTS_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/members/:eventMemberId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const eventMemberId = uuidParamSchema.parse(request.params['eventMemberId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_event_member_detail', { p_tenant_id: tenantId, p_event_id: eventId, p_event_member_id: eventMemberId })
    if (error) {
      throwFinancialDatabaseError(error, 'EVENT_MEMBER_DETAIL_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.patch('/api/v1/members/:memberId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const memberId = uuidParamSchema.parse(request.params['memberId'])
    const input = updateMemberSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const update = {
      ...(input.fullName !== undefined ? { full_name: input.fullName } : {}),
      ...(input.phoneE164 !== undefined ? { phone_e164: input.phoneE164 || null } : {}),
      ...(input.alternativePhoneE164 !== undefined ? { alternative_phone_e164: input.alternativePhoneE164 || null } : {}),
      ...(input.email !== undefined ? { email: input.email || null } : {}),
      ...(input.location !== undefined ? { location: input.location || null } : {}),
      ...(input.notes !== undefined ? { notes: input.notes || null } : {}),
      ...(input.preferredLanguage !== undefined ? { preferred_language: input.preferredLanguage } : {}),
      ...(input.smsEnabled !== undefined ? { sms_enabled: input.smsEnabled } : {}),
      ...(input.status !== undefined ? { status: input.status, archived_by: input.status === 'ARCHIVED' ? request.auth?.user.id : null } : {}),
    }
    const { data, error } = await client.from('members').update(update).eq('tenant_id', tenantId).eq('id', memberId).select('*').single()
    if (error) {
      throwFinancialDatabaseError(error, 'UPDATE_MEMBER_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/members/attach', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = attachMemberSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_attach_existing_member_to_event', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_member_id: input.memberId,
      p_category_id: input.categoryId || null,
      p_notes: input.notes || null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'ATTACH_MEMBER_FAILED')
    }
    response.status(201).json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/members/:eventMemberId/remove', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const eventMemberId = uuidParamSchema.parse(request.params['eventMemberId'])
    const input = removeEventMemberSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_remove_event_member', { p_tenant_id: tenantId, p_event_id: eventId, p_event_member_id: eventMemberId, p_reason: input.reason || null })
    if (error) {
      throwFinancialDatabaseError(error, 'REMOVE_EVENT_MEMBER_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/pledges', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_event_pledges', { p_tenant_id: tenantId, p_event_id: eventId })
    if (error) {
      throwFinancialDatabaseError(error, 'PLEDGES_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/outstanding-members', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_event_outstanding_members', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_due_soon_days: env.BALANCE_REMINDER_DUE_SOON_DAYS,
      p_cooldown_hours: env.BALANCE_REMINDER_COOLDOWN_HOURS,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'OUTSTANDING_MEMBERS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/share/whatsapp-settings', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'whatsapp_lists')
    const { data, error } = await client.rpc('rpc_get_event_whatsapp_share_settings', { p_tenant_id: tenantId, p_event_id: eventId })
    if (error) {
      throwFinancialDatabaseError(error, 'WHATSAPP_SHARE_SETTINGS_GET_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.put('/api/v1/events/:eventId/share/whatsapp-settings', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = whatsappShareSettingsSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'whatsapp_lists')
    const { data, error } = await client.rpc('rpc_update_event_whatsapp_share_settings', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_header_text: input.headerText || null,
      p_footer_text: input.footerText || null,
      p_include_event_name: input.includeEventName,
      p_include_event_date: input.includeEventDate,
      p_include_event_payment_instructions: input.includeEventPaymentInstructions,
      p_include_mobile_money_instructions: input.includeMobileMoneyInstructions,
      p_include_bank_instructions: input.includeBankInstructions,
      p_default_list_format: input.defaultListFormat,
      p_default_sort: input.defaultSort,
      p_default_include_summary: input.defaultIncludeSummary,
      p_summary_rows: input.summaryRows ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'WHATSAPP_SHARE_SETTINGS_SAVE_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/share/whatsapp-preview', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = whatsappSharePreviewSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'whatsapp_lists')
    const { data, error } = await client.rpc('rpc_generate_event_whatsapp_share_preview', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_format: input.format,
      p_status_filter: input.statusFilter,
      p_category_id: input.categoryId || null,
      p_sort: input.sort,
      p_include_summary: input.includeSummary,
      p_include_event_date: input.includeEventDate,
      p_include_event_payment_instructions: input.includeEventPaymentInstructions,
      p_include_mobile_money_instructions: input.includeMobileMoneyInstructions,
      p_include_bank_instructions: input.includeBankInstructions,
      p_include_without_pledges: input.includeWithoutPledges,
      p_phone_filter: input.phoneFilter,
      p_search: input.search,
      p_safe_char_limit: env.WHATSAPP_SHARE_SAFE_CHAR_LIMIT,
      p_summary_rows: input.summaryRows ?? null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'WHATSAPP_SHARE_PREVIEW_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/reminders/balance', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = balanceReminderSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'balance_reminders')
    const preview = await client.rpc('rpc_preview_event_member_sms', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_template_code: 'BALANCE_REMINDER',
    })
    if (preview.error) {
      throwFinancialDatabaseError(preview.error, 'SMS_PREVIEW_FAILED')
    }
    const previewRecord = jsonRecord(preview.data)
    if (!previewIsValid(previewRecord)) {
      response.status(200).json({ data: { queued: false, template: 'BALANCE_REMINDER', reason: 'SMS_CHARACTER_LIMIT_EXCEEDED', preview: previewRecord } })
      return
    }
    const { data, error } = await client.rpc('rpc_enqueue_balance_reminder_sms', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: 0,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/messages/preview', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = smsPreviewSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_preview_event_member_sms', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_template_code: input.templateCode,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_PREVIEW_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/messages/preview/bulk', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = smsBulkPreviewSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_preview_event_member_sms_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: input.eventMemberIds,
      p_template_code: input.templateCode,
      p_cooldown_hours: 0,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_BULK_PREVIEW_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/messages/no-pledge-members', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_event_no_pledge_members', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_cooldown_hours: 0,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'NO_PLEDGE_MEMBERS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/messages/completed-pledges', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_event_completed_pledge_members', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'COMPLETED_PLEDGE_MEMBERS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/messages/pledge-request', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = pledgeRequestSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const preview = await client.rpc('rpc_preview_event_member_sms', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_template_code: 'PLEDGE_REQUEST',
    })
    if (preview.error) {
      throwFinancialDatabaseError(preview.error, 'SMS_PREVIEW_FAILED')
    }
    const previewRecord = jsonRecord(preview.data)
    if (!previewIsValid(previewRecord)) {
      response.status(200).json({ data: { queued: false, template: 'PLEDGE_REQUEST', reason: 'SMS_CHARACTER_LIMIT_EXCEEDED', preview: previewRecord } })
      return
    }
    const { data, error } = await client.rpc('rpc_enqueue_pledge_request_sms', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: 0,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'PLEDGE_REQUEST_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/messages/pledge-request/bulk', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = bulkPledgeRequestSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const preview = await client.rpc('rpc_preview_event_member_sms_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: input.eventMemberIds,
      p_template_code: 'PLEDGE_REQUEST',
      p_cooldown_hours: 0,
    })
    if (preview.error) {
      throwFinancialDatabaseError(preview.error, 'SMS_BULK_PREVIEW_FAILED')
    }
    const validIds = validPreviewEventMemberIds(preview.data)
    if (!validIds.length) {
      response.status(200).json({ data: { ...jsonRecord(preview.data), queued: 0, reason: 'NO_VALID_SMS_MESSAGES' } })
      return
    }
    const { data, error } = await client.rpc('rpc_enqueue_pledge_request_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: validIds,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: 0,
      p_max_batch_size: env.PLEDGE_REQUEST_MAX_BATCH_SIZE,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'PLEDGE_REQUEST_BULK_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/messages/completed-pledges/bulk', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = bulkCompletedPledgeSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const preview = await client.rpc('rpc_preview_event_member_sms_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: input.eventMemberIds,
      p_template_code: 'PLEDGE_COMPLETED',
      p_cooldown_hours: 0,
    })
    if (preview.error) {
      throwFinancialDatabaseError(preview.error, 'SMS_BULK_PREVIEW_FAILED')
    }
    const validIds = validPreviewEventMemberIds(preview.data)
    if (!validIds.length) {
      response.status(200).json({ data: { ...jsonRecord(preview.data), queued: 0, reason: 'NO_VALID_SMS_MESSAGES' } })
      return
    }
    const { data, error } = await client.rpc('rpc_enqueue_completed_pledge_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: validIds,
      p_idempotency_key: input.idempotencyKey,
      p_max_batch_size: env.BALANCE_REMINDER_MAX_BATCH_SIZE,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'COMPLETED_PLEDGE_BULK_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/reminders/balance/bulk', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = bulkBalanceReminderSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'balance_reminders')
    const preview = await client.rpc('rpc_preview_event_member_sms_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: input.eventMemberIds,
      p_template_code: 'BALANCE_REMINDER',
      p_cooldown_hours: 0,
    })
    if (preview.error) {
      throwFinancialDatabaseError(preview.error, 'SMS_BULK_PREVIEW_FAILED')
    }
    const validIds = validPreviewEventMemberIds(preview.data)
    if (!validIds.length) {
      response.status(200).json({ data: { ...jsonRecord(preview.data), queued: 0, reason: 'NO_VALID_SMS_MESSAGES' } })
      return
    }
    const { data, error } = await client.rpc('rpc_enqueue_balance_reminder_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: validIds,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: 0,
      p_max_batch_size: env.BALANCE_REMINDER_MAX_BATCH_SIZE,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_BULK_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/pledges', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = upsertPledgeSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const existingPledge = await client.from('v_event_pledges_list').select('pledge_id').eq('tenant_id', tenantId).eq('event_id', eventId).eq('event_member_id', input.eventMemberId).maybeSingle()
    if (existingPledge.error) {
      console.warn('Pledge registration SMS pre-check failed; skipping automatic registration SMS', {
        requestId: request.requestId,
        tenantId,
        eventId,
        safeMessage: databaseMessage(existingPledge.error).slice(0, 160),
      })
    }
    const shouldQueueRegistrationSms = !existingPledge.error && !existingPledge.data?.pledge_id
    const { data, error } = await client.rpc('rpc_create_or_update_pledge', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_amount: input.amount,
      p_due_date: input.dueDate || null,
      p_notes: input.notes || null,
      p_change_reason: input.changeReason || null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'UPSERT_PLEDGE_FAILED')
    }
    const pledge = jsonRecord(data)
    const notification = shouldQueueRegistrationSms && typeof pledge['pledge_id'] === 'string'
      ? await enqueuePledgeRegistrationSms(client, tenantId, eventId, pledge['pledge_id'], request.requestId)
      : { smsQueued: false, reason: shouldQueueRegistrationSms ? 'PLEDGE_ID_MISSING' : 'PLEDGE_ALREADY_EXISTS', template: 'PLEDGE_REGISTRATION' }
    response.status(201).json({ data: { ...pledge, notification } })
  } catch (error) {
    next(error)
  }
})

app.patch('/api/v1/events/:eventId/pledges/:pledgeId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const pledgeId = uuidParamSchema.parse(request.params['pledgeId'])
    const input = patchPledgeSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    let eventMemberId = input.eventMemberId
    if (!eventMemberId) {
      const pledgeLookup = await client.from('v_event_pledges_list').select('event_member_id').eq('tenant_id', tenantId).eq('event_id', eventId).eq('pledge_id', pledgeId).single()
      if (pledgeLookup.error || !pledgeLookup.data?.event_member_id || typeof pledgeLookup.data.event_member_id !== 'string') {
        throwFinancialDatabaseError(pledgeLookup.error ?? new Error('PLEDGE_NOT_FOUND'), 'PLEDGE_LOOKUP_FAILED')
      }
      eventMemberId = pledgeLookup.data.event_member_id
    }
    const { data, error } = await client.rpc('rpc_create_or_update_pledge', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: eventMemberId,
      p_amount: input.amount,
      p_due_date: input.dueDate || null,
      p_notes: input.notes || null,
      p_change_reason: input.changeReason || null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'UPDATE_PLEDGE_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/pledges/:pledgeId/cancel', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const pledgeId = uuidParamSchema.parse(request.params['pledgeId'])
    const input = cancelPledgeSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_cancel_pledge', { p_tenant_id: tenantId, p_event_id: eventId, p_pledge_id: pledgeId, p_reason: input.reason })
    if (error) {
      throwFinancialDatabaseError(error, 'CANCEL_PLEDGE_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/payments', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_event_payments', { p_tenant_id: tenantId, p_event_id: eventId })
    if (error) {
      throwFinancialDatabaseError(error, 'PAYMENTS_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/payments', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const input = recordPaymentSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_record_installment_payment', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_amount: input.amount,
      p_payment_method: input.paymentMethod,
      p_payment_date: input.paymentDate || new Date().toISOString(),
      p_transaction_reference: input.transactionReference || null,
      p_provider_name: input.providerName || null,
      p_notes: input.notes || null,
      p_pledge_id: input.pledgeId || null,
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'RECORD_PAYMENT_FAILED')
    }
    const payment = jsonRecord(data)
    let notification: Record<string, unknown> = { smsQueued: false, reason: 'PAYMENT_ID_MISSING' }
    if (typeof payment['payment_id'] === 'string') {
      const enqueue = await client.rpc('rpc_enqueue_payment_confirmation_sms', { p_tenant_id: tenantId, p_payment_id: payment['payment_id'] })
      if (enqueue.error) {
        console.error('Payment confirmation SMS enqueue failed', {
          requestId: request.requestId,
          tenantId,
          paymentId: payment['payment_id'],
          safeMessage: databaseMessage(enqueue.error).slice(0, 160),
        })
        notification = { smsQueued: false, reason: smsEnqueueFailureReason(enqueue.error) }
      } else {
        notification = notificationFromEnqueue(enqueue.data)
      }
    }
    response.status(201).json({ data: { ...payment, notification } })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/events/:eventId/payments/:paymentId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const eventId = uuidParamSchema.parse(request.params['eventId'])
    const paymentId = uuidParamSchema.parse(request.params['paymentId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.from('v_event_payments_list').select('*').eq('tenant_id', tenantId).eq('event_id', eventId).eq('payment_id', paymentId).single()
    if (error) {
      throwFinancialDatabaseError(error, 'PAYMENT_DETAIL_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/events/:eventId/payments/:paymentId/reverse', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    uuidParamSchema.parse(request.params['eventId'])
    const paymentId = uuidParamSchema.parse(request.params['paymentId'])
    const input = reversePaymentSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_reverse_payment', { p_tenant_id: tenantId, p_payment_id: paymentId, p_reason: input.reason, p_idempotency_key: input.idempotencyKey })
    if (error) {
      throwFinancialDatabaseError(error, 'REVERSE_PAYMENT_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/receipts/:receiptId', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const receiptId = uuidParamSchema.parse(request.params['receiptId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_receipt_detail', { p_tenant_id: tenantId, p_receipt_id: receiptId })
    if (error) {
      throwFinancialDatabaseError(error, 'RECEIPT_DETAIL_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/messages', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_sms_history', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_HISTORY_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/messages/settings', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_sms_settings', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_SETTINGS_GET_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/settings/messages/providers', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_sms_provider_options', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_PROVIDER_OPTIONS_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

async function saveTenantSmsSettings(request: express.Request, response: express.Response, next: express.NextFunction) {
  try {
    const tenantId = tenantIdFromRequest(request)
    const input = smsSettingsSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_update_sms_settings', {
      p_tenant_id: tenantId,
      p_sms_enabled: input.smsEnabled,
      p_provider_code: input.provider,
      p_sender_id: input.senderId,
      p_default_language: input.defaultLanguage,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_SETTINGS_SAVE_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
}

app.put('/api/v1/messages/settings', requireAuth, loadUserContext, requireTenantContext, saveTenantSmsSettings)
app.patch('/api/v1/settings/messages', requireAuth, loadUserContext, requireTenantContext, saveTenantSmsSettings)

app.get('/api/v1/messages/templates', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_list_sms_templates', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_TEMPLATES_LIST_FAILED')
    }
    response.json({ data: jsonArray(data) })
  } catch (error) {
    next(error)
  }
})

app.put('/api/v1/messages/templates/:code', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const code = parseSmsTemplateCodeParam(request.params['code'])
    const input = smsTemplateSaveSchema.parse(request.body)
    const body = normalizeSmsTemplateBody(code, input.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_upsert_sms_template', {
      p_tenant_id: tenantId,
      p_code: code,
      p_language: input.language,
      p_body: body,
    })
    if (error) {
      console.warn('SMS template save rejected', {
        requestId: request.requestId,
        tenantId,
        code,
        safeMessage: databaseMessage(error).slice(0, 160),
      })
      throwFinancialDatabaseError(error, 'SMS_TEMPLATE_SAVE_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/messages/templates/:code/reset', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const code = parseSmsTemplateCodeParam(request.params['code'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_reset_sms_template', { p_tenant_id: tenantId, p_code: code, p_language: 'sw' })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_TEMPLATE_RESET_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/messages/templates/balance-reminder', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'balance_reminders')
    const { data, error } = await client.rpc('rpc_get_balance_reminder_template', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_TEMPLATE_GET_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.put('/api/v1/messages/templates/balance-reminder', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const input = templateBodySchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'balance_reminders')
    const { data, error } = await client.rpc('rpc_upsert_balance_reminder_template', { p_tenant_id: tenantId, p_body: input.body })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_TEMPLATE_SAVE_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/messages/templates/balance-reminder/reset', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'balance_reminders')
    const { data, error } = await client.rpc('rpc_reset_balance_reminder_template', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_TEMPLATE_RESET_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/messages/:outboxId/retry', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const outboxId = uuidParamSchema.parse(request.params['outboxId'])
    const input = resendBalanceReminderSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_resend_failed_sms', {
      p_tenant_id: tenantId,
      p_outbox_id: outboxId,
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_RETRY_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/messages/:outboxId/resend-balance-reminder', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const outboxId = uuidParamSchema.parse(request.params['outboxId'])
    const input = resendBalanceReminderSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    await ensureTenantFeatureEnabled(client, tenantId, 'balance_reminders')
    const { data, error } = await client.rpc('rpc_resend_failed_balance_reminder', {
      p_tenant_id: tenantId,
      p_outbox_id: outboxId,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: 0,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_RESEND_FAILED')
    }
    const result = notificationFromEnqueue(data)
    response.status(201).json({ data: result })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/messages/worker-diagnostics', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const permissions = new Set(request.tenantContext?.permissions ?? [])
    if (!permissions.has('messages.send') && !request.tenantContext?.membership?.isOwner) {
      throw new AppError('TENANT_ACCESS_DENIED', 'Message send permission is required')
    }
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_sms_worker_diagnostics', { p_limit: 10 })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_WORKER_DIAGNOSTICS_FAILED')
    }
    response.json({ data: jsonRecord(data) })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/messages/process-queued', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const permissions = new Set(request.tenantContext?.permissions ?? [])
    if (!permissions.has('messages.send') && !request.tenantContext?.membership?.isOwner) {
      throw new AppError('TENANT_ACCESS_DENIED', 'Message send permission is required')
    }
    processQueuedSmsSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_sms_worker_diagnostics', { p_limit: 10 })
    if (error) {
      throwFinancialDatabaseError(error, 'SMS_WORKER_DIAGNOSTICS_FAILED')
    }
    response.status(202).json({ data: { accepted: true, processing: 'WORKER', diagnostics: jsonRecord(data), message: 'Queued SMS is processed by the background worker.' } })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/receipts/:receiptId/print', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const receiptId = uuidParamSchema.parse(request.params['receiptId'])
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_get_receipt_detail', { p_tenant_id: tenantId, p_receipt_id: receiptId })
    if (error) {
      throwFinancialDatabaseError(error, 'RECEIPT_PRINT_FAILED')
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.use(errorHandler)
