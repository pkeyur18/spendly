# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

A single individual, budget-disciplined saver actively trying to stay under monthly budgets and avoid overspending — not a passive expense logger. Tracks personal expenses in INR, wants fast entry (seconds, from app / Home Screen widget / iOS Lock Screen), and values that the app works fully offline with no account or server.

## Product Purpose

Spendly is a fast, offline-first personal expense tracker for iOS & Android. Log an expense in seconds, see where money goes through charts and reports, stay inside per-month budgets, group spending by trip, and own a full versioned backup so data is never truly lost. Success means the user can log and stay under budget with minimal friction, entirely offline.

## Positioning

Single Flutter codebase, no account, no server, no cloud sync (by design — see ADR-004). Money stored as integer minor units (paise), never float. Currency is INR (₹) with device-locale formatting. Backup/restore integrity (not sync consistency) is the correctness bar — see docs/architecture.md §1.2 and the ADR set in docs/adr/.

## Operating Context

- Quick Add: custom numeric keypad (no OS keyboard), top-8 category grid + "More" picker, last-used category preselected, backdate up to 90 days, optional note/trip/payment method.
- Dashboard: current-month hero card, budget bar, category donut, 6-month trend bars, recent transactions.
- All Transactions: grouped by day/month, custom date range, multi-select category filter, lazy paging, swipe-to-delete.
- Categories: 18 defaults, create/rename/recolor/reorder, icon + color pickers, archive (never hard-delete referenced categories).
- Budgets: per-month overall + per-category, carry-forward, over-allocation warning, 80%/100% threshold notifications, per-category "ignore in totals" toggle.
- Trips (tags): group expenses independent of category, per-trip report + CSV/PDF export.
- Reports: auto end-of-month report (scheduled local notification), on-demand custom-range reports, PDF/CSV export via OS share sheet.
- Monthly Recap: full-screen takeover shown once per new month on launch/resume.
- Widgets: iOS WidgetKit (Today, Quick Add, This Month, Lock Screen) + Android Glance; deep-link into pre-filled Quick Add.
- Backup & Restore: full versioned JSON backup, optional AES-256-GCM password protection, save-to-cloud via OS share sheet, auto-backup, Merge/Replace restore.
- Profile: name/email/phone, avatar, lifetime stats, theme, backup-gated "Delete all data".
- Onboarding: one-time name-gated welcome screen.

## Capabilities and Constraints

- Ships iOS + Android from one Flutter codebase, but renders a single unified custom design language across both OSes (Material-based widgets styled by `lib/core/theme/tokens.dart`) rather than per-OS Cupertino/Material divergence — no `Cupertino*` widgets in `lib/`. Native iOS/Android platform guidance should not be read as "adopt native OS chrome"; the brand's own tokens are the visual authority.
- No networking dependencies at all (no `http`, `dio`, `connectivity_plus`) — offline-first is met by construction.
- Widget refresh is push-based (`HomeWidget.updateWidget` → reload) with a periodic iOS safety-net timeline; both iOS WidgetKit and Android Glance impose OS-level refresh-frequency ceilings (unresolved tension, see ADR-006).
- No multi-device sync, live or otherwise (ADR-004); correctness bar is backup/restore fidelity, not sync consistency. Rows carry a stable `externalId` (UUID) for Merge-restore matching.
- Local DB: Drift (SQLite), schema v7. Money as integer minor units — never float (ADR-008).
- Several dependencies are deliberately pinned (`file_picker 10.3.10`, `share_plus ^12`) for Android toolchain reasons; iOS deployment target is 26.0 by explicit choice (real floor is iOS 14). See README "Tech stack" note and PROGRESS.md "Stack / tooling" before bumping.
- Beta/hardening (Sprint 8) and store submission (Sprint 9) are planned but not started — public app-store release is the eventual target.

## Brand Commitments

App name: Spendly. Fonts (bundled offline): Sora (display) + Inter (body). Brand palette: indigo → pink gradient (`#6366F1` → `#EC4899`), translated verbatim into `lib/core/theme/tokens.dart` from an existing clickable prototype at `docs/requirement_docs/spendly-prototype.html` (the design system's origin/visual authority — not documented as DESIGN.md yet).

## Evidence on Hand

- Full functional spec (FR-numbered): `docs/requirement_docs/spendly-requirements.md`.
- Clickable design prototype: `docs/requirement_docs/spendly-prototype.html`.
- Architecture doc (arc42): `docs/architecture.md`, with decision records in `docs/adr/001`–`009`.
- Sprint-by-sprint build log and locked decisions: `PROGRESS.md`.
- 190 passing tests across 37 test files (`test/`) as of README's last update.
- No testimonials, benchmarks, pricing, or third-party evidence exist — none should be fabricated; this is a pre-release single-developer project.

## Product Principles

1. Offline-first, no account, no server — never introduce a network dependency in the core read/write path.
2. Money is always integer minor units, never float; INR is the only supported currency today.
3. Fast entry beats completeness — Quick Add optimizes for seconds-to-log over exhaustive fields.
4. Never destroy user data silently: archive over delete, backup fidelity over sync convenience.
5. Design system already exists (tokens.dart, indigo→pink brand, Sora/Inter) — extend it, don't replace it, absent an explicit redesign request.

## Accessibility & Inclusion

Full light/dark theming (system default + manual override, 400ms crossfade), Dynamic Type support, VoiceOver/TalkBack labels including chart summaries, and color is never used as the only signal (per README).
