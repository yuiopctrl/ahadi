import cors from 'cors'
import express from 'express'
import rateLimit from 'express-rate-limit'
import helmet from 'helmet'
import morgan from 'morgan'
import {
  onboardingPayloadSchema,
  requestOtpSchema,
  setupPinSchema,
  tenantContextHeaderSchema,
  verifyOtpSchema,
  verifyPinSchema,
} from '@ahadi/validation'
import { env } from './env.js'
import { AppError, errorHandler } from './errors.js'
import { createUserSupabase, supabasePublic } from './supabase.js'
import { loadUserContext, requestIdMiddleware, requireAuth, requirePlatformPermission, requireTenantContext } from './middleware.js'

const app = express()

const strictLimiter = rateLimit({
  windowMs: 60_000,
  limit: 5,
  standardHeaders: true,
  legacyHeaders: false,
})

app.use(helmet())
app.use(
  cors({
    origin: env.WEB_URL,
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Tenant-ID', 'X-Request-ID'],
  }),
)
app.use(express.json({ limit: '1mb' }))
app.use(requestIdMiddleware)
app.use(
  morgan(env.NODE_ENV === 'production' ? 'combined' : 'dev', {
    skip: (request) => request.path.startsWith('/api/v1/auth/verify'),
  }),
)

app.get('/health', (_request, response) => {
  response.json({ status: 'ok', service: 'ahadi-api' })
})

app.post('/api/v1/auth/request-otp', strictLimiter, async (request, response, next) => {
  try {
    const input = requestOtpSchema.parse(request.body)
    const { error } = await supabasePublic.auth.signInWithOtp({
      phone: input.phone,
      options: {
        channel: 'sms',
      },
    })
    if (error) {
      throw new AppError('OTP_REQUEST_FAILED', 'Unable to send verification code')
    }
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
    const input = setupPinSchema.parse(request.body)
    const client = createUserSupabase(request.auth?.accessToken ?? '')
    const { data, error } = await client.rpc('rpc_set_my_pin', { p_pin: input.pin })
    if (error) {
      throw error
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
    response.json({ data })
  } catch (error) {
    next(error)
  }
})

app.post('/api/v1/onboarding/complete', requireAuth, async (request, response, next) => {
  try {
    const input = onboardingPayloadSchema.parse(request.body)
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

app.listen(env.PORT, () => {
  console.log(`Ahadi API listening on :${env.PORT}`)
})
