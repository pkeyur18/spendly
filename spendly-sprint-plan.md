# Spendly — Build Kickoff Pack
**For use with:** Claude Code (Opus 4.8)
**Companion files:** `spendly-requirements.md` (PRD), `spendly-prototype.html` (interactive screens)

This document has two parts:
1. **The kickoff prompt** — paste this into Claude Code to start the project correctly
2. **The sprint plan** — the full roadmap from empty repo to production release, which the kickoff prompt tells Claude Code to follow

---

## Part 1 — The Kickoff Prompt

Copy everything in the box below into Claude Code as your first message. Put `spendly-requirements.md` and `spendly-prototype.html` in the project folder first so Claude Code can read them.

```
I'm building "Spendly," a cross-platform personal expense tracker (iOS + Android),
from scratch to a production app store release. I'm working with you across many
sessions, so treat this repo's documentation as our shared memory between sessions.

CONTEXT FILES (read both before doing anything else):
- spendly-requirements.md — full PRD with numbered functional requirements (FR-1
  to FR-43), non-functional requirements, and information architecture
- spendly-prototype.html — interactive HTML/CSS mockup of every screen, both
  light and dark theme. Treat this as the visual and UX source of truth: match
  its layout, spacing rhythm, color palette (indigo #6366F1 to pink #EC4899
  gradient), typography pairing (Sora for display/numbers, Inter for body), and
  card-based structure. Open it and study it before writing UI code.

STACK DECISION:
Flutter, for a single codebase across iOS and Android, using fl_chart for the
donut/bar/line charts, sqflite (or drift/isar) for local-first storage, and
home_widget + small native platform code for the iOS/Android widgets, since
neither OS lets Flutter code run inside the widget itself.

HOW WE'LL WORK:
Build this in the sprint order laid out in "spendly-sprint-plan.md" (in this
folder). Do not skip ahead to later-sprint features. At the start of every
session, read PROGRESS.md in the repo root to see what's done and what sprint
we're on. At the end of every session, update PROGRESS.md yourself: mark
completed items, note anything you deferred and why, and note the next task to
pick up. Treat PROGRESS.md as the thing that makes the next session (which
won't have this conversation's context) able to continue correctly.

Within each sprint:
1. Propose a short technical plan for that sprint's scope before writing code.
2. Build it.
3. Write tests for anything with logic (calculations, category rules, budget
   thresholds, backup/restore, date-range math) — this is a finance app, get
   the math right.
4. Tell me how to manually verify it in the simulator/emulator.
5. Only then move to the next sprint item.

GROUND RULES:
- Offline-first always. Every feature must work with no network connection
  except the "save backup to cloud" step (FR-31, FR-35, FR-43).
- Every screen needs a working light AND dark theme from the moment it's built,
  not retrofitted later.
- Currency, budgets, and totals are money — use a decimal-safe type, never
  float, for any arithmetic.
- Flag it to me immediately if you hit a requirement in the PRD that's
  ambiguous or that you think should change, rather than guessing silently.
- Ask before adding a dependency that isn't already agreed in the sprint plan.

Start with Sprint 0 now: confirm you've read both context files, propose the
project scaffold and folder structure, and set up PROGRESS.md.
```

---

## Part 2 — Sprint Plan (Sprint 0 → Production)

Save this as `spendly-sprint-plan.md` in your project root alongside the PRD — the kickoff prompt above points Claude Code at it by name.

Each sprint assumes roughly **1 focused week for a solo builder** working with Claude Code, but treat these as scope units, not calendar deadlines — a sprint is "done" when its exit criteria are met, not when a week passes.

---

### Sprint 0 — Project Setup
**Goal:** A blank app that runs on both platforms with the visual foundation in place.

- Flutter project scaffold, folder structure (feature-first: `lib/features/expenses`, `lib/features/reports`, etc.)
- Design tokens file: colors, gradients, spacing scale, type scale — translated from the HTML prototype into Flutter theme data
- Light + dark `ThemeData`, toggle wired to system setting with manual override
- Local database schema: expenses, categories, budgets, settings tables
- CI basics: lint on push, run tests on push
- `PROGRESS.md` created

