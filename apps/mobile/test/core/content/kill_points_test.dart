import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/pack_store.dart';

import '../../helpers/content.dart';

// A kill at any point of a download or a switch leaves exactly one verified
// pack active at the next launch, and no stray file (FR-028, SC-005).

const _app = '1.0.0+2';

final class _Killed implements Exception {}

/// Bundled v1, plus a stored active v2.
Directory _withActiveV2() {
  final dir = tempStoreDir();
  final store = openStore(dir);
  storeSampleVersion(store, 2);
  store.activate(2);
  return dir;
}

/// A store on [dir] whose hook throws at [point].
PackStore _killingAt(Directory dir, KillPoint point) => PackStore(
  dir,
  onKillPoint: (reached) {
    if (reached == point) throw _Killed();
  },
)..reconcile();

Future<void> _expectOneVerifiedActive(Directory dir, Set<int> allowed) async {
  final active = await contentContainer(storeDir: dir)
      .read(activeContentProvider.future);
  expect(active.origin, ContentOrigin.stored);
  expect(allowed, contains(active.version));
  final state = openStore(dir).state;
  expect(state.active?.version, active.version);
  expectStoreInvariants(dir, _app);
  expect(Directory('${dir.path}/tmp').existsSync(), isFalse);
}

void main() {
  const download = {
    KillPoint.partWritten: {2},
    KillPoint.partFlushed: {2},
    KillPoint.renamed: {2},
    KillPoint.stateWritten: {3},
  };
  for (final MapEntry(key: point, value: allowed) in download.entries) {
    test('a kill at ${point.name} during a download', () async {
      final dir = _withActiveV2();
      expect(
        () => storeSampleVersion(_killingAt(dir, point), 3),
        throwsA(isA<_Killed>()),
      );
      await _expectOneVerifiedActive(dir, allowed);
    });
  }

  test('a kill at activateStateWritten during a switch', () async {
    final dir = _withActiveV2();
    storeSampleVersion(openStore(dir), 3);
    expect(
      () => _killingAt(dir, KillPoint.activateStateWritten).activate(3),
      throwsA(isA<_Killed>()),
    );
    // The old active file is still there, unlisted: the launch removes it.
    expect(File('${dir.path}/core-2.json.gz').existsSync(), isTrue);
    await _expectOneVerifiedActive(dir, {3});
  });
}
