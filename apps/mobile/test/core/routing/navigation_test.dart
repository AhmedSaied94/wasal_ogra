import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/home/presentation/home_header.dart';
import 'package:wassal/features/lines/presentation/lines_screen.dart';
import 'package:wassal/features/settings/settings_screen.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../../helpers/economy.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';
import '../../helpers/trip.dart';

/// Reached by their own screens' controls, not by a placeholder link
/// (specs/015-m10-apartment-story, T048): the apartment's chapter bar and,
/// from US2, the rooms view. Their screens' tests cover them.
const _byScreen = {
  'apartmentItem',
  'apartmentRequests',
  'apartmentChapters',
  'apartmentPreTrip',
  // And the story's pages, from the chapters timeline (US4, US6).
  'story',
  'storyAlbum',
  'storyScene',
};

/// Reached by boot and the first session's redirects, not by links.
const _onboarding = {
  'onboardingIntro',
  'onboardingName',
  'onboardingScene',
  'onboardingFuel',
};

Iterable<Destination> get _routable =>
    destinations.where((d) => d.path != null && d.name != 'boot');

void main() {
  group('links (FR-017a, SC-006)', () {
    for (final d in _routable.where(
      (d) => !_onboarding.contains(d.name) && !_byScreen.contains(d.name),
    )) {
      testWidgets('الموقف reaches ${d.name}', (tester) async {
        final route = routeTo(d.name);
        expect(route, isNotNull, reason: '${d.name} is unreachable');
        // M13's daily row, as links, keeps the daily pages reachable.
        await pumpWassalApp(tester, overrides: [homeDailyLinks()]);
        if (route!.tab != Section.home) await tapTab(tester, route.tab);
        for (final step in route.links) {
          // The trip has no link: playing it to the end leads to the
          // result.
          if (step == RouteNames.result) {
            await finishTrip(tester);
          } else {
            await tapLink(tester, step);
          }
        }
        expect(currentLocation(tester), d.location);
      });
    }

    testWidgets('the apartment tab draws the goal view, and its chapter bar '
        'opens the timeline (T048)', (tester) async {
      await pumpWassalApp(tester, initialLocation: '/apartment');
      expect(find.text('تحويش الجواز'), findsOneWidget);
      await tester.tap(find.text('كل الفصول'));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/apartment/chapters');
    });

    testWidgets('a new player: intro, the Name card, then trip 1, by the '
        "screens' own buttons", (tester) async {
      await pumpWassalApp(tester, newPlayer: true);
      expect(currentLocation(tester), '/onboarding/intro');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(ScenePlayer.nextKey));
        await tester.pumpAndSettle();
      }
      expect(currentLocation(tester), '/onboarding/name');
      await tester.tap(find.byKey(NameScreen.ctaKey));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/trip/line_hay.01');
    });
  });

  group('bottom bar only on the four tabs (FR-015)', () {
    for (final d in _routable) {
      testWidgets(d.name, (tester) async {
        await pumpWassalApp(
          tester,
          initialLocation: d.location,
          // With nothing kept, the result is Home (M08 FR-036); a scene
          // still locked goes to the apartment (M10 story-flow.md).
          economy: switch (d.name) {
            RouteNames.result => economyOverridesOf(
              await lastFinishedEconomy(),
            ),
            RouteNames.storyScene => economyOverridesOf(
              await testEconomy(firstState: standPlayedState),
            ),
            _ => null,
          },
        );
        // A piece in a locked room leaves to the tab (M10 T064).
        expect(
          currentLocation(tester),
          d.name == RouteNames.apartmentItem ? '/apartment' : d.location,
        );
        expect(
          find.byType(BottomNav).hitTestable(),
          d.presentation == Presentation.tab ||
                  d.name == RouteNames.apartmentItem
              ? findsOneWidget
              : findsNothing,
        );
      });
    }
  });

  group('sheets close three ways (FR-018)', () {
    final sheets = destinations.where(
      (d) =>
          d.presentation == Presentation.sheet &&
          // The piece sheet needs an unlocked room to open; its own test
          // covers closing (M10 T055).
          d.name != RouteNames.apartmentItem,
    );
    final closers = <String, Future<void> Function(WidgetTester)>{
      'drag down': (tester) =>
          tester.drag(find.byType(AppSheet).last, const Offset(0, 600)),
      'close button': (tester) => tester.tap(
        find
            .descendant(
              of: find.byType(AppSheet).last,
              matching: find.bySemanticsLabel('قفل'),
            )
            .last,
      ),
      'tap outside': (tester) => tester.tapAt(const Offset(195, 20)),
    };
    for (final d in sheets) {
      for (final MapEntry(key: how, value: close) in closers.entries) {
        testWidgets('${d.name} by $how', (tester) async {
          await pumpWassalApp(tester, initialLocation: d.location);
          // The card opened from Lines is a sheet over the line's details,
          // and closes to them (specs/014-m09-lines-vehicles, R5).
          final nested = d.name == RouteNames.linePreTrip;
          expect(find.byType(AppSheet), findsNWidgets(nested ? 2 : 1));
          await close(tester);
          await tester.pumpAndSettle();
          expect(find.byType(AppSheet), findsNWidgets(nested ? 1 : 0));
          expect(
            currentLocation(tester),
            nested
                ? destinationNamed(RouteNames.lineDetail).location
                : tabFor(d.section).location,
          );
        });
      }
    }
  });

  group('tabs (FR-016)', () {
    testWidgets('a tab keeps its state while another is open', (tester) async {
      // Lines' map keeps its scroll while another tab is open.
      await pumpWassalApp(tester, initialLocation: '/lines');
      final scrollable = find
          .descendant(
            of: find.byType(LinesScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      final before = tester.state<ScrollableState>(scrollable);
      await tapTab(tester, Section.shop);
      await tapTab(tester, Section.lines);
      final after = tester.state<ScrollableState>(scrollable);
      expect(identical(before, after), isTrue);
    });

    testWidgets('tapping the selected tab keeps it at its root', (
      tester,
    ) async {
      await pumpWassalApp(tester, initialLocation: '/lines');
      await tapTab(tester, Section.lines);
      expect(currentLocation(tester), '/lines');
    });
  });

  group('bad routes land on الموقف (FR-022)', () {
    for (final bad in [
      '/trip/line_xyz.01',
      '/trip/line_hay.1',
      '/lines/bad',
      '/lines/vehicle/bus',
      '/apartment/item/garage.car',
      '/story/ch9_none',
      '/nope',
    ]) {
      testWidgets(bad, (tester) async {
        await pumpWassalApp(tester, initialLocation: bad);
        expect(currentLocation(tester), '/home');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('page transitions (FR-023)', () {
    Finder transitionAround(Type type) => find.ancestor(
      of: find.byType(SettingsScreen),
      matching: find.byType(type),
    );

    testWidgets('full motion uses the fade-through scale', (tester) async {
      await pumpWassalApp(tester);
      await tester.tap(find.byKey(HomeHeader.profileKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(transitionAround(ScaleTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/settings');
    });

    testWidgets('reduce motion: a plain fade, no slide or scale', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpWassalApp(tester);
      await tester.tap(find.byKey(HomeHeader.profileKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(transitionAround(FadeTransition), findsWidgets);
      expect(transitionAround(ScaleTransition), findsNothing);
      expect(transitionAround(SlideTransition), findsNothing);
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/settings');
    });
  });
}
