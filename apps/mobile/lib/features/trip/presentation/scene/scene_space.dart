// The design's scene coordinates (390×444, `C-Trip`, `Tutorial`) on the
// laid-out scene: x spreads with the width, y keeps its distance from the
// bottom, and below 408 pt both scale (contracts/trip-layout.md).
import 'dart:ui';

import 'package:wassal/features/trip/domain/scene_layout.dart';

extension SceneSpace on SceneLayout {
  /// A design point.
  Offset at(double x, double y) {
    final p = place(x, y);
    return Offset(p.x, p.y);
  }

  /// A design rect.
  Rect rectOf(double x, double y, double w, double h) =>
      Rect.fromPoints(at(x, y), at(x + w, y + h));

  /// A design rect with rounded corners.
  RRect rrectOf(double x, double y, double w, double h, double radius) =>
      RRect.fromRectAndRadius(
        rectOf(x, y, w, h),
        Radius.circular(radius * scale),
      );

  /// A design length across, such as a stroke's width.
  double across(double length) => length * scale;
}
