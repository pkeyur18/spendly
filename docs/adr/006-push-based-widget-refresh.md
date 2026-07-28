# ADR-006: Push-based widget refresh via a centralized Drift `tableUpdates()` hook

## Status

Accepted, with one acknowledged unresolved tension (see Consequences) — the OS reload-budget
point. The centralized-hook question this ADR originally left open has since been resolved
(see Decision).

## Context

Widgets need to reflect current totals reasonably promptly after the user changes data, but
also shouldn't be redrawn wastefully. Two broad strategies exist: have the app explicitly
push a "reload now" signal to the OS every time relevant data changes, or have the widget
poll/refresh on a fixed timer regardless of whether anything changed.

## Decision

Push-based, via a single centralized hook rather than per-call-site discipline.
`widgetRefreshHookProvider` (`lib/features/widgets/widget_refresh.dart`) subscribes once to
Drift's own `AppDatabase.tableUpdates()` stream, scoped to the `expenses`/`categories`/
`budgets` tables and debounced 250ms so a burst of rapid writes collapses into a single
push. Any write to those tables — through any repository, from any screen — triggers
`refreshWidgets(ref)` automatically; no mutating screen needs to remember to call it. The
only two remaining explicit calls are cold-start and app-resume, routed through
`refreshWidgetsActionProvider`. Each refresh recomputes the snapshot from fresh one-shot
reads and calls `HomeWidget.updateWidget`, which on iOS maps to
`WidgetCenter.reloadTimelines(ofKind:)`. iOS additionally schedules a periodic timeline entry
roughly every hour purely as a safety net for missed pushes, not as the primary refresh
mechanism (`SpendlyWidget.swift`, `Provider.getTimeline`).

This supersedes the ADR's original decision (a manual `refreshWidgets(ref)` call at every
mutating call site — 10 at peak, plus at least 8 further mutations that shipped with no
refresh call at all). That approach caused a real miss (`b45de67`, budget-setup edits
shipped without a refresh call) and was replaced by the table-hook design above; see
`docs/known-issues.md` push-back #3 for the full incident history.

## Alternatives Considered

- **Pure timer/polling refresh (e.g. every 15-30 minutes, no explicit push)** — rejected:
  would make the common case (open the app, log an expense, glance at the home screen) show
  stale data for up to the polling interval, which defeats the point of a glanceable widget.
- **Push-only, no periodic safety net** — rejected: if a push is ever missed (a crash between
  write and refresh call, an OS-throttled reload that silently drops) the widget could go
  stale indefinitely with no self-correction. The hourly iOS timeline entry exists specifically
  to bound that.

## Consequences

- Freshness is good in the common case, and the table-hook design removes the per-call-site
  discipline burden entirely — a write can't ship without triggering a refresh, since the
  hook lives beneath the repository layer, not inside each screen.
- **One real cost remains open**, not resolved by this decision:
  1. iOS's `reloadTimelines` calls are subject to an OS-managed budget that this app does not
     currently account for — under rapid successive writes (e.g. several Quick Adds in a
     row), some pushes may be silently dropped by the OS, and the 1-hour safety net is a
     coarse fallback, not a real answer. This is stated as an open tension in
     `docs/architecture.md` §1.2 #2, not something this ADR claims to have solved.
