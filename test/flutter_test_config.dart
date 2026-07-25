import 'dart:async';

import 'package:drift/drift.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Tests intentionally open several independent in-memory AppDatabase
  // instances (source/fresh dbs for backup import-export scenarios); they
  // never share a QueryExecutor, so drift's multi-instance heuristic is a
  // false positive here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
