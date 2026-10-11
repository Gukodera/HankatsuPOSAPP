# Hankatsu POS — system flow review

Reviewed: September 30, 2026

## Overall assessment

The app supports a useful basic flow: sign in, build a cart, record a cash sale, mark the order served, and inspect sales history. The recent filters, confirmations, customer names, and pagination improve daily use.

My assessment: prioritize transaction correctness and recovery before another visual redesign. A cashier needs to know whether a payment was saved, a kitchen worker needs to identify the right order, and an administrator needs to explain every stock change. The current flow does not yet answer these questions reliably in all failure cases.

This review covers the local Dart code, the supplied order-tracking SQL, and the test sources. It is not a live Supabase audit. The implementation of `complete_sale`, the original table definitions, and the existing Row Level Security policies are absent locally. Findings below distinguish visible application gaps from backend behavior that requires verification. No application code was changed for this review, and tests were not rerun for this documentation task.

## What should stay

- Keep the red selected filters with white labels and checkmarks.
- Keep the payment, logout, and stock-change confirmations requested for this app.
- Keep server-recorded serving timestamps and admin IDs.
- Keep the separate invoice archive and daily, weekly, and monthly ranges.
- Keep explicit empty states, disabled save buttons, and success feedback.
- Preserve historical orders with unknown service status rather than inventing a status.

## Priority order

| Priority | Change | Why it comes first |
| --- | --- | --- |
| P1 | Make sale submission safe to retry | A lost response must not produce another sale. |
| P1 | Key cart lines by product ID | Refreshing the menu can break the relationship between the cart and product cards. |
| P1 | Save and return a complete transaction result | The cashier needs an authoritative total, payment record, and receipt reference. |
| P1 | Verify checkout rules and permissions on the server | UI restrictions cannot establish database permissions or prevent overselling. |
| P2 | Add stock movement history and batch adjustments | Current quantities do not explain who changed stock or why. |
| P2 | Improve order handoff and correction flows | Waiting/served alone cannot explain preparation, mistakes, or partial service. |
| P2 | Complete invoice and reporting semantics | A transaction list is useful, but it does not provide all the records needed for reconciliation. |
| P2 | Implement server pagination and consistent reporting queries | Showing ten records does not currently limit database loading. |
| P3 | Improve navigation continuity, form behavior, and accessibility | Reduce repeated work and make failures easier to recover from. |

P1 means resolve before relying on the app for routine live transactions. P2 means address in the next operational release. P3 means improve after the underlying records and transitions are dependable.

## 1. P1 — A payment retry can create uncertainty or a duplicate

**Evidence:** [Repo.sale and checkout completion](D:/POS/hankatsu/lib/main.dart:102), [payment confirmation](D:/POS/hankatsu/lib/checkout_sheet.dart:43), and [complete_named_sale](D:/POS/hankatsu/supabase/order_tracking.sql:37).

The client submits product IDs, quantities, and a customer name. It sends no unique checkout request ID. The SQL wrapper returns `void`. A local busy flag prevents rapid taps, but it cannot resolve a request that commits in Supabase and then loses its response.

**Failure scenario:** The cashier confirms a sale. The database saves it, but connectivity drops. The UI shows a connection error and retains the cart. Retrying may create another sale. Whether the existing backend has independent protection is unverified; the visible interface does not provide enough information to identify a retry.

**Recommended change:** Generate one checkout ID when payment begins. Keep it through retries and app recovery. Enforce uniqueness in the database and return the same saved sale for that ID. Show distinct states: saving, saved, not saved, and result unknown. For an unknown result, offer “Check transaction” before another submission.

**Acceptance criteria:** Simulate a lost response after commit. Retrying creates exactly one sale, deducts stock once, and displays the original receipt reference.

## 2. P1 — Refreshing the menu can leave a stale cart

**Evidence:** [cart declaration](D:/POS/hankatsu/lib/main.dart:201) and [product reload](D:/POS/hankatsu/lib/main.dart:268).

The cart is a `Map<Item, int>`. `Item` uses object identity, while `_load()` replaces the product list with newly constructed objects. Existing cart entries continue to reference the old objects.

**Failure scenario:** Add a product, refresh the menu, and tap that product again. The card can show no existing quantity, and a second cart entry can reference the same database product. Existing prices and available quantities can also be stale.

