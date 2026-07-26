# ADR-001: Feature-first module structure, no data/domain/presentation layering

## Status

Accepted (in effect since the project's early sprints; documented retroactively here).

## Context

`lib/` needed to be organized somehow. Two broad options exist for a Flutter app of this
kind: layer-first (split top-level by technical concern — `data/`, `domain/`,
`presentation/` — with each feature's code spread across all three) or feature-first (split
top-level by domain area, with each feature owning its own screens, repository, and state
together).

Spendly is built and maintained by a single developer. There is no team boundary that a
layered split would protect, and every real change (add a field to an expense, add a screen)
touches one feature end-to-end rather than one layer across many features.

## Decision

Organize `lib/` by feature (`lib/features/expenses/`, `lib/features/budgets/`, etc.), each
folder holding its screens, a plain repository class, and its Riverpod providers — usually
co-located in the same 1-3 files. `lib/core/` holds only genuinely cross-cutting code (DB
setup, the `Money` type, notification wiring, theming, shared widgets) — no domain logic.

No `domain/` layer of use-case/interactor classes, no repository interfaces separate from
their implementations, no separate DTO/entity mapping — Drift rows are extended with domain
getters in place (`lib/core/db/row_extensions.dart`) rather than mapped to parallel models.

## Alternatives Considered

- **Layered architecture (data/domain/presentation)** — rejected. Adds indirection (interface
  + implementation for every repository, mapping layers between DB rows and domain entities)
  that would slow down a solo developer without buying anything a layer boundary is meant to
  buy: it doesn't enable a second team, doesn't support swapping the persistence
  implementation (there's exactly one, and no plan for a second), and doesn't materially
  improve testability here — the actual test seam that's used (`databaseProvider.overrideWithValue`,
  see ADR-009) works identically with or without a domain layer in between.
- **Clean Architecture / MVVM with explicit use-case classes** — rejected for the same reason:
  ceremony proportional to team size and to genuine multi-implementation needs, neither of
  which apply here.

## Consequences

- Fast to work in: a feature's entire vertical slice is usually 2-4 files.
- No architectural boundary preventing a screen from reaching straight into a repository, or
  a repository query shape leaking into a screen's expectations — acceptable at this scale,
  but is part of why the reactive-read-staleness bug class (see `docs/architecture.md` §8.1)
  recurred three times without a structural boundary catching it.
- If the app ever needs a second persistence backend, a second developer working the same
  feature simultaneously, or public plugin-style extension points, this decision should be
  revisited — none of those are true today.
