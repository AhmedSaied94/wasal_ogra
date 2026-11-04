import 'dart:collection';

import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/network/api_client.dart';

// The piggy's server as the tests script it (specs/018-m11-ads, T044, T045).

/// Answers each request with the next of [answers], then 404s.
final class ScriptedPiggyServer implements AuthorizedApi {
  ScriptedPiggyServer([Iterable<ApiResult> answers = const []])
    : _answers = Queue.of(answers);

  final Queue<ApiResult> _answers;
  final requests = <ApiRequest>[];

  void add(ApiResult answer) => _answers.add(answer);

  @override
  Future<ApiResult> send(ApiRequest request) async {
    requests.add(request);
    return _answers.isEmpty ? notFound : _answers.removeFirst();
  }
}

ApiOk piggyOk(Map<String, Object?> json) =>
    ApiOk(200, json, sentAtElapsedMs: 0, receivedAtElapsedMs: 0);

const notFound = ApiFailure(404, 'not_found');

/// B07's granted answer, with a wallet the phone doesn't apply.
ApiOk piggyGranted({int jenehat = 30, int bonat = 2}) => piggyOk({
  'status': 'granted',
  'jenehat': jenehat,
  'bonat': bonat,
  'granted_at': '2026-10-22T07:00:00Z',
  'wallet': {'jenehat': 1270, 'bonat': 87, 'fuel': 5},
});

ApiOk piggyRefused(String reason) =>
    piggyOk({'status': 'refused', 'reason': reason});
