# ADR-007: Imperative `Navigator` + `MaterialPageRoute`, no router package

## Status

Accepted.

## Context

Flutter apps commonly reach for a declarative router package (`go_router`, `auto_route`) for
URL-based routing, deep-link parsing, and typed route arguments. Spendly does have one
external-entry-point need (deep links from a home-screen widget tap and from a local
notification tap), but no need for shareable URLs, nested/tabbed route state restoration, or
web-style browser history.

## Decision

`MaterialApp` sets a single `home:` that branches on profile existence (`WelcomeScreen` vs
`HomeScreen`, `lib/app.dart`); all further navigation is `Navigator.push(MaterialPageRoute(...))`
called directly from within screens — no named routes, no route table. External entry points
(widget tap, notification tap) are handled by pushing through a module-level
`GlobalKey<NavigatorState> appNavigatorKey` (`lib/core/notify/notifications.dart`), set as
`MaterialApp.navigatorKey`, so code outside the widget tree (a stream listener in `app.dart`)
can still navigate.

## Alternatives Considered

- **`go_router`** — rejected: its main value (URL-syncable routes, declarative redirect
  logic, typed route parameters parsed from a URL) doesn't apply to an app with no web target
  and no need for routes to be externally addressable beyond the two deep-link cases already
  handled by `appNavigatorKey`. Would add a route-table abstraction layer for navigation
  patterns (`Navigator.push`, pop, and two external pushes) that are already simple to
  express imperatively.
- **`auto_route`** — rejected for the same reason, plus its codegen step is unjustified
  overhead for ~19 screens with no nested/shell routing needs.

## Consequences

- Navigation code is simple and local to each screen — no central route table to keep in
  sync with the screen list.
- The two external-entry-point cases (widget tap, notification tap) both funnel through the
  same `appNavigatorKey` pattern, keeping "navigate from outside the widget tree" to one
  documented mechanism rather than one-off hacks.
- If the app ever needs shareable/restorable deep-link URLs beyond the current
  `spendly://quickadd?category=<id>` case, or a web target, this decision should be
  revisited — neither is planned today.
