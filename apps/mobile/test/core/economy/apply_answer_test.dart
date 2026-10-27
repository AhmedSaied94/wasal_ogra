import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../helpers/economy.dart';

// One sync answer, in one step (specs/011-m06-identity-sync, contracts/
// sync.md "The rebase", research R11), on a real database.

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

ServerWallet _wallet({
  int jenehat = 900,
  int bonat = 77,
  int fuel = 3,
  int updatedAtMs = testEpochMs,
  int? unlimitedUntilMs,
}) => ServerWallet(
  jenehat: jenehat,
  bonat: bonat,
  fuel: fuel,
  fuelMax: 5,
  fuelUpdatedAtMs: updatedAtMs,
  fuelUnlimitedUntilMs: unlimitedUntilMs,
);

SyncAnswer _answer(
  List<LedgerOp> batch, {
  Map<LedgerOp, String> rejected = const {},
  ServerWallet? wallet,
  int stateVersion = 5,
  bool stale = false,
}) => SyncAnswer(
  stateVersion: stateVersion,
  stateStale: stale,
  results: [
    for (final op in batch)
      if (rejected[op] case final reason?)
        OpResult.rejected(op.op.txnId.value, reason)
      else
        OpResult.accepted(op.op.txnId.value),
  ],
  wallet: wallet ?? _wallet(),
);

Future<List<Map<String, Object?>>> _rows(TestEconomy e) async =>
    (await dumpTables(e.db))['ledger_ops']!;

Future<ProjectionBase> _base(TestEconomy e) async =>
    (await e.store.load()).base;

