import { env } from '../../../env.js'
import { TestBillingGateway } from './providers/test.gateway.js'
import { NmbBillingGateway } from './providers/nmb.gateway.js'
import type { BillingGatewayProvider, BillingPaymentGateway } from './gateway.types.js'

const gateways: Record<BillingGatewayProvider, BillingPaymentGateway> = {
  TEST: new TestBillingGateway(),
  NMB: new NmbBillingGateway(),
}

export function getBillingGateway(provider: string = env.GATEWAY_PROVIDER): BillingPaymentGateway {
  const key = provider.toUpperCase() as BillingGatewayProvider
  return gateways[key] ?? gateways.TEST
}

export function listBillingGatewayCapabilities() {
  return Object.values(gateways).map((gateway) => gateway.capability())
}
