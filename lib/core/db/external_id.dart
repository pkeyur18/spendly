import 'dart:math';

/// A random UUID v4 used as a stable cross-device/cross-backup record
/// identity (`externalId` columns) — see `docs/backup-schema.md`. Hand-rolled
/// on `dart:math`'s `Random.secure()` rather than pulling in the `uuid`
/// package: this project deliberately keeps its dependency surface small,
/// and a UUID v4 is ~10 lines of stdlib.
String generateExternalId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx

  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
