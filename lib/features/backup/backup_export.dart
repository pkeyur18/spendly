import 'dart:convert';
import 'dart:typed_data';

import '../../core/db/providers.dart';
import '../reports/report_export.dart' show shareReportFile;
import 'backup_format.dart';
import 'backup_repository.dart';

/// Builds the backup file bytes (FR-33, FR-34) — plain, or password-encrypted
/// per [password]. Pure I/O-free logic, so it's directly reusable by both the
/// manual "Back up now" share flow and the silent auto-backup writer.
Future<Uint8List> buildBackupBytes(
  BackupRepository repo, {
  String? password,
}) async {
  final payload = await repo.exportAll();
  final envelopeJson = await encodeEnvelope(payload, password: password);
  return Uint8List.fromList(utf8.encode(envelopeJson));
}

/// Manual "Back up now" (FR-36): build the file, hand it to the OS
/// share/save sheet (FR-35 — iCloud Drive, Google Drive, Files), then record
/// last-backup status (FR-42). Reuses the exact share mechanism Sprint 4
/// already built for report export — no reason to duplicate it.
Future<void> shareBackupFile(
  BackupRepository repo,
  SettingsRepository settings, {
  String? password,
}) async {
  final bytes = await buildBackupBytes(repo, password: password);
  final filename = 'spendly-backup-${_dateStamp(DateTime.now())}.json';
  await shareReportFile(
    bytes: bytes,
    filename: filename,
    text: 'Spendly backup',
  );
  await _recordBackupStatus(settings, bytes.length);
}

Future<void> _recordBackupStatus(
  SettingsRepository settings,
  int sizeBytes,
) async {
  await settings.set(
    SettingsRepository.lastBackupAtKey,
    DateTime.now().toIso8601String(),
  );
  await settings.set(
    SettingsRepository.lastBackupSizeKey,
    sizeBytes.toString(),
  );
}

String _dateStamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
