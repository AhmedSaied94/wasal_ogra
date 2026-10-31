import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/features/lines/presentation/lines_screen.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';

import '../../helpers/pump_app.dart';

// The four-tab shell (FR-013, FR-014).

void main() {
  testWidgets('a cold start lands on الموقف inside the shell', (tester) async {
    await pumpWassalApp(tester);
    expect(currentLocation(tester), '/home');
    final bar = tester.widget<BottomNav>(find.byType(BottomNav));
    expect(bar.currentIndex, 0);
    // The real stand since M08.
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('/lines shows Lines inside the shell (M09)', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/lines');
    expect(currentLocation(tester), '/lines');
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 1);
    expect(find.byType(LinesScreen), findsOneWidget);
  });

  testWidgets('the lines tab always opens at its root: a card left for a '
      'trip is not rebuilt (specs/014-m09-lines-vehicles, research R5)', (
    tester,
  ) async {
    await pumpWassalApp(
      tester,
      initialLocation: '/lines/line_hay/pre-trip/line_hay.01',
    );
    expect(find.byType(PreTripCard), findsOneWidget);
    // «اطلع» → the trip; then «الخطوط».
    await tester.tap(find.byKey(PreTripCard.goKey));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), startsWith('/trip/'));
    // Away to another tab, as the result's way back does.
    GoRouter.of(tester.element(find.byType(Navigator).first)).go('/shop');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BottomNav.cellKey(1)));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/lines');
    expect(find.byType(PreTripCard), findsNothing);
  });

  testWidgets('the other tabs keep where they were (M03)', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/shop/fuel');
    await tester.tap(find.byKey(BottomNav.cellKey(0)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BottomNav.cellKey(3)));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/shop/fuel');
  });

  const tabs = {'/shop': (index: 3, title: 'المحل')};

  testWidgets('/apartment draws its goal view inside the shell (T048)', (
    tester,
  ) async {
    await pumpWassalApp(tester, initialLocation: '/apartment');
    expect(currentLocation(tester), '/apartment');
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 2);
    expect(find.text('تحويش الجواز'), findsOneWidget);
  });

  for (final MapEntry(key: path, value: tab) in tabs.entries) {
    testWidgets('$path shows its placeholder inside the shell', (tester) async {
      await pumpWassalApp(tester, initialLocation: path);
      expect(currentLocation(tester), path);
      expect(
        tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex,
        tab.index,
      );
      expect(
        find.descendant(
          of: find.byType(PlaceholderScreen).hitTestable(),
          matching: find.text(tab.title),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('tapping a tab switches branch', (tester) async {
    await pumpWassalApp(tester);
    await tester.tap(find.text('الشقة'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/apartment');
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 2);
  });
}
