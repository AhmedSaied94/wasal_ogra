// Content test helpers (specs/006-m04-content-loader/tasks.md T010): the
// sample pack as bytes, packs built from it, and the fakes the loader's
// seams take.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/content_state.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/content/refusal_reason.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/platform/clock.dart';
import 'package:wassal/core/platform/connectivity.dart';

const sampleBundledRecordAsset = 'assets/content/dev/bundled.json';
const sampleBundledFileAsset = 'assets/content/dev/core-1.json.gz';

/// The dev flavor's bundled pack file, read from disk.
Uint8List sampleBundledBytes() =>
    File(sampleBundledFileAsset).readAsBytesSync();

/// The sample pack as JSON, decoded from [sampleBundledBytes].
Map<String, Object?> samplePackJson() => (jsonDecode(
  utf8.decode(gzip.decode(sampleBundledBytes())),
) as Map<String, dynamic>).cast<String, Object?>();

/// The values `bundled.json` holds for the sample pack.
ExpectedPack sampleExpectedPack() {
  final record = jsonDecode(
    File(sampleBundledRecordAsset).readAsStringSync(),
  ) as Map<String, dynamic>;
  return ExpectedPack(
    version: record['version'] as int,
    size: record['size'] as int,
    sha256: record['sha256'] as String,
    minClientVersion: record['min_client_version'] as String,
  );
}

/// A pack file built from [json], and what a check expects of it.
typedef EncodedPack = ({Uint8List bytes, ExpectedPack expected});

/// [json] as a pack file: JSON, then gzip at level 9.
EncodedPack encodePackFile(
  Map<String, Object?> json, {
  String minClientVersion = '1.0.0',
}) {
  final bytes = Uint8List.fromList(
    GZipCodec(level: 9).encode(utf8.encode(jsonEncode(json))),
  );
  return (
    bytes: bytes,
    expected: ExpectedPack(
      version: json['version']! as int,
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      minClientVersion: minClientVersion,
    ),
  );
}

/// The sample pack with its `version` set to [version].
EncodedPack samplePackVersion(int version) =>
    encodePackFile({...samplePackJson(), 'version': version});

/// The sha256 of [bytes], as lowercase hex.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// An [AppInfo] with a fixed `<version>+<build>`.
final class FakeAppInfo implements AppInfo {
  FakeAppInfo(
    this.versionWithBuild, {
    this.platform = 'android',
    this.packageName = 'com.wassalogra.app.dev',
  });

  @override
  final String versionWithBuild;

  @override
  final String platform;

  @override
  final String packageName;

  @override
  String get version => versionWithBuild.split('+').first;

  @override
  String get buildNumber => versionWithBuild.split('+').last;
}

/// The dev flavor's bundled assets, read from disk. Tests copy the map, then
/// damage or remove entries.
Map<String, Uint8List?> sampleBundledAssets() => {
  sampleBundledRecordAsset: File(sampleBundledRecordAsset).readAsBytesSync(),
  sampleBundledFileAsset: sampleBundledBytes(),
};

/// The sample's bundled assets under both flavor directories, so a test of
/// any flavor finds a pack.
Map<String, Uint8List?> allFlavorBundledAssets() {
  final dev = sampleBundledAssets();
  return {
    ...dev,
    'assets/content/release/bundled.json': dev[sampleBundledRecordAsset],
    'assets/content/release/core-1.json.gz': dev[sampleBundledFileAsset],
  };
}

/// An [AssetBytesReader] over [assets], read at each call so a test can
/// change the map between reads. A path it doesn't list reads as null.
AssetBytesReader fakeAssetBytesReader(Map<String, Uint8List?> assets) =>
    (path) async => assets[path];

/// Decodes on the calling isolate. `testWidgets` runs in fake async, where
/// `Isolate.run` never completes.
Future<PackDecodeResult> inlinePackDecoder(
  Uint8List bytes,
  ExpectedPack expected,
) async => decodePackFile(bytes, expected);

