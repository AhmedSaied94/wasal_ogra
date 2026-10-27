import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/network/http_client.dart';

import '../../helpers/content.dart' show FakeAppInfo;

// The player endpoints' client (specs/011-m06-identity-sync/contracts/
// api-client.md) against a server on the loopback address: one request, one
// result, and nothing thrown.

typedef _Handler = Future<void> Function(HttpRequest request);

final class _Server {
  _Server._(this._server) {
    _server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((request: request, body: body));
      final handler = handlers[request.uri.path];
      try {
        if (handler == null) {
          request.response.statusCode = 404;
        } else {
          await handler(request);
        }
        await request.response.close();
      } on Object {
        // The client went away.
      }
    });
  }

  static Future<_Server> start() async =>
      _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final handlers = <String, _Handler>{};
  final requests = <({HttpRequest request, String body})>[];

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);
}

_Handler _answer(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => (request) async {
  request.response.statusCode = status;
  headers.forEach(request.response.headers.set);
  if (body != null) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(body is String ? body : jsonEncode(body));
  }
};

/// An adapter that fails every request with [error], for the failures a
/// loopback server can't make.
final class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter(this.error);

  final Object Function(RequestOptions options) error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw error(options);

  @override
  void close({bool force = false}) {}
}

const _read = ApiRequest.get(
  ApiPaths.bootstrap,
  receiveTimeout: readReceiveTimeout,
);

