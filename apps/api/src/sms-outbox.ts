import type { SupabaseClient } from '@supabase/supabase-js'
import {
  maskSmsPhone,
  normalizeSmsProviderName,
  sendSmsWithProvider,
  SmsProviderError,
  type ConfiguredSmsProviderOptions,
  type SmsProviderResult,
} from '@ahadi/sms'
import { env } from './env.js'

export interface SmsOutboxJob {
  id: string
  tenant_id: string
  event_id: string | null
  member_id: string | null
  payment_id: string | null
  receipt_id: string | null
  template_code: string | null
  phone_e164: string
  message_body: string
  status: 'PROCESSING'
  attempt_count: number
  max_attempts: number
  provider?: string | null
  sender_id?: string | null
}

export interface SmsSendSummary {
  claimed: number
  sent: number
  failed: number
}

interface SendTenantQueuedSmsOptions {
  batchId?: string | null
  batchSize?: number
  outboxIds?: string[]
  requestId?: string
}

interface SmsFailureClassification {
  code: string
  message: string
  retryable: boolean
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.replace(/[+0-9][0-9\s().-]{6,}/g, '<redacted-phone>').slice(0, 160)
  }
  return 'SMS provider failed'
}

function classifySmsFailure(error: unknown): SmsFailureClassification {
  if (error instanceof SmsProviderError) {
    const reason = (error.providerReason ?? error.message).toLowerCase()
    const status = error.status
    if (status === 401 || status === 403 || reason.includes('auth') || reason.includes('password') || reason.includes('credential')) {
      return { code: 'PROVIDER_AUTH_FAILED', message: safeErrorMessage(error), retryable: false }
    }
    if (status === 400 || reason.includes('invalid phone') || reason.includes('unsupported') || reason.includes('sender id') || reason.includes('contract_required') || reason.includes('character_limit')) {
      return { code: 'PROVIDER_PERMANENT_FAILURE', message: safeErrorMessage(error), retryable: false }
    }
    if (status === 429 || (status !== undefined && status >= 500)) {
      return { code: 'PROVIDER_RETRYABLE_FAILURE', message: safeErrorMessage(error), retryable: true }
    }
  }
  return { code: 'PROVIDER_RETRYABLE_FAILURE', message: safeErrorMessage(error), retryable: true }
}

async function markSent(client: SupabaseClient, outboxId: string, providerMessageId: string | null) {
  const { error } = await client.rpc('rpc_mark_sms_sent', { p_outbox_id: outboxId, p_provider_message_id: providerMessageId })
  if (error) {
    throw error
  }
}

async function markFailed(client: SupabaseClient, outboxId: string, errorCode: string, errorMessage: string, retryable: boolean) {
  const { error } = await client.rpc('rpc_mark_sms_failed', { p_outbox_id: outboxId, p_error_code: errorCode, p_error_message: errorMessage, p_retryable: retryable })
  if (error) {
    throw error
  }
}

async function sendJob(job: SmsOutboxJob): Promise<SmsProviderResult> {
  const provider = normalizeSmsProviderName(job.provider ?? env.SMS_PROVIDER)
  const senderId = job.sender_id ?? (provider === 'NEXTSMS' ? env.NEXTSMS_DEFAULT_SENDER_ID : env.SMS_SENDER_ID)
  let options: ConfiguredSmsProviderOptions
  if (provider === 'NEXTSMS') {
    options = {
      provider,
      baseUrl: env.NEXTSMS_BASE_URL,
      singleSmsPath: env.NEXTSMS_SINGLE_SMS_PATH,
      defaultSenderId: env.NEXTSMS_DEFAULT_SENDER_ID,
      allowedSenderIds: env.NEXTSMS_ALLOWED_SENDER_IDS.split(',').map((item) => item.trim().toUpperCase()).filter(Boolean),
      ...(env.NEXTSMS_AUTHORIZATION ? { authorization: env.NEXTSMS_AUTHORIZATION } : {}),
    }
  } else {
    if (!env.SMS_PROVIDER_URL || !env.SMS_USERNAME || !env.SMS_PASSWORD) {
      throw new SmsProviderError('WebBulkSMS provider is not configured', 401, 'PROVIDER_AUTH_FAILED', 'PROVIDER_AUTH_FAILED', false)
    }
    options = {
      provider,
      password: env.SMS_PASSWORD,
      providerUrl: env.SMS_PROVIDER_URL,
      senderId: env.SMS_SENDER_ID,
      username: env.SMS_USERNAME,
    }
  }
  return sendSmsWithProvider({ to: job.phone_e164, message: job.message_body, senderId }, options)
}

export async function sendTenantQueuedSms(client: SupabaseClient, tenantId: string, options: SendTenantQueuedSmsOptions = {}, logger: Pick<Console, 'info' | 'warn'> = console): Promise<SmsSendSummary> {
  const batchSize = Math.max(1, Math.min(options.batchSize ?? options.outboxIds?.length ?? 10, 50))
  const { data, error } = await client.rpc('rpc_claim_tenant_sms_outbox', {
    p_batch_id: options.batchId ?? null,
    p_batch_size: batchSize,
    p_outbox_ids: options.outboxIds?.length ? options.outboxIds : null,
    p_tenant_id: tenantId,
  })
  if (error) {
    throw error
  }

  const jobs = Array.isArray(data) ? data as SmsOutboxJob[] : []
  const summary: SmsSendSummary = { claimed: jobs.length, sent: 0, failed: 0 }
  for (const job of jobs) {
    try {
      logger.info('SMS outbox send started', {
        requestId: options.requestId,
        outboxId: job.id,
        tenantId: job.tenant_id,
        paymentId: job.payment_id,
        templateCode: job.template_code,
        attempt: job.attempt_count,
        maskedPhone: maskSmsPhone(job.phone_e164),
      })
      const result = await sendJob(job)
      await markSent(client, job.id, result.providerMessageId)
      summary.sent += 1
      logger.info('SMS outbox sent', {
        requestId: options.requestId,
        outboxId: job.id,
        tenantId: job.tenant_id,
        paymentId: job.payment_id,
        templateCode: job.template_code,
        providerHttpStatus: result.providerHttpStatus,
        providerMessageId: result.providerMessageId,
      })
    } catch (sendError) {
      const classification = classifySmsFailure(sendError)
      await markFailed(client, job.id, classification.code, classification.message, classification.retryable)
      summary.failed += 1
      logger.warn('SMS outbox send failed', {
        requestId: options.requestId,
        outboxId: job.id,
        tenantId: job.tenant_id,
        paymentId: job.payment_id,
        templateCode: job.template_code,
        attempt: job.attempt_count,
        safeFailureCategory: classification.code,
        retryable: classification.retryable,
      })
    }
  }

  return summary
}

export async function attemptTenantQueuedSms(client: SupabaseClient, tenantId: string, options: SendTenantQueuedSmsOptions = {}, logger: Pick<Console, 'error' | 'info' | 'warn'> = console): Promise<SmsSendSummary & { error?: string }> {
  try {
    return await sendTenantQueuedSms(client, tenantId, options, logger)
  } catch (error) {
    logger.error('SMS outbox processing failed', {
      requestId: options.requestId,
      tenantId,
      safeMessage: safeErrorMessage(error),
    })
    return { claimed: 0, sent: 0, failed: 0, error: 'SMS_OUTBOX_PROCESSING_FAILED' }
  }
}
