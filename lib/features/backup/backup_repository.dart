import 'dart:convert';

import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import 'backup_models.dart';

/// Export/import of the full dataset (FR-33, FR-38, FR-39, FR-40). Operates
/// directly on [AppDatabase]'s generated table getters rather than the
/// per-feature repositories — those are scoped to their own CRUD needs, and
/// bolting bulk get-all/wipe-all onto all three just for this one sprint
/// would spread backup logic across files that don't otherwise need it.
class BackupRepository {
  BackupRepository(this._db);
  final AppDatabase _db;

  /// Excluded from the generic settings export/import: backup bookkeeping,
  /// so importing a file elsewhere never overwrites the restoring device's
  /// own schedule/status.
  static const _excludedSettingsKeys = {
    SettingsRepository.autoBackupEnabledKey,
    SettingsRepository.autoBackupFrequencyKey,
    SettingsRepository.lastBackupAtKey,
    SettingsRepository.lastBackupSizeKey,
  };

  /// Everything except the app's own backup bookkeeping (so importing this
  /// file elsewhere never overwrites the restoring device's own schedule).
  Future<BackupPayload> exportAll() async {
    final categories = await _db.select(_db.categories).get();
    final expenses = await _db.select(_db.expenses).get();
    final budgets = await _db.select(_db.budgets).get();
    final settings = await _db.select(_db.settings).get();
    final tags = await _db.select(_db.tags).get();
    final receipts = await _db.select(_db.expenseReceipts).get();
    final accounts = await _db.select(_db.accounts).get();
    final ledgerEntries = await _db.select(_db.ledgerEntries).get();

    return BackupPayload(
      exportedAt: DateTime.now(),
      categories: categories.map(BackupCategory.fromRow).toList(),
      expenses: expenses.map(BackupExpense.fromRow).toList(),
      budgets: budgets.map(BackupBudget.fromRow).toList(),
      settings: settings
          .where((s) => !_excludedSettingsKeys.contains(s.key))
          .map(BackupSetting.fromRow)
          .toList(),
      tags: tags.map(BackupTag.fromRow).toList(),
      // expenseId here is the LOCAL expense id (this device's own tables,
      // not yet a backup file) — exactly the id BackupExpense.id carries for
      // the same row, so the two line up with no translation needed.
      receipts: [
        for (final r in receipts)
          BackupReceipt(
            expenseId: r.expenseId,
            photoBase64: base64Encode(r.photoBytes),
          ),
      ],
      accounts: accounts.map(BackupAccount.fromRow).toList(),
      ledgerEntries: ledgerEntries.map(BackupLedgerEntry.fromRow).toList(),
    );
  }

  /// Wipes all four tables, then restores exactly [payload], reusing its
  /// original ids verbatim (safe — the tables are empty by then). Wrapped in
  /// one transaction: any failure partway through rolls back everything. The
  /// profile photo travels as an ordinary `settings` row (base64 bytes under
  /// [SettingsRepository.profilePhotoBase64Key]), so it round-trips with no
  /// special handling.
  Future<void> replaceAll(BackupPayload payload) async {
    await _db.transaction(() async {
      // Children before parents (FK order). expenseReceipts is a child of
      // expenses, so it goes first, same reasoning as everything below it.
      // ledgerEntries is also a child of accounts (accountId), same as
      // expenses — both are deleted before accounts.
      // accounts is a parent of expenses (accountId), so it's deleted after
      // expenses, same as categories/tags.
      await _db.delete(_db.expenseReceipts).go();
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.ledgerEntries).go();
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.tags).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.settings).go();

