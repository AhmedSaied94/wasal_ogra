import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// Buttons (HANDOFF §3.1; contracts/components.md "The set").

/// The face's own box: the first decorated box with a fill under [of].
BoxDecoration _face(WidgetTester tester, Finder of) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: of, matching: find.byType(DecoratedBox)),
  )) {
    final d = box.decoration;
    if (d is BoxDecoration && d.color != null) return d;
  }
  throw StateError('no face');
}

BoxShadow? _lip(WidgetTester tester, Finder of) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: of, matching: find.byType(DecoratedBox)),
  )) {
    final shadows = (box.decoration as BoxDecoration).boxShadow;
    if (shadows != null && shadows.isNotEmpty) return shadows.first;
  }
  return null;
}

TextStyle _labelStyle(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

Widget _sized(Widget child) => SizedBox(width: 268, child: child);

void main() {
  testWidgets('primary xl: 64 high, radius 22, lip 6, button.xl in white', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      _sized(AppButton.primary(label: 'يلا نطلع!', onTap: () {})),
    );
    final button = find.byType(AppButton);
    expect(tester.getSize(button).height, 64);
    final face = _face(tester, button);
    expect(face.color, ColorTokens.primary);
    expect(face.borderRadius, BorderRadius.circular(22));
    expect(_lip(tester, button)!.offset.dy, 6);
    expect(_lip(tester, button)!.color, ColorTokens.primaryLip);
    final style = _labelStyle(tester, 'يلا نطلع!');
    expect(style.fontSize, TypeTokens.buttonXl.fontSize);
    expect(style.fontFamily, TypeTokens.marhey);
    expect(style.color, ColorTokens.paper);
  });

  testWidgets('primary l: between 54 and 58 high, radius 20, lip 5', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      _sized(
        AppButton.primary(
          label: 'اشتريها',
          size: AppButtonSize.l,
          onTap: () {},
        ),
      ),
    );
    final button = find.byType(AppButton);
    final h = tester.getSize(button).height;
    expect(h, inInclusiveRange(54, 58));
    expect(_face(tester, button).borderRadius, BorderRadius.circular(20));
    expect(_lip(tester, button)!.offset.dy, 5);
    expect(
      _labelStyle(tester, 'اشتريها').fontSize,
      TypeTokens.buttonL.fontSize,
    );
  });

  testWidgets('secondary: white with a ground.lip ring and lip, ink label', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      _sized(AppButton.secondary(label: 'مشوار تاني', onTap: () {})),
    );
    final button = find.byType(AppButton);
    final face = _face(tester, button);
    expect(face.color, ColorTokens.paper);
    final ring = face.border! as Border;
    expect(ring.top.color, ColorTokens.groundLip);
    expect(ring.top.width, 2);
    expect(ring.top.strokeAlign, BorderSide.strokeAlignInside);
    expect(_lip(tester, button)!.color, ColorTokens.groundLip);
    expect(_labelStyle(tester, 'مشوار تاني').color, ColorTokens.ink);
  });

  testWidgets('sun: sun fill, sun.lip lip, ink label, 44 high', (tester) async {
    await pumpDesignComponent(
      tester,
      _sized(AppButton.sun(label: 'حد معاه فكة؟', onTap: () {})),
    );
    final button = find.byType(AppButton);
    expect(tester.getSize(button).height, 44);
    expect(_face(tester, button).color, ColorTokens.sun);
    expect(_lip(tester, button)!.color, ColorTokens.sunLip);
    expect(_labelStyle(tester, 'حد معاه فكة؟').color, ColorTokens.ink);
  });

  testWidgets('danger: danger fill with ink text, never white', (tester) async {
    await pumpDesignComponent(
      tester,
      _sized(AppButton.danger(label: 'البنزين خلص', onTap: () {})),
    );
    final button = find.byType(AppButton);
    expect(_face(tester, button).color, ColorTokens.danger);
    expect(_lip(tester, button)!.color, ColorTokens.dangerInk);
    final style = _labelStyle(tester, 'البنزين خلص');
    expect(style.color, ColorTokens.ink);
    expect(style.fontSize, DesignExtras.dangerButtonLabel.fontSize);
  });

  testWidgets('tertiary: primary text, ≥ 44 high, pressed = 70% opacity', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      AppButton.tertiary(label: 'ارجع الموقف', onTap: () {}),
    );
    final button = find.byType(AppButton);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(_labelStyle(tester, 'ارجع الموقف').color, ColorTokens.primary);
    expect(_lip(tester, button), isNull);
    final pressable = tester.widget<Pressable>(find.byType(Pressable));
    expect(pressable.pressedOpacity, 0.7);
  });

  testWidgets('disabled: 45% opacity, no lip', (tester) async {
    await pumpDesignComponent(
      tester,
      _sized(
        AppButton.primary(
          label: 'اشتريها',
          size: AppButtonSize.l,
          enabled: false,
          onTap: () {},
        ),
      ),
    );
    final button = find.byType(AppButton);
    expect(_lip(tester, button), isNull);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: button, matching: find.byType(Opacity)),
          )
          .opacity,
      Pressable.disabledOpacity,
    );
  });

  testWidgets('loading: three dots instead of the label, not tappable', (
    tester,
  ) async {
    var taps = 0;
    await pumpDesignComponent(
      tester,
      _sized(
        AppButton.primary(
          label: 'يلا نطلع!',
          loading: true,
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('يلا نطلع!'), findsNothing);
    expect(find.byKey(AppButton.loadingDotsKey), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 0);
  });

  testWidgets('a cost chip trails the label: «−١» and the fuel icon on sun', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      _sized(
        AppButton.primary(
          label: 'يلا نطلع!',
          trailing: const CostChip(amount: '−١'),
          onTap: () {},
        ),
      ),
    );
    final chip = find.byType(CostChip);
    expect(find.descendant(of: chip, matching: find.text('−١')), findsOne);
    expect(
      find.descendant(of: chip, matching: find.byType(SvgPicture)),
      findsOne,
    );
    expect(_face(tester, chip).color, ColorTokens.sun);
    // In RTL the trailing chip sits at the end (left) of the label.
    expect(
      tester.getCenter(chip).dx,
      lessThan(tester.getCenter(find.text('يلا نطلع!')).dx),
    );
  });

  testWidgets('rewarded ad: ready shows title and benefit on primary', (
    tester,
  ) async {
    var taps = 0;
    await pumpDesignComponent(
      tester,
      _sized(
        RewardedAdButton(
          ready: true,
          title: 'اقبض ×٢',
          benefit: '+١٧٠ بدل ٨٥',
          onTap: () => taps++,
        ),
      ),
    );
    final button = find.byType(RewardedAdButton);
    expect(tester.getSize(button).height, DesignExtras.rewardedHeight);
    expect(_face(tester, button).color, ColorTokens.primary);
    expect(find.text('اقبض ×٢'), findsOne);
    expect(find.text('+١٧٠ بدل ٨٥'), findsOne);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('rewarded ad: not ready says so, looks disabled, does nothing', (
    tester,
  ) async {
    var taps = 0;
    await pumpDesignComponent(
      tester,
      _sized(
        RewardedAdButton(
          ready: false,
          title: 'اقبض ×٢',
          benefit: '+١٧٠ بدل ٨٥',
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('الإعلان مش جاهز'), findsOne);
    expect(find.text('اقبض ×٢'), findsNothing);
    final button = find.byType(RewardedAdButton);
    expect(_lip(tester, button), isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  group('IconCircleButton', () {
    for (final icon in ['close', 'back', 'pause', 'edit', 'copy']) {
      testWidgets('$icon on ground: white, lip, 44×44', (tester) async {
        await pumpDesignComponent(
          tester,
          IconCircleButton(icon: icon, semanticLabel: icon, onTap: () {}),
        );
        final button = find.byType(IconCircleButton);
        expect(tester.getSize(button), const Size(44, 44));
        expect(_face(tester, button).color, ColorTokens.paper);
        expect(_lip(tester, button)!.color, ColorTokens.groundLip);
        expect(find.byType(SvgPicture), findsOne);
      });
    }

    testWidgets('in a sheet: ground fill, no lip', (tester) async {
      await pumpDesignComponent(
        tester,
        IconCircleButton(
          icon: 'close',
          semanticLabel: 'close',
          inSheet: true,
          onTap: () {},
        ),
        background: ColorTokens.paper,
      );
      final button = find.byType(IconCircleButton);
      expect(_face(tester, button).color, ColorTokens.ground);
      expect(_lip(tester, button), isNull);
    });
  });

  testWidgets('every button reads its label to a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpDesignComponent(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sized(
            AppButton.primary(
              label: 'يلا نطلع!',
              trailing: const CostChip(amount: '−١'),
              semanticLabel: 'يلا نطلع، بلتر بنزين',
              onTap: () {},
            ),
          ),
          _sized(AppButton.secondary(label: 'مشوار تاني', onTap: () {})),
          AppButton.tertiary(label: 'ارجع الموقف', onTap: () {}),
          IconCircleButton(
            icon: 'pause',
            semanticLabel: 'إيقاف مؤقت',
            onTap: () {},
          ),
        ],
      ),
    );
    expect(find.semantics.byLabel('يلا نطلع، بلتر بنزين'), findsOne);
    expect(find.semantics.byLabel('مشوار تاني'), findsOne);
    expect(find.semantics.byLabel('ارجع الموقف'), findsOne);
    expect(find.semantics.byLabel('إيقاف مؤقت'), findsOne);
    semantics.dispose();
  });
}
