# ADR-009: Testing via `ProviderContainer` + in-memory Drift, no widget-pump/`pumpAndSettle`, no golden or integration tests yet

## Status

Accepted.

## Context

Most of the app's UI is driven by Drift `.watch()` streams (reactive queries) feeding into
`fl_chart` widgets on the dashboard/reports screens. Standard Flutter widget testing
(`pumpAndSettle`) waits for the widget tree to become fully idle — but a live Drift stream
never truly "settles" (it stays subscribed indefinitely), and neither does `fl_chart`'s
internal animation/render loop in some configurations, so `pumpAndSettle` hangs
indefinitely on screens built this way.

## Decision

Test at the provider/repository level, not the widget-pump level, for anything backed by a
live stream. Standard pattern (`test/widget_test.dart` and most of the 29 test files):

```dart
db = AppDatabase.forTesting(NativeDatabase.memory());
container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
container.listen(currentMonthExpensesProvider, (_, _) {});   // keep the stream alive
...
await _waitUntil(container, monthTotalProvider, (m) => m == Money.fromMinor(10000));
```

`_waitUntil` (a local test helper) subscribes to a provider and completes on a predicate,
with a timeout — used instead of `pump`/`pumpAndSettle` to await Drift stream propagation
without hanging. The DI seam this relies on is the same one used throughout the app
(ADR-002): `databaseProvider.overrideWithValue`. A handful of true widget-pump tests exist
for genuinely static, non-stream-driven widgets (`amount_keypad_test.dart`,
`category_edit_strip_test.dart`, `chart_semantics_test.dart`, `avatar_test.dart`) — those are
fine to `pump` normally since nothing in them subscribes to a live stream.

`test/flutter_test_config.dart` sets `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`
globally, since backup import/export test scenarios intentionally open several independent
in-memory `AppDatabase` instances that never share a `QueryExecutor`.

No `integration_test/` directory and no golden-image tests exist yet.

## Alternatives Considered

- **`pumpAndSettle` everywhere, mocking out Drift streams to complete instead of stay open**
  — rejected: would mean testing against a fake stream-completion behavior the real app never
  exhibits, undermining confidence that the tests reflect real reactive behavior — exactly
  the class of bug (stale reads after a write) this app has actually shipped (see
  `docs/architecture.md` §8.1). Testing against the real Drift stream semantics, just without
  `pumpAndSettle`, is more faithful.
- **Mocking the repository layer instead of using a real in-memory Drift database** — rejected:
  the repositories' actual SQL query correctness (joins, aggregates for reports, budget math)
  is exactly what needs testing; mocking them out would remove that coverage entirely for the
  parts of the app most worth getting right.

## Consequences

- Tests reflect real Drift stream timing behavior, including the kind of staleness bug this
  codebase has actually hit — a meaningful advantage over mocking streams away.
- No widget-pump/golden coverage exists for the reactive screens (dashboard, reports) —
  visual regressions there would not be caught by the current suite.
- No `integration_test/` coverage exists — end-to-end flows (Quick Add → widget refresh →
  native reload, full backup/restore round-trip through the OS share sheet) are not verified
  automatically. This is an accepted gap for Sprint 12, not evaluated here as a mistake — but
  it's worth flagging as unstarted work ahead of the Sprint 8 (hardening) and Sprint 9 (store
  submission) phases noted in the README as not yet begun.
