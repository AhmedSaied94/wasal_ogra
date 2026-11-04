@Tags(['backend'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/ads/piggy_service.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/pass.dart' show SyncTrigger;

import '../helpers/fake_ads_gateway.dart';
import '../helpers/memory_settings_store.dart';
import '../helpers/ads.dart';
import 'e2e.dart';

// The morning piggy against the dev stack (specs/018-m11-ads, T052,
// quickstart §4.5): the phone watches with a fake gateway, a signed SSV
// callback reaches the server as Google's would, the phone's asks find the
// grant within 7 s, the pass rebases the wallet, and once `ad_reward_seen`
// syncs the bootstrap lists nothing unseen.
//
// The callback is signed by the command in `WASSAL_E2E_ADS_CALLBACK`, with
// `--user <player_id> --nonce <reference>` appended. Locally it is
// `uv run --directory ../../backend manage.py ads_dev_callback`; CI's
// `sync-e2e` job runs it in the API container.

final _callback = Platform.environment['WASSAL_E2E_ADS_CALLBACK'];

/// A gateway whose rewarded show also fires the server's callback, as
/// Google does after a watched ad.
final class _CallbackGateway implements AdsGateway {
  final _inner = FakeAdsGateway(ready: AdUnit.values.toSet());

  @override
  Future<bool> start(RequestConfig config) => _inner.start(config);

  @override
  Future<bool> privacyOptionsRequired() => _inner.privacyOptionsRequired();

  @override
  Future<bool> showPrivacyOptions() => _inner.showPrivacyOptions();

  @override
  Future<bool> mayRequestAds() => _inner.mayRequestAds();

  @override
  Future<void> load(AdUnit unit) => _inner.load(unit);

  @override
  ValueListenable<Readiness> readiness(AdUnit unit) => _inner.readiness(unit);

  @override
  Future<ShowOutcome> show(
    AdUnit unit, {
    PiggyVerification? verification,
  }) async {
    final outcome = await _inner.show(unit, verification: verification);
    if (verification != null) {
      final nonce = RegExp(r'"nonce":"([^"]+)"')
          .firstMatch(verification.customData)!
          .group(1)!;
      final parts = _callback!.split(' ');
      final result = await Process.run(parts.first, [
        ...parts.skip(1),
        '--user',
        verification.userId,
        '--nonce',
        nonce,
        '--api',
        e2eApiBase,
      ]);
      if (result.exitCode != 0) {
        fail('the callback failed: ${result.stdout} ${result.stderr}');
      }
    }
    return outcome;
  }
}

Future<AdsBlock> _ads(E2eDevice device) async {
  final result = await device.account.authorized.send(
    const ApiRequest.get(
      ApiPaths.bootstrap,
      receiveTimeout: readReceiveTimeout,
    ),
  );
  if (result is! ApiOk) fail('bootstrap: $result');
  return AdsBlock.fromJson(result.json['ads']);
}

void main() {
  setUpAll(useRealHttp);

  test(
    'granted within 7 s, the wallet rebased, and seen once synced',
    skip: _callback == null
        ? 'WASSAL_E2E_ADS_CALLBACK is not set: the callback needs the dev '
              'stack\'s signing command (quickstart §4.5)'
        : false,
    () async {
      final device = await e2eDevice();
      final engine = e2eEngine(device);
      expect(await device.account.ensureSession(), isTrue);
      final player = device.account.playerId!;
      await engine.syncNow();
      final before = await _ads(device);
      expect(before.piggyAvailable, isTrue);

      final world = FakeAdsWorld(device.economy)..adsBlock = before;
      final gateway = _CallbackGateway();
      final ads = AdsServiceImpl(
        gateway: gateway,
        economy: device.economy.service,
        settings: MemorySettingsStore(),
        world: world,
        probe: ValueNotifier(false),
      );
      addTearDown(ads.dispose);
      final syncs = <SyncTrigger>[];
      final piggy = PiggyService(
        ads: ads,
        api: PiggyApi(device.account.authorized),
        economy: device.economy.service,
        playerId: () => player,
        requestSync: syncs.add,
      );
      addTearDown(piggy.dispose);

      final watch = Stopwatch()..start();
      final outcome = await piggy.watch();
      expect(outcome, isA<PiggyArrivedNow>(), reason: '$outcome');
      expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 8)));
      final arrived = outcome! as PiggyArrivedNow;
      expect(arrived.jenehat + arrived.bonat, greaterThan(0));
      expect(syncs, [SyncTrigger.adReward]);

      // The pass takes the grant and sends `ad_reward_seen`.
      final bonat = device.economy.service.view.bonat;
      await engine.syncNow();
      expect(device.economy.service.view.bonat, bonat + arrived.bonat);
      expect(device.economy.service.pendingCount, 0);

      final after = await _ads(device);
      expect(after.piggyAvailable, isFalse);
      expect(after.unseen.where((g) => g.nonce == arrived.nonce), isEmpty);
    },
  );
}
