import { AppError } from '../../../../errors.js'
import { env } from '../../../../env.js'
import type {
  BillingPaymentGateway,
  GatewayCapability,
  GatewayPaymentIntentResult,
  ParsedGatewayWebhook,
} from '../gateway.types.js'

export class NmbBillingGateway implements BillingPaymentGateway {
  capability(): GatewayCapability {
    const configured = Boolean(env.NMB_BASE_URL && env.NMB_CLIENT_ID && env.NMB_CLIENT_SECRET && env.NMB_WEBHOOK_SECRET)
    return {
      provider: 'NMB',
      enabled: false,
      environment: env.GATEWAY_ENVIRONMENT,
      supportedMethods: ['MOBILE_MONEY', 'CONTROL_NUMBER'],
      referenceMode: 'PAYMENT_INTENT',
      webhookStatus: configured ? 'CONTRACT_REQUIRED' : 'MISSING_SECRETS',
      health: configured ? 'CONTRACT_REQUIRED' : 'MISCONFIGURED',
    }
  }

  async createPaymentIntent(): Promise<GatewayPaymentIntentResult> {
    throw new AppError('PAYMENT_PROVIDER_UNAVAILABLE', 'NMB gateway contract is not configured')
  }

  async verifyWebhook(): Promise<boolean> {
    return false
  }

  async parseWebhook(): Promise<ParsedGatewayWebhook> {
    throw new AppError('PAYMENT_WEBHOOK_INVALID', 'NMB webhook contract is not configured')
  }
}
