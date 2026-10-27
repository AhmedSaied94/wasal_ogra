import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../helpers/economy.dart';

// The server's full state as the base (specs/011-m06-identity-sync,
// contracts/sync.md "Taking the full state", research R12), on a real
// database.

const _player = '0192f1c3-7d1e-7a4b-9c11-000000000001';

EconomyState _rich(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: 1000, bonat: 100);

Future<LedgerOp> _buy(TestEconomy e, String skuId) async {
  final outcome = await e.service.buy(
    e.service.newRequestId(),
    kind: SkuKind.booster,
    skuId: skuId,
  ) as OpApplied;
  return outcome.op;
}

EconomyState _snapshot() => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: testEpochMs,
).copyWith(jenehat: 4321, bonat: 500, inventory: {BoosterId.changeBag: 5});

Future<ProjectionBase> _base(TestEconomy e) async =>
    (await e.store.load()).base;

void main() {
  test(
    'after_seq is the highest answered seq; pending ops fold on top',
    () async {
      final e = await testEconomy(firstState: _rich);
      final first = await _buy(e, 'change_bag');
      final second = await _buy(e, 'wake_all');
      final third = await _buy(e, 'ledger_peek');
      await e.service.applyAnswer(
        SyncAnswer(
          stateVersion: 4,
          stateStale: false,
          results: [OpResult.accepted(first.op.txnId.value)],
          wallet: const ServerWallet(
            jenehat: 1000,
            bonat: 90,
            fuel: 5,
            fuelMax: 5,
            fuelUpdatedAtMs: testEpochMs,
          ),
        ),
        batch: [first],
        playerId: _player,
      );

      await e.service.replaceFromServer(
        _snapshot(),
        playerId: _player,
        stateVersion: 12,
      );

      final base = await _base(e);
      expect(base.afterSeq, first.seq);
      expect(base.stateVersion, 12);
      expect(base.playerId, _player);
      expect(base.kind, BaseKind.serverSnapshot);
      expect(base.state.bonat, 500);
      expect(e.service.pendingCount, 2);
      expect(
        e.service.view.bonat,
        500 + second.op.bonatDelta + third.op.bonatDelta,
      );
      expect(e.service.view.jenehat, 4321);
      expect(e.service.view.inventory, {
        BoosterId.changeBag: 5,
        BoosterId.wakeAll: 1,
        BoosterId.ledgerPeek: 1,
      });
      expect(e.service.baseInfo, (stateVersion: 12, playerId: _player));
      await e.store.checkProjection(const ProductionRules());
    },
  );

  test(
    'a base with no player adopts the operations and takes the player',
    () async {
      final e = await testEconomy(firstState: _rich);
      expect(e.service.baseInfo.playerId, isNull);
      final op = await _buy(e, 'change_bag');

      await e.service.replaceFromServer(
        _snapshot(),
        playerId: _player,
        stateVersion: 3,
      );

      final base = await _base(e);
      expect(base.afterSeq, 0);
      expect(base.playerId, _player);
      expect(e.service.pendingCount, 1, reason: 'kept, not dropped');
      expect(e.service.view.bonat, 500 + op.op.bonatDelta);
      expect(e.service.view.inventory, {BoosterId.changeBag: 6});
      await e.store.checkProjection(const ProductionRules());
    },
  );

  test(
    'an operation the state no longer allows stays pending, unfolded',
    () async {
      final e = await testEconomy(firstState: _rich);
      final op = await _buy(e, 'change_bag');

      await e.service.replaceFromServer(
        _snapshot().copyWith(bonat: 0),
        playerId: _player,
        stateVersion: 3,
      );

      expect(e.service.pendingCount, 1);
      expect(e.service.view.bonat, 0);
      expect(e.service.view.inventory, {BoosterId.changeBag: 5});
      expect(
        (await dumpTables(e.db))['ledger_ops']!.single['txn_id'],
        op.op.txnId.value,
      );
      await e.store.checkProjection(const ProductionRules());
    },
  );

  test('it survives a relaunch', () async {
    final e = await testEconomy(firstState: _rich, dbFile: tempDbFile());
    await _buy(e, 'change_bag');
    await e.service.replaceFromServer(
      _snapshot(),
      playerId: _player,
      stateVersion: 3,
    );
    final view = e.service.view;

    final again = await reopen(e);

    expect(again.service.view.bonat, view.bonat);
    expect(again.service.view.inventory, view.inventory);
    expect(again.service.baseInfo, (stateVersion: 3, playerId: _player));
  });
}
