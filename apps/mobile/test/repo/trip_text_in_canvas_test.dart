import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// Text is never drawn in the trip's canvas (specs/008-m02-trip-screen,
// research R3, contracts/ci-checks.md): bubbles, «آخر كلام», labels and the
// amount on every money token are Flutter widgets over the Flame scene, so
// they get the theme's fonts, the digit setting, scaling and semantics.
const _scene = 'lib/features/trip/presentation/scene/';

final _canvasText = RegExp(
  r'\b(?:TextPainter|TextComponent|TextBoxComponent|TextSpan)\b',
);

/// Lines of [source] that draw text, comments excluded.
List<String> canvasText(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_canvasText.hasMatch(lines[i])) '${i + 1}: ${lines[i].trim()}',
  ];
}

void main() {
  test('the trip scene draws no text', () {
    final dir = Directory(_scene);
    expect(dir.existsSync(), isTrue, reason: '$_scene must exist');
    final violations = [
      for (final file in dir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart'))
          for (final hit in canvasText(file.readAsStringSync()))
            '${file.path}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches text drawing and ignores the rest', () {
    expect(canvasText('final p = TextPainter(text: t);'), hasLength(1));
    expect(canvasText('add(TextComponent(text: a));'), hasLength(1));
    expect(canvasText('TextBoxComponent(text: a)'), hasLength(1));
    expect(canvasText("const s = TextSpan(text: 'x');"), hasLength(1));
    expect(canvasText('// a TextPainter would break the rule'), isEmpty);
    expect(canvasText('final contextPainter = 1;'), isEmpty);
  });
}
