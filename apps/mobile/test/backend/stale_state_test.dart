@Tags(['backend'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/sync_engine.dart';

import '../helpers/economy.dart';
import 'backend_shell.dart';
import 'e2e.dart';

// Scenario 2 of research R23, against the dev stack: two sessions of one
// player (two phones on the same install id). The second plays a trip and
// syncs; the first's next batch is answered `state_stale`, it takes the
// full state, and its own operations are applied once.

/// A trip on line_hay.01, start and result. Returns their ids.
Future<List<TxnId>> _trip(EconomyService economy) async {
  final start = economy.newRequestId();
  expect(
    await economy.startTrip(start, tripId: 'line_hay.01'),
    isA<OpApplied>(),
  );
  final result = economy.newRequestId();
  expect(
    await economy.recordResult(
      result,
      start: start,
      result: tripResult(
        tripId: 'line_hay.01',
        stars: 2,
        earnings: 12,
        durationMs: 60000,
      ),
    ),
    isA<OpApplied>(),
  );
  return [start, result];
}

void main() {
  setUpAll(useRealHttp);

  test('a second session makes the first stale; it converges', () async {
    final first = await e2eDevice();
    final second = await e2eDevice(installIds: first.installIds);
    expect(await first.account.ensureSession(), isTrue);
    expect(await second.account.ensureSession(), isTrue);
    final player = first.account.playerId!;
    expect(second.account.playerId, player);

    final firstEngine = e2eEngine(first);
    final events = <SyncEvent>[];
    firstEngine.events.listen(events.add);
    final mine = await _trip(first.economy.service);
    await firstEngine.syncNow();
    expect(first.economy.service.pendingCount, 0);
    final versionBefore = first.economy.service.baseInfo.stateVersion;

    // The other phone plays and syncs.
    final theirs = await _trip(second.economy.service);
    await e2eEngine(second).syncNow();
    expect(second.economy.service.pendingCount, 0);

    // The first phone's next batch.
    mine.addAll(await _trip(first.economy.service));
    await firstEngine.syncNow();
    await pumpEventQueue();

    expect(first.economy.service.pendingCount, 0);
    expect(
      events.whereType<StateTaken>().map((e) => e.why),
      contains(StateWhy.stale),
    );
    expect(
      first.economy.service.baseInfo.stateVersion,
      greaterThan(versionBefore!),
    );

    final processed = await backendShell('''
import json
from apps.economy.models import ProcessedOp
rows = ProcessedOp.objects.filter(player_id="$player")
print(json.dumps({str(r.client_txn_id): r.status for r in rows}))
''');
    final byId = (jsonDecode(processed.trim().split('\n').last) as Map)
        .cast<String, String>();
    expect(byId, {
      for (final id in [...mine, ...theirs]) id.value: 'accepted',
    });

    final state = await first.account.authorized.send(
      const ApiRequest.get(ApiPaths.state, receiveTimeout: readReceiveTimeout),
    );
    final json = (state as ApiOk).json;
    final wallet = (json['wallet']! as Map).cast<String, Object?>();
    final view = first.economy.service.view;
    expect(view.jenehat, wallet['jenehat']);
    expect(view.bonat, wallet['bonat']);
    expect(first.economy.service.state.fuel.liters, wallet['fuel']);
    // Three trips played, two here and one there.
    expect(view.progress['line_hay.01']?.plays, 3);
    expect(view.inventory, isEmpty);
  });
}
