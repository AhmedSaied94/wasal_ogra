// The app database's tables, schema version 1
// (specs/007-m05-local-economy/data-model.md "Tables"). Every column is
// INTEGER or TEXT: a guard forbids REAL (constitution II). Single-row tables
// hold `id = 1` only.
//
// drift's check DSL names a column inside its own getter; drift_dev reads
// that statically and the getter never calls itself at runtime.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

/// One row per applied operation, append-only. Only `sync_status` and
/// `sync_reason` ever change (FR-015).
@DataClassName('LedgerOpRow')
@TableIndex(name: 'ledger_ops_sync', columns: {#syncStatus, #seq})
@TableIndex(name: 'ledger_ops_ref', columns: {#ref})
class LedgerOps extends Table {
  @override
  String get tableName => 'ledger_ops';

  /// The application order.
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get txnId => text().unique()();
  TextColumn get opType => text().check(
    opType.isIn(const [
      'trip_start',
      'trip_result',
      'ad_reward',
      'spend_jenehat',
      'spend_bonat',
      'use_booster',
    ]),
  )();

  /// Canonical JSON: keys sorted, no whitespace, integers only.
  TextColumn get payload => text()();
  IntColumn get jenehatDelta => integer().withDefault(const Constant(0))();
  IntColumn get bonatDelta => integer().withDefault(const Constant(0))();
  IntColumn get fuelDelta => integer().withDefault(const Constant(0))();
  TextColumn get reason => text().nullable()();
  TextColumn get ref => text().nullable()();
  IntColumn get occurredAtMs => integer()();
  IntColumn get contentVersion =>
      integer().check(contentVersion.isBiggerOrEqualValue(1))();
  IntColumn get fuelMax => integer().check(fuelMax.isBiggerOrEqualValue(1))();
  IntColumn get fuelRegenMinutes =>
      integer().check(fuelRegenMinutes.isBiggerOrEqualValue(1))();
  IntColumn get maxEarningsJenehat =>
      integer().nullable().check(maxEarningsJenehat.isBiggerOrEqualValue(0))();
  TextColumn get syncStatus => text()
      .withDefault(const Constant('pending'))
      .check(syncStatus.isIn(const ['pending', 'accepted', 'rejected']))();
  TextColumn get syncReason => text().nullable()();
}

@DataClassName('WalletRow')
class WalletTable extends Table {
  @override
  String get tableName => 'wallet';

  IntColumn get id => integer().check(id.equals(1))();
  IntColumn get jenehat => integer().check(jenehat.isBiggerOrEqualValue(0))();
  IntColumn get bonat => integer().check(bonat.isBiggerOrEqualValue(0))();
  IntColumn get fuel => integer().check(fuel.isBiggerOrEqualValue(0))();
  IntColumn get fuelCountedFromMs => integer()();
  IntColumn get fuelUnlimitedUntilMs => integer().nullable()();

  /// The last operation folded in.
  IntColumn get lastSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('InventoryRow')
class InventoryTable extends Table {
  @override
  String get tableName => 'inventory';

  TextColumn get boosterId => text().check(
    boosterId.isIn(const [
      'change_bag',
      'wake_all',
      'ledger_peek',
      'traffic_jam',
    ]),
  )();
  IntColumn get count => integer().check(count.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {boosterId};
}

@DataClassName('OwnershipRow')
class OwnershipTable extends Table {
  @override
  String get tableName => 'ownership';

  TextColumn get kind =>
      text().check(kind.isIn(const ['item', 'vehicle', 'chapter']))();
  TextColumn get skuId => text()();
  TextColumn get variantId => text().nullable()();
  IntColumn get acquiredAtMs => integer()();

  /// The `txn_id` that bought it.
  TextColumn get acquiredBy => text()();

  @override
  Set<Column<Object>> get primaryKey => {kind, skuId};
}

@DataClassName('TripProgressRow')
class TripProgressTable extends Table {
  @override
  String get tableName => 'trip_progress';

  TextColumn get tripId => text()();
  IntColumn get bestStars => integer().check(bestStars.isBetweenValues(0, 3))();
  IntColumn get bestTimeMs => integer().nullable()();
  IntColumn get plays => integer().check(plays.isBiggerOrEqualValue(0))();
  IntColumn get firstCompletedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {tripId};
}

/// The unfinished trip and the latest result. Every `unfinished_` column is
/// null when no trip is unfinished, and every `last_result_` one before the
/// first result.
@DataClassName('TripSessionRow')
class TripSessionTable extends Table {
  @override
  String get tableName => 'trip_session';

  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get unfinishedStart => text().nullable()();
  TextColumn get unfinishedTripId => text().nullable()();
  IntColumn get unfinishedContentVersion => integer().nullable()();
  IntColumn get unfinishedMaxEarnings => integer().nullable()();
  IntColumn get unfinishedStartedAtMs => integer().nullable()();
  BoolColumn get unfinishedRevived => boolean().nullable()();
  IntColumn get unfinishedTrafficJamAds => integer().nullable()();
  TextColumn get lastResultStart => text().nullable()();
  TextColumn get lastResultOutcome => text().nullable()();
  IntColumn get lastResultEarnings => integer().nullable()();
  BoolColumn get lastResultDoubled => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What the projection folds from: the new player's state, or (M06) the
/// server's snapshot.
@DataClassName('ProjectionBaseRow')
class ProjectionBaseTable extends Table {
  @override
  String get tableName => 'projection_base';

  IntColumn get id => integer().check(id.equals(1))();

  /// The base `EconomyState` as canonical JSON.
  TextColumn get state => text()();

  /// The last operation the base already includes.
  IntColumn get afterSeq => integer()();
  TextColumn get kind =>
      text().check(kind.isIn(const ['new_player', 'server_snapshot']))();

  /// The server's `state_version`, from M06.
  IntColumn get stateVersion => integer().nullable()();
  IntColumn get takenAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The trusted-time anchor (research R9).
@DataClassName('ClockAnchorRow')
class ClockAnchorTable extends Table {
  @override
  String get tableName => 'clock_anchor';

  IntColumn get id => integer().check(id.equals(1))();
  IntColumn get anchorMs => integer()();
  IntColumn get anchorElapsedMs => integer()();
  IntColumn get bootCount => integer().nullable()();
  TextColumn get source =>
      text().check(source.isIn(const ['device', 'server']))();

  /// Never decreases.
  IntColumn get latestTrustedMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
