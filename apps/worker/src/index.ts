import dotenv from 'dotenv'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { buildNextSmsSingleSmsUrl, maskSmsPhone, SmsProviderError, SmsProviderRegistry, type SmsProviderResult } from '@ahadi/sms'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'

const workerEnvFiles = [
  '../../../.env',
  '../../api/.env',
  '../.env',
] as const

export function loadWorkerEnvFiles(): string[] {
  const loaded: string[] = []
  for (const relativePath of workerEnvFiles) {
    const path = fileURLToPath(new URL(relativePath, import.meta.url))
    if (!existsSync(path)) {
      continue
    }
    dotenv.config({ path, quiet: true, override: relativePath === '../.env' })
    loaded.push(path)
  }
  return loaded
}

export const loadedWorkerEnvFiles = loadWorkerEnvFiles()

const nextSmsAllowedSenderValues = ['SHEREHE', 'MICHANGO', 'KIKAO'] as const
const expectedNextSmsEndpoint = 'https://messaging-service.co.tz/api/sms/v1/text/single'

export const workerEnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  WORKER_POLL_INTERVAL_MS: z.coerce.number().int().positive().default(30_000),
  WORKER_BATCH_SIZE: z.coerce.number().int().positive().max(50).default(10),
  SUPABASE_URL: z.string().url(),
  SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  SUPABASE_WORKER_ACCESS_TOKEN: z.string().min(1).optional(),
  SMS_PROVIDER: z.enum(['WEBBULKSMS', 'NEXTSMS']).default('NEXTSMS'),
  SMS_PROVIDER_URL: z.string().url().optional(),
  SMS_USERNAME: z.string().min(1).optional(),
  SMS_PASSWORD: z.string().min(1).optional(),
  SMS_SENDER_ID: z.string().trim().min(1).max(20).default('MICHANGO'),
  WEBBULKSMS_URL: z.string().url().optional(),
  WEBBULKSMS_USERNAME: z.string().min(1).optional(),
  WEBBULKSMS_PASSWORD: z.string().min(1).optional(),
  WEBBULKSMS_SENDER_ID: z.string().trim().min(1).max(20).optional(),
  NEXTSMS_BASE_URL: z.string().url().default('https://messaging-service.co.tz'),
  NEXTSMS_SINGLE_SMS_PATH: z.string().trim().min(1).default('/api/sms/v1/text/single'),
  NEXTSMS_AUTHORIZATION: z.string().trim().min(1).optional(),
  NEXTSMS_DEFAULT_SENDER_ID: z.enum(nextSmsAllowedSenderValues).default('MICHANGO'),
  NEXTSMS_ALLOWED_SENDER_IDS: z.string().trim().min(1).default('SHEREHE,MICHANGO,KIKAO'),
}).superRefine((value, context) => {
  const allowed = value.NEXTSMS_ALLOWED_SENDER_IDS.split(',').map((item) => item.trim().toUpperCase()).filter(Boolean)
  if (!allowed.length || allowed.some((senderId) => !nextSmsAllowedSenderValues.includes(senderId as typeof nextSmsAllowedSenderValues[number]))) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_ALLOWED_SENDER_IDS'], message: 'NEXTSMS_ALLOWED_SENDER_IDS must contain only SHEREHE, MICHANGO, and KIKAO' })
  }
  if (!allowed.includes(value.NEXTSMS_DEFAULT_SENDER_ID)) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_DEFAULT_SENDER_ID'], message: 'NEXTSMS_DEFAULT_SENDER_ID must be in NEXTSMS_ALLOWED_SENDER_IDS' })
  }
  if (!value.NEXTSMS_AUTHORIZATION?.trim()) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_AUTHORIZATION'], message: 'NEXTSMS_AUTHORIZATION is required by the worker runtime' })
  } else if (!/^Basic\s+(?!Basic\s).+/i.test(value.NEXTSMS_AUTHORIZATION.trim())) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_AUTHORIZATION'], message: 'NEXTSMS_AUTHORIZATION must be the exact provider Authorization header value' })
  }
  const endpoint = buildNextSmsSingleSmsUrl(value.NEXTSMS_BASE_URL, value.NEXTSMS_SINGLE_SMS_PATH)
  if (endpoint !== expectedNextSmsEndpoint) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_SINGLE_SMS_PATH'], message: `NextSMS endpoint must be ${expectedNextSmsEndpoint}` })
  }
})

export type WorkerEnv = z.infer<typeof workerEnvSchema>

export function parseWorkerEnv(input: NodeJS.ProcessEnv): WorkerEnv {
  const parsed = workerEnvSchema.safeParse(input)
  if (!parsed.success) {
    const fields = [...new Set(parsed.error.issues.map((issue) => issue.path.join('.') || 'environment'))]
    throw new Error(
      `Invalid worker environment. Missing or invalid: ${fields.join(', ')}. ` +
      'Configure Supabase worker access and provider credentials for the SMS providers enabled in the platform.',
    )
  }
  return parsed.data
}

