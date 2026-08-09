import type { ApiErrorCode } from '@ahadi/types'
import type { NextFunction, Request, Response } from 'express'
import { ZodError } from 'zod'

const errorStatus: Record<ApiErrorCode, number> = {
  INVALID_INPUT: 400,
  INVALID_PHONE: 400,
  OTP_REQUEST_FAILED: 502,
  INVALID_OTP: 401,
  SESSION_REQUIRED: 401,
  PIN_REQUIRED: 428,
  PIN_TOO_WEAK: 400,
  PIN_INVALID: 400,
  PIN_LOCKED: 423,
  TENANT_ACCESS_DENIED: 403,
  PLATFORM_ACCESS_DENIED: 403,
  PERMISSION_DENIED: 403,
  ONBOARDING_ALREADY_COMPLETED: 409,
  REGISTRATION_PAUSED: 503,
  INVITATION_REQUIRED: 403,
  INVITATION_INVALID: 403,
  FEATURE_DISABLED: 403,
  PLAN_NOT_AVAILABLE: 404,
  SUBSCRIPTION_INACTIVE: 402,
  MEMBER_NOT_FOUND: 404,
  MEMBER_PHONE_ALREADY_EXISTS: 409,
  MEMBER_ALREADY_IN_EVENT: 409,
  EVENT_MEMBER_NOT_FOUND: 404,
  EVENT_MEMBER_REMOVED: 409,
  CATEGORY_NOT_FOUND: 404,
  PLEDGE_NOT_FOUND: 404,
  PLEDGE_ALREADY_EXISTS: 409,
  PLEDGE_AMOUNT_INVALID: 400,
  PLEDGE_BELOW_PAID_AMOUNT: 409,
  PLEDGE_CANCELLED: 409,
  PAYMENT_NOT_FOUND: 404,
  PAYMENT_AMOUNT_INVALID: 400,
  PAYMENT_REFERENCE_DUPLICATE: 409,
  PAYMENT_ALREADY_REVERSED: 409,
  PAYMENT_REVERSAL_REASON_REQUIRED: 400,
  PAYMENT_IDEMPOTENCY_CONFLICT: 409,
  EVENT_NOT_ACTIVE: 409,
  EVENT_ACCESS_DENIED: 403,
  EVENT_LIMIT_REACHED: 409,
  INVALID_EVENT_TYPE: 400,
  INVALID_EVENT_DATE: 400,
  INVALID_TARGET_AMOUNT: 400,
  RECEIPT_NOT_FOUND: 404,
  SUBSCRIPTION_READ_ONLY: 402,
  SUBSCRIPTION_BLOCKED: 402,
  RATE_LIMITED: 429,
  INVALID_WEBHOOK_SIGNATURE: 401,
  INVALID_SMS_HOOK_PAYLOAD: 400,
  SMS_PROVIDER_FAILED: 502,
  BALANCE_REMINDER_NOT_ELIGIBLE: 409,
  NO_OUTSTANDING_BALANCE: 409,
  MEMBER_PHONE_MISSING: 409,
  MEMBER_SMS_DISABLED: 409,
  BALANCE_REMINDER_RECENTLY_SENT: 409,
  SMS_LIMIT_REACHED: 402,
  SMS_TEMPLATE_NOT_FOUND: 404,
  SMS_TEMPLATE_INVALID: 400,
  REMINDER_BATCH_TOO_LARGE: 400,
  REMINDER_BATCH_EMPTY: 400,
  SHARE_WHATSAPP_ACCESS_DENIED: 403,
  SHARE_WHATSAPP_FINANCIAL_REQUIRED: 403,
  SHARE_SETTINGS_ACCESS_DENIED: 403,
  REPORT_ACCESS_DENIED: 403,
  REPORT_EXPORT_NOT_ALLOWED: 403,
  REPORT_FORMAT_NOT_SUPPORTED: 400,
  REPORT_EXPORT_TOO_LARGE: 413,
  REPORT_EXPORT_FAILED: 502,
  MEMBER_STATEMENT_NOT_FOUND: 404,
  INVALID_EXPORT_FILTER: 400,
  EXPORT_PERMISSION_DENIED: 403,
  PAYMENT_GATEWAY_DISABLED: 403,
  PAYMENT_PROVIDER_UNAVAILABLE: 503,
  PAYMENT_INTENT_NOT_FOUND: 404,
  PAYMENT_INTENT_EXPIRED: 409,
  PAYMENT_INTENT_ALREADY_COMPLETED: 409,
  INVOICE_NOT_PAYABLE: 409,
  PAYMENT_AMOUNT_MISMATCH: 409,
  PAYMENT_CURRENCY_MISMATCH: 409,
  PAYMENT_WEBHOOK_INVALID: 401,
  PAYMENT_WEBHOOK_DUPLICATE: 409,
  PAYMENT_TRANSACTION_UNKNOWN: 404,
  PAYMENT_ALREADY_PROCESSED: 409,
  PAYMENT_REVERSAL_ALREADY_PROCESSED: 409,
  PAYMENT_RECONCILIATION_REQUIRED: 409,
  INTERNAL_ERROR: 500,
}

