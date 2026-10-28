// الموقف's states (specs/013-m08-home-result, contracts/home.md "States",
// US4): out of fuel and back, offline and back, maintenance, the early
// chapter, the unlimited window, the fuel lesson due and no next trip, each
// on Home without leaving it.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/home/presentation/home_header.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/features/home/presentation/street_scene.dart';

import '../../design/samples/c_home.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/progress.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/server_status.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

/// A liter every 20 minutes (the test tunables).
const _regen = Duration(minutes: 20);

/// 12:30 to the next liter.
const _toNext = Duration(minutes: 12, seconds: 30);

/// The board's scene card at 844 pt, and with the banner over it.
const _scene = 332.0;
const _sceneOffline = 282.0;

const _offline = ServerStatusState(reach: Reach.offline);

/// A checkpoint that never holds.
final class _Open implements BetweenTripsCheckpoint {
  @override
  Future<void> pass() async {}
}

/// Home for a returning player whose economy starts as [state] changes the
/// new player's.
Future<(ProviderContainer, TestEconomy)> _home(
  WidgetTester tester, {
  EconomyState Function(EconomyState player, int nowMs)? state,
  List<Override> overrides = const [],
  ServerStatusState serverStatus = const ServerStatusState(),
}) async {
  final economy = await testEconomy(
    firstState: (nowMs) {
      final player = EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs);
      return state == null ? player : state(player, nowMs);
    },
  );
  final container = await pumpWassalApp(
    tester,
    economy: economyOverridesOf(economy),
    serverStatus: serverStatus,
    overrides: [
      betweenTripsCheckpointProvider.overrideWithValue(_Open()),
      ...overrides,
    ],
    // The fuel pill's countdown ticks: nothing settles.
    settle: false,
    settleBoot: false,
  );
  await pumpFrames(tester);
  expect(find.byType(HomeScreen), findsOneWidget);
  return (container, economy);
}

/// An empty tank, [_toNext] from its next liter.
EconomyState _empty(EconomyState player, int nowMs) => player.copyWith(
  fuel: FuelState(
    liters: 0,
    countedFromMs: nowMs - (_regen - _toNext).inMilliseconds,
  ),
);

void _pin(ProviderContainer container, ServerStatusState state) =>
    (container.read(serverStatusProvider.notifier) as PinnedServerStatus).pin(
      state,
    );

double _sceneHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(HomeScreen.sceneKey)).height;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await pumpFrames(tester);
}

