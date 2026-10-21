import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/refusal_reason.dart';
import 'package:wassal/core/network/dio_content_remote.dart';
import 'package:wassal/core/network/http_client.dart';

import '../../helpers/content.dart';
import '../../helpers/synthetic_packs.dart';

typedef _Handler = Future<void> Function(HttpRequest request);

/// A local server: one handler per path, and every request it received.
final class _Server {
  _Server._(this._server) {
    _server.listen((request) async {
      requests.add(request);
      final handler = handlers[request.uri.path];
      if (handler == null) {
        request.response.statusCode = 404;
      } else {
        try {
          await handler(request);
        } on Object {
          // The client went away mid-response.
        }
      }
      try {
        await request.response.close();
      } on Object {
        // Already closed by the client.
      }
    });
  }

  static Future<_Server> start() async =>
      _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final handlers = <String, _Handler>{};
  final requests = <HttpRequest>[];

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);
}

_Handler _json(Object body, {int status = 200}) => (request) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(body is String ? body : jsonEncode(body));
};

_Handler _bytes(List<int> body) => (request) async {
  request.response.add(body);
};

/// Sends [body] at [bytesPerSecond], in tenths of a second.
_Handler _throttled(List<int> body, int bytesPerSecond) => (request) async {
  final step = bytesPerSecond ~/ 10;
  for (var i = 0; i < body.length; i += step) {
    request.response.add(body.sublist(i, (i + step).clamp(0, body.length)));
    await request.response.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
};

/// Sends [head], then nothing for [stall].
_Handler _stalling(List<int> head, Duration stall) => (request) async {
  request.response.add(head);
  await request.response.flush();
  await Future<void>.delayed(stall);
};

Map<String, Object?> _manifest(String url, {int size = 10, int version = 2}) =>
    {
      'version': version,
      'packs': [
        {
          'pack_id': 'core',
          'version': version,
          'url': url,
          'sha256': '0' * 64,
          'size': size,
          'min_client_version': '1.0.0',
        },
      ],
    };

ManifestPack _entry(String url, int size) => ManifestPack(
  packId: 'core',
  version: 2,
  url: url,
  sha256: '0' * 64,
  size: size,
  minClientVersion: '1.0.0',
);

void main() {
  late _Server server;
  late Directory dir;

  // The test binding answers every HttpClient request with a 400. These
  // tests talk to a real local server, so they use the real client.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    server = await _Server.start();
    dir = await Directory.systemTemp.createTemp('remote_test');
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  DioContentRemote remote({Flavor flavor = Flavor.dev, String? base}) =>
      DioContentRemote(
        dio: createHttpClient(flavor, FakeAppInfo('1.0.0+2')),
        flavor: flavor,
        apiBase: base ?? server.base,
        manifestReceiveTimeout: const Duration(milliseconds: 400),
        chunkTimeout: const Duration(milliseconds: 400),
        downloadTimeout: const Duration(seconds: 30),
      );

  File target() => File('${dir.path}/core-2.part');

  group('manifest', () {
    Future<ManifestResult> fetch([DioContentRemote? r]) =>
        (r ?? remote()).fetchManifest(cancel: CancelToken());

    RefusalDetail? failure(ManifestResult result) => switch (result) {
      ManifestFailed(:final detail) => detail,
      ManifestOk() || ManifestCancelled() => null,
    };

    test('a 200 with a valid body, and the request headers', () async {
      server.handlers[manifestPath] = _json(_manifest('${server.base}/p'));
      final result = await fetch();
      expect(result, isA<ManifestOk>());
      expect((result as ManifestOk).manifest.packs.single.version, 2);
      final headers = server.requests.single.headers;
      expect(headers.value('accept'), 'application/json');
      expect(headers.value('x-client-version'), '1.0.0+2');
      expect(headers.value('x-platform'), 'android');
      expect(headers.value('authorization'), isNull);
      expect(headers.value('cookie'), isNull);
    });

    test('a redirect is refused, and its target never requested', () async {
      server.handlers[manifestPath] = (request) async {
        request.response
          ..statusCode = 302
          ..headers.set('location', '${server.base}/elsewhere');
      };
      server.handlers['/elsewhere'] = _json(_manifest('x'));
      expect(failure(await fetch()), RefusalDetail.redirect);
      expect(server.requests.map((r) => r.uri.path), [manifestPath]);
    });

    test('a status other than 200', () async {
      for (final status in [500, 429, 204]) {
        server.handlers[manifestPath] = _json({}, status: status);
        expect(failure(await fetch()), RefusalDetail.status, reason: '$status');
      }
    });

    test('a body over 64 KiB', () async {
      server.handlers[manifestPath] = _bytes(Uint8List(65537));
      expect(failure(await fetch()), RefusalDetail.tooLarge);
    });

    test('a body that does not read as a manifest', () async {
      for (final body in [
        'nope',
        '{"version": 1.5, "packs": []}',
        '{"version": 1}',
        '{"version": 1, "packs": [{"pack_id": "core"}]}',
      ]) {
        server.handlers[manifestPath] = _json(body);
        expect(failure(await fetch()), RefusalDetail.unreadable, reason: body);
      }
    });

    test('a server that stalls, or no server at all', () async {
      server.handlers[manifestPath] = _stalling(
        utf8.encode('{"version"'),
        const Duration(seconds: 2),
      );
      expect(failure(await fetch()), RefusalDetail.unreachable);
      expect(
        failure(await fetch(remote(base: 'http://127.0.0.1:1'))),
        RefusalDetail.unreachable,
      );
    });

    test('a cancelled request is not a failure', () async {
      server.handlers[manifestPath] = _stalling(
        utf8.encode('{"version"'),
        const Duration(seconds: 2),
      );
      final cancel = CancelToken();
      Timer(const Duration(milliseconds: 100), cancel.cancel);
      expect(
        await remote().fetchManifest(cancel: cancel),
        isA<ManifestCancelled>(),
      );
    });

    test('staging refuses an http base before connecting', () async {
      server.handlers[manifestPath] = _json(_manifest('x'));
      final result = await fetch(remote(flavor: Flavor.staging));
      expect(failure(result), RefusalDetail.insecureUrl);
      expect(server.requests, isEmpty);
    });
  });

  group('download', () {
    Future<DownloadResult> download(
      ManifestPack entry, {
      DioContentRemote? r,
      CancelToken? cancel,
    }) => (r ?? remote()).download(
      entry,
      target(),
      cancel: cancel ?? CancelToken(),
    );

    test('streams to the file, with its size and sha256', () async {
      final body = samplePackVersion(2).bytes;
      server.handlers['/packs/core-2.json.gz'] = _bytes(body);
      final result = await download(
        _entry('${server.base}/packs/core-2.json.gz', body.length),
      );
      expect(result, isA<Downloaded>());
      final done = result as Downloaded;
      expect(done.size, body.length);
      expect(done.sha256, sha256Hex(body));
      expect(target().readAsBytesSync(), body);
      final headers = server.requests.single.headers;
      expect(headers.value('x-client-version'), '1.0.0+2');
      expect(headers.value('x-platform'), 'android');
      expect(headers.value('authorization'), isNull);
    });

    test('one byte over the entry size', () async {
      server.handlers['/p'] = _bytes(Uint8List(11));
      final result = await download(_entry('${server.base}/p', 10));
      expect(result, isA<DownloadFailed>());
      expect((result as DownloadFailed).reason, RefusalReason.tooLarge);
    });

    (RefusalReason, RefusalDetail?)? failure(DownloadResult result) =>
        switch (result) {
          DownloadFailed(:final reason, :final detail) => (reason, detail),
          _ => null,
        };

    test('a redirect, a 404 and a stall', () async {
      server.handlers['/moved'] = (request) async {
        request.response
          ..statusCode = 301
          ..headers.set('location', '${server.base}/p');
      };
      server.handlers['/stall'] = _stalling(
        Uint8List(4),
        const Duration(seconds: 2),
      );
      expect(failure(await download(_entry('${server.base}/moved', 10))), (
        RefusalReason.downloadFailed,
        RefusalDetail.redirect,
      ));
      expect(failure(await download(_entry('${server.base}/missing', 10))), (
        RefusalReason.downloadFailed,
        RefusalDetail.status,
      ));
      expect(failure(await download(_entry('${server.base}/stall', 10))), (
        RefusalReason.downloadFailed,
        RefusalDetail.timeout,
      ));
      expect(server.requests.map((r) => r.uri.path), isNot(contains('/p')));
    });

    test('no server at all', () async {
      expect(failure(await download(_entry('http://127.0.0.1:1/p', 10))), (
        RefusalReason.downloadFailed,
        RefusalDetail.unreachable,
      ));
    });

    test('the whole download has a time limit', () async {
      server.handlers['/slow'] = _throttled(Uint8List(4000), 1000);
      final r = DioContentRemote(
        dio: createHttpClient(Flavor.dev, FakeAppInfo('1.0.0+2')),
        flavor: Flavor.dev,
        apiBase: server.base,
        chunkTimeout: const Duration(seconds: 2),
        downloadTimeout: const Duration(milliseconds: 500),
      );
      expect(
        failure(await download(_entry('${server.base}/slow', 4000), r: r)),
        (RefusalReason.downloadFailed, RefusalDetail.timeout),
      );
    });

    test('cancelling mid-stream', () async {
      server.handlers['/p'] = _stalling(
        Uint8List(100),
        const Duration(seconds: 2),
      );
      final cancel = CancelToken();
      Timer(const Duration(milliseconds: 150), cancel.cancel);
      final result = await download(
        _entry('${server.base}/p', 1000),
        cancel: cancel,
        r: DioContentRemote(
          dio: createHttpClient(Flavor.dev, FakeAppInfo('1.0.0+2')),
          flavor: Flavor.dev,
          apiBase: server.base,
          chunkTimeout: const Duration(seconds: 5),
        ),
      );
      expect(result, isA<DownloadCancelled>());
    });

    test('at 1 Mbit/s, an MVP-size pack arrives and decodes in < 30 s '
        '(SC-006)', () async {
      final pack = mvpSizePack();
      server.handlers['/mvp'] = _throttled(pack.bytes, 125000);
      final watch = Stopwatch()..start();
      final result = await download(
        _entry('${server.base}/mvp', pack.bytes.length),
      );
      expect(result, isA<Downloaded>());
      final decoded = decodePackFile(target().readAsBytesSync(), pack.expected);
      expect(decoded, isA<PackDecoded>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
    });

    test('staging refuses an http pack URL before connecting', () async {
      server.handlers['/p'] = _bytes(Uint8List(10));
      expect(
        failure(
          await download(
            _entry('${server.base}/p', 10),
            r: remote(flavor: Flavor.staging),
          ),
        ),
        (RefusalReason.downloadFailed, RefusalDetail.insecureUrl),
      );
      expect(server.requests, isEmpty);
    });
  });
}
