import type { ApiErrorCode, OnboardingPayload, PinVerificationResult, UserContext, TenantContext } from '@ahadi/types'
import { env } from './env'
import { supabase } from './supabase'

export class ApiClientError extends Error {
  code: ApiErrorCode
  requestId: string | null

  constructor(code: ApiErrorCode, message: string, requestId: string | null = null) {
    super(message)
    this.code = code
    this.requestId = requestId
  }
}

async function getAccessToken(): Promise<string | null> {
  const { data } = await supabase.auth.getSession()
  return data.session?.access_token ?? null
}

async function apiFetch<T>(path: string, options: RequestInit & { tenantId?: string; auth?: boolean } = {}): Promise<T> {
  const headers = new Headers(options.headers)
  headers.set('Content-Type', 'application/json')
  headers.set('Cache-Control', 'no-cache')
  headers.set('Pragma', 'no-cache')
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
    cache: 'no-store',
  })
  const payload = (await response.json().catch(() => null)) as unknown

  if (!response.ok) {
    const errorPayload = payload as { error?: { code?: ApiErrorCode; message?: string; requestId?: string } } | null
    throw new ApiClientError(errorPayload?.error?.code ?? 'INTERNAL_ERROR', errorPayload?.error?.message ?? 'Request failed', errorPayload?.error?.requestId ?? response.headers.get('X-Request-ID'))
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
  tenantUsers: (tenantId: string) => apiFetch<{ data: Record<string, unknown>[] }>('/users', { tenantId }),
  settingsSummary: (tenantId: string) => apiFetch<{ data: Record<string, unknown> }>('/settings-summary', { tenantId }),
  eventFinancialSummary: (tenantId: string, eventId: string) => apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/financial-summary`, { tenantId }),
  eventMembers: (tenantId: string, eventId: string) => apiFetch<{ data: Record<string, unknown>[] }>(`/events/${eventId}/members`, { tenantId }),
  eventMemberDetail: (tenantId: string, eventId: string, eventMemberId: string) =>
    apiFetch<{ data: { member: Record<string, unknown>; payments: Record<string, unknown>[] } }>(`/events/${eventId}/members/${eventMemberId}`, { tenantId }),
  createEventMember: (tenantId: string, eventId: string, payload: Record<string, unknown>) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/members`, { tenantId, method: 'POST', body: JSON.stringify(payload) }),
  attachEventMember: (tenantId: string, eventId: string, payload: Record<string, unknown>) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/members/attach`, { tenantId, method: 'POST', body: JSON.stringify(payload) }),
  removeEventMember: (tenantId: string, eventId: string, eventMemberId: string) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/members/${eventMemberId}/remove`, { tenantId, method: 'POST' }),
  eventPledges: (tenantId: string, eventId: string) => apiFetch<{ data: Record<string, unknown>[] }>(`/events/${eventId}/pledges`, { tenantId }),
  eventOutstandingMembers: (tenantId: string, eventId: string) => apiFetch<{ data: Record<string, unknown>[] }>(`/events/${eventId}/outstanding-members`, { tenantId }),
  sendBalanceReminder: (tenantId: string, eventId: string, payload: Record<string, unknown>) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/reminders/balance`, { tenantId, method: 'POST', body: JSON.stringify(payload) }),
  sendBulkBalanceReminders: (tenantId: string, eventId: string, payload: Record<string, unknown>) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/reminders/balance/bulk`, { tenantId, method: 'POST', body: JSON.stringify(payload) }),
  upsertPledge: (tenantId: string, eventId: string, payload: Record<string, unknown>, pledgeId?: string) =>
    apiFetch<{ data: Record<string, unknown> }>(pledgeId ? `/events/${eventId}/pledges/${pledgeId}` : `/events/${eventId}/pledges`, {
      tenantId,
      method: pledgeId ? 'PATCH' : 'POST',
      body: JSON.stringify(payload),
    }),
  cancelPledge: (tenantId: string, eventId: string, pledgeId: string, reason: string) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/pledges/${pledgeId}/cancel`, { tenantId, method: 'POST', body: JSON.stringify({ reason }) }),
  eventPayments: (tenantId: string, eventId: string) => apiFetch<{ data: Record<string, unknown>[] }>(`/events/${eventId}/payments`, { tenantId }),
  recordPayment: (tenantId: string, eventId: string, payload: Record<string, unknown>) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/payments`, { tenantId, method: 'POST', body: JSON.stringify(payload) }),
  reversePayment: (tenantId: string, eventId: string, paymentId: string, payload: Record<string, unknown>) =>
    apiFetch<{ data: Record<string, unknown> }>(`/events/${eventId}/payments/${paymentId}/reverse`, { tenantId, method: 'POST', body: JSON.stringify(payload) }),
  receipt: (tenantId: string, receiptId: string) => apiFetch<{ data: Record<string, unknown> }>(`/receipts/${receiptId}`, { tenantId }),
  messages: (tenantId: string) => apiFetch<{ data: Record<string, unknown>[] }>('/messages', { tenantId }),
  balanceReminderTemplate: (tenantId: string) => apiFetch<{ data: Record<string, unknown> }>('/messages/templates/balance-reminder', { tenantId }),
  saveBalanceReminderTemplate: (tenantId: string, body: string) => apiFetch<{ data: Record<string, unknown> }>('/messages/templates/balance-reminder', { tenantId, method: 'PUT', body: JSON.stringify({ body }) }),
  resetBalanceReminderTemplate: (tenantId: string) => apiFetch<{ data: Record<string, unknown> }>('/messages/templates/balance-reminder/reset', { tenantId, method: 'POST' }),
  resendBalanceReminder: (tenantId: string, outboxId: string, idempotencyKey: string) =>
    apiFetch<{ data: Record<string, unknown> }>(`/messages/${outboxId}/resend-balance-reminder`, { tenantId, method: 'POST', body: JSON.stringify({ idempotencyKey }) }),
}
