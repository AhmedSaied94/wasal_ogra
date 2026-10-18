import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows Arabic RTL even when the device locale is en_US', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await pumpWassalApp(tester);

    final ctx = appContext(tester);
    expect(Localizations.localeOf(ctx).languageCode, 'ar');
    expect(Directionality.of(ctx), TextDirection.rtl);
  });

  testWidgets('stays light when the device is in dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await pumpWassalApp(tester);

    expect(Theme.of(appContext(tester)).brightness, Brightness.light);
  });

  testWidgets('clamps a large device text scale to 1.3', (tester) async {
    await pumpWassalApp(tester, textScale: 2.0);

    expect(MediaQuery.textScalerOf(appContext(tester)).scale(10), 13);
  });

  testWidgets('treats a small device text scale as 1.0', (tester) async {
    await pumpWassalApp(tester, textScale: 0.8);

    expect(MediaQuery.textScalerOf(appContext(tester)).scale(10), 10);
  });

  testWidgets('an unknown path lands on /home', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/nope');

    expect(currentLocation(tester), '/home');
  });
}
