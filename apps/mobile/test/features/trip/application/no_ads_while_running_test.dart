import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// No ad SDK call while a trip runs (tasks.md T083, constitution IX,
// research R20): a whole trip on screen with the traffic-jam booster, a
// failure and a revive never asks the ad seam while the engine runs, and
// no ad button shows.

void main() {
  testWidgets('a trip with a jam, a failure and a revive', (tester) async {
    final f = loadFixture('ending__revived');
    final price = sampleContent().price(SkuKind.revive, 'revive')!.amount;
    TripController? c;
    final spy = SpyTripAdOffers(engineStatus: () => c?.engine?.status);
    await pumpTrip(
      tester,
      tripId: f.definition.tripId,
      economy: await stockedEconomy(
        stock: {BoosterId.trafficJam: 1},
        bonat: price,
      ),
      fixed: FixedTrip(
        definition: f.definition,
        params: f.params,
        seed: f.seed,
      ),
      ads: spy,
    );
    c = controllerOf(tester);
    final controller = c;

    Future<void> runWhileRunning() async {
      while (controller.phase == TripPhase.running) {
        controller.advance(const Duration(milliseconds: engineStepMs));
        if (controller.engine!.state.tMs % 990 == 0) await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    advanceMs(controller, 3000);
    await tester.pump();
    await tester.tap(find.byKey(BoostersRow.slotKey(BoosterId.trafficJam)));
    await tester.pumpAndSettle();
    expect(controller.engine!.state.boostersUsed, [BoosterId.trafficJam]);

    await runWhileRunning();
    expect(controller.phase, TripPhase.failed);
    expect(controller.view!.boosters.every((s) => !s.adOffered), isTrue);
    await tester.tap(find.byKey(FailureCard.reviveKey));
    await tester.pumpAndSettle();
    expect(controller.engine!.state.revived, isTrue);

    await runWhileRunning();
    expect(controller.model.exit, isNotNull);

    // The spy fails the test if asked while the engine runs; nothing in
    // M02 offers an ad, so nothing shows one.
    expect(spy.calls, isEmpty);
  });
}
