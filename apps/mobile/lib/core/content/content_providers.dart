// How the rest of the app reads content
// (specs/006-m04-content-loader/contracts/content-source.md "Providers").
import 'dart:isolate';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/content_updater.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/network/api_environment.dart';
import 'package:wassal/core/network/dio_content_remote.dart';
import 'package:wassal/core/network/http_client.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/platform/clock.dart';

part 'content_providers.g.dart';

/// Checks and decodes pack bytes. Tests decode inline, because
/// `testWidgets` runs in fake async, where another isolate never answers.
typedef PackDecoder = Future<PackDecodeResult> Function(
  Uint8List bytes,
  ExpectedPack expected,
);

/// Decompresses and parses off the UI isolate (FR-007). Nothing else
/// belongs here: the whole decode runs in the other isolate.
Future<PackDecodeResult> isolatePackDecoder(
  Uint8List bytes,
  ExpectedPack expected,
) => Isolate.run(() => decodePackFile(bytes, expected));

@Riverpod(keepAlive: true)
PackDecoder packDecoder(Ref ref) => isolatePackDecoder;

/// The active pack. Synchronous once startup has completed: the boot screen
/// hands over only after [activeContentProvider] loads.
@Riverpod(keepAlive: true)
ContentSource contentSource(Ref ref) =>
    ref.watch(activeContentProvider).requireValue.source;

/// The active pack's version, which ops declare (M05, M06).
@Riverpod(keepAlive: true)
int contentVersion(Ref ref) =>
    ref.watch(activeContentProvider).requireValue.version;

/// The manifest and pack requests. Read only after startup, when the app's
/// version is known.
@Riverpod(keepAlive: true)
ContentRemote contentRemote(Ref ref) {
  final flavor = ref.watch(flavorProvider);
  final dio = createHttpClient(flavor, ref.watch(appInfoProvider).requireValue);
  ref.onDispose(() => dio.close(force: true));
  return DioContentRemote(
    dio: dio,
    flavor: flavor,
    apiBase: apiBaseUrl(flavor),
  );
}

/// Checks for new packs. Started once startup has completed
/// (contracts/updates.md "When a check runs").
@Riverpod(keepAlive: true)
ContentUpdater contentUpdater(Ref ref) {
  final controller = ref.watch(activeContentProvider.notifier);
  final updater = ContentUpdater(
    remote: ref.watch(contentRemoteProvider),
    store: ref.watch(packStoreProvider).requireValue,
    decode: ref.watch(packDecoderProvider),
    flavor: ref.watch(flavorProvider),
    appVersion: ClientVersion.parse(
      ref.watch(appInfoProvider).requireValue.versionWithBuild,
    ),
    clock: ref.watch(clockProvider),
    activeVersion: () => ref.read(activeContentProvider).requireValue.version,
    readyVersion: () => controller.readyVersion,
    acceptReady: controller.acceptReady,
  );
  ref.onDispose(updater.dispose);
  return updater;
}
