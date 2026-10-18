import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/theme/components/wassal_bottom_bar.dart';

import '../../helpers/pump_app.dart';

// The four-tab shell (FR-013, FR-014).

void main() {
  testWidgets('a cold start lands on الموقف inside the shell', (tester) async {
    await pumpWassalApp(tester);
    expect(currentLocation(tester), '/home');
    final bar = tester.widget<WassalBottomBar>(find.byType(WassalBottomBar));
    expect(bar.currentIndex, 0);
    expect(
      find.descendant(
        of: find.byType(PlaceholderScreen),
        matching: find.text('الموقف'),
      ),
      findsOneWidget,
    );
  });

  const tabs = {
    '/lines': (index: 1, title: 'الخطوط'),
    '/apartment': (index: 2, title: 'الشقة'),
    '/shop': (index: 3, title: 'المحل'),
  };

  for (final MapEntry(key: path, value: tab) in tabs.entries) {
    testWidgets('$path shows its placeholder inside the shell', (tester) async {
      await pumpWassalApp(tester, initialLocation: path);
      expect(currentLocation(tester), path);
      expect(
        tester
            .widget<WassalBottomBar>(find.byType(WassalBottomBar))
            .currentIndex,
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
    expect(
      tester.widget<WassalBottomBar>(find.byType(WassalBottomBar)).currentIndex,
      2,
    );
  });
}
