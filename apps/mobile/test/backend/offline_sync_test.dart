@Tags(['backend'])
library;

import 'dart:convert';
import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/network/api_client.dart';

import '../helpers/economy.dart';
import 'backend_shell.dart';
import 'e2e.dart';

// Scenario 1 of research R23 (SC-004), against the dev stack: a player
// online once (and given BONAT by staff), then 50 operations recorded
// offline, trips and booster purchases of the sample pack, synced with the
// connection cut at seeded points. Every id is accepted once, and the
// phone's balances equal the server's.

/// Cuts the connection at seeded points while [active]: before the request
/// leaves the phone, or after the server answered.
final class _Cutting implements ApiClient {
  _Cutting(this._inner, this._random);

  final ApiClient _inner;
  final Random _random;
  bool active = false;
  int cuts = 0;

  @override
  Future<ApiResult> send(ApiRequest request) async {
    if (!active) return _inner.send(request);
    // The first request is always cut, on a seeded side.
    switch (cuts == 0 ? _random.nextInt(2) : _random.nextInt(4)) {
      case 0:
        cuts++;
        return const ApiUnreachable(UnreachableKind.noConnection);
      case 1:
        cuts++;
        await _inner.send(request);
        return const ApiUnreachable(UnreachableKind.timeout);
      default:
        return _inner.send(request);
    }
  }
}

/// 50 operations the server accepts from a new player with 30 BONAT: 20
/// trips on four tanks (three `fuel_refill` ads, B03's daily cap), four
/// results doubled, and three boosters bought.
Future<List<TxnId>> _playOffline(EconomyService economy) async {
  final ids = <TxnId>[];
  Future<void> record(
    Future<OpOutcome> Function(TxnId id) request, {
    TxnId? id,
  }) async {
    final txn = id ?? economy.newRequestId();
    final outcome = await request(txn);
    expect(outcome, isA<OpApplied>(), reason: 'op ${ids.length + 1}');
    ids.add(txn);
  }

  const boosters = ['change_bag', 'wake_all', 'ledger_peek'];
  for (var tank = 0; tank < 4; tank++) {
    if (tank > 0) {
      await record(
        (id) => economy.applyAdReward(id, placement: AdPlacement.fuelRefill),
      );
      await record(
        (id) =>
            economy.buy(id, kind: SkuKind.booster, skuId: boosters[tank - 1]),
      );
    }
    for (var trip = 0; trip < 5; trip++) {
      final start = economy.newRequestId();
      await record(
        (id) => economy.startTrip(id, tripId: 'line_hay.01'),
        id: start,
      );
      await record(
        (id) => economy.recordResult(
          id,
          start: start,
          result: tripResult(
            tripId: 'line_hay.01',
            stars: 2,
            earnings: 20,
            durationMs: 60000,
          ),
        ),
      );
      if (tank < 2 && trip.isOdd) {
        await record(
          (id) =>
              economy.applyAdReward(id, placement: AdPlacement.resultDouble),
        );
      }
    }
  }
  return ids;
}

void main() {
  setUpAll(useRealHttp);

  for (final seed in [1, 2, 3]) {
    test('seed $seed: each id accepted once, balances equal', () async {
      late _Cutting cutting;
      final device = await e2eDevice(
        wrap: (api) => cutting = _Cutting(api, Random(seed)),
      );
      final economy = device.economy.service;
      // Ahead of any base: the first pass takes the full state.
      int? serverVersion = 1 << 30;
      final engine = e2eEngine(
        device,
        serverStateVersion: () => serverVersion,
        seed: seed,
      );

      // Online once: the account, staff's BONAT, and the state with it.
      expect(await device.account.ensureSession(), isTrue);
      final player = device.account.playerId!;
      await grantBonat(player, 30);
      await engine.syncNow();
      serverVersion = null;
      expect(economy.view.bonat, 30);

      final ids = await _playOffline(economy);
      expect(ids, hasLength(50));

      cutting.active = true;
      for (var pass = 0; pass < 40 && economy.pendingCount > 0; pass++) {
        await engine.syncNow();
      }
      cutting.active = false;
      expect(economy.pendingCount, 0, reason: '${engine.snapshot.lastError}');
      expect(cutting.cuts, greaterThan(0));

      final processed = await backendShell('''
import json
from apps.economy.models import ProcessedOp
rows = ProcessedOp.objects.filter(player_id="$player")
print(json.dumps({str(r.client_txn_id): [r.status, r.reason] for r in rows}))
''');
      final byId = (jsonDecode(processed.trim().split('\n').last) as Map)
          .cast<String, List<Object?>>();
      expect(byId.keys.toSet(), {for (final id in ids) id.value});
      expect({
        for (final MapEntry(:key, :value) in byId.entries)
          if (value.first != 'accepted') key: value,
      }, isEmpty);

      final state = await device.account.authorized.send(
        const ApiRequest.get(
          ApiPaths.state,
          receiveTimeout: readReceiveTimeout,
        ),
      );
      final wallet = ((state as ApiOk).json['wallet']! as Map)
          .cast<String, Object?>();
      expect(economy.view.jenehat, wallet['jenehat']);
      expect(economy.view.bonat, wallet['bonat']);
      expect(economy.state.fuel.liters, wallet['fuel']);
      expect(economy.view.inventory, {
        BoosterId.changeBag: 1,
        BoosterId.wakeAll: 1,
        BoosterId.ledgerPeek: 1,
      });
    });
  }
}
