import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// No player-visible Arabic in lib/ (FR-042): player text lives in the ARB
// files. Comments are skipped; they are not player-visible, and domain
// terms such as الموقف keep them precise.

final _arabic = RegExp('[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');

/// `line: text` for every line of [source] with Arabic outside comments.
List<String> arabicOutsideComments(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_arabic.hasMatch(lines[i])) '${i + 1}: ${lines[i].trim()}',
  ];
}

void main() {
  test('lib/ has no Arabic outside comments and generated l10n', () {
    final violations = [
      for (final file in libDartFiles())
        for (final hit in arabicOutsideComments(file.readAsStringSync()))
          '${file.path}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches Arabic in code and skips comments', () {
    expect(arabicOutsideComments("final s = 'ا';"), ['1: final s = \'ا\';']);
    expect(
      arabicOutsideComments('final s = "x";\nfinal t = "يلا";'),
      hasLength(1),
    );
    expect(arabicOutsideComments("const s = '''\nسطر\n''';"), ['2: سطر']);
    expect(arabicOutsideComments('final n = 3; // الموقف'), isEmpty);
    expect(arabicOutsideComments('/// الموقف\nclass A {}'), isEmpty);
    expect(
      arabicOutsideComments('/* الموقف\n * الخطوط */ int a = 1;'),
      isEmpty,
    );
    expect(arabicOutsideComments("final url = 'https://x.y'; // ا"), isEmpty);
    expect(arabicOutsideComments("final s = 'a // ب';"), hasLength(1));
    // Arabic-Indic digits and presentation forms count too.
    expect(arabicOutsideComments("final d = '١';"), hasLength(1));
    expect(arabicOutsideComments("final d = 'ﻻ';"), hasLength(1));
  });
}
