# Repository Guidelines

Flutter POS app (Hankatsu) backed by Supabase/Postgres. Business rules live in the database; the client is a thin, optimistic UI over guarded RPCs.

## Read First

Read `IMPLEMENTATION.md` before touching checkout, stock, roles, shifts, or reporting. It is the source of truth for business rules. If code and `IMPLEMENTATION.md` disagree, flag it instead of silently picking one.

## Project Structure

- `lib/`: Flutter client. `main.dart` holds bootstrapping and the app shell. Feature screens: `checkout_sheet.dart`, `analytics_page.dart`, `inventory_page.dart`, `orders_page.dart`.
- `supabase/migrations/`: all schema changes. Setup is in `supabase/SETUP.md`.
- `test/`: Flutter tests. `test/browser/`: browser tests.
- `database.test.mjs`: PGlite-backed migration and RPC tests (`npm test`).
- `assets/`: static resources.

## Commands

| Task                   | Command                                |
| ---------------------- | -------------------------------------- |
| Install deps           | `flutter pub get`                      |
| Run app                | `flutter run`                          |
| Static analysis        | `flutter analyze`                      |
| All Flutter tests      | `flutter test`                         |
| One test file          | `flutter test test/checkout_test.dart` |
| Web build              | `flutter build web --no-pub`           |
| DB migration/RPC tests | `npm test`                             |
| Format changed code    | `dart format lib test`                 |

Iterate with focused tests. Before finishing a substantial change, run `dart format`, `flutter analyze`, `flutter test`, and `npm test` if anything under `supabase/` changed.

## Architecture Rules

- **Money:** integer minor units everywhere. Format currency only at the UI/export boundary. Never use `double` for amounts.
- **Server-side only:** authorization, stock validation, and payment persistence. The client must never be the only guard.
- **Checkout:** must stay idempotent, with pending-request recovery intact. Retries must not double-charge or double-decrement stock.
- **Migrations:** add a new file in `supabase/migrations/`; never edit one that has already been applied. Include permission grants/RLS for any new table or RPC.

## Code Style

- Files `snake_case.dart`, types `PascalCase`, members `camelCase`.
- Keep widgets small and focused; extract when a build method gets hard to scan.
- Follow `flutter_lints`. Avoid `// ignore:` suppressions unless you add a one-line justification.
- Match surrounding patterns before introducing new ones, and don't add dependencies without asking.

## Testing

- Name tests as observable behavior, e.g. `Zero key works and checkout requires a customer`.
- Cover error, cancellation, and retry paths, not just success.
- Add `database.test.mjs` coverage for any change to migrations, RPCs, permissions, checkout, stock, or reporting.
- Changes to access, payments, refunds, inventory, or exports must test role boundaries and guarded RPC behavior.
- Fix the code, not the test, unless the test is wrong. Say so if you change an assertion.

## Boundaries

**Ask first:** new dependencies, schema changes that alter existing columns or data, changes to role/permission models, anything touching payment or refund flow semantics.

**Never:** commit keys, tokens, customer data, or hosted Supabase credentials; edit applied migrations; bypass server-side checks for convenience; run destructive commands against a hosted database.

## Commits & Pull Requests

- Concise imperative subjects: `Add PDF receipt export`, `Fix checkout keypad alignment`. One focused change per commit.
- PR descriptions include: user-visible behavior, database/config changes, linked issues, UI screenshots, validation commands run, and any remaining staging or device checks.

## Definition of Done

- Analyzer and relevant tests pass, and you report which commands you ran and their results. Don't claim success without running them.
- New behavior has tests, including failure paths.
- Docs (`IMPLEMENTATION.md`, `supabase/SETUP.md`) are updated if rules or setup steps changed.
- Anything you couldn't verify (device behavior, hosted Supabase) is stated explicitly.
