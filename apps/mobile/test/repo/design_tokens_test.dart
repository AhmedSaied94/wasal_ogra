import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/design/token_generator.dart';

// The committed tokens equal what docs/design/tokens.json generates
// (specs/008.5-m21-design-refresh, contracts/design-tokens.md "Generation").

const _committed = 'lib/core/theme/tokens/design_tokens.dart';

void main() {
  test('design_tokens.dart is generated from docs/design/tokens.json', () {
    final json = jsonDecode(
      File('../../docs/design/tokens.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final want = formatTokens(generateTokens(json)).split('\n');
    // Formatted again, so a newer `dart format` can't fail the check.
    final have = formatTokens(File(_committed).readAsStringSync()).split('\n');
    for (var i = 0; i < want.length || i < have.length; i++) {
      final w = i < want.length ? want[i] : '<end of file>';
      final h = i < have.length ? have[i] : '<end of file>';
      if (w != h) {
        fail(
          '$_committed differs from docs/design/tokens.json at line '
          '${i + 1}:\n  generated: $w\n  committed: $h\n'
          'Run: fvm dart run tool/design/gen_tokens.dart',
        );
      }
    }
  });
}
