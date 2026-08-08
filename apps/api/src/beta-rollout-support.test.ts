import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/030_beta_rollout_support_operations.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const types = readFileSync(new URL('../../../packages/types/src/index.ts', import.meta.url), 'utf8')
const validation = readFileSync(new URL('../../../packages/validation/src/index.ts', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../../../apps/web/src/lib/api.ts', import.meta.url), 'utf8')
const routes = readFileSync(new URL('../../../apps/web/src/routes/index.tsx', import.meta.url), 'utf8')
const tenantPage = readFileSync(new URL('../../../apps/web/src/pages/tenant.tsx', import.meta.url), 'utf8')
const platformPage = readFileSync(new URL('../../../apps/web/src/pages/platform.tsx', import.meta.url), 'utf8')

test('batch 7 migration creates rollout, invitation, feature, support, feedback and error tables', () => {
  for (const table of [
    'platform_settings',
    'beta_invitations',
    'product_events',
    'support_requests',
    'product_feedback',
    'feature_flags',
    'tenant_feature_flags',
    'frontend_error_reports',
    'support_access_sessions',
  ]) {
    assert.match(migration, new RegExp(`create table if not exists public\\.${table}`))
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`))
  }
  assert.match(migration, /registration_mode text not null default 'OPEN'/)
  assert.match(migration, /create or replace function public\.has_feature/)
  assert.match(migration, /coalesce\(\([\s\S]*where flag\.key = p_feature_key[\s\S]*\), false\)/)
})

test('batch 7 API enforces registration policy and tenant feature flags', () => {
  assert.match(types, /REGISTRATION_PAUSED/)
  assert.match(types, /INVITATION_REQUIRED/)
  assert.match(types, /FEATURE_DISABLED/)
  assert.match(types, /betaInvitationCode\?: string \| null/)
  assert.match(validation, /betaInvitationCode: nullableTextSchema\(64\)/)
  assert.match(app, /app\.get\('\/api\/v1\/rollout-settings'/)
  assert.match(app, /registrationMode === 'PAUSED'/)
  assert.match(app, /registrationMode === 'INVITE_ONLY'/)
  assert.match(app, /rpc_validate_beta_invitation/)
  assert.match(app, /rpc_consume_beta_invitation/)
  assert.match(app, /ensureTenantFeatureEnabled\(client, tenantId, 'whatsapp_lists'\)/)
  assert.match(app, /ensureTenantFeatureEnabled\(client, tenantId, 'balance_reminders'\)/)
  assert.match(app, /reportType === 'member-statement' \? 'member_statement_pdf' : 'report_exports'/)
})

test('batch 7 platform and support endpoints are exposed to the web client', () => {
  for (const method of [
    'rolloutSettings',
    'platformBeta',
    'updateRolloutSettings',
    'createBetaInvitation',
    'platformSupport',
    'updatePlatformSupportRequest',
    'platformFeedback',
    'platformFeatures',
    'platformErrors',
    'supportRequests',
    'createSupportRequest',
    'createFeedback',
    'reportFrontendError',
  ]) {
    assert.match(apiClient, new RegExp(`${method}:`))
  }
  for (const route of [
    "path: 'beta', element: <PlatformBetaPage />",
    "path: 'support', element: <PlatformSupportPage />",
    "path: 'feedback', element: <PlatformFeedbackPage />",
    "path: 'features', element: <PlatformFeaturesPage />",
    "path: 'system/errors', element: <PlatformErrorsPage />",
    "path: 'help', element: <TenantHelpPage />",
  ]) {
    assert.match(routes, new RegExp(route.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  }
})

test('batch 7 UI contains operational beta, support, feature and help surfaces', () => {
  assert.match(platformPage, /PlatformBetaPage/)
  assert.match(platformPage, /Registration Policy/)
  assert.match(platformPage, /Create Invite/)
  assert.match(platformPage, /Support Desk/)
  assert.match(platformPage, /Feature Flags/)
  assert.match(platformPage, /Error Signals/)
  assert.match(tenantPage, /TenantHelpPage/)
  assert.match(tenantPage, /First-Run Checklist/)
  assert.match(tenantPage, /Contact Support/)
  assert.match(tenantPage, /Beta Feedback/)
})
