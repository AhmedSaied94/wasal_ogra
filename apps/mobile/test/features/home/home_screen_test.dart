// الموقف (specs/013-m08-home-result, contracts/home.md, US1): the header,
// the line card and the savings card from the economy and the pack, the
// links, the apartment's dot, a finished trip shown on return, and
// `startNextTrip`'s branches.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/application/last_finished_trip.dart';
import 'package:wassal/features/home/presentation/home_header.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/home/presentation/line_card.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/features/settings/settings_screen.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/home.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

/// A finished trip's record.
const _done = TripProgress(bestStars: 3, plays: 1, firstCompletedAtMs: 1);

Owned _owned(SkuKind kind, {String? variant}) =>
    Owned(kind: kind, acquiredAtMs: 0, variantId: variant);

/// The between-trips checkpoint, held until [open].
final class _Checkpoint implements BetweenTripsCheckpoint {
  int passes = 0;
  var _gate = Completer<void>()..complete();

  void hold() => _gate = Completer<void>();

  void open() => _gate.complete();

  @override
  Future<void> pass() {
    passes++;
    return _gate.future;
  }
}

/// Home for a returning player whose economy starts as [state] changes the
/// new player's.
Future<(ProviderContainer, TestEconomy)> _home(
  WidgetTester tester, {
  EconomyState Function(EconomyState player)? state,
  List<Override> overrides = const [],
  ServerStatusState serverStatus = const ServerStatusState(),
}) async {
  final economy = await testEconomy(
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
    // The fuel pill's countdown ticks: nothing settles.
    settle: false,
    settleBoot: false,
  );
  await pumpFrames(tester);
  expect(find.byType(HomeScreen), findsOneWidget);
  return (container, economy);
}

Finder _inHeader(String text) =>
    find.descendant(of: find.byType(HomeHeader), matching: find.text(text));

Finder _inside<T>(Finder matching) =>
    find.descendant(of: find.byType(T), matching: matching);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await pumpFrames(tester);
}

