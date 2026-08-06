import type { User } from '@supabase/supabase-js'
import type { TenantAccessState, TenantContext, UserContext } from '@ahadi/types'

declare global {
  namespace Express {
    interface Request {
      auth?: {
        accessToken: string
        user: User
        context?: UserContext
      }
      tenantContext?: TenantContext & {
        accessState: TenantAccessState
      }
      requestId: string
    }
  }
}

export {}
