import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';

// One route per intent, however fast the taps (FR-024).

void main() {
  testWidgets('two rapid taps on a link push one route', (tester) async {
    await pumpWassalApp(tester);
    final link = find.byKey(PlaceholderScreen.linkKey('settings'));
    await tester.tap(link);
    await tester.tap(link, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/settings');
    await pressBack(tester);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('navigating to the current location is ignored', (tester) async {
    await pumpWassalApp(tester);
    await tapLink(tester, 'settings');
    expect(NavGuard.push(appContext(tester), '/settings'), isFalse);
    await tester.pumpAndSettle();
    await pressBack(tester);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('a request while a push is pending is ignored', (tester) async {
    await pumpWassalApp(tester);
    final context = appContext(tester);
    expect(NavGuard.push(context, '/settings'), isTrue);
    expect(NavGuard.push(context, '/daily/reward'), isFalse);
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/settings');
    await pressBack(tester);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('a covered page cannot navigate', (tester) async {
    await pumpWassalApp(tester);
    final homeLink = tester.element(
      find.byKey(PlaceholderScreen.linkKey('dailyTasks')),
    );
    await tapLink(tester, 'settings');
    expect(NavGuard.push(homeLink, '/daily/tasks'), isFalse);
  });

  testWidgets('navigation is allowed again once the push lands', (
    tester,
  ) async {
    await pumpWassalApp(tester);
    await tapLink(tester, 'settings');
    await tapLink(tester, 'account');
    expect(currentLocation(tester), '/settings/account');
  });
}
