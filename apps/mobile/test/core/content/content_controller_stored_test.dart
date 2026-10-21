import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/pack_store.dart';

import '../../helpers/content.dart';

const _app = '1.0.0+2';

void main() {
  test('a stored ready pack above the bundled one becomes active', () async {
    final dir = tempStoreDir();
    storeSampleVersion(openStore(dir), 2);

    final container = contentContainer(storeDir: dir);
    final active = await container.read(activeContentProvider.future);
    expect(active.version, 2);
    expect(active.origin, ContentOrigin.stored);
    expect(openStore(dir).state.active?.version, 2);
    expectStoreInvariants(dir, _app);
  });

  test('a stored active pack stays active', () async {
    final dir = tempStoreDir();
    final store = openStore(dir);
    storeSampleVersion(store, 2);
    store.activate(2);

    final active = await contentContainer(storeDir: dir)
        .read(activeContentProvider.future);
    expect((active.version, active.origin), (2, ContentOrigin.stored));
    expectStoreInvariants(dir, _app);
  });

  test('a stored pack for a newer app is skipped and dropped', () async {
    final dir = tempStoreDir();
    storeSampleVersion(openStore(dir), 2, minClientVersion: '9.0.0');

    final active = await contentContainer(storeDir: dir)
        .read(activeContentProvider.future);
    expect((active.version, active.origin), (1, ContentOrigin.bundled));
    expect(openStore(dir).state.stored, isEmpty);
    expectStoreInvariants(dir, _app);
  });

  group('the switch at Home', () {
    test('switchIfReady makes the ready pack active in one change', () async {
      final dir = tempStoreDir();
      final container = contentContainer(storeDir: dir);
      await container.read(activeContentProvider.future);
      final seen = <ActiveContent>[];
      container.listen(
        activeContentProvider,
        (_, next) => seen.add(next.requireValue),
      );

      // What the updater leaves: v3 stored as ready, and decoded in memory.
      final store = await container.read(packStoreProvider.future);
      storeSampleVersion(store, 3);
      final pack = samplePackVersion(3);
      final decoded = decodePackFile(pack.bytes, pack.expected) as PackDecoded;
      final controller = container.read(activeContentProvider.notifier)
        ..acceptReady(decoded.source);
      expect(controller.readyVersion, 3);

      await controller.switchIfReady();
      expect(seen.map((a) => (a.version, a.origin)), [
        (3, ContentOrigin.stored),
      ]);
      expect(controller.readyVersion, isNull);
      expect(openStore(dir).state.active?.version, 3);
      expectStoreInvariants(dir, _app);
    });

    test('the switch records the pack as active before the frame', () async {
      final dir = tempStoreDir();
      final container = contentContainer(storeDir: dir);
      await container.read(activeContentProvider.future);
      final store = await container.read(packStoreProvider.future);
      storeSampleVersion(store, 3);
      final pack = samplePackVersion(3);
      final decoded = decodePackFile(pack.bytes, pack.expected) as PackDecoded;
      final controller = container.read(activeContentProvider.notifier)
        ..acceptReady(decoded.source);

      final switching = controller.switchIfReady();
      expect(store.state.active?.version, 3);
      // A download that commits before the old file is deleted can't take
      // v3 for an older ready pack.
      storeSampleVersion(store, 4);
      await switching;
      final state = openStore(dir).state;
      expect((state.active?.version, state.ready?.version), (3, 4));
      expect(store.packFile(3).existsSync(), isTrue);
      expectStoreInvariants(dir, _app);
    });

    test('switchIfReady without a ready pack does nothing', () async {
      final container = contentContainer();
      await container.read(activeContentProvider.future);
      var changes = 0;
      container.listen(activeContentProvider, (_, _) => changes++);
      await container.read(activeContentProvider.notifier).switchIfReady();
      expect(changes, 0);
      expect(container.read(activeContentProvider).requireValue.version, 1);
    });
  });
}
