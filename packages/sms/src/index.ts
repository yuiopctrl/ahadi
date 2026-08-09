import { normalizeTanzaniaPhone } from '@ahadi/validation'

export interface SmsProviderInput {
  requestId?: string
  to: string
  message: string
  senderId?: string | null
}

export type SmsProviderName = 'WEBBULKSMS' | 'NEXTSMS'

export interface WebBulkSmsProviderOptions {
  fetchImpl?: typeof fetch
  password: string
  providerUrl: string
  senderId: string
  timeoutMs?: number
  username: string
}

export type SmsProviderOptions = WebBulkSmsProviderOptions

export interface NextSmsProviderOptions {
  authorization?: string
  baseUrl: string
  defaultSenderId: string
  fetchImpl?: typeof fetch
  singleSmsPath: string
  allowedSenderIds?: string[]
  timeoutMs?: number
}

export type ConfiguredSmsProviderOptions =
  | ({ provider: 'WEBBULKSMS' } & WebBulkSmsProviderOptions)
  | ({ provider: 'NEXTSMS' } & NextSmsProviderOptions)

export interface SmsProviderResult {
  accepted: boolean
  providerHttpStatus?: number
  providerMessageId: string | null
  providerStatusCode: string | null
  safeReason: string | null
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

export const defaultNextSmsBaseUrl = 'https://messaging-service.co.tz'
export const defaultNextSmsSingleSmsPath = '/api/sms/v1/text/single'
export const nextSmsAllowedSenderIds = ['SHEREHE', 'MICHANGO', 'KIKAO'] as const
export const MAX_SMS_CHARACTERS = 159
export type NextSmsSenderId = typeof nextSmsAllowedSenderIds[number]

export function buildNextSmsSingleSmsUrl(baseUrl: string, singleSmsPath: string): string {
  return `${baseUrl.replace(/\/+$/, '')}/${singleSmsPath.replace(/^\/+/, '')}`
}

export function normalizeSmsMessageText(value: string): string {
  return value.replace(/\r\n/g, '\n').replace(/\n+/g, ' ').replace(/[ \t]+/g, ' ').trim()
}

export function smsCharacterCount(value: string): number {
  return Array.from(normalizeSmsMessageText(value)).length
}

export function assertSmsCharacterLimit(message: string): string {
  const normalized = normalizeSmsMessageText(message)
  const characters = smsCharacterCount(normalized)
  if (characters > MAX_SMS_CHARACTERS) {
    throw new SmsProviderError('SMS exceeds the permitted character limit', 400, 'SMS_CHARACTER_LIMIT_EXCEEDED', 'SMS_CHARACTER_LIMIT_EXCEEDED', false)
  }
  return normalized
}

export function normalizeSmsProviderName(value: string | null | undefined): SmsProviderName {
  const normalized = (value ?? '').trim().toUpperCase()
  if (normalized === 'NEXTSMS' || normalized === 'WEBBULKSMS') return normalized
  throw new SmsProviderError('SMS provider is not supported', 400, 'SMS_PROVIDER_NOT_SUPPORTED', 'SMS_PROVIDER_NOT_SUPPORTED', false)
}

export function normalizeSmsSenderId(value: string | null | undefined, allowedSenderIds: readonly string[] = nextSmsAllowedSenderIds): string {
  const normalized = (value ?? 'MICHANGO').trim().toUpperCase()
  const senderId = normalized || 'MICHANGO'
  const allowed = allowedSenderIds.map((item) => item.trim().toUpperCase()).filter(Boolean)
  if (!allowed.includes(senderId)) {
    throw new SmsProviderError('SMS sender id is not allowed', 400, 'SMS_SENDER_ID_NOT_ALLOWED', 'SMS_SENDER_ID_NOT_ALLOWED', false)
  }
  return senderId
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

function getNestedStatusProperty(value: unknown, keys: string[]): string | null {
  if (typeof value !== 'object' || value === null) {
    return null
  }
  const record = value as Record<string, unknown>
  const status = record['status']
  if (typeof status !== 'object' || status === null || Array.isArray(status)) {
    return null
  }
  return getStringProperty(status, keys)
}

function getProviderReasonFromJson(value: unknown): string | null {
  const candidate = Array.isArray(value) ? value[0] : value
  return getStringProperty(candidate, ['message', 'error', 'error_message', 'errorMessage', 'description'])
}

function getRawProviderMessageId(responseBody: string): string | null {
  for (const key of ['message_id', 'messageId', 'msgid', 'msg_id', 'reference', 'batch_id', 'id']) {
    const match = responseBody.match(new RegExp(`"${key}"\\s*:\\s*"?([^",}\\s]+)"?`, 'i'))
    if (match?.[1]) {
      return match[1]
    }
  }
  return null
}

function parseProviderJson(value: unknown): SmsProviderResult {
  const root = Array.isArray(value) ? value[0] : value
  const nestedMessages = typeof root === 'object' && root !== null && !Array.isArray(root) ? (root as Record<string, unknown>)['messages'] : null
  const candidate = Array.isArray(nestedMessages) ? nestedMessages[0] : root
  const providerMessageId = getStringProperty(candidate, ['message_id', 'messageId', 'msgid', 'msg_id', 'id', 'reference', 'batch_id'])
  const providerStatusCode = getStringProperty(candidate, ['status_code', 'statusCode', 'code', 'response_code', 'responseCode', 'status'])
    ?? getNestedStatusProperty(candidate, ['id', 'name', 'groupName', 'description'])
  const providerMessage = getStringProperty(candidate, ['message'])
  const explicitSuccess = getBooleanProperty(candidate, ['success', 'accepted', 'ok'])
  const safeReason = getProviderReasonFromJson(candidate)
  if (explicitSuccess !== null) {
    return { accepted: explicitSuccess, providerMessageId, providerStatusCode, safeReason }
  }

  const status = getStringProperty(candidate, ['status', 'state', 'code', 'response_code', 'responseCode'])
    ?? getNestedStatusProperty(candidate, ['groupName', 'name', 'description', 'id'])
  if (status) {
    const normalizedStatus = status.toLowerCase()
    const accepted = ['0', '00', '000', '18', '51', '200', '201', '202', '1701', 'ok', 'success', 'successful', 'accepted', 'pending', 'queued', 'sent', 'enroute (sent)', 'message sent to next instance'].includes(normalizedStatus)
    return { accepted, providerMessageId, providerStatusCode: status, safeReason: accepted ? null : safeReason }
  }

  if (providerMessage) {
    const normalizedMessage = providerMessage.toLowerCase()
    const accepted = ['sent sms successfully', 'sms sent successfully', 'sent successfully', 'success'].some((message) => normalizedMessage.includes(message))
    return { accepted, providerMessageId, providerStatusCode, safeReason: accepted ? null : safeReason }
  }

  return { accepted: Boolean(providerMessageId), providerMessageId, providerStatusCode, safeReason }
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
    const result = parseProviderJson(JSON.parse(trimmed) as unknown)
    return { ...result, providerMessageId: getRawProviderMessageId(trimmed) ?? result.providerMessageId }
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

export function formatNextSmsPhone(phoneE164: string): string {
  const normalized = normalizeTanzaniaPhone(phoneE164)
  return normalized.startsWith('+') ? normalized.slice(1) : normalized
}

export function maskSmsPhone(phone: string): string {
  return phone.replace(/[0-9](?=[0-9]{3})/g, '*')
}

export async function sendWebBulkSms(input: SmsProviderInput, options: WebBulkSmsProviderOptions): Promise<SmsProviderResult> {
  const providerPhoneNumber = formatWebBulkSmsPhone(input.to)
  const normalizedMessage = assertSmsCharacterLimit(input.message)
  const payload: WebBulkSmsRequest = {
    username: options.username,
    password: options.password,
    senderId: options.senderId.trim(),
    message: normalizedMessage,
    phoneNumbers: [providerPhoneNumber],
  }

  let response: Response
  try {
    response = await (options.fetchImpl ?? fetch)(options.providerUrl, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(options.timeoutMs ?? 10_000),
    })
  } catch (error) {
    const isTimeout = error instanceof Error && error.name === 'TimeoutError'
    throw new SmsProviderError(isTimeout ? 'SMS provider timeout' : 'SMS provider network error')
  }

  const responseBody = await response.text().catch(() => '')
  const result = parseSmsProviderResponse(responseBody)
  result.providerHttpStatus = response.status
  const providerReason = result.safeReason ?? sanitizeProviderReason(responseBody)

  if (!response.ok) {
    throw new SmsProviderError('SMS provider rejected message', response.status, providerReason, result.providerStatusCode, result.accepted)
  }

  if (!result.accepted) {
    throw new SmsProviderError('SMS provider reported failure', response.status, providerReason, result.providerStatusCode, result.accepted)
  }

  return result
}

export async function sendNextSms(input: SmsProviderInput, options: NextSmsProviderOptions): Promise<SmsProviderResult> {
  const senderId = normalizeSmsSenderId(input.senderId ?? options.defaultSenderId, options.allowedSenderIds ?? nextSmsAllowedSenderIds)
  const providerPhoneNumber = formatNextSmsPhone(input.to)
  const normalizedMessage = assertSmsCharacterLimit(input.message)
  if (!options.authorization?.trim()) {
    throw new SmsProviderError('NextSMS authorization is not configured', 401, 'PROVIDER_AUTH_FAILED', 'PROVIDER_AUTH_FAILED', false)
  }
  if (!options.baseUrl.trim() || !options.singleSmsPath.trim()) {
    throw new SmsProviderError('NextSMS endpoint is not configured', 400, 'PROVIDER_CONFIG_INVALID', 'PROVIDER_CONFIG_INVALID', false)
  }

  const payload = {
    from: senderId,
    to: providerPhoneNumber,
    text: normalizedMessage,
  }

  let response: Response
  try {
    response = await (options.fetchImpl ?? fetch)(buildNextSmsSingleSmsUrl(options.baseUrl, options.singleSmsPath), {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        Authorization: options.authorization.trim(),
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(options.timeoutMs ?? 10_000),
    })
  } catch (error) {
    const isTimeout = error instanceof Error && error.name === 'TimeoutError'
    throw new SmsProviderError(isTimeout ? 'SMS provider timeout' : 'SMS provider network error')
  }

  const responseBody = await response.text().catch(() => '')
  const result = parseSmsProviderResponse(responseBody)
  result.providerHttpStatus = response.status
  const providerReason = result.safeReason ?? sanitizeProviderReason(responseBody)

  if (!response.ok) {
    throw new SmsProviderError('SMS provider rejected message', response.status, providerReason, result.providerStatusCode, result.accepted)
  }

  if (!result.accepted) {
    throw new SmsProviderError('SMS provider reported failure', response.status, providerReason, result.providerStatusCode, result.accepted)
  }

  return result
}

export async function sendSmsWithProvider(input: SmsProviderInput, options: ConfiguredSmsProviderOptions): Promise<SmsProviderResult> {
  if (options.provider === 'NEXTSMS') {
    return sendNextSms(input, options)
  }
  return sendWebBulkSms(input, {
    password: options.password,
    providerUrl: options.providerUrl,
    senderId: input.senderId ?? options.senderId,
    username: options.username,
    ...(options.fetchImpl ? { fetchImpl: options.fetchImpl } : {}),
    ...(options.timeoutMs ? { timeoutMs: options.timeoutMs } : {}),
  })
}

export interface SmsProviderRuntimeConfig {
  fetchImpl?: typeof fetch | undefined
  nextSmsAuthorization?: string | null | undefined
  nextSmsBaseUrl?: string | null | undefined
  nextSmsDefaultSenderId?: string | null | undefined
  nextSmsSingleSmsPath?: string | null | undefined
  nextSmsAllowedSenderIds?: string[] | readonly string[] | null | undefined
  webBulkSmsPassword?: string | null | undefined
  webBulkSmsSenderId?: string | null | undefined
  webBulkSmsUrl?: string | null | undefined
  webBulkSmsUsername?: string | null | undefined
}

export class SmsProviderRegistry {
  constructor(private readonly config: SmsProviderRuntimeConfig) {}

  getProviderOptions(providerCode: string): ConfiguredSmsProviderOptions {
    const provider = normalizeSmsProviderName(providerCode)
    if (provider === 'NEXTSMS') {
      return {
        provider,
        baseUrl: this.config.nextSmsBaseUrl?.trim() || defaultNextSmsBaseUrl,
        singleSmsPath: this.config.nextSmsSingleSmsPath?.trim() || defaultNextSmsSingleSmsPath,
        defaultSenderId: normalizeSmsSenderId(this.config.nextSmsDefaultSenderId ?? 'MICHANGO', this.config.nextSmsAllowedSenderIds ?? nextSmsAllowedSenderIds),
        allowedSenderIds: (this.config.nextSmsAllowedSenderIds ?? nextSmsAllowedSenderIds).map((item) => item.trim().toUpperCase()).filter(Boolean),
        ...(this.config.nextSmsAuthorization?.trim() ? { authorization: this.config.nextSmsAuthorization.trim() } : {}),
        ...(this.config.fetchImpl ? { fetchImpl: this.config.fetchImpl } : {}),
      }
    }

    if (!this.config.webBulkSmsUrl?.trim() || !this.config.webBulkSmsUsername?.trim() || !this.config.webBulkSmsPassword?.trim()) {
      throw new SmsProviderError('WebBulkSMS provider is not configured', 401, 'PROVIDER_AUTH_FAILED', 'PROVIDER_AUTH_FAILED', false)
    }

    return {
      provider,
      password: this.config.webBulkSmsPassword,
      providerUrl: this.config.webBulkSmsUrl,
      senderId: this.config.webBulkSmsSenderId?.trim() || 'MICHANGO',
      username: this.config.webBulkSmsUsername,
      ...(this.config.fetchImpl ? { fetchImpl: this.config.fetchImpl } : {}),
    }
  }

  async sendSingle(input: SmsProviderInput & { providerCode: string }): Promise<SmsProviderResult> {
    const options = this.getProviderOptions(input.providerCode)
    return sendSmsWithProvider(input, options)
  }
}

export function formatTzsAmount(value: unknown): string {
  const numeric = Number(value)
  return new Intl.NumberFormat('en-TZ', { maximumFractionDigits: 0 }).format(Number.isFinite(numeric) ? numeric : 0)
}

const paymentMethodNames: Record<string, string> = {
  CASH: 'Cash',
  M_PESA: 'M-Pesa',
  AIRTEL_MONEY: 'Airtel Money',
  MIX_BY_YAS: 'Mixx by Yas',
  HALOPESA: 'Halopesa',
  BANK_TRANSFER: 'Bank Transfer',
  CHEQUE: 'Cheque',
  OTHER: 'Other',
}

export function paymentMethodDisplayName(method: string): string {
  return paymentMethodNames[method] ?? method.replaceAll('_', ' ').toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase())
}

export function renderSmsTemplate(body: string, variables: Record<string, string | number | null | undefined>): string {
  return body.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_match, key: string) => String(variables[key] ?? ''))
}
