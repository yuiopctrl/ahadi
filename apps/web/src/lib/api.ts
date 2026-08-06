import type { ApiErrorCode, OnboardingPayload, PinVerificationResult, UserContext, TenantContext } from '@ahadi/types'
import { env } from './env'
import { supabase } from './supabase'

export class ApiClientError extends Error {
  code: ApiErrorCode

  constructor(code: ApiErrorCode, message: string) {
    super(message)
    this.code = code
  }
}

async function getAccessToken(): Promise<string | null> {
  const { data } = await supabase.auth.getSession()
  return data.session?.access_token ?? null
}

async function apiFetch<T>(path: string, options: RequestInit & { tenantId?: string; auth?: boolean } = {}): Promise<T> {
  const headers = new Headers(options.headers)
  headers.set('Content-Type', 'application/json')
  if (options.auth !== false) {
    const token = await getAccessToken()
    if (token) {
      headers.set('Authorization', `Bearer ${token}`)
    }
  }
  if (options.tenantId) {
    headers.set('X-Tenant-ID', options.tenantId)
  }

  const response = await fetch(`${env.apiUrl}${path}`, {
    ...options,
    headers,
  })
  const payload = (await response.json().catch(() => null)) as unknown

  if (!response.ok) {
    const errorPayload = payload as { error?: { code?: ApiErrorCode; message?: string } } | null
    throw new ApiClientError(errorPayload?.error?.code ?? 'INTERNAL_ERROR', errorPayload?.error?.message ?? 'Request failed')
  }

  return payload as T
}

export const api = {
  requestOtp: (phone: string) => apiFetch<{ ok: boolean }>('/auth/request-otp', { method: 'POST', auth: false, body: JSON.stringify({ phone }) }),
  verifyOtp: (phone: string, token: string) =>
    apiFetch<{ session: { access_token: string; refresh_token: string }; user: unknown }>('/auth/verify-otp', {
      method: 'POST',
      auth: false,
      body: JSON.stringify({ phone, token }),
    }),
  setPin: (pin: string, confirmPin: string) => apiFetch<{ ok: boolean }>('/auth/set-pin', { method: 'POST', body: JSON.stringify({ pin, confirmPin }) }),
  verifyPin: (pin: string) => apiFetch<PinVerificationResult>('/auth/verify-pin', { method: 'POST', body: JSON.stringify({ pin }) }),
  hasPin: () => apiFetch<{ hasPin: boolean }>('/auth/has-pin'),
  logout: () => apiFetch<{ ok: boolean }>('/auth/logout', { method: 'POST' }),
  plans: () => apiFetch<{ data: unknown[] }>('/plans', { auth: false }),
  completeOnboarding: (payload: OnboardingPayload) =>
    apiFetch('/onboarding/complete', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  me: () => apiFetch<{ data: UserContext }>('/me'),
  tenantContext: (tenantId: string) => apiFetch<{ data: TenantContext }>('/tenant-context', { tenantId }),
  platformDashboard: () => apiFetch<{ data: Record<string, number> }>('/platform/dashboard'),
  platformTenants: () => apiFetch<{ data: unknown[] }>('/platform/tenants'),
  platformPlans: () => apiFetch<{ data: unknown[] }>('/platform/plans'),
}
