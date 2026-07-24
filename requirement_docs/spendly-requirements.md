# Spendly — Product Requirements Document

**Version:** 1.3 · **Date:** July 22, 2026
**Product:** Cross-platform personal expense tracker (iOS + Android)

---

## 1. Purpose

A mobile app that lets a person log every expense in seconds, see where money goes through visual reports, and get a clear summary automatically at the end of each month — without opening the full app for routine entries.

---

## 2. Goals & Non-Goals

**Goals**
- Fastest possible expense entry (target: under 5 seconds from tap to saved)
- Zero manual math — the app categorizes, totals, and visualizes automatically
- A monthly report that arrives without being asked for
- On-demand reports for any custom date range
- Works fully offline; syncs when online
- Data is never truly lost — a user can always back up to their own cloud storage and fully recover after an uninstall, data wipe, or device change

**Non-goals (v1)**
- Bank account linking / auto-transaction import
- Multi-user or shared household budgets
- Investment or net-worth tracking

---

## 3. Target Platforms

| Platform | Native shell | Widget technology |
|---|---|---|
| iOS 16+ | Swift/SwiftUI shell (if native) or Flutter | WidgetKit (Home Screen + Lock Screen) |
| Android 10+ | Kotlin shell (if native) or Flutter | Glance App Widget |

**Recommended stack:** Flutter for the main app (single codebase, strong charting via `fl_chart`), with small native modules per platform for widgets, since neither OS allows widgets to run cross-platform code directly.

---

## 4. User Roles

Single-user app. No login required for local-only use; optional account for cloud backup/sync.

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
| FR-50 | Onboarding only appears once, on first launch; it does not reappear on subsequent app opens unless local data is cleared or restored fresh |

### 5.2 Add Expense
| ID | Requirement |
|---|---|
| FR-1 | User can add an expense with: amount (required), category (required), date (defaults to today), note (optional), payment method (optional) |
| FR-2 | User can add an expense from within the app in ≤3 taps |
| FR-3 | User can add an expense from a **Home Screen widget** in ≤2 taps |
| FR-4 | User can add an expense from a **Lock Screen widget** (iOS) without unlocking, where OS permits |
| FR-5 | Numeric keypad entry — no external keyboard needed for amount |
| FR-6 | User can edit or delete any past expense |
| FR-7 | User can mark an expense as recurring (daily/weekly/monthly) |

### 5.3 Categories
| ID | Requirement |
|---|---|
| FR-8 | App ships with default categories (Food, Travel, Shopping, Bills, Entertainment, Health, Home, Other) |
| FR-9 | User can create, rename, recolor, and reorder custom categories |
| FR-10 | User can set an icon per category from an icon set |
| FR-11 | User can archive (not delete) a category still referenced by past expenses |

### 5.4 Dashboard / Home
| ID | Requirement |
|---|---|
| FR-12 | Home screen shows total spent in the current month |
| FR-13 | Home screen shows a category breakdown (donut/pie chart) |
| FR-14 | Home screen shows a trend chart (bar or line) across recent months |
| FR-15 | Home screen shows the most recent transactions with quick access to edit |
| FR-16 | Optional budget bar shows % of a set monthly budget used |

### 5.5 Reports
| ID | Requirement |
|---|---|
| FR-17 | System auto-generates a report at the end of each calendar month |
| FR-18 | User is notified (push notification) when the monthly report is ready |
| FR-19 | User can generate a report for any custom date range on demand |
| FR-20 | Reports include: total spend, category breakdown, top 5 expenses, comparison vs. previous period, daily average |
| FR-21 | User can export a report as PDF or CSV |
| FR-22 | User can share a report via the OS share sheet |

### 5.6 Budgets (v1 lightweight)
| ID | Requirement |
|---|---|
| FR-23 | User can set an overall monthly budget |
| FR-24 | User can set a per-category budget |
| FR-25 | User is notified when a category crosses 80% and 100% of its budget |

### 5.7 Widgets
| ID | Requirement |
|---|---|
| FR-26 | Small widget: today's total spend + mini trend |
| FR-27 | Small widget: quick-add with top 4 categories |
| FR-28 | Medium widget: month total + budget bar + quick-add row |
| FR-29 | Widgets refresh automatically after any new expense is added, from any source |

### 5.8 Data & Sync
| ID | Requirement |
|---|---|
| FR-30 | All data stored locally by default (offline-first) |
| FR-31 | Optional cloud backup/sync tied to an account |
| FR-32 | Data export (CSV) available at any time from Settings |