      await _db.batch((b) {
        b.insertAll(
          _db.categories,
          payload.categories.map((c) => c.toReplaceCompanion()),
        );
        b.insertAll(_db.tags, payload.tags.map((t) => t.toReplaceCompanion()));
        b.insertAll(
          _db.accounts,
          payload.accounts.map((a) => a.toReplaceCompanion()),
        );
        b.insertAll(
          _db.budgets,
          payload.budgets.map((bg) => bg.toReplaceCompanion()),
        );
        b.insertAll(
          _db.expenses,
          payload.expenses.map((e) => e.toReplaceCompanion()),
        );
        if (payload.settings.isNotEmpty) {
          b.insertAll(
            _db.settings,
            payload.settings.map((s) => s.toCompanion()),
          );
        }
        // Safe to reuse [BackupReceipt.expenseId] verbatim as the local
        // expenseId: expenses were just inserted above with THEIR original
        // ids reused too (the table was empty), so the two line up exactly
        // the way they did at export time.
        if (payload.receipts.isNotEmpty) {
          b.insertAll(
            _db.expenseReceipts,
            payload.receipts.map(
              (r) => ExpenseReceiptsCompanion.insert(
                expenseId: r.expenseId,
                photoBytes: base64Decode(r.photoBase64),
              ),
            ),
          );
        }
        if (payload.ledgerEntries.isNotEmpty) {
          b.insertAll(
            _db.ledgerEntries,
            payload.ledgerEntries.map((l) => l.toReplaceCompanion()),
          );
        }
      });
    });
  }

  /// Adds [payload]'s data to what's already on the device without
  /// duplicating it — see the "Merge algorithm" section of
  /// `docs/backup-schema.md` for the natural-key matching rules and their
  /// known ceiling. Settings (profile, theme, and the profile photo — an
  /// ordinary setting like the rest) are never touched by a merge; only
  /// Replace restores them. One transaction.
  Future<void> mergeAll(BackupPayload payload) async {
    await _db.transaction(() async {
      final categoryIdMap = await _mergeCategories(payload.categories);
      final tagIdMap = await _mergeTags(payload.tags);
      final accountIdMap = await _mergeAccounts(payload.accounts);
      await _mergeBudgets(payload.budgets, categoryIdMap);
      await _mergeExpenses(
        payload.expenses,
        categoryIdMap,
        tagIdMap,
        accountIdMap,
        payload.receipts,
      );
      await _mergeLedgerEntries(payload.ledgerEntries, accountIdMap);
    });
  }

  /// Matches by [BackupCategory.externalId] first (stable across a rename —
  /// see `docs/backup-schema.md`), falling back to normalized name for rows
  /// written before schema v7 or backup files that predate the field
  /// entirely (every fresh install seeds the same 8 default names, so
  /// blind-insert would double them). Inserts the rest individually (not
  /// batched) so each new row's assigned id can be recorded — category
  /// counts are small enough that this is fine. Returns
  /// backup-category-id -> local-category-id.
  Future<Map<int, int>> _mergeCategories(
    List<BackupCategory> backupCats,
  ) async {
    final existing = await _db.select(_db.categories).get();
    final byExternalId = <String, int>{
      for (final c in existing)
        if (c.externalId != null) c.externalId!: c.id,
    };
    final byNormalizedName = <String, int>{
      for (final c in existing) _normalize(c.name): c.id,
    };
    var nextSortOrder = existing.isEmpty
        ? 0
        : existing.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    final idMap = <int, int>{};
    for (final c in backupCats) {
      final matchedId =
          (c.externalId != null ? byExternalId[c.externalId] : null) ??
          byNormalizedName[_normalize(c.name)];
      if (matchedId != null) {
        idMap[c.id] = matchedId;
        continue;
      }
      final newId = await _db
          .into(_db.categories)
          .insert(c.toInsertCompanion(sortOrder: nextSortOrder));
      idMap[c.id] = newId;
      nextSortOrder++;
    }
    return idMap;
  }

  /// Matches by [BackupTag.externalId] first, falling back to normalized
  /// name — same rule as [_mergeCategories]. Tags have no sort order, so new
  /// ones are simply inserted. Returns backup-tag-id -> local-tag-id.
  Future<Map<int, int>> _mergeTags(List<BackupTag> backupTags) async {
    final existing = await _db.select(_db.tags).get();
    final byExternalId = <String, int>{
      for (final t in existing)
        if (t.externalId != null) t.externalId!: t.id,
    };
    final byNormalizedName = <String, int>{
      for (final t in existing) _normalize(t.name): t.id,
    };

    final idMap = <int, int>{};
    for (final t in backupTags) {
      final matchedId =
          (t.externalId != null ? byExternalId[t.externalId] : null) ??
          byNormalizedName[_normalize(t.name)];
      if (matchedId != null) {
        idMap[t.id] = matchedId;
        continue;
      }
      final newId = await _db.into(_db.tags).insert(t.toInsertCompanion());
      idMap[t.id] = newId;
    }
    return idMap;
  }

  /// Matches by [BackupAccount.externalId] first, falling back to normalized
  /// name — same rule as [_mergeCategories]/[_mergeTags]. Returns
  /// backup-account-id -> local-account-id.
  ///
  /// A matched (already-present) account's `isDefault` is left untouched,
  /// same as every other field on a match. For newly-inserted accounts: at
  /// most one gets `isDefault: true`, and only if the local device has no
  /// default at all yet — carrying over every backup row's own flag
  /// verbatim could otherwise produce two default accounts (this device's
  /// existing one, plus a merged-in one that was default on the source
  /// device), which [AccountRepository.setDefault] never allows to happen
  /// through the app's own UI.
  Future<Map<int, int>> _mergeAccounts(
    List<BackupAccount> backupAccounts,
  ) async {
    final existing = await _db.select(_db.accounts).get();
    final byExternalId = <String, int>{
      for (final a in existing)
        if (a.externalId != null) a.externalId!: a.id,
    };
    final byNormalizedName = <String, int>{
      for (final a in existing) _normalize(a.name): a.id,
    };
    var canAssignDefault = existing.every((a) => !a.isDefault);

    final idMap = <int, int>{};
    for (final a in backupAccounts) {
      final matchedId =
          (a.externalId != null ? byExternalId[a.externalId] : null) ??
          byNormalizedName[_normalize(a.name)];
      if (matchedId != null) {
        idMap[a.id] = matchedId;
        continue;
      }
      final asDefault = a.isDefault && canAssignDefault;
      if (asDefault) canAssignDefault = false; // at most one, ever
      final newId = await _db
          .into(_db.accounts)
          .insert(a.toInsertCompanion(asDefault: asDefault));
      idMap[a.id] = newId;
    }
    return idMap;
  }

  /// Matches by [BackupBudget.externalId] first, falling back to (mapped
  /// categoryId) slot — null = overall. A slot already occupied locally is
  /// left alone (merge is additive, never overwrites a budget the user has
  /// since changed).
  Future<void> _mergeBudgets(
    List<BackupBudget> backupBudgets,
    Map<int, int> categoryIdMap,
  ) async {
    final existing = await _db.select(_db.budgets).get();
    final byExternalId = <String, BudgetRow>{
      for (final b in existing)
        if (b.externalId != null) b.externalId!: b,
    };
    final occupiedSlots = <int?>{for (final b in existing) b.categoryId};

    final toInsert = <BudgetsCompanion>[];
    for (final b in backupBudgets) {
      if (b.externalId != null && byExternalId.containsKey(b.externalId)) {
        continue; // already present locally, matched by stable id
      }
      int? mappedCategoryId;
      if (b.categoryId != null) {
        mappedCategoryId = categoryIdMap[b.categoryId];
        if (mappedCategoryId == null) continue; // orphan safety net
      }
      if (!occupiedSlots.add(mappedCategoryId)) continue; // slot taken
      toInsert.add(b.toInsertCompanion(mappedCategoryId: mappedCategoryId));
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.budgets, toInsert));
    }
  }

  /// Matches by [BackupExpense.externalId] first, falling back to content
  /// fingerprint (amount, date, mapped category, note, payment method) for
  /// rows written before schema v7 or backup files that predate the field.
  ///
  /// A matched (already-present) expense's receipt is never touched, same as
  /// every other field on a match — merge only adds, never overwrites local
  /// state. Only a newly-inserted expense can gain a receipt from the backup,
  /// since there is no existing local one it could clash with.
  Future<void> _mergeExpenses(
    List<BackupExpense> backupExpenses,
    Map<int, int> categoryIdMap,
    Map<int, int> tagIdMap,
    Map<int, int> accountIdMap,
    List<BackupReceipt> backupReceipts,
  ) async {
    final existing = await _db.select(_db.expenses).get();
    final knownExternalIds = <String>{
      for (final e in existing)
        if (e.externalId != null) e.externalId!,
    };
    final fingerprints = <String>{
      for (final e in existing)
        BackupExpense.fromRow(e).fingerprint(mappedCategoryId: e.categoryId),
    };
    final receiptByExpenseId = <int, BackupReceipt>{
      for (final r in backupReceipts) r.expenseId: r,
    };

    final toInsert = <ExpensesCompanion>[];
    // Expenses whose backup entry carries a receipt: inserted individually
    // (not batched) so each one's assigned local id is known and the receipt
    // can be attached to the RIGHT row — a batch insert never reports back
    // the ids it assigned. Receipted expenses are expected to be the small
    // minority, so the common batched path stays fast for everything else.
    final toInsertWithReceipt = <(ExpensesCompanion, BackupReceipt)>[];
    for (final e in backupExpenses) {
      if (e.externalId != null && knownExternalIds.contains(e.externalId)) {
        continue; // already present locally, matched by stable id
      }
      final mappedCategoryId = categoryIdMap[e.categoryId];
      if (mappedCategoryId == null) continue; // orphan safety net
      final fp = e.fingerprint(mappedCategoryId: mappedCategoryId);
      if (!fingerprints.add(fp)) continue; // already present (or dup in file)
      final mappedTagId = e.tagId == null ? null : tagIdMap[e.tagId];
      final mappedAccountId = e.accountId == null
          ? null
          : accountIdMap[e.accountId];
      final companion = e.toInsertCompanion(
        mappedCategoryId: mappedCategoryId,
        mappedTagId: mappedTagId,
        mappedAccountId: mappedAccountId,
      );
      final receipt = receiptByExpenseId[e.id];
      if (receipt != null) {
        toInsertWithReceipt.add((companion, receipt));
      } else {
        toInsert.add(companion);
      }
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.expenses, toInsert));
    }
    for (final (companion, receipt) in toInsertWithReceipt) {
      final newId = await _db.into(_db.expenses).insert(companion);
      await _db
          .into(_db.expenseReceipts)
          .insert(
            ExpenseReceiptsCompanion.insert(
              expenseId: newId,
              photoBytes: base64Decode(receipt.photoBase64),
            ),
          );
    }
  }

  /// Matches by [BackupLedgerEntry.externalId] first, falling back to
  /// content fingerprint — same two-tier rule as [_mergeExpenses], for the
  /// same reason: a natural-key match (like categories/tags/accounts have by
  /// name) doesn't exist for a plain income entry.
  Future<void> _mergeLedgerEntries(
    List<BackupLedgerEntry> backupEntries,
    Map<int, int> accountIdMap,
  ) async {
    final existing = await _db.select(_db.ledgerEntries).get();
    final knownExternalIds = <String>{
      for (final e in existing)
        if (e.externalId != null) e.externalId!,
    };
    final fingerprints = <String>{
      for (final e in existing)
        BackupLedgerEntry.fromRow(
          e,
        ).fingerprint(mappedAccountId: e.accountId),
    };

    final toInsert = <LedgerEntriesCompanion>[];
    for (final e in backupEntries) {
      if (e.externalId != null && knownExternalIds.contains(e.externalId)) {
        continue; // already present locally, matched by stable id
      }
      final mappedAccountId = e.accountId == null
          ? null
          : accountIdMap[e.accountId];
      final fp = e.fingerprint(mappedAccountId: mappedAccountId);
      if (!fingerprints.add(fp)) continue; // already present (or dup in file)
      toInsert.add(e.toInsertCompanion(mappedAccountId: mappedAccountId));
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.ledgerEntries, toInsert));
    }
  }

  static String _normalize(String name) => name.trim().toLowerCase();
}
