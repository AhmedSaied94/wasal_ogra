import 'dart:convert';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/content/decode_pack_file.dart';

/// The bundled pack's directory for [flavor]
/// (specs/006-m04-content-loader/contracts/bundling.md).
String bundledPackDir(Flavor flavor) => switch (flavor) {
  Flavor.dev => 'assets/content/dev',
  Flavor.staging || Flavor.prod => 'assets/content/release',
};

/// The flavor's bundle has no pack, or its record names a file it lacks.
final class BundledPackMissing implements Exception {
  const BundledPackMissing(this.path);

  final String path;

  @override
  String toString() => 'BundledPackMissing: $path is not in the bundle';
}

/// The bundle's `bundled.json` breaks a data-model rule.
final class BundledPackInvalid implements Exception {
  const BundledPackInvalid(this.message);

  final String message;

  @override
  String toString() => 'BundledPackInvalid: $message';
}

/// `bundled.json`, checked against data-model.md "Bundled pack record".
final class BundledPackRecord {
  const BundledPackRecord._({
    required this.version,
    required this.file,
    required this.size,
    required this.sha256,
    required this.minClientVersion,
    required this.source,
    this.releaseRecordSha256,
  });

  /// Throws [BundledPackInvalid] for a record that breaks a rule.
  factory BundledPackRecord.parse(Uint8List bytes) {
    final Map<String, Object> json;
    try {
      json = decodeContentJson(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw BundledPackInvalid('not UTF-8 JSON: ${error.message}');
    } on ContentJsonError catch (error) {
      throw BundledPackInvalid('$error');
    }
    T field<T extends Object>(String name) => switch (json[name]) {
      final T value => value,
      _ => throw BundledPackInvalid('$name is missing or not a $T'),
    };
    void rule(bool holds, String message) {
      if (!holds) throw BundledPackInvalid(message);
    }

    final version = field<int>('version');
    final file = field<String>('file');
    final size = field<int>('size');
    final sha256 = field<String>('sha256');
    final minClientVersion = field<String>('min_client_version');
    final source = field<String>('source');
    final release = json['release_record_sha256'];
    rule(field<String>('pack_id') == 'core', 'pack_id must be "core"');
    rule(version >= 1, 'version must be at least 1');
    rule(file == 'core-$version.json.gz', 'file must be core-$version.json.gz');
    rule(size >= 1, 'size must be at least 1');
    rule(_sha256.hasMatch(sha256), 'sha256 must be 64 lowercase hex');
    rule(
      _version.hasMatch(minClientVersion) &&
          ClientVersion.parse(minClientVersion) != null,
      'min_client_version must be MAJOR.MINOR.PATCH',
    );
    rule(_sources.contains(source), 'source must be one of $_sources');
    rule(
      release == null || (release is String && _sha256.hasMatch(release)),
      'release_record_sha256 must be 64 lowercase hex',
    );
    return BundledPackRecord._(
      version: version,
      file: file,
      size: size,
      sha256: sha256,
      minClientVersion: minClientVersion,
      source: source,
      releaseRecordSha256: release as String?,
    );
  }

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');
  static final _version = RegExp(r'^\d+\.\d+\.\d+$');
  static const _sources = {'sample', 'content_source'};

  final int version;
  final String file;
  final int size;
  final String sha256;
  final String minClientVersion;

  /// `sample` (dev) or `content_source` (release).
  final String source;
  final String? releaseRecordSha256;

  ExpectedPack get expected => ExpectedPack(
    version: version,
    size: size,
    sha256: sha256,
    minClientVersion: minClientVersion,
  );
}

/// The bundled record and the bytes of the file it names.
final class BundledPack {
  const BundledPack(this.record, this.bytes);

  final BundledPackRecord record;
  final Uint8List bytes;
}

/// Reads the flavor's `bundled.json`, then the file it names. The file is
/// checked later, by `decodePackFile`.
Future<BundledPack> loadBundledPack(
  AssetBytesReader read,
  Flavor flavor,
) async {
  final dir = bundledPackDir(flavor);
  final recordPath = '$dir/bundled.json';
  final recordBytes = await read(recordPath);
  if (recordBytes == null) throw BundledPackMissing(recordPath);
  final record = BundledPackRecord.parse(recordBytes);
  final filePath = '$dir/${record.file}';
  final bytes = await read(filePath);
  if (bytes == null) throw BundledPackMissing(filePath);
  return BundledPack(record, bytes);
}