**Exit criteria:** App builds and runs on an iOS simulator and an Android emulator, shows an empty themed home screen, and toggling system dark mode changes the app.

---

### Sprint 1 — Core Data Layer
**Goal:** Expenses and categories exist and persist, with no UI polish yet.

- Expense model + CRUD (FR-1, FR-6)
- Category model + CRUD, default category seed data (FR-8, FR-9, FR-10, FR-11)
- Decimal-safe money handling throughout
- Recurring expense data model (FR-7) — logic only, no reminder UI yet
- Unit tests: category totals, date filtering, recurring expense date math

**Exit criteria:** Can create/edit/delete an expense and a category through a debug screen or tests; data survives an app restart.

---

### Sprint 2 — Home Dashboard & Quick Add
**Goal:** The two highest-traffic screens, matching the prototype pixel-for-pixel in spirit.

- Home dashboard: month total, budget bar, donut chart, trend bar chart, recent transactions list (FR-12 to FR-16)
- Quick Add screen: numeric keypad, category grid, ≤3-tap save (FR-2, FR-5)
- Empty states (no expenses yet, no budget set)
- Wire Quick Add → Home so the dashboard updates immediately after saving

**Exit criteria:** You can use the app for real daily logging — add an expense from Home in under 3 taps and see it reflected in the charts immediately.

---

### Sprint 3 — Categories & Budgets
**Goal:** Full category management and budget tracking.

- Category Manager screen: add/edit/reorder/archive (FR-9, FR-11)
- Budget Setup screen: overall + per-category budgets (FR-23, FR-24)
- Budget threshold notifications at 80%/100% (FR-25) — local notifications, no backend needed
- Icon/color picker for categories (FR-10)

**Exit criteria:** Can fully manage categories and set budgets; crossing 80% of a category budget triggers a local notification.

---

### Sprint 4 — Reports
**Goal:** Both report types, exportable.

- Monthly auto-report generation logic (FR-17) — runs on month rollover
- Push notification when monthly report is ready (FR-18)
- Custom date-range report builder with quick-range chips (FR-19)
- Report contents: total, category breakdown, top 5, comparison vs. previous period, daily average (FR-20)
- PDF export (FR-21) and CSV export (FR-32)
- OS share sheet integration (FR-22)
- Unit tests: report math (comparisons, averages, top-N) across edge cases — empty month, single expense, month boundary

**Exit criteria:** Can generate a report for any custom range and for the current month, and export/share both as PDF and CSV, with numbers verified correct against manually-computed test data.

---

### Sprint 5 — Backup, Export & Import
**Goal:** The full data-safety net — this is FR-33 to FR-43, and the newest requirement, so give it a full sprint on its own rather than folding it into Sprint 4.

