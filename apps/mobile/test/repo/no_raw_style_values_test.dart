import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// No screen uses a non-token color or radius (FR-005, FR-006). Values live
// only in lib/core/theme/tokens/.

final _rules = <String, RegExp>{
  'literal Color': RegExp(r'Color\(0x'),
  'Material Colors palette': RegExp(r'\bColors\.(?!transparent\b)'),
  'numeric radius': RegExp(r'BorderRadius\.circular\(\s*[0-9.]'),
};

const _excluded = ['lib/core/theme/tokens/', 'lib/l10n/generated/'];

void main() {
  test('lib/ holds no raw colors or radii outside the tokens', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) =>
              !_excluded.any((e) => f.path.replaceAll(r'\', '/').startsWith(e)),
        );

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        for (final MapEntry(key: rule, value: pattern) in _rules.entries) {
          if (pattern.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: $rule: $line');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches what it should', () {
    expect(
      _rules['literal Color']!.hasMatch('color: Color(0xFF000000),'),
      isTrue,
    );
    expect(_rules['Material Colors palette']!.hasMatch('Colors.red'), isTrue);
    expect(
      _rules['Material Colors palette']!.hasMatch('Colors.transparent'),
      isFalse,
    );
    expect(
      _rules['numeric radius']!.hasMatch('BorderRadius.circular(12)'),
      isTrue,
    );
    expect(
      _rules['numeric radius']!.hasMatch(
        'BorderRadius.circular(ShapeTokens.radiusCard)',
      ),
      isFalse,
    );
  });
}
