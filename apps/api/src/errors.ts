import type { ApiErrorCode } from '@ahadi/types'
import type { NextFunction, Request, Response } from 'express'
import { ZodError } from 'zod'

const errorStatus: Record<ApiErrorCode, number> = {
  INVALID_INPUT: 400,
  INVALID_PHONE: 400,
  OTP_REQUEST_FAILED: 429,
  INVALID_OTP: 401,
  SESSION_REQUIRED: 401,
  PIN_REQUIRED: 428,
  PIN_INVALID: 401,
  PIN_LOCKED: 423,
  TENANT_ACCESS_DENIED: 403,
  ONBOARDING_ALREADY_COMPLETED: 409,
  PLAN_NOT_AVAILABLE: 404,
  SUBSCRIPTION_INACTIVE: 402,
  RATE_LIMITED: 429,
  INTERNAL_ERROR: 500,
}

export class AppError extends Error {
  code: ApiErrorCode
  status: number

  constructor(code: ApiErrorCode, message: string = code, status = errorStatus[code]) {
    super(message)
    this.code = code
    this.status = status ?? 500
  }
}

export function mapUnknownError(error: unknown): AppError {
  if (error instanceof AppError) {
    return error
  }
  if (error instanceof ZodError) {
    return new AppError('INVALID_INPUT', 'Request validation failed', 400)
  }
  if (error instanceof Error) {
    const message = error.message.toUpperCase()
    const matchedCode = Object.keys(errorStatus).find((code) => message.includes(code)) as ApiErrorCode | undefined
    if (matchedCode) {
      return new AppError(matchedCode)
    }
  }
  return new AppError('INTERNAL_ERROR', 'Unexpected application error')
}

export function errorHandler(error: unknown, request: Request, response: Response, _next: NextFunction) {
  void _next
  const appError = mapUnknownError(error)
  response.status(appError.status).json({
    error: {
      code: appError.code,
      message: appError.status >= 500 ? 'Unexpected application error' : appError.message,
      requestId: request.requestId,
    },
  })
}
