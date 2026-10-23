import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// Containers (HANDOFF §3.3; contracts/components.md).

BoxDecoration _face(WidgetTester tester, Finder of) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: of, matching: find.byType(DecoratedBox)),
  )) {
    final d = box.decoration;
    if (d is BoxDecoration && d.color != null) return d;
  }
  throw StateError('no face');
}

void main() {
  group('AppCard', () {
    testWidgets('paper, radius 22, a ground.lip lip', (tester) async {
      await pumpDesignComponent(tester, const AppCard(child: Text('كارت')));
      final face = _face(tester, find.byType(AppCard));
      expect(face.color, ColorTokens.paper);
      expect(face.borderRadius, BorderRadius.circular(RadiusTokens.card));
      expect(face.boxShadow!.single, LipTokens.card);
    });

    testWidgets('locked: locked.bg, a 2 pt outline ring, ink.2 text and a '
        'lock, never opacity', (tester) async {
      await pumpDesignComponent(
        tester,
        const AppCard(locked: true, child: Text('مقفول')),
      );
      final card = find.byType(AppCard);
      final face = _face(tester, card);
      expect(face.color, ColorTokens.lockedBg);
      final ring = face.border! as Border;
      expect(ring.top.color, ColorTokens.outline);
      expect(ring.top.width, 2);
      expect(ring.top.strokeAlign, BorderSide.strokeAlignInside);
      expect(
        DefaultTextStyle.of(tester.element(find.text('مقفول'))).style.color,
        ColorTokens.ink2,
      );
      expect(
        find.descendant(of: card, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        tester
            .widgetList<AppIcon>(
              find.descendant(of: card, matching: find.byType(AppIcon)),
            )
            .map((i) => i.name),
        contains('lock'),
      );
    });
  });

  group('ListRow', () {
    testWidgets('a title, a caption and a chevron at the end', (tester) async {
      var taps = 0;
      await pumpDesignComponent(
        tester,
        SizedBox(
          width: 358,
          child: ListRow(
            title: 'شكل الأرقام',
            caption: '١٢٣',
            trailing: const ListRowChevron(),
            onTap: () => taps++,
          ),
        ),
      );
      final row = find.byType(ListRow);
      expect(tester.getSize(row).height, inInclusiveRange(52, 70));
      final chevron = find.byType(ListRowChevron);
      // RTL: the chevron sits at the end (left) of the title.
      expect(
        tester.getCenter(chevron).dx,
        lessThan(tester.getCenter(find.text('شكل الأرقام')).dx),
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('with a switch or a price at the end', (tester) async {
      await pumpDesignComponent(
        tester,
        SizedBox(
          width: 358,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListRow(
                title: 'الصوت',
                trailing: AppSwitch(
                  label: 'الصوت',
                  value: true,
                  framed: false,
                  onChanged: (_) {},
                ),
              ),
              const ListRow(
                title: 'كيس فكة',
                trailing: PriceTag(kind: CurrencyKind.bonat, value: '٨'),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(AppSwitch), findsOne);
      expect(find.byType(PriceTag), findsOne);
    });
  });

  group('ProgressBar', () {
    double fillWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(ProgressBar.fillKey)).width;

    for (final (color, fill) in [
      (ProgressColor.primary, ColorTokens.primary),
      (ProgressColor.gold, ColorTokens.gold),
      (ProgressColor.sun, ColorTokens.sun),
    ]) {
      testWidgets('${color.name}: its fill on the track', (tester) async {
        await pumpDesignComponent(
          tester,
          SizedBox(width: 200, child: ProgressBar(value: 0.5, color: color)),
        );
        final bar = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(ProgressBar.fillKey),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect((bar.decoration as BoxDecoration).color, fill);
        expect(fillWidth(tester), 100);
      });
    }

    Widget bar(ValueNotifier<double> value) => SizedBox(
      width: 200,
      child: ValueListenableBuilder<double>(
        valueListenable: value,
        builder: (context, v, _) => ProgressBar(value: v),
      ),
    );

    testWidgets('a change tweens its width over 500 ms', (tester) async {
      final value = ValueNotifier(0.2);
      addTearDown(value.dispose);
      await pumpDesignComponent(tester, bar(value));
      await tester.pumpAndSettle();
      value.value = 0.8;
      await tester.pump();
      await tester.pump(DesignExtras.progressTween ~/ 2);
      final mid = fillWidth(tester);
      expect(mid, greaterThan(40));
      expect(mid, lessThan(160));
      await tester.pump(DesignExtras.progressTween);
      expect(fillWidth(tester), 160);
    });

    testWidgets('under reduced motion it jumps', (tester) async {
      final value = ValueNotifier(0.2);
      addTearDown(value.dispose);
      await pumpDesignComponent(tester, bar(value), reducedMotion: true);
      await tester.pumpAndSettle();
      value.value = 0.8;
      await tester.pump();
      expect(fillWidth(tester), 160);
    });
  });

  group('ScreenHeader', () {
    testWidgets('the back control at the start (right in RTL), the title, '
        'under the top inset', (tester) async {
      var back = 0;
      tester.view.padding = const FakeViewPadding(top: 36);
      tester.view.viewPadding = const FakeViewPadding(top: 36);
      await pumpDesignComponent(
        tester,
        ScreenHeader(title: 'الإعدادات', onBack: () => back++),
        center: false,
      );
      final button = tester.getRect(find.byType(IconCircleButton));
      expect(button, const Rect.fromLTWH(330, 40, 44, 44));
      expect(
        tester.getCenter(find.text('الإعدادات')).dx,
        lessThan(button.left),
      );
      await tester.tap(find.byType(IconCircleButton));
      await tester.pumpAndSettle();
      expect(back, 1);
    });

    testWidgets('a phone reporting a 10 pt status bar still keeps 24', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 10);
      tester.view.viewPadding = const FakeViewPadding(top: 10);
      await pumpDesignComponent(
        tester,
        ScreenHeader(title: 'الإعدادات', onBack: () {}),
        center: false,
      );
      expect(tester.getRect(find.byType(IconCircleButton)).top, 24 + 4);
    });
  });

  testWidgets('EmptyState: its message, centred', (tester) async {
    await pumpDesignComponent(
      tester,
      const EmptyState(message: 'الشاشة دي لسه بتتجهز.'),
    );
    final text = tester.widget<Text>(find.text('الشاشة دي لسه بتتجهز.'));
    expect(text.textAlign, TextAlign.center);
    expect(text.style!.color, ColorTokens.inkMuted);
  });
}
