# Spendly backup file format (FR-34)

Every future app version must be able to read every past backup file, so this
format is versioned and additive-only: bump `version` and add a new decode
branch when the shape changes, never repurpose an existing field. This
mirrors the migration stub already in `AppDatabase.migration.onUpgrade`
(`lib/core/db/database.dart`).

## Outer envelope

Always plain, valid JSON — never encrypted, so `version` and `encrypted` can
be read (and an incompatible-future-version file rejected) *before* a
password is ever requested.

```json
{
  "spendlyBackup": true,
  "version": 8,
  "encrypted": false,
  "data": { "...payload, see below..." }
}
```

When the user sets a password on export, `data` is replaced by an AES-256-GCM
container instead:

```json
{
  "spendlyBackup": true,
  "version": 8,
  "encrypted": true,
  "kdf": "PBKDF2-HMAC-SHA256",
  "kdfIterations": 200000,
  "salt": "<base64, 16 bytes>",
  "nonce": "<base64, 12 bytes>",
  "mac": "<base64, 16 bytes>",
  "cipher": "AES-256-GCM",
  "ciphertext": "<base64>"
}
```

The key is derived from the user's password via PBKDF2-HMAC-SHA256 with the
stored `salt` and `kdfIterations`. Decrypting `ciphertext` with that key and
`nonce`, verified against `mac`, yields the exact same payload JSON as the
unencrypted case.

## Payload (`data`)

```json
{
  "exportedAt": "2026-07-23T10:15:00.000Z",
  "counts": { "expenses": 1204, "categories": 10, "budgets": 3, "tags": 1 },
  "categories": [
    {
      "id": 1,
      "name": "Food",
      "icon": "🍔",
      "colorValue": 1667510321,
      "sortOrder": 0,
      "isArchived": false,
      "isDefault": true,
      "isIgnoredForBudget": false
    }
  ],
  "expenses": [
    {
      "id": 1,
      "amountMinor": 24500,
      "categoryId": 1,
      "date": "2026-07-01T00:00:00.000Z",
      "note": "Groceries",
      "paymentMethod": "UPI",
      "isRecurring": false,
      "recurrence": null,
      "tagId": 1,
      "createdAt": "2026-07-01T09:03:11.000Z",
      "updatedAt": "2026-07-01T09:03:11.000Z",
      "fxCurrency": "JPY",
      "fxAmountMinor": 4500000
    }
  ],
  "budgets": [
    { "id": 1, "categoryId": null, "amountMinor": 5000000, "period": "monthly" }
  ],
  "settings": [
    { "key": "theme_mode", "value": "system" },
    { "key": "profile_name", "value": "Aditi Sharma" },
    { "key": "profile_avatar_color", "value": "1" },
    { "key": "profile_photo_base64", "value": "<base64, key absent entirely if no photo is set>" }
  ],
  "tags": [
    {
      "id": 1,
      "name": "Japan Trip 2026",
      "colorValue": 1667510321,
      "isArchived": false,
      "fxCurrency": "JPY",
      "fxRateMicros": 550000,
      "tripStartDate": "2026-07-01T00:00:00.000Z",
      "tripEndDate": "2026-07-10T00:00:00.000Z"
    }
  ]
}
```

Rules:

- `amountMinor` is always an integer (paise) — never a decimal or float. This
  is what makes export→import round-trip exact. It is also always **home
  currency**, in every version of this format; a foreign amount rides
  alongside it in `fxAmountMinor` (v4) and is never the value a total is
  built from.
- `id` values are the *source device's* autoincrement ids, kept only so
  `expenses`/`budgets` can reference `categories` within the same file.
  - **Replace** wipes all four tables first, then reuses these ids verbatim
    (no collision possible).
  - **Merge** never trusts these ids across devices — it remaps every
    `categoryId` through a name-match table, and dedupes expenses/budgets by
    content, not by id. See "Merge algorithm" below.
- `recurrence` / `period` enum fields serialize as their `.name` string
  (`"daily"`, `"weekly"`, `"monthly"`), matching Drift's own on-disk
  `textEnum` representation.
- `settings` excludes the app's own backup-bookkeeping keys
  (`auto_backup_enabled`, `auto_backup_frequency`, `last_backup_at`,
  `last_backup_size`) — importing a backup must never rewrite the restoring
  device's own backup schedule or status. Ordinary profile fields
  (`profile_name`, `profile_email`, `profile_phone`, `profile_avatar_color`,
  `profile_photo_base64`) are plain settings rows and always included.

