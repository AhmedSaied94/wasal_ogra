// The only code that writes the economy's tables (FR-013, research R11,
// R16). Every operation's row and the rows it changes commit in one
// transaction; `economy_writes_test.dart` keeps every other file out.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/storage/app_database.dart';

/// The moments inside a commit a kill must not corrupt anything (research
/// R11). Tests throw from [DriftEconomyStore.onKillPoint] at each one.
enum EconomyKillPoint {
  afterOpRow,
  afterWallet,
  afterInventory,
  afterOwnership,
  afterProgress,
  afterSession,
  afterAnchor,

  /// After the transaction committed, before the caller hears of it.
  afterCommit,
}

/// A write failed and was rolled back: a full disk or another storage
/// error. Nothing changed.
final class EconomyWriteError implements Exception {
  const EconomyWriteError(this.cause);

  final Object cause;

  @override
  String toString() => 'EconomyWriteError($cause)';
}

/// The materialized tables disagree with the fold of the base and the
/// stored operations (research R5). Checked when a debug build opens the
/// database.
final class ProjectionMismatch implements Exception {
  const ProjectionMismatch(this.detail);

  final String detail;

  @override
  String toString() => 'ProjectionMismatch($detail)';
}

/// Where the projection folds from.
enum BaseKind {
  newPlayer('new_player'),
  serverSnapshot('server_snapshot');

  const BaseKind(this.wire);

  final String wire;
}

/// The projection's starting point (data-model.md `projection_base`).
final class ProjectionBase {
  const ProjectionBase({
    required this.state,
    required this.afterSeq,
    required this.kind,
    required this.takenAtMs,
    this.stateVersion,
  });

  final EconomyState state;

  /// The last operation it already includes.
  final int afterSeq;
  final BaseKind kind;
  final int? stateVersion;
  final int takenAtMs;
}

/// What startup reads: the materialized tables, never `ledger_ops`
/// (research R18).
final class StoredEconomy {
  const StoredEconomy({
    required this.base,
    required this.state,
    required this.lastSeq,
    required this.anchor,
  });

  final ProjectionBase base;
  final EconomyState state;
  final int lastSeq;
  final ClockAnchor anchor;
}

final class DriftEconomyStore {
  DriftEconomyStore(this._db, {this.onKillPoint});

  final AppDatabase _db;
  final void Function(EconomyKillPoint point)? onKillPoint;

  Future<StoredEconomy> load() async {
    final wallet = await _db.select(_db.walletTable).getSingle();
    return StoredEconomy(
      base: await _loadBase(),
      state: await _loadState(),
      lastSeq: wallet.lastSeq,
      anchor: await loadAnchor(),
    );
  }

  Future<LedgerOp?> findOp(TxnId id) async {
    final row = await (_db.select(
      _db.ledgerOps,
    )..where((t) => t.txnId.equals(id.value))).getSingleOrNull();
    return row == null ? null : _ledgerOpOf(row);
  }

  /// Stores [op] and the rows it changes from [before] to [after], in one
  /// transaction. Throws [EconomyWriteError] when nothing could be written.
  Future<LedgerOp> commit(
    Op op, {
    required EconomyState before,
    required EconomyState after,
  }) async {
    final stored = await _write(() async {
      final seq = await _db
          .into(_db.ledgerOps)
          .insert(
            LedgerOpsCompanion.insert(
              txnId: op.txnId.value,
              opType: op.type.wire,
              payload: canonicalJson(op.payload),
              jenehatDelta: Value(op.jenehatDelta),
              bonatDelta: Value(op.bonatDelta),
              fuelDelta: Value(op.fuelDelta),
              reason: Value(op.reason?.wire),
              ref: Value(op.ref?.value),
              occurredAtMs: op.occurredAtMs,
              contentVersion: op.contentVersion,
              fuelMax: op.fuelMax,
              fuelRegenMinutes: op.fuelRegenMinutes,
              maxEarningsJenehat: Value(op.maxEarningsJenehat),
            ),
          );
      _kill(EconomyKillPoint.afterOpRow);
      await _writeWallet(after, seq);
      _kill(EconomyKillPoint.afterWallet);
      await _writeInventory(before.inventory, after.inventory);
      _kill(EconomyKillPoint.afterInventory);
      await _writeOwnership(before.ownership, after.ownership);
      _kill(EconomyKillPoint.afterOwnership);
      await _writeProgress(before.progress, after.progress);
      _kill(EconomyKillPoint.afterProgress);
      if (before.unfinished != after.unfinished ||
          before.lastResult != after.lastResult) {
        await _writeSession(after);
      }
      _kill(EconomyKillPoint.afterSession);
      await _raiseLatest(op.occurredAtMs);
      _kill(EconomyKillPoint.afterAnchor);
      return LedgerOp(seq: seq, op: op, syncStatus: SyncStatus.pending);
    });
    _kill(EconomyKillPoint.afterCommit);
    return stored;
  }

