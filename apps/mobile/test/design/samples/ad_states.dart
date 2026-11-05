import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../helpers/economy.dart';
import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../design_check.dart';
import 'c_trip.dart';
import 'trip_events.dart';

// M11's trip-screen boards (specs/018-m11-ads, T064): `BoosterAdCard`,
// «زحمة» with none left, its ad ready and its price 8 with 45 BONAT; and
// `NoFuelAd` / `NoFuelAdLimit`, the start refused for an empty tank, the
// next liter in 12:30, the refill ad with 3 left or none, and the BONAT
// refill at the draft's 30. The engine never sees the booster card's
// cabin; the no-fuel boards are the real refusal on an empty tank.

/// `BoosterAdCard`'s balance and «زحمة»'s price.
const boosterAdBonat = 45;
const boosterAdPrice = 8;

/// The next free liter on the no-fuel boards: 12:30.
const noFuelNextMs = (12 * 60 + 30) * 1000;

TripModel boosterAdModel() => TripModel(
  phase: TripPhase.boosterCard,
  view: tripEventsView(),
  boosterCard: const BoosterCardModel(
    booster: BoosterId.trafficJam,
    priceBonat: boosterAdPrice,
    bonat: boosterAdBonat,
    shortBy: null,
    ad: AdSlot.ready,
  ),
);

/// The trip screen on the reference frame, with «زحمة»'s card as
/// `BoosterAdCard` draws it.
Future<void> pumpBoosterAdCard(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(tester, tripId: cTripId, digits: digits);
  controllerOf(tester).debugShowModel(boosterAdModel());
  await tester.pumpAndSettle();
}

var _rows = 0x700;

Future<TestEconomy> _emptyTank(int refillsToday) async {
  final economy = await testEconomy(
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          fuel: FuelState(liters: 0, countedFromMs: nowMs),
          bonat: boosterAdBonat,
        ),
  );
  for (var i = 0; i < refillsToday; i++) {
    await economy.db.customStatement(
      'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
      'content_version, fuel_max, fuel_regen_minutes) VALUES '
      "('0192f3a1-7b2c-7d4e-8f00-"
      "${(_rows++).toRadixString(16).padLeft(12, '0')}', "
      '\'ad_reward\', \'{"ad_placement":"fuel_refill"}\', '
      '${economy.clock.nowMs()}, 1, 5, 20)',
    );
  }
  return economy;
}

List<Override> _readyAds() => [
  adsGatewayProvider.overrideWithValue(
    FakeAdsGateway(ready: {AdUnit.fuelRefill}),
  ),
  isOnlineProvider.overrideWithValue(true),
];

/// The trip screen refused for an empty tank, with [refillsToday] refill
/// ads already watched today (3: `NoFuelAdLimit`).
Future<void> pumpNoFuelAd(
  WidgetTester tester, {
  int refillsToday = 0,
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  final economy = await _emptyTank(refillsToday);
  final container = await pumpTrip(
    tester,
    tripId: cTripId,
    digits: digits,
    economy: economy,
    overrides: _readyAds(),
  );
  await container.read(adsServiceProvider).ensureReady();
  await tester.pump();
  final now = container.read(trustedClockProvider).requireValue.nowMs();
  controllerOf(tester).debugShowModel(
    TripModel(phase: TripPhase.noFuel, nextLiterAtMs: now + noFuelNextMs),
  );
  await tester.pump();
  await tester.pump();
}

/// M12's fuel sheet's stand-in (`/shop/fuel`) with the same offer, on an
/// empty tank (T060).
Future<void> pumpFuelPlaceholder(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  final economy = await _emptyTank(0);
  applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  final container = await pumpWassalApp(
    tester,
    digits: digits,
    economy: economyOverridesOf(economy),
    initialLocation: '/shop/fuel',
    overrides: _readyAds(),
  );
  await container.read(adsServiceProvider).ensureReady();
  await tester.pumpAndSettle();
}
