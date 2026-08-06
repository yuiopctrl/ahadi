import type { Request, Response } from 'express'
import { Webhook, WebhookVerificationError } from 'standardwebhooks'
import { normalizeTanzaniaPhone } from '@ahadi/validation'
import { logOtpDiagnostic, maskPhoneForLog } from '../../../diagnostics.js'
import { env } from '../../../env.js'
import { type AuthenticationSmsInput, sendAuthenticationSms, SmsProviderError } from '../providers/auth-sms-provider.js'
import { sendSmsHookPayloadSchema } from './send-sms-hook.types.js'

const invalidSignatureResponse = {
  error: {
    code: 'INVALID_WEBHOOK_SIGNATURE',
    message: 'Webhook signature verification failed.',
  },
} as const

const invalidPayloadResponse = {
  error: {
    code: 'INVALID_SMS_HOOK_PAYLOAD',
    message: 'Invalid SMS hook payload.',
  },
} as const

const providerFailureResponse = {
  error: {
    code: 'SMS_PROVIDER_FAILED',
    message: 'The SMS provider did not accept the message.',
  },
} as const

export interface SendSmsHookDependencies {
  hookSecret?: string
  logger?: Pick<Console, 'error' | 'info' | 'warn'>
  sendAuthenticationSms?: (input: AuthenticationSmsInput) => Promise<unknown>
}

class MissingWebhookHeadersError extends Error {
  constructor() {
    super('Missing required webhook headers')
    this.name = 'MissingWebhookHeadersError'
  }
}

interface StandardWebhookHeaders {
  'webhook-id': string
  'webhook-signature': string
  'webhook-timestamp': string
}

export function normalizeSupabaseHookSecret(secret: string): string {
  const trimmed = secret.trim()
  return trimmed.startsWith('v1,') ? trimmed.slice(3) : trimmed
}

function collectStandardWebhookHeaders(request: Request): StandardWebhookHeaders {
  const webhookId = request.get('webhook-id')
  const webhookTimestamp = request.get('webhook-timestamp')
  const webhookSignature = request.get('webhook-signature')

  if (!webhookId || !webhookTimestamp || !webhookSignature) {
    throw new MissingWebhookHeadersError()
  }

  return {
    'webhook-id': webhookId,
    'webhook-signature': webhookSignature,
    'webhook-timestamp': webhookTimestamp,
  }
}

function verifyHookBody(rawBody: Buffer, request: Request, hookSecret: string): unknown {
  const webhook = new Webhook(normalizeSupabaseHookSecret(hookSecret))
  return webhook.verify(rawBody, collectStandardWebhookHeaders(request))
}

function buildAuthenticationMessage(otp: string): string {
  return `${otp} ni namba yako ya uthibitisho ya Ahadi. Usimpe mtu mwingine.`
}

