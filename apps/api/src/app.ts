import cors from 'cors'
import express from 'express'
import rateLimit from 'express-rate-limit'
import helmet from 'helmet'
import morgan from 'morgan'
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
import { attemptTenantQueuedSms, sendTenantQueuedSms } from './sms-outbox.js'
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

const balanceReminderSchema = z.object({
  eventMemberId: z.string().uuid(),
  idempotencyKey: z.string().uuid(),
})

const bulkBalanceReminderSchema = z.object({
  eventMemberIds: z.array(z.string().uuid()).min(1),
  idempotencyKey: z.string().uuid(),
})

const templateBodySchema = z.object({
  body: z.string().trim().min(1).max(918),
})

const resendBalanceReminderSchema = z.object({
  idempotencyKey: z.string().uuid(),
})

const processQueuedSmsSchema = z.object({
  batchSize: z.coerce.number().int().positive().max(50).optional(),
})

const whatsappShareFormatSchema = z.enum(['DETAILED', 'PRIVACY', 'PAYMENT_PROGRESS', 'OUTSTANDING_FOLLOW_UP'])
const whatsappShareSortSchema = z.enum(['ORIGINAL', 'NAME_ASC', 'PLEDGED_DESC', 'PAID_FIRST', 'OUTSTANDING_FIRST'])
const whatsappShareStatusSchema = z.enum(['ALL', 'PAID', 'PARTIAL', 'UNPAID', 'OVERDUE'])
const whatsappPhoneFilterSchema = z.enum(['ALL', 'WITH_PHONE', 'WITHOUT_PHONE'])

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
  'PAYMENT_NOT_FOUND',
  'PAYMENT_AMOUNT_INVALID',
  'PAYMENT_REFERENCE_DUPLICATE',
  'PAYMENT_ALREADY_REVERSED',
  'PAYMENT_REVERSAL_REASON_REQUIRED',
  'PAYMENT_IDEMPOTENCY_CONFLICT',
  'EVENT_NOT_ACTIVE',
  'EVENT_ACCESS_DENIED',
  'EVENT_LIMIT_REACHED',
  'RECEIPT_NOT_FOUND',
  'SUBSCRIPTION_READ_ONLY',
  'SUBSCRIPTION_BLOCKED',
]

