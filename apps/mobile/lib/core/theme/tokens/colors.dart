import 'package:material_ui/material_ui.dart';

/// The «ستيكر الميكروباص» palette (contracts/design-tokens.md). It supersedes
/// the ux-spec «الألوان» table. A new color or a new text-on-fill pairing must
/// be added to the contract and to `palette_test.dart` in the same change.
abstract final class ColorTokens {
  /// شمس: screen background and launch background.
  static const shams = Color(0xFFFFD23F);

  /// حبر: borders, text, hard shadows, dark station letters.
  static const hibr = Color(0xFF1D1A2B);

  /// ورق: cards, bubbles, light station letters, text on dark fills.
  static const waraq = Color(0xFFFFFFFF);

  /// تابلوه: dashboard and bottom-bar background.
  static const tablouh = Color(0xFF2A2633);

  /// أزرق: primary buttons, exact money, progress.
  static const primary = Color(0xFF1A4B8C);

  /// برتقالي: danger. Text on it is [hibr]; white fails contrast.
  static const danger = Color(0xFFF2542D);

  /// ذهبي: coins and stars.
  static const gold = Color(0xFFF5B301);

  static const station1 = Color(0xFF3B2A6B);
  static const station2 = Color(0xFF0F766E);
  static const station3 = Color(0xFF5FAE4E);
  static const station4 = Color(0xFFA9DDF3);

  /// The «new» dot fill, drawn with a [hibr] outline.
  static const badgeNew = danger;

  /// Drop-off station colors in stop order within a trip, never by station
  /// identity. A trip has at most four drop-off stations, and the letter is
  /// always shown so color is never the only cue.
  static const stations = [
    StationColor(fill: station1, letter: waraq),
    StationColor(fill: station2, letter: waraq),
    StationColor(fill: station3, letter: hibr),
    StationColor(fill: station4, letter: hibr),
  ];

  static const all = [
    shams,
    hibr,
    waraq,
    tablouh,
    primary,
    danger,
    gold,
    station1,
    station2,
    station3,
    station4,
  ];
}

/// A station's fill and the color of the letter drawn on it.
@immutable
class StationColor {
  const StationColor({required this.fill, required this.letter});

  final Color fill;
  final Color letter;
}
