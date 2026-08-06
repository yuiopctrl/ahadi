# Installment Payment Flow

The payment flow is mobile-first:

1. Select a member.
2. Enter amount, method, date, reference and notes.
3. Review allocation, excess and receipt details.

The server is the source of truth for pledge totals, outstanding balances and unallocated excess. Payment submission includes an idempotency key to prevent duplicate records from double taps.
