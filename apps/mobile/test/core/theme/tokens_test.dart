import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/colors.dart';
import 'package:wassal/core/theme/tokens/motion.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('type scale (FR-007)', () {
    void check(TextStyle s, String family, double size, FontWeight weight) {
      expect(s.fontFamily, family);
      expect(s.fontSize, size);
      expect(s.fontWeight, weight);
    }

    check(TypeTokens.display, 'Lalezar', 32, FontWeight.w400);
    check(TypeTokens.headline, 'Lalezar', 24, FontWeight.w400);
    check(TypeTokens.button, 'Lalezar', 20, FontWeight.w400);
    check(TypeTokens.title, 'BalooBhaijaan2', 18, FontWeight.w700);
    check(TypeTokens.body, 'BalooBhaijaan2', 15, FontWeight.w500);
    check(TypeTokens.label, 'BalooBhaijaan2', 13, FontWeight.w600);
    check(TypeTokens.caption, 'BalooBhaijaan2', 12, FontWeight.w500);
    for (final s in TypeTokens.all) {
      expect(s.fontSize, greaterThanOrEqualTo(TypeTokens.minFontSize));
    }
    expect(TypeTokens.minFontSize, 12);
  });

  test('shape tokens (FR-006)', () {
    expect(ShapeTokens.borderCard, 2.5);
    expect(ShapeTokens.radiusCard, 18);
    expect(ShapeTokens.radiusControl, 14);
    expect(ShapeTokens.shadowCard, 4);
    expect(ShapeTokens.shadowPrimary, 5);
    expect(ShapeTokens.badgeSize, 12);
    expect(ShapeTokens.badgeOutline, 2);
    expect(ShapeTokens.minTouch, 44);
  });

  test('hard shadows fall toward the end side', () {
    expect(hardShadowOffset(5, TextDirection.rtl), const Offset(-5, 5));
    expect(hardShadowOffset(5, TextDirection.ltr), const Offset(5, 5));
  });

  test('motion tokens stay under a third of a second (FR-022)', () {
    expect(MotionTokens.fast, const Duration(milliseconds: 150));
    expect(MotionTokens.screen, const Duration(milliseconds: 250));
    expect(MotionTokens.sheet, const Duration(milliseconds: 250));
    for (final d in MotionTokens.all) {
      expect(d.inMilliseconds, lessThan(333));
    }
  });

  test('space tokens follow the 4-pt grid', () {
    expect(
      [
        SpaceTokens.xs,
        SpaceTokens.s,
        SpaceTokens.m,
        SpaceTokens.l,
        SpaceTokens.xl,
        SpaceTokens.xxl,
      ],
      [4, 8, 12, 16, 24, 32],
    );
  });

  testWidgets('the app theme carries the tokens and the شمس background', (
    tester,
  ) async {
    await pumpWassalApp(tester);
    final theme = Theme.of(appContext(tester));
    expect(theme.extension<WassalTokens>(), isNotNull);
    expect(theme.scaffoldBackgroundColor, ColorTokens.shams);
    expect(theme.brightness, Brightness.light);
  });

  test('WassalTokens copies and switches between themes', () {
    const t = WassalTokens.standard;
    final copy = t.copyWith(primary: ColorTokens.danger);
    expect(copy.primary, ColorTokens.danger);
    expect(copy.shams, t.shams);
    expect(copy.stations, t.stations);
    expect(t.copyWith().hibr, t.hibr);
    // One theme only (FR-009): no blending, just a switch at the midpoint.
    expect(t.lerp(copy, 0.4), same(t));
    expect(t.lerp(copy, 0.6), same(copy));
    expect(t.lerp(null, 0.9), same(t));
  });
}
