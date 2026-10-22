import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/colors.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';

// Palette checks from contracts/design-tokens.md (FR-010, FR-011).

double _channel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.1 relative luminance.
double luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// CIE L* (D65), from relative luminance.
double lightness(Color c) {
  final y = luminance(c);
  return y > 216 / 24389
      ? 116 * math.pow(y, 1 / 3).toDouble() - 16
      : y * 24389 / 27;
}

double hue(Color c) => HSLColor.fromColor(c).hue;

double hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return math.min(d, 360 - d);
}

String hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  test('palette values are exactly the owner-approved hex codes', () {
    expect(hex(ColorTokens.shams), '#FFD23F');
    expect(hex(ColorTokens.hibr), '#1D1A2B');
    expect(hex(ColorTokens.waraq), '#FFFFFF');
    expect(hex(ColorTokens.tablouh), '#2A2633');
    expect(hex(ColorTokens.primary), '#1A4B8C');
    expect(hex(ColorTokens.danger), '#F2542D');
    expect(hex(ColorTokens.gold), '#F5B301');
    expect(hex(ColorTokens.station1), '#3B2A6B');
    expect(hex(ColorTokens.station2), '#0F766E');
    expect(hex(ColorTokens.station3), '#5FAE4E');
    expect(hex(ColorTokens.station4), '#A9DDF3');
    expect(ColorTokens.badgeNew, ColorTokens.danger);
    // The trip screen's tokens (specs/008-m02-trip-screen, research R17).
    expect(hex(ColorTokens.fare), '#7ACC6C');
    expect(hex(ColorTokens.bubbleWarn), '#FFD9A8');
    expect(hex(ColorTokens.bubbleFight), '#F2894A');
    expect(hex(ColorTokens.bubbleThanks), '#BFE3F7');
    expect(hex(ColorTokens.shirtEffendi), '#8A8F99');
    expect(hex(ColorTokens.shirtStudent), '#EDF1F5');
    expect(hex(ColorTokens.shirtWorker), '#24508F');
    expect(hex(ColorTokens.shirtHajja), '#2B2633');
    expect(hex(ColorTokens.shirtYoung), '#C23B2E');
    expect(hex(ColorTokens.shirtPlain), '#D9C9A3');
    for (final c in ColorTokens.all) {
      expect(c.a, 1.0, reason: 'tokens are opaque');
    }
  });

  test('colors that must be told apart differ by ΔL* ≥ 18', () {
    final stations = ColorTokens.stations.map((s) => s.fill).toList();
    final pairs = <(Color, Color)>[
      for (var i = 0; i < stations.length; i++)
        for (var j = i + 1; j < stations.length; j++)
          (stations[i], stations[j]),
      (ColorTokens.primary, ColorTokens.danger),
      // A fare on its way and change on its way (research R17).
      (ColorTokens.fare, ColorTokens.primary),
      // A warning bubble and a fight bubble.
      (ColorTokens.bubbleWarn, ColorTokens.bubbleFight),
    ];
    for (final (a, b) in pairs) {
      expect(
        (lightness(a) - lightness(b)).abs(),
        greaterThanOrEqualTo(18),
        reason: '${hex(a)} vs ${hex(b)}',
      );
    }
  });

  test('every text-on-fill pair the app uses meets WCAG AA (4.5:1)', () {
    final pairs = <(Color text, Color fill)>[
      (ColorTokens.hibr, ColorTokens.shams),
      (ColorTokens.hibr, ColorTokens.waraq),
      (ColorTokens.waraq, ColorTokens.primary),
      (ColorTokens.waraq, ColorTokens.tablouh),
      (ColorTokens.shams, ColorTokens.tablouh),
      (ColorTokens.hibr, ColorTokens.danger),
      (ColorTokens.hibr, ColorTokens.gold),
      for (final s in ColorTokens.stations) (s.letter, s.fill),
      // The amount on a fare token, and the text of each bubble style.
      (ColorTokens.hibr, ColorTokens.fare),
      (ColorTokens.hibr, ColorTokens.bubbleWarn),
      (ColorTokens.hibr, ColorTokens.bubbleFight),
      (ColorTokens.hibr, ColorTokens.bubbleThanks),
    ];
    for (final (text, fill) in pairs) {
      expect(
        contrast(text, fill),
        greaterThanOrEqualTo(4.5),
        reason: '${hex(text)} on ${hex(fill)}',
      );
    }
  });

  test('shirts that look alike otherwise differ by ΔL* ≥ 18', () {
    const tokens = WassalTokens.standard;
    final pairs = shirtPairsToSeparate();
    expect(pairs, isNotEmpty);
    for (final (a, b) in pairs) {
      final ca = shirtColor(tokens, a);
      final cb = shirtColor(tokens, b);
      expect(
        (lightness(ca) - lightness(cb)).abs(),
        greaterThanOrEqualTo(18),
        reason: '$a ${hex(ca)} vs $b ${hex(cb)}',
      );
    }
  });

  test('every shirt has its own token', () {
    const tokens = WassalTokens.standard;
    final colors = {for (final s in Shirt.values) shirtColor(tokens, s)};
    expect(colors, hasLength(Shirt.values.length));
    expect(colors.every(ColorTokens.all.contains), isTrue);
  });

  test('station letters: white on stations 1–2, ink on stations 3–4', () {
    const s = ColorTokens.stations;
    expect(s, hasLength(4));
    expect(s[0].fill, ColorTokens.station1);
    expect(s[1].fill, ColorTokens.station2);
    expect(s[2].fill, ColorTokens.station3);
    expect(s[3].fill, ColorTokens.station4);
    expect(s[0].letter, ColorTokens.waraq);
    expect(s[1].letter, ColorTokens.waraq);
    expect(s[2].letter, ColorTokens.hibr);
    expect(s[3].letter, ColorTokens.hibr);
  });

  test('the «new» dot reaches 3:1 by fill or outline on every background', () {
    for (final bg in [
      ColorTokens.tablouh,
      ColorTokens.shams,
      ColorTokens.waraq,
    ]) {
      final best = math.max(
        contrast(ColorTokens.badgeNew, bg),
        contrast(ColorTokens.hibr, bg),
      );
      expect(best, greaterThanOrEqualTo(3), reason: 'on ${hex(bg)}');
    }
  });

  test('no station color reuses the danger hue (≥ 30° apart)', () {
    final dangerHue = hue(ColorTokens.danger);
    for (final s in ColorTokens.stations) {
      expect(
        hueDistance(hue(s.fill), dangerHue),
        greaterThanOrEqualTo(30),
        reason: hex(s.fill),
      );
    }
  });

  test('the old ux-spec blue would fail the danger lightness gap', () {
    // Guards the check itself: #1F5FA8 is only ΔL* 17.4 from danger.
    const oldBlue = Color(0xFF1F5FA8);
    expect(
      (lightness(oldBlue) - lightness(ColorTokens.danger)).abs(),
      lessThan(18),
    );
  });
}
