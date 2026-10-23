import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

// Colour maths for the palette checks (M03 contracts/design-tokens.md,
// specs/008.5-m21-design-refresh research R21).

double _channel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.1 relative luminance.
double luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.1 contrast ratio.
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
