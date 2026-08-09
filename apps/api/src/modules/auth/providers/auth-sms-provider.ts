import {
  formatWebBulkSmsPhone,
  parseSmsProviderResponse,
  parseWebBulkSmsResponse,
  sanitizeProviderReason,
  sendWebBulkSms,
  SmsProviderError,
  type SmsProviderOptions,
  type SmsProviderResult,
} from '@ahadi/sms'
import { env } from '../../../env.js'
import { logOtpDiagnostic, maskPhoneForLog, type SafeLogger } from '../../../diagnostics.js'

export interface AuthenticationSmsInput {
  requestId?: string
  to: string
  message: string
}

export interface AuthenticationSmsProviderOptions extends Partial<Omit<SmsProviderOptions, 'password' | 'providerUrl' | 'senderId' | 'username'>> {
  password?: string
  providerUrl?: string
  senderId?: string
  logger?: SafeLogger
  username?: string
}

function maskWebBulkSmsPhoneForLog(phone: string): string {
  return phone.length >= 7 ? `${phone.slice(0, 4)}*****${phone.slice(-3)}` : '***'
}

export async function sendAuthenticationSms(input: AuthenticationSmsInput, options: AuthenticationSmsProviderOptions = {}): Promise<SmsProviderResult> {
  const providerUrl = options.providerUrl ?? env.SMS_PROVIDER_URL
  const username = options.username ?? env.SMS_USERNAME
  const password = options.password ?? env.SMS_PASSWORD
  const senderId = (options.senderId ?? env.SMS_SENDER_ID).trim()
  const timeoutMs = options.timeoutMs ?? 10_000
  const logger = options.logger ?? console
  if (!providerUrl || !username || !password) {
    throw new SmsProviderError('Authentication SMS provider is not configured', 401, 'PROVIDER_AUTH_FAILED', 'PROVIDER_AUTH_FAILED', false)
  }
  const providerPhoneNumber = formatWebBulkSmsPhone(input.to)
  const providerHost = new URL(providerUrl).hostname

  logOtpDiagnostic(logger, 'SMS_PROVIDER_REQUEST_STARTED', {
    requestId: input.requestId,
    providerHost,
    method: 'POST',
    contentType: 'application/json',
    requestFieldNames: ['username', 'password', 'senderId', 'message', 'phoneNumbers'],
    senderFieldName: 'senderId',
    senderId,
    destinationFieldName: 'phoneNumbers',
    destinationIsArray: true,
    destinationCount: 1,
    maskedDestination: maskWebBulkSmsPhoneForLog(providerPhoneNumber),
  })

  try {
    const providerOptions: SmsProviderOptions = options.fetchImpl ? {
      fetchImpl: options.fetchImpl,
      password,
      providerUrl,
      senderId,
      timeoutMs,
      username,
    } : {
      password,
      providerUrl,
      senderId,
      timeoutMs,
      username,
    }
    const result = await sendWebBulkSms(input, providerOptions)

    logOtpDiagnostic(logger, 'SMS_PROVIDER_ACCEPTED', {
      requestId: input.requestId,
      providerHttpStatus: result.providerHttpStatus,
      providerStatusCode: result.providerStatusCode,
      providerMessageId: result.providerMessageId,
    })

    return result
  } catch (error) {
    if (error instanceof SmsProviderError) {
      const stage = error.status ? (error.status >= 200 && error.status < 300 ? 'SMS_PROVIDER_REJECTED' : 'SMS_PROVIDER_HTTP_ERROR') : 'SMS_PROVIDER_NETWORK_ERROR'
      logOtpDiagnostic(logger, stage, {
        requestId: input.requestId,
        to: maskPhoneForLog(input.to),
        providerHttpStatus: error.status,
        providerStatusCode: error.providerStatusCode,
        accepted: error.providerAccepted,
      })
    }
    throw error
  }
}

export { formatWebBulkSmsPhone, parseSmsProviderResponse, parseWebBulkSmsResponse, sanitizeProviderReason, SmsProviderError }
export type { SmsProviderResult }
