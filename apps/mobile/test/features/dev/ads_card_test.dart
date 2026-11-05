import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/dev/ads_card.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/home.dart';
import '../../helpers/pump_app.dart';

// Internal builds' ads card (specs/018-m11-ads, T032, FR-029), in the
// testers' sheet: consent and readiness, a show per placement (none while
// a trip runs), and dev's consent controls.

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdsGateway gateway, {
  Flavor flavor = Flavor.dev,
  bool started = false,
}) async {
  final container = await pumpWassalApp(
    tester,
    flavor: flavor,
    overrides: [
      adsGatewayProvider.overrideWithValue(gateway),
      // Online only to start the SDK: online, Home's piggy loads and its
      // dots never settle.
      if (started) isOnlineProvider.overrideWithValue(true),
    ],
  );
  // The SDK starts once per launch; nothing shows before it has (and the
  // start preloads every unit).
  // Not awaited inside `runAsync`: the start reads the economy, whose work
  // also needs frames.
  if (started) {
    final ads = container.read(adsServiceProvider);
    unawaited(ads.ensureReady());
    for (var i = 0; i < 50 && !ads.canRequestAds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ads.canRequestAds, isTrue);
  }
  await openDebugSheet(tester);
  await tester.ensureVisible(find.byType(AdsDebugCard));
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

String _value(WidgetTester tester, String label) {
  final row = find
      .ancestor(
        of: find.descendant(
          of: find.byType(AdsDebugCard),
          matching: find.text(label),
        ),
        matching: find.byType(Row),
      )
      .first;
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .last
      .data!;
}

/// Taps [key] and lets what it starts finish: the show's and the
/// database's work run on real time.
Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  for (var i = 0; i < 10; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

void main() {
  testWidgets('consent and each unit\'s readiness', (tester) async {
    final gateway = FakeAdsGateway(
      formShown: true,
      ready: {AdUnit.resultDouble},
    );
    await _pump(tester, gateway);
    expect(_value(tester, 'consent_form_shown'), 'true');
    expect(_value(tester, AdUnit.resultDouble.name), 'ready');
    expect(_value(tester, AdUnit.interstitial.name), 'notLoaded');
    expect(_value(tester, 'piggy_nonce'), 'none');
    expect(find.byKey(AdsDebugCard.copyKey), findsNothing);

    gateway.setReadiness(AdUnit.interstitial, Readiness.loading);
    await tester.pump();
    expect(_value(tester, AdUnit.interstitial.name), 'loading');
  });

  testWidgets('«show» shows the placement\'s unit, never while a trip runs', (
    tester,
  ) async {
    final gateway = FakeAdsGateway(ready: AdUnit.values.toSet());
    final container = await _pump(tester, gateway, started: true);
    final key = AdsDebugCard.showKey(AdPlacement.fuelRefill);
    await _tap(tester, key);
    expect(gateway.count('show', AdUnit.fuelRefill), 1);
    expect(_value(tester, 'last_show'), 'fuel_refill: rewarded');

    container.read(tripRunningProvider).value = true;
    await tester.pump();
    await tester.tap(find.byKey(key), warnIfMissed: false);
    await tester.pump();
    expect(gateway.count('show', AdUnit.fuelRefill), 1);
    container.read(tripRunningProvider).value = false;
  });

  testWidgets('dev: the test geography and «reset consent»', (tester) async {
    final gateway = FakeAdsGateway();
    await _pump(tester, gateway);
    await _tap(tester, AdsDebugCard.geographyKey(ConsentGeography.eea));
    expect(gateway.geography, ConsentGeography.eea);
    expect(_value(tester, 'test_geography'), 'eea');
    await _tap(tester, AdsDebugCard.resetKey);
    expect(gateway.consentResets, 1);
  });

  testWidgets('staging: no consent controls', (tester) async {
    await _pump(tester, FakeAdsGateway(), flavor: Flavor.staging);
    expect(find.byType(AdsDebugCard), findsOneWidget);
    expect(find.byKey(AdsDebugCard.resetKey), findsNothing);
    expect(
      find.byKey(AdsDebugCard.geographyKey(ConsentGeography.eea)),
      findsNothing,
    );
  });

  test('the callback line names the player and the reference', () {
    expect(
      AdsDebugCard.callbackLine(player: 'p-1', nonce: 'n-1'),
      'uv run manage.py ads_dev_callback --user p-1 --nonce n-1',
    );
    expect(
      AdsDebugCard.callbackLine(player: null, nonce: 'n-1'),
      'uv run manage.py ads_dev_callback --nonce n-1',
    );
  });
}
