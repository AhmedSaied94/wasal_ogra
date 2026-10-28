// The loop from الموقف (specs/013-m08-home-result SC-001, SC-002, SC-004),
// offline, for a player whose tutorial is done: Home shows the next trip,
// «يلا نطلع!» opens its card, «اطلع» starts it, M02's scripted player
// finishes it, the result shows the trip's own figures, and «مشوار تاني»
// opens the next trip's card, which closes onto a Home that moved on. It
// also times Home's first frame with the new figures after the result's
// back, and after a tab switch: each under a second. Headless:
//
//   fvm flutter test integration_test/home_loop_test.dart -d flutter-tester
//
// or on a device with `--flavor dev`.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show Text;
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/home/presentation/line_card.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/result/presentation/breakdown_card.dart';
import 'package:wassal/features/result/presentation/pay_block.dart';
import 'package:wassal/features/result/presentation/result_screen.dart';
import 'package:wassal/features/result/presentation/result_stars.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../test/helpers/content.dart';
import '../test/helpers/economy.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

/// SC-002: Home's first frame with the new figures, under a second.
const _homeBudget = Duration(seconds: 1);

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

/// A checkpoint that never holds (M11's interstitial comes later).
final class _Open implements BetweenTripsCheckpoint {
  @override
  Future<void> pass() async {}
}

/// Taps [finder] once it can be hit: pages come in with a transition, and
/// the result scrolls its bottom row into view.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, () => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(finder);
  await pumpUntil(tester, () => finder.hitTestable().evaluate().isNotEmpty);
  await tester.tap(finder);
}

/// The line card's trip number, or null while Home isn't showing (a page
/// over it puts it offstage).
int? _lineCardTrip(WidgetTester tester) {
  final card = find.byType(HomeLineCard).evaluate();
  return card.isEmpty
      ? null
      : (card.first.widget as HomeLineCard).figures.tripIndex;
}

/// Real time from a tap on [control] until Home is back with trip [index]
/// on its line card. The tap waits until [control] can take it.
Future<Duration> _timeHome(
  WidgetTester tester,
  Finder control,
  int index,
) async {
  await pumpUntil(tester, () => control.hitTestable().evaluate().isNotEmpty);
  final watch = Stopwatch()..start();
  await tester.tap(control);
  await pumpUntil(
    tester,
    () => currentLocation(tester) == '/home' && _lineCardTrip(tester) == index,
  );
  return watch.elapsed;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home → card → trip → result → the next card → Home, '
      'offline', (tester) async {
    final fixture = loadFixture('sample__line_hay_01_three_stars');
    final economy = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs),
    );
    await preloadTripArt(tester);
    final container = await pumpWassalApp(
      tester,
      settleBoot: false,
      settle: false,
      content: contentTestOverrides(),
      economy: economyOverridesOf(economy),
      trip: tripTestOverrides(),
      overrides: [
        betweenTripsCheckpointProvider.overrideWithValue(_Open()),
        tripFixedProvider.overrideWithValue(
          FixedTrip(
            definition: fixture.definition,
            params: fixture.params,
            seed: fixture.seed,
          ),
        ),
      ],
    );

    // 1. Home shows the next trip: the line's first.
    await pumpUntil(tester, () => _lineCardTrip(tester) == 1);
    final before = container.read(economyViewProvider).jenehat;

    // 2. «يلا نطلع!» → the card → «اطلع».
    await _tap(tester, find.byKey(HomeStartButton.startKey));
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/home/pre-trip/line_hay.01',
    );
    await _tap(tester, find.byKey(PreTripCard.goKey));

    // 3. The trip, to the end.
    await pumpUntil(
      tester,
      () =>
          currentLocation(tester) == '/trip/line_hay.01' &&
          find.byType(TripDashboard).evaluate().isNotEmpty &&
          controllerOf(tester).phase == TripPhase.running,
    );
    final run = await ScriptedPlayer(tester, fixture).drive(
      settle: () => pumpUntil(
        tester,
        () => currentLocation(tester) == '/trip/line_hay.01/result',
      ),
    );
    final result = run.result!;
    expect(result.outcome, TripOutcome.finished);
    if (!run.inexact) {
      expect(result.toJson(), fixture.expectedResult.toJson());
    }

    // 4. The result's figures: the trip's own.
    await pumpUntil(
      tester,
      () => find.byType(ResultStars).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<ResultStars>(find.byType(ResultStars)).stars,
      result.stars,
    );
    expect(
      find.descendant(
        of: find.byKey(BreakdownCard.faresKey),
        matching: find.text(_numbers.piasters(result.faresCollectedPiasters)),
      ),
      findsOneWidget,
    );
    await pumpUntil(
      tester,
      () =>
          tester.widget<Text>(find.byKey(PayBlock.amountKey)).data ==
          _numbers.integer(result.earningsJenehat),
    );
    expect(
      container.read(economyViewProvider).jenehat,
      before + result.earningsJenehat,
    );

    // 5. «مشوار تاني» → the next card → close → Home, moved on.
    await _tap(tester, find.byKey(ResultScreen.againKey));
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/home/pre-trip/line_hay.02',
    );
    await _tap(tester, find.byKey(PreTripCard.closeKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/home');
    // The card slides away; then Home's line card shows trip 2.
    await pumpUntil(tester, () => _lineCardTrip(tester) == 2);

    // SC-002 from the result: its back, to Home's first frame with the
    // new figures. The trip's result again, as the last pay.
    container.read(routerProvider).go('/trip/line_hay.01/result');
    // Once it has replaced Home: leaving mid-slide would build the tabs
    // again while the old ones are still going.
    await pumpUntil(
      tester,
      () =>
          find
              .byKey(ResultScreen.backKey)
              .hitTestable()
              .evaluate()
              .isNotEmpty &&
          find.byType(HomeScreen, skipOffstage: false).evaluate().isEmpty,
    );
    expect(
      await _timeHome(tester, find.byKey(ResultScreen.backKey), 2),
      lessThan(_homeBudget),
    );

    // SC-002 from a tab: Home's first frame on its way back.
    await _tap(tester, find.byKey(BottomNav.cellKey(1)));
    await pumpUntil(tester, () => currentLocation(tester) == '/lines');
    expect(
      await _timeHome(tester, find.byKey(BottomNav.cellKey(0)), 2),
      lessThan(_homeBudget),
    );
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
