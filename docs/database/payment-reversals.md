# Payment Reversals

Confirmed payments are immutable. Incorrect payments are reversed with `rpc_reverse_payment`.

The reversal flow locks the payment, stores a snapshot of the payment, allocations and receipt, sets payment status to `REVERSED`, recalculates affected pledge statuses and writes audit logs.

A payment can be reversed only once. Receipts remain available and render with reversed status and reason.
