import type { NextFunction, Request, Response } from 'express'
import { randomUUID } from 'node:crypto'
import { uuidHeaderSchema } from '@ahadi/validation'
import type { TenantContext, UserContext } from '@ahadi/types'
import { AppError } from './errors.js'
import { calculateTenantAccessState } from './access.js'
import { normalizeUserContext } from './context-normalization.js'
import { createUserSupabase, supabasePublic } from './supabase.js'

const activePlatformRoles = new Set(['PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR'])
const platformRolePermissions: Record<string, string[]> = {
  PLATFORM_ADMIN: [
    'platform.dashboard.view',
    'platform.tenants.view',
    'platform.tenants.manage',
    'platform.plans.view',
    'platform.plans.manage',
    'platform.subscriptions.manage',
    'platform.sms.view',
    'platform.beta.view',
    'platform.beta.manage',
    'platform.support.view',
    'platform.support.manage',
    'platform.feedback.view',
    'platform.features.view',
    'platform.features.manage',
    'platform.system_errors.view',
  ],
  PLATFORM_SUPPORT: [
    'platform.dashboard.view',
    'platform.tenants.view',
    'platform.sms.view',
    'platform.support.view',
    'platform.support.manage',
    'platform.feedback.view',
    'platform.system_errors.view',
  ],
  PLATFORM_AUDITOR: ['platform.dashboard.view', 'platform.audit.view', 'platform.system_errors.view'],
}

function hasPlatformPermission(context: UserContext, permission: string) {
  if (context.platformPermissions.includes(permission)) {
    return true
  }
  if (context.platformRole === 'PLATFORM_OWNER' && permission.startsWith('platform.')) {
    return true
  }
  return Boolean(context.platformRole && platformRolePermissions[context.platformRole]?.includes(permission))
}

export function requestIdMiddleware(request: Request, response: Response, next: NextFunction) {
  request.requestId = request.header('X-Request-ID') ?? randomUUID()
  response.setHeader('X-Request-ID', request.requestId)
  next()
}

export async function requireAuth(request: Request, _response: Response, next: NextFunction) {
  try {
    const header = request.header('Authorization')
    const token = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : null
    if (!token) {
      throw new AppError('SESSION_REQUIRED')
    }

    const { data, error } = await supabasePublic.auth.getUser(token)
    if (error || !data.user) {
      throw new AppError('SESSION_REQUIRED')
    }

    request.auth = { accessToken: token, user: data.user }
    next()
  } catch (error) {
    next(error)
  }
}

export async function loadUserContext(request: Request, _response: Response, next: NextFunction) {
  try {
    if (!request.auth) {
      throw new AppError('SESSION_REQUIRED')
    }
    const client = createUserSupabase(request.auth.accessToken)
    const { data, error } = await client.rpc('rpc_get_my_context')
    if (error) {
      throw error
    }
    request.auth.context = normalizeUserContext(data)
    next()
  } catch (error) {
    next(error)
  }
}

export function requirePlatformPermission(permission: string) {
  return (request: Request, _response: Response, next: NextFunction) => {
    const context = request.auth?.context
    if (!context || context.platformStatus !== 'ACTIVE' || !context.platformRole || !activePlatformRoles.has(context.platformRole)) {
      next(new AppError('PLATFORM_ACCESS_DENIED', 'Active platform access is required'))
      return
    }
    if (!hasPlatformPermission(context, permission)) {
      next(new AppError('PLATFORM_ACCESS_DENIED', `Missing platform permission: ${permission}`))
      return
    }
    next()
  }
}

export async function requireTenantContext(request: Request, _response: Response, next: NextFunction) {
  try {
    if (!request.auth) {
      throw new AppError('SESSION_REQUIRED')
    }

    const requestedTenantId = request.header('X-Tenant-ID')
    const memberships = request.auth.context?.tenantMemberships ?? []
    let tenantId: string | null = null

    if (requestedTenantId) {
      tenantId = uuidHeaderSchema.parse(requestedTenantId)
    } else if (memberships.filter((membership) => membership.membershipStatus === 'ACTIVE').length === 1) {
      tenantId = memberships.find((membership) => membership.membershipStatus === 'ACTIVE')?.tenantId ?? null
    }

    if (!tenantId) {
      throw new AppError('TENANT_ACCESS_DENIED', 'A verified tenant context is required')
    }

    const client = createUserSupabase(request.auth.accessToken)
    const { data, error } = await client.rpc('rpc_get_tenant_context', { p_tenant_id: tenantId })
    if (error) {
      throw error
    }

    const tenantContext = data as unknown as TenantContext
    const accessState = calculateTenantAccessState(tenantContext.tenant.status, tenantContext.subscription)
    if (tenantContext.membership?.status !== 'ACTIVE' || accessState === 'BLOCKED') {
      throw new AppError('SUBSCRIPTION_INACTIVE')
    }

    request.tenantContext = { ...tenantContext, accessState }
    next()
  } catch (error) {
    next(error)
  }
}
