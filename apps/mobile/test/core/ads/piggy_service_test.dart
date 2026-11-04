import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/ads/piggy_service.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/pass.dart' show SyncTrigger;
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';

import '../../helpers/ads.dart';
import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/piggy.dart';
import '../../helpers/trip.dart' show opCount;

// The morning piggy (specs/018-m11-ads, research R12, T045): the ad with
// its verification, the asks at 1, 3 and 7 s, the outcomes, and
// `ad_reward_seen`. The waits are recorded instead of slept.

const _player = '0192f3a1-7b2c-7d4e-8f00-00000000beef';

final class _Piggy {
  _Piggy(this.rig, this.server, this.service, this.waits, this.syncs);

  final AdsRig rig;
  final ScriptedPiggyServer server;
  final PiggyService service;

  /// The time since the reward of each ask, in ms.
  final List<int> waits;
  final List<SyncTrigger> syncs;

  FakeAdsGateway get gateway => rig.gateway;
}

Future<_Piggy> _open({
  List<ApiResult> answers = const [],
  FakeAdsGateway? gateway,
  String? player = _player,
}) async {
  // The piggy's ad loaded on Home's appearance.
  final rig = await AdsRig.open(
    gateway: gateway ?? FakeAdsGateway(ready: {AdUnit.morningPiggy}),
  );
  rig.world.adsBlock = const AdsBlock(piggyAvailable: true, unseen: []);
  await rig.service.ensureReady();
  final server = ScriptedPiggyServer(answers);
  final waits = <int>[];
  final syncs = <SyncTrigger>[];
  var at = 0;
  var nonces = 0;
  final service = PiggyService(
    ads: rig.service,
    api: PiggyApi(server),
    economy: rig.economy.service,
    playerId: () => player,
    requestSync: syncs.add,
    wait: (wait) async {
      at += wait.inMilliseconds;
      waits.add(at);
    },
    newNonce: () => '8c1f0a4e-2b7d-4c61-9a3e-5f0d2c7b9e1${nonces++}',
  );
  addTearDown(service.dispose);
  return _Piggy(rig, server, service, waits, syncs);
}

void main() {
  test('the verification: the player and the placement with a new nonce '
      'per ad', () async {
    // The first closes early; the second is watched to the end.
    final gateway = FakeAdsGateway(ready: {AdUnit.morningPiggy})
      ..script(AdUnit.morningPiggy, [const Closed(), const Rewarded()]);
    final p = await _open(answers: [piggyGranted()], gateway: gateway);
    expect(await p.service.watch(), isNull);
    p.gateway.setReadiness(AdUnit.morningPiggy, Readiness.ready);
    await p.service.watch();
    expect(
      [for (final v in p.gateway.verifications) v.userId],
      [_player, _player],
    );
    expect(
      [for (final v in p.gateway.verifications) v.customData],
      [
        '{"placement":"morning_piggy","nonce":"8c1f0a4e-2b7d-4c61-9a3e-5f0d2c7b9e10"}',
        '{"placement":"morning_piggy","nonce":"8c1f0a4e-2b7d-4c61-9a3e-5f0d2c7b9e11"}',
      ],
    );
    // Asked with the rewarded one's nonce.
    expect(p.server.requests.single.path, endsWith('9e11'));
  });

  test('Closed: no asking, and the banner stays', () async {
    final gateway = FakeAdsGateway(ready: {AdUnit.morningPiggy})
      ..script(AdUnit.morningPiggy, [const Closed()]);
    final p = await _open(gateway: gateway);
    expect(await p.service.watch(), isNull);
    expect(p.server.requests, isEmpty);
    expect(p.rig.service.offer(AdPlacement.morningPiggy), isNot(isA<Hidden>()));
  });

  test('asks at 1, 3 and 7 s, then gives up with nothing queued', () async {
    final p = await _open();
    expect(await p.service.watch(), isA<PiggyComesLater>());
    expect(p.waits, [1000, 3000, 7000]);
    expect(p.server.requests, hasLength(3));
    expect(await opCount(p.rig.economy, 'ad_reward_seen'), 0);
    expect(p.syncs, isEmpty);
    expect(p.rig.service.offer(AdPlacement.morningPiggy), isA<Hidden>());
  });

  test('granted at the second ask: no third, the op queued and a pass '
      'asked', () async {
    final p = await _open(answers: [notFound, piggyGranted()]);
    final outcome = await p.service.watch();
    expect(outcome, isA<PiggyArrivedNow>());
    final arrived = outcome! as PiggyArrivedNow;
    expect((arrived.jenehat, arrived.bonat), (30, 2));
    expect(p.server.requests, hasLength(2));
    expect(await opCount(p.rig.economy, 'ad_reward_seen'), 1);
    expect(await p.rig.economy.service.adRewardSeen(arrived.nonce), isTrue);
    expect(p.syncs, [SyncTrigger.adReward]);
    // The wallet waits for the pass: the phone grants nothing itself.
    expect(p.rig.economy.service.view.bonat, 0);
  });

  test('refused: today\'s piggy is used, and the op is queued', () async {
    final p = await _open(answers: [piggyRefused('cap_reached')]);
    expect(await p.service.watch(), isA<PiggyUsedToday>());
    expect(await opCount(p.rig.economy, 'ad_reward_seen'), 1);
    expect(p.syncs, isEmpty);
  });

  test(
    'the banner hides for the day after the reward, whatever comes',
    () async {
      for (final answers in [
        <ApiResult>[piggyGranted()],
        <ApiResult>[piggyRefused('expired')],
        <ApiResult>[],
      ]) {
        final p = await _open(answers: answers);
        await p.service.watch();
        expect(p.rig.service.offer(AdPlacement.morningPiggy), isA<Hidden>());
      }
    },
  );

  test('the rewarded trip count is written', () async {
    final p = await _open(answers: [piggyGranted()]);
    await p.service.watch();
    expect(p.rig.settings.values[lastRewardedTripKey], isNotNull);
  });

  test('asking reads true only while it asks', () async {
    final p = await _open(answers: [piggyGranted()]);
    final seen = <bool>[];
    p.service.asking.addListener(() => seen.add(p.service.asking.value));
    await p.service.watch();
    expect(seen, [true, false]);
  });

  test('no call while the probe reads true', () async {
    final p = await _open(answers: [piggyGranted()]);
    p.rig.probe.value = true;
    expect(await p.service.watch(), isNull);
    expect(p.gateway.count('show'), 0);
  });

  test('without a player, nothing', () async {
    final p = await _open(player: null);
    expect(await p.service.watch(), isNull);
    expect(p.gateway.count('show'), 0);
  });
}