  Future<ClockAnchor> loadAnchor() async {
    final row = await _db.select(_db.clockAnchorTable).getSingle();
    return ClockAnchor(
      anchorMs: row.anchorMs,
      anchorElapsedMs: row.anchorElapsedMs,
      bootCount: row.bootCount,
      source: byWire(AnchorSource.values, (s) => s.wire, row.source)!,
      latestTrustedMs: row.latestTrustedMs,
    );
  }

  /// Replaces the anchor. `latest_trusted_ms` never goes down: the stored
  /// value is kept when it is later than [anchor]'s.
  Future<void> saveAnchor(ClockAnchor anchor) => _write(() async {
    final stored = await _db.select(_db.clockAnchorTable).getSingle();
    final latest = stored.latestTrustedMs > anchor.latestTrustedMs
        ? stored.latestTrustedMs
        : anchor.latestTrustedMs;
    await _db
        .update(_db.clockAnchorTable)
        .write(
          ClockAnchorTableCompanion(
            anchorMs: Value(anchor.anchorMs),
            anchorElapsedMs: Value(anchor.anchorElapsedMs),
            bootCount: Value(anchor.bootCount),
            source: Value(anchor.source.wire),
            latestTrustedMs: Value(latest),
          ),
        );
  });

  /// The oldest pending operations, in `seq` order (FR-045).
  Future<List<LedgerOp>> pendingOps(int limit) async {
    final rows =
        await (_db.select(_db.ledgerOps)
              ..where((t) => t.syncStatus.equals(SyncStatus.pending.wire))
              ..orderBy([(t) => OrderingTerm.asc(t.seq)])
              ..limit(limit))
            .get();
    return [for (final row in rows) _ledgerOpOf(row)];
  }

  /// Marks [ids] accepted. Returns the ids that weren't pending, which are
  /// left as they were: a status never goes back (data-model.md).
  Future<List<TxnId>> markAccepted(Iterable<TxnId> ids) => _write(() async {
    final skipped = <TxnId>[];
    for (final id in ids) {
      if (!await _setSyncStatus(id, SyncStatus.accepted, null)) {
        skipped.add(id);
      }
    }
    return skipped;
  });

  /// Marks [rejected] and, when given, replaces the base with [newBase],
  /// then folds the base and every operation still in play with [foldOps]
  /// and writes the result, all in one transaction (FR-046, FR-047).
  /// Returns the fold and the ids of [rejected] that weren't pending.
  Future<({FoldResult fold, List<TxnId> skipped})> rebuild(
    FoldResult Function(EconomyState base, List<Op> ops) foldOps, {
    Map<TxnId, String> rejected = const {},
    ProjectionBase? newBase,
  }) => _write(() async {
    final skipped = <TxnId>[];
    for (final MapEntry(key: id, value: reason) in rejected.entries) {
      if (!await _setSyncStatus(id, SyncStatus.rejected, reason)) {
        skipped.add(id);
      }
    }
    if (newBase != null) await _writeBase(newBase);
    final base = await _loadBase();
    final ops = await _foldableOps(base.afterSeq);
    final result = foldOps(base.state, ops);
    final lastSeq = await _lastSeq();
    await _writeWallet(result.state, lastSeq);
    await _db.delete(_db.inventoryTable).go();
    await _writeInventory(const {}, result.state.inventory);
    await _db.delete(_db.ownershipTable).go();
    await _writeOwnership(const {}, result.state.ownership);
    await _db.delete(_db.tripProgressTable).go();
    await _writeProgress(const {}, result.state.progress);
    await _writeSession(result.state);
    return (fold: result, skipped: skipped);
  });

  /// Throws [ProjectionMismatch] unless the materialized tables equal the
  /// fold of the base and the stored operations (invariant 1).
  Future<void> checkProjection(Rules rules) async {
    final base = await _loadBase();
    final expected = fold(
      base.state,
      await _foldableOps(base.afterSeq),
      rules,
    ).state;
    final actual = await _loadState();
    if (actual != expected) {
      throw ProjectionMismatch('tables $actual, fold $expected');
    }
  }

  // Reads.

  Future<ProjectionBase> _loadBase() async {
    final row = await _db.select(_db.projectionBaseTable).getSingle();
    return ProjectionBase(
      state: EconomyState.fromJson(jsonDecode(row.state)),
      afterSeq: row.afterSeq,
      kind: byWire(BaseKind.values, (k) => k.wire, row.kind)!,
      stateVersion: row.stateVersion,
      takenAtMs: row.takenAtMs,
    );
  }

