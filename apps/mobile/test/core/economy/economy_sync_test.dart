import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// The economy's sync interface (specs/011-m06-identity-sync, contracts/
// sync.md "`EconomySync`", research R20) on a real database: what the sync
// reads, the local rejection, and the serial queue it shares with the
// player's requests.

EconomyState _rich(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: 1000, bonat: 100);

Future<TxnId> _buy(TestEconomy e, String skuId) async {
  final outcome = await e.service.buy(
    e.service.newRequestId(),
    kind: SkuKind.booster,
    skuId: skuId,
  ) as OpApplied;
  return outcome.op.op.txnId;
}

/// The table each write touches, in order.
final class _WriteOrder extends QueryInterceptor {
  final tables = <String>[];

  void _record(String statement) {
    final match = RegExp(
      r'^\s*(?:INSERT(?: OR \w+)? INTO|UPDATE)\s+"?(\w+)"?',
      caseSensitive: false,
    ).firstMatch(statement);
    if (match != null) tables.add(match[1]!);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runUpdate(executor, statement, args);
  }
}

void main() {
  test('baseInfo starts with no state version and no player', () async {
    final e = await testEconomy();
    expect(e.service.baseInfo, (stateVersion: null, playerId: null));
  });

  test('pendingCount and pendingCounts follow committed ops', () async {
    final e = await testEconomy(firstState: _rich);
    final counts = <int>[];
    final subscription = e.service.pendingCounts.listen(counts.add);
    addTearDown(subscription.cancel);
    expect(e.service.pendingCount, 0);

    final first = await _buy(e, 'change_bag');
    await _buy(e, 'wake_all');
    // A repeated request stores nothing.
    await e.service.buy(first, kind: SkuKind.booster, skuId: 'change_bag');
    await pumpEventQueue();
    expect(e.service.pendingCount, 2);
    expect(counts, [1, 2]);

    await e.service.setAside({first: 'validation_error'});
    await pumpEventQueue();
    expect(e.service.pendingCount, 1);
    expect(counts, [1, 2, 1]);
  });

  test('a relaunch reads the pending count from the log', () async {
    final e = await testEconomy(dbFile: tempDbFile(), firstState: _rich);
    await _buy(e, 'change_bag');
    await _buy(e, 'wake_all');
    expect((await reopen(e)).service.pendingCount, 2);
  });

  test('pendingOps keeps seq order and its limit', () async {
    final e = await testEconomy(firstState: _rich);
    final ids = [
      for (final sku in ['change_bag', 'wake_all', 'ledger_peek'])
        await _buy(e, sku),
    ];
    expect([for (final p in await e.service.pendingOps()) p.op.txnId], ids);
    expect(
      [for (final p in await e.service.pendingOps(limit: 2)) p.seq],
      [1, 2],
    );
  });

  test('highestAnsweredSeq is 0, then follows answers', () async {
    final e = await testEconomy(firstState: _rich);
    expect(await e.service.highestAnsweredSeq(), 0);
    final first = await _buy(e, 'change_bag');
    final second = await _buy(e, 'wake_all');
    await _buy(e, 'ledger_peek');
    expect(await e.service.highestAnsweredSeq(), 0);

    await e.store.markAccepted([first]);
    expect(await e.service.highestAnsweredSeq(), 1);
    await e.service.setAside({second: 'payload_too_large'});
    expect(await e.service.highestAnsweredSeq(), 2);
  });

  test('setAside marks the op rejected with its reason and refolds', () async {
    final e = await testEconomy(firstState: _rich);
    final kept = await _buy(e, 'change_bag');
    final bad = await _buy(e, 'wake_all');
    final bonatBefore = e.service.view.bonat;
    final views = <EconomyView>[];
    final subscription = e.service.views.listen(views.add);
    addTearDown(subscription.cancel);

    await e.service.setAside({bad: 'validation_error'});
    await pumpEventQueue();

    final rows = (await dumpTables(e.db))['ledger_ops']!;
    expect(rows.map((r) => (r['sync_status'], r['sync_reason'])), [
      ('pending', null),
      ('rejected', 'validation_error'),
    ]);
    // The projection lost its effects, and only its.
    expect(e.service.view.inventory, {BoosterId.changeBag: 1});
    expect(e.service.view.bonat, greaterThan(bonatBefore));
    expect(views, hasLength(1));
    expect([for (final p in await e.service.pendingOps()) p.op.txnId], [kept]);
    await e.store.checkProjection(const ProductionRules());
  });

  test('a clock write issued during a buy waits for the buy', () async {
    final order = _WriteOrder();
    final e = await testEconomy(
      firstState: _rich,
      executor: (inner) => inner.interceptWith(order),
    );
    order.tables.clear();

    final buying = e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.booster,
      skuId: 'change_bag',
    );
    final anchoring = e.service.anchorOnServer(
      testEpochMs + 3000,
      elapsedAtResponseMs: e.uptime.elapsedRealtimeMs,
    );
    final pausing = e.service.handleLifecycle(AppLifecycleState.paused);
    await Future.wait([buying, anchoring, pausing]);

    final firstAnchor = order.tables.indexOf('clock_anchor');
    expect(firstAnchor, greaterThan(order.tables.indexOf('ledger_ops')));
    expect(order.tables.lastIndexOf('ledger_ops'), lessThan(firstAnchor));
    // The buy was stamped with the time before the new anchor.
    final op = (await e.service.pendingOps()).single.op;
    expect(op.occurredAtMs, testEpochMs);
  });
}
