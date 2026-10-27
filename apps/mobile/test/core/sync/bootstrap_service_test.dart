import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/bootstrap_service.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/sync_engine.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/sync.dart';

// The bootstrap (specs/011-m06-identity-sync research R15): its spacing,
// trusted time, the cached blocks and what follows the answer.

/// Two hours after the test economy's clock, so the anchor moves it.
final _serverTime = msToIso(testEpochMs + 2 * 3600 * 1000);

final class _Clients implements ClientBlockSink {
  final blocks = <ClientBlock>[];

  @override
  void client(ClientBlock block) => blocks.add(block);
}

final class _Rig {
  _Rig._(this.economy, this.store, this.api);

  static Future<_Rig> create({int activeContentVersion = 1}) async {
    final economy = await testEconomy();
    final store = await testAccountStore(economy);
    final api = FakeApi(
      elapsedMs: () => economy.uptime.elapsedRealtimeMs,
      latency: const Duration(milliseconds: 400),
      wait: (d) async => economy.passTime(d),
    );
    final rig = _Rig._(economy, store, api);
    rig.service = BootstrapService(
      api: PlainAuthorizedApi(api),
      store: store,
      economy: economy.service,
      writeProfile: rig._profile,
      checkContent: () async => rig.contentChecks++,
      activeContentVersion: () => activeContentVersion,
      nowMs: economy.clock.nowMs,
      elapsedMs: () => economy.uptime.elapsedRealtimeMs,
      clients: rig.clients,
    );
    return rig;
  }

  final TestEconomy economy;
  final DriftAccountStore store;
  final FakeApi api;
  final clients = _Clients();
  late final BootstrapService service;
  int contentChecks = 0;
  final profiles = <(String?, int?, List<String>?)>[];

  Future<void> _profile({
    String? displayName,
    int? driverLevel,
    List<String>? providers,
  }) async => profiles.add((displayName, driverLevel, providers));

  void answer(Map<String, Object?> json) =>
      api.always('GET', ApiPaths.bootstrap, apiOk(json));

  int get bootstraps => api.to(ApiPaths.bootstrap).length;
}

void main() {
  test('none within 60 s of the last success, unless forced', () async {
    final rig = await _Rig.create();
    rig.answer(bootstrapJson());

    expect(await rig.service.refresh(), isTrue);
    rig.economy.passTime(const Duration(seconds: 59));
    expect(await rig.service.refresh(), isFalse);
    expect(rig.bootstraps, 1);

    expect(await rig.service.refresh(force: true), isTrue);
    expect(rig.bootstraps, 2);

    rig.economy.passTime(const Duration(seconds: 61));
    expect(await rig.service.refresh(), isTrue);
    expect(rig.bootstraps, 3);
  });

  test('a failure doesn\'t count as a success', () async {
    final rig = await _Rig.create();
    rig.api.reply('GET', ApiPaths.bootstrap, [
      unreachable,
      apiOk({'server_time': 'nope'}),
    ]);
    rig.answer(bootstrapJson());

    expect(await rig.service.refresh(), isFalse);
    expect(await rig.service.refresh(), isFalse, reason: 'malformed');
    expect(await rig.service.refresh(), isTrue);
  });

  test('trusted time anchors on server_time + rtt / 2', () async {
    final rig = await _Rig.create();
    rig.answer(bootstrapJson(serverTime: _serverTime));

    await rig.service.refresh();

    // 400 ms there and back: the server's clock was 200 ms behind the
    // answer's arrival.
    expect(rig.economy.clock.nowMs(), isoToMs(_serverTime) + 200);
  });

  test('the cache row, and a fresh store reads it offline', () async {
    final rig = await _Rig.create();
    rig.answer(bootstrapJson(stateVersion: 77, comebackClaimable: true));

    await rig.service.refresh();

    final info = rig.store.serverInfo;
    expect(info.receivedAtMs, rig.economy.clock.nowMs());
    expect(info.serverTimeMs, isoToMs('2026-10-17T09:00:00Z'));
    expect(info.stateVersion, 77);
    expect(info.contentVersion, 1);
    expect(info.comebackClaimable, isTrue);
    expect(jsonDecode(info.clientJson!), bootstrapJson()['client']);
    expect(jsonDecode(info.entitlementsJson!), bootstrapJson()['entitlements']);
    expect(jsonDecode(info.dailyJson!), bootstrapJson()['daily']);

    final again = await testAccountStore(rig.economy);
    expect(again.serverInfo.stateVersion, 77);
    expect(again.serverInfo.entitlements.removeAds, isTrue);
    expect(again.serverInfo.entitlements.fuelMaxBonus, 2);
    expect(again.serverInfo.daily!.rewardClaimable, isTrue);
    expect(again.serverInfo.client!.latestVersion, '1.2.0');
  });

  test(
    'the profile goes to the account, the client block to its sink',
    () async {
      final rig = await _Rig.create();
      rig.answer(bootstrapJson(forceUpdate: true));

      await rig.service.refresh();

      final (name, level, providers) = rig.profiles.single;
      expect((name, level), ('name', 4));
      expect(providers, ['google']);
      expect(rig.clients.blocks.single.forceUpdate, isTrue);
    },
  );

  test('a newer pack forces a content check; the same one doesn\'t', () async {
    final rig = await _Rig.create(activeContentVersion: 3);
    rig.api.reply('GET', ApiPaths.bootstrap, [
      apiOk(bootstrapJson(contentVersion: 3)),
      apiOk(bootstrapJson(contentVersion: 4)),
      apiOk(bootstrapJson(contentVersion: null)),
    ]);

    await rig.service.refresh(force: true);
    expect(rig.contentChecks, 0);
    await rig.service.refresh(force: true);
    expect(rig.contentChecks, 1);
    await rig.service.refresh(force: true);
    expect(rig.contentChecks, 1);
  });

  test('the wallet in it is never applied', () async {
    final rig = await _Rig.create();
    final before = rig.economy.service.view;
    rig.answer(bootstrapJson(jenehat: 99999));

    await rig.service.refresh();

    expect(rig.economy.service.view.jenehat, before.jenehat);
    expect(rig.economy.service.pendingCount, 0);
  });

  test('a state_version above the base, nothing pending: the next pass '
      'takes the state', () async {
    final rig = await _Rig.create();
    rig.answer(bootstrapJson(stateVersion: 9));
    rig.api.always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 9)));
    final states = RecordingStates(rig.economy.service);
    final engine = SyncRunner(
      account: FakeSyncAccount(),
      api: PlainAuthorizedApi(rig.api),
      economy: rig.economy.service,
      states: states,
      time: FakeSyncTime(),
      serverStateVersion: () => rig.service.stateVersion,
      bootstrap: () => rig.service.refresh(force: true),
      random: Random(1),
    );
    addTearDown(engine.dispose);
    expect(rig.service.stateVersion, isNull);

    await engine.syncNow();

    expect(rig.service.stateVersion, 9);
    expect(states.calls.single.why, StateWhy.ahead);
    expect(rig.economy.service.baseInfo.stateVersion, 9);
  });
}
