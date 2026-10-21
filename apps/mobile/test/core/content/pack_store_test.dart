import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_state.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/content/refusal_reason.dart';

import '../../helpers/content.dart';

const _app = '1.0.0+2';
final _t0 = DateTime.utc(2026, 10, 21, 9);

void main() {
  late Directory dir;
  late PackStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pack_store_test');
    store = PackStore(dir, clock: () => _t0)
      ..reconcile()
      ..setAppVersion(_app);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  ContentState onDisk() =>
      ContentState.decode(File('${dir.path}/state.json').readAsBytesSync());

  /// Downloads v[version] of the sample into the store as `ready`.
  void storeReady(int version) {
    final pack = samplePackVersion(version);
    store.beginDownload(version).writeAsBytesSync(pack.bytes);
    store.commitDownload(version, pack.expected);
  }

  group('state.json', () {
    test('round-trips every field', () {
      final state = ContentState(
        appVersion: _app,
        stored: [
          StoredPack(
            version: 2,
            size: 10,
            sha256: 'a' * 64,
            minClientVersion: '1.0.0',
            state: StoredState.active,
          ),
          StoredPack(
            version: 3,
            size: 11,
            sha256: 'b' * 64,
            minClientVersion: '1.0.0',
            state: StoredState.ready,
          ),
        ],
        unusable: {5: 'checksum_failed'},
        attempts: {4: 2},
        lastCheckAt: _t0,
        events: [
          ContentEvent(at: _t0, reason: 'manifest_failed', detail: 'status'),
          ContentEvent(at: _t0, reason: 'unreadable', version: 5),
        ],
      );
      final decoded = ContentState.decode(state.encode());
      expect(decoded.toJson(), state.toJson());
      expect(decoded.lastCheckAt, _t0);
      expect(decoded.lastCheckAt!.isUtc, isTrue);
      final json = jsonDecode(utf8.decode(state.encode())) as Map;
      expect(json['format'], 1);
      expect(json['last_check_at'], '2026-10-21T09:00:00.000Z');
    });

    test('anything this app cannot read counts as empty', () {
      final valid = const ContentState(appVersion: _app).toJson();
      for (final bad in <Object>[
        {...valid, 'format': 2},
        {...valid, 'stored': 'x'},
        {
          ...valid,
          'stored': [
            for (final v in [2, 3, 4])
              {
                'version': v,
                'file': 'core-$v.json.gz',
                'size': 1,
                'sha256': 'a' * 64,
                'min_client_version': '1.0.0',
                'state': v == 4 ? 'active' : 'ready',
              },
          ],
        },
        {...valid, 'last_check_at': '2026-10-21T09:00:00'},
        'not json',
      ]) {
        final bytes = utf8.encode(bad is String ? bad : jsonEncode(bad));
        expect(
          ContentState.decode(bytes).toJson(),
          ContentState.empty.toJson(),
          reason: '$bad',
        );
      }
    });
  });

  test('a download becomes the ready pack, and a newer one replaces it', () {
    storeReady(2);
    expect(store.packFile(2).existsSync(), isTrue);
    expect(onDisk().ready?.version, 2);
    expect(store.partFile(2).existsSync(), isFalse);

    storeReady(3);
    expect(onDisk().ready?.version, 3);
    expect(onDisk().stored, hasLength(1));
    expect(store.packFile(2).existsSync(), isFalse);
    expectStoreInvariants(dir, _app);
  });

  test('activate makes the ready pack active and deletes the old one', () {
    storeReady(2);
    store.activate(2);
    storeReady(3);
    expect(onDisk().active?.version, 2);
    expect(onDisk().ready?.version, 3);

    store.activate(3);
    expect(onDisk().active?.version, 3);
    expect(onDisk().ready, isNull);
    expect(store.packFile(2).existsSync(), isFalse);
    expectStoreInvariants(dir, _app);
  });

  test('activating a version the store lacks does nothing', () {
    storeReady(2);
    store.activate(2);
    store.activate(7);
    expect(onDisk().active?.version, 2);
    expectStoreInvariants(dir, _app);
  });

  test('dropStored and removeStored delete files after the state', () {
    storeReady(2);
    store.activate(2);
    storeReady(3);
    store.removeStored(3);
    expect(onDisk().stored.map((e) => e.version), [2]);
    expect(store.packFile(3).existsSync(), isFalse);
    store.dropStored();
    expect(onDisk().stored, isEmpty);
    expect(store.packFile(2).existsSync(), isFalse);
    expectStoreInvariants(dir, _app);
  });

  test('markChecked records the time; restoreChecked puts it back', () {
    store.markChecked(_t0);
    expect(onDisk().lastCheckAt, _t0);
    final later = _t0.add(const Duration(hours: 1));
    store.markChecked(later);
    store.restoreChecked(_t0);
    expect(onDisk().lastCheckAt, _t0);
    store.restoreChecked(null);
    expect(onDisk().lastCheckAt, isNull);
    expect(onDisk().toJson().containsKey('last_check_at'), isFalse);
    expectStoreInvariants(dir, _app);
  });

  test('recordFailure appends an event', () {
    store
      ..recordFailure(
        RefusalReason.manifestFailed,
        detail: RefusalDetail.unreachable,
      )
      ..recordFailure(
        RefusalReason.storedCheckFailed,
        version: 4,
        cause: RefusalReason.sha256Mismatch,
      );
    final events = onDisk().events;
    expect(events.map((e) => e.toJson()), [
      {
        'at': '2026-10-21T09:00:00.000Z',
        'reason': 'manifest_failed',
        'detail': 'unreachable',
      },
      {
        'at': '2026-10-21T09:00:00.000Z',
        'reason': 'stored_check_failed',
        'version': 4,
        'detail': 'sha256_mismatch',
      },
    ]);
    expect(onDisk().unusable, isEmpty, reason: 'a launch check failure');
    expect(onDisk().attempts, isEmpty);
    expectStoreInvariants(dir, _app);
  });

  test('no state.json.tmp is left after a write', () {
    storeReady(2);
    store
      ..activate(2)
      ..markChecked(_t0)
      ..recordFailure(RefusalReason.tooLarge, version: 9);
    expect(File('${dir.path}/state.json.tmp').existsSync(), isFalse);
  });

  group('reconcile', () {
    test('removes tmp/, unlisted files and entries without a file', () {
      storeReady(2);
      store.activate(2);
      storeReady(3);
      store.beginDownload(4).writeAsStringSync('partial');
      File('${dir.path}/core-9.json.gz').writeAsStringSync('stray');
      store.packFile(3).deleteSync();

      final again = PackStore(dir)..reconcile();
      expect(Directory('${dir.path}/tmp').existsSync(), isFalse);
      expect(File('${dir.path}/core-9.json.gz').existsSync(), isFalse);
      expect(again.state.stored.map((e) => e.version), [2]);
      expect(onDisk().stored.map((e) => e.version), [2]);
      expectStoreInvariants(dir, _app);
    });

    test('an unreadable state.json counts as empty, and its files go', () {
      for (final bad in ['{"format": 2}', 'garbage']) {
        storeReady(2);
        File('${dir.path}/state.json').writeAsStringSync(bad);
        final again = PackStore(dir)..reconcile();
        expect(again.state.stored, isEmpty);
        expect(store.packFile(2).existsSync(), isFalse);
        again.setAppVersion(_app);
        expectStoreInvariants(dir, _app);
        store = PackStore(dir, clock: () => _t0)..reconcile();
      }
    });
  });

  group('attempts and the unusable list (research R14)', () {
    test('the third checksum failure makes a version unusable', () {
      store.recordFailure(RefusalReason.sha256Mismatch, version: 5);
      expect(onDisk().attempts, {5: 1});
      store.recordFailure(RefusalReason.sizeMismatch, version: 5);
      expect(onDisk().attempts, {5: 2});
      store.recordFailure(RefusalReason.sha256Mismatch, version: 5);
      expect(onDisk().attempts, isEmpty);
      expect(onDisk().unusable, {5: 'checksum_failed'});
      expect(onDisk().events.last.reason, 'checksum_failed');
      expectStoreInvariants(dir, _app);
    });

    test('a decoder refusal makes a version unusable at once', () {
      for (final reason in [
        RefusalReason.decompressTooLarge,
        RefusalReason.unreadable,
        RefusalReason.wrongIdentity,
        RefusalReason.schemaUnsupported,
      ]) {
        store.recordFailure(RefusalReason.sha256Mismatch, version: 6);
        store.recordFailure(reason, version: 6);
        expect(onDisk().unusable, {6: reason.wire});
        expect(onDisk().attempts, isEmpty);
        store.setAppVersion('x');
        store.setAppVersion(_app);
      }
      expectStoreInvariants(dir, _app);
    });

    test('a new app version clears both lists; the same one keeps them', () {
      store
        ..recordFailure(RefusalReason.unreadable, version: 5)
        ..recordFailure(RefusalReason.sha256Mismatch, version: 6)
        ..setAppVersion(_app);
      expect(onDisk().unusable, isNotEmpty);
      expect(onDisk().attempts, isNotEmpty);
      store.setAppVersion('1.0.0+3');
      expect(onDisk().unusable, isEmpty);
      expect(onDisk().attempts, isEmpty);
      expectStoreInvariants(dir, '1.0.0+3');
    });

    test('a stored version that downloads again resets its attempts', () {
      store.recordFailure(RefusalReason.sha256Mismatch, version: 2);
      storeReady(2);
      expect(onDisk().attempts, isEmpty);
    });
  });

  test('a repeat of the newest event only moves its time', () {
    var now = _t0;
    final later = _t0.add(const Duration(minutes: 15));
    final repeating = PackStore(dir, clock: () => now)..reconcile();
    void ignored(RefusalDetail detail) => repeating.recordFailure(
      RefusalReason.entryIgnored,
      version: 9,
      detail: detail,
    );
    ignored(RefusalDetail.minClientVersion);
    now = later;
    ignored(RefusalDetail.minClientVersion);
    ignored(RefusalDetail.unusable);
    expect(onDisk().events.map((e) => (e.at, e.detail)), [
      (later, RefusalDetail.minClientVersion.wire),
      (later, RefusalDetail.unusable.wire),
    ]);
  });

  test('a delete that fails after the state write is left to reconcile', () {
    storeReady(2);
    final failing = PackStore(
      dir,
      clock: () => _t0,
      onKillPoint: (point) {
        // The directory turns read-only once state.json lists only v3.
        if (point == KillPoint.stateWritten) {
          Process.runSync('chmod', ['555', dir.path]);
        }
      },
    )..reconcile();
    final pack = samplePackVersion(3);
    failing.beginDownload(3).writeAsBytesSync(pack.bytes);
    try {
      failing.commitDownload(3, pack.expected);
    } finally {
      Process.runSync('chmod', ['755', dir.path]);
    }
    expect(onDisk().ready?.version, 3);
    expect(store.packFile(2).existsSync(), isTrue);
    PackStore(dir).reconcile();
    expect(store.packFile(2).existsSync(), isFalse);
    expectStoreInvariants(dir, _app);
  });

  test('only the last 20 events are kept, oldest first', () {
    for (var i = 1; i <= 25; i++) {
      store.recordFailure(RefusalReason.tooLarge, version: i);
    }
    final events = onDisk().events;
    expect(events, hasLength(maxContentEvents));
    expect(events.map((e) => e.version), [for (var i = 6; i <= 25; i++) i]);
    for (final event in events) {
      expect(
        event.toJson().keys.toSet().difference({
          'at',
          'reason',
          'version',
          'detail',
        }),
        isEmpty,
      );
    }
  });
}
