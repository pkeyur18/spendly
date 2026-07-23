import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/features/backup/backup_crypto.dart';

void main() {
  test('AES-GCM round trip decrypts to the original plaintext', () async {
    const plaintext = '{"hello":"world","amountMinor":2450}';
    final blob = await encryptBackup(plaintext, 'correct horse');
    final decrypted = await decryptBackup(blob, 'correct horse');
    expect(decrypted, plaintext);
  });

  test('wrong password fails MAC verification distinctly', () async {
    final blob = await encryptBackup('secret payload', 'right password');
    expect(
      () => decryptBackup(blob, 'wrong password'),
      throwsA(isA<BackupWrongPasswordException>()),
    );
  });

  test('tampered ciphertext fails MAC verification', () async {
    final blob = await encryptBackup('secret payload', 'a password');
    final tampered = EncryptedBlob(
      kdfIterations: blob.kdfIterations,
      salt: blob.salt,
      nonce: blob.nonce,
      mac: blob.mac,
      ciphertext: Uint8List.fromList(blob.ciphertext.map((b) => b ^ 0xFF).toList()),
    );
    expect(
      () => decryptBackup(tampered, 'a password'),
      throwsA(isA<BackupWrongPasswordException>()),
    );
  });
}
