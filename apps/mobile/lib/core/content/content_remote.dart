// The server side of content updates
// (specs/006-m04-content-loader/contracts/updates.md "ContentRemote").
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:wassal/core/content/refusal_reason.dart';

/// B04's manifest endpoint, under the API base.
const manifestPath = '/v1/content/manifest';

abstract interface class ContentRemote {
  /// GET `<api base>/v1/content/manifest`.
  Future<ManifestResult> fetchManifest({required CancelToken cancel});

  /// Streams `entry.url` into [target], hashing while writing. Stops past
  /// `entry.size`. The caller deletes [target] on any result but
  /// [Downloaded].
  Future<DownloadResult> download(
    ManifestPack entry,
    File target, {
    required CancelToken cancel,
  });
}

sealed class ManifestResult {
  const ManifestResult();
}

final class ManifestOk extends ManifestResult {
  const ManifestOk(this.manifest);

  final Manifest manifest;
}

final class ManifestFailed extends ManifestResult {
  const ManifestFailed(this.detail);

  final RefusalDetail detail;

  @override
  String toString() => 'ManifestFailed(${detail.wire})';
}

/// The caller cancelled the request: not a failure, so nothing is recorded.
final class ManifestCancelled extends ManifestResult {
  const ManifestCancelled();
}

sealed class DownloadResult {
  const DownloadResult();
}

final class Downloaded extends DownloadResult {
  const Downloaded({required this.size, required this.sha256});

  final int size;

  /// Lowercase hex, computed while the file was written.
  final String sha256;
}

final class DownloadFailed extends DownloadResult {
  const DownloadFailed(this.reason, [this.detail]);

  /// `download_failed`, `too_large` or `storage_error`.
  final RefusalReason reason;
  final RefusalDetail? detail;

  @override
  String toString() => 'DownloadFailed(${reason.wire}, ${detail?.wire})';
}

/// The caller cancelled the download: not a failure, so nothing is recorded.
final class DownloadCancelled extends DownloadResult {
  const DownloadCancelled();
}
