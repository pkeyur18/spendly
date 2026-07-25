import 'dart:convert';
import 'dart:io';

import 'backup_format.dart';
import 'backup_models.dart';
import 'backup_repository.dart';

/// FR-40 choice — Merge adds to what's on-device, Replace wipes then
/// restores only from the backup.
enum RestoreMode { merge, replace }

/// Everything the restore-preview screen shows (FR-39): backup date, expense
/// count, date range, file size.
class BackupPreview {
  const BackupPreview({
    required this.payload,
    required this.fileName,
    required this.fileSizeBytes,
  });

  final BackupPayload payload;
  final String fileName;
  final int fileSizeBytes;

  DateTime get exportedAt => payload.exportedAt;
  int get expenseCount => payload.expenses.length;
  int get categoryCount => payload.categories.length;
  (DateTime, DateTime)? get expenseDateRange => payload.expenseDateRange;
}

/// Reads and fully validates a backup file before any database write happens
/// (FR-41). Propagates [BackupCorruptException] / [BackupVersionTooNewException]
/// / [BackupPasswordRequiredException] / [BackupWrongPasswordException]
/// untouched — the caller decides how to present each.
Future<BackupPreview> loadAndValidate(String path, {String? password}) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  final payload = await decodePayload(utf8.decode(bytes), password: password);
  return BackupPreview(
    payload: payload,
    fileName: path.split(Platform.pathSeparator).last,
    fileSizeBytes: bytes.length,
  );
}

Future<void> executeRestore(
  BackupPayload payload,
  RestoreMode mode,
  BackupRepository repo,
) {
  return switch (mode) {
    RestoreMode.merge => repo.mergeAll(payload),
    RestoreMode.replace => repo.replaceAll(payload),
  };
}
