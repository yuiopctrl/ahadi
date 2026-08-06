import type { ApiErrorCode } from '@ahadi/types'

export type OnboardingDatabaseFailureCategory =
  | 'ONBOARDING_RPC_NOT_FOUND'
  | 'ONBOARDING_CRYPTO_FUNCTION_UNAVAILABLE'
  | 'ONBOARDING_IDEMPOTENCY_RESULT_WRITE_FAILED'
  | 'ONBOARDING_DATABASE_PERMISSION_DENIED'
  | 'ONBOARDING_SESSION_REQUIRED'
  | 'ONBOARDING_TENANT_OWNER_ROLE_MISSING'
  | 'ONBOARDING_DATABASE_CONSTRAINT_FAILED'
  | 'UNKNOWN_ONBOARDING_DATABASE_ERROR'

export interface OnboardingErrorClassification {
  category?: OnboardingDatabaseFailureCategory
  code: ApiErrorCode
  message: string
  status: number
}

export interface SafeOnboardingDatabaseErrorDetails {
  details?: string
  errorName?: string
  functionName?: string
  hint?: string
  operation: 'onboarding-complete'
  postgresCode?: string
  requestId: string
  safeMessage?: string
}

function getStringProperty(error: unknown, key: string): string | null {
  if (typeof error === 'object' && error !== null && key in error) {
    const value = (error as Record<string, unknown>)[key]
    return typeof value === 'string' ? value : null
  }
  return null
}

function getDatabaseMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }
  return getStringProperty(error, 'message') ?? ''
}

function sanitizeDatabaseText(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer <redacted-token>')
    .replace(/\b((?:access|refresh)_token)\b\s*[:=]\s*['"]?[^'",\s}]+/gi, '$1=<redacted-token>')
    .replace(/[+0-9][0-9\s().-]{6,}/g, '<redacted-phone-or-number>')
    .slice(0, 360)
}

export function getSafeOnboardingDatabaseErrorDetails(requestId: string, operation: 'onboarding-complete', error: unknown): SafeOnboardingDatabaseErrorDetails {
  const name = getStringProperty(error, 'name') ?? (error instanceof Error ? error.name : null)
  const code = getStringProperty(error, 'code')
  const message = getDatabaseMessage(error)
  const details = getStringProperty(error, 'details')
  const hint = getStringProperty(error, 'hint')

  return {
    requestId,
    operation,
    ...(name ? { errorName: sanitizeDatabaseText(name) } : {}),
    ...(code ? { postgresCode: sanitizeDatabaseText(code) } : {}),
    ...(message ? { safeMessage: sanitizeDatabaseText(message) } : {}),
    ...(details ? { details: sanitizeDatabaseText(details) } : {}),
    ...(hint ? { hint: sanitizeDatabaseText(hint) } : {}),
    functionName: 'rpc_complete_tenant_onboarding',
  }
}

export function classifyOnboardingDatabaseError(error: unknown, hasAuthenticatedSession: boolean): OnboardingErrorClassification {
  const code = getStringProperty(error, 'code')
  const message = getDatabaseMessage(error).toUpperCase()
  const details = (getStringProperty(error, 'details') ?? '').toUpperCase()

  if (message.includes('SESSION_REQUIRED')) {
    return { code: 'SESSION_REQUIRED', message: 'SESSION_REQUIRED', status: 401, category: 'ONBOARDING_SESSION_REQUIRED' }
  }
  if (message.includes('ONBOARDING_ALREADY_COMPLETED')) {
    return {
      code: 'ONBOARDING_ALREADY_COMPLETED',
      message: 'ONBOARDING_ALREADY_COMPLETED',
      status: 409,
      category: 'ONBOARDING_DATABASE_CONSTRAINT_FAILED',
    }
  }
  if (message.includes('PLAN_NOT_AVAILABLE')) {
    return { code: 'PLAN_NOT_AVAILABLE', message: 'PLAN_NOT_AVAILABLE', status: 404, category: 'ONBOARDING_DATABASE_CONSTRAINT_FAILED' }
  }
  if (message.includes('INVALID_INPUT')) {
    return { code: 'INVALID_INPUT', message: 'Request validation failed', status: 400, category: 'ONBOARDING_DATABASE_CONSTRAINT_FAILED' }
  }
  if (message.includes('TENANT_OWNER_ROLE_MISSING') || details.includes('TENANT_USER_ROLES') || details.includes('ROLE_ID')) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'Tenant owner role seed data is missing',
      status: 500,
      category: 'ONBOARDING_TENANT_OWNER_ROLE_MISSING',
    }
  }
  if (code === 'PGRST202') {
    return {
      code: 'INTERNAL_ERROR',
      message: 'Onboarding function is not available',
      status: 500,
      category: 'ONBOARDING_RPC_NOT_FOUND',
    }
  }
  if (code === '42883' || message.includes('DIGEST') || message.includes('GEN_RANDOM_UUID')) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'Onboarding crypto helpers are not available',
      status: 500,
      category: 'ONBOARDING_CRYPTO_FUNCTION_UNAVAILABLE',
    }
  }
  if (code === '42702' && message.includes('RESULT')) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'Onboarding idempotency result could not be saved',
      status: 500,
      category: 'ONBOARDING_IDEMPOTENCY_RESULT_WRITE_FAILED',
    }
  }
  if (code === '42501' || code === '28000') {
    if (!hasAuthenticatedSession) {
      return { code: 'SESSION_REQUIRED', message: 'SESSION_REQUIRED', status: 401, category: 'ONBOARDING_SESSION_REQUIRED' }
    }
    return {
      code: 'INTERNAL_ERROR',
      message: 'Onboarding storage is not accessible',
      status: 500,
      category: 'ONBOARDING_DATABASE_PERMISSION_DENIED',
    }
  }
  if (code && ['22023', '23502', '23503', '23505', '23514'].includes(code)) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'Onboarding storage rejected the request',
      status: 500,
      category: 'ONBOARDING_DATABASE_CONSTRAINT_FAILED',
    }
  }

  return {
    code: 'INTERNAL_ERROR',
    message: 'Unable to complete onboarding',
    status: 500,
    category: 'UNKNOWN_ONBOARDING_DATABASE_ERROR',
  }
}
