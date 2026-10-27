// How the app calls the server's player endpoints
// (specs/011-m06-identity-sync/contracts/api-client.md, research R3). One
// request, one result: nothing here throws for an answer or a network
// failure, and nothing logs a header or a body.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/network/api_environment.dart';
import 'package:wassal/core/network/http_client.dart';
import 'package:wassal/core/platform/app_info.dart';

part 'api_client.g.dart';

/// The player endpoints (B02, B03).
abstract final class ApiPaths {
  static const anonymous = '/v1/auth/anonymous';
  static const refresh = '/v1/auth/refresh';
  static const link = '/v1/auth/link';
  static const bootstrap = '/v1/bootstrap';
  static const state = '/v1/state';
  static const sync = '/v1/sync';
}

/// Receive timeouts per call (contracts/api-client.md "Timeouts"). Every
/// call connects within the factory's 10 s.
const authReceiveTimeout = Duration(seconds: 15);
const readReceiveTimeout = Duration(seconds: 15);
const syncReceiveTimeout = Duration(seconds: 30);

final class ApiRequest {
  const ApiRequest(
    this.method,
    this.path, {
    required this.receiveTimeout,
    this.body,
    this.bearer,
    this.forPlayer,
  });

  const ApiRequest.get(
    this.path, {
    required this.receiveTimeout,
    this.bearer,
    this.forPlayer,
  }) : method = 'GET',
       body = null;

  const ApiRequest.post(
    this.path, {
    required this.receiveTimeout,
    this.body,
    this.bearer,
    this.forPlayer,
  }) : method = 'POST';

  final String method;

  /// `/v1/…`, joined to the flavor's base URL.
  final String path;

  /// JSON-encodable; integers only for numbers.
  final Object? body;

  /// The access token, or null for the public auth calls.
  final String? bearer;
  final Duration receiveTimeout;

  /// The player whose data the request carries (the sync's batches and
  /// state fetches). The authorized client never sends it with another
  /// player's tokens (M06 research R7).
  final String? forPlayer;

  ApiRequest withBearer(String access) => ApiRequest(
    method,
    path,
    receiveTimeout: receiveTimeout,
    body: body,
    bearer: access,
    forPlayer: forPlayer,
  );

  /// The path only: the bearer and the body never reach a log.
  @override
  String toString() => 'ApiRequest($method $path)';
}

sealed class ApiResult {
  const ApiResult();
}

/// A `2xx` with a JSON object. The elapsed times are on the uptime counter,
/// for the time anchor (research R15).
final class ApiOk extends ApiResult {
  const ApiOk(
    this.status,
    this.json, {
    required this.sentAtElapsedMs,
    required this.receivedAtElapsedMs,
  });

  final int status;
  final Map<String, Object?> json;
  final int sentAtElapsedMs;
  final int receivedAtElapsedMs;

  @override
  String toString() => 'ApiOk($status)';
}

/// The error envelope's code. A body that isn't the envelope, or a `2xx`
/// that isn't a JSON object, is `server_error`.
final class ApiFailure extends ApiResult {
  const ApiFailure(
    this.status,
    this.code, {
    this.details = const {},
    this.retryAfter,
  });

  /// A URL the address rule refuses: a bug, never sent (FR-038).
  const ApiFailure.insecureUrl()
    : status = 0,
      code = 'insecure_url',
      details = const {},
      retryAfter = null;

  final int status;
  final String code;
  final Map<String, Object?> details;

  /// `Retry-After`, in seconds.
  final Duration? retryAfter;

  @override
  String toString() => 'ApiFailure($status $code)';
}

enum UnreachableKind { noConnection, timeout, dns }

/// No answer: the request may or may not have reached the server.
final class ApiUnreachable extends ApiResult {
  const ApiUnreachable(this.kind);

  final UnreachableKind kind;

  @override
  String toString() => 'ApiUnreachable(${kind.name})';
}

abstract interface class ApiClient {
  /// One request. Never throws for an answer or a network failure.
  Future<ApiResult> send(ApiRequest request);
}

