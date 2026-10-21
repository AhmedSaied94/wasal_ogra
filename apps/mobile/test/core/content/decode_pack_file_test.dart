import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/refusal_reason.dart';

import '../../helpers/content.dart';

RefusalReason? _refusal(Uint8List bytes, ExpectedPack expected) =>
    switch (decodePackFile(bytes, expected)) {
      PackRefused(:final reason) => reason,
      PackDecoded() => null,
    };

RefusalReason? _refusalOf(EncodedPack pack) =>
    _refusal(pack.bytes, pack.expected);

ExpectedPack _with(ExpectedPack e, {int? version, int? size, String? sha}) =>
    ExpectedPack(
      version: version ?? e.version,
      size: size ?? e.size,
      sha256: sha ?? e.sha256,
      minClientVersion: e.minClientVersion,
    );

/// A gzip file of [bytes] with the size and sha256 a check expects of it.
EncodedPack _gzipOf(List<int> bytes) {
  final packed = Uint8List.fromList(GZipCodec(level: 9).encode(bytes));
  return (
    bytes: packed,
    expected: ExpectedPack(
      version: 1,
      size: packed.length,
      sha256: sha256Hex(packed),
      minClientVersion: '1.0.0',
    ),
  );
}

Map<String, dynamic> _firstTrip(Map<String, Object?> json) =>
    (json['trips']! as List<Object?>).first! as Map<String, dynamic>;

void main() {
  test('the sample decodes against its bundled record', () {
    final result = decodePackFile(sampleBundledBytes(), sampleExpectedPack());
    expect(result, isA<PackDecoded>());
    final decoded = result as PackDecoded;
    expect(decoded.source.version, 1);
    expect(decoded.canonicalBytes, greaterThan(sampleBundledBytes().length));
  });

  group('each step refuses with its reason', () {
    test('1: size', () {
      final e = sampleExpectedPack();
      expect(
        _refusal(sampleBundledBytes(), _with(e, size: e.size + 1)),
        RefusalReason.sizeMismatch,
      );
    });

    test('2: sha256, one flipped byte with the same size', () {
      final bytes = sampleBundledBytes();
      bytes[bytes.length ~/ 2] ^= 0x01;
      expect(
        _refusal(bytes, sampleExpectedPack()),
        RefusalReason.sha256Mismatch,
      );
    });

    test('3: more than 32 MiB out', () {
      expect(
        _refusalOf(_gzipOf(Uint8List(maxDecompressedBytes + 1))),
        RefusalReason.decompressTooLarge,
      );
    });

    test('3: truncated gzip', () {
      final bytes = Uint8List.sublistView(
        sampleBundledBytes(),
        0,
        sampleBundledBytes().length ~/ 2,
      );
      final expected = ExpectedPack(
        version: 1,
        size: bytes.length,
        sha256: sha256Hex(bytes),
        minClientVersion: '1.0.0',
      );
      expect(_refusal(bytes, expected), RefusalReason.unreadable);
    });

    test('4: invalid UTF-8 inside valid gzip', () {
      expect(
        _refusalOf(_gzipOf([0x7b, 0xff, 0xfe, 0x7d])),
        RefusalReason.unreadable,
      );
    });

    test('5: a fractional number', () {
      final json = samplePackJson();
      final events = _firstTrip(json)['events'] as List<dynamic>;
      (events.first as Map<String, dynamic>)['at_seconds'] = 38.5;
      expect(_refusalOf(encodePackFile(json)), RefusalReason.unreadable);
    });

    test('5: an unknown enum value', () {
      final json = samplePackJson();
      final passengers = _firstTrip(json)['passengers'] as List<dynamic>;
      (passengers.first as Map<String, dynamic>)['archetype'] = 'wizard';
      expect(_refusalOf(encodePackFile(json)), RefusalReason.unreadable);
    });

    test('5: a missing required part', () {
      final json = samplePackJson()..remove('catalog');
      expect(_refusalOf(encodePackFile(json)), RefusalReason.unreadable);
    });

    test('5: JSON that is not an object', () {
      expect(
        _refusalOf(_gzipOf(utf8.encode('[1, 2]'))),
        RefusalReason.unreadable,
      );
    });

    test('6: another pack id', () {
      final json = {...samplePackJson(), 'pack_id': 'other'};
      expect(_refusalOf(encodePackFile(json)), RefusalReason.wrongIdentity);
    });

    test('6: another version than expected', () {
      final pack = samplePackVersion(2);
      expect(
        _refusal(pack.bytes, _with(pack.expected, version: 1)),
        RefusalReason.wrongIdentity,
      );
    });

    test('7: an unsupported schema major', () {
      final json = {...samplePackJson(), 'schema_version': '2.0'};
      expect(_refusalOf(encodePackFile(json)), RefusalReason.schemaUnsupported);
    });
  });

  test('unknown fields are ignored', () {
    final json = samplePackJson();
    _firstTrip(json)['added_later'] = 'x';
    json['also_added'] = {'n': 1};
    expect(
      decodePackFile(encodePackFile(json).bytes, encodePackFile(json).expected),
      isA<PackDecoded>(),
    );
  });

  test('nothing is decompressed before the checksum passes', () {
    final huge = _gzipOf(Uint8List(maxDecompressedBytes + 1));
    expect(
      _refusal(huge.bytes, _with(huge.expected, sha: '0' * 64)),
      RefusalReason.sha256Mismatch,
    );
  });

  test('the supported schema majors are the schema set\'s', () {
    final schemaSet = jsonDecode(
      File('../../content/schemas/schema-set.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final majors = (schemaSet['min_client_version_by_major'] as Map).keys
        .map((k) => int.parse(k as String))
        .toSet();
    expect(supportedSchemaMajors, majors);
  });
}