## v2 — profile photo (FR-56)

Sprint 10 added a Profile screen with a real-photo option. The photo's bytes
are stored base64-encoded directly in the `profile_photo_base64` setting —
same row-store as every other profile field, so it's an ordinary
`BackupSetting` like the rest, with no extra payload plumbing needed.

(Earlier versions of this app stored the photo as a local file, referenced
by a `profile_photo_path` setting — that path wasn't portable across
devices, so v2's *original* implementation carried the photo as a separate
top-level `profilePhotoBase64` payload field instead. That field has since
been folded into `settings` now that the value itself — image bytes, not a
path — is portable. `BackupPayload.fromJson` still recognizes the legacy
top-level key on old exported files and folds it into `settings` on read, so
old v2 backups continue to restore their photo correctly.)

- **Replace** restores `profile_photo_base64` the same as any other setting
  row — no special-casing. If absent (no photo was set), photo state is
  simply left wiped — the avatar correctly falls back to colored initials
  (FR-55).
- **Merge never touches settings at all** (unchanged from v1 — see "Merge
  algorithm" below), so a merged backup's photo, like its name/email/phone,
  is never applied to the target device; only Replace restores profile data.

## v3 — trip/tag tracking

Trips (e.g. a vacation) can be tracked separately from the overall budget:
each expense optionally carries a `tagId`, orthogonal to its `categoryId` —
tagging doesn't change any category, budget, or date-range total, it's
purely an additional grouping. v3 adds:

- `tags` (array, top-level payload field, same shape as `categories` but
  without `icon`/`sortOrder`/`isDefault`) — every trip/tag on the source
  device.
- `tagId` (int, nullable, on each expense) — the backup-file id of the tag
  it was assigned to, or `null` if untagged.
- A pre-v3 file has neither key. `BackupPayload.fromJson` reads a missing
  `tags` as `[]`; `BackupExpense.fromJson` reads a missing `tagId` as `null`
  — same additive, no-version-branch pattern as v2's photo field.
- **Replace** wipes and restores `tags` the same way as `categories`
  (original ids reused verbatim, inserted before `expenses` for FK order).
- **Merge** matches tags by normalized name, exactly like categories (see
  below), and remaps each expense's `tagId` through that map the same way
  `categoryId` is remapped.

## Additive field — `isIgnoredForBudget` (Sprint 12, still v3)

Sprint 12 added a per-category "ignore for budget" flag (`categories.isIgnoredForBudget`,
Drift schema v6). It's carried in the payload as a plain new key on each `categories` entry
— no version bump needed, same additive pattern as v2's photo field and v3's `tagId`:
pre-Sprint-12 backups simply lack the key, and `BackupCategory.fromJson` reads a missing
key as `false`.

- **Replace** restores it verbatim, same as `isArchived`/`isDefault`.
- **Merge** — matched (pre-existing) categories are left untouched (same as
  `isArchived`/`isDefault` today — merge never overwrites an existing category's flags from
  the backup); only a brand-new category inserted by Merge carries over its backed-up
  `isIgnoredForBudget` value.

## Additive field — `externalId` (schema v7)

Every table used by backup (`categories`, `expenses`, `tags`, `budgets`) now carries a
nullable `externalId` (UUID v4, hand-generated — see `lib/core/db/external_id.dart`, no new
dependency). Same additive, no-version-branch pattern as every prior field added to this
format: `BackupCategory.fromJson` (and the sibling classes) read a missing `externalId` key
as `null`. Every new row gets one automatically via Drift's `clientDefault` on the column —
no repository code had to change. The v7 migration also backfills every pre-existing row with
a freshly generated id immediately (not lazily), via `backfillExternalIds()` in
`lib/core/db/database.dart`.

- **Replace** carries the backup's `externalId` through verbatim, same as `id`.
- **Merge** — see below, this is what `externalId` was added to fix.

## v4 — trip currency (schema v8)

A trip abroad is entered in the local currency and converted to home currency
once, at save time. The converted amount is what gets stored in
`amountMinor`; the original travels alongside it as a receipt for display.
**`amountMinor` is always home currency, in every version of this format** —
that's why no total, budget, chart or export needed changing, and why a v4
file restored into an older build is still correct.

On each `tags` entry:

- `fxCurrency` (string, nullable) — ISO 4217 code for a trip abroad, e.g.
  `"THB"`. `null` on an ordinary tag.
- `fxRateMicros` (int, nullable) — home-currency units per 1 unit of
  `fxCurrency`, scaled by 1e6 (2.62 INR/THB is `2620000`). Integer so a rate
  never rides a double, same discipline as `amountMinor`. See
  `lib/core/money/fx.dart`.

On each `expenses` entry:

- `fxCurrency` (string, nullable) — what this expense was actually paid in.
- `fxAmountMinor` (int, nullable) — the original amount, in that currency's
  minor units. Stored as two-decimal minor units for **every** currency, so
  ¥1500 is `150000`; formatting drops the digits a currency doesn't use.

Both fields on a row are set together or not at all — never one without the
other.

- A pre-v4 file has none of these keys, and `fromJson` reads each missing key
  as `null` — same additive, no-version-branch pattern as every field above.
  Such a file restores as ordinary home-currency data.
- The rate is deliberately **not** recorded per expense. Editing a trip's
  rate mid-trip applies only to expenses saved afterwards; ones already saved
  keep the home amount they were converted to, so restoring a backup can
  never move a month's total. A trip report derives its average rate as
  `sum(amountMinor) / sum(fxAmountMinor)` over the trip's expenses.
- **Replace** restores all four verbatim.
- **Merge** — a brand-new tag inserted by Merge carries over its
  `fxCurrency`/`fxRateMicros`; a matched pre-existing tag is left untouched,
  same as `isArchived`. Expenses carry their own receipt regardless, since
  it's frozen data rather than a live setting.

## v5 — trip dates (schema v9)

A trip tag can carry a start/end date so Quick Add auto-attaches it to any expense
logged on a day inside that range, without the user re-picking it each time — see
`tripForDate` in `lib/features/expenses/quick_add_screen.dart`. Independent of the v4
currency fields; a domestic trip can use dates without ever setting `fxCurrency`.

On each `tags` entry:

- `tripStartDate` (string, nullable, ISO 8601) — first day the trip auto-tags.
- `tripEndDate` (string, nullable, ISO 8601) — last day the trip auto-tags, inclusive.

Both null on a tag with no date range. A pre-v5 file has neither key, and
`BackupTag.fromJson` reads a missing key as `null` — same additive, no-version-branch
pattern as every field above.

- **Replace** restores both verbatim, same as every other tag field.
- **Merge** — a brand-new tag inserted by Merge carries over its dates; a matched
  pre-existing tag is left untouched, same as `isArchived`/`fxCurrency`.
- The app enforces at most one active trip covering any given day (blocked at save time
  in `tag_edit_sheet.dart`, via `TagRepository.hasOverlappingDateRange`), but a restored
  backup is trusted as-is — Merge/Replace never re-validates this, the same way it never
  re-validates any other field.

## v6 — recurring schedule (schema v10)

A recurring expense is an ordinary expense row that also carries the schedule for its
series — see `lib/features/expenses/recurring_schedule.dart`. Future occurrences are
never materialised as rows; the series is tracked by a single pointer, so a backup only
needs to carry that pointer and the optional end date.

On each `expenses` entry:

- `nextDueDate` (string, nullable, ISO 8601) — when the next occurrence falls due.
  Null once the series has finished, or on any non-recurring expense.
- `recurrenceEndDate` (string, nullable, ISO 8601) — last date the series may produce an
  occurrence on. Null = repeats until switched off.

`isRecurring` and `recurrence` already existed in every prior version; without these two
new keys a restored file would keep the recurring *flag* but have nothing scheduled, so
the reminder would never fire again. A pre-v6 file has neither key, and
`BackupExpense.fromJson` reads a missing key as `null` — same additive, no-version-branch
pattern as every field above. That leaves a restored pre-v6 recurring expense in exactly
the state the schema-v10 migration leaves an existing one: flagged, unscheduled, and
listed as "not scheduled" until the user opens it. No due date is invented, because
there is nothing to reconstruct one from and a guessed date would fire a reminder the
user never asked for.

- **Replace** restores both verbatim, same as every other expense field.
- **Merge** — a brand-new expense inserted by Merge carries over its schedule; a matched
  pre-existing expense is left untouched, same as every other field. The schedule takes
  no part in the fingerprint, so re-importing a backup after confirming an occurrence
  locally does not duplicate the expense.

## v7 — receipt photos (schema v11)

A receipt photo lives in its own `expense_receipts` table, not a column on `expenses` —
see the doc comment on `ExpenseReceipts` in `lib/core/db/database.dart` for why (every
expense query in the app reads full rows; a blob column there would ride along on every
one of them, including the lazily-paginated transaction list, even for expenses with no
photo). The payload gets a new top-level array to match:

```json
"receipts": [
  { "expenseId": 42, "photoBase64": "<base64 JPEG bytes>" }
]
```

`expenseId` is the **backup file's** expense id — the same id `BackupExpense.id` carries
for the row it belongs to within this same payload — never a local device id. Replace and
Merge resolve it to a local expense id differently, so the meaning has to be fixed at the
file level for both to agree on it:

- **Replace** wipes `expense_receipts` before wiping `expenses`, then restores the backup's
  expenses reusing their original ids verbatim (the table is empty by then — same
  reasoning as every other Replace field). Because ids line up exactly, `expenseId` in a
  receipt entry is reused as-is for the local `expense_receipts` row it produces.
- **Merge** never touches a matched (already-present) expense's receipt, same as it never
  touches any other field on a match — merge only adds, it doesn't overwrite local state.
  Only a newly-inserted expense can gain a receipt from the backup, and only under the
  **local id Merge just assigned it**, not the backup file's id — those two numbers are
  unrelated once a new autoincrement id is handed out. `BackupRepository._mergeExpenses`
  inserts a receipted expense individually (not batched) specifically to learn that new id
  before attaching its photo; expenses with no receipt still insert batched, since that
  path covers the common case and receipted expenses are expected to be the minority.

A pre-v7 file has no `receipts` key at all, and `BackupPayload.fromJson` reads that as an
empty list — same additive, no-version-branch pattern as every field above. Nothing is
lost by this: a pre-v7 backup was written before receipts existed, so there was never a
photo to carry.

## v8 — accounts (schema v12)

An account (cash/bank/card/wallet) is its own table, same shape of decision as receipts in
v7: `expenses` is read in full by nearly every query in the app, so a new master-data
concept gets its own table rather than more columns dragged through every one of those
reads. The payload gets a new top-level array:

```json
"accounts": [
  {
    "id": 1,
    "name": "HDFC Bank",
    "type": "bank",
    "openingBalanceMinor": 500000,
    "isArchived": false,
    "externalId": "...",
    "isDefault": false
  }
],
```

and each `expenses` entry gains one new key:

- `accountId` (int, nullable) — the backup-file id of the account it was paid from, or
  `null`. Same convention as `tagId`: this is the **backup file's** id, resolved to a local
  account id by Replace and Merge exactly the way `tagId` already is, not a raw local id
  carried across devices.

`type` serializes as its `.name` string (`"cash"`, `"bank"`, `"card"`, `"wallet"`), same
convention as `recurrence`/`period`.

- **Replace** wipes `accounts` (after `expenses`, since `expenses.accountId` references it —
  same FK-order reasoning as everything else) then restores it before restoring `expenses`,
  reusing original ids verbatim. Because ids line up exactly, an expense's `accountId` needs
  no remapping.
- **Merge** matches accounts by `externalId` first, falling back to normalized name — same
  rule as categories/tags. A matched (already-present) account is left untouched, same as
  every other master-data table; only a newly-inserted expense's `accountId` gets remapped
  through the resulting backup-id → local-id map, the same way `tagId` already is.

A pre-v8 file has no `accounts` key and no `accountId` key on its expenses.
`BackupPayload.fromJson` reads a missing `accounts` as `[]`; `BackupExpense.fromJson` reads
a missing `accountId` as `null` — same additive, no-version-branch pattern as every field
above.

## Additive field — `isDefault` on accounts (schema v13)

At most one account is the default Quick Add prefills onto a fresh expense — enforced by
`AccountRepository.setDefault`, not a DB constraint. Carried in the payload as a plain new
key on each `accounts` entry, no version bump, same additive pattern as
`isIgnoredForBudget`: a pre-v13 file simply lacks the key, and `BackupAccount.fromJson`
reads a missing key as `false`.

- **Replace** restores it verbatim, same as every other account field — safe because the
  whole table is wiped first, and the backup itself never had two defaults at once (this
  app's own UI never allows that), so restoring every row's flag as-is can't recreate a
  violation that didn't exist in the file.
- **Merge** does **not** trust this field blindly, unlike most others. A matched
  (already-present) account's `isDefault` is left untouched, same as any other field on a
  match. But a *newly-inserted* account's flag can't simply carry over the backup's own
  value: if the local device already has its own default, and a merged-in account also
  claims `isDefault: true` from its source device, honoring both would produce two default
  accounts at once — a state the app's own `setDefault` never permits. `_mergeAccounts`
  computes this instead: at most one newly-inserted account ever gets `isDefault: true`,
  and only when the local device had no default at all before the merge started.

## Additive field — `openingBalanceMonth` on accounts (schema v14)

Unused by the app today. Originally backed a monthly-reset display rule for opening
balance (the stored `openingBalanceMinor` only counted when this `'YYYY-MM'` stamp
matched the current month); that rule has since been removed — opening balance is now a
one-time starting point that carries forward forever, read directly off
`openingBalanceMinor`. The column and this backup field are kept, not dropped, purely so
old backup files with this key still round-trip cleanly; no version bump either way.

- **Replace** restores it verbatim, same as every other account field.
- **Merge** restores it verbatim too on a newly-inserted account — unlike `isDefault`,
  there's no "at most one" invariant to protect here, so a plain carry-over is safe. A
  matched (already-present) account isn't touched by merge at all, so its own local stamp
  is never overwritten by the backup's.

## v9 — income (schema v15)

Income entries are a new table, `LedgerEntries`, kept separate from `Expenses` rather than a
`kind` column on it — see
`docs/superpowers/specs/2026-08-23-ux-and-ledger-design.md`'s "separate ledger table"
decision: roughly fourteen existing expense queries would each need an opt-out guard to
exclude income if it lived in the same table, and a single missed one silently inflates
reported spending. The payload gets a new top-level array:

```json
"ledgerEntries": [
  {
    "id": 1,
    "amountMinor": 5000000,
    "date": "2026-07-01T00:00:00.000",
    "accountId": 1,
    "sourceLabel": "Salary",
    "note": null,
    "externalId": "..."
  }
],
```

`accountId` is the **backup file's** account id, same convention as `expenses[].accountId` —
resolved to a local account id by Replace (verbatim, since ids are reused) and Merge (through
the account id map).

- **Replace** wipes `ledgerEntries` before `accounts` (it references `accounts.id`, same
  FK-order reasoning as `expenses`) then restores it after `accounts`, reusing original ids
  verbatim.
- **Merge** matches by `externalId` first, falling back to a content fingerprint (amount,
  date, mapped account, source label, note) — same two-tier rule as `expenses`, since a plain
  income entry has no natural-key field like a name to fall back on.

A pre-v9 file has no `ledgerEntries` key at all. `BackupPayload.fromJson` reads it as `[]` —
same additive, no-destructive-branch pattern as every new array before it.

## Additive fields — `kind` and `counterAccountId` on ledger entries (schema v16)

Transfers (Phase 6) reuse the same `ledgerEntries` array v9 introduced rather than adding a
new one — an entry is now either `"kind": "income"` (the only kind that existed before) or
`"kind": "transfer"`, and a transfer additionally carries `counterAccountId`: the backup
file's id for the destination account, resolved the same way `accountId` already is (Replace
verbatim, Merge through the account id map). No version bump, same additive pattern as
`openingBalanceMonth` on accounts: a pre-v16 file simply lacks both keys, and
`BackupLedgerEntry.fromJson` reads a missing `kind` as `income` and a missing
`counterAccountId` as `null` — exactly what every pre-transfer entry already was.

- **Replace** restores both fields verbatim, same as every other ledger entry field.
- **Merge** resolves `counterAccountId` through the same account id map `accountId` uses. A
  transfer whose either end can't be mapped to a real local account (should never happen on a
  well-formed payload — every transfer's accounts appear in the same payload's `accounts`
  array) is skipped entirely rather than inserted half-mapped, same orphan-safety reasoning
  as `_mergeExpenses`'s category check.
