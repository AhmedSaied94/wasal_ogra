import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/trip_pause_overlay.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';
import '../../helpers/surfaces.dart';

// Back rules (contracts/routes.md «Back behavior», FR-019 – FR-021, R7).

const pressAgain = 'دوس رجوع تاني عشان تخرج';

void main() {
  late int exits;

  setUp(() {
    exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('back pops a page', (tester) async {
    await pumpWassalApp(tester);
    await tapLink(tester, 'settings');
    await tapLink(tester, 'account');
    await pressBack(tester);
    expect(currentLocation(tester), '/settings');
    await pressBack(tester);
    expect(currentLocation(tester), '/home');
    expect(exits, 0);
  });

  testWidgets('the top-right back control pops a page', (tester) async {
    await pumpWassalApp(tester);
    await tapLink(tester, 'settings');
    final control = find.byTooltip('رجوع');
    expect(control, findsOneWidget);
    // Top right in RTL: the start side of the header.
    final rect = tester.getRect(control);
    expect(rect.center.dx, greaterThan(390 / 2));
    expect(rect.top, lessThan(844 / 4));
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('a page opened on its own goes back to الموقف', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/daily/reward');
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('with a sheet open, back closes only the sheet', (tester) async {
    await pumpWassalApp(tester);
    await tapLink(tester, 'preTrip');
    expect(find.byType(BottomSheet), findsOneWidget);
    await pressBack(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(currentLocation(tester), '/home');
    expect(exits, 0);
  });

  group('trip (FR-020)', () {
    Future<void> openTrip(WidgetTester tester, {Surface? surface}) async {
      await pumpWassalApp(tester, surface: surface ?? Surface.reference);
      await tapLink(tester, 'preTrip');
      await tapLink(tester, 'trip');
      expect(currentLocation(tester), '/trip/line_hay.01');
    }

    testWidgets('back opens the pause; back again closes it', (tester) async {
      await openTrip(tester);
      await pressBack(tester);
      expect(find.byType(TripPauseOverlay), findsOneWidget);
      expect(currentLocation(tester), '/trip/line_hay.01');

      await pressBack(tester);
      expect(find.byType(TripPauseOverlay), findsNothing);
      expect(currentLocation(tester), '/trip/line_hay.01');
      expect(exits, 0);
    });

    testWidgets('resume closes the pause', (tester) async {
      await openTrip(tester);
      await pressBack(tester);
      await tester.tap(find.text('كمّل المشوار'));
      await tester.pumpAndSettle();
      expect(find.byType(TripPauseOverlay), findsNothing);
      expect(currentLocation(tester), '/trip/line_hay.01');
    });

    testWidgets('the pause home action goes to الموقف', (tester) async {
      await openTrip(tester);
      await pressBack(tester);
      await tester.tap(find.text('ارجع الموقف'));
      await tester.pumpAndSettle();
      expect(find.byType(TripPauseOverlay), findsNothing);
      expect(currentLocation(tester), '/home');
    });

    for (final surface in Surface.values) {
      testWidgets('no top-right control; taps in the bottom third '
          '(${surface.name}, constitution XI)', (tester) async {
        await openTrip(tester, surface: surface);
        expect(find.byTooltip('رجوع'), findsNothing);
        final tappables = find.descendant(
          of: find.byType(PlaceholderScreen),
          matching: find.byWidgetPredicate(
            (w) =>
                (w is GestureDetector && w.onTap != null) ||
                w is IconButton ||
                w is InkWell,
          ),
        );
        expect(tappables, findsWidgets);
        for (final element in tappables.evaluate()) {
          final top = tester.getRect(find.byWidget(element.widget)).top;
          expect(top, greaterThanOrEqualTo(surface.size.height * 2 / 3));
        }
      });
    }
  });

  testWidgets('back on a tab goes to الموقف (FR-021)', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/shop');
    await pressBack(tester);
    expect(currentLocation(tester), '/home');
    expect(exits, 0);
  });

  group('back on الموقف: press twice to leave (FR-021)', () {
    testWidgets('first press warns and stays', (tester) async {
      await pumpWassalApp(tester);
      await pressBack(tester);
      expect(find.text(pressAgain), findsOneWidget);
      expect(exits, 0);
      expect(currentLocation(tester), '/home');
    });

    testWidgets('a second press within 2 s leaves', (tester) async {
      await pumpWassalApp(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exits, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('a press after the window counts as a first press', (
      tester,
    ) async {
      await pumpWassalApp(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exits, 0);
      expect(find.text(pressAgain), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
