// Determinism (constitution I, research R1): time is the caller's step count
// and the PRNG is seeded, so the engine never reads a clock, a random source,
// the file system or anything asynchronous.
import 'package:test/test.dart';

import 'source_scan.dart';

final _forbiddenWords = <String, RegExp>{
  for (final word in ['DateTime', 'Stopwatch', 'Random', 'Future'])
    word: RegExp('\\b$word\\b'),
};

const _forbiddenLibraries = ['dart:io', 'dart:async'];

List<String> _violations(String source) => [
  for (final MapEntry(:key, :value) in _forbiddenWords.entries)
    if (value.hasMatch(stripped(source, strings: false))) key,
  for (final library in _forbiddenLibraries)
    if (directiveUris(source).contains(library)) library,
];

void main() {
  test('the guard catches each forbidden form', () {
    expect(_violations('final now = DateTime.now();'), ['DateTime']);
    expect(_violations('final r = Random(1);'), ['Random']);
    expect(_violations("import 'dart:io';"), ['dart:io']);
    expect(_violations("import 'dart:async';\nFuture<void> f() async {}"), [
      'Future',
      'dart:async',
    ]);
    expect(_violations("// DateTime\nfinal s = 'Stopwatch';"), isEmpty);
  });

  for (final file in libSources()) {
    test('${file.path} reads no clock or random source', () {
      expect(_violations(file.readAsStringSync()), isEmpty);
    });
  }
}
