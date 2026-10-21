import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/decode_pack_file.dart';

import '../../helpers/content.dart';

ProviderContainer _container({
  Map<String, Uint8List?>? assets,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      flavorProvider.overrideWithValue(Flavor.dev),
      ...contentTestOverrides(assets: assets),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a fresh install makes the bundled pack active', () async {
    final container = _container();
    final active = await container.read(activeContentProvider.future);
    expect(active.version, 1);
    expect(active.origin, ContentOrigin.bundled);
    expect(active.source.version, 1);
  });

  test('the source and the version read synchronously after startup', () async {
    final container = _container();
    await container.read(activeContentProvider.future);
    expect(container.read(contentSourceProvider).lines, hasLength(2));
    expect(container.read(contentVersionProvider), 1);
  });

  test('a damaged bundled pack makes content unavailable', () async {
    final assets = sampleBundledAssets();
    final bytes = Uint8List.fromList(assets[sampleBundledFileAsset]!);
    bytes[100] ^= 0x01;
    assets[sampleBundledFileAsset] = bytes;
    final container = _container(assets: assets);
    await expectLater(
      container.read(activeContentProvider.future),
      throwsA(isA<ContentUnavailable>()),
    );
  });

  test('a missing bundled pack makes content unavailable', () async {
    final container = _container(
      assets: {...sampleBundledAssets(), sampleBundledRecordAsset: null},
    );
    await expectLater(
      container.read(activeContentProvider.future),
      throwsA(isA<ContentUnavailable>()),
    );
  });

  test('debug builds log the active pack and the load time', () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = original);

    await _container().read(activeContentProvider.future);
    expect(
      logs,
      contains(matches(RegExp(r'^content: active v1 \(bundled\) in \d+ ms$'))),
    );
  });

  group('off the UI isolate (FR-007)', () {
    test('the default decoder is isolatePackDecoder', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(packDecoderProvider), isolatePackDecoder);
    });

    test('isolatePackDecoder decodes the sample in another isolate', () async {
      final result = await isolatePackDecoder(
        sampleBundledBytes(),
        sampleExpectedPack(),
      );
      expect(result, isA<PackDecoded>());
      expect((result as PackDecoded).source.version, 1);
    });
  });
}
