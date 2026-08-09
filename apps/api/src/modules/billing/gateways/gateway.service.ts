import { AppError } from '../../../errors.js'
import type { createUserSupabase } from '../../../supabase.js'
import { getBillingGateway } from './gateway.registry.js'
import type { BillingPaymentMethod, CreateGatewayPaymentIntentInput, ParsedGatewayWebhook } from './gateway.types.js'

type SupabaseClientForUser = ReturnType<typeof createUserSupabase>

function jsonRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function stringField(row: Record<string, unknown>, key: string, fallback = '') {
  const value = row[key]
  return typeof value === 'string' ? value : fallback
}

function numberField(row: Record<string, unknown>, key: string) {
  const value = row[key]
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

export async function createSubscriptionPaymentIntent(
  client: SupabaseClientForUser,
  input: Omit<CreateGatewayPaymentIntentInput, 'amount' | 'currency' | 'subscriptionId' | 'invoiceNumber'> & {
    provider: string
    paymentMethod: BillingPaymentMethod
  },
) {
  const { data: invoiceData, error: invoiceError } = await client
    .from('subscription_invoices')
    .select('id, tenant_id, subscription_id, invoice_number, amount_due, currency, status')
    .eq('id', input.invoiceId)
    .eq('tenant_id', input.tenantId)
    .single()
  if (invoiceError) throw invoiceError

  const invoice = jsonRecord(invoiceData)
  if (['VOID', 'PAID'].includes(stringField(invoice, 'status')) || numberField(invoice, 'amount_due') <= 0) {
    throw new AppError('INVOICE_NOT_PAYABLE')
  }

  const gateway = getBillingGateway(input.provider)
  const capability = gateway.capability()
  if (!capability.enabled) {
    throw new AppError('PAYMENT_GATEWAY_DISABLED')
  }
  if (!capability.supportedMethods.includes(input.paymentMethod)) {
    throw new AppError('PAYMENT_PROVIDER_UNAVAILABLE')
  }

  const gatewayIntent = await gateway.createPaymentIntent({
    tenantId: input.tenantId,
    subscriptionId: stringField(invoice, 'subscription_id'),
    invoiceId: input.invoiceId,
    invoiceNumber: stringField(invoice, 'invoice_number'),
    amount: numberField(invoice, 'amount_due'),
    currency: stringField(invoice, 'currency', 'TZS'),
    customerName: input.customerName,
    customerPhone: input.customerPhone,
    customerEmail: input.customerEmail ?? null,
    paymentMethod: input.paymentMethod,
    returnUrl: input.returnUrl ?? null,
    idempotencyKey: input.idempotencyKey,
  })

  const { data, error } = await client.rpc('rpc_create_subscription_payment_intent', {
    p_tenant_id: input.tenantId,
    p_invoice_id: input.invoiceId,
    p_provider: gatewayIntent.provider,
    p_payment_method: input.paymentMethod,
    p_provider_intent_id: gatewayIntent.providerIntentId,
    p_provider_reference: gatewayIntent.providerReference,
    p_idempotency_key: input.idempotencyKey,
    p_checkout_url: gatewayIntent.checkoutUrl ?? null,
    p_control_number: gatewayIntent.controlNumber ?? null,
    p_expires_at: gatewayIntent.expiresAt ?? null,
    p_metadata: {
      paymentInstructions: gatewayIntent.paymentInstructions ?? null,
      gatewayMetadata: gatewayIntent.metadata ?? {},
    },
  })
  if (error) throw error
  return data
}

export async function confirmParsedGatewayPayment(client: SupabaseClientForUser, parsed: ParsedGatewayWebhook) {
  const { data, error } = await client.rpc('rpc_confirm_subscription_gateway_payment', {
    p_provider: parsed.provider,
    p_provider_intent_id: parsed.providerIntentId,
    p_provider_transaction_id: parsed.providerTransactionId,
    p_provider_reference: parsed.providerReference,
    p_provider_event_id: parsed.providerEventId,
    p_amount: parsed.amount,
    p_currency: parsed.currency,
    p_status: parsed.status,
    p_paid_at: parsed.paidAt,
    p_payload_hash: parsed.payloadHash,
    p_payer_phone_masked: parsed.payerPhoneMasked ?? null,
  })
  if (error) throw error
  return data
}

export async function confirmParsedGatewayReversal(client: SupabaseClientForUser, parsed: ParsedGatewayWebhook) {
  const { data, error } = await client.rpc('rpc_confirm_subscription_gateway_reversal', {
    p_provider: parsed.provider,
    p_provider_transaction_id: parsed.providerTransactionId,
    p_provider_event_id: parsed.providerEventId,
    p_amount: parsed.amount,
    p_currency: parsed.currency,
    p_reversed_at: parsed.paidAt,
    p_payload_hash: parsed.payloadHash,
  })
  if (error) throw error
  return data
}
