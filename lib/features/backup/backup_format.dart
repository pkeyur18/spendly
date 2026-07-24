import 'dart:convert';

import 'backup_crypto.dart';
import 'backup_models.dart';

export 'backup_crypto.dart' show BackupWrongPasswordException;

/// Envelope encode/decode (`docs/backup-schema.md`). No I/O here — callers
/// read/write the file. This is the FR-41 validation gate: [decodePayload]
/// either returns a fully-parsed [BackupPayload] or throws one of the
/// exceptions below, and always does so before any database write happens.
///
/// v2 (FR-56) added the optional `profilePhotoBase64` payload field — a v1
/// file simply lacks the key, which [BackupPayload.fromJson] already treats
/// as null, so no version-keyed decode branch is needed here.
const currentBackupVersion = 2;

class BackupCorruptException implements Exception {
  const BackupCorruptException(this.reason);
  final String reason;
  @override
  String toString() => 'This backup file could not be read: $reason';
}

class BackupVersionTooNewException implements Exception {
  const BackupVersionTooNewException(this.fileVersion);
  final int fileVersion;
  @override
  String toString() =>
      'This backup was made by a newer version of Spendly (format v$fileVersion) '
      'than this app supports (v$currentBackupVersion). Update the app to restore it.';
}

class BackupPasswordRequiredException implements Exception {
  const BackupPasswordRequiredException();
  @override
  String toString() => 'This backup is password-protected.';
}

/// The outer envelope's always-plaintext fields — readable, and safe to act
/// on, without ever asking for a password.
class BackupEnvelopeInfo {
  const BackupEnvelopeInfo({required this.version, required this.encrypted});
  final int version;
  final bool encrypted;
}

/// Builds the envelope JSON string. Encrypts [payload] when [password] is
/// non-null/non-empty; otherwise stores it in plain.
Future<String> encodeEnvelope(BackupPayload payload, {String? password}) async {
  final payloadJson = jsonEncode(payload.toJson());
  if (password == null || password.isEmpty) {
    return jsonEncode({
      'spendlyBackup': true,
      'version': currentBackupVersion,
      'encrypted': false,
      'data': payload.toJson(),
    });
  }
  final blob = await encryptBackup(payloadJson, password);
  return jsonEncode({
    'spendlyBackup': true,
    'version': currentBackupVersion,
    'encrypted': true,
    'kdf': 'PBKDF2-HMAC-SHA256',
    'kdfIterations': blob.kdfIterations,
    'salt': base64Encode(blob.salt),
    'nonce': base64Encode(blob.nonce),
    'mac': base64Encode(blob.mac),
    'cipher': 'AES-256-GCM',
    'ciphertext': base64Encode(blob.ciphertext),
  });
}

/// Parses just `spendlyBackup`/`version`/`encrypted` — never needs a
/// password, so an incompatible-future-version file is rejected before one
/// is ever requested.
BackupEnvelopeInfo peekEnvelope(String jsonText) {
  final envelope = _decodeEnvelopeMap(jsonText);
  final version = envelope['version'];
  if (version is! int) {
    throw const BackupCorruptException('missing or invalid "version" field');
  }
  if (version > currentBackupVersion) {
    throw BackupVersionTooNewException(version);
  }
  final encrypted = envelope['encrypted'];
  if (encrypted is! bool) {
    throw const BackupCorruptException('missing or invalid "encrypted" field');
  }
  return BackupEnvelopeInfo(version: version, encrypted: encrypted);
}

/// Full decode: peeks first (fails fast on a corrupt/incompatible file),
/// decrypts if needed (throws [BackupPasswordRequiredException] if
/// [password] is null for an encrypted file), then validates and parses the
/// payload shape. Throws before any DB access is ever attempted.
Future<BackupPayload> decodePayload(String jsonText, {String? password}) async {
  final envelope = _decodeEnvelopeMap(jsonText);
  peekEnvelope(jsonText); // re-validates version/encrypted, cheap and clear

  final String payloadJson;
  if (envelope['encrypted'] == true) {
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    payloadJson = await _decryptEnvelope(envelope, password);
  } else {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const BackupCorruptException('missing "data" payload');
    }
    payloadJson = jsonEncode(data);
  }

  try {
    final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
    return BackupPayload.fromJson(decoded);
  } catch (e) {
    throw BackupCorruptException('malformed backup contents ($e)');
  }
}

Future<String> _decryptEnvelope(
  Map<String, dynamic> envelope,
  String password,
) async {
  try {
    final blob = EncryptedBlob(
      kdfIterations: envelope['kdfIterations'] as int,
      salt: base64Decode(envelope['salt'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: base64Decode(envelope['mac'] as String),
      ciphertext: base64Decode(envelope['ciphertext'] as String),
    );
    return await decryptBackup(blob, password);
  } on BackupWrongPasswordException {
    rethrow;
  } catch (e) {
    throw BackupCorruptException('malformed encrypted container ($e)');
  }
}

Map<String, dynamic> _decodeEnvelopeMap(String jsonText) {
  Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } catch (e) {
    throw BackupCorruptException('not valid JSON ($e)');
  }
  if (decoded is! Map<String, dynamic> || decoded['spendlyBackup'] != true) {
    throw const BackupCorruptException('not a Spendly backup file');
  }
  return decoded;
}
