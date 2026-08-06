import type { ApiErrorCode } from '@ahadi/types'
import type { ZodError } from 'zod'

export type PinDatabaseFailureCategory =
  | 'PIN_RPC_NOT_FOUND'
  | 'PIN_HASH_FUNCTION_UNAVAILABLE'
  | 'PIN_STORAGE_TABLE_MISSING'
  | 'PIN_DATABASE_PERMISSION_DENIED'
  | 'PIN_SESSION_REQUIRED'
  | 'PIN_DATABASE_CONSTRAINT_FAILED'
  | 'UNKNOWN_PIN_DATABASE_ERROR'

export interface PinErrorClassification {
  category?: PinDatabaseFailureCategory
  code: ApiErrorCode
  message: string
  status: number
}

export interface SafePinDatabaseErrorDetails {
  details?: string
  errorName?: string
  functionName?: string
  hint?: string
  operation: 'set-pin'
  postgresCode?: string
  requestId: string
  safeMessage?: string
}

const constraintSqlStates = new Set(['22023', '23502', '23503', '23505', '23514'])

function getStringProperty(error: unknown, key: string): string | null {
  if (typeof error === 'object' && error !== null && key in error) {
    const value = (error as Record<string, unknown>)[key]
    return typeof value === 'string' ? value : null
  }
  return null
}

function sanitizeDatabaseText(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer <redacted-token>')
    .replace(/\b((?:access|refresh)_token)\b\s*[:=]\s*['"]?[^'",\s}]+/gi, '$1=<redacted-token>')
    .replace(/\b[0-9]{4,6}\b/g, '<redacted-code>')
    .slice(0, 320)
}

function getDatabaseMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }
  return getStringProperty(error, 'message') ?? ''
}

function getDatabaseCode(error: unknown): string | null {
  return getStringProperty(error, 'code')
}

export function getSafePinDatabaseErrorDetails(requestId: string, operation: 'set-pin', error: unknown): SafePinDatabaseErrorDetails {
  const name = getStringProperty(error, 'name') ?? (error instanceof Error ? error.name : null)
  const code = getDatabaseCode(error)
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
    functionName: 'rpc_set_my_pin',
  }
}

export function classifyPinSetupValidationError(error: ZodError): PinErrorClassification {
  const hasPinFormatIssue = error.issues.some((issue) => ['pin', 'confirmPin'].includes(issue.path.join('.')) && issue.code === 'invalid_format')
  if (hasPinFormatIssue) {
    return { code: 'PIN_INVALID', message: 'PIN_INVALID', status: 400 }
  }
  const hasWeakPinIssue = error.issues.some((issue) => issue.path.join('.') === 'pin' && issue.message === 'Choose a stronger PIN')
  if (hasWeakPinIssue) {
    return { code: 'PIN_TOO_WEAK', message: 'PIN_TOO_WEAK', status: 400 }
  }
  return { code: 'PIN_INVALID', message: 'PIN_INVALID', status: 400 }
}

export function classifyPinSetupDatabaseError(error: unknown, hasAuthenticatedSession: boolean): PinErrorClassification {
  const code = getDatabaseCode(error)
  const message = getDatabaseMessage(error).toUpperCase()
  const details = (getStringProperty(error, 'details') ?? '').toUpperCase()

  if (message.includes('PIN_TOO_WEAK')) {
    return { code: 'PIN_TOO_WEAK', message: 'PIN_TOO_WEAK', status: 400, category: 'PIN_DATABASE_CONSTRAINT_FAILED' }
  }
  if (message.includes('PIN_INVALID')) {
    return { code: 'PIN_INVALID', message: 'PIN_INVALID', status: 400, category: 'PIN_DATABASE_CONSTRAINT_FAILED' }
  }
  if (message.includes('SESSION_REQUIRED')) {
    return { code: 'SESSION_REQUIRED', message: 'SESSION_REQUIRED', status: 401, category: 'PIN_SESSION_REQUIRED' }
  }
  if (code === 'PGRST202') {
    return { code: 'INTERNAL_ERROR', message: 'PIN setup function is not available', status: 500, category: 'PIN_RPC_NOT_FOUND' }
  }
  if (code === '42883' || details.includes('GEN_SALT') || details.includes('CRYPT(') || message.includes('GEN_SALT') || message.includes('CRYPT(')) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'PIN hashing is not available',
      status: 500,
      category: 'PIN_HASH_FUNCTION_UNAVAILABLE',
    }
  }
  if (code === '42P01' || message.includes('USER_PIN_CREDENTIALS')) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'PIN credential storage is not available',
      status: 500,
      category: 'PIN_STORAGE_TABLE_MISSING',
    }
  }
  if (code === '42501') {
    if (!hasAuthenticatedSession) {
      return { code: 'SESSION_REQUIRED', message: 'SESSION_REQUIRED', status: 401, category: 'PIN_SESSION_REQUIRED' }
    }
    return {
      code: 'INTERNAL_ERROR',
      message: 'PIN credential storage is not accessible',
      status: 500,
      category: 'PIN_DATABASE_PERMISSION_DENIED',
    }
  }
  if (code && constraintSqlStates.has(code)) {
    return {
      code: 'INTERNAL_ERROR',
      message: 'PIN credential storage rejected the request',
      status: 500,
      category: 'PIN_DATABASE_CONSTRAINT_FAILED',
    }
  }

  return {
    code: 'INTERNAL_ERROR',
    message: 'Unable to set PIN',
    status: 500,
    category: 'UNKNOWN_PIN_DATABASE_ERROR',
  }
}
