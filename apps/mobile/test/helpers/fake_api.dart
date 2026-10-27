// A scriptable server (specs/011-m06-identity-sync/tasks.md T004): answers
// per `(method, path)`, in order, or from a handler; answers can be held or
// "dropped" (the request reaches the server, which records it, and the
// caller sees a timeout). Every request is logged with its bearer, for
// assertions.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/network/api_client.dart';

/// Answers a request: an [ApiResult], built from what it asked.
typedef ApiHandler = FutureOr<ApiResult> Function(ApiRequest request);

/// One scripted answer. [answer] is an [ApiResult] or an [ApiHandler].
final class FakeReply {
  const FakeReply(this.answer, {this.dropped = false, this.gate});

  /// The server answers, and the answer is lost: the caller sees
  /// `ApiUnreachable(timeout)`.
  const FakeReply.dropped(this.answer) : dropped = true, gate = null;

  /// The answer waits for [gate], so a test can act while it is in flight.
  const FakeReply.held(this.answer, Completer<void> this.gate)
    : dropped = false;

  final Object answer;
  final bool dropped;
  final Completer<void>? gate;
}

ApiOk apiOk(Map<String, Object?> json, {int status = 200}) =>
    ApiOk(status, json, sentAtElapsedMs: 0, receivedAtElapsedMs: 0);

ApiFailure apiFail(
  int status,
  String code, {
  Map<String, Object?> details = const {},
  Duration? retryAfter,
}) => ApiFailure(status, code, details: details, retryAfter: retryAfter);

const unreachable = ApiUnreachable(UnreachableKind.noConnection);

final class FakeApi implements ApiClient {
  FakeApi({this.elapsedMs, this.latency, this.wait, this.fallback});

  /// The answer to anything not scripted; null fails the test.
  ApiResult? fallback;

  /// The uptime counter, for the answers' elapsed times.
  int Function()? elapsedMs;

  /// How long each answer takes, waited through [wait] (the sync's fake
  /// time) when given.
  Duration? latency;
  Future<void> Function(Duration)? wait;

  /// Every request, in order.
  final log = <ApiRequest>[];

  final _queues = <String, List<FakeReply>>{};
  final _always = <String, FakeReply>{};

  static String _key(String method, String path) => '$method $path';

  /// Queues [answers] for [method] [path], each answered once in order.
  void reply(String method, String path, List<Object> answers) =>
      (_queues[_key(method, path)] ??= []).addAll([
        for (final a in answers) a is FakeReply ? a : FakeReply(a),
      ]);

  /// Answers [method] [path] with [answer] whenever its queue is empty.
  void always(String method, String path, Object answer) =>
      _always[_key(method, path)] = answer is FakeReply
      ? answer
      : FakeReply(answer);

  /// The requests to [path].
  List<ApiRequest> to(String path) => [
    for (final r in log)
      if (r.path == path) r,
  ];

  @override
  Future<ApiResult> send(ApiRequest request) async {
    log.add(request);
    final key = _key(request.method, request.path);
    final queue = _queues[key];
    final reply = queue != null && queue.isNotEmpty
        ? queue.removeAt(0)
        : _always[key] ??
              switch (fallback) {
                final ApiResult answer => FakeReply(answer),
                null => fail('No answer scripted for $key'),
              };
    final sentAt = elapsedMs?.call() ?? 0;
    if (latency case final latency?) {
      await (wait?.call(latency) ?? Future<void>.delayed(latency));
    }
    await reply.gate?.future;
    final result = switch (reply.answer) {
      final ApiResult result => result,
      final ApiHandler handler => await handler(request),
      final other => fail('Not an answer: $other'),
    };
    if (reply.dropped) return const ApiUnreachable(UnreachableKind.timeout);
    if (result case ApiOk(:final status, :final json)) {
      return ApiOk(
        status,
        json,
        sentAtElapsedMs: sentAt,
        receivedAtElapsedMs: elapsedMs?.call() ?? 0,
      );
    }
    return result;
  }
}
