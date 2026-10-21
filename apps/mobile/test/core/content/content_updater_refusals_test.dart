import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/content_updater.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/content/refusal_reason.dart';

import '../../helpers/content.dart';

// A bad file, a failed download, a full disk or leaving the foreground never
// changes the active pack (FR-022, FR-023, FR-029 to FR-031, SC-004, SC-008).

const _url = 'https://packs.test/core.json.gz';

final class _Rig {
  _Rig({void Function(KillPoint point)? onKillPoint}) {
    dir = tempStoreDir();
    store = PackStore(dir, clock: clock.call, onKillPoint: onKillPoint)
      ..reconcile()
      ..setAppVersion('1.0.0+2');
    updater = ContentUpdater(
      remote: remote,
      store: store,
      decode: inlinePackDecoder,
      flavor: Flavor.dev,
      appVersion: ClientVersion.parse('1.0.0+2'),
      clock: clock.call,
      activeVersion: () => 1,
      readyVersion: () => ready?.version,
      acceptReady: (PackContentSource source) => ready = source,
    );
  }

  late final Directory dir;
  late final PackStore store;
  late final ContentUpdater updater;
  final remote = FakeContentRemote();
  final clock = FakeClock(DateTime.utc(2026, 10, 21, 9));
  PackContentSource? ready;

  /// Runs one check, past the throttle.
  Future<void> checkAgain() {
    clock.advance(ContentUpdater.throttle);
    return updater.onResume();
  }

  bool get partLeft =>
      Directory('${dir.path}/tmp').existsSync() &&
      Directory('${dir.path}/tmp').listSync().isNotEmpty;

  List<String> get reasons => [for (final e in store.state.events) e.reason];
}

/// [bytes] offered as v2, with the size and sha256 the manifest promises.
void _offerAsV2(FakeContentRemote remote, List<int> bytes) {
  final packed = Uint8List.fromList(bytes);
  remote.offer((
    bytes: packed,
    expected: ExpectedPack(
      version: 2,
      size: packed.length,
      sha256: sha256Hex(packed),
      minClientVersion: '1.0.0',
    ),
  ), url: _url);
}

Uint8List _gzip(List<int> bytes) =>
    Uint8List.fromList(GZipCodec(level: 9).encode(bytes));

