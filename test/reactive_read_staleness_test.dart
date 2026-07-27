import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards docs/known-issues.md push-back #1 (reactive-read staleness after a
/// write): a Riverpod provider that wraps Drift query data — a
/// `StreamProvider`, a `FutureProvider`, or a plain `Provider` derived from
/// `ref.watch(otherProvider).value` — must only be consumed via `ref.watch()`
/// inside a widget's reactive build. `ref.read()` on one of these serves
/// neither legitimate need: live reactivity (use `ref.watch` in build) or a
/// guaranteed-current value for post-write logic (issue a fresh one-shot
/// repository read, as `widget_refresh.dart` does) — and is exactly the shape
/// of three previously-shipped bugs (`ff334a2`, `dd6724f`, `3f52b18`), plus a
/// fourth found live in `quick_add_screen.dart` while writing this test.
///
/// Source-scanning regex, not a real analyzer pass (see docs/known-issues.md
/// #4 for why a real lint plugin isn't a quick win here) — same style as
/// `migration_test.dart`. A provider name it hasn't seen defaults to "safe"
/// (no false positives on repo/service instances); a real violation always
/// names a provider declared with one of the four kinds below.
///
/// A `ref.read()` that inspects a provider's *currently-rendered* value for
/// something other than post-write correctness (e.g. pagination bookkeeping,
/// "what colors are already in use") is a reviewed exception, not a bug —
/// mark it with a `// staleness-ok: <reason>` comment on the line above the
/// read, the same way an `// ignore:` comment documents a lint suppression.
void main() {
  test('no ref.read() of a data-backed provider', () {
    final files = Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where(
      (f) => f.path.endsWith('.dart'),
    );
    final contentsByFile = {for (final f in files) f.path: f.readAsStringSync()};

    final declRegex = RegExp(
      r'final\s+(_?[A-Za-z][A-Za-z0-9_]*)\s*=\s*'
      r'(StreamProvider|FutureProvider|NotifierProvider|AsyncNotifierProvider|Provider)\b',
    );
    final derivedFromStreamRegex = RegExp(r'\.watch\(.*?\)\.value', dotAll: true);
    final readRegex = RegExp(r'ref\s*\.\s*read\(\s*([A-Za-z_][A-Za-z0-9_]*)');

    final dataProviders = <String>{};
    for (final content in contentsByFile.values) {
      final decls = declRegex.allMatches(content).toList();
      for (var i = 0; i < decls.length; i++) {
        final name = decls[i].group(1)!;
        final kind = decls[i].group(2)!;
        final bodyEnd = i + 1 < decls.length ? decls[i + 1].start : content.length;
        final body = content.substring(decls[i].end, bodyEnd);
        final isDataProvider = switch (kind) {
          'StreamProvider' || 'FutureProvider' => true,
          'NotifierProvider' || 'AsyncNotifierProvider' => false,
          _ => derivedFromStreamRegex.hasMatch(body),
        };
        if (isDataProvider) dataProviders.add(name);
      }
    }

    final violations = <String>[];
    contentsByFile.forEach((path, content) {
      final lines = content.split('\n');
      for (final match in readRegex.allMatches(content)) {
        final name = match.group(1)!;
        if (!dataProviders.contains(name)) continue;
        final lineIndex = '\n'.allMatches(content.substring(0, match.start)).length;
        final nearby = lineIndex > 0
            ? '${lines[lineIndex - 1]}\n${lines[lineIndex]}'
            : lines[lineIndex];
        if (nearby.contains('staleness-ok:')) continue;
        violations.add('$path:${lineIndex + 1} reads "$name" via ref.read()');
      }
    });

    expect(
      violations,
      isEmpty,
      reason:
          'ref.read() on a data-backed provider can return data from before '
          'the write that just happened (docs/architecture.md §8.1). Use '
          'ref.watch() in a widget build for live UI, or a fresh one-shot '
          'repository read (see refreshWidgets() in widget_refresh.dart) for '
          'post-write logic — never ref.read() the provider itself:\n'
          '${violations.join('\n')}',
    );
  });
}
