import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/components/sticker_card.dart';
import 'package:wassal/core/theme/components/wassal_bottom_bar.dart';
import 'package:wassal/core/theme/tokens/colors.dart';

import '../../helpers/pump_component.dart';

// Shared components (contracts/design-tokens.md «Shared components», FR-008).

/// The component's own decoration: its outermost DecoratedBox.
BoxDecoration decorationOf(WidgetTester tester, Finder component) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: component,
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Offset translationOf(WidgetTester tester, Finder component) {
  final transform = tester.widget<Transform>(
    find.descendant(of: component, matching: find.byType(Transform)).first,
  );
  final t = transform.transform.getTranslation();
  return Offset(t.x, t.y);
}

void expectStickerBorder(BoxDecoration d, {required double radius}) {
  final border = d.border! as Border;
  for (final side in [border.top, border.right, border.bottom, border.left]) {
    expect(side.color, ColorTokens.hibr);
    expect(side.width, 2.5);
  }
  expect(d.borderRadius, BorderRadius.circular(radius));
}

void expectHardShadow(BoxDecoration d, Offset offset) {
  expect(d.boxShadow, hasLength(1));
  final shadow = d.boxShadow!.single;
  expect(shadow.color, ColorTokens.hibr);
  expect(shadow.offset, offset);
  expect(shadow.blurRadius, 0);
  expect(shadow.spreadRadius, 0);
}

void main() {
  group('PrimaryButton', () {
    final button = find.byType(PrimaryButton);

    testWidgets(
      'primary fill, waraq text, hibr border, radius 14, RTL shadow',
      (tester) async {
        await pumpComponent(
          tester,
          body: PrimaryButton(label: 'يلا', onPressed: () {}),
        );
        final d = decorationOf(tester, button);
        expect(d.color, ColorTokens.primary);
        expectStickerBorder(d, radius: 14);
        // Falls down and toward the end side: bottom-left in RTL.
        expectHardShadow(d, const Offset(-5, 5));
        expect(
          tester.widget<Text>(find.text('يلا')).style?.color,
          ColorTokens.waraq,
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(52));
        expect(translationOf(tester, button), Offset.zero);
      },
    );

    testWidgets('pressing drops the shadow and shifts by its offset', (
      tester,
    ) async {
      var taps = 0;
      await pumpComponent(
        tester,
        body: PrimaryButton(label: 'يلا', onPressed: () => taps++),
      );
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump();
      final pressed = decorationOf(tester, button);
      expect(pressed.boxShadow ?? const <BoxShadow>[], isEmpty);
      expect(translationOf(tester, button), const Offset(-5, 5));

      await gesture.up();
      await tester.pump();
      expect(taps, 1);
      expectHardShadow(decorationOf(tester, button), const Offset(-5, 5));
      expect(translationOf(tester, button), Offset.zero);
    });

    testWidgets('fills the available width by default', (tester) async {
      await pumpComponent(
        tester,
        body: PrimaryButton(label: 'يلا', onPressed: () {}),
      );
      expect(tester.getSize(button).width, 390);
    });
  });

  testWidgets('SecondaryButton: waraq fill and hibr text', (tester) async {
    await pumpComponent(
      tester,
      body: SecondaryButton(label: 'رجوع', onPressed: () {}),
    );
    final d = decorationOf(tester, find.byType(SecondaryButton));
    expect(d.color, ColorTokens.waraq);
    expectStickerBorder(d, radius: 14);
    expectHardShadow(d, const Offset(-5, 5));
    expect(
      tester.widget<Text>(find.text('رجوع')).style?.color,
      ColorTokens.hibr,
    );
    expect(
      tester.getSize(find.byType(SecondaryButton)).height,
      greaterThanOrEqualTo(52),
    );
  });

  testWidgets('StickerCard: waraq fill, 2.5 border, radius 18, shadow 4', (
    tester,
  ) async {
    await pumpComponent(tester, body: const StickerCard(child: Text('كارت')));
    final d = decorationOf(tester, find.byType(StickerCard));
    expect(d.color, ColorTokens.waraq);
    expectStickerBorder(d, radius: 18);
    expectHardShadow(d, const Offset(-4, 4));
  });

  group('WassalBottomBar', () {
    const labels = ['الموقف', 'الخطوط', 'الشقة', 'المحل'];

    testWidgets('tablouh bar, four RTL cells of at least 44×44', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        bottomBar: WassalBottomBar(currentIndex: 0, onTap: (_) {}),
      );
      final bar = find.byType(WassalBottomBar);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: bar, matching: find.byType(ColoredBox)).first,
            )
            .color,
        ColorTokens.tablouh,
      );

      // The first tab is rightmost; the rest follow right to left.
      final xs = [for (final l in labels) tester.getCenter(find.text(l)).dx];
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], lessThan(xs[i - 1]), reason: labels[i]);
      }

      final widths = <double>{};
      for (var i = 0; i < labels.length; i++) {
        final cell = find.byKey(WassalBottomBar.cellKey(i));
        final size = tester.getSize(cell);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(
          find.descendant(of: cell, matching: find.text(labels[i])),
          findsOneWidget,
        );
        widths.add(size.width);
      }
      expect(widths, hasLength(1), reason: 'cells are equal width');
    });

    testWidgets('selected is shams, unselected is waraq', (tester) async {
      await pumpComponent(
        tester,
        bottomBar: WassalBottomBar(currentIndex: 2, onTap: (_) {}),
      );
      for (var i = 0; i < labels.length; i++) {
        final cell = find.byKey(WassalBottomBar.cellKey(i));
        final expected = i == 2 ? ColorTokens.shams : ColorTokens.waraq;
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: cell, matching: find.byType(Icon)),
              )
              .color,
          expected,
        );
        expect(
          tester.widget<Text>(find.text(labels[i])).style?.color,
          expected,
        );
      }
    });

    testWidgets('the whole cell is the tap target', (tester) async {
      int? tapped;
      await pumpComponent(
        tester,
        bottomBar: WassalBottomBar(currentIndex: 0, onTap: (i) => tapped = i),
      );
      final cell = tester.getRect(find.byKey(WassalBottomBar.cellKey(3)));
      // A corner of the cell, away from the icon and label.
      await tester.tapAt(cell.topLeft + const Offset(2, 2));
      expect(tapped, 3);
    });

    testWidgets('sits above the system gesture area', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      await pumpComponent(
        tester,
        bottomBar: WassalBottomBar(currentIndex: 0, onTap: (_) {}),
      );
      final safeArea = tester.widget<SafeArea>(
        find.descendant(
          of: find.byType(WassalBottomBar),
          matching: find.byType(SafeArea),
        ),
      );
      expect(safeArea.top, isFalse);
      expect(safeArea.bottom, isTrue);
      final cell = tester.getRect(find.byKey(WassalBottomBar.cellKey(0)));
      expect(cell.bottom, lessThanOrEqualTo(844 - 34));
      // The bar's fill still reaches the bottom edge.
      expect(tester.getRect(find.byType(WassalBottomBar)).bottom, 844);
    });
  });
}
