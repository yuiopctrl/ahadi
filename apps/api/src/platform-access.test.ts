import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const middleware = readFileSync(new URL('./middleware.ts', import.meta.url), 'utf8')
const types = readFileSync(new URL('../../../packages/types/src/index.ts', import.meta.url), 'utf8')
const contextMigration = readFileSync(new URL('../../../supabase/migrations/017_fix_platform_access_context.sql', import.meta.url), 'utf8')
const rlsMigration = readFileSync(new URL('../../../supabase/migrations/006_rls_helpers_and_policies.sql', import.meta.url), 'utf8')
const rbacMigration = readFileSync(new URL('../../../supabase/migrations/003_profiles_and_rbac.sql', import.meta.url), 'utf8')

test('platform context returns active role, status and permissions independently from tenant membership', () => {
  assert.match(contextMigration, /left join public\.platform_users pu on pu\.user_id = p\.id/i)
  assert.doesNotMatch(contextMigration, /left join public\.platform_users pu on pu\.user_id = p\.id and pu\.status = 'ACTIVE'/i)
  assert.match(contextMigration, /'platformStatus', pu\.status/)
  assert.match(contextMigration, /'platformPermissions'/)
  assert.match(contextMigration, /'platform\.dashboard\.view'/)
  assert.match(contextMigration, /from public\.tenant_users tu[\s\S]+where tu\.user_id = auth\.uid\(\) and tu\.status <> 'REMOVED'/)
  assert.match(types, /platformStatus: PlatformUserStatus \| null/)
  assert.match(types, /platformPermissions: string\[\]/)
})

test('platform owner receives dashboard permission and suspended users are not active platform users', () => {
  assert.match(rlsMigration, /pu\.role = 'PLATFORM_OWNER'/)
  assert.match(rlsMigration, /where user_id = auth\.uid\(\) and status = 'ACTIVE'/)
  assert.match(contextMigration, /when pu\.role = 'PLATFORM_OWNER' then to_jsonb\(platform_permissions\.owner_permissions\)/)
  assert.match(contextMigration, /when pu\.status <> 'ACTIVE' or pu\.id is null then '\[\]'::jsonb/)
})

test('platform API routes require auth and platform permission without tenant context or X-Tenant-ID', () => {
  for (const route of ['/api/v1/platform/dashboard', '/api/v1/platform/tenants', '/api/v1/platform/plans']) {
    const pattern = new RegExp(`app\\.get\\('${route.replaceAll('/', '\\/')}'.+requireAuth, loadUserContext, requirePlatformPermission`, 's')
    assert.match(app, pattern)
  }
  const platformBlock = app.slice(app.indexOf("app.get('/api/v1/platform/dashboard'"), app.indexOf("app.get('/api/v1/events/:eventId/financial-summary'"))
  assert.doesNotMatch(platformBlock, /requireTenantContext/)
  assert.doesNotMatch(platformBlock, /X-Tenant-ID/)
})

test('authenticated API responses disable browser cache validation', () => {
  assert.match(app, /app\.disable\('etag'\)/)
  assert.match(app, /app\.use\('\/api\/v1'/)
  assert.match(app, /Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate'/)
  assert.match(app, /Surrogate-Control', 'no-store'/)
})

test('development CORS allows common localhost web origins', () => {
  assert.match(app, /developmentWebOrigins = new Set/)
  assert.match(app, /'http:\/\/localhost:5173'/)
  assert.match(app, /'http:\/\/127\.0\.0\.1:5173'/)
  assert.match(app, /'http:\/\/localhost:5174'/)
  assert.match(app, /'http:\/\/127\.0\.0\.1:5174'/)
  assert.match(app, /callback\(null, origin \?\? true\)/)
  assert.match(app, /'Cache-Control'/)
  assert.match(app, /'Pragma'/)
})

test('production CORS and public health endpoint support web refresh checks', () => {
  assert.match(app, /productionWebOrigins = new Set/)
  assert.match(app, /'https:\/\/ahadi\.yuiop\.work'/)
  assert.match(app, /productionWebOrigins\.has\(origin\)/)
  assert.match(app, /app\.get\('\/api\/v1\/health', \(_request, response\) => \{\s+response\.json\(healthPayload\(\)\)/)
  assert.doesNotMatch(app, /app\.get\('\/api\/v1\/health', requireAuth/)
})

test('platform middleware authorizes from platform permissions and returns 403 for inactive or missing permission', () => {
  assert.match(types, /\| 'PLATFORM_ACCESS_DENIED'/)
  assert.match(middleware, /activePlatformRoles = new Set/)
  assert.match(middleware, /!context \|\| context\.platformStatus !== 'ACTIVE' \|\| !context\.platformRole \|\| !activePlatformRoles\.has\(context\.platformRole\)/)
  assert.match(middleware, /context\.platformPermissions\.includes\(permission\)/)
  assert.doesNotMatch(middleware, /context\?\.isPlatformUser|context\.isPlatformUser/)
  assert.doesNotMatch(middleware, /context\.platformRole === 'PLATFORM_ADMIN'/)
})

test('platform ownership remains a manual bootstrap and is not exposed through onboarding', () => {
  assert.match(rbacMigration, /Bootstrap manually after intended owner authenticates/)
  assert.doesNotMatch(app, /from\('platform_users'\)\.insert|insert into public\.platform_users/i)
  assert.doesNotMatch(app, /rpc_complete_tenant_onboarding[\s\S]+platform_users/i)
})
