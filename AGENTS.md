# Repository Guidelines

## Project Structure & Module Organization

The Flutter client lives in `lib/`. `main.dart` contains app bootstrapping and the main shell; feature screens include `checkout_sheet.dart`, `analytics_page.dart`, `inventory_page.dart`, and `orders_page.dart`.

Database work is under `supabase/`; migrations belong in `supabase/migrations/`, and setup instructions are in `supabase/SETUP.md`. Flutter tests are in `test/`, browser tests in `test/browser/`, and static resources in `assets/`. Read `IMPLEMENTATION.md` before changing checkout, stock, roles, shifts, or reporting.

## Build, Test, and Development Commands

- `flutter pub get` installs Flutter dependencies.
- `flutter run` starts the application on a connected target.
- `flutter analyze` runs Dart static analysis and repository lints.
- `flutter test` runs the Flutter test suite.
- `flutter test test/checkout_test.dart` runs a focused checkout test.
- `flutter build web --no-pub` compiles the browser build.
- `npm test` runs the PGlite-backed database migration and RPC behavior tests.

Run focused tests while iterating, then the broader suite before a substantial change.

## Coding Style & Naming Conventions

Run `dart format lib test` for changed Dart files. The project uses `flutter_lints`; avoid analyzer suppressions unless justified.

Use `snake_case.dart` filenames, `PascalCase` types, and `camelCase` methods and fields. Keep widgets focused. Financial values remain integer minor units; format currency only at the UI/export boundary. Keep authorization, stock validation, and payment persistence server-side.

## Testing Guidelines

Use `flutter_test` for UI and state behavior. Name tests as observable behavior, for example: `Zero key works and checkout requires a customer`. Add `database.test.mjs` coverage for migrations, RPCs, permissions, checkout, stock, or reporting.

Test error, cancellation, and retry paths as well as success. Preserve checkout idempotency and pending-request recovery coverage.

## Commit & Pull Request Guidelines

This repository has no existing commits, so there is no established message convention. Use concise imperative subjects such as `Add PDF receipt export` or `Fix checkout keypad alignment`.

Keep each commit focused. Pull requests should explain user-visible behavior, list database/configuration changes, link issues when available, and include UI screenshots. State validation commands and remaining staging or device checks.

## Security & Configuration

Never commit keys, tokens, customer data, or hosted Supabase credentials. Follow `supabase/SETUP.md` for migrations. Test role boundaries and guarded RPC behavior whenever changing access, payments, refunds, inventory, or exports.
