import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/new_dot.dart';
import 'package:wassal/core/theme/components/wassal_bottom_bar.dart';
import 'package:wassal/core/theme/tokens/colors.dart';

import '../../helpers/pump_app.dart';

// The «new» dot on the bottom bar (FR-016a). No feature turns one on in M03;
// these tests drive it through the provider.

Finder dotIn(int tab) => find.descendant(
  of: find.byKey(WassalBottomBar.cellKey(tab)),
  matching: find.byType(NewDot),
);

void main() {
  testWidgets('every tab dot defaults to off', (tester) async {
    final container = await pumpWassalApp(tester);
    for (final section in tabSections) {
      expect(container.read(newDotProvider(section)), isFalse);
    }
    expect(find.byType(NewDot), findsNothing);
  });

  for (final (index, section) in tabSections.indexed) {
    testWidgets('an on dot shows on the ${section.name} tab', (tester) async {
      // Stand on another tab: the open tab never keeps its dot.
      final container = await pumpWassalApp(
        tester,
        initialLocation: section == Section.home ? '/shop' : '/home',
      );
      container.read(newDotProvider(section).notifier).show();
      await tester.pump();
      expect(find.byType(NewDot), findsOneWidget);
      expect(dotIn(index), findsOneWidget);
    });
  }

  testWidgets('a dot turned on for the open tab clears at once', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    container.read(newDotProvider(Section.home).notifier).show();
    await tester.pumpAndSettle();
    expect(container.read(newDotProvider(Section.home)), isFalse);
    expect(find.byType(NewDot), findsNothing);
  });

  testWidgets('the dot: 12 pt, badgeNew fill, 2 pt ink outline, top-left in '
      'RTL, labelled «جديد»', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpWassalApp(
      tester,
      overrides: [
        newDotProvider(Section.lines)
            .overrideWithBuild((ref, notifier) => true),
      ],
    );
    final dot = dotIn(1);
    expect(tester.getSize(dot), const Size(12, 12));
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(of: dot, matching: find.byType(DecoratedBox)),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, ColorTokens.badgeNew);
    expect(decoration.shape, BoxShape.circle);
    final border = decoration.border! as Border;
    expect(border.top.color, ColorTokens.hibr);
    expect(border.top.width, 2);

    final icon = tester.getCenter(
      find.descendant(
        of: find.byKey(WassalBottomBar.cellKey(1)),
        matching: find.byType(Icon),
      ),
    );
    final centre = tester.getCenter(dot);
    expect(centre.dx, lessThan(icon.dx), reason: 'top-end is left in RTL');
    expect(centre.dy, lessThan(icon.dy));

    // The dot's label joins its tab's, so the tab reads as new.
    final cellLabel = tester
        .getSemantics(find.byKey(WassalBottomBar.cellKey(1)))
        .label;
    expect(cellLabel, contains('جديد'));
    expect(cellLabel, contains('الخطوط'));
    semantics.dispose();
  });

  testWidgets('opening the tab clears its dot, and it stays off', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    container.read(newDotProvider(Section.apartment).notifier).show();
    await tester.pump();
    expect(dotIn(2), findsOneWidget);

    await tester.tap(find.text('الشقة'));
    await tester.pumpAndSettle();
    expect(dotIn(2), findsNothing);
    expect(container.read(newDotProvider(Section.apartment)), isFalse);

    await tester.tap(find.text('الموقف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الشقة'));
    await tester.pumpAndSettle();
    expect(dotIn(2), findsNothing);
  });

  testWidgets('a dot overridden on clears when its tab opens by a link', (
    tester,
  ) async {
    final container = await pumpWassalApp(
      tester,
      overrides: [
        newDotProvider(Section.lines)
            .overrideWithBuild((ref, notifier) => true),
      ],
      initialLocation: '/lines',
    );
    await tester.pumpAndSettle();
    expect(container.read(newDotProvider(Section.lines)), isFalse);
    expect(dotIn(1), findsNothing);
  });

  test('show and clear toggle the dot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(newDotProvider(Section.shop).notifier);
    notifier.show();
    expect(container.read(newDotProvider(Section.shop)), isTrue);
    notifier.clear();
    expect(container.read(newDotProvider(Section.shop)), isFalse);
  });
}
