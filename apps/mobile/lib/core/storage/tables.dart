// The app database's tables, schema version 4: the economy's
// (specs/007-m05-local-economy/data-model.md "Tables"), since v2 the trip's
// records (specs/008-m02-trip-screen/data-model.md), since v3 the account
// and the last bootstrap (specs/011-m06-identity-sync/data-model.md "Tables
// (schema v3)"), and since v4 the driver's name, the tutorial grant and the
// first session's flags (specs/012-m07-onboarding/data-model.md "App
// database v4"). Every column is INTEGER or TEXT: a guard forbids
// REAL (constitution II). Single-row tables hold `id = 1` only.
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
      // v3: M06's local gift (research R16).
      'comeback_gift',
      // v4: M07's name and tutorial gift (research R8).
      'settings_update',
      'tutorial_gift',
      // v5: M10's story operations (specs/015-m10-apartment-story, R5).
      'story_progress',
      'claim_request',
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

  /// The `txn_id` that bought it. Null since v3 for a row taken from the
  /// server's state, which doesn't send it (M06 research R12).
  TextColumn get acquiredBy => text().nullable()();

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

  /// v3: the player whose server state the base is. Null for a new
  /// player's base until the first state or the first accepted batch (M06
  /// research R7).
  TextColumn get playerId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The driver's name and the tutorial grant, as the projection holds them
/// (M07 research R8). Written only by `DriftEconomyStore`, with the wallet.
/// An absent row reads as no name and no grant.
@DataClassName('PlayerStateRow')
class PlayerStateTable extends Table {
  @override
  String get tableName => 'player_state';

  /// Always 1.
  IntColumn get id => integer().check(id.equals(1))();

  /// No length check: the server allows up to 20, and its name wins on a
  /// restore.
  TextColumn get displayName => text().nullable()();
  BoolColumn get tutorialGranted =>
      boolean().withDefault(const Constant(false))();

  /// M10: a JSON object of scene-id arrays by chapter wire name, and a JSON
  /// array of claimed request ids (specs/015-m10-apartment-story, R5).
  TextColumn get scenesSeen => text().withDefault(const Constant('{}'))();
  TextColumn get requestsClaimed => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The first session's flags (M07 research R2). Written only by
/// `DriftFirstSessionStore`. Times are trusted-clock milliseconds.
@DataClassName('FirstSessionRow')
class FirstSessionTable extends Table {
  @override
  String get tableName => 'first_session';

  /// Always 1.
  IntColumn get id => integer().check(id.equals(1))();
  IntColumn get openingDoneAtMs => integer().nullable()();

  /// A JSON array of scene ids.
  TextColumn get scenesDue => text().withDefault(const Constant('[]'))();

  /// A JSON array of scene ids.
  TextColumn get scenesSeen => text().withDefault(const Constant('[]'))();
  IntColumn get fuelLessonDoneAtMs => integer().nullable()();

  /// 0 to 8, never lowered.
  IntColumn get stepReached => integer()
      .withDefault(const Constant(0))
      .check(stepReached.isBetweenValues(0, 8))();
  IntColumn get doneAtMs => integer().nullable()();

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

/// One trip start that hasn't recorded its result yet (M02). Written only by
/// `DriftTripRecords`.
@DataClassName('TripRecordRow')
class TripRecordTable extends Table {
  @override
  String get tableName => 'trip_record';

  /// The economy's request id for the start (UUIDv7).
  TextColumn get startTxn => text()();
  TextColumn get tripId => text()();
  IntColumn get contentVersion => integer()();

  /// Canonical JSON, so a pack switch can't change the trip.
  TextColumn get definitionJson => text()();
  IntColumn get seed => integer()();
  TextColumn get paramsJson => text()();

  /// The last saved clock.
  IntColumn get tMs => integer()();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {startTxn};
}

/// A record's accepted commands, append-only, in acceptance order.
@DataClassName('TripRecordCommandRow')
class TripRecordCommandTable extends Table {
  @override
  String get tableName => 'trip_record_command';

  TextColumn get startTxn => text()();
  IntColumn get seq => integer()();

  /// The wire form, `[t_ms, "Name", …args]`.
  TextColumn get commandJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {startTxn, seq};
}

/// An economy call that follows an engine command and must survive a kill.
@DataClassName('TripIntentRow')
class TripIntentTable extends Table {
  @override
  String get tableName => 'trip_intent';

  TextColumn get requestTxn => text()();
  TextColumn get startTxn => text()();
  TextColumn get kind => text().check(kind.isIn(const ['use_booster']))();
  TextColumn get booster => text()();

  @override
  Set<Column<Object>> get primaryKey => {requestTxn};
}

/// The account (M06). Written only by `DriftAccountStore`.
@DataClassName('AccountRow')
class AccountTable extends Table {
  @override
  String get tableName => 'account';

  /// Always 1.
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get status =>
      text().check(status.isIn(const ['none', 'active', 'deleted']))();

  /// The session's player, a UUIDv7.
  TextColumn get playerId => text().nullable()();

  /// A JSON array, `[]` until a token answer says otherwise.
  TextColumn get providers => text()();
  TextColumn get displayName => text().nullable()();
  IntColumn get driverLevel => integer().nullable()();

  /// Trusted time of the first open with M06; set once.
  IntColumn get firstOpenAtMs => integer().nullable()();

  /// Trusted time a returning player's state was first taken.
  IntColumn get restoredAtMs => integer().nullable()();

  /// Trusted time of the last write.
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The last bootstrap and the comeback gift's lock (M06). Written only by
/// `DriftAccountStore`.
@DataClassName('ServerInfoRow')
class ServerInfoTable extends Table {
  @override
  String get tableName => 'server_info';

  /// Always 1.
  IntColumn get id => integer().check(id.equals(1))();

  /// Trusted time the last bootstrap arrived; null before the first.
  IntColumn get receivedAtMs => integer().nullable()();
  IntColumn get serverTimeMs => integer().nullable()();
  IntColumn get stateVersion => integer().nullable()();
  IntColumn get contentVersion => integer().nullable()();

  /// Canonical JSON of each block.
  TextColumn get client => text().nullable()();
  TextColumn get entitlements => text().nullable()();
  TextColumn get daily => text().nullable()();

  /// 0 or 1; 0 before the first bootstrap.
  IntColumn get comebackClaimable =>
      integer().check(comebackClaimable.isIn(const [0, 1]))();
  IntColumn get comebackClaimedAtMs => integer().nullable()();
  IntColumn get comebackAnsweredAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