- The Merge dedupe fingerprint now includes `kind` and `counterAccountId` alongside the
  existing amount/date/account/sourceLabel/note terms, so two transfers that happen to share
  every other field but move money between different account pairs are never treated as
  duplicates of each other.

## v10 — savings goals (schema v17)

A savings goal is its own table with no FK to anything else — the simplest of the
whole-new-table additions. The payload gets a new top-level array:

```json
"savingsGoals": [
  {
    "id": 1,
    "name": "New laptop",
    "targetMinor": 8000000,
    "savedMinor": 2000000,
    "isArchived": false,
    "externalId": "..."
  }
],
```

- **Replace** wipes and restores `savingsGoals` (any position relative to the other
  deletes/inserts — nothing references it, nothing it references), reusing original ids
  verbatim.
- **Merge** matches by `externalId` first, falling back to normalized name — same rule as
  categories/tags. A matched (already-present) goal is left untouched, including its saved
  progress; only a newly-inserted goal carries the backup's `savedMinor` over, which is safe
  since there's no local progress on a goal that didn't already exist here for it to clobber.

A pre-v10 file has no `savingsGoals` key at all. `BackupPayload.fromJson` reads it as `[]` —
same additive, no-destructive-branch pattern as every new array before it.

## Additive field — `includeInNetWorth` on accounts (schema v18)

