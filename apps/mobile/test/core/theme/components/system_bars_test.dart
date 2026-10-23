import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';

// The phone's bars over each screen (SystemBars): the status bar clear, the
// navigation bar in the colour along the screen's bottom edge, so three
// buttons never sit on a band of another colour.

/// A status bar and a three-button navigation bar that the app draws under.
void _bars(WidgetTester tester) {
  const padding = FakeViewPadding(top: 24, bottom: 48);
  tester.view
    ..padding = padding
    ..viewPadding = padding;
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

/// What the app last asked of the system bars.
SystemUiOverlayStyle get _style => SystemChrome.latestStyle!;

void _expectBars({required Color bottom, required Brightness buttons}) {
  expect(_style.statusBarColor, Colors.transparent);
  expect(_style.systemNavigationBarColor, bottom);
  expect(_style.systemNavigationBarDividerColor, bottom);
  expect(_style.systemNavigationBarIconBrightness, buttons);
  expect(_style.systemNavigationBarContrastEnforced, isFalse);
}

void main() {
  test('icons are dark on a light colour and light on a dark one', () {
    final loading = SystemBars.style(
      top: ColorTokens.sun,
      bottom: ColorTokens.sun,
    );
    expect(loading.statusBarIconBrightness, Brightness.dark);
    expect(loading.statusBarBrightness, Brightness.light);
    expect(loading.systemNavigationBarIconBrightness, Brightness.dark);

    final trip = SystemBars.style(bottom: ColorTokens.dashboardBg);
    expect(trip.statusBarIconBrightness, Brightness.dark, reason: 'ground');
    expect(trip.systemNavigationBarIconBrightness, Brightness.light);
    expect(trip.systemStatusBarContrastEnforced, isFalse);
  });

  testWidgets('Loading: sun at both ends', (tester) async {
    _bars(tester);
    final startup = Completer<void>();
    await pumpWassalApp(
      tester,
      overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
    );
    expect(currentLocation(tester), '/boot');
    _expectBars(bottom: ColorTokens.sun, buttons: Brightness.dark);
    expect(_style.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('الموقف: the bottom nav runs on under the buttons', (
    tester,
  ) async {
    _bars(tester);
    await pumpWassalApp(tester);
    expect(currentLocation(tester), '/home');
    _expectBars(bottom: ColorTokens.paper, buttons: Brightness.dark);
    expect(_style.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('a page without the nav keeps the ground, and a sheet over it '
      'takes its own white', (tester) async {
    _bars(tester);
    await pumpWassalApp(tester, initialLocation: '/settings');
    _expectBars(bottom: ColorTokens.ground, buttons: Brightness.dark);

    unawaited(
      showAppSheet<void>(
        context: appContext(tester),
        title: 'عنوان اللوح',
        builder: (_) => const SizedBox(height: 300),
      ),
    );
    await tester.pumpAndSettle();
    _expectBars(bottom: ColorTokens.paper, buttons: Brightness.dark);

    Navigator.of(appContext(tester)).pop();
    await tester.pumpAndSettle();
    _expectBars(bottom: ColorTokens.ground, buttons: Brightness.dark);
  });

  testWidgets("the trip: the dashboard's dark, with light buttons", (
    tester,
  ) async {
    await pumpTrip(tester);
    _expectBars(bottom: ColorTokens.dashboardBg, buttons: Brightness.light);
  });
}