**Recommended change:** Use product IDs as cart keys. Store a deliberate cart-line snapshot with quantity and displayed price. Refresh product availability by ID and flag changes that require cashier review. Aggregate each product into one RPC line before submitting.

**Acceptance criteria:** Add two units, refresh, then add one more. There is one cart line with quantity three. A changed price or insufficient stock is explained before confirmation.

## 3. P1 — Cash confirmation is not a persisted payment record

**Evidence:** [CheckoutSheet callback](D:/POS/hankatsu/lib/checkout_sheet.dart:6) passes only the customer name. `Repo.sale` sends only that name and cart lines.

Cash received and change are calculated in the sheet and discarded. The confirmation uses a locally calculated total, while the underlying server function may use current product prices. Its behavior is not available for inspection. After success, the cart closes without a returned sale ID or immediate receipt.

**Recommended change:** Have checkout return a structured result containing sale ID, human-readable receipt number, final line totals, final total, payment method, tendered amount, change, cashier, and timestamp. Persist monetary values using an agreed decimal or integer-minor-unit representation. Validate or reconfirm any price change before accepting payment. Show an “Order saved” screen with receipt and service-queue actions.

**Acceptance criteria:** Reopening the transaction reproduces the confirmed amounts and cashier. A price change between cart creation and payment cannot silently produce a different saved total.

## 4. P1 — Server permissions and stock deduction need a real audit

**Evidence:** [admin check in Orders](D:/POS/hankatsu/lib/orders_page.dart:8), [service RPC authorization](D:/POS/hankatsu/supabase/order_tracking.sql:55), and direct product writes in `main.dart`.

Orders has an explicit admin gate in both UI and SQL. Stock creation, stock editing, and Analytics are available in the common signed-in shell. The supplied SQL deliberately leaves existing product and sales access policies unchanged. This does **not** prove those policies are unsafe; it means their protection is unverified.

**Recommended change:** Define cashier, kitchen/service, and administrator capabilities. Match navigation to those permissions and enforce every write on the server. Bring the existing `complete_sale` function and schema into versioned migrations. Verify quantity validation, current prices, atomic stock deduction, transaction rollback, and protection against overselling.

Keep the publishable key usable in the client; moving it out of source is environment management, not a replacement for authorization.

**Acceptance criteria:** Test with separate accounts and direct API calls. Unauthorized stock edits fail. Two cashiers purchasing the last unit concurrently produce one successful sale. A failed sale leaves no partial line items or stock deductions.

## 5. P2 — Stock changes need a reason and movement history

**Evidence:** [stock adjustment](D:/POS/hankatsu/lib/main.dart:300).

The confirmation shows old and new quantities, and the update compares the existing stock value before writing. These are useful safeguards. However, the app only updates the product's current quantity; this path does not write an adjustment reason or movement record. Any independent database auditing remains unverified.

One confirmation per `+1` or `−1` also makes a delivery of 50 units unnecessarily slow.

**Recommended change:** Keep confirmation, but add “Adjust stock” with an amount, reason, and optional note. Support received stock, waste, correction, and stock count. Confirm the full change once. Save actor, before/after quantity, timestamp, and linked sale or adjustment ID atomically. Separate “Create product” from “Receive more stock for an existing product.”

**Acceptance criteria:** Receiving 50 units takes one confirmed adjustment. The administrator can explain every movement. A concurrent modification prompts refresh and review instead of a generic connection error.

## 6. P2 — Order handoff needs a clear operational model

**Evidence:** [Orders service flow](D:/POS/hankatsu/lib/orders_page.dart:76) and the pending-to-served transition in `order_tracking.sql`.

All new sales enter `pending`; the only next state is `served`. The whole order is served together. This works for a simple counter operation, but cannot distinguish a ticket nobody has started from food that is ready for pickup. Only administrators can operate the board, making them a potential service bottleneck.

**Recommended change:** First confirm the restaurant's workflow. For a kitchen queue, use queued → preparing → ready → served, with timestamps and authorized actors. Introduce partial item service only if staff actually need it. Keep payment status separate from preparation status. Give authorized kitchen/service staff access while retaining administrator oversight.

Use a visible order number, customer name, dine-in/takeaway type, and table or pickup reference. Show elapsed waiting time. A clipped database ID is less useful for calling a customer. Display a staff name alongside the stored actor ID.