const developmentWebOrigins = new Set([
  env.WEB_URL,
  'http://localhost:5173',
  'http://127.0.0.1:5173',
  'http://localhost:5174',
  'http://127.0.0.1:5174',
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
    : env.WEB_URL

function databaseMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') {
    return error.message
  }
  return ''
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

function queuedOutboxId(data: Record<string, unknown>): string | null {
  return typeof data['outboxId'] === 'string' ? data['outboxId'] : null
}

function queuedBatchId(data: Record<string, unknown>): string | null {
  return typeof data['batchId'] === 'string' ? data['batchId'] : null
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
  const limit = exportLimits[exportRequest.format]
  const reportInput = {
    ...exportRequestToReportInput(exportRequest),
    ...(memberId ? { eventMemberId: memberId } : {}),
    page: 1,
    pageSize: limit,
  }
  const client = createUserSupabase(request.auth?.accessToken ?? '')
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
app.post('/auth/hooks/send-sms', sendSmsHookLimiter, express.raw({ type: 'application/json', limit: '64kb' }), sendSmsHookHandler)
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
  response.json({ status: 'ok', service: 'ahadi-api' })
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

app.post('/api/v1/onboarding/complete', requireAuth, async (request, response, next) => {
  try {
    const parsedInput = onboardingPayloadSchema.safeParse(request.body)
    if (!parsedInput.success) {
      logValidationError(request.requestId, 'onboarding-complete', parsedInput.error)
      throw new AppError('INVALID_INPUT', 'Request validation failed', 400)
    }
    const input = parsedInput.data
    const client = createUserSupabase(request.auth?.accessToken ?? '')
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

app.post('/api/v1/events', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    if (request.tenantContext?.accessState === 'READ_ONLY') {
      throw new AppError('SUBSCRIPTION_READ_ONLY', 'Subscription is read-only')
    }
    const input = createEventSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_create_event', {
      p_tenant_id: tenantId,
      p_name: input.name,
      p_event_type: input.eventType,
      p_custom_event_type: input.customEventType || null,
      p_event_date: input.eventDate || null,
      p_venue: input.venue || null,
      p_target_amount: input.targetAmount || null,
      p_pledge_deadline: input.pledgeDeadline || null,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'EVENT_CREATE_FAILED')
    }
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
    const { data, error } = await client.from('tenants').select('*').eq('id', tenantId).single()
    if (error) {
      throw error
    }
    response.json({ data })
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
      response.status(201).json({ data: { ...data, pledge: pledgeResult.data } })
      return
    }
    response.status(201).json({ data })
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
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_remove_event_member', { p_tenant_id: tenantId, p_event_id: eventId, p_event_member_id: eventMemberId })
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
    const { data, error } = await client.rpc('rpc_enqueue_balance_reminder_sms', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_id: input.eventMemberId,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: env.BALANCE_REMINDER_COOLDOWN_HOURS,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    const outboxId = queuedOutboxId(result)
    if (result['queued'] === true && outboxId) {
      result['sendAttempt'] = await attemptTenantQueuedSms(client, tenantId, {
        batchSize: 1,
        outboxIds: [outboxId],
        requestId: request.requestId,
      })
    }
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
    const { data, error } = await client.rpc('rpc_enqueue_balance_reminder_bulk', {
      p_tenant_id: tenantId,
      p_event_id: eventId,
      p_event_member_ids: input.eventMemberIds,
      p_idempotency_key: input.idempotencyKey,
      p_cooldown_hours: env.BALANCE_REMINDER_COOLDOWN_HOURS,
      p_max_batch_size: env.BALANCE_REMINDER_MAX_BATCH_SIZE,
    })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_BULK_QUEUE_FAILED')
    }
    const result = notificationFromEnqueue(data)
    const batchId = queuedBatchId(result)
    const queued = Number(result['queued'])
    if (batchId && Number.isFinite(queued) && queued > 0) {
      result['sendAttempt'] = await attemptTenantQueuedSms(client, tenantId, {
        batchId,
        batchSize: Math.min(queued, 50),
        requestId: request.requestId,
      })
    }
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
    response.status(201).json({ data })
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
        notification = { smsQueued: false, reason: 'ENQUEUE_FAILED' }
      } else {
        notification = notificationFromEnqueue(enqueue.data)
        const outboxId = queuedOutboxId(notification)
        if (notification['smsQueued'] === true && outboxId) {
          notification['sendAttempt'] = await attemptTenantQueuedSms(client, tenantId, {
            batchSize: 1,
            outboxIds: [outboxId],
            requestId: request.requestId,
          })
        }
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

app.get('/api/v1/messages/templates/balance-reminder', requireAuth, loadUserContext, requireTenantContext, async (request, response, next) => {
  try {
    const tenantId = tenantIdFromRequest(request)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
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
    const { data, error } = await client.rpc('rpc_reset_balance_reminder_template', { p_tenant_id: tenantId })
    if (error) {
      throwFinancialDatabaseError(error, 'BALANCE_REMINDER_TEMPLATE_RESET_FAILED')
    }
    response.json({ data })
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
    const newOutboxId = queuedOutboxId(result)
    if (result['queued'] === true && newOutboxId) {
      result['sendAttempt'] = await attemptTenantQueuedSms(client, tenantId, {
        batchSize: 1,
        outboxIds: [newOutboxId],
        requestId: request.requestId,
      })
    }
    response.status(201).json({ data: result })
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
    const tenantId = tenantIdFromRequest(request)
    const input = processQueuedSmsSchema.parse(request.body ?? {})
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const result = await sendTenantQueuedSms(client, tenantId, {
      batchSize: input.batchSize ?? 10,
      requestId: request.requestId,
    })
    response.json({ data: result })
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