void main() {
  test(
    'all accepted: rows accepted, the base is the wallet, after S',
    () async {
      final e = await testEconomy(firstState: _rich);
      final batch = [await _buy(e, 'change_bag'), await _buy(e, 'wake_all')];
      final wallet = _wallet(
        updatedAtMs: testEpochMs - 60000,
        unlimitedUntilMs: testEpochMs + 3600000,
      );

      final applied = await e.service.applyAnswer(
        _answer(batch, wallet: wallet, stateVersion: 9),
        batch: batch,
        playerId: _player,
      );

      expect((await _rows(e)).map((r) => r['sync_status']), [
        'accepted',
        'accepted',
      ]);
      final base = await _base(e);
      expect(base.afterSeq, 2);
      expect(base.stateVersion, 9);
      expect(base.playerId, _player);
      expect(base.kind, BaseKind.serverSnapshot);
      expect(base.state.jenehat, 900);
      expect(base.state.bonat, 77);
      expect(
        base.state.fuel,
        const FuelState(
          liters: 3,
          countedFromMs: testEpochMs - 60000,
          unlimitedUntilMs: testEpochMs + 3600000,
        ),
      );
      // Inventory is the fold's: the two boosters bought.
      expect(base.state.inventory, {
        BoosterId.changeBag: 1,
        BoosterId.wakeAll: 1,
      });
      expect(e.service.view.bonat, 77);
      expect(e.service.view.jenehat, 900);
      expect(e.service.baseInfo, (stateVersion: 9, playerId: _player));
      expect(e.service.pendingCount, 0);
      expect(applied.leftOutAccepted, isEmpty);
      expect(applied.before.bonat, isNot(77));
      expect(applied.after.bonat, 77);
      await e.store.checkProjection(const ProductionRules());
    },
  );

  test('pending operations after the batch fold on top', () async {
    final e = await testEconomy(firstState: _rich);
    final batch = [await _buy(e, 'change_bag')];
    final later = await _buy(e, 'ledger_peek');

    await e.service.applyAnswer(
      _answer(batch),
      batch: batch,
      playerId: _player,
    );

    expect((await _base(e)).afterSeq, 1);
    expect(e.service.view.bonat, 77 + later.op.bonatDelta);
    expect(e.service.view.inventory, {
      BoosterId.changeBag: 1,
      BoosterId.ledgerPeek: 1,
    });
    expect(e.service.pendingCount, 1);
    await e.store.checkProjection(const ProductionRules());
  });

  test('a rejected operation and its dependents roll back', () async {
    final e = await testEconomy(firstState: _rich);
    final bought = await _buy(e, 'change_bag');
    final start = e.service.newRequestId();
    await e.service.startTrip(start, tripId: 'line_hay.01');
    final started = (await e.service.pendingOps()).last;
    final used = (await e.service.useBooster(
      e.service.newRequestId(),
      booster: BoosterId.changeBag,
    ) as OpApplied).op;
    final batch = [bought, started, used];

    await e.service.applyAnswer(
      _answer(
        batch,
        rejected: {bought: 'insufficient_funds', used: 'dependency_rejected'},
        wallet: _wallet(jenehat: 1000, bonat: 100, fuel: 4),
      ),
      batch: batch,
      playerId: _player,
    );

    final rows = await _rows(e);
    expect(rows.map((r) => (r['sync_status'], r['sync_reason'])), [
      ('rejected', 'insufficient_funds'),
      ('accepted', null),
      ('rejected', 'dependency_rejected'),
    ]);
    expect(e.service.view.inventory, isEmpty);
    expect(e.service.view.bonat, 100);
    expect(e.service.view.unfinished?.startTxn, start);
    await e.store.checkProjection(const ProductionRules());
  });

  test('state_stale: results marked, no rebase', () async {
    final e = await testEconomy(firstState: _rich);
    final batch = [await _buy(e, 'change_bag'), await _buy(e, 'wake_all')];
    final view = e.service.view;

    await e.service.applyAnswer(
      _answer(batch, rejected: {batch.last: 'insufficient_funds'}, stale: true),
      batch: batch,
      playerId: _player,
    );

    expect((await _rows(e)).map((r) => r['sync_status']), [
      'accepted',
      'rejected',
    ]);
    final base = await _base(e);
    expect(base.afterSeq, 0);
    expect(base.stateVersion, isNull);
    expect(base.playerId, isNull);
    expect(e.service.baseInfo, (stateVersion: null, playerId: null));
    // The rejection still rolls back; the wallet isn't taken.
    expect(e.service.view.bonat, view.bonat - batch.last.op.bonatDelta);
    expect(e.service.view.inventory, {BoosterId.changeBag: 1});
  });

  test('divergence: an accepted op the fold leaves out is reported', () async {
    final e = await testEconomy(firstState: _rich);
    final bought = await _buy(e, 'change_bag');
    await e.service.startTrip(e.service.newRequestId(), tripId: 'line_hay.01');
    final started = (await e.service.pendingOps()).last;
    final used = (await e.service.useBooster(
      e.service.newRequestId(),
      booster: BoosterId.changeBag,
    ) as OpApplied).op;
    final batch = [bought, started, used];

    // The server took the use, but not the purchase it needs.
    final applied = await e.service.applyAnswer(
      _answer(batch, rejected: {bought: 'insufficient_funds'}),
      batch: batch,
      playerId: _player,
    );

    expect(applied.leftOutAccepted, [used.op.txnId]);
  });

  group('a kill leaves the answer applied fully or not at all', () {
    for (final point in [
      EconomyKillPoint.afterOpRow,
      EconomyKillPoint.afterWallet,
      EconomyKillPoint.afterInventory,
      EconomyKillPoint.afterOwnership,
      EconomyKillPoint.afterProgress,
      EconomyKillPoint.afterSession,
    ]) {
      test(point.name, () async {
        var armed = false;
        final e = await testEconomy(
          firstState: _rich,
          onKillPoint: (p) {
            if (armed && p == point) throw StateError('killed at $p');
          },
        );
        final batch = [await _buy(e, 'change_bag'), await _buy(e, 'wake_all')];
        final before = await dumpTables(e.db);
        final answer = _answer(batch);

        armed = true;
        await expectLater(
          e.service.applyAnswer(answer, batch: batch, playerId: _player),
          throwsStateError,
        );
        expect(await dumpTables(e.db), before);

        armed = false;
        await e.service.applyAnswer(answer, batch: batch, playerId: _player);
        expect((await _base(e)).afterSeq, 2);
        expect(e.service.view.bonat, 77);
        await e.store.checkProjection(const ProductionRules());
      });
    }
  });

  test('the same answer again changes nothing', () async {
    final e = await testEconomy(firstState: _rich);
    final batch = [await _buy(e, 'change_bag'), await _buy(e, 'wake_all')];
    await _buy(e, 'ledger_peek');
    final answer = _answer(batch, rejected: {batch.last: 'insufficient_funds'});

    await e.service.applyAnswer(answer, batch: batch, playerId: _player);
    final once = await dumpTables(e.db);
    final view = e.service.view;

    e.passTime(minute);
    final again = await e.service.applyAnswer(
      answer,
      batch: batch,
      playerId: _player,
    );

    expect(await dumpTables(e.db), once);
    expect(e.service.view.bonat, view.bonat);
    expect(again.leftOutAccepted, isEmpty);
  });

  test('a result for an id outside the batch is ignored', () async {
    final e = await testEconomy(firstState: _rich);
    final batch = [await _buy(e, 'change_bag')];
    final other = await _buy(e, 'wake_all');
    final answer = SyncAnswer(
      stateVersion: 5,
      stateStale: false,
      results: [
        OpResult.accepted(batch.single.op.txnId.value),
        OpResult.rejected(other.op.txnId.value, 'insufficient_funds'),
      ],
      wallet: _wallet(),
    );
    await e.service.applyAnswer(answer, batch: batch, playerId: _player);
    expect((await _rows(e)).last['sync_status'], 'pending');
  });
}
