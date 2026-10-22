// The economy's providers (contracts/economy-api.md "Providers"), built in
// this order: creating the database needs the first anchor, and the clock
// reads the stored one. This file only constructs the database and the
// store; every write goes through the store.
import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/economy/trusted_clock.dart';
import 'package:wassal/core/platform/clock.dart';
import 'package:wassal/core/platform/uptime.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

part 'economy_providers.g.dart';

@Riverpod(keepAlive: true)
UptimeSource uptimeSource(Ref ref) => const ChannelUptimeSource();

/// 1. One uptime reading, before any database.
@Riverpod(keepAlive: true)
Future<BootSnapshot?> uptimeSnapshot(Ref ref) =>
    ref.watch(uptimeSourceProvider).snapshot();

/// Opens the database's connection. Tests open one in memory.
typedef DatabaseOpener = Future<QueryExecutor> Function();

@Riverpod(keepAlive: true)
DatabaseOpener databaseOpener(Ref ref) =>
    () async => openDatabaseFile(await appDatabaseFile());

/// 2. The database, opened and migrated during startup (FR-005). A failure
/// fails startup, and the file stays as it is for the retry (FR-004).
@Riverpod(keepAlive: true)
Future<AppDatabase> appDatabase(Ref ref) async {
  final snapshot = await ref.watch(uptimeSnapshotProvider.future);
  // Read, not watched: a tunables reload must not reopen the database.
  await ref.read(tunableLayersProvider.future);
  final tunables = ref.read(configSourceProvider);
  final device = ref.watch(clockProvider);
  final db = AppDatabase(
    await ref.watch(databaseOpenerProvider)(),
    firstOpen: () {
      final anchor = firstAnchor(snapshot, device().millisecondsSinceEpoch);
      return FirstOpen(
        state: EconomyState.newPlayer(
          fuelMax: tunables.read(Tunable.fuelMax),
          nowMs: anchor.anchorMs,
        ),
        anchor: anchor,
      );
    },
    openCheck: kDebugMode
        ? (db) => DriftEconomyStore(db).checkProjection(const ProductionRules())
        : null,
  );
  try {
    await db.customSelect('SELECT 1').get();
  } on Object {
    await db.close();
    rethrow;
  }
  ref.onDispose(() => unawaited(db.close()));
  return db;
}

/// 3. The only writer of the economy's tables.
@Riverpod(keepAlive: true)
Future<DriftEconomyStore> economyStore(Ref ref) async =>
    DriftEconomyStore(await ref.watch(appDatabaseProvider.future));

/// 4. Trusted time, from the stored anchor and the same uptime reading.
@Riverpod(keepAlive: true)
Future<TrustedClock> trustedClock(Ref ref) async => UptimeTrustedClock.open(
  uptime: ref.watch(uptimeSourceProvider),
  device: ref.watch(clockProvider),
  store: await ref.watch(economyStoreProvider.future),
  snapshot: await ref.watch(uptimeSnapshotProvider.future),
);

/// 5. The economy. It joins startup, so reads after boot are synchronous.
@Riverpod(keepAlive: true)
Future<EconomyService> economy(Ref ref) async {
  final store = await ref.watch(economyStoreProvider.future);
  final clock = await ref.watch(trustedClockProvider.future);
  // Startup gates only, read rather than watched: the service reads the
  // current pack and tunables itself, so a switch at Home or a tunables
  // reload keeps this service and its queue (M04 research R7).
  await ref.read(tunableLayersProvider.future);
  await ref.read(activeContentProvider.future);
  final service = await EconomyService.open(
    store: store,
    clock: clock,
    content: () => ref.read(contentSourceProvider),
    contentVersion: () => ref.read(contentVersionProvider),
    tunables: () => ref.read(configSourceProvider),
  );
  ref
    ..listen(configSourceProvider, (_, _) => service.refresh())
    ..onDispose(service.dispose);
  return service;
}

/// 6. What screens read. Synchronous after startup; follows [Economy.views].
@Riverpod(keepAlive: true)
EconomyView economyView(Ref ref) {
  final economy = ref.watch(economyProvider).requireValue;
  final changes = economy.views.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(changes.cancel()));
  return economy.view;
}
