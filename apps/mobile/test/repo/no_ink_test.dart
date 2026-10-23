import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// No Material ink or stock buttons in the app (specs/008.5-m21-design-refresh,
// contracts/components.md "Rules"): every control presses its lip through
// Pressable, and messages use AppToast, never a SnackBar.

final _banned = RegExp(
  r'\b(InkWell|InkResponse|ElevatedButton|TextButton|OutlinedButton|'
  r'FilledButton|SnackBar)\b',
);

/// Files still allowed to use a banned name, until their task moves them.
const _allowed = <String>{};

/// Each banned use in [source], as `path:line: name`.
List<String> _scan(String path, String source) {
  final hits = <String>[];
  final lines = stripComments(source).split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final match in _banned.allMatches(lines[i])) {
      hits.add('$path:${i + 1}: ${match.group(0)}');
    }
  }
  return hits;
}

void main() {
  test('lib/ uses no Material ink, stock buttons or snack bars', () {
    final hits = <String>[
      for (final file in libDartFiles())
        if (!_allowed.contains(file.path.replaceAll(r'\', '/')))
          ..._scan(file.path, file.readAsStringSync()),
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the scan catches what it should', () {
    expect(_scan('a.dart', 'return InkWell(onTap: f);'), ['a.dart:1: InkWell']);
    expect(_scan('a.dart', 'x\nshowSnackBar(SnackBar(content: t));'), [
      'a.dart:2: SnackBar',
    ]);
    expect(_scan('a.dart', '// an InkWell in a comment'), isEmpty);
    expect(_scan('a.dart', 'Pressable(onTap: f)'), isEmpty);
  });
}
