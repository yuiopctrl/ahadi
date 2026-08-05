import { z } from 'zod'

const envSchema = z.object({
  VITE_APP_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  VITE_SUPABASE_URL: z.string().url().optional(),
  VITE_SUPABASE_ANON_KEY: z.string().min(1).optional(),
})

const parsed = envSchema.safeParse(import.meta.env)

if (!parsed.success) {
  throw new Error(`Invalid web environment: ${parsed.error.message}`)
}

export const env = {
  appEnv: parsed.data.VITE_APP_ENV,
  supabaseUrl: parsed.data.VITE_SUPABASE_URL ?? 'https://placeholder.supabase.co',
  supabaseAnonKey: parsed.data.VITE_SUPABASE_ANON_KEY ?? 'placeholder-anon-key',
}
