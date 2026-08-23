# Spendly — Product Requirements Document

**Version:** 2.1 · **Date:** July 26, 2026
**Product:** Cross-platform personal expense tracker (iOS + Android)
**Status:** Built — this document now reflects the implemented app, not just intent.

---

## 1. Purpose

A mobile app that lets a person log every expense in seconds, group spending by
category and by trip, see where money goes through visual reports, stay inside
per-month budgets, and get a clear summary automatically at the end of each month —
without opening the full app for routine entries, and with a full backup they own so
data is never truly lost.

---

## 2. Goals & Non-Goals

**Goals**
- Fastest possible expense entry (target: under 5 seconds from tap to saved)
- Zero manual math — the app categorizes, totals, and visualizes automatically
- Group spending two independent ways: by **category** and by **trip/tag**
- Per-month budgets, with the option to carry a month's setup forward
- A monthly report that arrives without being asked for; on-demand reports for any range
- Works fully offline; no account required
- Data is never truly lost — a user can always back up to their own cloud storage and
  fully recover after an uninstall, data wipe, or device change

**Non-goals (v1)**
- Bank account linking / auto-transaction import
- Multi-user or shared household budgets
- Investment or net-worth tracking
- Multi-currency (single currency, device-locale formatting — v2 candidate)
- Account-based cloud sync / a backend server (backup is share-sheet-only)

---

## 3. Target Platforms

| Platform | Shell | Widget technology |
|---|---|---|
| iOS 26+ (build target) | Flutter | WidgetKit (Home Screen + Lock Screen) |
| Android 10+ | Flutter | Glance App Widget |

**Stack (implemented):** Flutter single codebase; Riverpod state; Drift (SQLite) local
DB; `fl_chart` charts; `home_widget` bridge to per-platform native widgets (Swift/WidgetKit
on iOS, Kotlin/Glance on Android).

> **Note on iOS target:** the app is built against iOS deployment target **26.0** (an
> explicit product decision — see PROGRESS.md). The real technical floor is iOS 14
> (`home_widget`); the lock-screen widget is separately gated `@available(iOS 16.0, *)`.

---

## 4. User Roles

Single-user app. No login, no account. All data local by default.

---

## 5. Functional Requirements

### 5.1 Onboarding
| ID | Requirement |
|---|---|
| FR-44 | On first launch, user sees a Welcome screen before reaching the Home dashboard |
| FR-45 | User must provide a **name** to proceed (mandatory field) |
| FR-46 | User may optionally provide a **phone number** and/or **email address** |
| FR-47 | The "Get started" action stays disabled until the mandatory name field is filled |
| FR-48 | On completion, user is redirected directly to the Home dashboard — no further setup steps required before first use |
| FR-49 | Name, phone, and email (if provided) are stored locally and are included in the backup file (FR-33) so they're restored along with expense data |
| FR-50 | Onboarding only appears once, on first launch; it does not reappear on subsequent app opens unless local data is cleared or restored fresh. The gate is the presence of a saved name — no separate "onboarding complete" flag |

### 5.2 Add & Manage Expenses
| ID | Requirement |
|---|---|
| FR-1 | User can add an expense with: amount (required), category (required), date (defaults to today), note (optional), payment method (optional), trip/tag (optional) |
| FR-2 | User can add an expense from within the app in ≤3 taps |
| FR-3 | User can add an expense from a **Home Screen widget** in ≤2 taps (deep-links into a pre-filled Quick Add — see FR-27 note) |
| FR-4 | User can add an expense from a **Lock Screen widget** (iOS) where OS permits |
| FR-5 | Numeric keypad entry — a custom in-app keypad, no external/OS keyboard needed for the amount |
| FR-6 | User can edit or delete any past expense (tap to edit, swipe to delete with confirm) |
| FR-7 | User can mark an expense as recurring (daily/weekly/monthly); recurring items **remind + user confirms** on the due date via local notification — never silent auto-log |
| FR-59 | Quick Add lets the user backdate an expense up to 90 days; future dates are not allowed |
| FR-60 | Quick Add shows the top categories as a grid capped at 8, with a "More" tile opening a searchable full-category picker; last-used category is preselected |
| FR-61 | Quick Add's amount keypad collapses when the note field is focused, so the note is usable without leaving the screen |

### 5.3 Browse / All Transactions
| ID | Requirement |
|---|---|
| FR-62 | User can open a full transaction history, grouped by day (Today / Yesterday / date headers) |
| FR-63 | History supports month-by-month navigation (previous/next) and an on-demand custom date range |
| FR-64 | History supports a multi-select **category filter**, shown as removable chips with an active-count badge |
| FR-65 | History pages lazily (loads more on scroll) so large histories stay responsive |
| FR-66 | User can delete an expense directly from the history via swipe, with confirmation |

