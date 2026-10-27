// The app database (contracts/storage.md). It owns the schema and its
// migrations; each feature's data access lives with the feature, and for the
// economy that is `DriftEconomyStore`, the only writer of its tables.
import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/storage/app_database.steps.dart';
import 'package:wassal/core/storage/tables.dart';

part 'app_database.g.dart';

/// What a new install's first rows hold: the new player and the first
/// anchor (data-model.md "First open"). A new player has balances and fuel
/// only, which is all the first rows write.
final class FirstOpen {
  FirstOpen({required this.state, required this.anchor})
    : assert(
        state.inventory.isEmpty &&
            state.ownership.isEmpty &&
            state.progress.isEmpty &&
            state.unfinished == null &&
            state.lastResult == null,
        'A new player owns nothing and has played nothing.',
      );

  final EconomyState state;
  final ClockAnchor anchor;
}

/// The file was written by a newer version of the app. Opening it is refused
/// before any statement changes it (FR-004).
final class DatabaseFromNewerApp implements Exception {
  const DatabaseFromNewerApp(this.fileVersion, this.appVersion);

  final int fileVersion;
  final int appVersion;

  @override
  String toString() =>
      'DatabaseFromNewerApp(file v$fileVersion, app v$appVersion)';
}

/// A check run when the database opens, before anything reads it.
typedef OpenCheck = Future<void> Function(AppDatabase db);

/// One schema upgrade, to the version it is keyed by.
typedef UpgradeStep = Future<void> Function(Migrator m);

@DriftDatabase(
  tables: [
    LedgerOps,
    WalletTable,
    InventoryTable,
    OwnershipTable,
    TripProgressTable,
    TripSessionTable,
    ProjectionBaseTable,
    ClockAnchorTable,
    TripRecordTable,
    TripRecordCommandTable,
    TripIntentTable,
    AccountTable,
    ServerInfoTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [firstOpen] is read only when the file is new. Without it a new file
  /// gets the tables and no rows, as drift's schema tests need. [openCheck]
  /// runs after any migration (the debug fold check, research R5).
  AppDatabase(super.e, {this.firstOpen, this.openCheck});

  final FirstOpen Function()? firstOpen;
  final OpenCheck? openCheck;

  @override
  int get schemaVersion => 3;

  /// The step to each version after 1. A later schema adds its entry here,
  /// calling the step `make-migrations` generates for it.
  @protected
  Map<int, UpgradeStep> get upgradeSteps => const {2: _toV2, 3: _toV3};

  /// v2 adds the trip's records (specs/008-m02-trip-screen,
  /// contracts/trip-records.md "Schema"), as v2 defines them.
  static Future<void> _toV2(Migrator m) async {
    final schema = Schema2(database: m.database);
    final v2 = Migrator(m.database, schema);
    await v2.createTable(schema.tripRecord);
    await v2.createTable(schema.tripRecordCommand);
    await v2.createTable(schema.tripIntent);
  }

  /// v3 adds the account and the last bootstrap, and the economy's player
  /// (specs/011-m06-identity-sync, data-model.md "Tables (schema v3)"), as
  /// v3 defines them. Two tables are rebuilt with every row kept, since
  /// SQLite can't change a column's constraint in place: `ownership`, whose
  /// `acquired_by` becomes nullable, and `ledger_ops`, whose `op_type` check
  /// gains `comeback_gift`. Their indexes are re-created with them.
  static Future<void> _toV3(Migrator m) async {
    final schema = Schema3(database: m.database);
    final v3 = Migrator(m.database, schema);
    await v3.createTable(schema.account);
    await v3.createTable(schema.serverInfo);
    await v3.addColumn(schema.projectionBase, schema.projectionBase.playerId);
    await v3.alterTable(TableMigration(schema.ownership));
    await v3.alterTable(TableMigration(schema.ledgerOps));
    // The account before any sign-in, written at the latest trusted time.
    await m.database.customStatement(
      'INSERT INTO account (id, status, providers, updated_at_ms) '
      "SELECT 1, 'none', '[]', COALESCE(MAX(latest_trusted_ms), 0) "
      'FROM clock_anchor',
    );
    await m.database.customStatement(
      'INSERT INTO server_info (id, comeback_claimable) VALUES (1, 0)',
    );
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      final first = firstOpen?.call();
      if (first != null) await _insertFirstRows(first);
      await _insertAccountRows(first?.anchor.anchorMs ?? 0);
      // With the tables, so a kill can't leave tables at version 0.
      await customStatement('PRAGMA user_version = $schemaVersion');
    }),
    onUpgrade: (m, from, to) async {
      if (from > to) throw DatabaseFromNewerApp(from, to);
      for (var version = from + 1; version <= to; version++) {
        final step =
            upgradeSteps[version] ??
            (throw StateError('No upgrade step to schema v$version.'));
        // Each step commits with its version, so a failure or a kill leaves
        // the previous version whole (FR-003).
        await transaction(() async {
          await step(m);
          await customStatement('PRAGMA user_version = $version');
        });
      }
    },
    beforeOpen: (details) async {
      await openCheck?.call(this);
    },
  );

  /// The account before any sign-in, and no bootstrap yet. Inserted with
  /// every new file, and by the v3 upgrade.
  Future<void> _insertAccountRows(int nowMs) async {
    await into(accountTable).insert(
      AccountTableCompanion.insert(
        id: const Value(1),
        status: 'none',
        providers: '[]',
        updatedAtMs: nowMs,
      ),
    );
    await into(serverInfoTable).insert(
      ServerInfoTableCompanion.insert(id: const Value(1), comebackClaimable: 0),
    );
  }

  Future<void> _insertFirstRows(FirstOpen first) async {
    final FirstOpen(:state, :anchor) = first;
    await into(walletTable).insert(
      WalletTableCompanion.insert(
        id: const Value(1),
        jenehat: state.jenehat,
        bonat: state.bonat,
        fuel: state.fuel.liters,
        fuelCountedFromMs: state.fuel.countedFromMs,
        fuelUnlimitedUntilMs: Value(state.fuel.unlimitedUntilMs),
        lastSeq: 0,
      ),
    );
    await into(tripSessionTable)
        .insert(const TripSessionTableCompanion(id: Value(1)));
    await into(projectionBaseTable).insert(
      ProjectionBaseTableCompanion.insert(
        id: const Value(1),
        state: canonicalJson(state.toJson()),
        afterSeq: 0,
        kind: 'new_player',
        takenAtMs: anchor.anchorMs,
      ),
    );
    await into(clockAnchorTable).insert(
      ClockAnchorTableCompanion.insert(
        id: const Value(1),
        anchorMs: anchor.anchorMs,
        anchorElapsedMs: anchor.anchorElapsedMs,
        bootCount: Value(anchor.bootCount),
        source: anchor.source.wire,
        latestTrustedMs: anchor.latestTrustedMs,
      ),
    );
  }
}
