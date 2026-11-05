import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_trip_offers.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/trip/domain/ad_slot.dart';

import '../../helpers/ads.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/trip.dart' show opCount;

// The trip's seam over the ads service (specs/018-m11-ads, contracts/seams.md
// "`TripAdOffers`", T037): `slot` reads caches only, at any time; `show`
// never runs while the probe reads true.

final _start = TxnId.parse('0192f3a1-7b2c-7d4e-8f00-0000000000bb');

/// A player in the middle of a trip, with [jams] «زحمة» left and
/// [jamAds] ad «زحمة» used in it.
Future<TestEconomy> _inTrip({int jams = 0, int jamAds = 0}) => testEconomy(
  firstState: (nowMs) =>
      EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
        inventory: {BoosterId.trafficJam: jams},
        unfinished: () => UnfinishedTrip(
          startTxn: _start,
          tripId: 'line_hay.01',
          contentVersion: 1,
          maxEarningsJenehat: 100,
          startedAtMs: nowMs,
          trafficJamAds: jamAds,
        ),
      ),
);

Future<(AdsRig, AdsTripOffers)> _offers(TestEconomy economy) async {
  final rig = await AdsRig.open(economy: economy);
  await rig.service.ensureReady();
  return (rig, AdsTripOffers(rig.service));
}

void main() {
  test(
    'slot reads caches only, and may be asked while the trip runs',
    () async {
      final (rig, offers) = await _offers(await _inTrip());
      final before = rig.gateway.calls.length;
      rig.probe.value = true;
      expect(offers.slot(AdPlacement.trafficJam), AdSlot.ready);
      expect(offers.slot(AdPlacement.tripRevive), AdSlot.ready);
      expect(rig.gateway.calls.length, before);
    },
  );

  test('show while the probe reads true does nothing', () async {
    final (rig, offers) = await _offers(await _inTrip());
    rig.probe.value = true;
    expect(await offers.show(AdPlacement.trafficJam), isFalse);
    expect(rig.gateway.count('show'), 0);
    rig.probe.value = false;
    expect(await offers.show(AdPlacement.trafficJam), isTrue);
    expect(rig.gateway.count('show', AdUnit.trafficJam), 1);
  });

  test('show applies no reward: the controller does', () async {
    final economy = await _inTrip();
    final (_, offers) = await _offers(economy);
    expect(await offers.show(AdPlacement.tripRevive), isTrue);
    expect(await opCount(economy, 'ad_reward'), 0);
  });

  test('the «زحمة» ad only with none left and none used this trip', () async {
    final (_, none) = await _offers(await _inTrip());
    expect(none.slot(AdPlacement.trafficJam), AdSlot.ready);
    final (_, stocked) = await _offers(await _inTrip(jams: 1));
    expect(stocked.slot(AdPlacement.trafficJam), AdSlot.hidden);
    final (_, used) = await _offers(await _inTrip(jamAds: 1));
    expect(used.slot(AdPlacement.trafficJam), AdSlot.hidden);
  });

  test('not loaded, and offline', () async {
    final rig = await AdsRig.open(
      economy: await _inTrip(),
      gateway: FakeAdsGateway(loadsBecomeReady: false),
    );
    await rig.service.ensureReady();
    final offers = AdsTripOffers(rig.service);
    expect(offers.slot(AdPlacement.tripRevive), AdSlot.notReady);
    rig.world.online = false;
    expect(offers.slot(AdPlacement.tripRevive), AdSlot.offline);
  });
}
