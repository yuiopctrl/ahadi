import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/037_subscription_payment_gateway_foundation.sql', import.meta.url), 'utf8')
const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')
const types = readFileSync(new URL('../../../packages/types/src/index.ts', import.meta.url), 'utf8')
const service = readFileSync(new URL('./modules/billing/gateways/gateway.service.ts', import.meta.url), 'utf8')
const testGateway = readFileSync(new URL('./modules/billing/gateways/providers/test.gateway.ts', import.meta.url), 'utf8')
const nmbGateway = readFileSync(new URL('./modules/billing/gateways/providers/nmb.gateway.ts', import.meta.url), 'utf8')

test('subscription gateway migration creates isolated subscription billing tables', () => {
  for (const table of [
    'subscription_invoices',
    'subscription_invoice_items',
    'subscription_payments',
    'subscription_payment_allocations',
    'subscription_payment_intents',
    'subscription_gateway_transactions',
    'subscription_gateway_settings',
    'private.subscription_gateway_webhook_events',
  ]) {
    assert.match(migration, new RegExp(table.replace('.', '\\.')))
  }
  assert.match(migration, /subscription_payment_intents_provider_intent_unique/)
  assert.match(migration, /subscription_payment_intents_idempotency_unique/)
  assert.match(migration, /subscription_gateway_transactions_provider_tx_unique/)
  assert.match(migration, /subscription_gateway_webhook_events_hash_unique/)
  assert.doesNotMatch(migration, /event_member_id/)
  assert.doesNotMatch(migration, /pledge_id/)
  assert.doesNotMatch(migration, /collector_id/)
})

test('verified webhook confirmation is server-side, idempotent and amount-checked', () => {
  assert.match(migration, /create or replace function public\.rpc_confirm_subscription_gateway_payment/)
  assert.match(migration, /create or replace function public\.rpc_confirm_subscription_gateway_reversal/)
  assert.match(migration, /for update/)
  assert.match(migration, /PAYMENT_AMOUNT_MISMATCH/)
  assert.match(migration, /PAYMENT_CURRENCY_MISMATCH/)
  assert.match(migration, /insert into private\.subscription_gateway_webhook_events/)
  assert.match(migration, /insert into public\.subscription_gateway_transactions/)
  assert.match(migration, /insert into public\.subscription_payments/)
  assert.match(migration, /insert into public\.subscription_payment_allocations/)
  assert.match(migration, /amount_due = greatest\(total_amount - \(amount_paid \+ allocated_amount\), 0\)/)
  assert.match(migration, /status = 'SUCCEEDED'/)
  assert.match(migration, /SUBSCRIPTION_GATEWAY_PAYMENT_REVERSED/)
  assert.match(migration, /transaction_type = 'PAYMENT'/)
})

test('API exposes tenant payment-intent and platform gateway routes with raw webhook body', () => {
  const rawWebhookIndex = app.indexOf("app.post('/api/v1/webhooks/billing/test', express.raw")
  const jsonIndex = app.indexOf('app.use(express.json')
  assert.ok(rawWebhookIndex > 0)
  assert.ok(jsonIndex > rawWebhookIndex)
  assert.match(app, /app\.post\('\/api\/v1\/billing\/invoices\/:invoiceId\/payment-intents'/)
  assert.match(app, /app\.get\('\/api\/v1\/billing\/payment-intents\/:intentId'/)
  assert.match(app, /app\.get\('\/api\/v1\/platform\/billing\/gateways'/)
  assert.match(app, /app\.get\('\/api\/v1\/platform\/billing\/reconciliation'/)
  assert.match(app, /X-Ahadi-Test-Signature/)
  assert.match(app, /parsed\.status === 'REVERSED'/)
})

test('browser payment intent input cannot override invoice money fields', () => {
  assert.match(service, /\.from\('subscription_invoices'\)/)
  assert.match(service, /\.select\('id, tenant_id, subscription_id, invoice_number, amount_due, currency, status'\)/)
  assert.match(service, /amount: numberField\(invoice, 'amount_due'\)/)
  assert.match(service, /currency: stringField\(invoice, 'currency', 'TZS'\)/)
  assert.doesNotMatch(service, /input\.amount/)
  assert.doesNotMatch(service, /input\.currency/)
})

test('normalized payment gateway errors are part of public API types', () => {
  for (const code of [
    'PAYMENT_GATEWAY_DISABLED',
    'PAYMENT_PROVIDER_UNAVAILABLE',
    'PAYMENT_INTENT_NOT_FOUND',
    'PAYMENT_AMOUNT_MISMATCH',
    'PAYMENT_CURRENCY_MISMATCH',
    'PAYMENT_WEBHOOK_INVALID',
    'PAYMENT_ALREADY_PROCESSED',
    'PAYMENT_RECONCILIATION_REQUIRED',
  ]) {
    assert.match(types, new RegExp(`'${code}'`))
    assert.match(app, new RegExp(`'${code}'`))
  }
})

test('TEST gateway is sandbox-only and NMB remains contract-required', () => {
  assert.match(testGateway, /provider: 'TEST'/)
  assert.match(testGateway, /env\.NODE_ENV !== 'production'/)
  assert.match(testGateway, /createHmac\('sha256'/)
  assert.match(testGateway, /controlNumber/)
  assert.match(nmbGateway, /provider: 'NMB'/)
  assert.match(nmbGateway, /CONTRACT_REQUIRED/)
  assert.match(nmbGateway, /PAYMENT_PROVIDER_UNAVAILABLE/)
})
