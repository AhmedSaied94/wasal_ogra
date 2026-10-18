import 'package:material_ui/material_ui.dart';

/// The type scale (contracts/design-tokens.md «Typography»). Styles carry no
/// color; widgets apply one from the palette.
abstract final class TypeTokens {
  static const lalezar = 'Lalezar';
  static const baloo = 'BalooBhaijaan2';

  /// Smallest text the app may draw, in points (ux-spec minimum sizes).
  static const double minFontSize = 12;

  static const display = TextStyle(
    fontFamily: lalezar,
    fontSize: 32,
    fontWeight: FontWeight.w400,
  );
  static const headline = TextStyle(
    fontFamily: lalezar,
    fontSize: 24,
    fontWeight: FontWeight.w400,
  );
  static const button = TextStyle(
    fontFamily: lalezar,
    fontSize: 20,
    fontWeight: FontWeight.w400,
  );

  // Baloo Bhaijaan 2 is a variable font. The weight is set both ways so the
  // `wght` axis follows FontWeight on every renderer (research R6).
  static const title = TextStyle(
    fontFamily: baloo,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );
  static const body = TextStyle(
    fontFamily: baloo,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );
  static const label = TextStyle(
    fontFamily: baloo,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );
  static const caption = TextStyle(
    fontFamily: baloo,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );

  static const all = [display, headline, button, title, body, label, caption];
}
