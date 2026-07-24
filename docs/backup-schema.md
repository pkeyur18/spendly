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
  "version": 2,
  "encrypted": false,
  "data": { "...payload, see below..." }
}
```

When the user sets a password on export, `data` is replaced by an AES-256-GCM
container instead:

```json
{
  "spendlyBackup": true,
  "version": 2,
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
  "counts": { "expenses": 1204, "categories": 10, "budgets": 3 },
  "categories": [
    {
      "id": 1,
      "name": "Food",
      "icon": "🍔",
      "colorValue": 1667510321,
      "sortOrder": 0,
      "isArchived": false,
      "isDefault": true
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
      "createdAt": "2026-07-01T09:03:11.000Z",
      "updatedAt": "2026-07-01T09:03:11.000Z"
    }
  ],
  "budgets": [
    { "id": 1, "categoryId": null, "amountMinor": 5000000, "period": "monthly" }
  ],
  "settings": [
    { "key": "theme_mode", "value": "system" },
    { "key": "profile_name", "value": "Aditi Sharma" },
    { "key": "profile_avatar_color", "value": "1" }
  ],
  "profilePhotoBase64": "<base64, omitted entirely if no photo is set>"
}
```

Rules:

- `amountMinor` is always an integer (paise) — never a decimal or float. This
  is what makes export→import round-trip exact.
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
  device's own backup schedule or status — plus `profile_photo_path` (v2,
  see below), which is a local file path and meaningless on another device.
  Ordinary profile fields (`profile_name`, `profile_email`, `profile_phone`,
  `profile_avatar_color`) are plain settings rows and always included.

## v2 — profile photo (FR-56)

Sprint 10 added a Profile screen with a real-photo option, stored as a local
file (`profile_photo_path` setting → file on disk), not inline in the
database. A file path can't travel in a backup the way an ordinary setting
value can, so v2 adds one optional payload field instead:

- `profilePhotoBase64` (string, optional) — the photo file's bytes,
  base64-encoded. Omitted entirely when no photo is set (colored-initials
  avatar or no avatar at all), so a payload with no photo is
  indistinguishable from a v1 payload on this field.
- A v1 file has no `profilePhotoBase64` key at all, which
  `BackupPayload.fromJson` reads as `null` — no version-keyed decode branch
  was needed, per the additive-only rule above. This is why the bump to
  `version: 2` didn't require touching `decodePayload`'s logic, only the
  `currentBackupVersion` constant.
- **Replace** decodes it (if present) to a fresh local file and writes a new
  `profile_photo_path` setting row pointing at it. If absent (v1 file, or a
  v2 file with no photo), photo state is simply left wiped — the avatar
  correctly falls back to colored initials (FR-55).
- **Merge never touches settings at all** (unchanged from v1 — see "Merge
  algorithm" below), so a merged backup's photo, like its name/email/phone,
  is never applied to the target device; only Replace restores profile data.

## Merge algorithm (no UUID column — natural-key matching)

A stable UUID column on `Expenses`/`Categories`/`Budgets` was considered so
rows could be matched across reinstalls, but rejected: Sprint 5 only ever
does share-sheet backup/restore (no account, no continuous multi-device
sync), so the only real scenario is a one-time restore onto an empty or
near-empty device. That doesn't need a schema migration to solve. Natural
keys do it with zero schema change:

- **Categories** — matched by normalized name (`trim().toLowerCase()`).
  Every fresh install seeds the same 8 default category names, so this is
  what stops a Merge from doubling them.
- **Expenses** — matched by fingerprint
  `(amountMinor, date, mappedCategoryId, note, paymentMethod)`; an exact
  match is skipped, not re-inserted.
- **Budgets** — matched by `(mappedCategoryId)` (`null` = overall); a slot
  already occupied locally is left alone (merge is additive, never clobbers
  a budget the user has since changed).

**Known ceiling** (ponytail: ship this, ceiling is real): renaming a
category between backup and restore breaks name-matching — it inserts a
"new" category instead of recognizing the rename. Fingerprint matching can
rarely collide two genuinely distinct expenses that share amount, date,
category, note, and payment method. Upgrade path if this ever bites: add a
nullable `externalId` (UUID) column via a real Drift migration, populate it
going forward, prefer it when present, and fall back to natural keys only
for rows written before the migration.

## Replace algorithm

Runs inside a single Drift transaction so a failure partway through rolls
back automatically, never leaving partial data: delete `expenses` → delete
`budgets` → delete `categories` (child-to-parent FK order), then batch-insert
categories, budgets, expenses (reusing original ids), then delete+batch-insert
`settings`.

## Validation (FR-41)

The full envelope → decrypt → payload-shape validation pipeline
(`backup_format.dart`) must complete — or throw one of
`BackupCorruptException` / `BackupVersionTooNewException` /
`BackupPasswordRequiredException` / `BackupWrongPasswordException` — entirely
before any database write is attempted. A corrupted or incompatible file must
never touch existing data.
