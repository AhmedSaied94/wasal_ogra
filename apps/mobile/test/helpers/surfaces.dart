import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test frames in logical points (ux-spec reference frame and a small phone).
/// Goldens render at device pixel ratio 1 to keep the reference images small;
/// layout depends only on logical size.
enum Surface {
  reference(Size(390, 844)),
  small(Size(360, 640));

  const Surface(this.size);

  final Size size;
}

void applySurface(WidgetTester tester, Surface surface) {
  tester.view.physicalSize = surface.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
