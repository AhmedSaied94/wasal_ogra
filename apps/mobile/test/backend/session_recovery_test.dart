@Tags(['backend'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/network/api_client.dart';

import 'backend_shell.dart';
import 'e2e.dart';

// Scenario 3 of research R23, against the dev stack: a session the server
// ended recovers through the install id, as the same player.

const _bootstrap = ApiRequest.get(
  ApiPaths.bootstrap,
  receiveTimeout: readReceiveTimeout,
);

void main() {
  setUpAll(useRealHttp);

  test('an ended session signs in again as the same player', () async {
    final device = await e2eDevice();
    expect(await device.account.ensureSession(), isTrue);
    final player = device.account.profile!.playerId;
    expect(device.account.status, AccountStatus.active);
    expect(await device.account.authorized.send(_bootstrap), isA<ApiOk>());

    await endSessions(player);
    // Past the access token's 15 minutes on trusted time: the next call
    // renews, the ended session's refresh is refused, and the app signs in
    // again with its install id.
    device.economy.passTime(const Duration(minutes: 16));
    final before = device.sessions.session!;

    final result = await device.account.authorized.send(_bootstrap);

    expect(result, isA<ApiOk>());
    final after = device.sessions.session!;
    expect(after.playerId, player);
    expect(after.refresh, isNot(before.refresh));
    expect(device.account.profile!.playerId, player);
    expect((result as ApiOk).json['player'], containsPair('player_id', player));
  });
}
