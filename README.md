# Hankatsu POS

Hankatsu is a Flutter point-of-sale application for a single-store cash operation. It supports role-based access, product and stock management, cash shifts, checkout recovery, kitchen service tracking, receipts, reports, and PDF/CSV exports.

## Features

- Cashier, kitchen, and administrator roles
- Product catalog, stock adjustments, and stock-movement history
- Cash checkout with change calculation and durable retry recovery
- Takeaway and dine-in orders with table references
- Kitchen workflow: queued, preparing, ready, and served
- Cash shift opening, cash movements, closing, and reconciliation
- Sales summaries, invoice archive, PDF receipts, PDF period summaries, and CSV invoice exports
- Local cart drafts that survive normal app restarts

## Technology

- Flutter and Dart client with Material 3
- Supabase PostgreSQL backend and guarded RPC actions
- PGlite database tests through Node.js

## Prerequisites

- Flutter SDK compatible with the version in `pubspec.yaml`
- Node.js and npm
- A Supabase project with the required schema and access to its SQL Editor

## Local Setup

```bash
flutter pub get
npm install
flutter run
```

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` through Dart environment variables. Provide them for a different Supabase project:

```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-key
```

Do not commit production credentials. Use a local `.env` or secret manager outside source control when scripting these commands.

## Database Setup

Follow [supabase/SETUP.md](supabase/SETUP.md) before using the application against a Supabase project. It covers preflight checks, migration, initial role assignment, and post-deployment verification.

The main migration is [supabase/migrations/20260930_operational_pos.sql](supabase/migrations/20260930_operational_pos.sql). Test it in a staging copy before applying it to a live store.

## Commands

```bash
flutter analyze
flutter test
npm test
flutter build web --no-pub
```

- `flutter analyze` checks Dart diagnostics and lint rules.
- `flutter test` runs Flutter widget and unit tests.
- `npm test` runs database migration and RPC behavior tests through PGlite.
- `flutter build web --no-pub` creates a production web build in `build/web/`.

Run a focused test during development when useful, for example:

```bash
flutter test test/checkout_test.dart
```

## Operational Notes

- Money is stored as integer minor units; format values only at the display or export boundary.
- A checkout request is saved before it is sent. If a response is lost, use the in-app check/retry flow instead of creating a second sale.
- Cart drafts are device-local. They do not survive storage clearing, device loss, or device migration.
- The current scope is one store, cash payments, full reversals, and whole-order fulfillment. Partial refunds, card payments, and multiple branches require additional workflows.

See [IMPLEMENTATION.md](IMPLEMENTATION.md) for architecture, data rules, known limits, and verification coverage. See [AGENTS.md](AGENTS.md) for contributor guidance.
