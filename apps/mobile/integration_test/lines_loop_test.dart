// The loop from Lines (specs/014-m09-lines-vehicles, quickstart §4, SC-002,
// SC-008), offline, for a chapter-2 player with enough coins and the card
// setting on «دايمًا»: «الخطوط» opens on Home's line; the old microbus's
// tile → «اشتريها» spends its price once and makes it current; «كمّل» on
// خط الجامعة opens the card, whose close lands on the line's details; the
// details' «العب المشوار ١» → «اطلع» → the scene due before it (M10) → the
// trip by M02's scripted player → the result → Home → «الخطوط» shows the map. It also times Lines, the
// details and the sheet from the tap to their full content: each under
// 0.5 s. Headless:
//
//   fvm flutter test integration_test/lines_loop_test.dart -d flutter-tester
//
// or on a device with `--flavor dev`.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/lines/application/lines_model.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';
import 'package:wassal/features/lines/presentation/line_details_sheet.dart';
import 'package:wassal/features/lines/presentation/line_map.dart';
import 'package:wassal/features/lines/presentation/vehicle_sheet.dart';
import 'package:wassal/features/lines/presentation/vehicle_strip.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/result/presentation/result_screen.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../test/helpers/content.dart';
import '../test/helpers/economy.dart';
import '../test/helpers/lines.dart';
import '../test/helpers/memory_settings_store.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

/// SC-008: from the tap to full content.
const _openBudget = Duration(milliseconds: 500);

/// A checkpoint that never holds (M11's interstitial comes later).
final class _Open implements BetweenTripsCheckpoint {
  @override
  Future<void> pass() async {}
}

/// Taps [finder] once it can be hit.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, () => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(finder);
  await pumpUntil(tester, () => finder.hitTestable().evaluate().isNotEmpty);
  await tester.tap(finder);
}

