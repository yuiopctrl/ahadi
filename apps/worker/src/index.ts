import dotenv from 'dotenv'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { maskSmsPhone, sendWebBulkSms, SmsProviderError, type SmsProviderResult } from '@ahadi/sms'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'

dotenv.config()

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  WORKER_POLL_INTERVAL_MS: z.coerce.number().int().positive().default(30_000),
  WORKER_BATCH_SIZE: z.coerce.number().int().positive().max(50).default(10),
  SUPABASE_URL: z.string().url(),
  SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  SUPABASE_WORKER_ACCESS_TOKEN: z.string().min(1).optional(),
  SMS_PROVIDER_URL: z.string().url(),
  SMS_USERNAME: z.string().min(1),
  SMS_PASSWORD: z.string().min(1),
  SMS_SENDER_ID: z.string().trim().min(1).max(20),
})

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
}

export interface SmsOutboxStore {
  claim(batchSize: number): Promise<SmsOutboxJob[]>
  markSent(outboxId: string, providerMessageId: string | null): Promise<void>
  markFailed(outboxId: string, errorCode: string, errorMessage: string, retryable: boolean): Promise<void>
}

export interface SmsOutboxProvider {
  send(job: SmsOutboxJob): Promise<SmsProviderResult>
}

export interface SmsFailureClassification {
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

export function classifySmsFailure(error: unknown): SmsFailureClassification {
  if (error instanceof SmsProviderError) {
    const reason = (error.providerReason ?? error.message).toLowerCase()
    const status = error.status
    if (status === 401 || status === 403 || reason.includes('auth') || reason.includes('password') || reason.includes('credential')) {
      return { code: 'PROVIDER_AUTH_FAILED', message: safeErrorMessage(error), retryable: false }
    }
    if (status === 400 || reason.includes('invalid phone') || reason.includes('unsupported') || reason.includes('sender id')) {
      return { code: 'PROVIDER_PERMANENT_FAILURE', message: safeErrorMessage(error), retryable: false }
    }
    if (status === 429 || (status !== undefined && status >= 500)) {
      return { code: 'PROVIDER_RETRYABLE_FAILURE', message: safeErrorMessage(error), retryable: true }
    }
  }
  return { code: 'PROVIDER_RETRYABLE_FAILURE', message: safeErrorMessage(error), retryable: true }
}

export class SupabaseSmsOutboxStore implements SmsOutboxStore {
  constructor(private readonly client: SupabaseClient) {}

  async claim(batchSize: number): Promise<SmsOutboxJob[]> {
    const { data, error } = await this.client.rpc('rpc_claim_sms_outbox', { p_batch_size: batchSize })
    if (error) {
      throw error
    }
    return Array.isArray(data) ? data as SmsOutboxJob[] : []
  }

  async markSent(outboxId: string, providerMessageId: string | null): Promise<void> {
    const { error } = await this.client.rpc('rpc_mark_sms_sent', { p_outbox_id: outboxId, p_provider_message_id: providerMessageId })
    if (error) {
      throw error
    }
  }

  async markFailed(outboxId: string, errorCode: string, errorMessage: string, retryable: boolean): Promise<void> {
    const { error } = await this.client.rpc('rpc_mark_sms_failed', { p_outbox_id: outboxId, p_error_code: errorCode, p_error_message: errorMessage, p_retryable: retryable })
    if (error) {
      throw error
    }
  }
}

export class WebBulkSmsOutboxProvider implements SmsOutboxProvider {
  constructor(private readonly config: { providerUrl: string; username: string; password: string; senderId: string; fetchImpl?: typeof fetch }) {}

  async send(job: SmsOutboxJob): Promise<SmsProviderResult> {
    const providerOptions = this.config.fetchImpl ? {
      fetchImpl: this.config.fetchImpl,
      password: this.config.password,
      providerUrl: this.config.providerUrl,
      senderId: this.config.senderId,
      username: this.config.username,
    } : {
        password: this.config.password,
        providerUrl: this.config.providerUrl,
        senderId: this.config.senderId,
        username: this.config.username,
    }
    return sendWebBulkSms({ to: job.phone_e164, message: job.message_body }, providerOptions)
  }
}

export async function processSmsOutboxBatch(store: SmsOutboxStore, provider: SmsOutboxProvider, batchSize: number, logger: Pick<Console, 'info' | 'warn' | 'error'> = console): Promise<number> {
  const jobs = await store.claim(batchSize)
  for (const job of jobs) {
    try {
      logger.info('SMS outbox send started', {
        outboxId: job.id,
        tenantId: job.tenant_id,
        paymentId: job.payment_id,
        templateCode: job.template_code,
        attempt: job.attempt_count,
        maskedPhone: maskSmsPhone(job.phone_e164),
      })
      const result = await provider.send(job)
      await store.markSent(job.id, result.providerMessageId)
      logger.info('SMS outbox sent', {
        outboxId: job.id,
        tenantId: job.tenant_id,
        paymentId: job.payment_id,
        templateCode: job.template_code,
        providerHttpStatus: result.providerHttpStatus,
        providerMessageId: result.providerMessageId,
      })
    } catch (error) {
      const classification = classifySmsFailure(error)
      await store.markFailed(job.id, classification.code, classification.message, classification.retryable)
      logger.warn('SMS outbox send failed', {
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
  return jobs.length
}

function createSupabaseWorkerClient(input: z.infer<typeof envSchema>) {
  return createClient(input.SUPABASE_URL, input.SUPABASE_PUBLISHABLE_KEY, {
    ...(input.SUPABASE_WORKER_ACCESS_TOKEN
      ? {
          global: {
            headers: {
              Authorization: `Bearer ${input.SUPABASE_WORKER_ACCESS_TOKEN}`,
            },
          },
        }
      : {}),
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  })
}

async function main() {
  const env = envSchema.parse(process.env)
  const store = new SupabaseSmsOutboxStore(createSupabaseWorkerClient(env))
  const provider = new WebBulkSmsOutboxProvider({
    providerUrl: env.SMS_PROVIDER_URL,
    username: env.SMS_USERNAME,
    password: env.SMS_PASSWORD,
    senderId: env.SMS_SENDER_ID,
  })

  console.log(`Ahadi worker booted in ${env.NODE_ENV} mode with ${env.WORKER_POLL_INTERVAL_MS}ms poll interval`)
  setInterval(() => {
    void processSmsOutboxBatch(store, provider, env.WORKER_BATCH_SIZE).catch((error: unknown) => {
      console.error('SMS outbox batch failed', { safeMessage: safeErrorMessage(error) })
    })
  }, env.WORKER_POLL_INTERVAL_MS)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  void main()
}
