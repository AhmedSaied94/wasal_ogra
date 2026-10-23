import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// No screen uses a non-token color, radius, font size, shadow, duration or
// curve (FR-005, FR-006; specs/008.5-m21-design-refresh SC-002). Values
// live only in lib/core/theme/tokens/; the trip's named motion constants
// in trip_motion.dart are named, not inline.

/// Everywhere in lib/.
final _rules = <String, RegExp>{
  'literal Color': RegExp(r'Color\(0x'),
  'Material Colors palette': RegExp(r'\bColors\.(?!transparent\b)'),
  'numeric radius': RegExp(r'(Border)?Radius\.circular\(\s*[0-9.]'),
};

/// In UI code ([_ui]) as well.
final _uiRules = <String, RegExp>{
  'numeric font size': RegExp(r'fontSize:\s*[0-9.]'),
  'literal shadow': RegExp(r'BoxShadow\('),
  'literal animation duration': RegExp(r'duration:\s*(const\s+)?Duration\('),
  'literal curve': RegExp(r'curve:\s*Curves\.'),
};

const _excluded = ['lib/core/theme/tokens/', 'lib/l10n/generated/'];

final _ui = RegExp(
  r'^lib/(core/theme/components/|core/routing/|features/[^/]+/presentation/|'
  r'features/boot/|features/settings/|features/dev/)',
);

const _namedMotion = 'lib/features/trip/presentation/trip_motion.dart';

/// Each rule [line] of [path] breaks.
List<String> _scan(String path, String line) {
  final code = line.trimLeft();
  if (code.startsWith('//')) return const [];
  final ui = _ui.hasMatch(path) && path != _namedMotion;
  return [
    for (final MapEntry(key: rule, value: pattern) in {
      ..._rules,
      if (ui) ..._uiRules,
    }.entries)
      if (pattern.hasMatch(code)) rule,
  ];
}

void main() {
  test('lib/ holds no raw style values outside the tokens', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (file: f, path: f.path.replaceAll(r'\', '/')))
        .where((f) => !_excluded.any(f.path.startsWith));

    for (final (:file, :path) in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final rule in _scan(path, lines[i])) {
          violations.add('$path:${i + 1}: $rule: ${lines[i].trim()}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches what it should', () {
    const ui = 'lib/features/trip/presentation/x.dart';
    const core = 'lib/core/economy/x.dart';
    expect(_scan(core, 'color: Color(0xFF000000),'), ['literal Color']);
    expect(_scan(core, 'Colors.red'), ['Material Colors palette']);
    expect(_scan(core, 'Colors.transparent'), isEmpty);
    expect(_scan(core, 'BorderRadius.circular(12)'), ['numeric radius']);
    expect(_scan(core, 'Radius.circular(8)'), ['numeric radius']);
    expect(_scan(core, 'BorderRadius.circular(RadiusTokens.s)'), isEmpty);
    expect(_scan(ui, 'style: TextStyle(fontSize: 14),'), ['numeric font size']);
    expect(_scan(ui, 'BoxShadow(offset: o, color: c)'), ['literal shadow']);
    expect(_scan(ui, 'duration: const Duration(milliseconds: 200),'), [
      'literal animation duration',
    ]);
    expect(_scan(ui, 'curve: Curves.easeOut,'), ['literal curve']);
    expect(_scan(ui, 'duration: MotionTokens.press,'), isEmpty);
    expect(_scan(ui, '// duration: Duration(seconds: 1)'), isEmpty);
    expect(_scan(core, 'fontSize: 14'), isEmpty, reason: 'not UI code');
    expect(_scan(_namedMotion, 'curve: Curves.linear'), isEmpty);
  });
}
