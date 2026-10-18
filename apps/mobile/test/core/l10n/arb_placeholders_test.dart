import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Numbers in ARB messages come preformatted (contracts/number-format.md):
// an int, num or double placeholder may only pick a plural or select form.

List<String> numericPlaceholdersPrinted(Map<String, dynamic> arb) {
  final violations = <String>[];
  for (final MapEntry(:key, :value) in arb.entries) {
    if (key.startsWith('@') || value is! String) continue;
    final meta = arb['@$key'];
    final placeholders = meta is Map ? meta['placeholders'] : null;
    if (placeholders is! Map) continue;
    for (final MapEntry(key: name, value: spec) in placeholders.entries) {
      final type = spec is Map ? spec['type'] : null;
      if (!const {'int', 'num', 'double'}.contains(type)) continue;
      // `{n}` prints the number; `{n, plural, …}` only selects a form.
      if (RegExp('\\{\\s*$name\\s*\\}').hasMatch(value)) {
        violations.add('$key prints {$name} ($type)');
      }
    }
  }
  return violations;
}

void main() {
  test('app_ar.arb prints no raw numeric placeholder', () {
    final arb = jsonDecode(
      File('lib/l10n/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final violations = numericPlaceholdersPrinted(arb);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches a printed number and allows a selector', () {
    expect(
      numericPlaceholdersPrinted({
        'bad': '{count} محطات',
        '@bad': {
          'placeholders': {
            'count': {'type': 'int'},
          },
        },
      }),
      ['bad prints {count} (int)'],
    );
    expect(
      numericPlaceholdersPrinted({
        'good': '{n, plural, =1{{count} محطة} other{{count} محطات}}',
        '@good': {
          'placeholders': {
            'n': {'type': 'int'},
            'count': {'type': 'String'},
          },
        },
      }),
      isEmpty,
    );
  });
}