/// The sample pack as active content: version 1, bundled.
ActiveContent sampleActiveContent() {
  final result = decodePackFile(sampleBundledBytes(), sampleExpectedPack());
  return ActiveContent(
    version: 1,
    origin: ContentOrigin.bundled,
    source: (result as PackDecoded).source,
  );
}

/// A temp directory for a [PackStore], deleted after the test.
Directory tempStoreDir() {
  final dir = Directory.systemTemp.createTempSync('content_store');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// The overrides every test of the real loader needs:
/// - the sample's bundled assets for every flavor (or [assets]);
/// - the inline decoder (or [decoder]);
/// - a store on a fresh temp directory (or [storeDir]);
/// - the app version `1.0.0+2` (or [appVersion]);
/// - a [FakeContentRemote] (or [remote]) and a [FakeConnectivitySource]
///   (or [connectivity]), so no test reaches the network.
List<Override> contentTestOverrides({
  Map<String, Uint8List?>? assets,
  PackDecoder? decoder,
  Directory? storeDir,
  String appVersion = '1.0.0+2',
  Clock? clock,
  void Function(KillPoint point)? onKillPoint,
  ContentRemote? remote,
  ConnectivitySource? connectivity,
}) {
  final dir = storeDir ?? tempStoreDir();
  final now = clock ?? DateTime.now;
  return [
    assetBytesReaderProvider.overrideWithValue(
      fakeAssetBytesReader(assets ?? allFlavorBundledAssets()),
    ),
    packDecoderProvider.overrideWithValue(decoder ?? inlinePackDecoder),
    packStoreProvider.overrideWith(
      (ref) async => PackStore(dir, clock: now, onKillPoint: onKillPoint),
    ),
    appInfoProvider.overrideWith((ref) async => FakeAppInfo(appVersion)),
    clockProvider.overrideWithValue(now),
    contentRemoteProvider.overrideWithValue(remote ?? FakeContentRemote()),
    connectivitySourceProvider.overrideWithValue(
      connectivity ?? FakeConnectivitySource(),
    ),
  ];
}

/// Checks data-model.md "Content state" invariants 1–4 on [dir], as a launch
/// leaves it. [appVersion] is the running app's `<version>+<build>`.
void expectStoreInvariants(Directory dir, String appVersion) {
  final stateFile = File('${dir.path}/state.json');
  expect(stateFile.existsSync(), isTrue, reason: 'state.json is written');
  expect(File('${dir.path}/state.json.tmp').existsSync(), isFalse);
  final state = ContentState.decode(stateFile.readAsBytesSync());
  expect(state.appVersion, appVersion, reason: 'invariant 4');

  final active = state.active;
  final ready = state.ready;
  if (active != null && ready != null) {
    expect(ready.version, greaterThan(active.version), reason: 'invariant 1');
  }

  final listed = {for (final entry in state.stored) entry.file};
  for (final name in listed) {
    expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
  }
  final packFiles = {
    for (final file in dir.listSync().whereType<File>())
      if (file.uri.pathSegments.last.startsWith('core-'))
        file.uri.pathSegments.last,
  };
  expect(packFiles, listed, reason: 'invariant 2: no stray pack file');
  final tmp = Directory('${dir.path}/tmp');
  if (tmp.existsSync()) {
    expect(tmp.listSync(), isEmpty, reason: 'invariant 2: no tmp/ file');
  }

  for (final version in state.unusable.keys) {
    expect(state.stored.map((e) => e.version), isNot(contains(version)));
    expect(state.attempts.keys, isNot(contains(version)), reason: 'inv. 3');
  }
}

/// Puts v[version] of the sample in [store] as `ready`, as a verified
/// download leaves it, with its own [minClientVersion].
void storeSampleVersion(
  PackStore store,
  int version, {
  String minClientVersion = '1.0.0',
}) {
  final pack = samplePackVersion(version);
  store.beginDownload(version).writeAsBytesSync(pack.bytes);
  store.commitDownload(
    version,
    ExpectedPack(
      version: version,
      size: pack.expected.size,
      sha256: pack.expected.sha256,
      minClientVersion: minClientVersion,
    ),
  );
}

/// A dev container with the content seams of [contentTestOverrides].
ProviderContainer contentContainer({
  Directory? storeDir,
  Map<String, Uint8List?>? assets,
  String appVersion = '1.0.0+2',
  PackDecoder? decoder,
  void Function(KillPoint point)? onKillPoint,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      flavorProvider.overrideWithValue(Flavor.dev),
      ...contentTestOverrides(
        storeDir: storeDir,
        assets: assets,
        appVersion: appVersion,
        decoder: decoder,
        onKillPoint: onKillPoint,
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Dev bundled assets holding [pack] instead of the sample's v1.
Map<String, Uint8List?> bundledAssetsFor(EncodedPack pack) {
  final v = pack.expected.version;
  final record = {
    'file': 'core-$v.json.gz',
    'min_client_version': pack.expected.minClientVersion,
    'pack_id': 'core',
    'sha256': pack.expected.sha256,
    'size': pack.expected.size,
    'source': 'sample',
    'version': v,
  };
  return {
    sampleBundledRecordAsset: utf8.encode(canonicalJson(record)),
    'assets/content/dev/core-$v.json.gz': pack.bytes,
  };
}

/// A store on [dir] as a launch of [appVersion] leaves it.
PackStore openStore(Directory dir, {String appVersion = '1.0.0+2'}) =>
    PackStore(dir)
      ..reconcile()
      ..setAppVersion(appVersion);

/// A [ContentRemote] serving a scripted manifest and files, recording every
/// request.
final class FakeContentRemote implements ContentRemote {
  /// What the next manifest request returns.
  ManifestResult manifestResult = const ManifestOk(
    Manifest(version: 0, packs: []),
  );

  /// The file bytes each URL serves.
  final files = <String, Uint8List>{};

  /// When set, a download waits for it before finishing, so a test can
  /// cancel mid-download.
  Completer<void>? holdDownload;

  /// When set, a download returns this instead of serving its file.
  DownloadResult? downloadResult;

  int manifestRequests = 0;
  final downloads = <String>[];

  /// A manifest offering [pack] at [url], as the server would.
  void offer(
    EncodedPack pack, {
    String url = 'https://packs.test/core.json.gz',
    String minClientVersion = '1.0.0',
    int? size,
  }) {
    files[url] = pack.bytes;
    manifestResult = ManifestOk(
      Manifest(
        version: pack.expected.version,
        packs: [
          ManifestPack(
            packId: 'core',
            version: pack.expected.version,
            url: url,
            sha256: pack.expected.sha256,
            size: size ?? pack.expected.size,
            minClientVersion: minClientVersion,
          ),
        ],
      ),
    );
  }

  @override
  Future<ManifestResult> fetchManifest({required CancelToken cancel}) async {
    manifestRequests++;
    return manifestResult;
  }

  @override
  Future<DownloadResult> download(
    ManifestPack entry,
    File target, {
    required CancelToken cancel,
  }) async {
    downloads.add(entry.url);
    final bytes = files[entry.url] ?? Uint8List(0);
    target.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    final hold = holdDownload;
    if (hold != null) await Future.any([hold.future, cancel.whenCancel]);
    if (cancel.isCancelled) return const DownloadCancelled();
    if (downloadResult case final result?) return result;
    if (bytes.length > entry.size) {
      return const DownloadFailed(RefusalReason.tooLarge);
    }
    target.writeAsBytesSync(bytes);
    return Downloaded(size: bytes.length, sha256: sha256Hex(bytes));
  }
}

/// A [ConnectivitySource] a test drives.
final class FakeConnectivitySource implements ConnectivitySource {
  final _changes = StreamController<bool>.broadcast();
  bool current = true;

  void set(bool online) {
    current = online;
    _changes.add(online);
  }

  @override
  Stream<bool> get online => _changes.stream;

  @override
  Future<bool> isOnline() async => current;
}

/// A clock a test moves by hand.
final class FakeClock {
  FakeClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}
