# Payments And Allocations

`payments` represent money received from an event member. `payment_allocations` apply confirmed payments to pledges.

Payments use tenant-scoped `PAY-000001` numbers. Receipts use `tenant_settings.receipt_prefix`, for example `AHD-000001`.

Allocations never exceed the payment amount. When a payment is larger than pledge outstanding balance, Ahadi allocates only up to outstanding and preserves the excess as unallocated member payment balance.

Confirmed financial records are not deleted. Corrections are handled by reversal and re-entry.
