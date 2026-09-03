import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const middleware = readFileSync(new URL('./middleware.ts', import.meta.url), 'utf8')
const types = readFileSync(new URL('../../../packages/types/src/index.ts', import.meta.url), 'utf8')
const errors = readFileSync(new URL('./errors.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/069_platform_console_foundation.sql', import.meta.url), 'utf8')

test('every new platform route requires auth, user context and the correct platform permission', () => {
  const routes: Array<[method: string, path: string, permission: string]> = [
    ['get', '/api/v1/platform/system/health', 'platform.system_errors.view'],
    ['get', '/api/v1/platform/audit', 'platform.audit.view'],
    ['get', '/api/v1/platform/users', 'platform.users.view'],
    ['post', '/api/v1/platform/users', 'platform.users.manage'],
    ['patch', '/api/v1/platform/users/:platformUserId/role', 'platform.users.manage'],
    ['patch', '/api/v1/platform/users/:platformUserId/status', 'platform.users.manage'],
    ['post', '/api/v1/platform/plans', 'platform.plans.manage'],
    ['put', '/api/v1/platform/plans/:planId', 'platform.plans.manage'],
    ['post', '/api/v1/platform/tenants/:tenantId/status', 'platform.tenants.manage'],
    ['post', '/api/v1/platform/tenants/:tenantId/subscription/plan', 'platform.subscriptions.manage'],
    ['post', '/api/v1/platform/tenants/:tenantId/subscription/status', 'platform.subscriptions.manage'],
  ]
  for (const [method, path, permission] of routes) {
    const pattern = new RegExp(
      `app\\.${method}\\('${path.replaceAll('/', '\\/')}',\\s*requireAuth,\\s*loadUserContext,\\s*requirePlatformPermission\\('${permission.replaceAll('.', '\\.')}'\\)`,
    )
    assert.match(app, pattern, `${method.toUpperCase()} ${path} must chain requireAuth, loadUserContext, requirePlatformPermission('${permission}')`)
  }
})

test('platform.users.manage is not granted to any role except PLATFORM_OWNER (owner-only privilege escalation guard)', () => {
  const adminBlock = migration.slice(migration.indexOf("pu.role = 'PLATFORM_ADMIN'"), migration.indexOf("pu.role = 'PLATFORM_SUPPORT'"))
  const supportBlock = migration.slice(migration.indexOf("pu.role = 'PLATFORM_SUPPORT'"), migration.indexOf("pu.role = 'PLATFORM_AUDITOR'"))
  const auditorBlock = migration.slice(migration.indexOf("pu.role = 'PLATFORM_AUDITOR'"), migration.indexOf('create or replace function public.rpc_list_platform_users'))
  assert.doesNotMatch(adminBlock, /platform\.users\.manage/)
  assert.doesNotMatch(supportBlock, /platform\.users\.manage/)
  assert.doesNotMatch(auditorBlock, /platform\.users\.manage/)

  const nodeAdmin = middleware.slice(middleware.indexOf('PLATFORM_ADMIN: ['), middleware.indexOf('PLATFORM_SUPPORT: ['))
  const nodeSupport = middleware.slice(middleware.indexOf('PLATFORM_SUPPORT: ['), middleware.indexOf('PLATFORM_AUDITOR: ['))
  const nodeAuditor = middleware.slice(middleware.indexOf('PLATFORM_AUDITOR: ['), middleware.indexOf('}\n', middleware.indexOf('PLATFORM_AUDITOR: [')))
  assert.doesNotMatch(nodeAdmin, /platform\.users\.manage/)
  assert.doesNotMatch(nodeSupport, /platform\.users\.manage/)
  assert.doesNotMatch(nodeAuditor, /platform\.users\.manage/)
})

test('platform staff role/status RPCs enforce has_platform_permission and protect the final active PLATFORM_OWNER', () => {
  const roleFn = migration.slice(migration.indexOf('function public.rpc_set_platform_user_role'), migration.indexOf('function public.rpc_set_platform_user_status'))
  const statusFn = migration.slice(migration.indexOf('function public.rpc_set_platform_user_status'), migration.indexOf('-- ---------------------------------------------------------------------\n-- Part 3'))
  for (const fn of [roleFn, statusFn]) {
    assert.match(fn, /has_platform_permission\('platform\.users\.manage'\)/)
    assert.match(fn, /CANNOT_REMOVE_LAST_PLATFORM_OWNER/)
    assert.match(fn, /role = 'PLATFORM_OWNER' and status = 'ACTIVE' and id <> p_platform_user_id/)
  }
})

