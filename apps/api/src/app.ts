import cors from 'cors'
import express from 'express'
import rateLimit from 'express-rate-limit'
import helmet from 'helmet'
import morgan from 'morgan'
import { ZodError } from 'zod'
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
import { classifyPinSetupDatabaseError, classifyPinSetupValidationError, getSafePinDatabaseErrorDetails } from './pin-errors.js'
import { createUserSupabase, supabasePublic } from './supabase.js'
import { loadUserContext, requestIdMiddleware, requireAuth, requirePlatformPermission, requireTenantContext } from './middleware.js'

export const app = express()

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

app.use(helmet())
app.use(requestIdMiddleware)
app.post('/auth/hooks/send-sms', sendSmsHookLimiter, express.raw({ type: 'application/json', limit: '64kb' }), sendSmsHookHandler)
app.use(
  cors({
    origin: env.WEB_URL,
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Tenant-ID', 'X-Request-ID'],
  }),
)
app.use(express.json({ limit: '1mb' }))
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
      throw error
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
    const [tenants, events, expiring] = await Promise.all([
      client.from('tenants').select('status', { count: 'exact', head: false }),
      client.from('events').select('id', { count: 'exact', head: true }),
      client
        .from('tenant_subscriptions')
        .select('id', { count: 'exact', head: true })
        .lte('current_period_end', new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString())
        .in('status', ['TRIAL', 'ACTIVE']),
    ])
    if (tenants.error ?? events.error ?? expiring.error) {
      throw tenants.error ?? events.error ?? expiring.error
    }
    const statusCounts = (tenants.data ?? []).reduce<Record<string, number>>((counts, tenant) => {
      counts[tenant.status] = (counts[tenant.status] ?? 0) + 1
      return counts
    }, {})
    response.json({
      data: {
        totalTenants: tenants.count ?? tenants.data?.length ?? 0,
        trialTenants: statusCounts['TRIAL'] ?? 0,
        activeTenants: statusCounts['ACTIVE'] ?? 0,
        suspendedTenants: statusCounts['SUSPENDED'] ?? 0,
        totalEvents: events.count ?? 0,
        subscriptionsExpiringSoon: expiring.count ?? 0,
      },
    })
  } catch (error) {
    next(error)
  }
})

app.get('/api/v1/platform/tenants', requireAuth, loadUserContext, requirePlatformPermission('platform.tenants.view'), async (request, response, next) => {
  try {
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client
      .from('tenants')
      .select('id, code, name, phone_e164, status, created_at, tenant_subscriptions(status, trial_ends_at, current_period_end, subscription_plans(code, name)), events(id, status)')
      .order('created_at', { ascending: false })
    if (error) {
      throw error
    }
    response.json({ data })
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
    const { data, error } = await client.from('subscription_plans').select('*').order('display_order')
    if (error) {
      throw error
    }
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.use(errorHandler)
