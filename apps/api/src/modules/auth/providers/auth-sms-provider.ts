import { env } from '../../../env.js'
import { logOtpDiagnostic, maskPhoneForLog, type SafeLogger } from '../../../diagnostics.js'
import { normalizeTanzaniaPhone } from '@ahadi/validation'

export interface AuthenticationSmsInput {
  requestId?: string
  to: string
  message: string
}

export interface AuthenticationSmsProviderOptions {
  fetchImpl?: typeof fetch
  password?: string
  providerUrl?: string
  senderId?: string
  logger?: SafeLogger
  timeoutMs?: number
  username?: string
}

export interface SmsProviderResult {
  accepted: boolean
  providerHttpStatus?: number
  providerMessageId: string | null
  providerStatusCode: string | null
  safeReason: string | null
}

interface ParseWebBulkSmsResponseInput {
  httpStatus: number
  responseBody: unknown
}

interface WebBulkSmsRequest {
  username: string
  password: string
  senderId: string
  message: string
  phoneNumbers: string[]
}

export class SmsProviderError extends Error {
  readonly providerAccepted: boolean | undefined
  readonly providerReason: string | undefined
  readonly status: number | undefined
  readonly providerStatusCode: string | undefined

  constructor(message = 'SMS provider failed', status?: number, providerReason?: string, providerStatusCode?: string | null, providerAccepted?: boolean) {
    super(message)
    this.name = 'SmsProviderError'
    this.status = status
    this.providerReason = providerReason
    this.providerStatusCode = providerStatusCode ?? undefined
    this.providerAccepted = providerAccepted
  }
}

function getStringProperty(value: unknown, keys: string[]): string | null {
  if (typeof value !== 'object' || value === null) {
    return null
  }
  const record = value as Record<string, unknown>
  for (const key of keys) {
    const property = record[key]
    if (typeof property === 'string' && property.trim()) {
      return property.trim()
    }
    if (typeof property === 'number') {
      return String(property)
    }
  }
  return null
}

function getBooleanProperty(value: unknown, keys: string[]): boolean | null {
  if (typeof value !== 'object' || value === null) {
    return null
  }
  const record = value as Record<string, unknown>
  for (const key of keys) {
    const property = record[key]
    if (typeof property === 'boolean') {
      return property
    }
  }
  return null
}

function parseProviderJson(value: unknown): SmsProviderResult {
  const candidate = Array.isArray(value) ? value[0] : value
  const providerMessageId = getStringProperty(candidate, ['message_id', 'messageId', 'msgid', 'msg_id', 'id', 'reference', 'batch_id'])
  const providerStatusCode = getStringProperty(candidate, ['status_code', 'statusCode', 'code', 'response_code', 'responseCode', 'status'])
  const providerMessage = getStringProperty(candidate, ['message'])
  const explicitSuccess = getBooleanProperty(candidate, ['success', 'accepted', 'ok'])
  const safeReason = getProviderReasonFromJson(candidate)
  if (explicitSuccess !== null) {
    return { accepted: explicitSuccess, providerMessageId, providerStatusCode, safeReason }
  }

  const status = getStringProperty(candidate, ['status', 'state', 'code', 'response_code', 'responseCode'])
  if (status) {
    const normalizedStatus = status.toLowerCase()
    const accepted = ['0', '00', '000', '200', '201', '202', '1701', 'ok', 'success', 'successful', 'accepted', 'queued', 'sent'].includes(normalizedStatus)
    return { accepted, providerMessageId, providerStatusCode: status, safeReason }
  }

  if (providerMessage) {
    const normalizedMessage = providerMessage.toLowerCase()
    const accepted = ['sent sms successfully', 'sms sent successfully', 'sent successfully', 'success'].some((message) => normalizedMessage.includes(message))
    return { accepted, providerMessageId, providerStatusCode, safeReason: accepted ? null : safeReason }
  }

  return { accepted: Boolean(providerMessageId), providerMessageId, providerStatusCode, safeReason }
}

function getProviderReasonFromJson(value: unknown): string | null {
  const candidate = Array.isArray(value) ? value[0] : value
  return getStringProperty(candidate, ['message', 'error', 'error_message', 'errorMessage', 'description'])
}

export function sanitizeProviderReason(responseBody: string): string | undefined {
  const trimmed = responseBody.trim()
  if (!trimmed) {
    return undefined
  }

  let reason: string | null
  try {
    reason = getProviderReasonFromJson(JSON.parse(trimmed) as unknown)
  } catch {
    reason = trimmed
  }

  return reason?.replace(/[+0-9][0-9\s().-]{6,}/g, '<redacted-phone>').slice(0, 160)
}

