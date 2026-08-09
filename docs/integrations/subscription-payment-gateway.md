# Subscription Payment Gateway

Ahadi subscription payment gateways are only for SaaS billing invoices. They must not be reused for event pledges, event member payments, pledge receipts, collectors, or event reports.

## Current Providers

- `TEST`: internal sandbox adapter for development and tests. Enabled only outside production.
- `NMB`: placeholder adapter. It is disabled until the real provider contract, endpoint list, authentication method, payload examples, and webhook signature rules are supplied.

## Environment

Required foundation variables:

- `GATEWAY_PROVIDER=TEST`
- `GATEWAY_ENVIRONMENT=SANDBOX`
- `TEST_GATEWAY_WEBHOOK_SECRET`

Future NMB variables:

- `NMB_BASE_URL`
- `NMB_CLIENT_ID`
- `NMB_CLIENT_SECRET`
- `NMB_WEBHOOK_SECRET`

Never place provider credentials in public tables, Vite variables, tenant settings, browser bundles, docs, or screenshots.

## Tenant Flow

1. Tenant owner opens `/app/settings/billing`.
2. Tenant opens a payable invoice.
3. Browser calls `POST /api/v1/billing/invoices/:invoiceId/payment-intents`.
4. API reloads the invoice and derives amount, balance, tenant, subscription, and currency.
5. Gateway adapter creates a provider intent or control number.
6. Browser displays instructions but never marks the invoice as paid.
7. Verified webhook confirms the payment server-side.
8. Database records one gateway transaction, one subscription payment, one allocation, and updates invoice/subscription state atomically.

## Webhook

Development route:

`POST /api/v1/webhooks/billing/test`

The TEST route verifies `X-Ahadi-Test-Signature` using HMAC SHA-256 over the raw request body. Production provider routes must use the exact verification method required by the provider contract.

Webhook processing stores normalized transaction data in public subscription billing tables. Raw payloads are not exposed to tenant UI. Restricted delivery metadata is kept in `private.subscription_gateway_webhook_events`.

## Idempotency

Payment attempts are protected by:

- unique `(tenant_id, invoice_id, idempotency_key)` on `subscription_payment_intents`
- unique `(provider, provider_intent_id)` when provider intent exists
- unique `(provider, provider_transaction_id, transaction_type)` on gateway transactions
- unique webhook payload/provider event tracking in the private inbox
- row locks inside `rpc_confirm_subscription_gateway_payment`

Repeated successful callbacks must produce one financial effect.

## Reconciliation

Platform owners can inspect:

- `/platform/billing/gateways`
- `/platform/billing/reconciliation`

The reconciliation view is read-only. It flags unmatched, mismatched, stale, or review-required rows without repairing money records automatically.

## Failure Handling

Normalized errors include:

- `PAYMENT_GATEWAY_DISABLED`
- `PAYMENT_PROVIDER_UNAVAILABLE`
- `PAYMENT_AMOUNT_MISMATCH`
- `PAYMENT_CURRENCY_MISMATCH`
- `PAYMENT_WEBHOOK_INVALID`
- `PAYMENT_ALREADY_PROCESSED`
- `PAYMENT_RECONCILIATION_REQUIRED`

Provider stack traces, raw payloads, secrets, and full payer phones must not be shown in tenant UI.

## Production Cutover

Do not enable a production gateway until `payment-gateway-production-checklist.md` is complete and signed off.
