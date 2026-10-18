import 'package:material_ui/material_ui.dart';

/// Borders, radii, hard shadows and touch sizes, in points
/// (contracts/design-tokens.md «Shape»).
abstract final class ShapeTokens {
  static const double borderCard = 2.5;
  static const double radiusCard = 18;
  static const double radiusControl = 14;
  static const double shadowCard = 4;
  static const double shadowPrimary = 5;
  static const double badgeSize = 12;
  static const double badgeOutline = 2;
  static const double minTouch = 44;
}

/// A hard shadow of [n] points falls down and toward the end side:
/// bottom-left in RTL, bottom-right in LTR.
Offset hardShadowOffset(double n, TextDirection direction) =>
    Offset(direction == TextDirection.rtl ? -n : n, n);
