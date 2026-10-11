# Operational POS setup

## Required upgrade

The new app uses `pos_api` and requires `supabase/migrations/20260930_operational_pos.sql`. The older `order_tracking.sql` is archived for the previous app version; do not run it after this upgrade.

1. Close all old POS app instances. Keep a database backup and the previous app release.
2. Run `supabase/preflight.sql` in Supabase SQL Editor. Save the results, including the previous function definitions and grants. Resolve invalid quantities/prices before migration. The existing products table must have id, name, category, price, stock, active; sales must have id, total, created_at; sale_items must have sale_id, product_name, qty.
3. Run the complete `supabase/migrations/20260930_operational_pos.sql` file. It is one transaction: an error rolls it back. It preserves original sales tables, imports their history, and does not deduct stock for historical records. It revokes old client writes and the named legacy checkout/service RPCs, so old app versions must stay closed.
4. Assign staff roles using the SQL below. Existing admin app metadata is retained.
5. Sign out and sign in again, then rebuild/run the updated Flutter app.
6. Open a cash shift, make a small test sale, verify the receipt and stock movement, advance its service steps, and inspect invoices and shift totals.

```sql
-- Replace each address with the exact Authentication -> Users email.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"admin"}'::jsonb
where email = 'YOUR_ADMIN_EMAIL'
returning email, raw_app_meta_data;

-- Repeat for each cashier or kitchen account with the intended role.
-- Allowed values: admin, cashier, kitchen.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"cashier"}'::jsonb
where email = 'YOUR_CASHIER_EMAIL'
returning email, raw_app_meta_data;
```

Roles are checked against the current server-side user record on every request. An account with no assigned role is denied access. Cashiers can sell, manage their own shift, and read their own receipts/reports. Kitchen accounts can advance food service. Administrators can manage products, stock, corrections, store reports, and shift history.

## Business settings

The agreed default is `Asia/Manila`, midnight. The `pos_config` row holds the server reporting time zone and cutoff. Do not change it during an open trading day without a reporting reconciliation plan. Tax has not been configured; the app does not assume a VAT rate.

## Tables and old records

New sales are written to `pos_transactions` and `pos_lines`; the old `sales` table is retained as historical source data. Imported records have `LEGACY-` receipt references and retain unknown information as NULL. Original line prices are imported only when those columns exist. Do not edit old sales expecting the new ledger to change.

Inventory remains in `products`. Every new stock write goes through `pos_api`, which creates a movement record. Raw writes by logged-in clients are revoked. Database owners/service credentials still have administrative privileges and must not be used in the app.

## Recovery and corrections

If checkout's response is uncertain, use **Check / safely retry checkout**. The app persists the same checkout ID and payload before sending it. Do not clear app storage, uninstall the app, or manually recreate the sale while it is unresolved.

Refund/void records a full cash return in the administrator's open shift. Restock is a separate explicit checkbox. Legacy financial corrections are blocked because the original payment details are incomplete.

## Rollback

If migration itself fails, its transaction rolls back. After successful migration, do not simply reopen the old app or rerun old scripts: new transactions exist only in the new ledger. Stop trading, export/reconcile new ledger records, then restore privileges/schema using the saved backup and preflight definitions under a deliberate recovery plan. No automatic destructive rollback is provided.

## Validation commands

```powershell
flutter pub get
flutter analyze
flutter test
npm ci --ignore-scripts
npm test
flutter build web
```

Local tests cannot establish the state of your hosted project's policies, custom triggers, or unknown RPCs. Verify deployment in a staging copy first, including real two-device stock contention and a lost network response after payment commit.
