import { z } from 'zod'

const envSchema = z.object({
  VITE_APP_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  VITE_APP_VERSION: z.string().trim().min(1).default('0.9.0-beta'),
  VITE_BUILD_COMMIT: z.string().trim().min(1).default('local'),
  VITE_API_URL: z.string().url().default('http://localhost:4000/api/v1'),
  VITE_SUPABASE_URL: z.string().url().optional(),
  VITE_SUPABASE_PUBLISHABLE_KEY: z.string().min(1).optional(),
})

const parsed = envSchema.safeParse(import.meta.env)

if (!parsed.success) {
  throw new Error(`Invalid web environment: ${parsed.error.message}`)
}

export const env = {
  appEnv: parsed.data.VITE_APP_ENV,
  appVersion: parsed.data.VITE_APP_VERSION,
  buildCommit: parsed.data.VITE_BUILD_COMMIT,
  apiUrl: parsed.data.VITE_API_URL,
  supabaseUrl: parsed.data.VITE_SUPABASE_URL ?? 'https://placeholder.supabase.co',
  supabasePublishableKey: parsed.data.VITE_SUPABASE_PUBLISHABLE_KEY ?? 'placeholder-publishable-key',
}