**Acceptance criteria:** Staff can identify who receives an order and what action comes next without opening Analytics or asking the administrator to mark each order.

## 7. P2 — Mistakes need recorded correction paths

**Evidence:** The inspected UI and supplied service SQL provide no void, refund, cancellation, or served-status correction flow.

Confirmation reduces mistakes but does not eliminate them. A cashier can charge the wrong items, and an administrator can confirm service on the wrong ticket. The current service trigger permits only pending → served.

**Recommended change:** Add authorized correction actions with a reason and an audit event. Decide explicitly when each action returns stock; prepared food should not automatically reappear as sellable inventory. Preserve the original transaction and link corrections to it. Keep cancellations, refunds, and service corrections distinct.

**Acceptance criteria:** Correcting a sale does not delete its history. Reports distinguish original sales, reversals, and net totals. Every correction identifies its actor and reason.

## 8. P2 — Invoices need stable financial detail and clearer period summaries

**Evidence:** [invoice detail view](D:/POS/hankatsu/lib/analytics_page.dart:661) and the fixed VAT display in [cart review](D:/POS/hankatsu/lib/main.dart:877).

The invoice screen displays item names, quantities, and the overall total, but not saved unit prices, line amounts, tender, change, or cashier. Copying an invoice produces plain text; there is no printing or file export. The cart always shows a calculated 12% VAT amount, with no visible transaction tax configuration.

The existing weekly/monthly invoice views filter individual transactions by date. They do not produce a weekly/monthly summary document. This distinction should be clear in the interface.

**Recommended change:** Persist and display transaction snapshots: item description, quantity, unit price, discounts when supported, tax treatment, line total, payment details, and receipt number. Configure tax presentation from verified business settings; do not infer it from a hardcoded formula. Add print/export actions after the underlying records are complete. Provide a separate period summary with date range, transaction count, gross sales, recorded adjustments, and net total.

This review makes no determination about invoice or tax compliance.

**Acceptance criteria:** Changing a product's current price never changes an old invoice. A period summary reconciles to its transaction list, and archived records preserve their original amounts.

## 9. P2 — Pagination currently limits rendering, not data loading

**Evidence:** `PageSlice` in [list_controls.dart](D:/POS/hankatsu/lib/list_controls.dart), [AnalyticsService.fetch](D:/POS/hankatsu/lib/analytics_page.dart:61), and [list_service_orders](D:/POS/hankatsu/supabase/order_tracking.sql:67).

The UI displays ten records per page, but products and period invoices are first loaded through repeated batches. Analytics also loads each sale's line items. Orders retrieves all waiting orders and only the latest 100 served orders. A large month still costs a full download before its ten-row invoice page is shown.

Offset-based invoice loading can also repeat or skip records if new transactions arrive between requests. That matters because totals are calculated from the downloaded rows.

**Recommended change:** Fetch invoice pages on demand with server-side filters and a stable cursor using timestamp and ID. Compute summary totals separately in the database using a consistent cutoff. Preserve the ten-item UI. Clearly label the service board's recent-history limit and link to the complete archive. For the menu, a bounded product cache may remain appropriate if the catalog is small.

**Acceptance criteria:** Opening page one of 20,000 invoices does not download all invoice details. Paging during new sales produces no duplicate records, and displayed summary totals reconcile at the chosen cutoff.

## 10. P2 — Reporting should use the business's clock and payment states

**Evidence:** [SalesWindow](D:/POS/hankatsu/lib/analytics_page.dart:9) uses the device's local dates; Analytics sums all returned sales totals.

Two devices in different time zones can assign a transaction to different business days. There is no explicit shift, business-day cutoff, or payment-state breakdown in the visible reporting flow. “Completed transactions” currently describes sale records, which does not establish payment reconciliation or food service completion.

**Recommended change:** Configure the store's time zone and day cutoff. Label date ranges and distinguish paid, refunded, voided, and served states. Add shift opening, cash movements, and closing reconciliation if the app will manage a physical cash drawer.

**Acceptance criteria:** Two devices report the same business-day total. Weekly totals reconcile to the included days. Service completion never changes revenue by itself.

## 11. P3 — Preserve working context and provide actionable errors

