import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import '../../helpers/economy.dart';

// DriftEconomyStore on a real file (contracts/storage.md "The economy
// store"). The ops and states here are written by hand: the store stores
// what it is given, and the rules are tested elsewhere.

final _anchor = firstAnchor(
  const BootSnapshot(elapsedRealtimeMs: testBootElapsedMs, bootCount: 1),
  testEpochMs,
);

final _player = EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs);

final class _Opened {
  _Opened(this.db, this.store);

  final AppDatabase db;
  final DriftEconomyStore store;
}

/// The store over [file], with no open check: these states aren't folds.
Future<_Opened> _open(
  File file, {
  void Function(EconomyKillPoint point)? onKillPoint,
}) async {
  final db = AppDatabase(
    NativeDatabase(file, setup: configureConnection),
    firstOpen: () => FirstOpen(state: _player, anchor: _anchor),
  );
  addTearDown(db.close);
  await db.customSelect('SELECT 1').get();
  return _Opened(db, DriftEconomyStore(db, onKillPoint: onKillPoint));
}

Op _op(
  int n,
  OpType type, {
  Map<String, Object> payload = const {},
  int jenehatDelta = 0,
  int bonatDelta = 0,
  int fuelDelta = 0,
  LedgerReason? reason,
  TxnId? ref,
  int? maxEarningsJenehat,
}) => Op(
  txnId: txnIdOf(n),
  type: type,
  payload: payload,
  jenehatDelta: jenehatDelta,
  bonatDelta: bonatDelta,
  fuelDelta: fuelDelta,
  reason: reason,
  ref: ref,
  occurredAtMs: testEpochMs + n * 1000,
  contentVersion: 1,
  fuelMax: 5,
  fuelRegenMinutes: 20,
  maxEarningsJenehat: maxEarningsJenehat,
);

/// Every field of [op], since Op has no equality.
Map<String, Object?> _fields(Op op) => {
  'txn_id': op.txnId,
  'type': op.type,
  'payload': op.payload,
  'jenehat_delta': op.jenehatDelta,
  'bonat_delta': op.bonatDelta,
  'fuel_delta': op.fuelDelta,
  'reason': op.reason,
  'ref': op.ref,
  'occurred_at_ms': op.occurredAtMs,
  'content_version': op.contentVersion,
  'fuel_max': op.fuelMax,
  'fuel_regen_minutes': op.fuelRegenMinutes,
  'max_earnings_jenehat': op.maxEarningsJenehat,
};

final _start = _op(
  1,
  OpType.tripStart,
  payload: {
    'trip_id': 'line_hay.01',
    'content_version': 1,
    'fuel_mode': 'fuel',
  },
  fuelDelta: -1,
  maxEarningsJenehat: 20,
);

final _started = _player.copyWith(
  fuel: FuelState(liters: 4, countedFromMs: _start.occurredAtMs),
  unfinished: () => UnfinishedTrip(
    startTxn: _start.txnId,
    tripId: 'line_hay.01',
    contentVersion: 1,
    maxEarningsJenehat: 20,
    startedAtMs: _start.occurredAtMs,
  ),
);

final _result = _op(
  2,
  OpType.tripResult,
  payload: {'trip_start_txn': _start.txnId.value},
  jenehatDelta: 15,
  reason: LedgerReason.tripEarnings,
  ref: _start.txnId,
);

final _finished = _started.copyWith(
  jenehat: 15,
  progress: {
    'line_hay.01': TripProgress(
      bestStars: 3,
      bestTimeMs: 90000,
      plays: 1,
      firstCompletedAtMs: _result.occurredAtMs,
    ),
  },
  unfinished: () => null,
  lastResult: () => LastResult(
    startTxn: _start.txnId,
    outcome: TripOutcome.finished,
    earningsJenehat: 15,
  ),
);

/// A commit that changes every table a commit can change.
final _everything = _op(
  3,
  OpType.spendJenehat,
  payload: {'sku_kind': 'item', 'sku_id': 'salon.nish'},
  jenehatDelta: -5,
  reason: LedgerReason.itemPurchase,
);

final _afterEverything = _finished.copyWith(
  jenehat: 10,
  inventory: {BoosterId.changeBag: 2},
  ownership: {
    (SkuKind.item, 'salon.nish'): Owned(
      kind: SkuKind.item,
      variantId: 'classic',
      acquiredAtMs: _everything.occurredAtMs,
      acquiredBy: _everything.txnId,
    ),
  },
  progress: {
    ..._finished.progress,
    'line_hay.02': const TripProgress(bestStars: 0, plays: 1),
  },
  lastResult: () => null,
);

