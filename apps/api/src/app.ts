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

function notificationFromEnqueue(data: unknown): Record<string, unknown> {
  const notification = jsonRecord(data)
  return Object.keys(notification).length ? notification : { smsQueued: false, reason: 'ENQUEUE_FAILED' }
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
