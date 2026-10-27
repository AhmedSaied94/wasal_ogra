import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/sync/domain/pass.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/server_status.dart';

import '../../helpers/content.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/memory_settings_store.dart';

// What the player is told of the server (specs/011-m06-identity-sync,
// data-model.md "State transitions", research R17–R19).

ClientBlock _client({String latest = '1.0.0', bool force = false}) =>
    ClientBlock.fromJson({
      'min_version': '1.0.0',
      'latest_version': latest,
      'force_update': force,
    });

const _done = PassDone(batches: 1, accepted: 1, rejected: 0, setAside: 0);

final class _Rig {
  _Rig({bool online = true, Map<String, String>? settings})
    : connectivity = FakeConnectivitySource()..current = online,
      settings = MemorySettingsStore(settings) {
    container = ProviderContainer(
      overrides: [
        connectivitySourceProvider.overrideWithValue(connectivity),
        settingsStoreProvider.overrideWith((ref) async => this.settings),
        appInfoProvider.overrideWith((ref) async => FakeAppInfo('1.1.0+3')),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakeConnectivitySource connectivity;
  final MemorySettingsStore settings;
  late final ProviderContainer container;

  Future<ServerStatus> start() async {
    await container.read(appInfoProvider.future);
    await container.read(settingsStoreProvider.future);
    final status = container.read(serverStatusProvider.notifier);
    await pumpEventQueue();
    return status;
  }

  ServerStatusState get state => container.read(serverStatusProvider);
}

void main() {
  group('reach', () {
    test('starts online with a link, offline without', () async {
      final up = _Rig();
      await up.start();
      expect(up.state.reach, Reach.online);
      final down = _Rig(online: false);
      await down.start();
      expect(down.state.reach, Reach.offline);
    });

    test('a link down goes offline', () async {
      final rig = _Rig();
      await rig.start();
      rig.connectivity.set(false);
      await pumpEventQueue();
      expect(rig.state.reach, Reach.offline);
    });

    test('an unreachable request goes offline', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.observe(unreachable);
      expect(rig.state.reach, Reach.offline);
    });

    test('online again only after a bootstrap, then a pass with no network '
        'failure', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.unreachable();

      rig.connectivity.set(true);
      await pumpEventQueue();
      expect(rig.state.reach, Reach.offline, reason: 'the link alone');

      status.passEnded(_done);
      expect(rig.state.reach, Reach.offline, reason: 'no bootstrap yet');

      status.client(_client());
      expect(rig.state.reach, Reach.offline, reason: 'no pass yet');

      status.passEnded(const PassFailed('timeout', retryAtMs: 0));
      expect(rig.state.reach, Reach.offline, reason: 'a failed pass');

      status.passEnded(const PassIdle());
      expect(rig.state.reach, Reach.online);
    });

    test('a failure after the bootstrap needs only a good pass, since the '
        'next bootstrap may be minutes away', () async {
      final rig = _Rig();
      final status = await rig.start();
      status
        ..unreachable()
        ..client(_client())
        ..passEnded(_done)
        ..unreachable();
      expect(rig.state.reach, Reach.offline);

      status.passEnded(const PassFailed('timeout', retryAtMs: 0));
      expect(rig.state.reach, Reach.offline, reason: 'a failed pass');

      status.passEnded(_done);
      expect(rig.state.reach, Reach.online);
    });

    test('a good pass with the link down stays offline', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.client(_client());
      rig.connectivity.set(false);
      await pumpEventQueue();
      status.passEnded(_done);
      expect(rig.state.reach, Reach.offline);
    });

    test('isOnlineProvider follows reach', () async {
      final rig = _Rig();
      final status = await rig.start();
      expect(rig.container.read(isOnlineProvider), isTrue);
      status.unreachable();
      expect(rig.container.read(isOnlineProvider), isFalse);
      status
        ..client(_client())
        ..passEnded(_done);
      expect(rig.container.read(isOnlineProvider), isTrue);
    });
  });

  group('maintenance', () {
    test('503 maintenance turns it on, with until in ms', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.observe(
        apiFail(503, 'maintenance', details: {'until': '2026-10-27T14:30:00Z'}),
      );
      expect(
        rig.state.maintenance,
        Maintenance(untilMs: isoToMs('2026-10-27T14:30:00Z')),
      );
    });

    for (final details in <Map<String, Object?>>[
      {},
      {'until': 'soon'},
      {'until': 1730000000},
      {'until': null},
    ]) {
      test('an absent or malformed until is ignored: $details', () async {
        final rig = _Rig();
        final status = await rig.start();
        status.maintenance(details);
        expect(rig.state.maintenance, const Maintenance());
      });
    }

    test('it clears on the next successful pass', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.maintenance(const {});
      status.passEnded(const PassHeld(HoldReason.maintenance));
      expect(rig.state.maintenance, isNotNull);
      status.passEnded(_done);
      expect(rig.state.maintenance, isNull);
    });

    test('503 dependency_unavailable is no maintenance', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.observe(apiFail(503, 'dependency_unavailable'));
      expect(rig.state.maintenance, isNull);
    });
  });

  group('update', () {
    test('forced from a live force_update, or a 426; memory only', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.client(_client(force: true));
      expect(rig.state.update, const ForcedUpdate());

      final other = _Rig();
      final status2 = await other.start();
      status2.observe(apiFail(426, 'client_outdated'));
      expect(other.state.update, const ForcedUpdate());
      // Nothing optional replaces it.
      status2.client(_client(latest: '9.0.0'));
      expect(other.state.update, const ForcedUpdate());

      final fresh = _Rig(settings: {...other.settings.values});
      await fresh.start();
      expect(fresh.state.update, const NoUpdate());
    });

    test('optional when latest is above the app, until dismissed', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.client(_client(latest: '1.1.0'));
      expect(rig.state.update, const NoUpdate(), reason: 'the same version');

      status.client(_client(latest: '1.2.0'));
      expect(rig.state.update, const OptionalUpdate('1.2.0'));

      await status.dismiss();
      expect(rig.state.update, const NoUpdate());
      expect(rig.settings.values[dismissedUpdateKey], '1.2.0');

      status.client(_client(latest: '1.2.0'));
      expect(rig.state.update, const NoUpdate(), reason: 'dismissed');

      status.client(_client(latest: '1.3.0'));
      expect(rig.state.update, const OptionalUpdate('1.3.0'));
    });

    test('a dismissal survives a relaunch', () async {
      final rig = _Rig(settings: {dismissedUpdateKey: '1.2.0'});
      final status = await rig.start();
      status.client(_client(latest: '1.2.0'));
      expect(rig.state.update, const NoUpdate());
    });

    test('an unreadable latest version offers nothing', () async {
      final rig = _Rig();
      final status = await rig.start();
      status.client(_client(latest: 'next'));
      expect(rig.state.update, const NoUpdate());
    });
  });

  test('ObservedApiClient hands every result on', () async {
    final seen = <ApiResult>[];
    final api = FakeApi()
      ..reply('GET', ApiPaths.bootstrap, [unreachable, apiOk({})]);
    final observed = ObservedApiClient(api, seen.add);
    const request = ApiRequest.get(
      ApiPaths.bootstrap,
      receiveTimeout: readReceiveTimeout,
    );

    expect(await observed.send(request), unreachable);
    expect(await observed.send(request), isA<ApiOk>());
    expect(seen, [unreachable, isA<ApiOk>()]);
  });
}
