import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const middleware = readFileSync(new URL('./middleware.ts', import.meta.url), 'utf8')
const access = readFileSync(new URL('./access.ts', import.meta.url), 'utf8')
const types = readFileSync(new URL('../../../packages/types/src/index.ts', import.meta.url), 'utf8')
const subscriptionContextMigration = readFileSync(new URL('../../../supabase/migrations/026_share_and_event_creation_stabilization.sql', import.meta.url), 'utf8')
const smsLimitMigration = readFileSync(new URL('../../../supabase/migrations/024_balance_reminders.sql', import.meta.url), 'utf8')

test('public packages and tenant billing summary reuse the established subscription model', () => {
  assert.match(app, /app\.get\('\/api\/v1\/plans'/)
  assert.match(app, /\.from\('subscription_plans'\)[\s\S]+\.eq\('is_active', true\)[\s\S]+\.eq\('is_public', true\)/)
  assert.match(app, /app\.get\('\/api\/v1\/billing\/summary', requireAuth, loadUserContext, requireTenantContext/)
  assert.match(app, /subscription: request\.tenantContext\?\.subscription \?\? null/)
  assert.match(app, /\.from\('subscription_invoices'\)[\s\S]+\.eq\('tenant_id', tenantId\)/)
  assert.match(app, /\.from\('subscription_payments'\)[\s\S]+\.eq\('tenant_id', tenantId\)/)
  assert.match(types, /export interface SubscriptionPlan/)
  assert.match(types, /export interface SubscriptionSummary/)
})

test('tenant subscription context includes plan identity, trial dates and server-side usage limits', () => {
  assert.match(subscriptionContextMigration, /create or replace function public\.subscription_context_json/)
  assert.match(subscriptionContextMigration, /'planCode', sp\.code/)
  assert.match(subscriptionContextMigration, /'planName', sp\.name/)
  assert.match(subscriptionContextMigration, /'trialEndsAt', ts\.trial_ends_at/)
  assert.match(subscriptionContextMigration, /'currentPeriodEnd', ts\.current_period_end/)
  assert.match(subscriptionContextMigration, /'limits', ts\.plan_snapshot \|\| public\.event_slot_usage\(p_tenant_id\)/)
  assert.match(subscriptionContextMigration, /'eventUsage', public\.event_slot_usage\(p_tenant_id\)/)
})

test('package limits remain backend-enforced for tenant write actions and SMS sends', () => {
  assert.match(app, /SUBSCRIPTION_READ_ONLY/)
  assert.match(app, /EVENT_LIMIT_REACHED/)
  assert.match(subscriptionContextMigration, /raise exception 'EVENT_LIMIT_REACHED'/)
  assert.match(smsLimitMigration, /SMS_LIMIT_REACHED/)
  assert.match(middleware, /calculateTenantAccessState/)
  assert.match(access, /'BLOCKED'/)
  assert.match(access, /'READ_ONLY'/)
})
