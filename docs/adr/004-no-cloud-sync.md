# ADR-004: No cloud sync — local export/import via the OS share sheet only

## Status

Accepted.

## Context

Users generally want their expense data to survive a lost/replaced phone, and often want it
on more than one device. The two broad ways to get there: build real sync (an account,
a server or serverless backend, a conflict-resolution strategy for concurrent edits across
devices) or provide backup/restore as a manual, user-triggered snapshot with no live
connection between devices. This decision determines a large swath of the rest of the
architecture — whether there's a server at all, whether the schema needs stable
cross-device IDs, and what "data integrity" even means for this app (see
`docs/architecture.md` §1.2 #3).

## Decision

No account, no server, no live sync. "Backup" is a local JSON export
(`lib/features/backup/backup_repository.dart`), optionally AES-256-GCM/PBKDF2-encrypted,
handed to the OS share sheet (`share_plus`) so the *user* decides where it goes (iCloud
Drive, Google Drive, email, AirDrop, local file — the app has no idea and no API integration
with any of them). A separate local-only auto-backup writes a timestamped snapshot to the
app's own Application Support directory on launch/resume, on a user-configured interval —
this is a local safety net, not a delivery mechanism; getting that file to the cloud still
requires the user to explicitly act. Restore is manual and pull-based: the user picks a file,
previews it, and chooses Merge (additive, name/fingerprint-matched — see ADR-005's sibling
note in `docs/architecture.md` §1.2 #3) or Replace (wipe and reload).

## Alternatives Considered

- **Firebase (Firestore/Realtime DB) with anonymous or account-based auth** — rejected.
  Would require a real conflict-resolution strategy (last-write-wins at minimum, ideally
  field-level merge) the moment two devices edit offline and reconnect, plus ongoing
  operational/cost exposure and a privacy posture change (financial data leaving the device
  by default) that doesn't match a personal single-user finance app.
- **Custom backend (self-hosted or serverless) with a sync protocol** — rejected for the same
  reasons, plus it's a second system to build, secure, and operate for a solo developer.
- **CRDT-based local-first sync (e.g. a CRDT library synced via a relay)** — the
  "correct" long-term answer to real multi-device sync without a central authority, but
  substantial complexity (stable per-record identity, merge semantics for every table,
  a relay/transport layer) far beyond what a single-device-primary, occasional-restore usage
  pattern justifies today.
- **iCloud/Google Drive native APIs (auto-uploaded backup, no share sheet)** — rejected as a
  next increment, not a rejection of the goal: would remove the manual share-sheet step for
  the common case, but ties the backup format/timing to two more platform-specific APIs and
  was judged not worth the integration cost until backup/restore's core mechanics (Merge
  matching, in particular) are more battle-tested. Revisit if "user forgot to back up
  manually" becomes a recurring real complaint.

## Consequences

- Genuinely offline-first: no networking dependency exists anywhere in the app
  (`docs/architecture.md` §1.2 #1) — this decision is *why* that's true, not a coincidence.
- No stable cross-device record identity exists in the schema, so Merge restore relies on
  best-effort natural-key/content-fingerprint matching with documented failure modes
  (renamed category → duplicate; fingerprint collision → possible incorrect merge) — see
  `docs/backup-schema.md` and `docs/architecture.md` §1.2 #3, §11 risk #5.
- If real multi-device sync ever becomes a hard requirement, this ADR should be
  superseded outright (not incrementally patched) — the schema would need a stable
  `externalId`, and Merge's matching logic would need to be replaced, not extended.
