// The only writer of the trip's tables (contracts/trip-records.md). Writes
// run one after the other in the order they were asked for, each in one
// transaction; the engine never waits for them.
import 'dart:async';
import 'dart:collection';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/features/trip/domain/wire.dart';

final class DriftTripRecords implements TripRecords {
  DriftTripRecords(this._db, {this.onKillPoint});

  final AppDatabase _db;
  final void Function(TripKillPoint point)? onKillPoint;

  final _queue = Queue<_Write>();

  /// Completes when the queue runs dry; null while it is idle.
  Completer<void>? _draining;

  /// Writing the same header again (a retry) leaves one record.
  @override
  Future<bool> create(TripRecordHeader header) => _enqueue(() async {
    await _db
        .into(_db.tripRecordTable)
        .insertOnConflictUpdate(
          TripRecordTableCompanion.insert(
            startTxn: header.startTxn.value,
            tripId: header.tripId,
            contentVersion: header.contentVersion,
            definitionJson: canonicalJson(header.definition.toJson()),
            seed: header.seed,
            paramsJson: canonicalJson(header.params.toJson()),
            tMs: 0,
            createdAtMs: header.createdAtMs,
          ),
        );
  }, after: TripKillPoint.recordCreated);

  @override
  Future<bool> appendCommand(TxnId start, LoggedCommand command) =>
      _enqueue(() async {
        await _transaction(() => _append(start, command));
      }, after: TripKillPoint.commandAppended);

  @override
  Future<bool> appendBoosterUse(
    TxnId start,
    LoggedCommand command,
    TripIntent intent,
  ) => _enqueue(() async {
    await _transaction(() async {
      await _append(start, command);
      _kill(TripKillPoint.boosterCommandRow);
      await _db
          .into(_db.tripIntentTable)
          .insert(
            TripIntentTableCompanion.insert(
              requestTxn: intent.requestTxn.value,
              startTxn: intent.startTxn.value,
              kind: TripIntent.useBoosterKind,
              booster: wireOf(intent.booster),
            ),
          );
    });
  }, after: TripKillPoint.boosterUseWritten);

  @override
  Future<bool> saveClock(TxnId start, int tMs) => _enqueue(() async {
    await (_db.update(_db.tripRecordTable)
          ..where((r) => r.startTxn.equals(start.value)))
        .write(TripRecordTableCompanion(tMs: Value(tMs)));
  }, after: TripKillPoint.clockSaved);

  @override
  Future<bool> deleteIntent(TxnId request) => _enqueue(() async {
    await (_db.delete(
      _db.tripIntentTable,
    )..where((i) => i.requestTxn.equals(request.value))).go();
  });

  @override
  Future<bool> delete(TxnId start) => _enqueue(() async {
    await _transaction(() async {
      final id = start.value;
      await (_db.delete(
        _db.tripRecordCommandTable,
      )..where((c) => c.startTxn.equals(id))).go();
      await (_db.delete(
        _db.tripIntentTable,
      )..where((i) => i.startTxn.equals(id))).go();
      await (_db.delete(
        _db.tripRecordTable,
      )..where((r) => r.startTxn.equals(id))).go();
    });
  }, after: TripKillPoint.recordDeleted);

  @override
  Future<bool> deleteAllExcept(TxnId? keep) => _enqueue(() async {
    await _transaction(() async {
      final id = keep?.value;
      await (_db.delete(_db.tripRecordCommandTable)..where(
            (c) =>
                id == null ? const Constant(true) : c.startTxn.equals(id).not(),
          ))
          .go();
      await (_db.delete(_db.tripIntentTable)..where(
            (i) =>
                id == null ? const Constant(true) : i.startTxn.equals(id).not(),
          ))
          .go();
      await (_db.delete(_db.tripRecordTable)..where(
            (r) =>
                id == null ? const Constant(true) : r.startTxn.equals(id).not(),
          ))
          .go();
    });
  });

