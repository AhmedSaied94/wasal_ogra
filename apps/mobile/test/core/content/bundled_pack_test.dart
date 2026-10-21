import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/bundled_pack.dart';

import '../../helpers/content.dart';

const _releaseRecord = 'assets/content/release/bundled.json';
const _releaseFile = 'assets/content/release/core-1.json.gz';

Map<String, Object?> _record() => (jsonDecode(
  utf8.decode(sampleBundledAssets()[sampleBundledRecordAsset]!),
) as Map<String, dynamic>).cast<String, Object?>();

/// The sample's assets with `bundled.json` replaced by [record].
Map<String, Uint8List?> _withRecord(Object record) => {
  ...sampleBundledAssets(),
  sampleBundledRecordAsset: utf8.encode(
    record is String ? record : jsonEncode(record),
  ),
};

Future<BundledPack> _load(Map<String, Uint8List?> assets, [Flavor? flavor]) =>
    loadBundledPack(fakeAssetBytesReader(assets), flavor ?? Flavor.dev);

void main() {
  test('dev reads the dev directory: the record and the file', () async {
    final pack = await _load(sampleBundledAssets());
    expect(pack.record.version, 1);
    expect(pack.record.source, 'sample');
    expect(pack.bytes, sampleBundledBytes());
    final expected = pack.record.expected;
    expect(expected.size, sampleExpectedPack().size);
    expect(expected.sha256, sampleExpectedPack().sha256);
    expect(expected.minClientVersion, '1.0.0');
  });

  test('staging and prod read the release directory', () async {
    final dev = sampleBundledAssets();
    final release = {
      _releaseRecord: dev[sampleBundledRecordAsset],
      _releaseFile: dev[sampleBundledFileAsset],
    };
    for (final flavor in [Flavor.staging, Flavor.prod]) {
      expect((await _load(release, flavor)).record.version, 1);
      await expectLater(_load(dev, flavor), throwsA(isA<BundledPackMissing>()));
    }
    await expectLater(_load(release), throwsA(isA<BundledPackMissing>()));
  });

  test('a missing record or file is missing', () async {
    await expectLater(
      _load({...sampleBundledAssets(), sampleBundledRecordAsset: null}),
      throwsA(isA<BundledPackMissing>()),
    );
    await expectLater(
      _load({...sampleBundledAssets(), sampleBundledFileAsset: null}),
      throwsA(isA<BundledPackMissing>()),
    );
  });

  group('a record that breaks a rule is invalid', () {
    final cases = <String, Object>{
      'pack_id': {..._record(), 'pack_id': 'other'},
      'version 0': {..._record(), 'version': 0, 'file': 'core-0.json.gz'},
      'file': {..._record(), 'file': 'core-2.json.gz'},
      'size 0': {..._record(), 'size': 0},
      'sha256 upper case': {
        ..._record(),
        'sha256': (_record()['sha256']! as String).toUpperCase(),
      },
      'sha256 short': {
        ..._record(),
        'sha256': (_record()['sha256']! as String).substring(1),
      },
      'min_client_version': {..._record(), 'min_client_version': '1.0'},
      'source': {..._record(), 'source': 'elsewhere'},
      'release_record_sha256': {..._record(), 'release_record_sha256': 'x'},
      'a missing field': {..._record()}..remove('sha256'),
      'a float size': jsonEncode(_record())
          .replaceFirst(RegExp(r'"size":\d+'), '"size":3386.5'),
      'not JSON': '{"pack_id":',
    };
    for (final MapEntry(key: name, value: record) in cases.entries) {
      test(name, () async {
        await expectLater(
          _load(_withRecord(record)),
          throwsA(isA<BundledPackInvalid>()),
        );
      });
    }
  });

  test('a record naming a missing file is missing', () async {
    final assets = _withRecord({
      ..._record(),
      'version': 2,
      'file': 'core-2.json.gz',
    });
    await expectLater(_load(assets), throwsA(isA<BundledPackMissing>()));
  });
}
