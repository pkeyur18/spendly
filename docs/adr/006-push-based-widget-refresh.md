# ADR-006: Push-based widget refresh via explicit per-call-site `refreshWidgets()`

## Status

Accepted, with an acknowledged unresolved tension (see Consequences).

## Context

Widgets need to reflect current totals reasonably promptly after the user changes data, but
also shouldn't be redrawn wastefully. Two broad strategies exist: have the app explicitly
push a "reload now" signal to the OS every time relevant data changes, or have the widget
poll/refresh on a fixed timer regardless of whether anything changed.

## Decision

Push-based: `refreshWidgets(ref)` (`lib/features/widgets/widget_refresh.dart`) is called
explicitly from every screen/flow that mutates totals-affecting data — 7 call sites today
(`app.dart` cold start and resume, `quick_add_screen.dart` after save, `restore_screen.dart`
after restore, and 5 sites in `budget_setup_screen.dart`). Each call recomputes the snapshot
from fresh one-shot reads and calls `HomeWidget.updateWidget`, which on iOS maps to
`WidgetCenter.reloadTimelines(ofKind:)`. iOS additionally schedules a periodic timeline entry
roughly every hour purely as a safety net for missed pushes, not as the primary refresh
mechanism (`SpendlyWidget.swift`, `Provider.getTimeline`).

## Alternatives Considered

- **Pure timer/polling refresh (e.g. every 15-30 minutes, no explicit push)** — rejected:
  would make the common case (open the app, log an expense, glance at the home screen) show
  stale data for up to the polling interval, which defeats the point of a glanceable widget.
- **Push-only, no periodic safety net** — rejected: if a push is ever missed (a crash between
  write and refresh call, an OS-throttled reload that silently drops) the widget could go
  stale indefinitely with no self-correction. The hourly iOS timeline entry exists specifically
  to bound that.

## Consequences

- Freshness is good in the common case and the pattern is simple to reason about per call
  site.
- **Two real costs, both open**, not resolved by this decision:
  1. There is no centralized "on any total-affecting write, refresh" hook — every mutating
     screen must remember to call `refreshWidgets(ref)` itself. This has already been missed
     once (budget-setup edits shipped without it, fixed retroactively in `b45de67`). See
     `docs/architecture.md` §8.3, §11 risk #3 for the recommended fix direction (a
     repository-level notifier) if a fourth miss occurs.
  2. iOS's `reloadTimelines` calls are subject to an OS-managed budget that this app does not
     currently account for — under rapid successive writes (e.g. several Quick Adds in a
     row), some pushes may be silently dropped by the OS, and the 1-hour safety net is a
     coarse fallback, not a real answer. This is stated as an open tension in
     `docs/architecture.md` §1.2 #2, not something this ADR claims to have solved.
