import 'dart:async';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/content_state.dart';
import 'package:wassal/core/content/content_updater.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/content/refusal_reason.dart';

import '../../helpers/content.dart';

final _t0 = DateTime.utc(2026, 10, 21, 9);
const _app = '1.0.0+2';

/// An updater on a temp store, with an active v[active] and fakes around it.
final class _Rig {
  _Rig({Flavor flavor = Flavor.dev, this.active = 1}) {
    dir = tempStoreDir();
    store = openStore(dir);
    updater = ContentUpdater(
      remote: remote,
      store: store,
      decode: inlinePackDecoder,
      flavor: flavor,
      appVersion: ClientVersion.parse(_app),
      clock: clock.call,
      activeVersion: () => active,
      acceptReady: (PackContentSource source) => ready = source,
    );
  }

  late final Directory dir;
  late final PackStore store;
  late final ContentUpdater updater;
  final remote = FakeContentRemote();
  final clock = FakeClock(_t0);
  int active;
  PackContentSource? ready;

  ContentEvent? get lastEvent =>
      store.state.events.isEmpty ? null : store.state.events.last;

  /// Moves past the throttle.
  void later() => clock.advance(ContentUpdater.throttle);
}

void main() {
  group('triggers', () {
    test('a check runs after start, on resume and when back online', () async {
      final rig = _Rig();
      await rig.updater.check();
      expect(rig.remote.manifestRequests, 0, reason: 'not started yet');

      await rig.updater.start();
      expect(rig.remote.manifestRequests, 1);

      rig.later();
      await rig.updater.onResume();
      expect(rig.remote.manifestRequests, 2);

      rig.later();
      await rig.updater.onConnectivity(false);
      expect(rig.remote.manifestRequests, 2);
      await rig.updater.onConnectivity(true);
      expect(rig.remote.manifestRequests, 3);

      rig.later();
      await rig.updater.onConnectivity(true);
      expect(rig.remote.manifestRequests, 3, reason: 'online → online');
    });

    test('no check runs in the background', () async {
      final rig = _Rig();
      await rig.updater.start();
      rig
        ..later()
        ..updater.onBackground();
      await rig.updater.check(force: true);
      expect(rig.remote.manifestRequests, 1);
    });
  });

  group('throttle', () {
    test('15 minutes between checks', () async {
      final rig = _Rig();
      await rig.updater.start();
      rig.clock.advance(const Duration(minutes: 14, seconds: 59));
      await rig.updater.onResume();
      expect(rig.remote.manifestRequests, 1);
      rig.clock.advance(const Duration(seconds: 1));
      await rig.updater.onResume();
      expect(rig.remote.manifestRequests, 2);
      expect(rig.store.state.lastCheckAt, rig.clock.now);
    });

    test('a last check in the future counts as elapsed', () async {
      final rig = _Rig();
      rig.store.markChecked(_t0.add(const Duration(hours: 3)));
      await rig.updater.start();
      expect(rig.remote.manifestRequests, 1);
    });

    test('force skips only the throttle', () async {
      final rig = _Rig();
      await rig.updater.start();
      await rig.updater.check(force: true);
      expect(rig.remote.manifestRequests, 2);
    });
  });

  test('one check at a time', () async {
    final rig = _Rig();
    rig.remote
      ..offer(samplePackVersion(2))
      ..holdDownload = Completer<void>();
    final first = rig.updater.start();
    await pumpEventQueue();
    expect(rig.remote.downloads, hasLength(1));

    await rig.updater.check(force: true);
    expect(rig.remote.manifestRequests, 1);

    rig.remote.holdDownload!.complete();
    await first;
    expect(rig.ready?.version, 2);
  });

  group('manifest entry rules', () {
    Future<_Rig> offered(
      void Function(FakeContentRemote remote) offer, {
      Flavor flavor = Flavor.dev,
      int active = 1,
      void Function(PackStore store)? seed,
    }) async {
      final rig = _Rig(flavor: flavor, active: active);
      seed?.call(rig.store);
      offer(rig.remote);
      await rig.updater.start();
      return rig;
    }

    test('nothing new: no download and no event', () async {
      for (final rig in [
        await offered((r) {}),
        await offered((r) => r.offer(samplePackVersion(2)), active: 2),
        await offered((r) {
          final pack = samplePackVersion(2);
          r.manifestResult = ManifestOk(
            Manifest(
              version: 2,
              packs: [
                ManifestPack(
                  packId: 'other',
                  version: 2,
                  url: 'https://packs.test/other.json.gz',
                  sha256: pack.expected.sha256,
                  size: pack.expected.size,
                  minClientVersion: '1.0.0',
                ),
              ],
            ),
          );
        }),
        await offered((r) {
          r.manifestResult = const ManifestOk(Manifest(version: 0, packs: []));
        }),
      ]) {
        expect(rig.remote.downloads, isEmpty);
        expect(rig.store.state.events, isEmpty);
      }
    });

    test('a size over 16 MiB', () async {
      final rig = await offered(
        (r) => r.offer(samplePackVersion(2), size: 16777217),
      );
      expect(rig.remote.downloads, isEmpty);
      expect(rig.lastEvent?.reason, RefusalReason.tooLarge.wire);
      expect(rig.lastEvent?.version, 2);
    });

    test('a newer minimum app version', () async {
      final rig = await offered(
        (r) => r.offer(samplePackVersion(2), minClientVersion: '9.0.0'),
      );
      expect(rig.remote.downloads, isEmpty);
      expect(rig.lastEvent?.reason, RefusalReason.entryIgnored.wire);
      expect(rig.lastEvent?.detail, RefusalDetail.minClientVersion.wire);
    });

    test('an unusable version', () async {
      final rig = await offered(
        (r) => r.offer(samplePackVersion(2)),
        seed: (store) =>
            store.recordFailure(RefusalReason.unreadable, version: 2),
      );
      expect(rig.remote.downloads, isEmpty);
      expect(rig.lastEvent?.detail, RefusalDetail.unusable.wire);
    });

    test('an http URL outside dev', () async {
      final rig = await offered(
        (r) => r.offer(samplePackVersion(2), url: 'http://packs.test/p'),
        flavor: Flavor.staging,
      );
      expect(rig.remote.downloads, isEmpty);
      expect(rig.lastEvent?.detail, RefusalDetail.insecureUrl.wire);
    });
  });

  test('a failed manifest is one event, and nothing changes', () async {
    final rig = _Rig();
    rig.remote.manifestResult = const ManifestFailed(RefusalDetail.unreachable);
    await rig.updater.start();
    expect(rig.store.state.events, hasLength(1));
    expect(rig.lastEvent?.reason, RefusalReason.manifestFailed.wire);
    expect(rig.lastEvent?.detail, RefusalDetail.unreachable.wire);
    expect(rig.ready, isNull);
    expect(rig.store.state.stored, isEmpty);
  });

  test('a good pack becomes ready, and is not downloaded twice', () async {
    final rig = _Rig();
    rig.remote.offer(samplePackVersion(2));
    await rig.updater.start();
    expect(rig.ready?.version, 2);
    expect(rig.store.state.ready?.version, 2);
    expect(rig.store.state.events, isEmpty);

    rig.later();
    await rig.updater.onResume();
    expect(rig.remote.manifestRequests, 2);
    expect(rig.remote.downloads, hasLength(1));
    expectStoreInvariants(rig.dir, _app);
  });
}
