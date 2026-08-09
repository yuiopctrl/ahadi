import { createHmac, createHash } from 'node:crypto'
import { env } from '../../../../env.js'
import type {
  BillingPaymentGateway,
  CreateGatewayPaymentIntentInput,
  GatewayCapability,
  GatewayPaymentIntentResult,
  ParsedGatewayWebhook,
  VerifyGatewayWebhookInput,
} from '../gateway.types.js'

function sha256(input: Buffer) {
  return createHash('sha256').update(input).digest('hex')
}

function sign(rawBody: Buffer) {
  return createHmac('sha256', env.TEST_GATEWAY_WEBHOOK_SECRET).update(rawBody).digest('hex')
}

export class TestBillingGateway implements BillingPaymentGateway {
  capability(): GatewayCapability {
    return {
      provider: 'TEST',
      enabled: env.NODE_ENV !== 'production',
      environment: 'SANDBOX',
      supportedMethods: ['MOBILE_MONEY', 'CONTROL_NUMBER'],
      referenceMode: 'PAYMENT_INTENT',
      webhookStatus: 'READY',
      health: env.NODE_ENV === 'production' ? 'DISABLED' : 'READY',
    }
  }

  async createPaymentIntent(input: CreateGatewayPaymentIntentInput): Promise<GatewayPaymentIntentResult> {
    const providerIntentId = `test_intent_${input.invoiceId}_${input.idempotencyKey}`.replace(/[^a-zA-Z0-9_:-]/g, '_').slice(0, 120)
    const controlNumber = `99${Math.abs([...providerIntentId].reduce((sum, char) => sum + char.charCodeAt(0), 0)).toString().padStart(10, '0').slice(0, 10)}`
    return {
      provider: 'TEST',
      providerIntentId,
      providerReference: input.invoiceNumber,
      status: 'PENDING',
      amount: input.amount,
      currency: input.currency,
      controlNumber,
      expiresAt: new Date(Date.now() + 30 * 60_000).toISOString(),
      paymentInstructions: `Use test control number ${controlNumber} for invoice ${input.invoiceNumber}.`,
      metadata: {
        paymentMethod: input.paymentMethod,
        referenceMode: 'PAYMENT_INTENT',
        returnUrl: input.returnUrl ?? null,
      },
    }
  }

  async verifyWebhook(input: VerifyGatewayWebhookInput): Promise<boolean> {
    if (!input.signature) return false
    return input.signature === sign(input.rawBody)
  }

  async parseWebhook(rawBody: Buffer): Promise<ParsedGatewayWebhook> {
    const payload = JSON.parse(rawBody.toString('utf8')) as Record<string, unknown>
    return {
      provider: 'TEST',
      providerEventId: typeof payload['eventId'] === 'string' ? payload['eventId'] : null,
      providerIntentId: String(payload['providerIntentId'] ?? ''),
      providerTransactionId: String(payload['providerTransactionId'] ?? payload['transactionId'] ?? ''),
      providerReference: typeof payload['providerReference'] === 'string' ? payload['providerReference'] : null,
      amount: Number(payload['amount']),
      currency: String(payload['currency'] ?? 'TZS').toUpperCase(),
      status: String(payload['status'] ?? 'SUCCESS').toUpperCase() as ParsedGatewayWebhook['status'],
      paidAt: typeof payload['paidAt'] === 'string' ? payload['paidAt'] : new Date().toISOString(),
      payerPhoneMasked: typeof payload['payerPhoneMasked'] === 'string' ? payload['payerPhoneMasked'] : null,
      payloadHash: sha256(rawBody),
    }
  }
}

export function signTestGatewayWebhookForTests(rawBody: Buffer) {
  return sign(rawBody)
}