/// Real time from a tap on [control] until [shown] can be hit.
Future<Duration> _timeOpen(
  WidgetTester tester,
  Finder control,
  Finder shown,
) async {
  await pumpUntil(tester, () => control.hitTestable().evaluate().isNotEmpty);
  final watch = Stopwatch()..start();
  await tester.tap(control);
  await pumpUntil(tester, () => shown.hitTestable().evaluate().isNotEmpty);
  return watch.elapsed;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Lines → buy the microbus → «كمّل» → the details → the trip → '
      'the result → Home → Lines, offline', (tester) async {
    final fixture = loadFixture('sample__line_gamaa_01_three_stars');
    final economy = await testEconomy(
      // Chapter 1's line done: chapter 2, saving for the microbus (1,500).
      firstState: playerState(
        jenehat: 2000,
        stars: {'line_hay.01': 3, 'line_hay.02': 3, 'line_hay.03': 3},
      ),
    );
    await preloadTripArt(tester);
    final container = await pumpWassalApp(
      tester,
      settleBoot: false,
      settle: false,
      content: contentTestOverrides(),
      economy: economyOverridesOf(economy),
      trip: tripTestOverrides(),
      settingsStore: MemorySettingsStore({
        DigitStyleNotifier.key: DigitStyle.arabicIndic.wire,
        PreTripCardModeNotifier.key: PreTripCardMode.always.wire,
      }),
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
    await pumpUntil(tester, () => currentLocation(tester) == '/home');

    // 1. «الخطوط» opens on Home's line, within SC-008.
    final lines = await _timeOpen(
      tester,
      find.byKey(BottomNav.cellKey(1)),
      find.byKey(LineMap.scrollKey),
    );
    expect(lines, lessThan(_openBudget));
    expect(currentLocation(tester), '/lines');
    expect(container.read(linesModelProvider).focus, LineId.lineHay);

    // 2. The microbus's tile → «اشتريها»: its price once, and it's current.
    final sheet = await _timeOpen(
      tester,
      find.byKey(VehicleTileView.keyOf(VehicleId.microOld)),
      find.byKey(VehicleSheet.buyKey),
    );
    expect(sheet, lessThan(_openBudget));
    await _tap(tester, find.byKey(VehicleSheet.buyKey));
    await tester.tap(find.byKey(VehicleSheet.buyKey), warnIfMissed: false);
    await pumpUntil(tester, () => currentLocation(tester) == '/lines');
    final view = container.read(economyViewProvider);
    expect(view.jenehat, 500);
    expect(view.owns(SkuKind.vehicle, 'micro_old'), isTrue);
    // M10's launch backfill also keeps a `story_progress` op: only the
    // spends are this step's.
    final pending = await tester.runAsync(economy.service.pendingOps);
    expect(
      pending!.where((row) => row.op.type == OpType.spendJenehat),
      hasLength(1),
      reason: 'one spend, kept to sync',
    );

    // 3. «كمّل» on خط الجامعة → the card; its close lands on the details.
    await _tap(tester, find.byKey(LineCard.continueKeyOf(LineId.lineGamaa)));
    await pumpUntil(
      tester,
      () =>
          currentLocation(tester) == '/lines/line_gamaa/pre-trip/line_gamaa.01',
    );
    await _tap(tester, find.byKey(PreTripCard.closeKey));
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/lines/line_gamaa',
    );

    // The details from the map, within SC-008.
    await _tap(tester, find.byKey(LineDetailsSheet.closeKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/lines');
    final details = await _timeOpen(
      tester,
      find.byKey(LineCard.keyOf(LineId.lineGamaa)),
      find.byKey(LineDetailsSheet.playKey),
    );
    expect(details, lessThan(_openBudget));

    // 4. «العب المشوار ١» → «اطلع» → the trip, to the end.
    await _tap(tester, find.byKey(LineDetailsSheet.playKey));
    await pumpUntil(
      tester,
      () =>
          currentLocation(tester) == '/lines/line_gamaa/pre-trip/line_gamaa.01',
    );
    await _tap(tester, find.byKey(PreTripCard.goKey));
    // M10: the scene due before this trip plays first, then the trip opens.
    await pumpUntil(
      tester,
      () => currentLocation(tester).startsWith('/story/scene/'),
    );
    expect(
      currentLocation(tester),
      '/story/scene/father_visit?then=%2Ftrip%2Fline_gamaa.01',
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(SceneViewerPage.panelKey)
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    for (
      var i = 0;
      i < 12 && find.byKey(SceneViewerPage.continueKey).evaluate().isEmpty;
      i++
    ) {
      await tester.tap(find.byKey(SceneViewerPage.panelKey));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
    }
    await _tap(tester, find.byKey(SceneViewerPage.continueKey));
    await pumpUntil(
      tester,
      () =>
          currentLocation(tester) == '/trip/line_gamaa.01' &&
          find.byType(TripDashboard).evaluate().isNotEmpty &&
          controllerOf(tester).phase == TripPhase.running,
    );
    final run = await ScriptedPlayer(tester, fixture).drive(
      settle: () => pumpUntil(
        tester,
        () => currentLocation(tester) == '/trip/line_gamaa.01/result',
      ),
    );
    expect(run.result!.outcome, TripOutcome.finished);

    // 5. The result → Home → «الخطوط»: the map, not the card.
    await _tap(tester, find.byKey(ResultScreen.backKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/home');
    await _tap(tester, find.byKey(BottomNav.cellKey(1)));
    await pumpUntil(tester, () => currentLocation(tester) == '/lines');
    // خط الجامعة's next trip is now its second, and its first keeps the
    // star the result earned (T108).
    final gamaa = container
        .read(linesModelProvider)
        .cards
        .firstWhere((card) => card.line == LineId.lineGamaa);
    expect((gamaa.state as LineCurrent).next.number, 2);
    expect(
      container.read(playerProgressProvider).starsOf('line_gamaa.01'),
      greaterThanOrEqualTo(1),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(LineCard.continueKeyOf(LineId.lineGamaa))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(PreTripCard), findsNothing);
  });
}
