# ADR-005: Widget bridge via `home_widget` + hand-mirrored shared-storage schema

## Status

Accepted, with a known and documented weak spot (see Consequences).

## Context

Home-screen widgets run in a separate OS process from the Flutter app (a WidgetKit extension
on iOS, a Glance `AppWidgetProvider` on Android) and cannot call into Dart/Flutter code
directly. Some channel is needed to hand data from the app to native widget code, and some
mechanism is needed to tell the OS to redraw the widget when that data changes.

## Decision

Use the `home_widget` package (`^0.9.3`) as the bridge. The Flutter side computes a flat
`Map<String, String>` snapshot (`buildWidgetSnapshot()`,
`lib/features/widgets/widget_snapshot.dart`) — all values pre-formatted (currency, dates) so
native code does no formatting math — and writes it via `HomeWidget.saveWidgetData` into an
App Group–shared `UserDefaults` suite on iOS (`group.com.spendly.spendly`) or shared
preferences on Android, then calls `HomeWidget.updateWidget` to trigger a redraw. Native code
independently declares the same key names and decodes the same JSON sub-payloads (`trend`,
`quickAdd`): `Decodable` structs in Swift, hand-written `JSONArray`/`getJSONObject` parsing in
Kotlin.

## Alternatives Considered

- **Platform channels with a custom binary/JSON protocol, hand-rolled without `home_widget`**
  — rejected: would solve the same problem `home_widget` already solves (App Group storage +
  timeline-reload triggering) with more code to maintain, for no capability this app needs
  that the package doesn't already provide.
- **A generated/shared schema (e.g. a JSON Schema or protobuf definition compiled to Dart,
  Swift, and Kotlin)** — considered as the "correct" long-term fix for the duplication this
  ADR accepts, but rejected *for now* as disproportionate tooling investment (three codegen
  targets, three build pipeline integrations) for a snapshot that's currently 6-8 flat keys.
  Explicitly flagged as the fix direction to revisit if the snapshot's shape grows
  significantly or duplication-caused bugs recur — see `docs/architecture.md` §8.2, §11
  risk #2, which instead recommends a cheaper interim safeguard (a drift-detection test, not
  full codegen).

## Consequences

- Fast to add a new widget field: one Dart key, one Swift field, one Kotlin field — no build
  step in between.
- No compiler or test currently enforces the three sides stay in sync — only source comments.
  This has already caused two shipped bugs: the `spendly://` URL scheme not being registered
  for iOS deep links, and the `home_widget`-required `homeWidget` tap marker missing from iOS
  `Link` URLs (see `docs/architecture.md` §6, §8.2 for commit references).
- Accepted at current scale; if the snapshot schema grows substantially or a third
  duplication-caused bug ships, revisit the codegen alternative above rather than adding a
  fourth hand-maintained key by convention.
