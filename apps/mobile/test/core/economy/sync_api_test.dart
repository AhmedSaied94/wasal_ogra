import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// What M06 calls (contracts/economy-api.md "For M06"): the pending ops,
// marking them, and replacing the base. Since M06 (specs/011-m06-identity-
// sync, research R20) the reads and the local rejection go through
// `EconomySync` and the marks through the store, so these test both.

EconomyState _rich(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: 1000, bonat: 100);

Future<OpApplied> _buyBooster(TestEconomy e, String skuId) async =>
    await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.booster,
      skuId: skuId,
    ) as OpApplied;

Future<List<Map<String, Object?>>> _ledger(TestEconomy e) async =>
    (await dumpTables(e.db))['ledger_ops']!;

FoldResult _fold(EconomyState base, List<Op> ops) =>
    fold(base, ops, const ProductionRules());

void main() {
  test('pendingOps gives the oldest pending ops, in seq order', () async {
    final e = await testEconomy(firstState: _rich);
    final first = await _buyBooster(e, 'change_bag');
    e.passTime(minute);
    final second = await _buyBooster(e, 'wake_all');
    e.passTime(minute);
    await _buyBooster(e, 'ledger_peek');

    final pending = await e.service.pendingOps(limit: 2);
    expect([for (final p in pending) p.seq], [1, 2]);
    expect(pending.first.op.txnId, first.op.op.txnId);
    expect(pending.first.op.payload, first.op.op.payload);
    expect(pending.first.op.occurredAtMs, testEpochMs);
    expect(pending.last.op.txnId, second.op.op.txnId);
    expect(pending.last.op.occurredAtMs, testEpochMs + 60000);
    for (final p in pending) {
      expect(p.syncStatus, SyncStatus.pending);
      expect(p.syncReason, isNull);
    }

    await e.store.markAccepted([first.op.op.txnId]);
    expect(
      [for (final p in await e.service.pendingOps(limit: 2)) p.seq],
      [2, 3],
    );
  });

  test('markAccepted changes only sync_status, and not the view', () async {
    final e = await testEconomy(firstState: _rich);
    final bought = await _buyBooster(e, 'change_bag');
    final views = <EconomyView>[];
    final subscription = e.service.views.listen(views.add);
    addTearDown(subscription.cancel);
    final before = await dumpTables(e.db);
    final state = e.service.state;

    expect(await e.store.markAccepted([bought.op.op.txnId]), isEmpty);
    await pumpEventQueue();

    final after = await dumpTables(e.db);
    final row = after['ledger_ops']!.single;
    expect(row['sync_status'], 'accepted');
    expect(row['sync_reason'], isNull);
    expect(
      {...row}..remove('sync_status'),
      {...before['ledger_ops']!.single}..remove('sync_status'),
    );
    expect({...after}..remove('ledger_ops'), {...before}..remove('ledger_ops'));
    expect(e.service.state, state);
    expect(views, isEmpty);
  });

  test(
    'setAside stores the reason, rebuilds and emits the rebuilt view',
    () async {
      final e = await testEconomy(firstState: _rich);
      final bought = await _buyBooster(e, 'change_bag');
      final start = e.service.newRequestId();
      await e.service.startTrip(start, tripId: 'line_hay.01');
      final used = await e.service.useBooster(
        e.service.newRequestId(),
        booster: BoosterId.changeBag,
      );
      expect(used, isA<OpApplied>());
      final views = <EconomyView>[];
      final subscription = e.service.views.listen(views.add);
      addTearDown(subscription.cancel);

      await e.service.setAside({bought.op.op.txnId: 'insufficient_funds'});
      await pumpEventQueue();

      final row = (await _ledger(e)).first;
      expect(row['sync_status'], 'rejected');
      expect(row['sync_reason'], 'insufficient_funds');
      // Its dependent use was left out; the rest stays.
      expect(views, hasLength(1));
      expect(views.single.bonat, 100);
      expect(views.single.inventory, isEmpty);
      expect(views.single.unfinished?.startTxn, start);
      expect(views.single.fuel.liters, 4);
      // The tables are the rebuilt state, and stay so on a reopen.
      expect((await e.store.load()).state, e.service.state);
      await e.store.checkProjection(const ProductionRules());
    },
  );

  group('a status never goes back to pending', () {
    test('marking an accepted op again is skipped', () async {
      final e = await testEconomy(firstState: _rich);
      final id = (await _buyBooster(e, 'change_bag')).op.op.txnId;
      expect(await e.store.markAccepted([id]), isEmpty);

      expect(await e.store.markAccepted([id]), [id]);
      expect((await e.store.rebuild(_fold, rejected: {id: 'late'})).skipped, [
        id,
      ]);
      final row = (await _ledger(e)).single;
      expect(row['sync_status'], 'accepted');
      expect(row['sync_reason'], isNull);
      expect((await e.store.load()).state.inventory[BoosterId.changeBag], 1);
    });

    test('marking a rejected op again is skipped', () async {
      final e = await testEconomy(firstState: _rich);
      final id = (await _buyBooster(e, 'change_bag')).op.op.txnId;
      await e.service.setAside({id: 'first'});

      expect(await e.store.markAccepted([id]), [id]);
      expect((await e.store.rebuild(_fold, rejected: {id: 'second'})).skipped, [
        id,
      ]);
      final row = (await _ledger(e)).single;
      expect(row['sync_status'], 'rejected');
      expect(row['sync_reason'], 'first');
      expect(await e.service.pendingOps(), isEmpty);
    });
  });

  test('a new base folds the snapshot and the ops after it', () async {
    var e = await testEconomy(dbFile: tempDbFile(), firstState: _rich);
    await _buyBooster(e, 'change_bag');
    await _buyBooster(e, 'wake_all');
    final third = await _buyBooster(e, 'ledger_peek');
    final rejected = await _buyBooster(e, 'traffic_jam');
    await e.service.setAside({rejected.op.op.txnId: 'test'});

    // The server's state after op 2: different balances, one booster.
    final snapshot = EconomyState(
      jenehat: 500,
      bonat: 60,
      fuel: const FuelState(liters: 3, countedFromMs: testEpochMs),
      inventory: const {BoosterId.wakeAll: 4},
    );
    final rebuilt = await e.store.rebuild(
      _fold,
      newBase: ProjectionBase(
        state: snapshot,
        afterSeq: 2,
        kind: BaseKind.serverSnapshot,
        takenAtMs: e.clock.nowMs(),
        stateVersion: 7,
        playerId: '0192f1c3-7d1e-7a4b-9c11-000000000001',
      ),
    );

    final state = rebuilt.fold.state;
    expect(state.jenehat, 500);
    expect(state.bonat, 60 + third.op.op.bonatDelta);
    expect(state.inventory, {BoosterId.wakeAll: 4, BoosterId.ledgerPeek: 1});
    expect(state.fuel.liters, 3);

    final base = (await dumpTables(e.db))['projection_base']!.single;
    expect(base['kind'], 'server_snapshot');
    expect(base['after_seq'], 2);
    expect(base['state_version'], 7);
    expect(base['player_id'], '0192f1c3-7d1e-7a4b-9c11-000000000001');
    expect(base['state'], canonicalJson(snapshot.toJson()));

    e = await reopen(e);
    expect(e.service.view.bonat, 60 + third.op.op.bonatDelta);
    expect(e.service.baseInfo, (
      stateVersion: 7,
      playerId: '0192f1c3-7d1e-7a4b-9c11-000000000001',
    ));
    expect((await e.store.load()).base.kind, BaseKind.serverSnapshot);
  });

  test('anchorOnServer makes the server the source of time', () async {
    final e = await testEconomy();
    await e.service.anchorOnServer(
      testEpochMs + 5000,
      elapsedAtResponseMs: e.uptime.elapsedRealtimeMs,
    );
    expect((await e.store.loadAnchor()).source, AnchorSource.server);
    expect(e.clock.nowMs(), testEpochMs + 5000);
  });
}