### 5.4 Categories
| ID | Requirement |
|---|---|
| FR-8 | App ships with **18 default categories**: Food, Travel, Shopping, Bills, Entertainment, Health, Home, Other, EMI/Loan, Online Shopping, Groceries, Fuel, Insurance, Subscriptions, Education, Personal Care, Fitness, Gifts & Donations |
| FR-9 | User can create, rename, recolor, and reorder (drag-and-drop) custom categories |
| FR-10 | User can set an icon per category from a curated emoji set (~50 icons) via a preview-strip + popup picker |
| FR-11 | User can archive (not delete) a category. A category still referenced by past expenses cannot be hard-deleted; the delete flow offers "Archive instead" |
| FR-67 | Category color is chosen from an 18-swatch brand palette **or** a custom hex color via a color-picker dialog; the picker flags a color already used by another category |
| FR-68 | Archived categories are viewable and manageable (unarchive / delete) on a dedicated Archived Categories screen |

### 5.5 Trips (Tags)
| ID | Requirement |
|---|---|
| FR-69 | User can create, rename, recolor, archive/unarchive, and delete a **trip** (tag) — a grouping of expenses orthogonal to category (e.g. "Goa trip", "Wedding") |
| FR-70 | An expense may be tagged with at most one trip; the trip is optional and set from Quick Add (trip chip) |
| FR-71 | User can view a per-trip report (total, category breakdown, spending trend, top expenses) and export it (CSV/PDF) |
| FR-72 | Deleting a trip untags its expenses but keeps the expenses themselves (never data loss) |
| FR-73 | Trips are reachable from the Reports screen (Trips icon) → Trips list → Trip detail; a Trip Manager screen handles create/edit/archive |

### 5.6 Dashboard / Home
| ID | Requirement |
|---|---|
| FR-12 | Home screen shows total spent in the current month (hero gradient card) |
| FR-13 | Home screen shows a category breakdown (donut chart with legend) |
| FR-14 | Home screen shows a trend chart (bars) across the last 6 months, current month accented |
| FR-15 | Home screen shows the most recent transactions with quick access to edit; "View all" opens the full history |
| FR-16 | Hero card shows a budget bar (% of the set monthly budget used, colored on-track/near-limit/over), or a "set budget" empty state |

### 5.7 Reports
| ID | Requirement |
|---|---|
| FR-17 | System auto-generates a report at the end of each calendar month (scheduled local notification, 1st of month) |
| FR-18 | User is notified when the monthly report is ready; tapping the notification opens the previous month's report |
| FR-19 | User can generate a report for any custom date range on demand (quick-range chips + custom picker) |
| FR-20 | Reports include: total spend, category breakdown, top 5 expenses, comparison vs. previous period (% change), daily average, transaction count, top category, budget-used % |
| FR-21 | User can export a report as PDF or Excel (.xlsx) (PDF bundles the app fonts so ₹ renders; Excel has a Summary sheet with totals/category/weekly breakdown as in-cell bar visuals, and a Transactions sheet with the full raw list) |
| FR-22 | User can share a report via the OS share sheet (email is a share target, not a backend) |

### 5.8 Budgets
| ID | Requirement |
|---|---|
| FR-23 | User can set an overall monthly budget |
| FR-24 | User can set a per-category budget |
| FR-25 | User is notified when a category (or the overall budget) crosses 80% and 100% of its budget, fired at expense-save time on a real crossing |
| FR-74 | Budgets are **per calendar month**; Budget Setup navigates month-by-month |
| FR-75 | An empty budget month can **carry forward** the previous month's budget setup in one tap |
| FR-76 | Budget Setup warns when the sum of per-category budgets exceeds the overall budget |
| FR-77 | User can mark a category as "ignored for budget" (for fixed costs like rent/EMI); ignored categories are excluded from daily totals, budget calculations, top categories, and top expenses, but still appear in All Transactions and exports. Toggle is per-category, reversible any time, and applies live to existing and future expenses |

### 5.9 Widgets
| ID | Requirement |
|---|---|
| FR-26 | Small widget: today's total spend + mini trend (iOS "Today's spend") |
| FR-27 | Small widget: quick-add with top 4 categories. Tapping a category deep-links into a pre-filled Quick Add (`spendly://quickadd?category=<id>`) rather than writing silently in-widget |
| FR-28 | Medium widget: month total + budget bar + quick-add row (iOS "This month"); Android uses one adaptive Glance widget covering the same content |
| FR-29 | Widgets refresh automatically after any new expense is added, from any source (Quick Add save, restore, app cold-start/resume) |