void main() {
  group('out of fuel', () {
    testWidgets('«البنزين خلص» with the next liter; the pill empty', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _home(tester, state: _empty);
      final button = find.byKey(HomeStartButton.emptyKey);
      expect(tester.widget(button), isA<AppButton>());
      expect(find.byKey(HomeStartButton.startKey), findsNothing);
      expect(
        find.descendant(of: button, matching: find.text('البنزين خلص')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: button,
          matching: find.text('اللتر الجاي ${_numbers.countdown(_toNext)}'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(HomeHeader.fuelKey)).label,
        startsWith('البنزين خلص'),
      );
      semantics.dispose();
    });

    for (final (name, key) in [
      ('the button', HomeStartButton.emptyKey),
      ('the pill', HomeHeader.fuelKey),
    ]) {
      testWidgets('$name opens the fuel sheet', (tester) async {
        await _home(tester, state: _empty);
        await _tap(tester, find.byKey(key));
        expect(currentLocation(tester), '/shop/fuel');
      });
    }

    testWidgets('a liter back: «يلا نطلع!», still on Home', (tester) async {
      final (_, economy) = await _home(tester, state: _empty);
      economy.passTime(_toNext);
      await tester.pump(_toNext);
      await pumpFrames(tester);
      expect(find.byKey(HomeStartButton.startKey), findsOneWidget);
      expect(find.byKey(HomeStartButton.emptyKey), findsNothing);
      expect(currentLocation(tester), '/home');
    });
  });

  group('offline', () {
    testWidgets('the banner over a shorter scene; the shop and the pill '
        'need the network; trips still start', (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await pumpCHome(tester);
      expect(_sceneHeight(tester), _scene);

      _pin(container, _offline);
      await pumpFrames(tester);
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(_sceneHeight(tester), _sceneOffline);
      expect(
        tester.getSemantics(find.byKey(BottomNav.cellKey(3))).label,
        'المحل، محتاج نت',
      );
      await _tap(tester, find.byKey(BottomNav.cellKey(3)));
      expect(currentLocation(tester), '/home');
      await _tap(tester, find.byKey(HomeHeader.bonatKey));
      expect(currentLocation(tester), '/home');

      await _tap(tester, find.byKey(HomeStartButton.startKey));
      expect(currentLocation(tester), startsWith('/home/pre-trip/'));
      semantics.dispose();
    });

    testWidgets('the network back: as before, still on Home', (tester) async {
      final container = await pumpCHome(tester);
      _pin(container, _offline);
      await pumpFrames(tester);
      _pin(container, const ServerStatusState());
      await pumpFrames(tester);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(_sceneHeight(tester), _scene);
      await _tap(tester, find.byKey(BottomNav.cellKey(3)));
      expect(currentLocation(tester), '/shop');
    });

    testWidgets('the scene shrinks over 200 ms; at once under reduced '
        'motion', (tester) async {
      final container = await pumpCHome(tester);
      _pin(container, _offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = _sceneHeight(tester);
      expect(midway, lessThan(_scene));
      expect(midway, greaterThan(_sceneOffline));

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      _pin(container, const ServerStatusState());
      await tester.pump();
      await tester.pump();
      expect(_sceneHeight(tester), _scene);
    });
  });

  testWidgets('maintenance in the banner\'s place; trips work', (tester) async {
    await _home(
      tester,
      serverStatus: const ServerStatusState(maintenance: Maintenance()),
    );
    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('الموقف بيتصلّح'), findsOneWidget);
    await _tap(tester, find.byKey(HomeStartButton.startKey));
    expect(currentLocation(tester), '/home/pre-trip/line_hay.01');
  });

  testWidgets('the early chapter: the goal card, the tuktuk with بلية', (
    tester,
  ) async {
    await _home(tester);
    final card = tester.widget<HomeSavingsCard>(find.byType(HomeSavingsCard));
    expect(card.target, isA<ChapterGoalTarget>());
    expect(
      tester.widget<StreetScene>(find.byType(StreetScene)).vehicle,
      VehicleId.tuktuk,
    );
    expect(find.byKey(StreetScene.signKey), findsNothing);
  });

  testWidgets('the unlimited window: no «−١», the time left', (tester) async {
    final semantics = tester.ensureSemantics();
    await _home(
      tester,
      state: (player, nowMs) => player.copyWith(
        fuel: FuelState(
          liters: 2,
          countedFromMs: nowMs,
          unlimitedUntilMs: nowMs + const Duration(hours: 1).inMilliseconds,
        ),
      ),
    );
    final start = find.byKey(HomeStartButton.startKey);
    expect(
      find.descendant(of: start, matching: find.byType(CostChip)),
      findsNothing,
    );
    expect(
      tester.getSemantics(find.byKey(HomeHeader.fuelKey)).label,
      startsWith('بنزين مفتوح'),
    );
    semantics.dispose();
  });

  testWidgets('the fuel lesson due: «يلا نطلع!» on an empty tank, to the '
      'trip and its lesson', (tester) async {
    final economy = await testEconomy(
      content: tutorialContent(),
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            displayName: () => 'حمادة',
            fuel: FuelState(liters: 0, countedFromMs: nowMs),
            progress: {
              tutorialTripIds.first: const TripProgress(
                bestStars: 3,
                plays: 1,
                firstCompletedAtMs: 1,
              ),
            },
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
        betweenTripsCheckpointProvider.overrideWithValue(_Open()),
      ],
    );
    await pumpFrames(tester);
    expect(find.byKey(HomeStartButton.emptyKey), findsNothing);
    await _tap(tester, find.byKey(HomeStartButton.startKey));
    expect(currentLocation(tester), startsWith('/onboarding/fuel'));
  });

  testWidgets('no next trip: the button disabled', (tester) async {
    // Nothing startable: every trip needs the microbus, which isn't owned.
    final json = sampleJsonCopy();
    for (final trip in entries(json, 'trips')) {
      trip
        ..['vehicle_id'] = 'micro_old'
        ..['kind'] = 'regular';
    }
    final economy = await testEconomy(
      content: PackContentSource(Pack.fromJson(json)),
    );
    await pumpWassalApp(
      tester,
      content: contentTestOverrides(
        assets: bundledAssetsFor(encodePackFile(json)),
      ),
      economy: economyOverridesOf(economy),
      settle: false,
      settleBoot: false,
    );
    await pumpFrames(tester);
    final button = tester.widget<AppButton>(
      find.byKey(HomeStartButton.startKey),
    );
    expect(button.enabled, isFalse);
    expect(button.onTap, isNull);
  });
}