### 5.9 Backup, Export & Import
| ID | Requirement |
|---|---|
| FR-33 | User can export a full backup of all app data (expenses, categories, budgets, settings) as a single file |
| FR-34 | Backup file uses a structured, versioned format (JSON) so it can be safely read back by the app in future versions |
| FR-35 | User can save the backup file to a cloud location of their choice (iCloud Drive, Google Drive, or device Files/Downloads) via the OS share/save sheet |
| FR-36 | User can trigger a manual backup at any time from Settings |
| FR-37 | User can enable **automatic backup**, which creates a fresh backup file on a schedule (e.g. daily/weekly) without manual action |
| FR-38 | User can import a backup file to restore data — either onto a fresh install (after uninstall/reinstall) or a new device |
| FR-39 | Import shows a preview (date of backup, number of expenses, date range covered) before the user confirms |
| FR-40 | User chooses **Merge** (add backup data to what's already on the device) or **Replace** (wipe current data, restore only from backup) before import proceeds |
| FR-41 | App validates the backup file before import and shows a clear error if the file is corrupted, unreadable, or from an incompatible future version, without altering existing data |
| FR-42 | App shows the timestamp and file size of the most recent successful backup in Settings, so the user knows their data is protected |
| FR-43 | Backup/restore works fully offline for local file export/import; only the "save to cloud" destination step requires network access |

### 5.10 Profile
| ID | Requirement |
|---|---|
| FR-51 | User has a Profile screen showing their name, email, and avatar/photo, plus lifetime usage stats (months tracked, expenses logged, categories used) |
| FR-52 | User can edit their name, phone, and email at any time from Profile |
| FR-53 | User can set a profile picture by uploading a photo (camera or photo library) |
| FR-54 | User can instead choose a colored initials-avatar from a preset palette, if they don't want to upload a photo |
| FR-55 | If no photo or avatar color has been chosen, the app shows a colored initials-avatar by default, generated from the user's name — never a blank/broken image state |
| FR-56 | Profile picture (photo or chosen avatar color) is included in the backup file (FR-33) and restored along with other profile data (FR-49) |
| FR-57 | Profile screen links directly to Backup & Restore and Theme/Currency settings, since these are all part of the same account-level settings cluster |
| FR-58 | "Delete all data" is accessible from Profile, clearly marked as destructive, and prompts the user to back up first before proceeding |

---

## 6. Non-Functional Requirements

| Category | Requirement |
|---|---|
| Performance | App cold start under 2s; widget tap-to-save under 1s |
| Offline | Fully usable with no network connection |
| Privacy | No expense data leaves the device unless cloud sync is explicitly enabled |
| Accessibility | Dynamic Type / font scaling support; VoiceOver / TalkBack labels on all controls; color is never the only signal (icons + labels alongside category colors) |
| Theming | Full light and dark mode, following system setting by default with manual override |
| Localization | Currency symbol and number formatting follow device locale; multi-currency is a v2 candidate |

---

## 7. Information Architecture

```
Welcome / Onboarding (first launch only)
├── Name (mandatory)
├── Phone (optional)
├── Email (optional)
└── → redirects to Home

Home (Dashboard)
├── This month summary + budget bar
├── Category chart
├── Trend chart
├── Recent transactions
└── FAB → Quick Add

Reports
├── Monthly report (auto-generated, latest first)
├── Custom range report builder
└── Export / Share

Categories
├── Manage list (add/edit/reorder/archive)
└── Per-category budget

Profile
├── Avatar / photo (upload or colored initials)
├── Name, phone, email (editable)
├── Lifetime stats (months tracked, expenses, categories)
├── → Backup & Restore
├── → Theme & Currency
└── Delete all data (destructive, prompts backup first)

Settings
├── Monthly budget
├── Notifications
├── Theme (light/dark/system)
├── Currency & locale
├── Backup & Restore
│   ├── Back up now (save to iCloud/Drive/Files)
│   ├── Auto backup schedule (off/daily/weekly)
│   ├── Last backup status (date, size)
│   └── Restore from backup file (Merge / Replace)
└── Widget setup help
```

---

## 8. Screen List (see accompanying interactive prototype)

0. **Welcome / Onboarding** — name (mandatory), phone and email (optional), redirects to Home on completion
1. **Home / Dashboard** — month total, donut chart, trend bars, recent transactions
2. **Quick Add** — keypad + category grid, in-app fast entry
3. **Reports — Monthly** — auto-generated end-of-month summary
4. **Reports — Custom Range** — date picker + on-demand report generation
5. **Category Manager** — list, add/edit, budget per category
6. **Budget Setup** — overall + per-category budget sliders
7. **Home Screen Widgets** — small (today), small (quick-add), medium (combo)
8. **Lock Screen Widget** (iOS) — minimal glanceable total
9. **Backup & Restore** — manual/auto backup status, save-to-cloud, and restore-from-file with Merge/Replace choice
10. **Profile** — avatar/photo, name/email display, lifetime stats, links to account settings
11. **Edit Profile** — update name, phone, email
12. **Avatar Picker** — upload a photo or choose a colored initials-avatar

---

## 9. Success Metrics

- % of expenses logged via widget vs. in-app (target: widget ≥50% after month 1)
- Median time from app/widget open to expense saved
- Monthly report open rate
- 30-day retention

---

## 10. Open Questions for Stakeholder

1. Single currency at launch, or multi-currency from day one?
2. Is cloud sync required for v1, or can it ship in v1.1?
3. Should recurring expenses auto-log, or just remind the user to confirm?
4. Any specific export format required by the user beyond PDF/CSV (e.g. Excel)?
5. For backup: is "save file to iCloud Drive / Google Drive via OS share sheet" sufficient, or is direct integration with a specific cloud account (e.g. auto-upload to a connected Google Drive without user picking a folder each time) required?
6. Should the backup file be encrypted or password-protectable, given it contains full financial history?
7. Default auto-backup frequency — daily, weekly, or only on app close?

---

*Companion file: `spendly-prototype.html` — interactive, clickable screens for all items in Section 8, in both light and dark themes.*