  Future<EconomyState> _loadState() async {
    final wallet = await _db.select(_db.walletTable).getSingle();
    final inventory = await _db.select(_db.inventoryTable).get();
    final ownership = await _db.select(_db.ownershipTable).get();
    final progress = await _db.select(_db.tripProgressTable).get();
    final session = await _db.select(_db.tripSessionTable).getSingle();
    return EconomyState(
      jenehat: wallet.jenehat,
      bonat: wallet.bonat,
      fuel: FuelState(
        liters: wallet.fuel,
        countedFromMs: wallet.fuelCountedFromMs,
        unlimitedUntilMs: wallet.fuelUnlimitedUntilMs,
      ),
      inventory: {
        for (final row in inventory)
          fromWire(boosterWire, row.boosterId)!: row.count,
      },
      ownership: {
        for (final row in ownership)
          (fromWire(skuKindWire, row.kind)!, row.skuId): Owned(
            kind: fromWire(skuKindWire, row.kind)!,
            variantId: row.variantId,
            acquiredAtMs: row.acquiredAtMs,
            acquiredBy: TxnId.parse(row.acquiredBy),
          ),
      },
      progress: {
        for (final row in progress)
          row.tripId: TripProgress(
            bestStars: row.bestStars,
            bestTimeMs: row.bestTimeMs,
            plays: row.plays,
            firstCompletedAtMs: row.firstCompletedAtMs,
          ),
      },
      unfinished: _unfinishedOf(session),
      lastResult: _lastResultOf(session),
    );
  }

  UnfinishedTrip? _unfinishedOf(TripSessionRow row) {
    final start = row.unfinishedStart;
    if (start == null) return null;
    return UnfinishedTrip(
      startTxn: TxnId.parse(start),
      tripId: row.unfinishedTripId!,
      contentVersion: row.unfinishedContentVersion!,
      maxEarningsJenehat: row.unfinishedMaxEarnings!,
      startedAtMs: row.unfinishedStartedAtMs!,
      revived: row.unfinishedRevived!,
      trafficJamAds: row.unfinishedTrafficJamAds!,
    );
  }

  LastResult? _lastResultOf(TripSessionRow row) {
    final start = row.lastResultStart;
    if (start == null) return null;
    return LastResult(
      startTxn: TxnId.parse(start),
      outcome: byWire(
        TripOutcome.values,
        (o) => o.wire,
        row.lastResultOutcome,
      )!,
      earningsJenehat: row.lastResultEarnings!,
      doubled: row.lastResultDoubled!,
    );
  }

