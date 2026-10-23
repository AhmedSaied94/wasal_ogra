import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Nothing of the retired «ستيكر الميكروباص» design is left in the app
// (specs/008.5-m21-design-refresh, spec SC-008): no file in lib/,
// pubspec.yaml or assets/ names its fonts, components, tokens, stand-in or
// M02's single Rive file, in its path or its text.

final _retired = RegExp(
  r'Lalezar|BalooBhaijaan2|StickerButton|StickerCard|PrimaryButton|'
  r'SecondaryButton|WassalBottomBar|StickerPage|StickerColors|StickerType|'
  r'StickerShape|StickerSpace|StickerMotion|StickerTokens|stickerTokens|'
  r'StandInPassenger|passenger\.riv|SkinLook',
);

/// Files whose text is read; the rest (fonts, images, Rive) by path only.
const _text = {'.dart', '.yaml', '.json', '.arb', '.svg', '.md', '.txt'};

/// Each retired name in [path] or its [text], as `path[:line]: name`.
List<String> _scan(String path, String? text) => [
  for (final match in _retired.allMatches(path)) '$path: ${match.group(0)}',
  if (text != null)
    for (final (i, line) in text.split('\n').indexed)
      for (final match in _retired.allMatches(line))
        '$path:${i + 1}: ${match.group(0)}',
];

Iterable<File> _files() sync* {
  yield File('pubspec.yaml');
  for (final dir in ['lib', 'assets']) {
    yield* Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.contains('/generated/'));
  }
}

String? _read(File file) {
  final dot = file.path.lastIndexOf('.');
  final ext = dot < 0 ? '' : file.path.substring(dot);
  return _text.contains(ext) ? file.readAsStringSync() : null;
}

void main() {
  test('lib/, pubspec.yaml and assets/ name nothing retired', () {
    final hits = [
      for (final file in _files())
        ..._scan(file.path.replaceAll(r'\', '/'), _read(file)),
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the scan catches what it should', () {
    expect(_scan('assets/fonts/Lalezar-Regular.ttf', null), [
      'assets/fonts/Lalezar-Regular.ttf: Lalezar',
    ]);
    expect(_scan('a.dart', 'x\nreturn PrimaryButton(label: l);'), [
      'a.dart:2: PrimaryButton',
    ]);
    expect(_scan('a.dart', '// M02 drew passenger.riv'), [
      'a.dart:1: passenger.riv',
    ]);
    expect(_scan('a.dart', 'AppButton.primary(label: l)'), isEmpty);
  });
}
