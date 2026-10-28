// The pre-trip card (specs/013-m08-home-result, contracts/pre-trip-card.md,
// US2): closing spends nothing, «اطلع» opens the trip, an empty tank the
// fuel sheet, an unknown or locked trip goes home; the story chip and bar,
// the pinned button, the locked boosters, and buying a booster from it.
import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/pre_trip/presentation/booster_tiles.dart';
import 'package:wassal/features/pre_trip/presentation/buy_dialog.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/home.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

const _done = TripProgress(bestStars: 3, plays: 1, firstCompletedAtMs: 1);

/// The card of [tripId] over Home, for a returning player whose economy
/// starts as [state] changes the new player's.
Future<(ProviderContainer, TestEconomy)> _card(
  WidgetTester tester, {
  String tripId = 'line_hay.01',
  EconomyState Function(EconomyState player)? state,
  FailingInterceptor? interceptor,
  ServerStatusState serverStatus = const ServerStatusState(),
  List<Override> overrides = const [],
  Surface surface = Surface.reference,
  double textScale = 1.0,
}) async {
  final economy = await testEconomy(
    executor: interceptor == null
        ? null
        : (inner) => inner.interceptWith(interceptor),
    firstState: (nowMs) {
      final player = EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs);
      return state == null ? player : state(player);
    },
  );
  final container = await pumpWassalApp(
    tester,
    economy: economyOverridesOf(economy),
    serverStatus: serverStatus,
    overrides: overrides,
    surface: surface,
    textScale: textScale,
  );
  container.read(routerProvider).go('/home/pre-trip/$tripId');
  await tester.pumpAndSettle();
  return (container, economy);
}

/// What the player holds, to show nothing was spent.
(int, int, int, Map<BoosterId, int>) _wallet(ProviderContainer c) {
  final view = c.read(economyViewProvider);
  return (view.jenehat, view.bonat, view.fuel.liters, view.inventory);
}