**Evidence:** `Shell` builds only the selected page; `OrdersPage` and `AnalyticsPage` hold their filters locally. `_err()` maps different failures to the same connection message.

Leaving and returning to a page can reset its selected period or service filter. Polling runs on a fixed timer while the Orders widget exists, without an explicit application-lifecycle freshness indicator. A permission problem, missing migration, stock conflict, or network failure can be presented as the same issue.

**Recommended change:** Preserve important filters and scroll position across tab changes, with a clear reset action. Show last successful update time and stale data state. Pause unnecessary polling in the background and refresh on resume. Map known failures to specific recovery actions. Do not offer a blind retry for an uncertain payment result.

**Acceptance criteria:** Return from Menu to the same invoice month and page. A stock conflict says to refresh stock. A missing permission says to contact an administrator. A stale order board is visibly stale.

## 12. P3 — Forms and long lists still need realistic device checks

**Evidence:** [new-item form](D:/POS/hankatsu/lib/main.dart:904) and [cart sheet](D:/POS/hankatsu/lib/main.dart:814).

The item form silently rejects missing name/price, accepts values without explicit nonnegative/finite checks, and turns an invalid quantity into zero. The cart and item-entry sheets use columns rather than a fully scrollable layout. Long carts, an open keyboard, or larger text can exhaust the available height. A long press for removing a menu item is also hard to discover.

**Recommended change:** Show field-level errors; require a valid nonnegative quantity and an allowed finite price. Use scrollable, keyboard-aware sheets. Provide obvious quantity controls and make the cart count easy to find. Keep success toasts, but provide accessible announcements and inline feedback where a temporary message is insufficient. Dispose of form controllers after their sheet finishes closing.

**Acceptance criteria:** Test a 20-line cart, long product names, a small phone, landscape mode, and enlarged text. Required actions remain reachable. Invalid stock input cannot silently create a zero-stock product.

## Proposed end-to-end flow

1. **Sign in:** load role and store context; show only authorized operational actions.
2. **Build order:** identify customer/table, select items, and maintain one cart line per product ID.
3. **Review:** show quantities and authoritative prices; resolve unavailable stock or changed prices.
4. **Confirm payment:** show final total, method, cash received, and change; use one persistent checkout ID.
5. **Commit:** save sale, payment, stock movements, and order ticket atomically.
6. **Acknowledge:** show receipt/order number and a clear saved state; recover unknown results without another sale.
7. **Fulfill:** progress through the agreed preparation states and confirm service with actor and time.
8. **Reconcile:** review invoices and adjustments by store period; close the shift when applicable.

## Implementation sequence

### Release 1 — Transaction foundation

- Version the existing schema, checkout function, and policies.
- Fix cart identity and product refresh reconciliation.
- Add checkout IDs, authoritative return values, and payment snapshots.
- Add database tests for permissions, rollback, concurrent stock use, and retries.

### Release 2 — Staff operations

- Introduce stock movement records and batch adjustments with confirmation.
- Define kitchen/service permissions and the agreed order states.
- Add order identifiers, actionable errors, and correction workflows.

### Release 3 — Reports and refinement

- Add server-side invoice paging and reporting totals.
- Complete invoice details and store-time-zone reporting.
- Add export/print and period summaries.
- Preserve navigation state and finish accessibility/device checks.

## Test coverage needed before live rollout

The current test sources cover filter colors, basic pagination, confirmation choices, calendar boundaries, invoice navigation, and mocked order-service behavior. Those are useful, but they do not establish database correctness.

Add integration checks for:

- Retrying after a committed sale's response is lost.
- Two devices competing for the last product unit.
- Refreshing products while the cart contains those products.
- Price changes between adding an item and confirming payment.
- Unauthorized direct API calls for products, sales, and service transitions.
- A stale stock adjustment and a sale occurring concurrently.
- Returning to the correct invoice after a retry or restart.
- Paging while transactions are inserted, and reconciling period totals.
- Session expiry during payment and application resume after connectivity loss.
- Rendering long carts and item forms with the keyboard open.

## Final recommendation

The next milestone should be a sale that can be retried safely, traced through service, and reconciled afterward. Keep the existing visual improvements, but judge the next release by whether staff can recover from mistakes and interrupted requests without losing money, stock accuracy, or transaction history.
