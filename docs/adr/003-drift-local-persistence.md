# ADR-003: Drift/SQLite for local persistence, no repository-interface abstraction over it

## Status

Accepted.

## Context

The app needs local, structured, queryable persistence for expenses/categories/budgets/tags/
settings, and — because the UI is reactive by default (ADR-002) — ideally persistence that
can emit a live stream of query results rather than requiring the app to manually invalidate
caches on every write.

## Decision

Use Drift (SQLite) as the only persistence mechanism (`lib/core/db/database.dart`), with one
`*Repository` class per feature holding a direct `AppDatabase` reference and writing Drift
query builder code inline — no DAO layer, no repository *interface* separate from its single
implementation. UI reads are Drift `.watch()` streams wired straight into
`StreamProvider`s (ADR-002); this is the app-wide default for "data that should stay current,"
not an exception.

## Alternatives Considered

- **`sqflite` + hand-written SQL** — rejected: no compile-time query safety, no generated
  reactive streams — would require hand-rolling the exact stream-invalidation logic Drift
  provides for free, which is also the exact mechanism most of the app's UI reactivity
  depends on.
- **`Isar` / `Hive` (NoSQL local stores)** — rejected: the data is genuinely relational
  (expenses reference categories and optionally tags; budgets reference categories; reports
  aggregate across expenses by category/date range) and benefits from SQL's join/aggregate
  expressiveness for report queries, which a document store would push into application code.
- **Repository *interfaces* with a single Drift-backed implementation** — rejected as
  premature: an interface earns its cost when there's a second implementation to swap to
  (a remote API, a mock). There isn't one, and the test suite's substitution point is the
  `AppDatabase` itself (`databaseProvider.overrideWithValue`, ADR-009), not the repository —
  so an interface layer here would add indirection without adding a real seam.

## Consequences

- Reactive-by-default UI is essentially free — most screens need no manual refresh logic.
- This is also the precondition for the reactive-read-staleness bug class documented in
  `docs/architecture.md` §8.1: because reactivity is pervasive and largely invisible, the one
  place it silently *doesn't* apply (a cached `Provider` wrapping a stream's last value) is
  easy to introduce by accident and has been, three times.
- Migrations are hand-written and manually versioned (`schemaVersion`, linear `onUpgrade`
  chain) with no automated schema-verification test — see `docs/architecture.md` §8.4 and
  §11 risk #4 for the gap and recommended fix.
- If Spendly ever needs a second persistence backend (unlikely given ADR-004's no-server
  stance), this decision — and the lack of a repository interface — should be revisited
  together, not the interface question alone.
