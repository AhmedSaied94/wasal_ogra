import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/network/api_client.dart';

import '../../helpers/piggy.dart';

// The piggy's lookup (specs/018-m11-ads, contracts/economy-ops.md "The
// piggy's lookup", T044) over a scripted server.

Future<PiggyLookup> _lookup(ApiResult answer, {String nonce = 'n-1'}) =>
    PiggyApi(ScriptedPiggyServer([answer])).lookup(nonce);

void main() {
  test('granted: the amounts, with the wallet ignored', () async {
    expect(
      await _lookup(piggyGranted()),
      const PiggyGranted(jenehat: 30, bonat: 2),
    );
  });

  test('refused, with each reason', () async {
    for (final reason in ['cap_reached', 'not_server_placement', 'expired']) {
      expect(await _lookup(piggyRefused(reason)), PiggyRefused(reason));
    }
  });

  test('404, 5xx, the network and a timeout are not yet', () async {
    for (final answer in <ApiResult>[
      notFound,
      const ApiFailure(500, 'server_error'),
      const ApiFailure(503, 'maintenance'),
      const ApiUnreachable(UnreachableKind.noConnection),
      const ApiUnreachable(UnreachableKind.timeout),
    ]) {
      expect(await _lookup(answer), isA<PiggyNotYet>(), reason: '$answer');
    }
  });

  test('a malformed grant is not yet', () async {
    expect(
      await _lookup(piggyOk({'status': 'granted', 'jenehat': '30'})),
      isA<PiggyNotYet>(),
    );
    expect(await _lookup(piggyOk({'status': 'pending'})), isA<PiggyNotYet>());
  });

  test('a GET on /v1/ads/rewards/<nonce>, with a short wait', () async {
    final server = ScriptedPiggyServer([notFound]);
    await PiggyApi(server).lookup('8c1f0a4e-2b7d-4c61-9a3e-5f0d2c7b9e11');
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      '/v1/ads/rewards/8c1f0a4e-2b7d-4c61-9a3e-5f0d2c7b9e11',
    );
    expect(request.receiveTimeout, piggyLookupTimeout);
  });
}
