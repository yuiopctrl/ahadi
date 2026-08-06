import { createClient } from '@supabase/supabase-js'
import { env } from './env.js'

export const supabasePublic = createClient(env.SUPABASE_URL, env.supabasePublishableKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
})

export function createUserSupabase(accessToken: string) {
  return createClient(env.SUPABASE_URL, env.supabasePublishableKey, {
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  })
}
