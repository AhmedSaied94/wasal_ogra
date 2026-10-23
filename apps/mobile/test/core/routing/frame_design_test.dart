import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/routing/shell_scaffold.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';

// The app's frame in the new look (spec FR-014 – FR-018): the bottom nav
// and its cross-fade, the placeholders, sheets, the exit toast and the top
// inset. The back rules themselves are back_behavior_test.dart's.

/// The cross-fade's layers caught part-way: opacity strictly between 0 and 1.
Iterable<double> _midFade(WidgetTester tester) => tester
    .widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(TabCrossFade),
        matching: find.byType(FadeTransition),
      ),
    )
    .map((f) => f.opacity.value)
    .where((o) => o > 0 && o < 1);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  group('the bottom nav', () {
    testWidgets('on the four sections, and on no other screen', (tester) async {
      await pumpWassalApp(tester);
      for (final (i, location) in [
        '/home',
        '/lines',
        '/apartment',
        '/shop',
      ].indexed) {
        await tapTab(tester, tabSections[i]);
        expect(currentLocation(tester), location);
        final nav = tester.widget<BottomNav>(find.byType(BottomNav));
        expect(nav.currentIndex, i, reason: 'the pill on $location');
      }
      await pumpWassalApp(tester, initialLocation: '/settings');
      expect(find.byType(BottomNav).hitTestable(), findsNothing);
    });

    testWidgets('the new-dots come from new_dot_providers', (tester) async {
      final container = await pumpWassalApp(tester);
      container.read(newDotProvider(Section.apartment).notifier).show();
      await tester.pump();
      final nav = tester.widget<BottomNav>(find.byType(BottomNav));
      expect(nav.newDots, [false, false, true, false]);
    });

    testWidgets('tabs cross-fade over 150 ms', (tester) async {
      expect(TabCrossFade.duration, DesignExtras.tabFade);
      await pumpWassalApp(tester);
      await tester.tap(find.byKey(BottomNav.cellKey(1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(_midFade(tester), hasLength(2), reason: 'one in, one out');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_midFade(tester), isEmpty);
      expect(currentLocation(tester), '/lines');
    });

    testWidgets('no cross-fade under reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpWassalApp(tester);
      await tester.tap(find.byKey(BottomNav.cellKey(1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_midFade(tester), isEmpty);
    });
  });

  group('placeholders', () {
    testWidgets('a header with a working back, and an EmptyState', (
      tester,
    ) async {
      await pumpWassalApp(tester, initialLocation: '/daily/reward');
      final header = tester.widget<ScreenHeader>(find.byType(ScreenHeader));
      expect(
        header.title,
        destinationNamed(RouteNames.dailyReward).title(l10n),
      );
      expect(
        tester.widget<EmptyState>(find.byType(EmptyState)).message,
        l10n.placeholderNote,
      );
      await tester.tap(find.bySemanticsLabel(l10n.backLabel));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/home');
    });

    testWidgets('a tab has its title and no back control', (tester) async {
      await pumpWassalApp(tester, initialLocation: '/lines');
      final header = tester.widget<ScreenHeader>(find.byType(ScreenHeader));
      expect(header.title, l10n.destLines);
      expect(header.onBack, isNull);
    });
  });

  group('sheets', () {
    Future<void> openFuel(WidgetTester tester) async {
      await tapTab(tester, Section.shop);
      await tapLink(tester, RouteNames.fuel);
      expect(currentLocation(tester), '/shop/fuel');
      expect(find.byType(AppSheet), findsOne);
    }

    testWidgets('closes by its ✕', (tester) async {
      await pumpWassalApp(tester);
      await openFuel(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.bySemanticsLabel(l10n.closeLabel),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/shop');
    });

    testWidgets('closes by back', (tester) async {
      await pumpWassalApp(tester);
      await openFuel(tester);
      await pressBack(tester);
      expect(currentLocation(tester), '/shop');
    });

    testWidgets('closes by the scrim', (tester) async {
      await pumpWassalApp(tester);
      await openFuel(tester);
      await tester.tapAt(const Offset(195, 60));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/shop');
    });

    testWidgets('closes by a drag down', (tester) async {
      await pumpWassalApp(tester);
      await openFuel(tester);
      await tester.drag(find.byKey(AppSheet.grabberKey), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/shop');
    });
  });

  testWidgets('back on الموقف shows an AppToast, never a SnackBar', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpWassalApp(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppToast), findsOne);
    expect(find.text(l10n.pressBackAgainToExit), findsOne);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(find.byType(AppToast), findsNothing);
  });

  group('the top inset is max(viewPadding.top, 24)', () {
    for (final (reported, expected) in [(10.0, 24.0), (47.0, 47.0)]) {
      testWidgets('reported $reported', (tester) async {
        tester.view.viewPadding = FakeViewPadding(top: reported);
        tester.view.padding = FakeViewPadding(top: reported);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        await pumpWassalApp(tester, initialLocation: '/settings');
        expect(tester.getTopLeft(find.byType(ScreenHeader)).dy, 0);
        final back = tester.getRect(find.bySemanticsLabel(l10n.backLabel));
        // The header's 52-high row starts under the inset.
        expect(back.center.dy, closeTo(expected + ScreenHeader.height / 2, 1));
      });
    }
  });
}