Whether this account's balance counts toward the home screen's "Balance across accounts"
total — nothing else reads it (an account's own balance, its transaction history, exports:
all identical either way). Plain new nullable-by-omission key on each `accounts` entry, no
version bump, same additive pattern as `openingBalanceMonth`.

- **Replace** restores it verbatim, same as every other account field.
- **Merge** restores it verbatim too on a newly-inserted account — no "at most one"
  invariant to protect (unlike `isDefault`), so a plain carry-over is safe. A matched
  (already-present) account isn't touched by merge at all, so its own local setting is
  never overwritten by the backup's.

A pre-v18 file has no `includeInNetWorth` key. `BackupAccount.fromJson` reads a missing key
as `true` — counted, matching what a pre-v18 account already was by not having the concept
at all.

## Additive field — `isLiability` on accounts (schema v19)

Whether this account is a liability (a loan, a credit card's running debt) rather than an
asset — purely a display/sign convention, same as `includeInNetWorth`: nothing in the
schema branches on it, `openingBalanceMinor` is simply stored negative for a liability
account. Plain new nullable-by-omission key on each `accounts` entry, no version bump, same
additive pattern as `includeInNetWorth`.

- **Replace** restores it verbatim, same as every other account field.
- **Merge** restores it verbatim too on a newly-inserted account — no "at most one"
  invariant to protect, so a plain carry-over is safe. A matched (already-present) account
  isn't touched by merge at all, so its own local setting is never overwritten by the
  backup's.

A pre-v19 file has no `isLiability` key. `BackupAccount.fromJson` reads a missing key as
`false` — an asset, matching what every pre-v19 account already was.

## Additive fields — `customTypeName`/`customTypeIcon`/`customTypeColorValue` on accounts (schema v20)

A custom account type's own name, emoji icon and ARGB color — only ever non-null together,
and only on an `AccountType.custom` account. Same additive, no-version-bump shape as
`isLiability`, restored verbatim by both Replace and Merge (no "at most one" invariant to
protect, same reasoning as `includeInNetWorth`/`isLiability`).

A pre-v20 file has no custom-type keys at all. `BackupAccount.fromJson` reads all three as
`null` — matching every pre-v20 account, none of which could be custom-typed.

## Additive fields — `isRecurring`/`recurrence`/`nextDueDate`/`recurrenceEndDate` on ledger entries (schema v21)

Recurring income reuses the same four columns `Expenses` already carries for recurring
expenses, added to `ledgerEntries` array entries the same way `kind`/`counterAccountId`
were at schema v16 — additive, no version bump. Only ever meaningful on a `kind: "income"`
entry; a transfer never recurs.

- **Replace** restores all four verbatim, same as every other ledger entry field.
- **Merge** restores them verbatim too on a newly-inserted entry — no "at most one"
  invariant to protect, same reasoning as `includeInNetWorth`/`isLiability` on accounts.
  A matched (already-present) entry isn't touched by merge at all.
- Not included in the Merge dedupe fingerprint: a recurring template always carries an
  `externalId` (schema v21 postdates `externalId` becoming universal at v7), so the
  fingerprint fallback path can never actually apply to one.

A pre-v21 file has no recurrence keys at all. `BackupLedgerEntry.fromJson` reads
`isRecurring` as `false` and the other three as `null` — matching every pre-v21 entry,
none of which could recur.

## Additive field — `templateOnly` on expenses and ledger entries (schema v22)

A recurring series created from schema v22 onward gets its own dedicated template row,
separate from the real transaction that started it (see `database.dart`'s
`Expenses.templateOnly` doc comment for why). `templateOnly` marks that dedicated row —
true only for a row that exists purely to carry a schedule, never a real transaction.
Additive on both tables, no version bump, same pattern as every field above it.

- **Replace** restores it verbatim, same as every other field.
- **Merge** restores it verbatim on a newly-inserted row; a matched (already-present)
  row isn't touched by merge at all — same as `isRecurring`/`recurrence` above.
- **Unlike schema v21's recurrence fields, this one IS included in the Merge dedupe
  fingerprint**, for the opposite reason v21 gave for excluding theirs: a template row is
  a near-exact clone of the real transaction that spawned it (same amount, date, category,
  note, payment method) and both can plausibly lack an `externalId` match across devices,
  so without `templateOnly` in the fingerprint the two would collide — Merge would treat
  one as a duplicate of the other and silently drop it, losing either the real transaction
  or its recurring schedule. See `BackupExpense.fingerprint`/`BackupLedgerEntry.fingerprint`.

A pre-v22 file has no `templateOnly` key at all. `fromJson` reads it as `false` on both
tables — matching every pre-v22 row, none of which were a dedicated template.

## Additive field — `isFrequent` on accounts (schema v23)

Whether an account is offered first in every account picker once at least one account has
it set. Independent of `isDefault` — no "at most one" invariant, same additive,
no-version-bump shape as `includeInNetWorth`/`isLiability`.

- **Replace** restores it verbatim, same as `includeInNetWorth`/`isLiability`.
- **Merge** restores it verbatim too on a newly-inserted account — no invariant to protect,
  same reasoning. A matched (already-present) account's `isFrequent` is left untouched,
  same as any other field on a matched row.

A pre-v23 file has no `isFrequent` key. `BackupAccount.fromJson` reads a missing key as
`false` — matching every pre-v23 account, none of which had this concept.

## App Lock is never in the payload

Whether App Lock is turned on (`app_lock_enabled` in `Settings`) is excluded from export
entirely — same list as the auto-backup bookkeeping keys (`BackupRepository._excludedSettingsKeys`).
Restoring a backup on a new device must never silently lock the person out of the app they
just installed it on; App Lock is a device-local security preference, not portable state.

## Merge algorithm (`externalId` first, natural-key fallback)

- **Categories** — matched by `externalId` first when both the backup row and a local row
  have one; falls back to normalized name (`trim().toLowerCase()`) otherwise. Every fresh
  install seeds the same 8 default category names, so the name fallback is still what stops a
  Merge from doubling those.
- **Tags** — same rule as categories.
- **Accounts** — same rule as categories/tags.
- **Expenses** — matched by `externalId` first; falls back to content fingerprint
  `(amountMinor, date, mappedCategoryId, note, paymentMethod)`.
- **Budgets** — matched by `externalId` first; falls back to `(mappedCategoryId)` slot
  (`null` = overall) — a slot already occupied locally is left alone (merge is additive,
  never clobbers a budget the user has since changed).

**Residual ceiling**: the natural-key/fingerprint fallback is still real and still used —
for rows created before schema v7, and for restoring a backup file exported before this
change (which has no `externalId` key at all). For any row/file with `externalId` present,
renaming a category between backup and restore now matches correctly (the exact bug this was
built to fix); the previous "known ceiling" section described that failure mode before the
fix — this replaces it.

## Replace algorithm

Runs inside a single Drift transaction so a failure partway through rolls
back automatically, never leaving partial data: delete `expense_receipts` →
delete `expenses` → delete `accounts` → delete `tags` → delete `budgets` →
delete `categories` (child-to-parent FK order), then batch-insert
categories, tags, accounts, budgets, expenses, expense_receipts (reusing
original ids throughout), then delete+batch-insert `settings`.

## Validation (FR-41)

The full envelope → decrypt → payload-shape validation pipeline
(`backup_format.dart`) must complete — or throw one of
`BackupCorruptException` / `BackupVersionTooNewException` /
`BackupPasswordRequiredException` / `BackupWrongPasswordException` — entirely
before any database write is attempted. A corrupted or incompatible file must
never touch existing data.