  /// The operations a fold applies: after the base, not rejected, in order.
  Future<List<Op>> _foldableOps(int afterSeq) async {
    final rows =
        await (_db.select(_db.ledgerOps)
              ..where(
                (t) =>
                    t.seq.isBiggerThanValue(afterSeq) &
                    t.syncStatus.equals(SyncStatus.rejected.wire).not(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
            .get();
    return [for (final row in rows) _opOf(row)];
  }

  Future<int> _lastSeq() async {
    final max = _db.ledgerOps.seq.max();
    final row = await (_db.selectOnly(
      _db.ledgerOps,
    )..addColumns([max])).getSingle();
    return row.read(max) ?? 0;
  }

  LedgerOp _ledgerOpOf(LedgerOpRow row) => LedgerOp(
    seq: row.seq,
    op: _opOf(row),
    syncStatus: byWire(SyncStatus.values, (s) => s.wire, row.syncStatus)!,
    syncReason: row.syncReason,
  );

  Op _opOf(LedgerOpRow row) => Op(
    txnId: TxnId.parse(row.txnId),
    type: byWire(OpType.values, (t) => t.wire, row.opType)!,
    payload: (jsonDecode(row.payload) as Map<String, Object?>)
        .cast<String, Object>(),
    jenehatDelta: row.jenehatDelta,
    bonatDelta: row.bonatDelta,
    fuelDelta: row.fuelDelta,
    reason: row.reason == null
        ? null
        : byWire(LedgerReason.values, (r) => r.wire, row.reason),
    ref: switch (row.ref) {
      final ref? => TxnId.parse(ref),
      null => null,
    },
    occurredAtMs: row.occurredAtMs,
    contentVersion: row.contentVersion,
    fuelMax: row.fuelMax,
    fuelRegenMinutes: row.fuelRegenMinutes,
    maxEarningsJenehat: row.maxEarningsJenehat,
  );

  // Writes, each inside a caller's transaction.

  /// The one place a `ledger_ops` row changes, and only its sync columns
  /// (FR-015). Returns false when the row isn't pending.
  Future<bool> _setSyncStatus(
    TxnId id,
    SyncStatus status,
    String? reason,
  ) async {
    final changed =
        await (_db.update(_db.ledgerOps)..where(
              (t) =>
                  t.txnId.equals(id.value) &
                  t.syncStatus.equals(SyncStatus.pending.wire),
            ))
            .write(
              LedgerOpsCompanion(
                syncStatus: Value(status.wire),
                syncReason: Value(reason),
              ),
            );
    return changed == 1;
  }

  Future<void> _writeWallet(EconomyState state, int lastSeq) => _db
      .update(_db.walletTable)
      .write(
        WalletTableCompanion(
          jenehat: Value(state.jenehat),
          bonat: Value(state.bonat),
          fuel: Value(state.fuel.liters),
          fuelCountedFromMs: Value(state.fuel.countedFromMs),
          fuelUnlimitedUntilMs: Value(state.fuel.unlimitedUntilMs),
          lastSeq: Value(lastSeq),
        ),
      );

  Future<void> _writeInventory(
    Map<BoosterId, int> before,
    Map<BoosterId, int> after,
  ) async {
    for (final booster in {...before.keys, ...after.keys}) {
      final count = after[booster];
      if (count == before[booster]) continue;
      final id = boosterWire[booster]!;
      if (count == null) {
        await (_db.delete(
          _db.inventoryTable,
        )..where((t) => t.boosterId.equals(id))).go();
      } else {
        await _db
            .into(_db.inventoryTable)
            .insertOnConflictUpdate(
              InventoryTableCompanion.insert(boosterId: id, count: count),
            );
      }
    }
  }

  Future<void> _writeOwnership(
    Map<OwnedKey, Owned> before,
    Map<OwnedKey, Owned> after,
  ) async {
    for (final MapEntry(key: (kind, skuId), :value) in after.entries) {
      if (before[(kind, skuId)] == value) continue;
      await _db
          .into(_db.ownershipTable)
          .insertOnConflictUpdate(
            OwnershipTableCompanion.insert(
              kind: skuKindWire[kind]!,
              skuId: skuId,
              variantId: Value(value.variantId),
              acquiredAtMs: value.acquiredAtMs,
              acquiredBy: value.acquiredBy.value,
            ),
          );
    }
  }

  Future<void> _writeProgress(
    Map<String, TripProgress> before,
    Map<String, TripProgress> after,
  ) async {
    for (final MapEntry(:key, :value) in after.entries) {
      if (before[key] == value) continue;
      await _db
          .into(_db.tripProgressTable)
          .insertOnConflictUpdate(
            TripProgressTableCompanion.insert(
              tripId: key,
              bestStars: value.bestStars,
              bestTimeMs: Value(value.bestTimeMs),
              plays: value.plays,
              firstCompletedAtMs: Value(value.firstCompletedAtMs),
            ),
          );
    }
  }

  Future<void> _writeSession(EconomyState state) {
    final unfinished = state.unfinished;
    final last = state.lastResult;
    return _db
        .update(_db.tripSessionTable)
        .write(
          TripSessionTableCompanion(
            unfinishedStart: Value(unfinished?.startTxn.value),
            unfinishedTripId: Value(unfinished?.tripId),
            unfinishedContentVersion: Value(unfinished?.contentVersion),
            unfinishedMaxEarnings: Value(unfinished?.maxEarningsJenehat),
            unfinishedStartedAtMs: Value(unfinished?.startedAtMs),
            unfinishedRevived: Value(unfinished?.revived),
            unfinishedTrafficJamAds: Value(unfinished?.trafficJamAds),
            lastResultStart: Value(last?.startTxn.value),
            lastResultOutcome: Value(last?.outcome.wire),
            lastResultEarnings: Value(last?.earningsJenehat),
            lastResultDoubled: Value(last?.doubled),
          ),
        );
  }

  Future<void> _writeBase(ProjectionBase base) => _db
      .update(_db.projectionBaseTable)
      .write(
        ProjectionBaseTableCompanion(
          state: Value(canonicalJson(base.state.toJson())),
          afterSeq: Value(base.afterSeq),
          kind: Value(base.kind.wire),
          stateVersion: Value(base.stateVersion),
          takenAtMs: Value(base.takenAtMs),
        ),
      );

  Future<void> _raiseLatest(int ms) =>
      (_db.update(_db.clockAnchorTable)
            ..where((t) => t.latestTrustedMs.isSmallerThanValue(ms)))
          .write(ClockAnchorTableCompanion(latestTrustedMs: Value(ms)));

  /// Runs [body] in one transaction. A storage error rolls it back and
  /// surfaces as [EconomyWriteError]; anything else (a test's kill) passes
  /// through as it is.
  Future<T> _write<T>(Future<T> Function() body) async {
    try {
      return await _db.transaction(body);
    } on SqliteException catch (e) {
      throw EconomyWriteError(e);
    } on DriftRemoteException catch (e) {
      throw EconomyWriteError(e.remoteCause);
    } on CouldNotRollBackException catch (e) {
      throw EconomyWriteError(e);
    }
  }

  void _kill(EconomyKillPoint point) => onKillPoint?.call(point);
}
