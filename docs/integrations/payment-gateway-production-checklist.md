# Payment Gateway Production Checklist

Complete this checklist before enabling any production subscription payment gateway.

- Production provider contract received and reviewed.
- Production endpoints documented.
- Authentication method documented.
- Webhook signature or certificate verification documented.
- Production credentials installed outside the repository.
- `GATEWAY_PROVIDER` set to the approved provider.
- `GATEWAY_ENVIRONMENT=PRODUCTION`.
- Public webhook URL configured with the provider.
- Webhook verification tested with valid and invalid signatures.
- Transaction status lookup tested if provider supports it.
- Successful payment tested.
- Failed payment tested.
- Duplicate webhook delivery tested.
- Amount mismatch tested.
- Currency mismatch tested.
- Reversal callback tested.
- Refund foundation reviewed, with self-service refunds disabled.
- Reconciliation page reviewed after sandbox and production test payments.
- Logs and alerts reviewed for safe fields only.
- Tenant billing invoice flow verified on mobile viewports.
- Platform gateway and reconciliation permissions verified.
- Event pledge/payment reports verified as unchanged.
- Rollback plan documented.

Production must remain disabled until every item passes.
