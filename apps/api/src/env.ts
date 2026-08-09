import dotenv from 'dotenv'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'

dotenv.config({ path: fileURLToPath(new URL('../.env', import.meta.url)), quiet: true })

export const apiEnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  WEB_URL: z.string().url().default('http://localhost:5173'),
  APP_VERSION: z.string().trim().min(1).default('0.9.0-beta'),
  TRUST_PROXY_HOPS: z.coerce.number().int().nonnegative().default(0),
  SUPABASE_URL: z.string().url(),
  SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  SEND_SMS_HOOK_SECRET: z
    .string()
    .trim()
    .refine((value) => value.startsWith('v1,whsec_') || value.startsWith('whsec_'), {
      message: 'SEND_SMS_HOOK_SECRET must start with v1,whsec_ or whsec_',
    }),
  SMS_PROVIDER: z.enum(['WEBBULKSMS', 'NEXTSMS']).default('WEBBULKSMS'),
  SMS_PROVIDER_URL: z.string().url().optional(),
  SMS_USERNAME: z.string().min(1).optional(),
  SMS_PASSWORD: z.string().min(1).optional(),
  SMS_SENDER_ID: z.string().trim().min(1).max(20).default('MICHANGO'),
  NEXTSMS_BASE_URL: z.string().url().default('https://messaging-service.co.tz'),
  NEXTSMS_SINGLE_SMS_PATH: z.string().trim().min(1).default('/api/sms/v1/text/single'),
  NEXTSMS_AUTHORIZATION: z.string().trim().min(1).optional(),
  NEXTSMS_DEFAULT_SENDER_ID: z.enum(['MICHANGO', 'SHEREHE', 'KIKAO']).default('MICHANGO'),
  NEXTSMS_ALLOWED_SENDER_IDS: z.string().trim().min(1).default('SHEREHE,MICHANGO,KIKAO'),
  BALANCE_REMINDER_COOLDOWN_HOURS: z.coerce.number().int().nonnegative().default(24),
  BALANCE_REMINDER_DUE_SOON_DAYS: z.coerce.number().int().nonnegative().max(60).default(7),
  BALANCE_REMINDER_MAX_BATCH_SIZE: z.coerce.number().int().positive().max(100).default(100),
  PLEDGE_REQUEST_COOLDOWN_HOURS: z.coerce.number().int().nonnegative().default(24),
  PLEDGE_REQUEST_MAX_BATCH_SIZE: z.coerce.number().int().positive().max(100).default(100),
  WHATSAPP_SHARE_SAFE_CHAR_LIMIT: z.coerce.number().int().positive().max(20000).default(3500),
  GATEWAY_PROVIDER: z.enum(['TEST', 'NMB']).default('TEST'),
  GATEWAY_ENVIRONMENT: z.enum(['SANDBOX', 'PRODUCTION']).default('SANDBOX'),
  TEST_GATEWAY_WEBHOOK_SECRET: z.string().trim().min(8).default('dev-test-gateway-secret'),
  NMB_BASE_URL: z.string().url().optional(),
  NMB_CLIENT_ID: z.string().trim().optional(),
  NMB_CLIENT_SECRET: z.string().trim().optional(),
  NMB_WEBHOOK_SECRET: z.string().trim().optional(),
}).superRefine((value, context) => {
  if (value.SMS_PROVIDER === 'WEBBULKSMS') {
    for (const key of ['SMS_PROVIDER_URL', 'SMS_USERNAME', 'SMS_PASSWORD'] as const) {
      if (!value[key]) {
        context.addIssue({ code: 'custom', path: [key], message: `${key} is required when SMS_PROVIDER=WEBBULKSMS` })
      }
    }
  }
  if (value.SMS_PROVIDER === 'NEXTSMS' && !value.NEXTSMS_AUTHORIZATION) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_AUTHORIZATION'], message: 'NEXTSMS_AUTHORIZATION is required when SMS_PROVIDER=NEXTSMS' })
  }
  const allowed = value.NEXTSMS_ALLOWED_SENDER_IDS.split(',').map((item) => item.trim().toUpperCase()).filter(Boolean)
  const supported = new Set(['MICHANGO', 'SHEREHE', 'KIKAO'])
  if (!allowed.length || allowed.some((item) => !supported.has(item))) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_ALLOWED_SENDER_IDS'], message: 'NEXTSMS_ALLOWED_SENDER_IDS must contain only SHEREHE, MICHANGO, and KIKAO' })
  }
  if (!allowed.includes(value.NEXTSMS_DEFAULT_SENDER_ID)) {
    context.addIssue({ code: 'custom', path: ['NEXTSMS_DEFAULT_SENDER_ID'], message: 'NEXTSMS_DEFAULT_SENDER_ID must be in NEXTSMS_ALLOWED_SENDER_IDS' })
  }
})

export type ApiEnv = z.infer<typeof apiEnvSchema>

export function parseApiEnv(input: NodeJS.ProcessEnv): ApiEnv {
  const parsed = apiEnvSchema.safeParse(input)

  if (!parsed.success) {
    throw new Error(`Invalid API environment: ${parsed.error.message}`)
  }

  return parsed.data
}

const parsed = parseApiEnv(process.env)

export const env = {
  ...parsed,
  supabasePublishableKey: parsed.SUPABASE_PUBLISHABLE_KEY,
}