export function getNextSmsRuntimeDiagnostics(env: WorkerEnv) {
  return {
    baseUrlConfigured: Boolean(env.NEXTSMS_BASE_URL.trim()),
    authorizationConfigured: Boolean(env.NEXTSMS_AUTHORIZATION?.trim()),
    defaultSenderId: env.NEXTSMS_DEFAULT_SENDER_ID,
  }
}

export function getNextSmsEndpoint(env: WorkerEnv): string {
  return buildNextSmsSingleSmsUrl(env.NEXTSMS_BASE_URL, env.NEXTSMS_SINGLE_SMS_PATH)
}

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
    if (status === 400 || reason.includes('invalid phone') || reason.includes('unsupported') || reason.includes('sender id') || reason.includes('contract_required') || reason.includes('character_limit')) {
      return { code: 'PROVIDER_PERMANENT_FAILURE', message: safeErrorMessage(error), retryable: false }
    }
    if (status === 429 || (status !== undefined && status >= 500)) {
      return { code: 'PROVIDER_RETRYABLE_FAILURE', message: safeErrorMessage(error), retryable: true }
    }
  }
  return { code: 'PROVIDER_RETRYABLE_FAILURE', message: safeErrorMessage(error), retryable: true }
}

function providerStatusCode(error: unknown): string | null {
  return error instanceof SmsProviderError ? (error.providerStatusCode ?? null) : null
}

function providerHttpStatus(error: unknown): number | null {
  return error instanceof SmsProviderError ? (error.status ?? null) : null
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

export class ConfiguredSmsOutboxProvider implements SmsOutboxProvider {
  private registry?: SmsProviderRegistry

  constructor(private readonly config: WorkerEnv & { fetchImpl?: typeof fetch }) {}

  async send(job: SmsOutboxJob): Promise<SmsProviderResult> {
    this.registry ??= new SmsProviderRegistry({
      fetchImpl: this.config.fetchImpl,
      nextSmsAuthorization: this.config.NEXTSMS_AUTHORIZATION,
      nextSmsBaseUrl: this.config.NEXTSMS_BASE_URL,
      nextSmsDefaultSenderId: this.config.NEXTSMS_DEFAULT_SENDER_ID,
      nextSmsSingleSmsPath: this.config.NEXTSMS_SINGLE_SMS_PATH,
      nextSmsAllowedSenderIds: this.config.NEXTSMS_ALLOWED_SENDER_IDS.split(',').map((item) => item.trim().toUpperCase()).filter(Boolean),
      webBulkSmsPassword: this.config.WEBBULKSMS_PASSWORD ?? this.config.SMS_PASSWORD,
      webBulkSmsSenderId: this.config.WEBBULKSMS_SENDER_ID ?? this.config.SMS_SENDER_ID,
      webBulkSmsUrl: this.config.WEBBULKSMS_URL ?? this.config.SMS_PROVIDER_URL,
      webBulkSmsUsername: this.config.WEBBULKSMS_USERNAME ?? this.config.SMS_USERNAME,
    })
    if (!job.provider || !job.sender_id) {
      throw new SmsProviderError('Queued SMS is missing provider selection', 400, 'SMS_PROVIDER_NOT_SELECTED', 'SMS_PROVIDER_NOT_SELECTED', false)
    }
    return this.registry.sendSingle({ providerCode: job.provider, to: job.phone_e164, message: job.message_body, senderId: job.sender_id })
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
        provider: job.provider,
        senderId: job.sender_id,
        attempt: job.attempt_count,
        maskedPhone: maskSmsPhone(job.phone_e164),
      })
      logger.info('SMS_SEND_START', {
        outboxId: job.id,
        provider: job.provider,
        senderId: job.sender_id,
        attempt: job.attempt_count,
      })
      const result = await provider.send(job)
      await store.markSent(job.id, result.providerMessageId)
      logger.info('SMS outbox sent', {
        outboxId: job.id,
        tenantId: job.tenant_id,
        paymentId: job.payment_id,
        templateCode: job.template_code,
        provider: job.provider,
        senderId: job.sender_id,
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
      logger.warn('SMS_SEND_FAILED', {
        outboxId: job.id,
        provider: job.provider,
        statusCode: providerHttpStatus(error),
        errorCode: providerStatusCode(error) ?? classification.code,
        safeMessage: classification.message,
      })
    }
  }
  return jobs.length
}

function createSupabaseWorkerClient(input: WorkerEnv) {
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
  const env = parseWorkerEnv(process.env)
  const store = new SupabaseSmsOutboxStore(createSupabaseWorkerClient(env))
  const provider = new ConfiguredSmsOutboxProvider(env)

  console.log('NEXTSMS_CONFIG', getNextSmsRuntimeDiagnostics(env))
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
