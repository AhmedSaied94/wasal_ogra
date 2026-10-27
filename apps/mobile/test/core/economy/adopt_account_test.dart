import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../helpers/economy.dart';

// Another player's state (specs/011-m06-identity-sync, contracts/account.md
// "Account changes", research R7), on a real database.

const _old = '0192f1c3-7d1e-7a4b-9c11-000000000001';
const _new = '0192f1c3-7d1e-7a4b-9c11-000000000002';

EconomyState _rich(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: 1000, bonat: 100);

EconomyState _theirs() => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: testEpochMs,
).copyWith(jenehat: 70, bonat: 3, inventory: {BoosterId.wakeAll: 2});

Future<LedgerOp> _buy(TestEconomy e, String skuId) async {
  final outcome = await e.service.buy(
    e.service.newRequestId(),
    kind: SkuKind.booster,
    skuId: skuId,
  ) as OpApplied;
  return outcome.op;
}

/// The old player's first purchase answered, the next two still pending.
Future<List<LedgerOp>> _played(TestEconomy e) async {
  final first = await _buy(e, 'change_bag');
  final pending = [await _buy(e, 'wake_all'), await _buy(e, 'ledger_peek')];
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
    playerId: _old,
  );
  return pending;
}

void main() {
  test('pending operations become rejected account_changed, counted', () async {
    final e = await testEconomy(firstState: _rich);
    final pending = await _played(e);

    final dropped = await e.service.adoptAccount(
      _theirs(),
      playerId: _new,
      stateVersion: 9,
    );

    expect(dropped, 2);
    expect(e.service.pendingCount, 0);
    final rows = {
      for (final row in (await dumpTables(e.db))['ledger_ops']!)
        row['txn_id']: row,
    };
    for (final op in pending) {
      final row = rows[op.op.txnId.value]!;
      expect(row['sync_status'], SyncStatus.rejected.wire);
      expect(row['sync_reason'], accountChangedReason);
    }
  });

  test('the base is the new player\'s snapshot, after the last seq', () async {
    final e = await testEconomy(firstState: _rich);
    final pending = await _played(e);

    await e.service.adoptAccount(_theirs(), playerId: _new, stateVersion: 9);

    final base = (await e.store.load()).base;
    expect(base.afterSeq, pending.last.seq);
    expect(base.playerId, _new);
    expect(base.stateVersion, 9);
    expect(base.kind, BaseKind.serverSnapshot);
    expect(base.state, _theirs());
    expect(e.service.baseInfo, (stateVersion: 9, playerId: _new));
  });

  test('the fold equals the tables, and only the new state shows', () async {
    final e = await testEconomy(firstState: _rich);
    await _played(e);

    await e.service.adoptAccount(_theirs(), playerId: _new, stateVersion: 9);

    expect(e.service.view.jenehat, 70);
    expect(e.service.view.bonat, 3);
    expect(e.service.view.inventory, {BoosterId.wakeAll: 2});
    await e.store.checkProjection(const ProductionRules());
  });

  test('nothing pending: none dropped', () async {
    final e = await testEconomy(firstState: _rich);

    expect(
      await e.service.adoptAccount(_theirs(), playerId: _new, stateVersion: 1),
      0,
    );
    expect((await e.store.load()).base.afterSeq, 0);
  });

  group('one transaction: a kill leaves the old state whole', () {
    for (final point in [
      EconomyKillPoint.afterOpRow,
      EconomyKillPoint.afterWallet,
      EconomyKillPoint.afterInventory,
      EconomyKillPoint.afterOwnership,
      EconomyKillPoint.afterProgress,
    ]) {
      test(point.name, () async {
        var armed = false;
        final e = await testEconomy(
          firstState: _rich,
          onKillPoint: (p) {
            if (armed && p == point) throw StateError('killed at $p');
          },
        );
        await _played(e);
        final before = await dumpTables(e.db);

        armed = true;
        await expectLater(
          e.service.adoptAccount(_theirs(), playerId: _new, stateVersion: 9),
          throwsStateError,
        );
        expect(await dumpTables(e.db), before);

        armed = false;
        expect(
          await e.service.adoptAccount(
            _theirs(),
            playerId: _new,
            stateVersion: 9,
          ),
          2,
        );
        await e.store.checkProjection(const ProductionRules());
      });
    }
  });
}