void main() {
  group('the header', () {
    testWidgets('the default name, the first level and the three pills', (
      tester,
    ) async {
      await _home(
        tester,
        state: (p) => p.copyWith(
          jenehat: 1240,
          bonat: 85,
          fuel: FuelState(liters: 4, countedFromMs: p.fuel.countedFromMs),
        ),
      );
      expect(_inHeader('الأسطى'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(HomeHeader), matching: shows('درجة ١')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(HomeHeader.coinsKey),
          matching: shows('١٬٢٤٠'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(HomeHeader.bonatKey),
          matching: shows('٨٥'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(HomeHeader.fuelKey),
          matching: shows('٤/٥'),
        ),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(labelled('الجنيهات ١٬٢٤٠'), findsOneWidget);
      expect(labelled('البونات ٨٥، افتح المحل'), findsOneWidget);
      expect(
        labelled('البنزين ٤ من ٥، اللتر الجاي بعد ٢٠ دقيقة'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets("the player's name on one line, ellipsized at 84", (
      tester,
    ) async {
      const name = 'عبدالرحمن الشرق';
      await _home(tester, state: (p) => p.copyWith(displayName: () => name));
      final text = _inHeader(name);
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.maxLines, 1);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.getSize(text).width, lessThanOrEqualTo(84));
    });

    testWidgets('offline: the BONAT pill is no link', (tester) async {
      await _home(
        tester,
        serverStatus: const ServerStatusState(reach: Reach.offline),
      );
      await _tap(tester, find.byKey(HomeHeader.bonatKey));
      expect(currentLocation(tester), '/home');
    });
  });

  testWidgets("the line card: the next trip's place and the stars", (
    tester,
  ) async {
    await _home(
      tester,
      state: (p) => p.copyWith(progress: {'line_hay.01': _done}),
    );
    final card = find.byType(HomeLineCard);
    expect(
      find.descendant(of: card, matching: find.text('خط الحي')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: shows('المشوار ٢ من ٣')),
      findsOneWidget,
    );
    expect(find.descendant(of: card, matching: shows('٣/٩')), findsOneWidget);
  });

  group('the savings card and the apartment dot', () {
    // The apartment is open: chapters 1 to 3 done.
    EconomyState open(EconomyState p, int jenehat) => p.copyWith(
      jenehat: jenehat,
      progress: {'line_hay.01': _done, 'line_hay.02': _done},
      ownership: {
        (SkuKind.vehicle, 'micro_old'): _owned(SkuKind.vehicle),
        (SkuKind.chapter, 'ch3_shabka'): _owned(SkuKind.chapter),
      },
    );

    testWidgets('saving for the next piece: no dot', (tester) async {
      final (container, _) = await _home(tester, state: (p) => open(p, 100));
      final card = find.byType(HomeSavingsCard);
      expect(
        find.descendant(of: card, matching: find.text('الجاية: النيش')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: shows('١٠٠ / ٤٠٠ ج')),
        findsOneWidget,
      );
      expect(find.byKey(HomeSavingsCard.readyKey), findsNothing);
      expect(container.read(newDotProvider(Section.apartment)), isFalse);
    });

    testWidgets('affordable: «جاهزة للشرا!» and the dot', (tester) async {
      final (container, _) = await _home(tester, state: (p) => open(p, 500));
      expect(find.byKey(HomeSavingsCard.readyKey), findsOneWidget);
      expect(find.text('جاهزة للشرا!'), findsOneWidget);
      expect(container.read(newDotProvider(Section.apartment)), isTrue);
      expect(
        tester.widget<BottomNav>(find.byType(BottomNav)).newDots[tabSections
            .indexOf(Section.apartment)],
        isTrue,
      );
    });

    testWidgets("before the apartment: the chapter's goal", (tester) async {
      await _home(tester);
      final card = find.byType(HomeSavingsCard);
      expect(
        find.descendant(of: card, matching: find.text('خلّص خط الحي')),
        findsOneWidget,
      );
      expect(find.descendant(of: card, matching: shows('٠/٢')), findsOneWidget);
    });
  });

  group('the links', () {
    for (final (name, finder, location) in [
      ('the profile', () => find.byKey(HomeHeader.profileKey), '/settings'),
      ('the BONAT pill', () => find.byKey(HomeHeader.bonatKey), '/shop'),
      ('the fuel pill', () => find.byKey(HomeHeader.fuelKey), '/shop/fuel'),
      ('the line card', () => find.byType(HomeLineCard), '/lines'),
      ('the savings card', () => find.byType(HomeSavingsCard), '/apartment'),
    ]) {
      testWidgets('$name opens $location', (tester) async {
        await _home(tester);
        await _tap(tester, finder());
        expect(currentLocation(tester), location);
      });
    }

    for (final (name, finder) in [
      ('the street', () => find.byKey(HomeScreen.sceneKey)),
      ('the JENEHAT pill', () => find.byKey(HomeHeader.coinsKey)),
    ]) {
      testWidgets('$name is no link', (tester) async {
        await _home(tester);
        await _tap(tester, finder());
        expect(currentLocation(tester), '/home');
      });
    }
  });

  testWidgets("a finished trip's new state shows on return, with no reload", (
    tester,
  ) async {
    final (container, economy) = await _home(tester);
    expect(shows('المشوار ١ من ٣'), findsOneWidget);
    await _tap(tester, find.byKey(HomeHeader.profileKey));
    expect(find.byType(SettingsScreen), findsOneWidget);

    // A trip played and recorded meanwhile, as the result screen leaves it.
    final service = economy.service;
    final start = service.newRequestId();
    await tester.runAsync(() async {
      await service.startTrip(start, tripId: 'line_hay.01');
      await service.recordResult(
        service.newRequestId(),
        start: start,
        result: tripResult(tripId: 'line_hay.01', earnings: 15),
      );
    });
    container.read(lastFinishedTripProvider.notifier).tripId = 'line_hay.01';

    await pressBackFrames(tester);
    expect(currentLocation(tester), '/home');
    expect(_inside<HomeLineCard>(shows('المشوار ٢ من ٣')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(HomeHeader.coinsKey),
        matching: shows('١٥'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(HomeHeader.fuelKey),
        matching: shows('٤/٥'),
      ),
      findsOneWidget,
    );
  });

  group('startNextTrip', () {
    testWidgets('the checkpoint, then the card', (tester) async {
      final checkpoint = _Checkpoint()..hold();
      await _home(
        tester,
        overrides: [
          betweenTripsCheckpointProvider.overrideWithValue(checkpoint),
        ],
      );
      await _tap(tester, find.byKey(HomeStartButton.startKey));
      expect(checkpoint.passes, 1);
      // Nothing moves while the checkpoint holds, and a second tap waits
      // for the first start (M11's interstitial shows once).
      expect(currentLocation(tester), '/home');
      await _tap(tester, find.byKey(HomeStartButton.startKey));
      expect(checkpoint.passes, 1);
      checkpoint.open();
      await pumpFrames(tester);
      expect(currentLocation(tester), '/home/pre-trip/line_hay.01');
    });

    testWidgets('an empty tank: the fuel sheet, past no checkpoint', (
      tester,
    ) async {
      final checkpoint = _Checkpoint();
      await _home(
        tester,
        state: (p) => p.copyWith(
          fuel: FuelState(liters: 0, countedFromMs: p.fuel.countedFromMs),
        ),
        overrides: [
          betweenTripsCheckpointProvider.overrideWithValue(checkpoint),
        ],
      );
      expect(find.byKey(HomeStartButton.startKey), findsNothing);
      await _tap(tester, find.byKey(HomeStartButton.emptyKey));
      expect(currentLocation(tester), '/shop/fuel');
      expect(checkpoint.passes, 0);
    });

    testWidgets('a tutorial trip starts at once, past the checkpoint', (
      tester,
    ) async {
      final checkpoint = _Checkpoint();
      final economy = await testEconomy(
        content: tutorialContent(),
        firstState: (nowMs) =>
            EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
              displayName: () => 'حمادة',
              progress: {tutorialTripIds.first: _done},
            ),
      );
      await preloadTripArt(tester);
      await pumpWassalApp(
        tester,
        newPlayer: true,
        content: contentTestOverrides(assets: tutorialBundledAssets()),
        economy: economyOverridesOf(economy),
        settle: false,
        settleBoot: false,
        overrides: [
          ...seededFirstSession((store) async {
            await store.markOpeningDone(0);
            await store.reachStep(2);
          }),
          betweenTripsCheckpointProvider.overrideWithValue(checkpoint),
        ],
      );
      await pumpFrames(tester);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      ).read(routerProvider);
      expect(router.state.uri.toString(), '/home');
      await _tap(tester, find.byKey(HomeStartButton.startKey));
      expect(checkpoint.passes, 1);
      expect(currentLocation(tester), '/trip/${tutorialTripIds[1]}');
    });
  });
}

/// Presses back on a screen with a clock on it.
Future<void> pressBackFrames(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await pumpFrames(tester);
}
