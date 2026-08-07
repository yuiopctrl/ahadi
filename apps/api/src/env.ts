import dotenv from 'dotenv'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'

dotenv.config({ path: fileURLToPath(new URL('../.env', import.meta.url)), quiet: true })

export const apiEnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  WEB_URL: z.string().url().default('http://localhost:5173'),
  TRUST_PROXY_HOPS: z.coerce.number().int().nonnegative().default(0),
  SUPABASE_URL: z.string().url(),
  SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  SEND_SMS_HOOK_SECRET: z
    .string()
    .trim()
    .refine((value) => value.startsWith('v1,whsec_') || value.startsWith('whsec_'), {
      message: 'SEND_SMS_HOOK_SECRET must start with v1,whsec_ or whsec_',
    }),
  SMS_PROVIDER_URL: z.string().url(),
  SMS_USERNAME: z.string().min(1),
  SMS_PASSWORD: z.string().min(1),
  SMS_SENDER_ID: z.string().trim().min(1).max(20),
  BALANCE_REMINDER_COOLDOWN_HOURS: z.coerce.number().int().nonnegative().default(24),
  BALANCE_REMINDER_DUE_SOON_DAYS: z.coerce.number().int().nonnegative().max(60).default(7),
  BALANCE_REMINDER_MAX_BATCH_SIZE: z.coerce.number().int().positive().max(100).default(100),
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