### 5.10 Data & Sync
| ID | Requirement |
|---|---|
| FR-30 | All data stored locally by default (offline-first, Drift/SQLite). Money is stored as integer minor units (paise), never float |
| FR-31 | *(Descoped for v1)* Account-based cloud sync is out of scope; backup is share-sheet-only (see 5.11) |
| FR-32 | Data export (Excel) available at any time via report export |

### 5.11 Backup, Export & Import
| ID | Requirement |
|---|---|
| FR-33 | User can export a full backup of all app data (expenses, categories, budgets, tags, settings, profile) as a single file |
| FR-34 | Backup file uses a structured, versioned, additive JSON format (see `docs/backup-schema.md`) so it can be safely read back by future versions. Current version: **3** |
| FR-35 | User can save the backup to a cloud location of their choice (iCloud Drive, Google Drive, device Files) via the OS share/save sheet |
| FR-36 | User can trigger a manual backup at any time; an optional password (AES-256-GCM + PBKDF2) can protect it |
| FR-37 | User can enable **automatic backup** on a schedule (daily/weekly/monthly, default weekly). The due-check runs on app launch/resume (no background service); auto-backups write a local file only and are never password-protected |
| FR-38 | User can import a backup file to restore data — onto a fresh install or a new device |
| FR-39 | Import shows a preview (backup date, number of expenses, date range covered, file size) before the user confirms |
| FR-40 | User chooses **Merge** (natural-key merge into existing data) or **Replace** (wipe current data, restore from backup) before import proceeds |
| FR-41 | App validates the backup file before import and shows a clear, typed error if it is corrupted, unreadable, from an incompatible future version, or password-protected/wrong-password — without altering existing data |
| FR-42 | App shows the timestamp and file size of the most recent successful backup, so the user knows their data is protected |
| FR-43 | Backup/restore works fully offline for local file export/import; only the "save to cloud" destination step uses the OS share sheet |

### 5.12 Profile
| ID | Requirement |
|---|---|
| FR-51 | User has a Profile screen showing their name, email, and avatar/photo, plus lifetime usage stats (months tracked, expenses logged, categories used) |
| FR-52 | User can edit their name, phone, and email at any time from Profile |
| FR-53 | User can set a profile picture by uploading a photo (camera or photo library) |
| FR-54 | User can instead choose a colored initials-avatar from a preset palette (5 gradients) |
| FR-55 | If no photo or avatar color has been chosen, the app shows a colored initials-avatar generated from the user's name — never a blank/broken image state |
| FR-56 | Profile picture (photo, base64) and avatar choice are included in the backup file (FR-33) and restored along with other profile data |
| FR-57 | Profile is the account/settings hub: it links to Edit Profile, Avatar Picker, Theme, Currency (read-only), and Backup & Restore |
| FR-58 | "Delete all data" is accessible from Profile, clearly marked destructive, and prompts the user to back up first, then requires typing "DELETE" to confirm |

---

## 6. Non-Functional Requirements

| Category | Requirement |
|---|---|
| Performance | App cold start under 2s (notification init deferred past first frame); widget tap-to-save fast path |
| Offline | Fully usable with no network connection; no account, no server |
| Privacy | No expense data leaves the device unless the user shares a backup/report themselves |
| Accessibility | Dynamic Type / font scaling (charts clamp internal scaling to 1.3×); VoiceOver / TalkBack labels and semantics on all controls and charts; color is never the only signal (checkmark badges on selected tiles, bold current-month bar, icon + label alongside color) |
| Theming | Full light and dark mode, following system setting by default with manual override; 400ms crossfade on theme change |
| Localization | Currency symbol and number formatting follow device locale, default ₹ INR; multi-currency is a v2 candidate |

---

## 7. Information Architecture

