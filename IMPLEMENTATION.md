# Operational POS implementation

Implemented against `suggestion.md`, September 30, 2026.

## Workflow

1. Sign in with an assigned `cashier`, `kitchen`, or `admin` role.
2. A cashier opens a cash shift with the counted opening float.
3. Build an order. Cart lines are keyed by product ID and saved locally per account.
4. Refresh and explicitly reconcile changed stock/prices before taking payment.
5. Enter customer, dine-in/table or takeaway, and cash received. Confirm the amounts.
6. A durable checkout ID is saved before calling the server. The server locks products, validates prices and quantities, records the sale/payment/movements, and returns a receipt in one transaction.
7. A lost response leaves a recoverable pending request. Check/retry sends the same ID and payload. Do not clear application storage while a request is pending.
8. Kitchen/admin advances Queued → Preparing → Ready → Served. Events record who did each step.
9. Admin can reopen service with a reason, or refund/void a full nonlegacy sale. Refunds record cash returned in the admin's open shift. Restocking is an explicit choice, off by default.
10. Close the cash shift with counted cash and an explanation for any difference.

## Review coverage

| Review item | Implementation |
| --- | --- |
| Safe retries | Unique request ID and exact request-body check; advisory lock; persisted per-account request; lookup and retry UI. |
| Stable cart | Product-ID keys; current catalog reconciliation; persisted draft. |
| Complete payment record | Integer minor units, cash/change, cashier, immutable line snapshots, generated receipt, immediate copy/printable export. |
| Permissions and checkout rules | One guarded RPC; live role lookup from `auth.users`; direct table writes and legacy mutation endpoints revoked; product row locks; rollback on errors. |
| Stock audit | Opening stock, reasoned batch adjustments, old-quantity comparison, actor/time/notes, ten-movement history pages. |
| Service flow | Queued, preparing, ready, served; customer/table/pickup context; elapsed time; staff names and event history. |
| Corrections | Full refund/void with reason and explicit restock choice; service reopening with reason; original sale preserved. |
| Invoice detail and summaries | Stored unit/line amounts and tender; copy and printable HTML; CSV invoices; printable daily/weekly/monthly summaries. Legacy unknown amounts remain unknown. |
| Pagination | Invoice and service cursors; server filtering and totals; inventory fetches ten records. Menu uses a catalog cache with ten visible products per page. |
| Business dates and cash | Server uses Asia/Manila and midnight; reversals count on their event date; opening/cash movements/closing reconciliation. |
| Navigation and failures | Indexed page state; pending draft survives account logout/restart; actionable API errors; order polling pauses for hidden/background pages. |
| Forms and devices | Scrollable cart and entry sheets; validated names, prices, quantities; explicit quantity buttons and accessible success messages. |

## Data and deployment

- New authoritative records live in `pos_transactions`, `pos_lines`, `pos_events`, `pos_stock_movements`, `pos_shifts`, and `pos_cash_events`.
- Original sales/line tables remain intact as historical source data. The migration copies their rows once. It does not reduce stock while importing history.
- Original product rows remain the inventory source.
- Existing unknown legacy payment details are not invented. Legacy financial corrections are blocked because original tender/payment detail cannot be established; reconcile them separately.
- The unverified hardcoded 12% VAT display is removed. Exports state that a tax breakdown is not configured. No tax treatment is assumed.
- The application now requires the new migration. It shows a setup error rather than silently falling back to the old checkout.
- Apply the migration using [supabase/SETUP.md](D:/POS/hankatsu/supabase/SETUP.md). No live Supabase changes were made during local implementation.

## Deliberate limits

- Single store, pay-before-service, whole-order fulfillment, cash payments, and full reversals. Partial service, partial refunds, card processing, and multiple branches require a separately agreed workflow.
- Printable HTML opens or downloads to the device; open it in a browser and use Print / Save as PDF. Native mobile printer integrations are not included. Native exports are saved under the app's documents/Hankatsu directory if automatic opening is unavailable.
- Drafts use device preferences. They survive ordinary restarts but not application storage clearing, device loss, or cross-device migration. They are not a server-side offline payment queue.
- The menu intentionally caches products. Invoice and kitchen history are fetched on demand. Cursor paging excludes newly created records beyond the selected report cutoff; simultaneous multi-session behavior must still be verified in staging.
- The original production schema and arbitrary custom RPCs were unavailable. Preflight captures the known schema/function/grant definitions; review any custom mutation endpoint outside the named legacy functions before rollout.

## Verification

- `npm test`: embedded PostgreSQL tests for migrations, retries, permissions, product/price checks, cash shifts, service transitions, reversals, and invoice cursors.
- `flutter test --no-pub`: money parsing, product-ID carts, draft persistence, checkout confirmation, filter contrast, service transitions, and invoice page loading.
- `flutter analyze`: application and test diagnostics.
- `flutter build web --no-pub`: compile the application with browser export support.

PGlite serializes its embedded connection. Competing-request tests verify the result but do not replace a real two-session PostgreSQL lock test. Staging must additionally test two devices, expired sessions, lost responses after commit, migration against the real schema, and native export behavior on the deployment device.