/// [ApiClient] over M04's client: the flavor's base URL, the address rule,
/// no redirects and the two headers. No logging interceptor, in any flavor.
final class DioApiClient implements ApiClient {
  DioApiClient({
    required this._dio,
    required this._flavor,
    required this._apiBase,
    required this._elapsedMs,
  });

  final Dio _dio;
  final Flavor _flavor;
  final String _apiBase;

  /// The uptime counter now.
  final int Function() _elapsedMs;

  @override
  Future<ApiResult> send(ApiRequest request) async {
    final uri = Uri.parse('$_apiBase${request.path}');
    if (!isAllowedUrl(_flavor, uri)) return const ApiFailure.insecureUrl();
    final sentAt = _elapsedMs();
    final Response<String> response;
    try {
      response = await _dio.requestUri<String>(
        uri,
        data: request.body,
        options: Options(
          method: request.method,
          receiveTimeout: request.receiveTimeout,
          // Decoded here, so a body that isn't JSON is `server_error`, not a
          // network failure.
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'application/json',
            'Authorization': ?switch (request.bearer) {
              final token? => 'Bearer $token',
              null => null,
            },
          },
          contentType: request.body == null ? null : Headers.jsonContentType,
        ),
      );
    } on DioException catch (error) {
      return ApiUnreachable(_kindOf(error));
    } on TimeoutException {
      return const ApiUnreachable(UnreachableKind.timeout);
    } on IOException {
      return const ApiUnreachable(UnreachableKind.noConnection);
    }
    return resultOf(
      response.statusCode ?? 0,
      _decode(response.data),
      retryAfter: response.headers.value('retry-after'),
      sentAtElapsedMs: sentAt,
      receivedAtElapsedMs: _elapsedMs(),
    );
  }
}

/// The result of an answer with [status] and decoded [body].
ApiResult resultOf(
  int status,
  Object? body, {
  required String? retryAfter,
  required int sentAtElapsedMs,
  required int receivedAtElapsedMs,
}) {
  if (status >= 200 && status < 300) {
    if (body is! Map<String, Object?>) {
      return ApiFailure(status, 'server_error');
    }
    return ApiOk(
      status,
      body,
      sentAtElapsedMs: sentAtElapsedMs,
      receivedAtElapsedMs: receivedAtElapsedMs,
    );
  }
  final seconds = int.tryParse(retryAfter?.trim() ?? '');
  final wait = seconds == null || seconds < 0
      ? null
      : Duration(seconds: seconds);
  return switch (body) {
    {
      'error': {'code': final String code} && final Map<String, Object?> error,
    } =>
      ApiFailure(
        status,
        code,
        details: switch (error['details']) {
          final Map<String, Object?> details => details,
          _ => const {},
        },
        retryAfter: wait,
      ),
    _ => ApiFailure(status, 'server_error', retryAfter: wait),
  };
}

/// The JSON in [body], or null when there is none or it isn't JSON.
Object? _decode(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

UnreachableKind _kindOf(DioException error) => switch (error.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => UnreachableKind.timeout,
  DioExceptionType.connectionError || DioExceptionType.unknown
      when error.error is SocketException &&
          _isLookupFailure(error.error! as SocketException) =>
    UnreachableKind.dns,
  _ => UnreachableKind.noConnection,
};

/// A failed host lookup, as dart:io reports it.
bool _isLookupFailure(SocketException error) =>
    error.message.contains('Failed host lookup') ||
    (error.osError?.message.contains('address associated') ?? false);

/// The player endpoints' client. Read only after startup, when the app's
/// version and the trusted clock are known.
@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) {
  final flavor = ref.watch(flavorProvider);
  final dio = createHttpClient(flavor, ref.watch(appInfoProvider).requireValue);
  final clock = ref.watch(trustedClockProvider).requireValue;
  ref.onDispose(() => dio.close(force: true));
  return DioApiClient(
    dio: dio,
    flavor: flavor,
    apiBase: apiBaseUrl(flavor),
    elapsedMs: clock.elapsedMs,
  );
}