export function parseSmsProviderResponse(responseBody: string): SmsProviderResult {
  const trimmed = responseBody.trim()
  if (!trimmed) {
    return { accepted: false, providerMessageId: null, providerStatusCode: null, safeReason: null }
  }

  try {
    return parseProviderJson(JSON.parse(trimmed) as unknown)
  } catch {
    const normalizedBody = trimmed.toLowerCase()
    const providerStatusCode = trimmed.match(/^([A-Za-z0-9_-]+)/)?.[1] ?? null
    const accepted = /(^|\b)(success|successful|accepted|queued|sent|ok)(\b|$)/.test(normalizedBody) || /^(0|00|000|1701)(\b|[|,:\s])/.test(normalizedBody)
    return { accepted, providerMessageId: null, providerStatusCode, safeReason: accepted ? null : (sanitizeProviderReason(trimmed) ?? null) }
  }
}

export function parseWebBulkSmsResponse(input: ParseWebBulkSmsResponseInput): SmsProviderResult {
  let result: SmsProviderResult
  if (typeof input.responseBody === 'string') {
    result = parseSmsProviderResponse(input.responseBody)
  } else if (input.responseBody === null || input.responseBody === undefined) {
    result = { accepted: false, providerMessageId: null, providerStatusCode: null, safeReason: null }
  } else {
    result = parseProviderJson(input.responseBody)
  }
  result.providerHttpStatus = input.httpStatus
  return result
}

export function formatWebBulkSmsPhone(phoneE164: string): string {
  const normalized = normalizeTanzaniaPhone(phoneE164)
  return normalized.startsWith('+') ? normalized.slice(1) : normalized
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
  const fetchImpl = options.fetchImpl ?? fetch
  const logger = options.logger ?? console
  const providerPhoneNumber = formatWebBulkSmsPhone(input.to)
  const providerHost = new URL(providerUrl).hostname
  const payload: WebBulkSmsRequest = {
    username,
    password,
    senderId,
    message: input.message,
    phoneNumbers: [providerPhoneNumber],
  }

  let response: Response
  try {
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
    response = await fetchImpl(providerUrl, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs),
    })
  } catch (error) {
    const isTimeout = error instanceof Error && error.name === 'TimeoutError'
    logOtpDiagnostic(logger, isTimeout ? 'SMS_PROVIDER_TIMEOUT' : 'SMS_PROVIDER_NETWORK_ERROR', {
      requestId: input.requestId,
      to: maskPhoneForLog(input.to),
    })
    throw new SmsProviderError(isTimeout ? 'SMS provider timeout' : 'SMS provider network error')
  }

  const responseContentType = response.headers.get('content-type') ?? ''
  const responseBody: unknown = responseContentType.includes('application/json') ? await response.json().catch(() => null) : await response.text().catch(() => null)
  const result = parseWebBulkSmsResponse({ httpStatus: response.status, responseBody })
  const providerReason = result.safeReason ?? (typeof responseBody === 'string' ? sanitizeProviderReason(responseBody) : undefined)
  logOtpDiagnostic(logger, 'SMS_PROVIDER_RESPONSE_RECEIVED', {
    requestId: input.requestId,
    providerHttpStatus: response.status,
    providerStatusCode: result.providerStatusCode,
    accepted: result.accepted,
    providerMessageId: result.providerMessageId,
    safeReason: result.safeReason,
  })

  if (!response.ok) {
    logOtpDiagnostic(logger, 'SMS_PROVIDER_HTTP_ERROR', {
      requestId: input.requestId,
      providerHttpStatus: response.status,
      providerStatusCode: result.providerStatusCode,
      accepted: result.accepted,
    })
    throw new SmsProviderError('SMS provider rejected message', response.status, providerReason, result.providerStatusCode, result.accepted)
  }

  if (!result.accepted) {
    logOtpDiagnostic(logger, 'SMS_PROVIDER_REJECTED', {
      requestId: input.requestId,
      providerHttpStatus: response.status,
      providerStatusCode: result.providerStatusCode,
      accepted: result.accepted,
    })
    throw new SmsProviderError('SMS provider reported failure', response.status, providerReason, result.providerStatusCode, result.accepted)
  }

  logOtpDiagnostic(logger, 'SMS_PROVIDER_ACCEPTED', {
    requestId: input.requestId,
    providerHttpStatus: response.status,
    providerStatusCode: result.providerStatusCode,
    providerMessageId: result.providerMessageId,
  })

  return result
}
