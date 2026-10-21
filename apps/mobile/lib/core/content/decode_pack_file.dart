// Pack bytes to a content source
// (specs/006-m04-content-loader/contracts/loading.md "decodePackFile").
// Pure Dart with no I/O and no clock, so it runs inside Isolate.run and the
// same bytes always give the same result.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:crypto/crypto.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/content/refusal_reason.dart';

/// The schema majors this app reads. Keep in step with the keys of
/// `min_client_version_by_major` in `content/schemas/schema-set.json`; a
/// test compares them.
const supportedSchemaMajors = {1};

/// The most a pack may decompress to (32 MiB).
const maxDecompressedBytes = 33554432;

/// What a check compares a pack file against: from `bundled.json`, a stored
/// entry or a manifest entry (data-model.md "Expected pack").
final class ExpectedPack {
  const ExpectedPack({
    required this.version,
    required this.size,
    required this.sha256,
    required this.minClientVersion,
  });

  final int version;
  final int size;

  /// 64 lowercase hex, over the gzip bytes as served.
  final String sha256;
  final String minClientVersion;

  @override
  String toString() => 'ExpectedPack(v$version, $size bytes, $sha256)';
}

sealed class PackDecodeResult {
  const PackDecodeResult();
}

final class PackDecoded extends PackDecodeResult {
  const PackDecoded(this.source, this.canonicalBytes);

  /// Indexed in the decoding isolate.
  final PackContentSource source;

  /// The decompressed length, for the load-time log.
  final int canonicalBytes;
}

final class PackRefused extends PackDecodeResult {
  const PackRefused(this.reason);

  final RefusalReason reason;

  @override
  String toString() => 'PackRefused(${reason.wire})';
}

/// Checks [bytes] against [expected], then decodes them. Nothing is
/// decompressed before the size and the sha256 match.
PackDecodeResult decodePackFile(Uint8List bytes, ExpectedPack expected) {
  if (bytes.length != expected.size) {
    return const PackRefused(RefusalReason.sizeMismatch);
  }
  if (sha256.convert(bytes).toString() != expected.sha256) {
    return const PackRefused(RefusalReason.sha256Mismatch);
  }
  final Pack pack;
  final int canonicalBytes;
  try {
    final json = _gunzipCapped(bytes);
    canonicalBytes = json.length;
    final text = const Utf8Decoder().convert(json);
    pack = Pack.fromJson(decodeContentJson(text));
  } on _TooLarge {
    return const PackRefused(RefusalReason.decompressTooLarge);
    // This is the one place untrusted bytes meet generated code: a bad gzip
    // stream, bad UTF-8, a strict-JSON refusal, a missing field (a TypeError
    // from a cast) or an unknown enum value (an ArgumentError). Each means
    // the same thing, an unreadable pack, so this boundary catches all of
    // them (research R3).
  } catch (_) {
    return const PackRefused(RefusalReason.unreadable);
  }
  if (pack.packId != 'core' || pack.version != expected.version) {
    return const PackRefused(RefusalReason.wrongIdentity);
  }
  final major = int.tryParse(pack.schemaVersion.split('.').first);
  if (!supportedSchemaMajors.contains(major)) {
    return const PackRefused(RefusalReason.schemaUnsupported);
  }
  return PackDecoded(PackContentSource(pack), canonicalBytes);
}

final class _TooLarge implements Exception {
  const _TooLarge();
}

/// Gunzips [bytes], throwing [_TooLarge] as soon as the output passes
/// [maxDecompressedBytes], so a crafted file can't exhaust memory.
Uint8List _gunzipCapped(Uint8List bytes) {
  final out = _CappedSink(maxDecompressedBytes);
  GZipCodec().decoder.startChunkedConversion(out)
    ..add(bytes)
    ..close();
  return out.builder.takeBytes();
}

final class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.cap);

  final int cap;
  final builder = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    // The decoder hands output over in buffer-sized pieces, so throwing here
    // stops it within one buffer of the cap.
    if (builder.length + chunk.length > cap) throw const _TooLarge();
    builder.add(chunk);
  }

  @override
  void close() {}
}
