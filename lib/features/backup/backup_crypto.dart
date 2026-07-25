import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM with a PBKDF2-derived key, for the optional password-protected
/// backup (open Q6). No key/password is ever stored — only `salt` and
/// `kdfIterations` travel with the encrypted envelope so decrypt can
/// re-derive the same key from a password the user re-enters.
const kdfIterations = 200000;

class BackupWrongPasswordException implements Exception {
  const BackupWrongPasswordException();
  @override
  String toString() => 'Incorrect password — could not unlock this backup.';
}

/// The AES-GCM output plus the parameters needed to reverse it, matching the
/// encrypted envelope fields in `docs/backup-schema.md`.
class EncryptedBlob {
  const EncryptedBlob({
    required this.kdfIterations,
    required this.salt,
    required this.nonce,
    required this.mac,
    required this.ciphertext,
  });

  final int kdfIterations;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List mac;
  final Uint8List ciphertext;
}

Future<EncryptedBlob> encryptBackup(
  String plaintextJson,
  String password,
) async {
  final salt = _randomBytes(16);
  final key = await _deriveKey(password, salt, kdfIterations);
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(plaintextJson),
    secretKey: key,
  );
  return EncryptedBlob(
    kdfIterations: kdfIterations,
    salt: salt,
    nonce: Uint8List.fromList(box.nonce),
    mac: Uint8List.fromList(box.mac.bytes),
    ciphertext: Uint8List.fromList(box.cipherText),
  );
}

/// Throws [BackupWrongPasswordException] if [password] doesn't match — the
/// GCM tag check fails distinctly from a generic parse error.
Future<String> decryptBackup(EncryptedBlob blob, String password) async {
  final key = await _deriveKey(password, blob.salt, blob.kdfIterations);
  final box = SecretBox(blob.ciphertext, nonce: blob.nonce, mac: Mac(blob.mac));
  try {
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw const BackupWrongPasswordException();
  }
}

Future<SecretKey> _deriveKey(String password, List<int> salt, int iterations) {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  return pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
}

final _random = Random.secure();

Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