void main() {
  group('commit', () {
    test('writes the ledger_ops row with every column', () async {
      final o = await _open(tempDbFile());
      final stored = await o.store.commit(
        _start,
        before: _player,
        after: _started,
      );
      expect(stored.seq, 1);
      expect(stored.syncStatus, SyncStatus.pending);
      await o.store.commit(_result, before: _started, after: _finished);

      final rows = (await dumpTables(o.db))['ledger_ops']!;
      expect(rows, [
        {
          'seq': 1,
          'txn_id': _start.txnId.value,
          'op_type': 'trip_start',
          'payload': '{"content_version":1,"fuel_mode":"fuel","trip_id":"line_hay.01"}',
          'jenehat_delta': 0,
          'bonat_delta': 0,
          'fuel_delta': -1,
          'reason': null,
          'ref': null,
          'occurred_at_ms': _start.occurredAtMs,
          'content_version': 1,
          'fuel_max': 5,
          'fuel_regen_minutes': 20,
          'max_earnings_jenehat': 20,
          'sync_status': 'pending',
          'sync_reason': null,
        },
        {
          'seq': 2,
          'txn_id': _result.txnId.value,
          'op_type': 'trip_result',
          'payload': '{"trip_start_txn":"${_start.txnId.value}"}',
          'jenehat_delta': 15,
          'bonat_delta': 0,
          'fuel_delta': 0,
          'reason': 'trip_earnings',
          'ref': _start.txnId.value,
          'occurred_at_ms': _result.occurredAtMs,
          'content_version': 1,
          'fuel_max': 5,
          'fuel_regen_minutes': 20,
          'max_earnings_jenehat': null,
          'sync_status': 'pending',
          'sync_reason': null,
        },
      ]);
    });

    test('writes the wallet with last_seq, and the trip session', () async {
      final o = await _open(tempDbFile());
      await o.store.commit(_start, before: _player, after: _started);
      var dump = await dumpTables(o.db);
      expect(dump['wallet'], [
        {
          'id': 1,
          'jenehat': 0,
          'bonat': 0,
          'fuel': 4,
          'fuel_counted_from_ms': _start.occurredAtMs,
          'fuel_unlimited_until_ms': null,
          'last_seq': 1,
        },
      ]);
      expect(dump['trip_session'], [
        {
          'id': 1,
          'unfinished_start': _start.txnId.value,
          'unfinished_trip_id': 'line_hay.01',
          'unfinished_content_version': 1,
          'unfinished_max_earnings': 20,
          'unfinished_started_at_ms': _start.occurredAtMs,
          'unfinished_revived': 0,
          'unfinished_traffic_jam_ads': 0,
          'last_result_start': null,
          'last_result_outcome': null,
          'last_result_earnings': null,
          'last_result_doubled': null,
        },
      ]);

      await o.store.commit(_result, before: _started, after: _finished);
      dump = await dumpTables(o.db);
      expect(dump['wallet']!.single['jenehat'], 15);
      expect(dump['wallet']!.single['last_seq'], 2);
      expect(dump['trip_session'], [
        {
          'id': 1,
          'unfinished_start': null,
          'unfinished_trip_id': null,
          'unfinished_content_version': null,
          'unfinished_max_earnings': null,
          'unfinished_started_at_ms': null,
          'unfinished_revived': null,
          'unfinished_traffic_jam_ads': null,
          'last_result_start': _start.txnId.value,
          'last_result_outcome': 'finished',
          'last_result_earnings': 15,
          'last_result_doubled': 0,
        },
      ]);
    });

    test('upserts trip_progress and inserts ownership', () async {
      final o = await _open(tempDbFile());
      await o.store.commit(_start, before: _player, after: _started);
      await o.store.commit(_result, before: _started, after: _finished);
      expect((await dumpTables(o.db))['trip_progress'], [
        {
          'trip_id': 'line_hay.01',
          'best_stars': 3,
          'best_time_ms': 90000,
          'plays': 1,
          'first_completed_at_ms': _result.occurredAtMs,
        },
      ]);

      await o.store.commit(
        _everything,
        before: _finished,
        after: _afterEverything,
      );
      final dump = await dumpTables(o.db);
      expect(dump['trip_progress'], hasLength(2));
      expect(dump['ownership'], [
        {
          'kind': 'item',
          'sku_id': 'salon.nish',
          'variant_id': 'classic',
          'acquired_at_ms': _everything.occurredAtMs,
          'acquired_by': _everything.txnId.value,
        },
      ]);

      // A replay of the same trip updates its row.
      final again = _afterEverything.copyWith(
        progress: {
          ..._afterEverything.progress,
          'line_hay.01': TripProgress(
            bestStars: 3,
            bestTimeMs: 80000,
            plays: 2,
            firstCompletedAtMs: _result.occurredAtMs,
          ),
        },
      );
      await o.store.commit(
        _op(4, OpType.tripResult),
        before: _afterEverything,
        after: again,
      );
      final progress = (await dumpTables(o.db))['trip_progress']!;
      expect(progress, hasLength(2));
      expect(
        progress.firstWhere((row) => row['trip_id'] == 'line_hay.01'),
        containsPair('plays', 2),
      );
    });

    test('inserts, updates and deletes inventory rows', () async {
      final o = await _open(tempDbFile());
      Future<List<Map<String, Object?>>> inventory() async =>
          (await dumpTables(o.db))['inventory']!;

      final one = _player.copyWith(inventory: {BoosterId.changeBag: 1});
      await o.store.commit(
        _op(1, OpType.spendBonat),
        before: _player,
        after: one,
      );
      expect(await inventory(), [
        {'booster_id': 'change_bag', 'count': 1},
      ]);

      final two = one.copyWith(
        inventory: {BoosterId.changeBag: 2, BoosterId.wakeAll: 1},
      );
      await o.store.commit(_op(2, OpType.spendBonat), before: one, after: two);
      expect(await inventory(), [
        {'booster_id': 'change_bag', 'count': 2},
        {'booster_id': 'wake_all', 'count': 1},
      ]);

      final used = two.copyWith(
        inventory: {BoosterId.changeBag: 2, BoosterId.wakeAll: 0},
      );
      await o.store.commit(_op(3, OpType.useBooster), before: two, after: used);
      expect(await inventory(), [
        {'booster_id': 'change_bag', 'count': 2},
      ]);
    });

    test('raises latest_trusted_ms to the op time, never lowers it', () async {
      final o = await _open(tempDbFile());
      await o.store.commit(_result, before: _player, after: _player);
      expect(
        (await o.store.loadAnchor()).latestTrustedMs,
        _result.occurredAtMs,
      );
      await o.store.commit(_start, before: _player, after: _player);
      expect(
        (await o.store.loadAnchor()).latestTrustedMs,
        _result.occurredAtMs,
      );
    });
  });

  test('load() returns what was committed, without reading the log', () async {
    final file = tempDbFile();
    final o = await _open(file);
    await o.store.commit(_start, before: _player, after: _started);
    await o.store.commit(_result, before: _started, after: _finished);
    await o.store.commit(
      _everything,
      before: _finished,
      after: _afterEverything,
    );
    await o.db.close();

    final reopened = await _open(file);
    final loaded = await reopened.store.load();
    expect(loaded.state, _afterEverything);
    expect(loaded.lastSeq, 3);
    expect(loaded.base.kind, BaseKind.newPlayer);
    expect(loaded.base.afterSeq, 0);
    expect(loaded.base.state, _player);
    expect(loaded.base.stateVersion, isNull);
    expect(loaded.base.takenAtMs, testEpochMs);
    expect(loaded.anchor, _anchor.withLatest(_everything.occurredAtMs));
  });

  test('findOp() returns the stored op, or null', () async {
    final o = await _open(tempDbFile());
    await o.store.commit(_start, before: _player, after: _started);
    await o.store.commit(_result, before: _started, after: _finished);

    final found = await o.store.findOp(_result.txnId);
    expect(found?.seq, 2);
    expect(found?.syncStatus, SyncStatus.pending);
    expect(found?.syncReason, isNull);
    expect(_fields(found!.op), _fields(_result));
    expect(_fields((await o.store.findOp(_start.txnId))!.op), _fields(_start));
    expect(await o.store.findOp(txnIdOf(99)), isNull);
  });

  test(
    'saveAnchor() round-trips every column, never lowering latest',
    () async {
      final o = await _open(tempDbFile());
      const server = ClockAnchor(
        anchorMs: testEpochMs + 5000,
        anchorElapsedMs: 42,
        source: AnchorSource.server,
        latestTrustedMs: testEpochMs + 9000,
      );
      await o.store.saveAnchor(server);
      expect(await o.store.loadAnchor(), server);

      const device = ClockAnchor(
        anchorMs: testEpochMs,
        anchorElapsedMs: 7,
        bootCount: 4,
        source: AnchorSource.device,
        latestTrustedMs: testEpochMs,
      );
      await o.store.saveAnchor(device);
      expect(await o.store.loadAnchor(), device.withLatest(testEpochMs + 9000));
    },
  );

  group('kill points', () {
    final inside = EconomyKillPoint.values.where(
      (p) => p != EconomyKillPoint.afterCommit,
    );

    for (final point in inside) {
      test('a kill at ${point.name} leaves the file as before', () async {
        final file = tempDbFile();
        var armed = false;
        final o = await _open(
          file,
          onKillPoint: (p) {
            if (armed && p == point) throw _Kill(p);
          },
        );
        await o.store.commit(_start, before: _player, after: _started);
        await o.store.commit(_result, before: _started, after: _finished);
        final before = await dumpTables(o.db);
        armed = true;

        await expectLater(
          o.store.commit(
            _everything,
            before: _finished,
            after: _afterEverything,
          ),
          throwsA(isA<_Kill>()),
        );
        await o.db.close();

        final reopened = await _open(file);
        expect(await dumpTables(reopened.db), before);
        expect((await reopened.store.load()).state, _finished);
      });
    }

    test('a kill after the commit leaves the file as after', () async {
      final file = tempDbFile();
      final o = await _open(
        file,
        onKillPoint: (p) {
          if (p == EconomyKillPoint.afterCommit) throw _Kill(p);
        },
      );
      await expectLater(
        o.store.commit(_start, before: _player, after: _started),
        throwsA(isA<_Kill>()),
      );
      await o.db.close();

      final reopened = await _open(file);
      final loaded = await reopened.store.load();
      expect(loaded.state, _started);
      expect(loaded.lastSeq, 1);
      expect(await reopened.store.findOp(_start.txnId), isNotNull);
    });
  });
}

final class _Kill implements Exception {
  const _Kill(this.point);

  final EconomyKillPoint point;
}