void main() {
  group('closing spends nothing', () {
    for (final (way, close) in <(String, Future<void> Function(WidgetTester))>[
      (
        '✕',
        (tester) async {
          await tester.tap(find.byKey(PreTripCard.closeKey));
          await tester.pumpAndSettle();
        },
      ),
      ('system back', pressBack),
      (
        'the scrim',
        (tester) async {
          await tester.tapAt(const Offset(195, 40));
          await tester.pumpAndSettle();
        },
      ),
      (
        'a swipe past a quarter',
        (tester) async {
          final height = tester.getSize(find.byType(AppSheet)).height;
          await tester.drag(
            find.byKey(AppSheet.grabberKey),
            Offset(0, height * 0.4),
          );
          await tester.pumpAndSettle();
        },
      ),
      (
        'a fling',
        (tester) async {
          await tester.fling(
            find.byKey(AppSheet.grabberKey),
            const Offset(0, 60),
            1500,
          );
          await tester.pumpAndSettle();
        },
      ),
    ]) {
      testWidgets(way, (tester) async {
        final (container, _) = await _card(
          tester,
          state: (p) => p.copyWith(bonat: 40),
        );
        expect(find.byType(PreTripCard), findsOneWidget);
        final before = _wallet(container);
        await close(tester);
        expect(currentLocation(tester), '/home');
        expect(find.byType(PreTripCard), findsNothing);
        expect(_wallet(container), before);
      });
    }

    testWidgets('a short swipe springs back', (tester) async {
      await _card(tester);
      await tester.drag(find.byKey(AppSheet.grabberKey), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/home/pre-trip/line_hay.01');
    });
  });

  group('«اطلع»', () {
    testWidgets('opens the trip; the card spends nothing itself', (
      tester,
    ) async {
      await preloadTripArt(tester);
      final (container, _) = await _card(tester);
      final before = _wallet(container);
      expect(container.read(economyViewProvider).fuel.liters, 5);
      await tester.tap(find.byKey(PreTripCard.goKey));
      // The trip's own frames never settle.
      await pumpFrames(tester);
      expect(currentLocation(tester), '/trip/line_hay.01');
      expect(find.byType(PreTripCard), findsNothing);
      // The start, and its liter, are the trip's (M02).
      expect(_wallet(container).$1, before.$1);
    });

    testWidgets('an empty tank: the fuel sheet', (tester) async {
      await _card(
        tester,
        state: (p) => p.copyWith(
          fuel: FuelState(liters: 0, countedFromMs: p.fuel.countedFromMs),
        ),
      );
      await tester.tap(find.byKey(PreTripCard.goKey));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/shop/fuel');
    });

    testWidgets('its label says it spends a liter; the cost chip shows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _card(tester);
      expect(labelled('اطلع، هيصرف لتر بنزين'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(PreTripCard.goKey),
          matching: shows('−١'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('a trip it cannot open goes home, charging nothing', () {
    for (final (what, tripId) in [
      ('unknown', 'line_hay.99'),
      ('locked (the microbus not owned)', 'line_gamaa.01'),
      ('locked (the trip before not played)', 'line_hay.02'),
    ]) {
      testWidgets(what, (tester) async {
        final (container, _) = await _card(tester, tripId: tripId);
        expect(currentLocation(tester), '/home');
        expect(find.byType(PreTripCard), findsNothing);
        expect(container.read(economyViewProvider).fuel.liters, 5);
      });
    }
  });

  testWidgets('a story trip: the chip and the condition bar', (tester) async {
    await _card(
      tester,
      tripId: 'line_hay.03',
      state: (p) =>
          p.copyWith(progress: {'line_hay.01': _done, 'line_hay.02': _done}),
    );
    expect(
      find.descendant(
        of: find.byType(StatusChip),
        matching: find.text('مشوار قصة'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(PreTripCard.storyBarKey), findsOneWidget);
    expect(find.text('أي خناقة والمشوار يتعاد'), findsOneWidget);
    // A regular trip has neither.
    appRouter(tester).go('/home/pre-trip/line_hay.01');
    await tester.pumpAndSettle();
    // The same sheet, updated in place, shows the other trip.
    expect(
      tester.widget<PreTripCard>(find.byType(PreTripCard)).tripId,
      'line_hay.01',
    );
    expect(find.byKey(PreTripCard.storyBarKey), findsNothing);
    expect(
      find.byType(StatusChip).evaluate().map((e) => e.widget),
      isNot(
        contains(
          isA<StatusChip>().having((c) => c.label, 'label', 'مشوار قصة'),
        ),
      ),
    );
  });

  testWidgets('on a small phone at large text the body scrolls and «اطلع» '
      'stays in view', (tester) async {
    await _card(
      tester,
      tripId: 'line_gamaa.02',
      state: (p) => p.copyWith(
        progress: {
          'line_hay.01': _done,
          'line_hay.02': _done,
          'line_gamaa.01': _done,
        },
        ownership: {
          (SkuKind.vehicle, 'micro_old'): Owned(
            kind: SkuKind.vehicle,
            acquiredAtMs: 0,
          ),
        },
      ),
      surface: Surface.small,
      textScale: 1.3,
    );
    final go = find.byKey(PreTripCard.goKey);
    expect(go.hitTestable(), findsOneWidget);
    expect(tester.getRect(go).bottom, lessThanOrEqualTo(640));
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(PreTripCard.scrollKey),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    final top = tester.getRect(go);
    await tester.drag(find.byKey(PreTripCard.scrollKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(go), top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the boosters are hidden while M07 locks them', (tester) async {
    final economy = await testEconomy(
      content: tutorialContent(),
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            displayName: () => 'حمادة',
            progress: {tutorialTripIds.first: _done},
          ),
    );
    final container = await pumpWassalApp(
      tester,
      newPlayer: true,
      content: contentTestOverrides(assets: tutorialBundledAssets()),
      economy: economyOverridesOf(economy),
      settle: false,
      settleBoot: false,
      overrides: seededFirstSession((store) async {
        await store.markOpeningDone(0);
        await store.reachStep(2);
      }),
    );
    expect(container.read(firstSessionProvider).boostersLocked, isTrue);
    container.read(routerProvider).go('/home/pre-trip/${tutorialTripIds[1]}');
    await pumpFrames(tester);
    expect(find.byType(PreTripCard), findsOneWidget);
    expect(find.byType(BoosterTiles), findsNothing);
    expect(find.text('المساعدات'), findsNothing);
  });

  group('buying a booster', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(BoosterTiles.buyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BoosterTiles.buyKey));
      await tester.pumpAndSettle();
      expect(find.byType(BuyDialog), findsOneWidget);
    }

    Finder count(BoosterId booster, String n) => find.descendant(
      of: find.byKey(BoosterTiles.tileKey(booster)),
      matching: shows(n),
    );

    for (final offline in [false, true]) {
      testWidgets(
        offline
            ? 'offline: applied all the same'
            : 'applied: the '
                  "tile's count, and the chip moves on",
        (tester) async {
          final (container, _) = await _card(
            tester,
            state: (p) => p.copyWith(bonat: 50),
            serverStatus: offline
                ? const ServerStatusState(reach: Reach.offline)
                : const ServerStatusState(),
          );
          expect(shows('كيس فكة بـ١٠ بونات'), findsOneWidget);
          await openDialog(tester);
          await tester.tap(find.byKey(BuyDialog.buyKey));
          await tester.pumpAndSettle();
          expect(find.byType(BuyDialog), findsNothing);
          expect(container.read(economyViewProvider).bonat, 40);
          expect(count(BoosterId.changeBag, '×١'), findsOneWidget);
          expect(shows('الدفتر بـ١٢ بون'), findsOneWidget);
          expect(currentLocation(tester), '/home/pre-trip/line_hay.01');
        },
      );
    }

    testWidgets('short: «ناقصك …», no way to buy, nothing spent', (
      tester,
    ) async {
      final (container, _) = await _card(
        tester,
        state: (p) => p.copyWith(bonat: 5),
      );
      await openDialog(tester);
      expect(find.textContaining('ناقصك'), findsOneWidget);
      expect(find.byKey(BuyDialog.buyKey), findsNothing);
      // Only its buttons close it.
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.byType(BuyDialog), findsOneWidget);
      await tester.tap(find.byKey(BuyDialog.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(BuyDialog), findsNothing);
      expect(container.read(economyViewProvider).bonat, 5);
    });

    testWidgets('a double tap buys once', (tester) async {
      final (container, _) = await _card(
        tester,
        state: (p) => p.copyWith(bonat: 50),
      );
      await openDialog(tester);
      await tester.tap(find.byKey(BuyDialog.buyKey));
      await tester.tap(find.byKey(BuyDialog.buyKey), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(container.read(economyViewProvider).bonat, 40);
      expect(container.read(economyViewProvider).inventory, {
        BoosterId.changeBag: 1,
      });
    });

    testWidgets('a failed write says so; buying again sends the same '
        'request', (tester) async {
      final interceptor = FailingInterceptor();
      final (container, economy) = await _card(
        tester,
        state: (p) => p.copyWith(bonat: 50),
        interceptor: interceptor,
      );
      await openDialog(tester);
      interceptor.failInserts = true;
      await tester.tap(find.byKey(BuyDialog.buyKey));
      await tester.pumpAndSettle();
      expect(find.byType(BuyDialog), findsOneWidget);
      expect(find.text('ما عرفناش نكمّل الشرا.'), findsOneWidget);
      expect(container.read(economyViewProvider).bonat, 50);
      interceptor.failInserts = false;
      await tester.tap(find.byKey(BuyDialog.buyKey));
      await tester.pumpAndSettle();
      expect(find.byType(BuyDialog), findsNothing);
      expect(container.read(economyViewProvider).bonat, 40);
      final pending = await tester.runAsync(economy.service.pendingOps);
      expect(pending, hasLength(1));
    });
  });
}