export class AppError extends Error {
  category: string | undefined
  code: ApiErrorCode
  status: number

  constructor(code: ApiErrorCode, message: string = code, status = errorStatus[code], category?: string) {
    super(message)
    this.category = category
    this.code = code
    this.status = status ?? 500
  }
}

function getStringProperty(error: unknown, key: string): string | null {
  if (typeof error === 'object' && error !== null && key in error) {
    const value = (error as Record<string, unknown>)[key]
    return typeof value === 'string' ? value : null
  }
  return null
}

function getRawErrorText(error: unknown): string {
  const message = error instanceof Error ? error.message : getStringProperty(error, 'message')
  const details = getStringProperty(error, 'details')
  const hint = getStringProperty(error, 'hint')
  const code = getStringProperty(error, 'code')
  return [message, details, hint, code].filter(Boolean).join(' ')
}

function sanitizeErrorText(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer <redacted-token>')
    .replace(/\b((?:access|refresh)_token)\b\s*[:=]\s*['"]?[^'",\s}]+/gi, '$1=<redacted-token>')
    .replace(/[+0-9][0-9\s().-]{6,}/g, '<redacted-phone-or-number>')
    .slice(0, 360)
}

export function mapUnknownError(error: unknown): AppError {
  if (error instanceof AppError) {
    return error
  }
  if (error instanceof ZodError) {
    return new AppError('INVALID_INPUT', 'Request validation failed', 400)
  }
  const message = getRawErrorText(error).toUpperCase()
  const matchedCode = Object.keys(errorStatus).find((code) => message.includes(code)) as ApiErrorCode | undefined
  if (matchedCode) {
    return new AppError(matchedCode)
  }
  const providerCode = getStringProperty(error, 'code')
  if (providerCode === '42501') {
    return new AppError('PERMISSION_DENIED')
  }
  if (providerCode === '23514') {
    if (message.includes('EVENT_TYPE')) {
      return new AppError('INVALID_EVENT_TYPE')
    }
    if (message.includes('EVENT_DATE') || message.includes('PLEDGE_DEADLINE')) {
      return new AppError('INVALID_EVENT_DATE')
    }
    if (message.includes('TARGET_AMOUNT')) {
      return new AppError('INVALID_TARGET_AMOUNT')
    }
  }
  return new AppError('INTERNAL_ERROR', 'Unexpected application error')
}

function logUnhandledError(error: unknown, appError: AppError, request: Request, isKnownApplicationError: boolean) {
  if (appError.status < 500 && isKnownApplicationError) {
    return
  }
  const errorName = getStringProperty(error, 'name') ?? (error instanceof Error ? error.name : null)
  const providerCode = getStringProperty(error, 'code')
  const rawText = getRawErrorText(error)
  console.error('API request failed', {
    requestId: request.requestId,
    method: request.method,
    path: request.originalUrl,
    code: appError.code,
    status: appError.status,
    ...(appError.category ? { category: appError.category } : {}),
    ...(errorName ? { errorName: sanitizeErrorText(errorName) } : {}),
    ...(providerCode ? { providerCode: sanitizeErrorText(providerCode) } : {}),
    ...(rawText ? { safeMessage: sanitizeErrorText(rawText) } : {}),
  })
}

export function errorHandler(error: unknown, request: Request, response: Response, _next: NextFunction) {
  void _next
  const appError = mapUnknownError(error)
  const isKnownApplicationError = error instanceof AppError
  logUnhandledError(error, appError, request, isKnownApplicationError)
  response.status(appError.status).json({
    error: {
      code: appError.code,
      ...(process.env['NODE_ENV'] === 'development' && appError.category ? { category: appError.category } : {}),
      message: appError.status >= 500 && !isKnownApplicationError ? 'Unexpected application error' : appError.message,
      requestId: request.requestId,
    },
  })
}