void main() {
  // flutter_test answers every HTTP request with a 400 unless this is unset.
  setUpAll(() => HttpOverrides.global = null);

  late _Server server;
  late List<int> ticks;
  late Dio dio;

  setUp(() async {
    server = await _Server.start();
    addTearDown(server.close);
    ticks = [100, 250, 400, 900];
    dio = createHttpClient(Flavor.dev, FakeAppInfo('1.4.0+27'));
    addTearDown(() => dio.close(force: true));
  });

  DioApiClient client({Flavor flavor = Flavor.dev, String? base}) =>
      DioApiClient(
        dio: dio,
        flavor: flavor,
        apiBase: base ?? server.base,
        elapsedMs: () => ticks.removeAt(0),
      );

  test('a 2xx object is ApiOk, with the elapsed times around it', () async {
    server.handlers[ApiPaths.bootstrap] = _answer({
      'server_time': '2026-10-27T10:00:00Z',
      'state_version': 3,
    });

    final result = await client().send(_read);

    expect(result, isA<ApiOk>());
    final ok = result as ApiOk;
    expect(ok.status, 200);
    expect(ok.json, {
      'server_time': '2026-10-27T10:00:00Z',
      'state_version': 3,
    });
    expect(ok.sentAtElapsedMs, 100);
    expect(ok.receivedAtElapsedMs, 250);
  });

  test('the body goes as JSON, and the bearer only when given', () async {
    server.handlers[ApiPaths.sync] = _answer({'ok': 1});
    server.handlers[ApiPaths.anonymous] = _answer({'ok': 1}, status: 201);

    await client().send(
      const ApiRequest.post(
        ApiPaths.sync,
        receiveTimeout: syncReceiveTimeout,
        body: {'state_version': 0, 'ops': <Object?>[]},
        bearer: 'access-token-1',
      ),
    );
    await client().send(
      const ApiRequest.post(
        ApiPaths.anonymous,
        receiveTimeout: authReceiveTimeout,
        body: {'install_id': 'x'},
      ),
    );

    final (:request, :body) = server.requests.first;
    expect(request.method, 'POST');
    expect(request.headers.value('authorization'), 'Bearer access-token-1');
    expect(request.headers.contentType?.mimeType, 'application/json');
    expect(jsonDecode(body), {'state_version': 0, 'ops': <Object?>[]});
    expect(server.requests.last.request.headers.value('authorization'), isNull);
  });

  test('every request carries the version and platform headers', () async {
    server.handlers[ApiPaths.state] = _answer({'ok': 1});
    await client().send(
      const ApiRequest.get(ApiPaths.state, receiveTimeout: readReceiveTimeout),
    );
    await client().send(
      const ApiRequest.post(
        ApiPaths.refresh,
        receiveTimeout: authReceiveTimeout,
        body: {'refresh': 'r'},
      ),
    );
    for (final (:request, body: _) in server.requests) {
      expect(request.headers.value('x-client-version'), '1.4.0+27');
      expect(request.headers.value('x-platform'), 'android');
      expect(request.headers.value('accept'), 'application/json');
    }
  });

  test('an error envelope is ApiFailure with its code and details', () async {
    server.handlers[ApiPaths.link] = _answer({
      'error': {
        'code': 'provider_in_use',
        'message': 'linked elsewhere',
        'details': {
          'existing': {'player_id': 'p'},
        },
      },
    }, status: 409);

    final result = await client().send(
      const ApiRequest.post(ApiPaths.link, receiveTimeout: authReceiveTimeout),
    );

    expect(result, isA<ApiFailure>());
    final failure = result as ApiFailure;
    expect(failure.status, 409);
    expect(failure.code, 'provider_in_use');
    expect(failure.details, {
      'existing': {'player_id': 'p'},
    });
    expect(failure.retryAfter, isNull);
  });

  test('an envelope without details has empty details', () async {
    server.handlers[ApiPaths.state] = _answer({
      'error': {'code': 'token_expired', 'message': 'm'},
    }, status: 401);
    final result = await client().send(
      const ApiRequest.get(ApiPaths.state, receiveTimeout: readReceiveTimeout),
    );
    expect((result as ApiFailure).code, 'token_expired');
    expect(result.details, isEmpty);
  });

  test('Retry-After becomes retryAfter', () async {
    server.handlers[ApiPaths.sync] = _answer(
      {
        'error': {'code': 'rate_limited', 'message': 'm'},
      },
      status: 429,
      headers: {'retry-after': '42'},
    );
    final result = await client().send(
      const ApiRequest.post(ApiPaths.sync, receiveTimeout: syncReceiveTimeout),
    );
    expect((result as ApiFailure).code, 'rate_limited');
    expect(result.retryAfter, const Duration(seconds: 42));
  });

  test('an error body that is not the envelope is server_error', () async {
    server.handlers[ApiPaths.bootstrap] = _answer(
      '<html>bad gateway</html>',
      status: 502,
      headers: {'retry-after': '30'},
    );
    final result = await client().send(_read);
    expect((result as ApiFailure).status, 502);
    expect(result.code, 'server_error');
    expect(result.retryAfter, const Duration(seconds: 30));

    server.handlers[ApiPaths.bootstrap] = _answer(null, status: 500);
    expect(((await client().send(_read)) as ApiFailure).code, 'server_error');
  });

  test('a 2xx that is not a JSON object is server_error', () async {
    for (final body in ['[1, 2]', '"text"', 'not json', '']) {
      server.handlers[ApiPaths.bootstrap] = _answer(body);
      ticks = [1, 2];
      final result = await client().send(_read);
      expect(result, isA<ApiFailure>(), reason: body);
      expect((result as ApiFailure).code, 'server_error', reason: body);
      expect(result.status, 200, reason: body);
    }
  });

  test('a stalled answer is ApiUnreachable(timeout)', () async {
    server.handlers[ApiPaths.bootstrap] = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    };
    final result = await client().send(
      const ApiRequest.get(
        ApiPaths.bootstrap,
        receiveTimeout: Duration(milliseconds: 100),
      ),
    );
    expect(result, isA<ApiUnreachable>());
    expect((result as ApiUnreachable).kind, UnreachableKind.timeout);
  });

  test('a refused connection is ApiUnreachable(noConnection)', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final result = await client(base: 'http://127.0.0.1:$port').send(_read);
    expect((result as ApiUnreachable).kind, UnreachableKind.noConnection);
  });

  test('a failed host lookup is ApiUnreachable(dns)', () async {
    dio.httpClientAdapter = _FailingAdapter(
      (options) => DioException.connectionError(
        requestOptions: options,
        reason: 'lookup',
        error: const SocketException(
          'Failed host lookup: staging-api.example',
          osError: OSError('No address associated with hostname', 7),
        ),
      ),
    );
    final result = await client().send(_read);
    expect((result as ApiUnreachable).kind, UnreachableKind.dns);
  });

  test(
    'a connect timeout from the adapter is ApiUnreachable(timeout)',
    () async {
      dio.httpClientAdapter = _FailingAdapter(
        (options) => DioException.connectionTimeout(
          timeout: connectTimeout,
          requestOptions: options,
        ),
      );
      expect(
        ((await client().send(_read)) as ApiUnreachable).kind,
        UnreachableKind.timeout,
      );
    },
  );

  test('plain HTTP is refused outside dev, and never sent', () async {
    server.handlers[ApiPaths.bootstrap] = _answer({'ok': 1});
    for (final flavor in [Flavor.staging, Flavor.prod]) {
      final result = await client(flavor: flavor).send(_read);
      expect(result, isA<ApiFailure>());
      expect((result as ApiFailure).code, 'insecure_url');
    }
    // Dev reaches only the developer's own machine over plain HTTP.
    final elsewhere = await client(base: 'http://192.0.2.1:8000').send(_read);
    expect((elsewhere as ApiFailure).code, 'insecure_url');
    expect(server.requests, isEmpty);
  });

  test('the timeouts follow the contract', () {
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(authReceiveTimeout, const Duration(seconds: 15));
    expect(readReceiveTimeout, const Duration(seconds: 15));
    expect(syncReceiveTimeout, const Duration(seconds: 30));
  });

  test('a request prints without its bearer or body', () {
    const request = ApiRequest.post(
      ApiPaths.refresh,
      receiveTimeout: authReceiveTimeout,
      body: {'refresh': 'secret-refresh'},
      bearer: 'secret-access',
    );
    expect(request.toString(), 'ApiRequest(POST /v1/auth/refresh)');
    expect(request.withBearer('other').bearer, 'other');
    expect(request.withBearer('other').body, request.body);
  });

  group('resultOf', () {
    ApiResult of(int status, Object? body, [String? retryAfter]) => resultOf(
      status,
      body,
      retryAfter: retryAfter,
      sentAtElapsedMs: 0,
      receivedAtElapsedMs: 0,
    );

    test('ignores a Retry-After that is not whole seconds', () {
      for (final value in [
        'soon',
        '-1',
        '1.5',
        'Wed, 21 Oct 2026 07:28:00 GMT',
      ]) {
        expect((of(503, null, value) as ApiFailure).retryAfter, isNull);
      }
    });

    test('reads details only when they are an object', () {
      final failure = of(400, {
        'error': {'code': 'validation_error', 'details': 'x'},
      }) as ApiFailure;
      expect(failure.code, 'validation_error');
      expect(failure.details, isEmpty);
    });

    test('an envelope with no string code is server_error', () {
      expect(
        (of(400, {
          'error': {'code': 7},
        }) as ApiFailure).code,
        'server_error',
      );
    });
  });
}