  @override
  Future<StoredTrip?> load(TxnId start) async {
    // Reads wait for the writes asked for before them.
    await _idle();
    final id = start.value;
    final record = await (_db.select(
      _db.tripRecordTable,
    )..where((r) => r.startTxn.equals(id))).getSingleOrNull();
    if (record == null) return null;
    final commands =
        await (_db.select(_db.tripRecordCommandTable)
              ..where((c) => c.startTxn.equals(id))
              ..orderBy([(c) => OrderingTerm.asc(c.seq)]))
            .get();
    final intents = await (_db.select(
      _db.tripIntentTable,
    )..where((i) => i.startTxn.equals(id))).get();
    return StoredTrip(
      startTxn: start,
      tripId: record.tripId,
      contentVersion: record.contentVersion,
      definitionJson: record.definitionJson,
      seed: record.seed,
      paramsJson: record.paramsJson,
      commandJsons: [for (final c in commands) c.commandJson],
      tMs: record.tMs,
      createdAtMs: record.createdAtMs,
      intents: [
        for (final i in intents)
          if (fromWireName(BoosterId.values, i.booster) case final booster?)
            TripIntent(
              requestTxn: TxnId.parse(i.requestTxn),
              startTxn: start,
              booster: booster,
            ),
      ],
    );
  }

  /// Appends [command] as the record's next row and moves its clock.
  Future<void> _append(TxnId start, LoggedCommand command) async {
    final id = start.value;
    final count = _db.tripRecordCommandTable.seq.count();
    final rows =
        await (_db.selectOnly(_db.tripRecordCommandTable)
              ..addColumns([count])
              ..where(_db.tripRecordCommandTable.startTxn.equals(id)))
            .getSingle();
    await _db
        .into(_db.tripRecordCommandTable)
        .insert(
          TripRecordCommandTableCompanion.insert(
            startTxn: id,
            seq: rows.read(count) ?? 0,
            commandJson: canonicalJson(command.toJson()),
          ),
        );
    await (_db.update(_db.tripRecordTable)..where((r) => r.startTxn.equals(id)))
        .write(TripRecordTableCompanion(tMs: Value(command.tMs)));
  }

  Future<void> _transaction(Future<void> Function() body) =>
      _db.transaction(body);

  Future<bool> _enqueue(Future<void> Function() run, {TripKillPoint? after}) {
    final write = _Write(run, after);
    _queue.add(write);
    unawaited(_drain());
    return write.done.future;
  }

  Future<void> _drain() async {
    if (_draining != null) return;
    final draining = _draining = Completer<void>();
    try {
      while (_queue.isNotEmpty) {
        final write = _queue.first;
        try {
          await write.run();
        } on Object catch (error, stack) {
          if (_isStorageError(error)) {
            // It stays first and runs again with the next write; nothing
            // after it may land before it.
            for (final waiting in _queue) {
              waiting.settle(false);
            }
            return;
          }
          // A kill in a test: this write is gone, as the process would be.
          _queue.removeFirst();
          write.fail(error, stack);
          continue;
        }
        _queue.removeFirst();
        try {
          if (write.after case final point?) _kill(point);
          write.settle(true);
        } on Object catch (error, stack) {
          write.fail(error, stack);
        }
      }
    } finally {
      _draining = null;
      draining.complete();
    }
  }

  Future<void> _idle() async => _draining?.future;

  void _kill(TripKillPoint point) => onKillPoint?.call(point);
}

bool _isStorageError(Object error) =>
    error is SqliteException ||
    error is DriftRemoteException ||
    error is CouldNotRollBackException;

final class _Write {
  _Write(this.run, this.after);

  final Future<void> Function() run;
  final TripKillPoint? after;
  final done = Completer<bool>();

  void settle(bool written) {
    if (!done.isCompleted) done.complete(written);
  }

  void fail(Object error, StackTrace stack) {
    if (!done.isCompleted) done.completeError(error, stack);
  }
}
