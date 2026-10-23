import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// Pills, badges and chips (HANDOFF §3.2; contracts/components.md).

BoxDecoration _face(WidgetTester tester, Finder of) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: of, matching: find.byType(DecoratedBox)),
  )) {
    final d = box.decoration;
    if (d is BoxDecoration && d.color != null) return d;
  }
  throw StateError('no face');
}

List<String> _icons(WidgetTester tester, Finder of) => [
  for (final icon in tester.widgetList<AppIcon>(
    find.descendant(of: of, matching: find.byType(AppIcon)),
  ))
    icon.name,
];

void main() {
  group('CurrencyPill', () {
    testWidgets('coin: white, lip, 44 high, the value and the coin', (
      tester,
    ) async {
      await pumpDesignComponent(
        tester,
        const CurrencyPill(kind: CurrencyKind.coin, value: '١٬٢٤٠'),
      );
      final pill = find.byType(CurrencyPill);
      expect(tester.getSize(pill).height, 44);
      final face = _face(tester, pill);
      expect(face.color, ColorTokens.paper);
      expect(face.boxShadow!.single.color, ColorTokens.groundLip);
      expect(find.text('١٬٢٤٠'), findsOne);
      expect(_icons(tester, pill), ['coin']);
    });

    testWidgets('bonat', (tester) async {
      await pumpDesignComponent(
        tester,
        const CurrencyPill(kind: CurrencyKind.bonat, value: '٨٥'),
      );
      expect(_icons(tester, find.byType(CurrencyPill)), ['bonat']);
    });

    testWidgets('fuel: the level over the refill timer', (tester) async {
      await pumpDesignComponent(
        tester,
        const CurrencyPill(
          kind: CurrencyKind.fuel,
          value: '٤/٥',
          timer: '١٢:٣٠',
        ),
      );
      final pill = find.byType(CurrencyPill);
      expect(_icons(tester, pill), ['fuel_small']);
      expect(
        tester.getCenter(find.text('٤/٥')).dy,
        lessThan(tester.getCenter(find.text('١٢:٣٠')).dy),
      );
      expect(
        tester.widget<Text>(find.text('١٢:٣٠')).style!.color,
        ColorTokens.inkMuted,
      );
    });

    testWidgets('fuel at 0: danger.soft with its lip', (tester) async {
      await pumpDesignComponent(
        tester,
        const CurrencyPill(
          kind: CurrencyKind.fuel,
          value: '٠/٥',
          timer: '١٢:٣٠',
          empty: true,
        ),
      );
      final face = _face(tester, find.byType(CurrencyPill));
      expect(face.color, ColorTokens.dangerSoft);
      expect(face.boxShadow!.single.color, ColorTokens.dangerSoftLip);
    });

    testWidgets('the 40-high variant', (tester) async {
      await pumpDesignComponent(
        tester,
        const CurrencyPill(
          kind: CurrencyKind.coin,
          value: '٥٠',
          height: CurrencyPill.compactHeight,
        ),
      );
      expect(tester.getSize(find.byType(CurrencyPill)).height, 40);
    });

    testWidgets('tappable: a button with its label', (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await pumpDesignComponent(
        tester,
        CurrencyPill(
          kind: CurrencyKind.bonat,
          value: '٨٥',
          semanticLabel: 'بونات ٨٥',
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.byType(CurrencyPill));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.semantics.byLabel('بونات ٨٥'), findsOne);
      semantics.dispose();
    });
  });

  group('CountBadge', () {
    testWidgets('at least 22×18 drawn, primary with white text', (
      tester,
    ) async {
      await pumpDesignComponent(tester, const CountBadge(text: '٢/٣'));
      final badge = find.byType(CountBadge);
      final size = tester.getSize(badge);
      expect(size.width, greaterThanOrEqualTo(22));
      expect(size.height, greaterThanOrEqualTo(18));
      expect(_face(tester, badge).color, ColorTokens.primary);
      expect(
        tester.widget<Text>(find.text('٢/٣')).style!.color,
        ColorTokens.paper,
      );
    });

    testWidgets('tappable: a 44×44 hit area', (tester) async {
      await pumpDesignComponent(
        tester,
        CountBadge(text: '٢/٣', semanticLabel: 'مهمتين من ٣', onTap: () {}),
      );
      final size = tester.getSize(find.byType(CountBadge));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  testWidgets('NewDot: 12, danger, a 2 pt ink ring', (tester) async {
    await pumpDesignComponent(tester, const NewDot());
    final dot = find.byType(NewDot);
    expect(tester.getSize(dot), const Size(12, 12));
    final face = _face(tester, dot);
    expect(face.color, ColorTokens.danger);
    final ring = face.border! as Border;
    expect(ring.top.color, ColorTokens.ink);
    expect(ring.top.width, 2);
  });

  group('StatusChip', () {
    final cases = {
      'new': (
        const StatusChip.new_(label: 'جديد'),
        ColorTokens.danger,
        ColorTokens.ink,
      ),
      'story': (
        const StatusChip.story(label: 'مشوار قصة'),
        ColorTokens.sun,
        ColorTokens.ink,
      ),
      'done': (
        const StatusChip.done(label: 'خلص'),
        ColorTokens.primarySoft,
        ColorTokens.primary,
      ),
      'offline': (
        const StatusChip.offline(label: 'محتاج نت'),
        ColorTokens.paper,
        ColorTokens.ink,
      ),
    };
    for (final MapEntry(key: name, value: (chip, fill, ink)) in cases.entries) {
      testWidgets('$name: its fill and text', (tester) async {
        await pumpDesignComponent(tester, chip);
        final found = find.byType(StatusChip);
        expect(_face(tester, found).color, fill);
        expect(
          tester
              .widget<Text>(
                find.descendant(of: found, matching: find.byType(Text)),
              )
              .style!
              .color,
          ink,
        );
        expect(tester.getSize(found).height, inInclusiveRange(22, 24));
      });
    }
  });

  testWidgets('PriceTag: the currency icon and the number', (tester) async {
    await pumpDesignComponent(
      tester,
      const PriceTag(kind: CurrencyKind.bonat, value: '٢٠'),
    );
    expect(_icons(tester, find.byType(PriceTag)), ['bonat']);
    expect(find.text('٢٠'), findsOne);
  });

  group('Stars', () {
    for (var earned = 0; earned <= 3; earned++) {
      testWidgets('$earned earned', (tester) async {
        await pumpDesignComponent(tester, Stars(earned: earned));
        final stars = find.byType(Stars);
        final names = _icons(tester, stars);
        // Each earned star draws its lip and its face.
        expect(names.where((n) => n == 'star'), hasLength(earned * 2));
        expect(names.where((n) => n == 'star_outline'), hasLength(3 - earned));
        expect(
          find.descendant(of: stars, matching: find.byType(SvgPicture)),
          findsNWidgets(earned * 2 + 3 - earned),
        );
      });
    }
  });
}