```
Welcome / Onboarding (first launch only — gated on saved name)
├── Name (mandatory)
├── Phone (optional)
├── Email (optional)
└── → redirects to Home

Home (Dashboard)
├── This month hero card + budget bar (→ Budget Setup)
├── Category donut chart
├── 6-month trend bars
├── Recent transactions (→ All Transactions)
├── FAB → Quick Add
└── Bottom nav: Home · Reports · [FAB] · Categories · Profile

Quick Add
├── Amount (custom keypad)
├── Category grid (top 8 + More picker)
├── Date chip (backdate ≤90d), Trip chip, Note field
└── Save

All Transactions
├── Day-grouped list, lazy paging
├── Month nav / custom range
└── Category filter (multi-select chips)

Reports
├── Monthly report (auto-generated) — hero, stat grid, donut, top-5, export
├── → Custom range report (chips + picker)
├── → Trips (Trips list → Trip detail report)
└── Export / Share (CSV / PDF)

Categories
├── Manage list (add/edit/reorder/archive, drag handles)
│   └── Category edit sheet: name, icon preview-strip+popup, color strip+popup (+ custom hex)
├── → Archived Categories (unarchive / delete)
└── → Budget Setup (wallet icon)

Budget Setup (per month, month nav)
├── Overall budget
├── Per-category budgets (usage bars, overrun warning, "Ignore in totals" toggle)
└── Carry forward from previous month

Trips
├── Trip Manager (create/rename/recolor/archive/delete)
├── Trips list (name, count, total)
└── Trip detail report (+ export)

Profile (account/settings hub)
├── Avatar / photo (upload or colored initials) → Avatar Picker
├── Name, phone, email → Edit Profile
├── Lifetime stats (months tracked, expenses, categories)
├── Preferences: Theme (system/light/dark), Currency (read-only ₹), → Backup & Restore
└── Delete all data (destructive — backup-first, then type "DELETE")

Backup & Restore
├── Last backup status (date, size, "Protected" chip)
├── Auto backup (toggle + Daily/Weekly/Monthly)
├── Back up now (optional password → share sheet)
└── → Restore (file picker → preview → Merge / Replace)

Widgets (iOS WidgetKit / Android Glance)
├── Today's spend (small)
├── Quick add (small, deep-link tap-to-add)
├── This month (medium: total + budget + quick-add)
└── Lock screen total (iOS 16+)
```

---

## 8. Screen List (see accompanying interactive prototype)

0. **Welcome / Onboarding** — name (mandatory), phone/email (optional), redirects to Home
1. **Home / Dashboard** — month hero + budget bar, donut, 6-mo trend, recent transactions
2. **Quick Add** — keypad, category grid + More picker, date/trip chips, note
3. **All Transactions** — day-grouped history, month nav, category filter
4. **Reports — Monthly** — auto-generated end-of-month summary
5. **Reports — Custom Range** — quick-range chips + date picker, weekly trend
6. **Category Manager** — list, drag-reorder, archived badge, add/edit
7. **Category Edit — Icon Picker popup** — preview strip + full emoji grid
8. **Category Edit — Color Picker popup** — 18 swatches + custom hex tile
9. **Archived Categories** — unarchive / delete
10. **Budget Setup** — per-month, overall + per-category usage bars, carry-forward, overrun warning, per-category "ignore for budget" toggle for fixed costs (rent/EMI)
11. **Trips list** — per-trip count + total
12. **Trip detail report** — hero, trend, donut, transactions, export
13. **Trip Manager / edit** — create/rename/recolor/archive/delete
14. **Home Screen Widgets** — small (today), small (quick-add), medium (combo)
15. **Lock Screen Widget** (iOS) — glanceable month total
16. **Backup & Restore** — status, auto-backup, save-to-cloud, restore entry
17. **Restore Flow** — file preview + Merge/Replace choice
18. **Profile** — avatar/photo, name/email, lifetime stats, settings hub
19. **Edit Profile** — update name, phone, email
20. **Avatar Picker** — upload a photo or choose a colored initials-avatar

---

## 9. Success Metrics

- % of expenses logged via widget vs. in-app (target: widget ≥50% after month 1)
- Median time from app/widget open to expense saved
- Monthly report open rate
- % of expenses tagged to a trip
- 30-day retention

---

## 10. Resolved Decisions (formerly open questions)

1. **Currency:** single currency; symbol + number format follow device locale, default ₹ INR. Multi-currency = v2.
2. **Cloud sync:** not in v1. Backup is share-sheet-save only — no account, no server, no auto-upload.
3. **Recurring expenses:** remind + user confirms on the due date; never silent auto-log.
4. **Export formats:** PDF and CSV.
5. **Cloud integration depth:** OS share/save sheet is sufficient; no direct cloud-account integration.
6. **Backup encryption:** optional per-backup password (AES-256-GCM + PBKDF2, 200k iterations) — user's choice, not mandatory.
7. **Auto-backup default frequency:** weekly (daily/monthly also selectable). Due-check runs on app launch/resume.

---

*Companion files: `spendly-prototype.html` — interactive, clickable screens for all items
in Section 8, in both light and dark themes. `../docs/backup-schema.md` — the versioned
backup file format. `../PROGRESS.md` — full sprint-by-sprint build log and locked decisions.*
