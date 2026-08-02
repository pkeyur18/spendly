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
  "version": 5,
  "encrypted": false,
  "data": { "...payload, see below..." }
}
```

When the user sets a password on export, `data` is replaced by an AES-256-GCM
container instead:

```json
{
  "spendlyBackup": true,
  "version": 5,
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

## Merge algorithm (`externalId` first, natural-key fallback)

- **Categories** — matched by `externalId` first when both the backup row and a local row
  have one; falls back to normalized name (`trim().toLowerCase()`) otherwise. Every fresh
  install seeds the same 8 default category names, so the name fallback is still what stops a
  Merge from doubling those.
- **Tags** — same rule as categories.
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
back automatically, never leaving partial data: delete `expenses` → delete
`tags` → delete `budgets` → delete `categories` (child-to-parent FK order),
then batch-insert categories, tags, budgets, expenses (reusing original ids),
then delete+batch-insert `settings`.

## Validation (FR-41)

The full envelope → decrypt → payload-shape validation pipeline
(`backup_format.dart`) must complete — or throw one of
`BackupCorruptException` / `BackupVersionTooNewException` /
`BackupPasswordRequiredException` / `BackupWrongPasswordException` — entirely
before any database write is attempted. A corrupted or incompatible file must
never touch existing data.
