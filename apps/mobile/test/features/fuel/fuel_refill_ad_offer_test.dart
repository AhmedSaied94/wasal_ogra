import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/economy/domain/spend_rules.dart' show refuelFullSku;
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/fuel/presentation/fuel_refill_ad_offer.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/no_fuel_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/economy.dart';
import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/trip.dart';

// The refill offer on the out-of-fuel card (specs/018-m11-ads, US5, T059):
// the ad's states, the BONAT refill beside it in every one of them
// (constitution IX), the reward or the purchase filling the tank once and
// starting the trip.

int get _refillPrice =>
    sampleContent().price(SkuKind.fuel, refuelFullSku)!.amount;

var _rows = 0x500;

/// An earlier refill ad today, as the log holds it.
Future<void> _refillToday(TestEconomy e) => e.db.customStatement(
  'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
  'content_version, fuel_max, fuel_regen_minutes) VALUES '
  "('0192f3a1-7b2c-7d4e-8f00-${(_rows++).toRadixString(16).padLeft(12, '0')}', "
  '\'ad_reward\', \'{"ad_placement":"fuel_refill"}\', '
  '${e.clock.nowMs()}, 1, 5, 20)',
);

/// An empty tank opens the card; the ads are started.
Future<(ProviderContainer, TestEconomy)> _card(
  WidgetTester tester, {
  int bonat = 100,
  int refillsToday = 0,
  bool online = true,
  FakeAdsGateway? gateway,
  bool started = true,
}) async {
  final economy = await testEconomy(
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          fuel: FuelState(liters: 0, countedFromMs: nowMs),
          bonat: bonat,
        ),
  );
  for (var i = 0; i < refillsToday; i++) {
    await _refillToday(economy);
  }
  final container = await pumpTrip(
    tester,
    economy: economy,
    overrides: [
      adsGatewayProvider.overrideWithValue(
        gateway ?? FakeAdsGateway(ready: {AdUnit.fuelRefill}),
      ),
      isOnlineProvider.overrideWithValue(online),
      if (!started) adWarmUpProvider.overrideWith(liveAdWarmUp),
    ],
  );
  if (started) await container.read(adsServiceProvider).ensureReady();
  await tester.pump();
  await tester.pump();
  expect(controllerOf(tester).phase, TripPhase.noFuel);
  return (container, economy);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(NoFuelCard)));

String _n(ProviderContainer c, int n) =>
    c.read(numberFormatterProvider).integer(n);

Finder _inAd(Finder f) =>
    find.descendant(of: find.byKey(FuelRefillAdOffer.adKey), matching: f);

Future<void> _settleTaps(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The BONAT refill: «فوّل الخزان» with its price chip.
void _expectBonatTile(WidgetTester tester, ProviderContainer c) {
  final l10n = _l10n(tester);
  final tile = find.byKey(FuelRefillAdOffer.bonatKey);
  expect(tile, findsOneWidget);
  expect(
    find.descendant(of: tile, matching: find.text(l10n.refillBonatTitle)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: tile,
      matching: find.text(l10n.tripBoosterPriceBadge(_n(c, _refillPrice))),
    ),
    findsOneWidget,
  );
}

void main() {
  testWidgets('a cold start: the card starts the ads and loads its unit', (
    tester,
  ) async {
    // An empty tank goes to the card before any checkpoint (review H1).
    final gateway = FakeAdsGateway();
    await _card(tester, gateway: gateway, started: false);
    await _settleTaps(tester);
    expect(gateway.count('start'), 1);
    expect(gateway.count('load', AdUnit.fuelRefill), greaterThanOrEqualTo(1));
  });

  testWidgets('ready, with 3, 2 and 1 left today', (tester) async {
    for (final done in [0, 1, 2]) {
      final (c, _) = await _card(tester, refillsToday: done);
      final left = 3 - done;
      expect(
        _inAd(find.text(_l10n(tester).refillAdLeft(left, _n(c, left)))),
        findsOneWidget,
        reason: '$done done',
      );
      _expectBonatTile(tester, c);
    }
  });

  testWidgets('the limit at 3, with the BONAT refill still beside it', (
    tester,
  ) async {
    final (c, _) = await _card(tester, refillsToday: 3);
    expect(_inAd(find.text(_l10n(tester).adLimitReached)), findsOneWidget);
    _expectBonatTile(tester, c);
  });

  testWidgets('not ready, and offline', (tester) async {
    final (c, _) = await _card(
      tester,
      gateway: FakeAdsGateway(loadsBecomeReady: false),
    );
    expect(_inAd(find.text(_l10n(tester).adNotReady)), findsOneWidget);
    _expectBonatTile(tester, c);
  });

  testWidgets('offline', (tester) async {
    final (c, _) = await _card(tester, online: false);
    expect(_inAd(find.text(_l10n(tester).adNeedsNetwork)), findsOneWidget);
    _expectBonatTile(tester, c);
  });

  testWidgets('the reward fills the tank once, and the trip starts', (
    tester,
  ) async {
    final (c, economy) = await _card(tester);
    await tester.tap(find.byKey(FuelRefillAdOffer.adKey));
    await _settleTaps(tester);
    expect(await opCount(economy, 'ad_reward'), 1);
    expect(controllerOf(tester).phase, TripPhase.running);
    // The start took its liter from the full tank.
    final fuel = c.read(economyViewProvider).fuel;
    expect(fuel.liters, fuel.max - 1);
  });

  testWidgets('the BONAT refill fills the tank, and the trip starts', (
    tester,
  ) async {
    final (c, _) = await _card(tester, bonat: _refillPrice);
    await tester.tap(find.byKey(FuelRefillAdOffer.bonatKey));
    await _settleTaps(tester);
    expect(c.read(economyViewProvider).bonat, 0);
    expect(controllerOf(tester).phase, TripPhase.running);
  });

  testWidgets('short of BONAT: «ناقصك …», and the tank stays empty', (
    tester,
  ) async {
    final (c, _) = await _card(tester, bonat: _refillPrice - 5);
    await tester.tap(find.byKey(FuelRefillAdOffer.bonatKey));
    await _settleTaps(tester);
    expect(
      find.text(_l10n(tester).tripBoosterShort(5, _n(c, 5))),
      findsOneWidget,
    );
    expect(controllerOf(tester).phase, TripPhase.noFuel);
  });

  testWidgets('both tiles are full-size targets', (tester) async {
    await _card(tester);
    for (final key in [FuelRefillAdOffer.adKey, FuelRefillAdOffer.bonatKey]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });
}
