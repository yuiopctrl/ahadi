# Pledges

Ahadi supports one primary pledge per event member in this phase. Pledges store the committed amount and due date, while paid totals come only from confirmed payment allocations.

Status is synchronized by database functions:

- `PAID`: confirmed allocated amount is at least pledged amount.
- `PARTIALLY_PAID`: confirmed allocated amount is above zero and below pledged amount.
- `OVERDUE`: unpaid balance remains and the due date has passed.
- `PENDING`: no confirmed allocation and not overdue.
- `CANCELLED`: explicit cancellation.

`pledge_history` is append-only and records creation, amount changes, due-date changes, cancellation and status changes.