export function createSendSmsHookHandler(dependencies: SendSmsHookDependencies = {}) {
  const hookSecret = dependencies.hookSecret ?? env.SEND_SMS_HOOK_SECRET
  const logger = dependencies.logger ?? console
  const sendSms = dependencies.sendAuthenticationSms ?? sendAuthenticationSms

  return async function sendSmsHookHandler(request: Request, response: Response): Promise<void> {
    let signatureVerified = false
    let payloadValidated = false
    let providerCalled = false
    let providerHttpStatus: number | undefined
    let providerAccepted: boolean | undefined
    let providerMessageId: string | null | undefined
    let providerStatusCode: string | null | undefined
    const bodyIsBuffer = Buffer.isBuffer(request.body)
    const hasWebhookId = Boolean(request.get('webhook-id'))
    const hasWebhookTimestamp = Boolean(request.get('webhook-timestamp'))
    const hasWebhookSignature = Boolean(request.get('webhook-signature'))

    const logHookResult = (statusCode: number) => {
      logger.info('Ahadi SMS hook result', {
        requestId: request.requestId,
        route: '/auth/hooks/send-sms',
        statusCode,
        bodyIsBuffer,
        hasWebhookId,
        hasWebhookTimestamp,
        hasWebhookSignature,
        signatureVerified,
        payloadValidated,
        providerCalled,
        providerHttpStatus,
        providerAccepted,
        providerMessageId,
        providerStatusCode,
      })
    }

    logOtpDiagnostic(logger, 'SMS_HOOK_RECEIVED', {
      requestId: request.requestId,
      route: '/auth/hooks/send-sms',
      bodyIsBuffer,
      hasWebhookId,
      hasWebhookTimestamp,
      hasWebhookSignature,
    })

    if (env.NODE_ENV === 'development') {
      logger.info('Supabase auth SMS hook diagnostics', {
        requestId: request.requestId,
        bodyIsBuffer,
        hasWebhookId,
        hasWebhookTimestamp,
        hasWebhookSignature,
        secretHasVersionPrefix: hookSecret.trim().startsWith('v1,'),
        secretHasWhsecPrefix: normalizeSupabaseHookSecret(hookSecret).startsWith('whsec_'),
      })
    }

    if (!bodyIsBuffer) {
      logOtpDiagnostic(logger, 'SMS_HOOK_BODY_NOT_RAW', { requestId: request.requestId })
      logHookResult(401)
      response.status(401).json(invalidSignatureResponse)
      return
    }

    let verifiedPayload: unknown
    try {
      verifiedPayload = verifyHookBody(request.body, request, hookSecret)
      signatureVerified = true
      logOtpDiagnostic(logger, 'SMS_HOOK_SIGNATURE_VERIFIED', { requestId: request.requestId })
    } catch (error) {
      if (error instanceof SyntaxError) {
        logOtpDiagnostic(logger, 'SMS_HOOK_PAYLOAD_INVALID', { requestId: request.requestId })
        logHookResult(400)
        response.status(400).json(invalidPayloadResponse)
        return
      }
      if (error instanceof MissingWebhookHeadersError) {
        logOtpDiagnostic(logger, 'SMS_HOOK_HEADERS_MISSING', { requestId: request.requestId })
        logHookResult(401)
        response.status(401).json(invalidSignatureResponse)
        return
      }
      if (error instanceof WebhookVerificationError || error instanceof Error) {
        logOtpDiagnostic(logger, 'SMS_HOOK_SIGNATURE_INVALID', { requestId: request.requestId })
        logHookResult(401)
        response.status(401).json(invalidSignatureResponse)
        return
      }
      logOtpDiagnostic(logger, 'SMS_HOOK_SIGNATURE_INVALID', { requestId: request.requestId })
      logHookResult(401)
      response.status(401).json(invalidSignatureResponse)
      return
    }

    const parsedPayload = sendSmsHookPayloadSchema.safeParse(verifiedPayload)
    if (!parsedPayload.success) {
      logger.warn('Supabase SMS hook payload validation failed', {
        requestId: request.requestId,
        issues: parsedPayload.error.issues.map((issue) => ({
          path: issue.path.join('.'),
          code: issue.code,
        })),
      })
      logOtpDiagnostic(logger, 'SMS_HOOK_PAYLOAD_INVALID', { requestId: request.requestId })
      logHookResult(400)
      response.status(400).json(invalidPayloadResponse)
      return
    }
    payloadValidated = true
    let normalizedPhone: string
    try {
      normalizedPhone = normalizeTanzaniaPhone(parsedPayload.data.user.phone)
    } catch {
      logOtpDiagnostic(logger, 'SMS_HOOK_PHONE_INVALID', { requestId: request.requestId })
      logHookResult(400)
      response.status(400).json(invalidPayloadResponse)
      return
    }
    logOtpDiagnostic(logger, 'SMS_HOOK_PAYLOAD_VALIDATED', { requestId: request.requestId, to: maskPhoneForLog(normalizedPhone) })

    const to = normalizedPhone
    try {
      providerCalled = true
      const providerResult = await sendSms({
        requestId: request.requestId,
        to,
        message: buildAuthenticationMessage(parsedPayload.data.sms.otp),
      })
      if (typeof providerResult === 'object' && providerResult !== null) {
        const result = providerResult as { accepted?: unknown; providerHttpStatus?: unknown; providerMessageId?: unknown; providerStatusCode?: unknown }
        providerAccepted = typeof result.accepted === 'boolean' ? result.accepted : true
        providerHttpStatus = typeof result.providerHttpStatus === 'number' ? result.providerHttpStatus : undefined
        providerMessageId = typeof result.providerMessageId === 'string' ? result.providerMessageId : null
        providerStatusCode = typeof result.providerStatusCode === 'string' ? result.providerStatusCode : null
      } else {
        providerAccepted = true
      }
      logOtpDiagnostic(logger, 'SMS_HOOK_COMPLETED', { requestId: request.requestId, statusCode: 200, to: maskPhoneForLog(to) })
      logHookResult(200)
      response.status(200).json({})
    } catch (error) {
      providerHttpStatus = error instanceof SmsProviderError ? error.status : undefined
      providerAccepted = error instanceof SmsProviderError ? error.providerAccepted : false
      providerStatusCode = error instanceof SmsProviderError ? error.providerStatusCode ?? null : undefined
      logger.error('Supabase auth SMS provider failed', {
        requestId: request.requestId,
        to: maskPhoneForLog(to),
        providerHttpStatus,
        providerStatusCode,
        providerAccepted,
        providerReason: error instanceof SmsProviderError ? error.providerReason : undefined,
      })
      logHookResult(502)
      response.status(502).json(providerFailureResponse)
    }
  }
}

export const sendSmsHookHandler = createSendSmsHookHandler()
