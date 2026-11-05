// An empty tank through the refill ad (specs/018-m11-ads, US5, T061;
// constitution XIII), on one trip screen with the fake ad gateway: the
// start is refused for fuel, the refill ad fills the tank and the trip
// starts; «عيد المشوار» burns the tank down again, and the trip opened
// again from the stand is refused, three times; the fourth
// empty tank says «خلصت النهارده» with the BONAT refill still beside it.
// Headless:
//
//   fvm flutter test integration_test/fuel_ad_test.dart -d flutter-tester
import 'package:flutter/widgets.dart' show Navigator;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/fuel/presentation/fuel_refill_ad_offer.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/no_fuel_card.dart';
import 'package:wassal/features/trip/presentation/trip_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../test/helpers/economy.dart';
import '../test/helpers/fake_ads_gateway.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

/// `pumpTrip`'s trip.
const _trip = '/trip/line_hay.01';

/// The refill ad's daily cap (the `ads_fuel_refill_daily_cap` default).
const _cap = 3;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the refill ad, to the cap', (tester) async {
    final economy = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(fuel: FuelState(liters: 0, countedFromMs: nowMs), bonat: 100),
    );
    final gateway = FakeAdsGateway(ready: {AdUnit.fuelRefill});
    final container = await pumpTrip(
      tester,
      economy: economy,
      // The empty tank's card ticks every second: nothing settles.
      settle: false,
      overrides: [
        adsGatewayProvider.overrideWithValue(gateway),
        isOnlineProvider.overrideWithValue(true),
      ],
    );
    await tester.runAsync(container.read(adsServiceProvider).ensureReady);
    await tester.pump();
    bool onTrip() => find.byType(TripScreen).evaluate().isNotEmpty;
    bool phaseIs(TripPhase phase) =>
        onTrip() && controllerOf(tester).phase == phase;
    String phase() =>
        onTrip() ? 'phase ${controllerOf(tester).phase.name}' : 'no trip';

    for (var refill = 1; refill <= _cap; refill++) {
      await pumpUntil(
        tester,
        () => phaseIs(TripPhase.noFuel),
        describe: () => 'refill $refill: ${phase()}',
      );
      await pumpUntil(
        tester,
        () => find.byKey(FuelRefillAdOffer.adKey).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(FuelRefillAdOffer.adKey));
      await pumpUntil(
        tester,
        () => phaseIs(TripPhase.running),
        describe: phase,
      );
      expect(gateway.count('show', AdUnit.fuelRefill), refill);
      expect(await opCount(economy, 'ad_reward'), refill);

      // «عيد المشوار» while a liter is left, then back to the stand and
      // the trip again, which the empty tank refuses.
      for (var left = economy.service.view.fuel.liters; left > 0; left--) {
        expect(phaseIs(TripPhase.running), isTrue, reason: phase());
        controllerOf(tester).pause(PauseReason.button);
        await tester.pump();
        await tester.runAsync(controllerOf(tester).restart);
        await tester.pump();
      }
      expect(economy.service.view.fuel.liters, 0);
      // The way out is the pause card's.
      controllerOf(tester).pause(PauseReason.button);
      await tester.pump();
      await tester.runAsync(controllerOf(tester).leave);
      await pumpUntil(
        tester,
        () => !onTrip(),
        describe: () => 'refill $refill: still on the trip, ${phase()}',
      );
      GoRouter.of(tester.element(find.byType(Navigator).first)).go(_trip);
      await tester.pump();
    }

    await pumpUntil(tester, () => phaseIs(TripPhase.noFuel), describe: phase);
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(NoFuelCard)));
    expect(
      find.descendant(
        of: find.byKey(FuelRefillAdOffer.adKey),
        matching: find.text(l10n.adLimitReached),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(FuelRefillAdOffer.bonatKey),
        matching: find.text(l10n.refillBonatTitle),
      ),
      findsOneWidget,
    );
    // The tile at the cap does nothing.
    await tester.tap(find.byKey(FuelRefillAdOffer.adKey));
    await tester.pump(const Duration(milliseconds: 500));
    expect(gateway.count('show', AdUnit.fuelRefill), _cap);
    expect(phaseIs(TripPhase.noFuel), isTrue);
  });
}
