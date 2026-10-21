import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/refusal_reason.dart';

import '../../helpers/content.dart';

// One test per row of data-model.md "Choosing the active pack at launch".

const _app = '1.0.0+2';

Future<ActiveContent> _launch(
  Directory dir, {
  Map<String, Uint8List?>? assets,
  String appVersion = _app,
}) => contentContainer(
  storeDir: dir,
  assets: assets,
  appVersion: appVersion,
).read(activeContentProvider.future);

void main() {
  test('a fresh install uses the bundled pack', () async {
    final dir = tempStoreDir();
    final active = await _launch(dir);
    expect((active.version, active.origin), (1, ContentOrigin.bundled));
    expect(openStore(dir).state.stored, isEmpty);
    expectStoreInvariants(dir, _app);
  });

  test('a stored ready pack that passes becomes active', () async {
    final dir = tempStoreDir();
    final store = openStore(dir);
    storeSampleVersion(store, 2);
    store.activate(2);
    storeSampleVersion(store, 3);

    final active = await _launch(dir);
    expect((active.version, active.origin), (3, ContentOrigin.stored));
    final state = openStore(dir).state;
    expect(state.stored.map((e) => (e.version, e.state.name)), [(3, 'active')]);
    expectStoreInvariants(dir, _app);
  });

  test('a stored pack that fails its check gives way to the next', () async {
    final dir = tempStoreDir();
    final store = openStore(dir);
    storeSampleVersion(store, 2);
    store.activate(2);
    storeSampleVersion(store, 3);
    final file = store.packFile(3);
    final bytes = file.readAsBytesSync()..[100] ^= 0x01;
    file.writeAsBytesSync(bytes);

    final active = await _launch(dir);
    expect((active.version, active.origin), (2, ContentOrigin.stored));
    final state = openStore(dir).state;
    expect(state.stored.map((e) => e.version), [2]);
    expect(file.existsSync(), isFalse);
    expect(state.unusable, isEmpty, reason: 'downloaded again next check');
    final event = state.events.last;
    expect(event.reason, RefusalReason.storedCheckFailed.wire);
    expect(event.version, 3);
    expect(event.detail, RefusalReason.sha256Mismatch.wire);
    expectStoreInvariants(dir, _app);
  });

  test('an update bundling a higher version drops every stored one', () async {
    final dir = tempStoreDir();
    final store = openStore(dir);
    storeSampleVersion(store, 2);
    store.activate(2);
    storeSampleVersion(store, 3);

    final active = await _launch(
      dir,
      assets: bundledAssetsFor(samplePackVersion(4)),
      appVersion: '1.0.0+3',
    );
    expect((active.version, active.origin), (4, ContentOrigin.bundled));
    expect(openStore(dir, appVersion: '1.0.0+3').state.stored, isEmpty);
    expectStoreInvariants(dir, '1.0.0+3');
  });

  test('an update bundling a lower version keeps the stored one', () async {
    final dir = tempStoreDir();
    final store = openStore(dir);
    storeSampleVersion(store, 3);
    store.activate(3);

    final active = await _launch(
      dir,
      assets: bundledAssetsFor(samplePackVersion(2)),
      appVersion: '1.0.0+3',
    );
    expect((active.version, active.origin), (3, ContentOrigin.stored));
    expectStoreInvariants(dir, '1.0.0+3');
  });

  test('nothing passes: content is unavailable, with an event', () async {
    final dir = tempStoreDir();
    final assets = sampleBundledAssets();
    assets[sampleBundledFileAsset] = Uint8List.fromList(
      assets[sampleBundledFileAsset]!,
    )..[50] ^= 0x01;

    await expectLater(
      _launch(dir, assets: assets),
      throwsA(isA<ContentUnavailable>()),
    );
    final event = openStore(dir).state.events.last;
    expect(event.reason, RefusalReason.bundledCheckFailed.wire);
    expect(event.detail, RefusalReason.sha256Mismatch.wire);
  });

  test('a new app version clears unusable and attempts first', () async {
    final dir = tempStoreDir();
    openStore(dir)
      ..recordFailure(RefusalReason.unreadable, version: 5)
      ..recordFailure(RefusalReason.sha256Mismatch, version: 6);

    await _launch(dir, appVersion: '1.0.0+3');
    final state = openStore(dir, appVersion: '1.0.0+3').state;
    expect(state.unusable, isEmpty);
    expect(state.attempts, isEmpty);
    expectStoreInvariants(dir, '1.0.0+3');
  });
}
