# ADR-002: Riverpod as the sole state management + dependency-composition mechanism

## Status

Accepted.

## Context

The app needs (a) reactive UI state driven by a local reactive database, and (b) some way to
wire repositories/services to the screens that use them, ideally swappably for tests. A
dedicated DI framework (`get_it`, `injectable`) and a state management library are two
traditionally separate concerns in Flutter apps; they don't have to be solved by the same
tool.

## Decision

Use `flutter_riverpod` for both. `ProviderScope` roots the app (`lib/main.dart`).
`Provider`/`StreamProvider`/`Provider.family`/`StreamProvider.family` expose repositories and
derived, reactive query results (backed by Drift's `.watch()` streams). `AsyncNotifier` is
used for stateful/persisted values (`ThemeModeNotifier`, profile state). The one manually
constructed service (`NotificationService`) is injected via a root-level `.overrideWithValue`
in `main.dart`, specifically to keep plugin/timezone initialization off the cold-start path.

No separate DI container exists. The provider graph *is* the composition root.

## Alternatives Considered

- **`get_it` (or similar service locator) + a separate state library (Bloc, plain
  `ChangeNotifier`)** — rejected. Would mean two different mental models (imperative service
  lookup vs. reactive provider graph) for what is, in this app, the same underlying need:
  give a screen access to a repository and rebuild when its data changes. Riverpod already
  does both without a second library.
- **Bloc** — rejected as more ceremony (events/states/mappers) than this app's actual
  complexity calls for; most screens are "watch a stream, render it," not multi-step state
  machines.
- **Provider (the older package) instead of Riverpod** — rejected: Riverpod is Provider's
  designed successor, compile-safe (no `BuildContext` lookups that can fail at runtime), and
  has first-class support for the exact override mechanism the test suite relies on (see
  ADR-009).

## Consequences

- One graph to reason about for both "where does this data come from" and "how do I swap it
  in a test" — the entire test seam is `ProviderContainer(overrides: [databaseProvider.overrideWithValue(...)])`.
- No compile-time enforcement that a screen only reaches into the providers it's "supposed
  to" — same trade-off as ADR-001's lack of layering; acceptable at solo-developer scale.
- If the app ever needs cross-cutting async orchestration heavier than "watch a stream and
  derive from it" (e.g. multi-step sagas, complex retry/backoff state machines), Riverpod's
  `AsyncNotifier` can express it, but a dedicated state-machine library would be worth
  reconsidering at that point — not needed today.
