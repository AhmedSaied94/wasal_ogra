import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/refusal_reason.dart';
import 'package:wassal/core/network/api_environment.dart';
import 'package:wassal/core/network/http_client.dart' as http;

/// [ContentRemote] over dio: streamed bodies with byte caps, the URL rule
/// before every request, and the time limits of contracts/updates.md.
final class DioContentRemote implements ContentRemote {
  DioContentRemote({
    required this._dio,
    required this._flavor,
    required this._apiBase,
    this._manifestReceiveTimeout = http.manifestReceiveTimeout,
    this._chunkTimeout = http.downloadChunkTimeout,
    this._downloadTimeout = http.downloadTotalTimeout,
  });

  final Dio _dio;
  final Flavor _flavor;
  final String _apiBase;
  final Duration _manifestReceiveTimeout;
  final Duration _chunkTimeout;
  final Duration _downloadTimeout;

  @override
  Future<ManifestResult> fetchManifest({required CancelToken cancel}) async {
    final uri = Uri.parse('$_apiBase$manifestPath');
    if (!isAllowedUrl(_flavor, uri)) {
      return const ManifestFailed(RefusalDetail.insecureUrl);
    }
    final Uint8List body;
    try {
      final response = await _dio.getUri<ResponseBody>(
        uri,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: _manifestReceiveTimeout,
          headers: {'Accept': 'application/json'},
        ),
      );
      if (_failedStatus(response) case final detail?) {
        await _discard(response);
        return ManifestFailed(detail);
      }
      final read = await _readCapped(
        response.data!.stream.timeout(_manifestReceiveTimeout),
        http.manifestMaxBytes,
      );
      if (read == null) return const ManifestFailed(RefusalDetail.tooLarge);
      body = read;
    } on DioException catch (error) {
      return error.type == DioExceptionType.cancel
          ? const ManifestCancelled()
          : const ManifestFailed(RefusalDetail.unreachable);
    } on TimeoutException {
      return const ManifestFailed(RefusalDetail.unreachable);
    } on IOException {
      return const ManifestFailed(RefusalDetail.unreachable);
    }
    try {
      return ManifestOk(
        Manifest.fromJson(decodeContentJson(const Utf8Decoder().convert(body))),
      );
      // Untrusted bytes meet generated code here, as in decodePackFile: bad
      // UTF-8, a strict-JSON refusal, a missing field (a TypeError) or an
      // unknown value (an ArgumentError) all mean an unreadable manifest.
    } catch (_) {
      return const ManifestFailed(RefusalDetail.unreadable);
    }
  }

  @override
  Future<DownloadResult> download(
    ManifestPack entry,
    File target, {
    required CancelToken cancel,
  }) async {
    final uri = Uri.tryParse(entry.url);
    if (uri == null || !isAllowedUrl(_flavor, uri)) {
      return const DownloadFailed(
        RefusalReason.downloadFailed,
        RefusalDetail.insecureUrl,
      );
    }
    // The caller's token stays the caller's: the time limit cancels this
    // one, so a timeout and a cancel are told apart.
    final token = CancelToken();
    var timedOut = false;
    unawaited(cancel.whenCancel.then((_) => token.cancel()));
    final deadline = Timer(_downloadTimeout, () {
      timedOut = true;
      token.cancel();
    });
    DownloadResult? stopped() => timedOut
        ? const DownloadFailed(
            RefusalReason.downloadFailed,
            RefusalDetail.timeout,
          )
        : cancel.isCancelled
        ? const DownloadCancelled()
        : null;
    IOSink? sink;
    try {
      final response = await _dio.getUri<ResponseBody>(
        uri,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: _chunkTimeout,
        ),
      );
      if (_failedStatus(response) case final detail?) {
        await _discard(response);
        return DownloadFailed(RefusalReason.downloadFailed, detail);
      }
      final file = sink = target.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var size = 0;
      await for (final chunk in response.data!.stream.timeout(_chunkTimeout)) {
        size += chunk.length;
        if (size > entry.size) {
          token.cancel();
          return const DownloadFailed(RefusalReason.tooLarge);
        }
        hasher.add(chunk);
        file.add(chunk);
      }
      hasher.close();
      await file.flush();
      return Downloaded(size: size, sha256: digest.value.toString());
    } on DioException catch (error) {
      if (error.type != DioExceptionType.cancel) {
        return DownloadFailed(RefusalReason.downloadFailed, _detail(error));
      }
      return timedOut
          ? const DownloadFailed(
              RefusalReason.downloadFailed,
              RefusalDetail.timeout,
            )
          : const DownloadCancelled();
    } on TimeoutException {
      return stopped() ??
          const DownloadFailed(
            RefusalReason.downloadFailed,
            RefusalDetail.timeout,
          );
    } on FileSystemException {
      return const DownloadFailed(RefusalReason.storageError);
    } on IOException {
      // dio reports a cancel as a DioException, even mid-body; if an adapter
      // ever surfaces the aborted socket instead, it is still a cancel.
      return stopped() ??
          const DownloadFailed(
            RefusalReason.downloadFailed,
            RefusalDetail.unreachable,
          );
    } finally {
      deadline.cancel();
      try {
        await sink?.close();
      } on FileSystemException {
        // The result already says what happened; the caller deletes the file.
      }
    }
  }
}

/// Null for a `200`; otherwise why the response doesn't count.
RefusalDetail? _failedStatus(Response<ResponseBody> response) =>
    switch (response.statusCode) {
      200 => null,
      final int code when code >= 300 && code < 400 => RefusalDetail.redirect,
      _ => RefusalDetail.status,
    };

RefusalDetail _detail(DioException error) => switch (error.type) {
  DioExceptionType.receiveTimeout ||
  DioExceptionType.sendTimeout => RefusalDetail.timeout,
  _ => RefusalDetail.unreachable,
};

/// Closes a body the app won't read, so the connection is released.
Future<void> _discard(Response<ResponseBody> response) async {
  await response.data?.stream.listen(null).cancel();
}

/// The whole body, or null as soon as it passes [cap] bytes.
Future<Uint8List?> _readCapped(Stream<List<int>> stream, int cap) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (builder.length + chunk.length > cap) return null;
    builder.add(chunk);
  }
  return builder.takeBytes();
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