- Versioned JSON backup format definition (FR-34) — write this schema down in the repo, e.g. `docs/backup-schema.md`, since every future app version must stay able to read old backups
- Full backup export: expenses, categories, budgets, settings (FR-33)
- Save-to-cloud via OS share/save sheet — iCloud Drive, Google Drive, Files (FR-35)
- Manual "Back up now" (FR-36)
- Auto-backup scheduler with daily/weekly/monthly options (FR-37)
- "Last backup" status display: timestamp + file size (FR-42)
- Restore flow: file picker → preview (date, expense count, date range) → Merge/Replace choice → execute (FR-38, FR-39, FR-40)
- Backup file validation: corrupted file, future-incompatible version — both must fail safely without touching existing data (FR-41)
- Decision needed from Sprint 5 kickoff: resolve the encryption question (open question #6 in the PRD) before building the schema, since it affects the file format
- Unit tests: round-trip export→import produces identical data; Merge doesn't duplicate; Replace fully wipes first; corrupted-file import leaves existing data untouched

**Exit criteria:** Export a backup, uninstall the app, reinstall, restore from the backup file saved in cloud storage, and end up with identical data. This is the scenario the user explicitly asked for — test it literally, not just at the unit level.

---

### Sprint 6 — Widgets
**Goal:** Home Screen and Lock Screen widgets, the "shortcut" the whole project started from.

- iOS: WidgetKit small (today total), small (quick-add), medium (combo) — native Swift code (FR-26 to FR-28)
- Android: Glance widgets, same three variants
- iOS Lock Screen widget (FR-4)
- Widget → app data bridge (`home_widget` package) so widgets read the same local database
- Widget auto-refresh after any new expense, from any entry point (FR-29)
- Tap-to-add from widget writes directly to the database without opening the full app where the OS allows it

**Exit criteria:** Add an expense from a home screen widget without opening the app, and see it reflected in the dashboard next time the app is opened. This is the feature most likely to have platform-specific surprises — budget extra time here.

---

### Sprint 7 — Polish & Accessibility
**Goal:** Everything the PRD's Non-Functional Requirements section demands, which is easy to skip and expensive to retrofit.

- Dynamic Type / font scaling support
- VoiceOver (iOS) / TalkBack (Android) labels on every control
- Color-blind-safe: verify no information is conveyed by color alone (icons/labels alongside category colors)
- Cold start under 2s, widget tap-to-save under 1s — profile and fix regressions
- Currency/number formatting via device locale
- Empty states, error states, and loading states for every screen (not just the happy path)
- Animation pass: only where the prototype's motion was intentional, nothing gratuitous

**Exit criteria:** A full accessibility audit pass (VoiceOver navigation through every screen; Dynamic Type at largest setting doesn't break layout) and a performance profile showing cold start and widget-add both within target.

---

### Sprint 8 — Beta & Hardening
**Goal:** Real-world testing before the world sees it.

- TestFlight (iOS) and Internal Testing track (Android) builds
- Crash reporting + basic analytics (opt-in, respecting the privacy NFR — no expense content ever leaves the device)
- Bug bash against your own daily use — log real expenses for at least a week during this sprint
- Edge cases: expense in a currency-locale that changed mid-month, device date/time changes, backup restore across app versions, very large transaction counts (1000+) for chart/report performance
- Fix everything found

**Exit criteria:** No crashes in a week of real daily use; at least one other person has used the beta build and logged real expenses.

---

### Sprint 9 — Store Submission & Launch
**Goal:** Production release.

- App Store Connect + Google Play Console listings: screenshots (can reuse/adapt the prototype's screens), description, privacy policy (required given financial data — state clearly that data stays on-device unless the user backs up)
- App icon, splash screen
- Apple/Google privacy nutrition labels filled out accurately (this app touches financial data — be precise)
- Age rating, category selection
- Submit for review; handle any review feedback
- Post-launch: monitor crash reports and the success metrics from the PRD (Section 9: widget-add %, time-to-save, report open rate, 30-day retention)

**Exit criteria:** App is live on both the App Store and Google Play.

---

## How This Maps to the PRD

Every FR number from `spendly-requirements.md` is covered by exactly one sprint above, so nothing gets lost between planning and building:

| PRD Section | Sprint |
|---|---|
| 5.1 Add Expense | 1, 2 |
| 5.2 Categories | 1, 3 |
| 5.3 Dashboard | 2 |
| 5.4 Reports | 4 |
| 5.5 Budgets | 3 |
| 5.6 Widgets | 6 |
| 5.7 Data & Sync | 5 |
| 5.8 Backup, Export & Import | 5 |
| Section 6 (NFRs) | 7 (ongoing from Sprint 0) |

---

## Notes for Working With Claude Code Across Sessions

- **PROGRESS.md is the whole point.** Claude Code has no memory between sessions unless the repo carries it. Insist it's updated at the end of every session before you close the terminal.
- **Resolve the PRD's open questions before the sprint that needs them**, not mid-sprint: currency (before Sprint 1), cloud sync scope (before Sprint 5), backup encryption (before Sprint 5), recurring auto-log behavior (before Sprint 1).
- **Don't let Claude Code skip tests on the money math.** Sprints 1, 4, and 5 all involve arithmetic a user will notice if it's wrong — insist on the test step in the kickoff prompt's workflow rather than letting it get skipped under time pressure.
- **Sprint 5 and Sprint 6 are the ones most likely to run long.** Backup/restore correctness and native widget code are both areas where "looks done" and "is actually done" diverge. Budget slack around them rather than the earlier UI sprints.
