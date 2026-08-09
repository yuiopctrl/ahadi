export type BillingGatewayProvider = 'TEST' | 'NMB'
export type BillingPaymentMethod = 'MOBILE_MONEY' | 'CONTROL_NUMBER'
export type BillingGatewayEnvironment = 'SANDBOX' | 'PRODUCTION'
export type BillingGatewayIntentStatus = 'CREATED' | 'PENDING' | 'PROCESSING' | 'SUCCEEDED' | 'FAILED' | 'EXPIRED' | 'CANCELLED'
export type BillingGatewayWebhookStatus = 'SUCCESS' | 'FAILED' | 'PENDING' | 'REVERSED'
export type BillingReferenceMode = 'PAYMENT_INTENT' | 'INVOICE' | 'TENANT' | 'PERSISTENT_CUSTOMER'

export interface CreateGatewayPaymentIntentInput {
  tenantId: string
  subscriptionId: string
  invoiceId: string
  invoiceNumber: string
  amount: number
  currency: string
  customerName: string
  customerPhone: string
  customerEmail?: string | null
  paymentMethod: BillingPaymentMethod
  returnUrl?: string | null
  idempotencyKey: string
}

export interface GatewayPaymentIntentResult {
  provider: BillingGatewayProvider
  providerIntentId: string
  providerReference: string | null
  status: BillingGatewayIntentStatus
  amount: number
  currency: string
  paymentInstructions?: string | null
  checkoutUrl?: string | null
  controlNumber?: string | null
  expiresAt?: string | null
  metadata?: Record<string, unknown>
}

export interface GatewayCapability {
  provider: BillingGatewayProvider
  enabled: boolean
  environment: BillingGatewayEnvironment
  supportedMethods: BillingPaymentMethod[]
  referenceMode: BillingReferenceMode
  webhookStatus: string
  health: 'READY' | 'DISABLED' | 'CONTRACT_REQUIRED' | 'MISCONFIGURED'
}

export interface ParsedGatewayWebhook {
  provider: BillingGatewayProvider
  providerEventId: string | null
  providerIntentId: string
  providerTransactionId: string
  providerReference: string | null
  amount: number
  currency: string
  status: BillingGatewayWebhookStatus
  paidAt: string
  payerPhoneMasked?: string | null
  payloadHash: string
}

export interface VerifyGatewayWebhookInput {
  rawBody: Buffer
  signature: string | null
}

export interface BillingPaymentGateway {
  capability(): GatewayCapability
  createPaymentIntent(input: CreateGatewayPaymentIntentInput): Promise<GatewayPaymentIntentResult>
  verifyWebhook(input: VerifyGatewayWebhookInput): Promise<boolean>
  parseWebhook(rawBody: Buffer): Promise<ParsedGatewayWebhook>
}
