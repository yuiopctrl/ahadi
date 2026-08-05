import dotenv from 'dotenv'
import { z } from 'zod'

dotenv.config()

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  WORKER_POLL_INTERVAL_MS: z.coerce.number().int().positive().default(30_000),
})

const env = envSchema.parse(process.env)

console.log(`Ahadi worker booted in ${env.NODE_ENV} mode with ${env.WORKER_POLL_INTERVAL_MS}ms poll interval`)
