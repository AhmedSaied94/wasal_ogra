import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../helpers/color_math.dart';
import '../../helpers/dart_source.dart';

// The «كرتون ناعم» palette checks (specs/008.5-m21-design-refresh,
// contracts/design-tokens.md "Palette checks", research R21).

const _white = ColorTokens.paper;

void _expectContrast(List<(Color text, Color fill)> pairs, double minimum) {
  for (final (text, fill) in pairs) {
    expect(
      contrast(text, fill),
      greaterThanOrEqualTo(minimum),
      reason: '${hex(text)} on ${hex(fill)}',
    );
  }
}

/// A danger or sun fill and white text in one expression, either order.
final _whiteOnWarm = [
  RegExp(
    r'(fill|background|bg):\s*ColorTokens\.(danger|dangerSoft|sun|sunSoft)\b'
    r'[^;{}]{0,240}?(text|ink|foreground|fg|label):\s*'
    r'(ColorTokens\.paper|Colors\.white)\b',
  ),
  RegExp(
    r'(text|ink|foreground|fg|label):\s*(ColorTokens\.paper|Colors\.white)\b'
    r'[^;{}]{0,240}?(fill|background|bg):\s*'
    r'ColorTokens\.(danger|dangerSoft|sun|sunSoft)\b',
  ),
];

List<String> _scanWhiteOnWarm(String path, String source) => [
  for (final rule in _whiteOnWarm)
    for (final match in rule.allMatches(stripComments(source)))
      '$path: ${match.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}',
];

void main() {
  test('every text colour on its fill meets WCAG AA (4.5:1)', () {
    const stations = StationColors.all;
    _expectContrast([
      for (final text in [
        ColorTokens.ink,
        ColorTokens.ink2,
        ColorTokens.inkMuted,
      ])
        for (final fill in [
          ColorTokens.paper,
          ColorTokens.ground,
          ColorTokens.lockedBg,
          ColorTokens.track,
        ])
          (text, fill),
      for (final fill in [
        ColorTokens.primary,
        ColorTokens.primaryLip,
        ColorTokens.dashboardBg,
        stations[0].bg,
        stations[1].bg,
      ])
        (_white, fill),
      for (final fill in [
        ColorTokens.sun,
        ColorTokens.sunSoft,
        ColorTokens.danger,
        ColorTokens.dangerSoft,
        ColorTokens.primarySoft,
        stations[2].bg,
        stations[3].bg,
      ])
        (ColorTokens.ink, fill),
      (ColorTokens.primary, ColorTokens.primarySoft),
      (ColorTokens.primary, ColorTokens.paper),
      (ColorTokens.dangerInk, ColorTokens.paper),
      for (final text in [
        ColorTokens.dashboardText,
        ColorTokens.dashboardMuted,
      ])
        for (final fill in [
          ColorTokens.dashboardBg,
          ColorTokens.dashboardRaised,
        ])
          (text, fill),
      (ColorTokens.noteFareText, ColorTokens.noteFare),
      (ColorTokens.noteChangeText, ColorTokens.noteChange),
      (ColorTokens.noteBlockedText, ColorTokens.noteBlocked),
      (ColorTokens.noteInHandText, ColorTokens.noteInHand),
      for (final s in stations) (s.letter, s.bg),
    ], 4.5);
  });

  test('display text (Marhey ≥ 18 bold) reaches 3:1 on its background', () {
    _expectContrast([
      (ColorTokens.ink, ColorTokens.ground),
      (ColorTokens.primary, ColorTokens.ground),
      (_white, ColorTokens.primary),
      (ColorTokens.ink, ColorTokens.sun),
      (ColorTokens.ink, ColorTokens.danger),
      (ColorTokens.dangerInk, ColorTokens.paper),
      (_white, ColorTokens.dashboardBg),
      (ColorTokens.sun, ColorTokens.ink),
    ], 3);
  });

  test('danger.ink on danger.soft is too faint for text', () {
    // The reason no component draws that pair (contracts/design-tokens.md).
    expect(
      contrast(ColorTokens.dangerInk, ColorTokens.dangerSoft),
      lessThan(4.5),
    );
  });

  test('colours that must be told apart differ by ΔL* ≥ 18', () {
    final stations = [for (final s in StationColors.all) s.bg];
    expect(stations, hasLength(4));
    final pairs = <(Color, Color)>[
      for (var i = 0; i < stations.length; i++)
        for (var j = i + 1; j < stations.length; j++)
          (stations[i], stations[j]),
      (ColorTokens.primary, ColorTokens.danger),
    ];
    for (final (a, b) in pairs) {
      expect(
        (lightness(a) - lightness(b)).abs(),
        greaterThanOrEqualTo(18),
        reason: '${hex(a)} vs ${hex(b)}',
      );
    }
  });

  test('station letters: white on stations 1–2, ink on 3–4', () {
    const s = StationColors.all;
    expect(
      [for (final x in s) x.letter],
      [_white, _white, ColorTokens.ink, ColorTokens.ink],
    );
  });

  test('every type style is at least 12 pt with even leading', () {
    for (final style in TypeTokens.all) {
      expect(style.fontSize, greaterThanOrEqualTo(12));
      expect(style.leadingDistribution, TextLeadingDistribution.even);
      expect(style.color, isNull, reason: 'colour comes from ColorTokens');
    }
  });

  test('no white text on a danger or sun fill in components and the trip', () {
    final hits = <String>[
      for (final dir in [
        'lib/core/theme/components',
        'lib/features/trip/presentation',
      ])
        if (Directory(dir).existsSync())
          for (final file
              in Directory(dir)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart')))
            ..._scanWhiteOnWarm(file.path, file.readAsStringSync()),
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the white-on-warm scan catches what it should', () {
    expect(
      _scanWhiteOnWarm(
        'a.dart',
        'const p = _Palette(fill: ColorTokens.danger, text: ColorTokens.paper);',
      ),
      hasLength(1),
    );
    expect(
      _scanWhiteOnWarm(
        'a.dart',
        'Pill(text: Colors.white,\n  bg: ColorTokens.sun)',
      ),
      hasLength(1),
    );
    expect(
      _scanWhiteOnWarm(
        'a.dart',
        'const p = _Palette(fill: ColorTokens.danger, text: ColorTokens.ink);',
      ),
      isEmpty,
    );
    expect(
      _scanWhiteOnWarm(
        'a.dart',
        'const p = _Palette(fill: ColorTokens.primary, text: ColorTokens.paper);',
      ),
      isEmpty,
    );
  });
}