void main() {
  test(
    'a checksum failure counts; the third makes the version unusable',
    () async {
      final rig = _Rig();
      rig.remote.offer(samplePackVersion(2), url: _url);
      final served = Uint8List.fromList(rig.remote.files[_url]!)..[40] ^= 0x01;
      rig.remote.files[_url] = served;

      await rig.updater.start();
      await rig.checkAgain();
      await rig.checkAgain();
      expect(rig.store.state.unusable, {2: RefusalReason.checksumFailed.wire});
      await rig.checkAgain();
      expect(rig.remote.downloads, hasLength(3));
      expect(rig.reasons.last, RefusalReason.entryIgnored.wire);
      expect(rig.ready, isNull);
      expect(rig.partLeft, isFalse);
    },
  );

  group('a content refusal makes the version unusable at once', () {
    final cases = <RefusalReason, List<int> Function()>{
      RefusalReason.decompressTooLarge: () =>
          _gzip(Uint8List(maxDecompressedBytes + 1)),
      RefusalReason.unreadable: () => _gzip(utf8.encode('not json')),
      RefusalReason.wrongIdentity: () =>
          _gzip(utf8.encode(jsonEncode({...samplePackJson(), 'version': 3}))),
      RefusalReason.schemaUnsupported: () => _gzip(
        utf8.encode(
          jsonEncode({
            ...samplePackJson(),
            'version': 2,
            'schema_version': '2.0',
          }),
        ),
      ),
    };
    for (final MapEntry(key: reason, value: bytes) in cases.entries) {
      test(reason.wire, () async {
        final rig = _Rig();
        _offerAsV2(rig.remote, bytes());
        await rig.updater.start();
        expect(rig.store.state.unusable, {2: reason.wire});
        await rig.checkAgain();
        expect(rig.remote.downloads, hasLength(1));

        rig.store.setAppVersion('1.0.0+3');
        await rig.checkAgain();
        expect(rig.remote.downloads, hasLength(2), reason: 'a new app');
        expect(rig.ready, isNull);
        expect(rig.partLeft, isFalse);
      });
    }
  });

  test('a download error leaves no part file and is retried', () async {
    final rig = _Rig();
    rig.remote.offer(samplePackVersion(2), url: _url, size: 100);
    await rig.updater.start();
    expect(rig.reasons, [RefusalReason.tooLarge.wire]);
    expect(rig.partLeft, isFalse);

    rig.remote
      ..offer(samplePackVersion(2), url: _url)
      ..downloadResult = const DownloadFailed(
        RefusalReason.downloadFailed,
        RefusalDetail.status,
      );
    await rig.checkAgain();
    expect(rig.reasons.last, RefusalReason.downloadFailed.wire);
    expect(rig.store.state.events.last.detail, RefusalDetail.status.wire);
    expect(rig.partLeft, isFalse);
    expect(rig.store.state.unusable, isEmpty);

    rig.remote.downloadResult = null;
    await rig.checkAgain();
    expect(rig.remote.downloads, hasLength(3));
    expect(rig.ready?.version, 2);
  });

  test('a storage error is recorded, and nothing changes', () async {
    final rig = _Rig(
      onKillPoint: (point) {
        if (point == KillPoint.partFlushed) {
          throw const FileSystemException('rename failed');
        }
      },
    );
    rig.remote.offer(samplePackVersion(2), url: _url);
    await rig.updater.start();
    expect(rig.reasons, [RefusalReason.storageError.wire]);
    expect(rig.store.state.events.single.version, 2);
    expect(rig.partLeft, isFalse);
    expect(rig.store.state.stored, isEmpty);
    expect(rig.ready, isNull);
  });

  group('leaving the foreground', () {
    test('cancels the download, with no event and no part file', () async {
      final rig = _Rig();
      rig.remote
        ..offer(samplePackVersion(2), url: _url)
        ..holdDownload = Completer<void>();
      final check = rig.updater.start();
      await pumpEventQueue();
      expect(rig.partLeft, isTrue, reason: 'mid-download');

      rig.updater.onBackground();
      await check;
      expect(rig.store.state.events, isEmpty);
      expect(rig.partLeft, isFalse);
      expect(rig.ready, isNull);
    });

    test("doesn't use up the 15 minutes (FR-015)", () async {
      final rig = _Rig();
      final before = rig.clock.now.subtract(const Duration(hours: 1));
      rig.store.markChecked(before);
      rig.remote
        ..offer(samplePackVersion(2), url: _url)
        ..holdDownload = Completer<void>();
      final check = rig.updater.start();
      await pumpEventQueue();
      rig.updater.onBackground();
      await check;
      expect(rig.store.state.lastCheckAt, before);

      rig.remote.holdDownload = null;
      await rig.updater.onResume();
      expect(rig.remote.manifestRequests, 2);
      expect(rig.remote.downloads, hasLength(2));
      expect(rig.ready?.version, 2);
    });

    test(
      'a resume right after waits for the cancelled check, then checks',
      () async {
        final rig = _Rig();
        rig.remote
          ..offer(samplePackVersion(2), url: _url)
          ..holdDownload = Completer<void>();
        final first = rig.updater.start();
        await pumpEventQueue();
        rig.updater.onBackground();
        rig.remote.holdDownload = null;
        // Before the cancelled check has unwound.
        final second = rig.updater.onResume();
        await Future.wait([first, second]);
        expect(rig.remote.manifestRequests, 2);
        expect(rig.remote.downloads, hasLength(2));
        expect(rig.ready?.version, 2);
      },
    );

    test('with no earlier check, the time is removed', () async {
      final rig = _Rig();
      rig.remote
        ..offer(samplePackVersion(2), url: _url)
        ..holdDownload = Completer<void>();
      final check = rig.updater.start();
      await pumpEventQueue();
      rig.updater.onBackground();
      await check;
      expect(rig.store.state.lastCheckAt, isNull);
    });
  });
}