test('platform staff and plan mutations write an audit log entry', () => {
  const mutatingFunctions = [
    'rpc_add_platform_user',
    'rpc_set_platform_user_role',
    'rpc_set_platform_user_status',
    'rpc_create_platform_plan',
    'rpc_update_platform_plan',
    'rpc_set_tenant_status',
    'rpc_change_tenant_subscription_plan',
    'rpc_set_tenant_subscription_status',
  ]
  for (const fnName of mutatingFunctions) {
    const start = migration.indexOf(`function public.${fnName}(`)
    assert.notStrictEqual(start, -1, `migration must define ${fnName}`)
    const end = migration.indexOf('\n$$;', start)
    const body = migration.slice(start, end)
    assert.match(body, /has_platform_permission\(/, `${fnName} must check has_platform_permission`)
    assert.match(body, /write_audit_log\(/, `${fnName} must call write_audit_log`)
  }
})

test('tenant status and subscription status changes require an explicit reason and reject invalid values', () => {
  const tenantStatusFn = migration.slice(migration.indexOf('function public.rpc_set_tenant_status'), migration.indexOf('function public.rpc_change_tenant_subscription_plan'))
  assert.match(tenantStatusFn, /p_status not in \('ACTIVE', 'SUSPENDED'\)/)
  assert.match(tenantStatusFn, /REASON_REQUIRED/)

  const subStatusFn = migration.slice(migration.indexOf('function public.rpc_set_tenant_subscription_status'), migration.indexOf('-- ---------------------------------------------------------------------\n-- Part 6'))
  assert.match(subStatusFn, /p_status not in \('ACTIVE', 'SUSPENDED', 'CANCELLED', 'TRIAL'\)/)
  assert.match(subStatusFn, /REASON_REQUIRED/)
  // Must never touch payment/invoice tables -- only ever an auditable manual status override.
  assert.doesNotMatch(subStatusFn, /insert into public\.subscription_payments|subscription_invoices|is_paid|paid_at\s*=/i)
})

test('plan create/update RPCs are permission-gated by platform.plans.manage and audited', () => {
  const createFn = migration.slice(migration.indexOf('function public.rpc_create_platform_plan'), migration.indexOf('function public.rpc_update_platform_plan'))
  const updateFn = migration.slice(migration.indexOf('function public.rpc_update_platform_plan'), migration.indexOf('-- ---------------------------------------------------------------------\n-- Part 4'))
  for (const fn of [createFn, updateFn]) {
    assert.match(fn, /has_platform_permission\('platform\.plans\.manage'\)/)
  }
  assert.match(createFn, /PLAN_CODE_ALREADY_EXISTS/)
  assert.match(updateFn, /PLAN_NOT_FOUND/)
})

test('platform audit log RPC is paginated, filterable and gated by platform.audit.view', () => {
  const fn = migration.slice(migration.indexOf('function public.rpc_list_platform_audit_log'), migration.indexOf('-- ---------------------------------------------------------------------\n-- Part 7'))
  assert.match(fn, /has_platform_permission\('platform\.audit\.view'\)/)
  assert.match(fn, /least\(greatest\(coalesce\(p_limit, 50\), 1\), 200\)/)
  assert.match(fn, /p_before_id is null or al\.id < p_before_id/)
  assert.match(fn, /nextCursor/)
})

test('platform system health RPC reports only real, queryable subsystems and no fabricated data', () => {
  const fn = migration.slice(migration.indexOf('function public.rpc_get_platform_system_health'), migration.indexOf('-- ---------------------------------------------------------------------\n-- Part 8'))
  assert.match(fn, /has_platform_permission\('platform\.system_errors\.view'\)/)
  assert.match(fn, /from public\.sms_outbox where status = 'QUEUED'/)
  assert.match(fn, /from public\.frontend_error_reports where created_at >= now\(\) - interval '24 hours'/)
  assert.match(fn, /from public\.support_requests where status in \('OPEN', 'IN_PROGRESS', 'WAITING_CUSTOMER'\)/)
  // No worker-heartbeat/background-job table exists yet -- must not invent one.
  assert.doesNotMatch(fn, /worker_heartbeat|background_job|'HEALTHY'.*worker/i)
})

test('new ApiErrorCode entries are wired through types, errors.ts and app.ts knownDatabaseCodes consistently', () => {
  const newCodes = [
    'PROFILE_NOT_FOUND',
    'INVALID_PLATFORM_ROLE',
    'PLATFORM_USER_NOT_FOUND',
    'CANNOT_REMOVE_LAST_PLATFORM_OWNER',
    'INVALID_PLATFORM_USER_STATUS',
    'PLAN_CODE_ALREADY_EXISTS',
    'PLAN_NOT_FOUND',
    'INVALID_TENANT_STATUS',
    'TENANT_NOT_FOUND',
    'SUBSCRIPTION_NOT_FOUND',
    'INVALID_SUBSCRIPTION_STATUS',
    'REASON_REQUIRED',
  ]
  const knownDatabaseCodesStart = app.indexOf('= [', app.indexOf('const knownDatabaseCodes')) + 3
  const knownDatabaseCodesBlock = app.slice(knownDatabaseCodesStart, app.indexOf('\n]', knownDatabaseCodesStart))
  for (const code of newCodes) {
    assert.match(types, new RegExp(`\\| '${code}'`), `${code} must be in ApiErrorCode`)
    assert.match(errors, new RegExp(`${code}: \\d+,`), `${code} must have an HTTP status in errorStatus`)
    assert.match(knownDatabaseCodesBlock, new RegExp(`'${code}'`), `${code} must be in app.ts knownDatabaseCodes so RPC errors map correctly`)
  }
})

test('new platform.users permissions are seeded and platform_users writes never hardcode a real user id', () => {
  assert.match(migration, /'platform\.users\.view'/)
  assert.match(migration, /'platform\.users\.manage'/)
  assert.doesNotMatch(migration, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i)
})
