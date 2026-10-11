# AI Engineering Knowledge Base

## 1. Project Overview

- Project name: Hankatsu POS
- Purpose: A role-based point-of-sale application for cash sales, inventory, service orders, receipts, reporting, and cash-shift reconciliation.
- Target users: Cashiers, kitchen staff, and administrators.
- Current status: Operational POS implementation. No AI model or AI-powered feature is currently integrated.

## 2. Core Objectives

- Primary objective: Record cash sales safely while keeping stock, receipts, service status, and cash shifts consistent.
- Secondary objective: Give staff clear menu, order, inventory, sales-report, and export workflows.
- Expected outcome: Authorized staff can process and reconcile daily store activity with auditable records.

## 3. Technology Stack

- Language: Dart for the Flutter client; SQL/PLpgSQL for Supabase database routines; JavaScript for database tests.
- AI model: Not configured.
- Framework: Flutter with Material 3; Supabase Flutter client.
- Database: Supabase PostgreSQL; PGlite for embedded database tests.
- Infrastructure: Supabase backend with Flutter clients for web and native platforms.

## 4. System Architecture

The Flutter application presents role-specific screens and calls guarded Supabase RPC actions. PostgreSQL stores transactions, stock movements, service events, and cash-shift records. Server-side checks enforce roles, validate checkout payloads, lock products, and persist the sale atomically.

- Input layer: Flutter forms for authentication, menu selection, cart edits, cash received, service status, reports, and exports.
- Processing layer: Dart cart state, draft persistence, validation, error handling, and export generation.
- AI inference layer: Not applicable until an approved AI feature and model are selected.
- Data storage: Supabase PostgreSQL tables for products, transactions, lines, events, stock movements, shifts, and cash events; local device preferences for recoverable cart drafts.
- Output layer: Receipt views, PDF/CSV exports, reports, order status, and user notifications.

Reference: [IMPLEMENTATION.md](IMPLEMENTATION.md) and [supabase/SETUP.md](supabase/SETUP.md)

## 5. Knowledge and Data Sources

| Source name | Location | Purpose | Last verified | Reliability or limitations |
| --- | --- | --- | --- | --- |
| Operational implementation | `IMPLEMENTATION.md` | Defines POS behavior, data model, limits, and verification scope. | 2026-10-11 | Local documentation; confirm hosted deployment details in staging. |
| Database setup | `supabase/SETUP.md` | Migration, roles, setup, and post-deployment checks. | 2026-10-11 | Does not replace verification against the hosted schema and policies. |
| Database migration | `supabase/migrations/20260930_operational_pos.sql` | Authoritative schema and guarded RPC implementation. | 2026-10-11 | Review before modifying live data or permissions. |
| Flutter source | `lib/` | Client behavior and user-interface implementation. | 2026-10-11 | Must be checked alongside server authorization rules. |

## 6. AI Behavior and Constraints

There is no deployed AI system in this project. If one is added, it must:

- Follow the project's functional, security, and role requirements.
- Distinguish verified database or documentation facts from assumptions.
- Never invent APIs, configuration values, sales data, prices, stock, payment status, or test results.
- Ask for clarification when a critical requirement is missing.
- Protect secrets, credentials, customer data, staff data, and payment information.
- Use only approved data sources, models, and server-side tools.
- Treat model output as untrusted input; validate it before display, storage, or action.
- Never authorize sales, refunds, stock changes, or role changes without the existing server-side checks and an appropriate user confirmation.

## 7. Engineering Standards

- Follow existing Dart, Flutter, SQL, and test conventions in the repository.
- Use clear names, focused components, and types appropriate to the language.
- Keep business rules on the server when they affect permissions, money, stock, or audit records.
- Validate inputs and surface actionable errors.
- Use integer minor currency units for financial calculations.
- Document important architectural decisions and changes to data contracts.
- Never commit API keys, passwords, tokens, or customer data.
- Preserve safe checkout retries and idempotency behavior when modifying payment flows.

## 8. Development Workflow

1. Understand the task and inspect the relevant client, server, and documentation files.
2. Review applicable setup and implementation documentation.
3. Propose the smallest change that satisfies the requirement.
4. Implement the change with authorization and data integrity in mind.
5. Run relevant Flutter, database, analysis, and build checks.
6. Review security, correctness, performance, and recovery behavior.
7. Update documentation when behavior, architecture, dependencies, or operational instructions change.

## 9. Testing and Evaluation

- Unit tests: Flutter widget and unit tests under `test/`.
- Integration tests: Database migration and behavior tests through `npm test`.
- AI quality evaluation: Not applicable until AI functionality exists; define task-specific datasets and acceptance criteria before release.
- Hallucination checks: Required for any future AI feature that presents facts, proposes actions, or uses store data.
- Security tests: Verify roles, permissions, RPC protections, input validation, and tenant/data boundaries.
- Performance benchmarks: Check checkout, catalog, reporting, export, and multi-device behavior in staging.

Define measurable acceptance criteria for each major feature. For payment changes, include stock locking, request retry behavior, total accuracy, receipt details, and recovery after a lost response.

## 10. Architecture Decisions

| Decision | Context | Alternatives considered | Reason | Consequences |
| --- | --- | --- | --- | --- |
| Server-guarded checkout RPC | Sales affect money, stock, and audit records. | Client-side writes; multiple endpoint calls. | Keeps validation, locks, and persistence atomic. | Client must use the approved RPC and recover safely from failed responses. |
| Integer minor currency units | Financial values require exact arithmetic. | Floating-point currency values. | Avoids rounding errors. | UI converts values only for display. |
| Persisted checkout request ID | Network loss can occur after the server commits a sale. | Retrying a new request. | Enables safe lookup and retry. | Pending requests must not be discarded until resolved. |
| Local cart drafts | Cashiers need recovery after ordinary app restarts. | Server-side offline queue. | Simpler recovery for active devices. | Drafts do not survive storage clearing, device loss, or migration. |
| PDF receipts and CSV invoice exports | Staff need printable records and spreadsheet data. | HTML-only export. | PDF preserves receipt layout; CSV supports analysis. | Export behavior must be tested on target devices and browsers. |

## 11. Known Issues and Limitations

- No AI model, AI data pipeline, or AI evaluation suite is currently configured.
- The system supports one store, cash payments, full-order fulfillment, and full reversals.
- Partial refunds, card payments, multiple branches, and partial service need separate workflow design.
- Tax treatment is not configured and must not be inferred.
- Local drafts are not a server-side offline payment queue.
- Staging still needs real multi-device stock contention and lost-response-after-commit testing.
- Browser export location behavior depends on browser support and user download settings.

## 12. Current Priorities

- Highest-priority task: Validate the POS migration and checkout workflows in a staging Supabase environment.
- Next task: Test real-device export behavior, including PDF save locations and CSV exports.
- Future improvement: Define requirements, data boundaries, model selection, evaluation criteria, and human-review rules before adding any AI feature.

## 13. Related Documentation

- Setup: [README.md](README.md) and [supabase/SETUP.md](supabase/SETUP.md)
- Architecture and implementation: [IMPLEMENTATION.md](IMPLEMENTATION.md)
- Database migration: [supabase/migrations/20260930_operational_pos.sql](supabase/migrations/20260930_operational_pos.sql)
- Testing: `test/`, `database.test.mjs`, and `npm test`
- Security: Supabase roles, SQL migration grants, and guarded RPC definitions

## 14. Maintenance

- Last updated: 2026-10-11
- Maintainer: Project engineering team
- Review when architecture, dependencies, database schema, AI models, APIs, export behavior, or project requirements change.
